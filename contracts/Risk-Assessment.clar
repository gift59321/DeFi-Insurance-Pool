(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_RISK_SCORE (err u108))
(define-constant ERR_INVALID_DURATION (err u109))
(define-constant ERR_POLICY_NOT_FOUND (err u110))

(define-data-var base-premium-rate uint u5)
(define-data-var risk-multiplier-cap uint u300)
(define-data-var assessment-period-blocks uint u4320)

(define-map risk-profiles
    principal
    {
        risk-score: uint,
        claims-count: uint,
        last-assessment: uint,
        assessment-history: (list 5 uint)
    }
)

(define-map risk-factors
    uint
    {
        factor-name: (string-ascii 50),
        weight: uint,
        active: bool
    }
)

(define-data-var next-factor-id uint u1)

(define-public (initialize-risk-factors)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set risk-factors u1 {factor-name: "claim-frequency", weight: u40, active: true})
        (map-set risk-factors u2 {factor-name: "coverage-amount", weight: u25, active: true})
        (map-set risk-factors u3 {factor-name: "policy-duration", weight: u20, active: true})
        (map-set risk-factors u4 {factor-name: "account-age", weight: u15, active: true})
        (var-set next-factor-id u5)
        (ok true)
    )
)

(define-public (add-risk-factor (factor-name (string-ascii 50)) (weight uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= weight u100) ERR_INVALID_RISK_SCORE)
        (let ((factor-id (var-get next-factor-id)))
            (map-set risk-factors factor-id
                {
                    factor-name: factor-name,
                    weight: weight,
                    active: true
                }
            )
            (var-set next-factor-id (+ factor-id u1))
            (ok factor-id)
        )
    )
)

(define-public (update-risk-factor (factor-id uint) (weight uint) (active bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= weight u100) ERR_INVALID_RISK_SCORE)
        (let ((factor (unwrap! (map-get? risk-factors factor-id) ERR_POLICY_NOT_FOUND)))
            (map-set risk-factors factor-id
                (merge factor {weight: weight, active: active})
            )
            (ok true)
        )
    )
)

(define-public (assess-user-risk (user principal) (claims-count uint) (coverage-amount uint) (duration uint))
    (let
        (
            (current-profile (default-to 
                {risk-score: u100, claims-count: u0, last-assessment: u0, assessment-history: (list)}
                (map-get? risk-profiles user)
            ))
            (claim-frequency-score (calculate-claim-frequency-score claims-count))
            (coverage-score (calculate-coverage-score coverage-amount))
            (duration-score (calculate-duration-score duration))
            (account-age-score (calculate-account-age-score user))
            (composite-score (calculate-composite-risk-score claim-frequency-score coverage-score duration-score account-age-score))
            (new-history (unwrap-panic (as-max-len? (append (get assessment-history current-profile) composite-score) u5)))
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (and (>= composite-score u50) (<= composite-score u200)) ERR_INVALID_RISK_SCORE)
        
        (map-set risk-profiles user
            {
                risk-score: composite-score,
                claims-count: claims-count,
                last-assessment: stacks-block-height,
                assessment-history: new-history
            }
        )
        (ok composite-score)
    )
)

(define-read-only (calculate-claim-frequency-score (claims-count uint))
    (if (is-eq claims-count u0)
        u80
        (if (<= claims-count u2)
            u120
            (if (<= claims-count u5)
                u160
                u200
            )
        )
    )
)

(define-read-only (calculate-coverage-score (coverage-amount uint))
    (if (< coverage-amount u5000000)
        u90
        (if (< coverage-amount u20000000)
            u110
            u140
        )
    )
)

(define-read-only (calculate-duration-score (duration uint))
    (if (>= duration u12)
        u80
        (if (>= duration u6)
            u100
            u120
        )
    )
)

(define-read-only (calculate-account-age-score (user principal))
    u100
)

(define-read-only (calculate-composite-risk-score (claim-freq uint) (coverage uint) (duration uint) (account-age uint))
    (let
        (
            (claim-weight (get weight (unwrap-panic (map-get? risk-factors u1))))
            (coverage-weight (get weight (unwrap-panic (map-get? risk-factors u2))))
            (duration-weight (get weight (unwrap-panic (map-get? risk-factors u3))))
            (account-weight (get weight (unwrap-panic (map-get? risk-factors u4))))
            (weighted-score (+ 
                (/ (* claim-freq claim-weight) u100)
                (/ (* coverage coverage-weight) u100)
                (/ (* duration duration-weight) u100)
                (/ (* account-age account-weight) u100)
            ))
        )
        weighted-score
    )
)

(define-read-only (min (a uint) (b uint))
    (if (< a b) a b)
)

(define-read-only (max (a uint) (b uint))
    (if (< a b) b a)
)

(define-read-only (calculate-risk-adjusted-premium (base-premium uint) (user principal))
    (let
        (
            (risk-profile (map-get? risk-profiles user))
        )
        (match risk-profile
            profile
            (let
                (
                    (risk-score (get risk-score profile))
                    (risk-multiplier (min (var-get risk-multiplier-cap) (max u50 risk-score)))
                    (adjusted-premium (/ (* base-premium risk-multiplier) u100))
                )
                adjusted-premium
            )
            base-premium
        )
    )
)

(define-public (purchase-risk-assessed-coverage (coverage-amount uint) (duration uint))
    (let
        (
            (base-premium (/ (* coverage-amount (var-get base-premium-rate)) u1000))
            (risk-adjusted-premium (calculate-risk-adjusted-premium base-premium tx-sender))
        )
        (asserts! (>= coverage-amount u1000000) ERR_INVALID_RISK_SCORE)
        (asserts! (and (>= duration u1) (<= duration u24)) ERR_INVALID_DURATION)
        (try! (stx-transfer? risk-adjusted-premium tx-sender (as-contract tx-sender)))
        (ok risk-adjusted-premium)
    )
)

(define-public (trigger-risk-reassessment (user principal))
    (let
        (
            (current-profile (unwrap! (map-get? risk-profiles user) ERR_POLICY_NOT_FOUND))
            (last-assessment (get last-assessment current-profile))
            (blocks-since-assessment (- stacks-block-height last-assessment))
        )
        (asserts! (> blocks-since-assessment (var-get assessment-period-blocks)) ERR_INVALID_DURATION)
        (ok true)
    )
)

(define-public (set-base-premium-rate (rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set base-premium-rate rate)
        (ok true)
    )
)

(define-public (set-risk-multiplier-cap (cap uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (>= cap u100) ERR_INVALID_RISK_SCORE)
        (var-set risk-multiplier-cap cap)
        (ok true)
    )
)

(define-public (set-assessment-period (blocks uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (>= blocks u1000) ERR_INVALID_DURATION)
        (var-set assessment-period-blocks blocks)
        (ok true)
    )
)

(define-read-only (get-user-risk-profile (user principal))
    (map-get? risk-profiles user)
)

(define-read-only (get-risk-factor (factor-id uint))
    (map-get? risk-factors factor-id)
)

(define-read-only (get-risk-assessment-config)
    {
        base-premium-rate: (var-get base-premium-rate),
        risk-multiplier-cap: (var-get risk-multiplier-cap),
        assessment-period-blocks: (var-get assessment-period-blocks)
    }
)

(define-read-only (calculate-premium-preview (coverage-amount uint) (user principal))
    (let
        (
            (base-premium (/ (* coverage-amount (var-get base-premium-rate)) u1000))
            (risk-adjusted-premium (calculate-risk-adjusted-premium base-premium user))
        )
        {
            base-premium: base-premium,
            risk-adjusted-premium: risk-adjusted-premium,
            risk-multiplier: (match (map-get? risk-profiles user)
                profile (get risk-score profile)
                u100
            )
        }
    )
)
