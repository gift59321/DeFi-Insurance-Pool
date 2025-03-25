(define-public (evaluate-risk (investment-value uint) (market-volatility uint))
  (let ((risk-level (if (>= market-volatility 75)
                        "high"
                        (if (>= market-volatility 50)
                          "medium"
                          "low"))))
    (ok risk-level)))

(define-public (assign-coverage-tier (risk-level (response (tuple (risk-level (string-ascii 10)))))
  (match risk-level
    ("high" (ok "Tier 1: High Coverage"))
    ("medium" (ok "Tier 2: Medium Coverage"))
    ("low" (ok "Tier 3: Low Coverage"))
    (err "Invalid risk level")))