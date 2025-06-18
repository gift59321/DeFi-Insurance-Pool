(define-data-var coverage-tiers (list (tuple (name (string-ascii 50)) (premium uint) (coverage-amount uint))))

(define-public (add-coverage-tier (name (string-ascii 50)) (premium uint) (coverage-amount uint))
  (begin
    (var-set coverage-tiers (cons (tuple (name name) (premium premium) (coverage-amount coverage-amount)) (var-get coverage-tiers)))
    (ok "Coverage tier added successfully.")
  )
)

(define-public (modify-coverage-tier (name (string-ascii 50)) (new-premium uint) (new-coverage-amount uint))
  (let ((existing-tier (find-tier name)))
    (if (is-none existing-tier)
      (err "Coverage tier not found.")
      (begin
        (var-set coverage-tiers (map (lambda (tier)
                                        (if (eq (get name tier) name)
                                          (tuple (name name) (premium new-premium) (coverage-amount new-coverage-amount))
                                          tier))
                                      (var-get coverage-tiers)))
        (ok "Coverage tier modified successfully.")
      )
    )
  )
)

(define-private (find-tier (name (string-ascii 50)))
  (map (lambda (tier)
          (if (eq (get name tier) name)
            tier
            (none)))
       (var-get coverage-tiers))
)

(define-public (get-coverage-tiers)
  (ok (var-get coverage-tiers))
)