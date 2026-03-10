;; Title: Stacks Escrow Service
;; Author: [Gridgirl]
;; Version: v1 (Safe Prototype)
;; Notes:
;; - Mock tokens allowed (testnet/dev only)
;; - Arbitrator = contract deployer
;; - Token validation prevents fake-token exploits

(use-trait ft-trait .sip-010-trait-ft-standard.sip-010-trait)


;; Constants & Errors


(define-constant CONTRACT-OWNER tx-sender)

(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-JOB-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-RELEASED (err u405))
(define-constant ERR-WRONG-TOKEN (err u406))
(define-constant ERR-INVALID-AMOUNT (err u400))


;; Storage


(define-map Jobs
  { job-id: uint }
  {
    buyer: principal,
    worker: principal,
    amount: uint,
    token: principal,
    status: (string-ascii 20)
  }
)

(define-data-var next-job-id uint u1)


;; Public Functions


;; Lock payment into escrow
(define-public (lock-payment (worker principal) (amount uint) (token-contract <ft-trait>))
  (let ((job-id (var-get next-job-id)))
    ;; Prevent zero-value or spam jobs
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Transfer tokens from buyer to escrow
    (try!
      (contract-call?
        token-contract
        transfer
        amount
        tx-sender
        (as-contract tx-sender)
        none
      )
    )

    ;; Store job
    (map-set Jobs { job-id: job-id }
      {
        buyer: tx-sender,
        worker: worker,
        amount: amount,
        token: (contract-of token-contract),
        status: "LOCKED"
      }
    )

    (var-set next-job-id (+ job-id u1))
    (ok job-id)
  )
)

;; Release payment to worker (buyer only)
(define-public (release-payment (job-id uint) (token-contract <ft-trait>))
  (let (
    (job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-JOB-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get buyer job)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status job) "LOCKED") ERR-ALREADY-RELEASED)
    (asserts! (is-eq (contract-of token-contract) (get token job)) ERR-WRONG-TOKEN)

    (try!
      (as-contract
        (contract-call?
          token-contract
          transfer
          (get amount job)
          tx-sender
          (get worker job)
          none
        )
      )
    )

    (map-set Jobs { job-id: job-id }
      (merge job { status: "RELEASED" })
    )

    (ok true)
  )
)

;; Refund buyer (buyer only)
(define-public (refund (job-id uint) (token-contract <ft-trait>))
  (let (
    (job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-JOB-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get buyer job)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status job) "LOCKED") ERR-ALREADY-RELEASED)
    (asserts! (is-eq (contract-of token-contract) (get token job)) ERR-WRONG-TOKEN)

    (try!
      (as-contract
        (contract-call?
          token-contract
          transfer
          (get amount job)
          tx-sender
          (get buyer job)
          none
        )
      )
    )

    (map-set Jobs { job-id: job-id }
      (merge job { status: "REFUNDED" })
    )

    (ok true)
  )
)

;; Dispute resolution (arbitrator only)
(define-public (resolve-dispute (job-id uint) (token-contract <ft-trait>) (pay-worker bool))
  (let (
    (job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-JOB-NOT-FOUND))
    (destination (if pay-worker (get worker job) (get buyer job)))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status job) "LOCKED") ERR-ALREADY-RELEASED)
    (asserts! (is-eq (contract-of token-contract) (get token job)) ERR-WRONG-TOKEN)

    (try!
      (as-contract
        (contract-call?
          token-contract
          transfer
          (get amount job)
          tx-sender
          destination
          none
        )
      )
    )

    (map-set Jobs { job-id: job-id }
      (merge job {
        status: (if pay-worker "DISPUTE_RELEASE" "DISPUTE_REFUND")
      })
    )

    (ok true)
  )
)

;; Read-only helper
(define-read-only (get-job-details (job-id uint))
  (map-get? Jobs { job-id: job-id })
)
