;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_COVERAGE (err u102))
(define-constant BLOCKS_PER_MONTH u4320) ;; ~30 days worth of blocks
(define-constant ERR_POLICY_EXPIRED (err u103))

;; Data vars
(define-data-var min-coverage-amount uint u1000000) ;; in micro STX
(define-data-var premium-rate uint u5) ;; 0.5% represented as 5/1000

;; Data maps
(define-map insurance-policies
    principal
    {
        coverage-amount: uint,
        premium-paid: uint,
        active: bool,
        start-height: uint,
        expiry-height: uint
    }
)

(define-map claims
    principal
    {
        claim-amount: uint,
        block-height: uint,
        status: (string-ascii 20)
    }
)

;; Public functions
(define-public (purchase-coverage (coverage-amount uint) (duration uint))
    (let
        (
            (premium-to-pay (calculate-premium coverage-amount))
            (expiry-blocks (* duration BLOCKS_PER_MONTH))
        )
        (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (>= coverage-amount (var-get min-coverage-amount)) ERR_INVALID_COVERAGE)
        (try! (stx-transfer? premium-to-pay tx-sender (as-contract tx-sender)))
        
        (map-set insurance-policies tx-sender
            {
                coverage-amount: coverage-amount,
                premium-paid: premium-to-pay,
                active: true,
                start-height: stacks-block-height,
                expiry-height: (+ stacks-block-height expiry-blocks)
            }
        )
        (ok true)
    )
)

(define-public (file-claim (amount uint))
    (let
        (
            (policy (unwrap! (map-get? insurance-policies tx-sender) ERR_NOT_AUTHORIZED))
        )
        (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (get active policy) ERR_NOT_AUTHORIZED)
        (asserts! (<= amount (get coverage-amount policy)) ERR_INVALID_COVERAGE)
        
        (map-set claims tx-sender
            {
                claim-amount: amount,
                block-height: stacks-block-height,
                status: "PENDING"
            }
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-policy (user principal))
    (map-get? insurance-policies user)
)

(define-read-only (get-claim (user principal))
    (map-get? claims user)
)

(define-read-only (calculate-premium (coverage-amount uint))
    (/ (* coverage-amount (var-get premium-rate)) u1000)
)

(define-read-only (is-policy-valid (user principal))
    (let (
        (policy (unwrap! (map-get? insurance-policies user) false))
    )
    (and 
        (get active policy)
        (< stacks-block-height (get expiry-height policy))
    ))
)

;; Admin functions
(define-public (approve-claim (user principal))
    (begin
    (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (let
            (
                (claim (unwrap! (map-get? claims user) ERR_NOT_AUTHORIZED))
                (policy (unwrap! (map-get? insurance-policies user) ERR_NOT_AUTHORIZED))
            )
            (try! (as-contract (stx-transfer? (get claim-amount claim) (as-contract tx-sender) user)))
            (map-set insurance-policies user
                (merge policy { active: false })
            )
            (map-set claims user
                (merge claim { status: "APPROVED" })
            )
            (ok true)
        )
    )
)



(define-public (reject-claim (user principal))
    (begin
    (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (let
            (
                (claim (unwrap! (map-get? claims user) ERR_NOT_AUTHORIZED))
                (policy (unwrap! (map-get? insurance-policies user) ERR_NOT_AUTHORIZED))
            )
            (map-set insurance-policies user
                (merge policy { active: false })
            )
            (map-set claims user
                (merge claim { status: "REJECTED" })
            )
            (ok true)
        )
    )
)
(define-public (cancel-policy (user principal))
    (begin
    (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (let
            (
                (policy (unwrap! (map-get? insurance-policies user) ERR_NOT_AUTHORIZED))
            )
            (map-set insurance-policies user
                (merge policy { active: false })
            )
            (ok true)
        )
    )
)
(define-public (set-min-coverage-amount (amount uint))
    (begin
    (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set min-coverage-amount amount)
        (ok true)
    )
)
(define-public (set-premium-rate (rate uint))
    (begin
    (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set premium-rate rate)
        (ok true)
    )
)
(define-public (get-min-coverage-amount)

    (ok (var-get min-coverage-amount))
)
(define-public (get-premium-rate)
    (ok (var-get premium-rate))
)
(define-public (get-coverage-amount (user principal))
    (let
        (
            (policy (unwrap! (map-get? insurance-policies user) ERR_NOT_AUTHORIZED))
        )
        (ok (get coverage-amount policy))
    )
)


;; Add new map for referral tracking
(define-map referrals
    principal ;; referrer
    {
        total-refs: uint,
        total-rewards: uint
    }
)

(define-data-var referral-reward-rate uint u10) ;; 1% of premium

(define-public (purchase-coverage-with-referral (coverage-amount uint) (referrer principal))
    (let
        (
            (premium-to-pay (calculate-premium coverage-amount))
            (referral-reward (/ (* premium-to-pay (var-get referral-reward-rate)) u1000))
        )
        (asserts! (not (var-get contract-paused)) (err u104))
        (var-set total-policies-issued (+ (var-get total-policies-issued) u1))
        (var-set total-premiums-collected (+ (var-get total-premiums-collected) premium-to-pay))
        (try! (stx-transfer? premium-to-pay tx-sender (as-contract tx-sender)))
        (try! (as-contract (stx-transfer? referral-reward (as-contract tx-sender) referrer)))
        
        ;; Update referral stats
        (map-set referrals referrer
            (merge (default-to
                    {total-refs: u0, total-rewards: u0}
                    (map-get? referrals referrer))
                {
                    total-refs: (+ u1),
                    total-rewards: (+ referral-reward)
                }
            ))
        (ok true)
    )
)


;; Add new data var for contract pause state
(define-data-var contract-paused bool false)

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (ok (var-set contract-paused (not (var-get contract-paused))))
    )
)


;; Add new maps and vars for staking
(define-map stakers
    principal
    {
        amount: uint,
        rewards: uint,
        last-claim: uint
    }
)

(define-data-var staking-rate uint u5) ;; 0.5% per month
(define-data-var total-staked uint u0)

(define-public (stake-tokens (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set stakers tx-sender
            (merge (default-to
                    {amount: u0, rewards: u0, last-claim: stacks-block-height}
                    (map-get? stakers tx-sender))
                {
                    amount: (+ amount),
                    last-claim: stacks-block-height
                }
            ))
        (var-set total-staked (+ (var-get total-staked) amount))
        (ok true)
    )
)



;; Add new data vars for analytics
(define-data-var total-policies-issued uint u0)
(define-data-var total-claims-filed uint u0)
(define-data-var total-premiums-collected uint u0)
(define-data-var total-claims-paid uint u0)

(define-read-only (get-pool-stats)
    {
        policies: (var-get total-policies-issued),
        claims: (var-get total-claims-filed),
        premiums: (var-get total-premiums-collected),
        payouts: (var-get total-claims-paid)
    }
)

(define-public (claim-staking-rewards)
    (let
        (
            (staker (unwrap! (map-get? stakers tx-sender) ERR_NOT_AUTHORIZED))
            (current-block stacks-block-height)
            (last-claim (get last-claim staker))
            (months-since-last-claim (/ (- current-block last-claim) BLOCKS_PER_MONTH))
            (rewards (* months-since-last-claim (/ (* (get amount staker) (var-get staking-rate)) u100)))
        )
        (asserts! (> months-since-last-claim u0) ERR_NOT_AUTHORIZED)
        (map-set stakers tx-sender
            (merge staker
                {
                    rewards: (+ rewards),
                    last-claim: current-block
                }
            )
        )
        (ok true)
    )
)

(define-public (withdraw-staking-rewards)
    (let
        (
            (staker (unwrap! (map-get? stakers tx-sender) ERR_NOT_AUTHORIZED))
            (rewards (get rewards staker))
        )
        (asserts! (> rewards u0) ERR_NOT_AUTHORIZED)
        (try! (as-contract (stx-transfer? rewards tx-sender (as-contract tx-sender))))
        (map-set stakers tx-sender
            (merge staker
                {
                    rewards: u0
                }
            )
        )
        (ok true)
    )
)


;; Add new map for tier definitions
(define-map coverage-tiers
    uint ;; tier ID
    {
        min-amount: uint,
        max-amount: uint,
        premium-rate: uint
    }
)

;; Initialize with default tiers
(define-data-var next-tier-id uint u1)

;; Function to add a new coverage tier
(define-public (add-coverage-tier (min-amount uint) (max-amount uint) (premium-ratee uint))
    (begin
        (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (< min-amount max-amount) (err u105))
        
        (let ((tier-id (var-get next-tier-id)))
            (map-set coverage-tiers tier-id
                {
                    min-amount: min-amount,
                    max-amount: max-amount,
                    premium-rate: premium-ratee
                }
            )
            (var-set next-tier-id (+ tier-id u1))
            (ok tier-id)
        )
    )
)

;; Function to remove a coverage tier
(define-public (remove-coverage-tier (tier-id uint))
    (begin
        (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (map-delete coverage-tiers tier-id) (err u106))
        (ok true)
    )
)

;; Updated premium calculation function that uses tiers
(define-read-only (calculate-premium-tiered (coverage-amount uint))
    (let ((tier-rate (find-applicable-tier-rate coverage-amount)))
        (/ (* coverage-amount tier-rate) u1000)
    )
)

;; Helper function to find the applicable tier rate
(define-read-only (find-applicable-tier-rate (coverage-amount uint))
    (let 
        (
            (default-rate (var-get premium-rate))
            (tier-1 (unwrap-panic (map-get? coverage-tiers u1)))
        )
        (if (and 
                (>= coverage-amount (get min-amount tier-1))
                (<= coverage-amount (get max-amount tier-1))
            )
            (get premium-rate tier-1)
            default-rate
        )
    )
)

;; Helper function to check tier applicability
(define-private (check-tier-amount
    (tier {min-amount: uint, max-amount: uint, premium-rate: uint})
    (amount uint))
    
    (if (and 
            (>= amount (get min-amount tier))
            (<= amount (get max-amount tier))
        )
        (some (get premium-rate tier))
        none
    )
)

;; Updated purchase-coverage function to use tiered pricing
(define-public (purchase-coverage-tiered (coverage-amount uint) (duration uint))
    (let
        (
            (premium-to-pay (calculate-premium-tiered coverage-amount))
            (expiry-blocks (* duration BLOCKS_PER_MONTH))
        )
        (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (>= coverage-amount (var-get min-coverage-amount)) ERR_INVALID_COVERAGE)
        (try! (stx-transfer? premium-to-pay tx-sender (as-contract tx-sender)))
        
        (map-set insurance-policies tx-sender
            {
                coverage-amount: coverage-amount,
                premium-paid: premium-to-pay,
                active: true,
                start-height: stacks-block-height,
                expiry-height: (+ stacks-block-height expiry-blocks)
            }
        )
        (var-set total-policies-issued (+ (var-get total-policies-issued) u1))
        (var-set total-premiums-collected (+ (var-get total-premiums-collected) premium-to-pay))
        (ok true)
    )
)

;; ;; Function to get all tiers
;; (define-read-only (get-all-tiers)
;;     (map-to-list coverage-tiers)
;; )

;; Function to get a specific tier
(define-read-only (get-tier (tier-id uint))
    (map-get? coverage-tiers tier-id)
)


;; Add new data var for renewal discount
(define-data-var renewal-discount-rate uint u10) ;; 1% discount represented as 10/1000

;; Add renewal count to policy data
(define-map insurance-policiess
    principal
    {
        coverage-amount: uint,
        premium-paid: uint,
        active: bool,
        start-height: uint,
        expiry-height: uint,
        renewal-count: uint
    }
)

;; Function to set renewal discount rate
(define-public (set-renewal-discount-rate (rate uint))
    (begin
        (asserts! (not (var-get contract-paused)) (err u104))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set renewal-discount-rate rate)
        (ok true)
    )
)

;; Function to calculate renewal premium with discount
(define-read-only (calculate-renewal-premium (coverage-amount uint) (renewal-count uint))
    (let 
        (
            (base-premium (calculate-premium coverage-amount))
            (capped-renewals (if (>= renewal-count u5) u5 renewal-count))
            (discount-multiplier (- u1000 (* (var-get renewal-discount-rate) capped-renewals)))
        )
        (/ (* base-premium discount-multiplier) u1000)
    )
)

;; Function to renew an existing policy
(define-public (renew-policy (duration uint))
    (let
        (
            (policy (unwrap! (map-get? insurance-policiess tx-sender) ERR_NOT_AUTHORIZED))
            (coverage-amount (get coverage-amount policy))
            (renewal-count (get renewal-count policy))
            (premium-to-pay (calculate-renewal-premium coverage-amount renewal-count))
            (expiry-blocks (* duration BLOCKS_PER_MONTH))
        )
        (asserts! (not (var-get contract-paused)) (err u104))
        
        ;; Check if policy is active or recently expired (within 30 days)
        (asserts! (or 
            (get active policy)
            (< (- stacks-block-height (get expiry-height policy)) BLOCKS_PER_MONTH)
        ) (err u107))
        
        (try! (stx-transfer? premium-to-pay tx-sender (as-contract tx-sender)))
        
        (map-set insurance-policiess tx-sender
            {
                coverage-amount: coverage-amount,
                premium-paid: premium-to-pay,
                active: true,
                start-height: stacks-block-height,
                expiry-height: (+ stacks-block-height expiry-blocks),
                renewal-count: (+ renewal-count u1)
            }
        )
        (var-set total-premiums-collected (+ (var-get total-premiums-collected) premium-to-pay))
        (ok true)
    )
)

;; Function to get renewal discount for a user
;; (define-read-only (get-renewal-discount (user principal))
;;     (let
;;         (
;;             (policy (unwrap! (map-get? insurance-policiess user) (err u108)))
;;             (renewal-count (get renewal-count policy))
;;             (capped-renewals (if (>= renewal-count u5) u5 renewal-count))
;;         )
;;         (* (var-get renewal-discount-rate) capped-renewals)
;;     )
;; )

;; Function to check if a policy is renewable
(define-read-only (is-policy-renewable (user principal))
    (let
        (
            (policy (unwrap! (map-get? insurance-policies user) false))
        )
        (and 
            ;; (is-some policy)
            (or 
                (get active policy)
                (< (- stacks-block-height (get expiry-height policy)) BLOCKS_PER_MONTH)
            )
        )
    )
)