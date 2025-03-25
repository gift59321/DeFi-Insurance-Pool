;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_COVERAGE (err u102))

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
        start-height: uint
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
(define-public (purchase-coverage (coverage-amount uint))
    (let
        (
            (premium-to-pay (calculate-premium coverage-amount))
        )
        (asserts! (>= coverage-amount (var-get min-coverage-amount)) ERR_INVALID_COVERAGE)
        (try! (stx-transfer? premium-to-pay tx-sender (as-contract tx-sender)))
        
        (map-set insurance-policies tx-sender
            {
                coverage-amount: coverage-amount,
                premium-paid: premium-to-pay,
                active: true,
                start-height: stacks-block-height
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

;; Admin functions
(define-public (approve-claim (user principal))
    (begin
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