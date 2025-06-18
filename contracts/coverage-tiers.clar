;; (define-data-var coverage-tiers (list (tuple (name (string-ascii 50)) (premium uint) (coverage-amount uint))) (list))

;; (define-public (add-coverage-tier (name (string-ascii 50)) (premium uint) (coverage-amount uint))
;;   (begin
;;     (var-set coverage-tiers (append (var-get coverage-tiers) (list (tuple (name name) (premium premium) (coverage-amount coverage-amount)))))
;;     (ok "Coverage tier added successfully.")
;;   )
;; )

;; (define-public (modify-coverage-tier (name (string-ascii 50)) (new-premium uint) (new-coverage-amount uint))
;;   (let ((existing-tier (find-tier name)))
;;     (if (is-none existing-tier)
;;       (err "Coverage tier not found.")
;;       (begin
;;         (var-set coverage-tiers (map (lambda (tier)
;;                                         (if (eq (get name tier) name)
;;                                           (tuple (name name) (premium new-premium) (coverage-amount new-coverage-amount))
;;                                           tier))
;;                                       (var-get coverage-tiers)))
;;         (ok "Coverage tier modified successfully.")
;;       )
;;     )
;;   )
;; )

;; (define-private (find-tier (name (string-ascii 50)))
;; ;;   (let ((filtered-tiers (filter (lambda (tier) (is-eq? (get name tier) name)) (var-get coverage-tiers))))
;;     (if (is-eq (len filtered-tiers) u0)
;;       none
;;       (some (element-at filtered-tiers u0))
;;     )
;;   )


;; (define-public (get-coverage-tiers)
;;   (ok (var-get coverage-tiers))
;; )