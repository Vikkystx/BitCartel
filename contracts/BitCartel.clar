;; BitCartel - Decentralized Marketplace for Digital Goods
;; Escrow contract with reputation system and dispute resolution

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-ESCROW-NOT-FOUND (err u102))
(define-constant ERR-ESCROW-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-ALREADY-RATED (err u106))
(define-constant ERR-INVALID-RATING (err u107))
(define-constant ERR-SELF-RATING (err u108))
(define-constant ERR-INVALID-HASH (err u109))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Escrow statuses
(define-constant STATUS-PENDING u0)
(define-constant STATUS-DELIVERED u1)
(define-constant STATUS-COMPLETED u2)
(define-constant STATUS-DISPUTED u3)
(define-constant STATUS-REFUNDED u4)

;; Data structures
(define-map escrows
    { escrow-id: uint }
    {
        buyer: principal,
        seller: principal,
        amount: uint,
        status: uint,
        created-at: uint,
        item-hash: (buff 32),
        delivery-hash: (optional (buff 32))
    }
)

(define-map user-reputation
    { user: principal }
    {
        total-rating: uint,
        rating-count: uint,
        completed-transactions: uint
    }
)

(define-map transaction-ratings
    { escrow-id: uint, rater: principal }
    { rating: uint }
)

;; Global variables
(define-data-var escrow-counter uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; Helper functions
(define-private (get-next-escrow-id)
    (begin
        (var-set escrow-counter (+ (var-get escrow-counter) u1))
        (var-get escrow-counter)
    )
)

(define-private (is-valid-hash (hash (buff 32)))
    (not (is-eq hash 0x0000000000000000000000000000000000000000000000000000000000000000))
)

(define-read-only (get-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-read-only (get-escrow-details (escrow-id uint))
    (begin
        (asserts! (> escrow-id u0) (err ERR-ESCROW-NOT-FOUND))
        (ok (map-get? escrows { escrow-id: escrow-id }))
    )
)

(define-read-only (get-user-reputation (user principal))
    (default-to 
        { total-rating: u0, rating-count: u0, completed-transactions: u0 }
        (map-get? user-reputation { user: user })
    )
)

(define-read-only (get-user-average-rating (user principal))
    (let ((reputation (get-user-reputation user)))
        (if (> (get rating-count reputation) u0)
            (some (/ (get total-rating reputation) (get rating-count reputation)))
            none
        )
    )
)

;; Public functions
(define-public (create-escrow (seller principal) (amount uint) (item-hash (buff 32)))
    (let 
        (
            (escrow-id (get-next-escrow-id))
            (total-amount (+ amount (get-platform-fee amount)))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq seller tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-hash item-hash) ERR-INVALID-HASH)
        (asserts! (is-none (map-get? escrows { escrow-id: escrow-id })) ERR-ESCROW-ALREADY-EXISTS)
        (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
        
        (map-set escrows
            { escrow-id: escrow-id }
            {
                buyer: tx-sender,
                seller: seller,
                amount: amount,
                status: STATUS-PENDING,
                created-at: stacks-block-height,
                item-hash: item-hash,
                delivery-hash: none
            }
        )
        (ok escrow-id)
    )
)

(define-public (confirm-delivery (escrow-id uint) (delivery-hash (buff 32)))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender (get seller escrow-data)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-PENDING) ERR-INVALID-STATUS)
        (asserts! (is-valid-hash delivery-hash) ERR-INVALID-HASH)
        
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow-data { 
                status: STATUS-DELIVERED,
                delivery-hash: (some delivery-hash)
            })
        )
        (ok true)
    )
)

(define-public (complete-transaction (escrow-id uint))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (platform-fee (get-platform-fee (get amount escrow-data)))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender (get buyer escrow-data)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-DELIVERED) ERR-INVALID-STATUS)
        
        ;; Transfer payment to seller
        (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get seller escrow-data))))
        
        ;; Transfer platform fee to contract owner
        (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT-OWNER)))
        
        ;; Update escrow status
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow-data { status: STATUS-COMPLETED })
        )
        
        ;; Update seller reputation
        (let ((seller-rep (get-user-reputation (get seller escrow-data))))
            (map-set user-reputation
                { user: (get seller escrow-data) }
                (merge seller-rep { 
                    completed-transactions: (+ (get completed-transactions seller-rep) u1)
                })
            )
        )
        (ok true)
    )
)

(define-public (dispute-transaction (escrow-id uint))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (or 
            (is-eq tx-sender (get buyer escrow-data))
            (is-eq tx-sender (get seller escrow-data))
        ) ERR-NOT-AUTHORIZED)
        (asserts! (or 
            (is-eq (get status escrow-data) STATUS-PENDING)
            (is-eq (get status escrow-data) STATUS-DELIVERED)
        ) ERR-INVALID-STATUS)
        
        (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow-data { status: STATUS-DISPUTED })
        )
        (ok true)
    )
)

(define-public (resolve-dispute (escrow-id uint) (refund-to-buyer bool))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (platform-fee (get-platform-fee (get amount escrow-data)))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-DISPUTED) ERR-INVALID-STATUS)
        
        (if refund-to-buyer
            (begin
                ;; Refund to buyer (including platform fee)
                (try! (as-contract (stx-transfer? 
                    (+ (get amount escrow-data) platform-fee)
                    tx-sender 
                    (get buyer escrow-data)
                )))
                (map-set escrows
                    { escrow-id: escrow-id }
                    (merge escrow-data { status: STATUS-REFUNDED })
                )
            )
            (begin
                ;; Pay seller and take platform fee
                (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get seller escrow-data))))
                (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT-OWNER)))
                (map-set escrows
                    { escrow-id: escrow-id }
                    (merge escrow-data { status: STATUS-COMPLETED })
                )
                ;; Update seller reputation
                (let ((seller-rep (get-user-reputation (get seller escrow-data))))
                    (map-set user-reputation
                        { user: (get seller escrow-data) }
                        (merge seller-rep { 
                            completed-transactions: (+ (get completed-transactions seller-rep) u1)
                        })
                    )
                )
            )
        )
        (ok true)
    )
)

(define-public (rate-user (escrow-id uint) (user principal) (rating uint))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (user-rep (get-user-reputation user))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (> rating u0) ERR-INVALID-RATING)
        (asserts! (is-eq (get status escrow-data) STATUS-COMPLETED) ERR-INVALID-STATUS)
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
        (asserts! (not (is-eq tx-sender user)) ERR-SELF-RATING)
        (asserts! (or 
            (is-eq tx-sender (get buyer escrow-data))
            (is-eq tx-sender (get seller escrow-data))
        ) ERR-NOT-AUTHORIZED)
        (asserts! (or 
            (is-eq user (get buyer escrow-data))
            (is-eq user (get seller escrow-data))
        ) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (map-get? transaction-ratings { escrow-id: escrow-id, rater: tx-sender })) ERR-ALREADY-RATED)
        
        ;; Record the rating
        (map-set transaction-ratings
            { escrow-id: escrow-id, rater: tx-sender }
            { rating: rating }
        )
        
        ;; Update user reputation
        (map-set user-reputation
            { user: user }
            {
                total-rating: (+ (get total-rating user-rep) rating),
                rating-count: (+ (get rating-count user-rep) u1),
                completed-transactions: (get completed-transactions user-rep)
            }
        )
        (ok true)
    )
)

;; Admin functions
(define-public (set-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR-INVALID-AMOUNT) ;; Max 10%
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)