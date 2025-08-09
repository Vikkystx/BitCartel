;; BitCartel - Decentralized Marketplace for Digital Goods
;; Escrow contract with reputation system, dispute resolution, and multi-token support

;; SIP-010 trait definition
(define-trait sip010-token
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-decimals () (response uint uint))
        (get-balance (principal) (response uint uint))
        (get-total-supply () (response uint uint))
        (get-token-uri () (response (optional (string-utf8 256)) uint))
    )
)

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
(define-constant ERR-TOKEN-TRANSFER-FAILED (err u110))
(define-constant ERR-UNSUPPORTED-TOKEN (err u111))
(define-constant ERR-TOKEN-NOT-FOUND (err u112))
(define-constant ERR-INVALID-TOKEN-NAME (err u113))
(define-constant ERR-INVALID-PARTY (err u114))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; STX token identifier (special case)
(define-constant STX-TOKEN "STX")

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
        delivery-hash: (optional (buff 32)),
        token-contract: (optional principal),
        token-name: (string-ascii 32)
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

(define-map supported-tokens
    { token-contract: principal }
    {
        token-name: (string-ascii 32),
        is-active: bool,
        added-at: uint
    }
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

(define-private (is-valid-token-name (name (string-ascii 32)))
    (and
        (> (len name) u0)
        (<= (len name) u32)
    )
)

(define-read-only (get-user-reputation (user principal))
    (default-to 
        { total-rating: u0, rating-count: u0, completed-transactions: u0 }
        (map-get? user-reputation { user: user })
    )
)

(define-private (is-valid-party (party principal) (escrow-data {
    buyer: principal,
    seller: principal,
    amount: uint,
    status: uint,
    created-at: uint,
    item-hash: (buff 32),
    delivery-hash: (optional (buff 32)),
    token-contract: (optional principal),
    token-name: (string-ascii 32)
}))
    (or
        (is-eq party (get buyer escrow-data))
        (is-eq party (get seller escrow-data))
    )
)

(define-read-only (get-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-read-only (is-token-supported (token-contract principal))
    (match (map-get? supported-tokens { token-contract: token-contract })
        token-data (get is-active token-data)
        false
    )
)

;; Read-only functions
(define-read-only (get-escrow-details (escrow-id uint))
    (if (> escrow-id u0)
        (ok (map-get? escrows { escrow-id: escrow-id }))
        ERR-ESCROW-NOT-FOUND
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

(define-read-only (get-supported-token (token-contract principal))
    (map-get? supported-tokens { token-contract: token-contract })
)

(define-read-only (get-escrow-count)
    (var-get escrow-counter)
)

(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

;; Public functions for STX
(define-public (create-escrow-stx (seller principal) (amount uint) (item-hash (buff 32)))
    (let 
        (
            (escrow-id (get-next-escrow-id))
            (platform-fee (get-platform-fee amount))
            (total-amount (+ amount platform-fee))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq seller tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-hash item-hash) ERR-INVALID-HASH)
        
        ;; Transfer STX to escrow
        (match (stx-transfer? total-amount tx-sender (as-contract tx-sender))
            success (begin
                (map-set escrows
                    { escrow-id: escrow-id }
                    {
                        buyer: tx-sender,
                        seller: seller,
                        amount: amount,
                        status: STATUS-PENDING,
                        created-at: stacks-block-height,
                        item-hash: item-hash,
                        delivery-hash: none,
                        token-contract: none,
                        token-name: STX-TOKEN
                    }
                )
                (ok escrow-id)
            )
            error ERR-TOKEN-TRANSFER-FAILED
        )
    )
)

;; Public functions for SIP-010 tokens
(define-public (create-escrow-sip010 (seller principal) (amount uint) (item-hash (buff 32)) (token-contract <sip010-token>) (token-name (string-ascii 32)))
    (let 
        (
            (escrow-id (get-next-escrow-id))
            (contract-principal (contract-of token-contract))
            (platform-fee (get-platform-fee amount))
            (total-amount (+ amount platform-fee))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq seller tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-hash item-hash) ERR-INVALID-HASH)
        (asserts! (is-token-supported contract-principal) ERR-UNSUPPORTED-TOKEN)
        (asserts! (is-valid-token-name token-name) ERR-INVALID-TOKEN-NAME)
        
        ;; Transfer SIP-010 tokens to escrow
        (match (contract-call? token-contract transfer total-amount tx-sender (as-contract tx-sender) none)
            success (begin
                (map-set escrows
                    { escrow-id: escrow-id }
                    {
                        buyer: tx-sender,
                        seller: seller,
                        amount: amount,
                        status: STATUS-PENDING,
                        created-at: stacks-block-height,
                        item-hash: item-hash,
                        delivery-hash: none,
                        token-contract: (some contract-principal),
                        token-name: token-name
                    }
                )
                (ok escrow-id)
            )
            error ERR-TOKEN-TRANSFER-FAILED
        )
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

(define-public (complete-transaction-stx (escrow-id uint))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (platform-fee (get-platform-fee (get amount escrow-data)))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender (get buyer escrow-data)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-DELIVERED) ERR-INVALID-STATUS)
        (asserts! (is-none (get token-contract escrow-data)) ERR-UNSUPPORTED-TOKEN)
        
        ;; Transfer STX to seller and platform fee to owner
        (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get seller escrow-data))))
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

(define-public (complete-transaction-sip010 (escrow-id uint) (token-contract <sip010-token>))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (platform-fee (get-platform-fee (get amount escrow-data)))
            (contract-principal (contract-of token-contract))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender (get buyer escrow-data)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-DELIVERED) ERR-INVALID-STATUS)
        (asserts! (is-eq (some contract-principal) (get token-contract escrow-data)) ERR-UNSUPPORTED-TOKEN)
        
        ;; Transfer tokens to seller and platform fee to owner
        (try! (as-contract (contract-call? token-contract transfer (get amount escrow-data) tx-sender (get seller escrow-data) none)))
        (try! (as-contract (contract-call? token-contract transfer platform-fee tx-sender CONTRACT-OWNER none)))
        
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
        (asserts! (is-valid-party tx-sender escrow-data) ERR-NOT-AUTHORIZED)
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

(define-public (resolve-dispute-stx (escrow-id uint) (refund-to-buyer bool))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (platform-fee (get-platform-fee (get amount escrow-data)))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-DISPUTED) ERR-INVALID-STATUS)
        (asserts! (is-none (get token-contract escrow-data)) ERR-UNSUPPORTED-TOKEN)
        
        (if refund-to-buyer
            (begin
                ;; Refund to buyer (including platform fee)
                (try! (as-contract (stx-transfer? (+ (get amount escrow-data) platform-fee) tx-sender (get buyer escrow-data))))
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

(define-public (resolve-dispute-sip010 (escrow-id uint) (refund-to-buyer bool) (token-contract <sip010-token>))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (platform-fee (get-platform-fee (get amount escrow-data)))
            (contract-principal (contract-of token-contract))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status escrow-data) STATUS-DISPUTED) ERR-INVALID-STATUS)
        (asserts! (is-eq (some contract-principal) (get token-contract escrow-data)) ERR-UNSUPPORTED-TOKEN)
        
        (if refund-to-buyer
            (begin
                ;; Refund to buyer (including platform fee)
                (try! (as-contract (contract-call? token-contract transfer (+ (get amount escrow-data) platform-fee) tx-sender (get buyer escrow-data) none)))
                (map-set escrows
                    { escrow-id: escrow-id }
                    (merge escrow-data { status: STATUS-REFUNDED })
                )
            )
            (begin
                ;; Pay seller and take platform fee
                (try! (as-contract (contract-call? token-contract transfer (get amount escrow-data) tx-sender (get seller escrow-data) none)))
                (try! (as-contract (contract-call? token-contract transfer platform-fee tx-sender CONTRACT-OWNER none)))
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

;; Single definition of rate-user function
(define-public (rate-user (escrow-id uint) (user principal) (rating uint))
    (let 
        (
            (escrow-data (unwrap! (map-get? escrows { escrow-id: escrow-id }) ERR-ESCROW-NOT-FOUND))
            (user-rep (get-user-reputation user))
        )
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
        (asserts! (is-eq (get status escrow-data) STATUS-COMPLETED) ERR-INVALID-STATUS)
        (asserts! (not (is-eq tx-sender user)) ERR-SELF-RATING)
        (asserts! (is-valid-party tx-sender escrow-data) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-party user escrow-data) ERR-INVALID-PARTY)
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

(define-public (emergency-refund-stx (escrow-id uint))
    (begin
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        (match (map-get? escrows { escrow-id: escrow-id })
            escrow-data
            (begin
                (asserts! (is-none (get token-contract escrow-data)) ERR-UNSUPPORTED-TOKEN)
                (asserts! (< (get created-at escrow-data) (- stacks-block-height u4320)) ERR-INVALID-STATUS) ;; 30 days old
                
                (let ((platform-fee (get-platform-fee (get amount escrow-data))))
                    ;; Refund to buyer
                    (try! (as-contract (stx-transfer? (+ (get amount escrow-data) platform-fee) tx-sender (get buyer escrow-data))))
                    
                    (map-set escrows
                        { escrow-id: escrow-id }
                        (merge escrow-data { status: STATUS-REFUNDED })
                    )
                    (ok true)
                )
            )
            ERR-ESCROW-NOT-FOUND
        )
    )
)

(define-public (emergency-refund-sip010 (escrow-id uint) (token-contract <sip010-token>))
    (begin
        (asserts! (> escrow-id u0) ERR-ESCROW-NOT-FOUND)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        (let ((contract-principal (contract-of token-contract)))
            (match (map-get? escrows { escrow-id: escrow-id })
                escrow-data
                (begin
                    (asserts! (is-eq (some contract-principal) (get token-contract escrow-data)) ERR-UNSUPPORTED-TOKEN)
                    (asserts! (< (get created-at escrow-data) (- stacks-block-height u4320)) ERR-INVALID-STATUS) ;; 30 days old
                    
                    (let ((platform-fee (get-platform-fee (get amount escrow-data))))
                        ;; Refund to buyer
                        (match (as-contract (contract-call? token-contract transfer (+ (get amount escrow-data) platform-fee) tx-sender (get buyer escrow-data) none))
                            success (begin
                                (map-set escrows
                                    { escrow-id: escrow-id }
                                    (merge escrow-data { status: STATUS-REFUNDED })
                                )
                                (ok true)
                            )
                            error ERR-TOKEN-TRANSFER-FAILED
                        )
                    )
                )
                ERR-ESCROW-NOT-FOUND
            )
        )
    )
)

;; Admin functions
(define-public (add-supported-token (token-contract principal) (token-name (string-ascii 32)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-token-name token-name) ERR-INVALID-TOKEN-NAME)
        
        (let ((token-key { token-contract: token-contract }))
            ;; Check if token already exists to prevent overwriting
            (match (map-get? supported-tokens token-key)
                existing-token ERR-ESCROW-ALREADY-EXISTS
                (begin
                    (map-set supported-tokens
                        token-key
                        {
                            token-name: token-name,
                            is-active: true,
                            added-at: stacks-block-height
                        }
                    )
                    (ok true)
                )
            )
        )
    )
)

(define-public (toggle-token-status (token-contract principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        (let ((token-key { token-contract: token-contract }))
            (match (map-get? supported-tokens token-key)
                token-data
                (begin
                    (map-set supported-tokens
                        token-key
                        (merge token-data { is-active: (not (get is-active token-data)) })
                    )
                    (ok true)
                )
                ERR-TOKEN-NOT-FOUND
            )
        )
    )
)