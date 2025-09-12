;; Parametric Insurance Triggers Contract
;; Enables automatic claim processing based on external data feeds and predefined conditions

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_TRIGGER_NOT_FOUND (err u111))
(define-constant ERR_INVALID_THRESHOLD (err u112))
(define-constant ERR_TRIGGER_INACTIVE (err u113))
(define-constant ERR_INSUFFICIENT_FUNDS (err u114))
(define-constant ERR_ALREADY_TRIGGERED (err u115))
(define-constant ERR_INVALID_ORACLE (err u116))
(define-constant ERR_PAYOUT_FAILED (err u117))

;; Data variables for contract configuration
(define-data-var oracle-timeout uint u4320) ;; 30 days in blocks
(define-data-var min-trigger-amount uint u1000000) ;; Minimum payout amount
(define-data-var max-trigger-amount uint u100000000) ;; Maximum payout amount
(define-data-var next-trigger-id uint u1)
(define-data-var total-triggers-created uint u0)
(define-data-var total-automatic-payouts uint u0)

;; Map to store oracle data sources
(define-map authorized-oracles
    principal
    {
        name: (string-ascii 50),
        active: bool,
        data-type: (string-ascii 30),
        last-update: uint
    }
)

;; Map to store trigger definitions
(define-map parametric-triggers
    uint ;; trigger-id
    {
        creator: principal,
        oracle-source: principal,
        trigger-type: (string-ascii 20),
        threshold-value: uint,
        comparison-operator: (string-ascii 10),
        payout-amount: uint,
        active: bool,
        created-at: uint,
        expiry-block: uint
    }
)

;; Map to track trigger executions and payouts
(define-map trigger-executions
    uint ;; trigger-id
    {
        executed: bool,
        execution-block: uint,
        oracle-value: uint,
        payout-completed: bool,
        beneficiary: principal
    }
)

;; Map to store latest oracle data
(define-map oracle-data
    {source: principal, data-key: (string-ascii 50)}
    {
        value: uint,
        timestamp: uint,
        block-height: uint
    }
)

;; Map to track user trigger subscriptions
(define-map user-trigger-subscriptions
    {user: principal, trigger-id: uint}
    {
        subscribed: bool,
        premium-paid: uint,
        coverage-amount: uint
    }
)

;; Public function to add authorized oracle
(define-public (add-oracle (oracle principal) (name (string-ascii 50)) (data-type (string-ascii 30)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set authorized-oracles oracle
            {
                name: name,
                active: true,
                data-type: data-type,
                last-update: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Public function to update oracle status
(define-public (update-oracle-status (oracle principal) (active bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (let ((oracle-info (unwrap! (map-get? authorized-oracles oracle) ERR_INVALID_ORACLE)))
            (map-set authorized-oracles oracle
                (merge oracle-info {active: active})
            )
            (ok true)
        )
    )
)

;; Public function for oracles to submit data
(define-public (submit-oracle-data (data-key (string-ascii 50)) (value uint))
    (let ((oracle-info (unwrap! (map-get? authorized-oracles tx-sender) ERR_NOT_AUTHORIZED)))
        (asserts! (get active oracle-info) ERR_TRIGGER_INACTIVE)
        (map-set oracle-data {source: tx-sender, data-key: data-key}
            {
                value: value,
                timestamp: stacks-block-height,
                block-height: stacks-block-height
            }
        )
        (map-set authorized-oracles tx-sender
            (merge oracle-info {last-update: stacks-block-height})
        )
        (ok true)
    )
)

;; Public function to create a new parametric trigger
(define-public (create-trigger 
    (oracle-source principal) 
    (trigger-type (string-ascii 20)) 
    (threshold-value uint) 
    (comparison-operator (string-ascii 10))
    (payout-amount uint)
    (duration uint))
    (let ((trigger-id (var-get next-trigger-id)))
        (asserts! (is-some (map-get? authorized-oracles oracle-source)) ERR_INVALID_ORACLE)
        (asserts! (and (>= payout-amount (var-get min-trigger-amount)) (<= payout-amount (var-get max-trigger-amount))) ERR_INVALID_THRESHOLD)
        (asserts! (> duration u0) ERR_INVALID_THRESHOLD)
        
        (map-set parametric-triggers trigger-id
            {
                creator: tx-sender,
                oracle-source: oracle-source,
                trigger-type: trigger-type,
                threshold-value: threshold-value,
                comparison-operator: comparison-operator,
                payout-amount: payout-amount,
                active: true,
                created-at: stacks-block-height,
                expiry-block: (+ stacks-block-height (* duration u4320))
            }
        )
        
        (var-set next-trigger-id (+ trigger-id u1))
        (var-set total-triggers-created (+ (var-get total-triggers-created) u1))
        (ok trigger-id)
    )
)

;; Public function to subscribe to a trigger
(define-public (subscribe-to-trigger (trigger-id uint) (premium-amount uint))
    (let ((trigger (unwrap! (map-get? parametric-triggers trigger-id) ERR_TRIGGER_NOT_FOUND)))
        (asserts! (get active trigger) ERR_TRIGGER_INACTIVE)
        (asserts! (< stacks-block-height (get expiry-block trigger)) ERR_TRIGGER_INACTIVE)
        
        ;; Transfer premium to contract
        (try! (stx-transfer? premium-amount tx-sender (as-contract tx-sender)))
        
        (map-set user-trigger-subscriptions {user: tx-sender, trigger-id: trigger-id}
            {
                subscribed: true,
                premium-paid: premium-amount,
                coverage-amount: (get payout-amount trigger)
            }
        )
        (ok true)
    )
)

;; Public function to check and execute trigger conditions
(define-public (check-and-execute-trigger (trigger-id uint) (data-key (string-ascii 50)))
    (let 
        (
            (trigger (unwrap! (map-get? parametric-triggers trigger-id) ERR_TRIGGER_NOT_FOUND))
            (oracle-source (get oracle-source trigger))
            (oracle-value-data (unwrap! (map-get? oracle-data {source: oracle-source, data-key: data-key}) ERR_INVALID_ORACLE))
            (oracle-value (get value oracle-value-data))
            (threshold (get threshold-value trigger))
            (operator (get comparison-operator trigger))
            (execution (map-get? trigger-executions trigger-id))
        )
        
        ;; Check if trigger is active and not already executed
        (asserts! (get active trigger) ERR_TRIGGER_INACTIVE)
        (asserts! (< stacks-block-height (get expiry-block trigger)) ERR_TRIGGER_INACTIVE)
        (asserts! (is-none execution) ERR_ALREADY_TRIGGERED)
        
        ;; Check oracle data freshness
        (asserts! (< (- stacks-block-height (get block-height oracle-value-data)) (var-get oracle-timeout)) ERR_INVALID_ORACLE)
        
        ;; Evaluate trigger condition
        (let ((condition-met (evaluate-trigger-condition oracle-value threshold operator)))
            (if condition-met
                (begin
                    ;; Record execution
                    (map-set trigger-executions trigger-id
                        {
                            executed: true,
                            execution-block: stacks-block-height,
                            oracle-value: oracle-value,
                            payout-completed: false,
                            beneficiary: (get creator trigger)
                        }
                    )
                    ;; Execute payout will be called separately
                    (ok true)
                )
                (ok false)
            )
        )
    )
)

;; Public function to execute payout for triggered condition
(define-public (execute-trigger-payout (trigger-id uint))
    (let 
        (
            (trigger (unwrap! (map-get? parametric-triggers trigger-id) ERR_TRIGGER_NOT_FOUND))
            (execution (unwrap! (map-get? trigger-executions trigger-id) ERR_TRIGGER_NOT_FOUND))
            (payout-amount (get payout-amount trigger))
            (beneficiary (get beneficiary execution))
        )
        
        ;; Verify execution conditions
        (asserts! (get executed execution) ERR_TRIGGER_NOT_FOUND)
        (asserts! (not (get payout-completed execution)) ERR_ALREADY_TRIGGERED)
        
        ;; Execute payout
        (match (as-contract (stx-transfer? payout-amount (as-contract tx-sender) beneficiary))
            success 
            (begin
                ;; Update execution record
                (map-set trigger-executions trigger-id
                    (merge execution {payout-completed: true})
                )
                ;; Deactivate trigger
                (map-set parametric-triggers trigger-id
                    (merge trigger {active: false})
                )
                (var-set total-automatic-payouts (+ (var-get total-automatic-payouts) u1))
                (ok payout-amount)
            )
            error ERR_PAYOUT_FAILED
        )
    )
)

;; Private function to evaluate trigger conditions
(define-private (evaluate-trigger-condition (oracle-value uint) (threshold uint) (operator (string-ascii 10)))
    (if (is-eq operator "GT")
        (> oracle-value threshold)
        (if (is-eq operator "LT")
            (< oracle-value threshold)
            (if (is-eq operator "EQ")
                (is-eq oracle-value threshold)
                (if (is-eq operator "GTE")
                    (>= oracle-value threshold)
                    (if (is-eq operator "LTE")
                        (<= oracle-value threshold)
                        false
                    )
                )
            )
        )
    )
)

;; Public function to deactivate a trigger
(define-public (deactivate-trigger (trigger-id uint))
    (let ((trigger (unwrap! (map-get? parametric-triggers trigger-id) ERR_TRIGGER_NOT_FOUND)))
        (asserts! (is-eq tx-sender (get creator trigger)) ERR_NOT_AUTHORIZED)
        (map-set parametric-triggers trigger-id
            (merge trigger {active: false})
        )
        (ok true)
    )
)

;; Admin function to set oracle timeout
(define-public (set-oracle-timeout (timeout uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set oracle-timeout timeout)
        (ok true)
    )
)

;; Admin function to set trigger amount limits
(define-public (set-trigger-limits (min-amount uint) (max-amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (< min-amount max-amount) ERR_INVALID_THRESHOLD)
        (var-set min-trigger-amount min-amount)
        (var-set max-trigger-amount max-amount)
        (ok true)
    )
)

;; Read-only function to get trigger details
(define-read-only (get-trigger (trigger-id uint))
    (map-get? parametric-triggers trigger-id)
)

;; Read-only function to get trigger execution status
(define-read-only (get-trigger-execution (trigger-id uint))
    (map-get? trigger-executions trigger-id)
)

;; Read-only function to get oracle data
(define-read-only (get-oracle-data (source principal) (data-key (string-ascii 50)))
    (map-get? oracle-data {source: source, data-key: data-key})
)

;; Read-only function to get oracle info
(define-read-only (get-oracle-info (oracle principal))
    (map-get? authorized-oracles oracle)
)

;; Read-only function to get user subscription
(define-read-only (get-user-subscription (user principal) (trigger-id uint))
    (map-get? user-trigger-subscriptions {user: user, trigger-id: trigger-id})
)

;; Read-only function to get contract statistics
(define-read-only (get-contract-stats)
    {
        total-triggers: (var-get total-triggers-created),
        total-payouts: (var-get total-automatic-payouts),
        oracle-timeout: (var-get oracle-timeout),
        min-trigger-amount: (var-get min-trigger-amount),
        max-trigger-amount: (var-get max-trigger-amount)
    }
)

;; Read-only function to check if trigger condition would be met
(define-read-only (simulate-trigger-check (trigger-id uint) (test-value uint))
    (let ((trigger (unwrap! (map-get? parametric-triggers trigger-id) false)))
        (evaluate-trigger-condition 
            test-value 
            (get threshold-value trigger) 
            (get comparison-operator trigger)
        )
    )
)


