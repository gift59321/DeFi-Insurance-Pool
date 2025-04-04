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