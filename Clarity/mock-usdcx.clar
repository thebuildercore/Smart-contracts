
;; Project: Stacks-Escrow
;; Contract: mock-usdcx
;; Description: SIP-010 compliant mock token
;;  TEST TOKEN ONLY DO NOT DEPLOY TO MAINNET

(impl-trait .sip-010-trait-ft-standard.sip-010-trait)

(define-fungible-token usdcx)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) (err u101))
        (try! (ft-transfer? usdcx amount sender recipient))
        (match memo to-print (print to-print) 0x)
        (ok true)
    )
)

(define-read-only (get-name) (ok "Mock USDCx"))
(define-read-only (get-symbol) (ok "USDCx"))
(define-read-only (get-decimals) (ok u6))
(define-read-only (get-balance (who principal)) (ok (ft-get-balance usdcx who)))
(define-read-only (get-total-supply) (ok (ft-get-supply usdcx)))
(define-read-only (get-token-uri) (ok none))

;; Only the contract owner can mint new tokens
(define-public (mint (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ft-mint? usdcx amount recipient)
    )
)
