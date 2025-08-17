;; Token-Based Voting System
;; A decentralized voting system where voting power is determined by token balance
;; Users can create proposals and vote with power proportional to their token holdings

;; Define the governance token
(define-fungible-token governance-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-proposal (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-voting-ended (err u104))
(define-constant err-invalid-amount (err u105))

;; Data variables
(define-data-var proposal-counter uint u0)
(define-data-var total-supply uint u1000000) ;; Initial supply of 1M tokens

;; Data structures
(define-map proposals
    uint
    {
        title: (string-ascii 100),
        description: (string-ascii 500),
        creator: principal,
        yes-votes: uint,
        no-votes: uint,
        end-block: uint,
        active: bool
    }
)

(define-map votes
    {proposal-id: uint, voter: principal}
    {vote: bool, power: uint}
)

;; Initialize contract with tokens for the owner
(define-private (initialize-contract)
    (begin
        (try! (ft-mint? governance-token (var-get total-supply) contract-owner))
        (ok true)
    )
)

;; Function 1: Create a new proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-duration uint))
    (let
        (
            (proposal-id (+ (var-get proposal-counter) u1))
            (end-block (+ block-height voting-duration))
        )
        (begin
            ;; Ensure caller has at least some tokens to create proposal
            (asserts! (> (ft-get-balance governance-token tx-sender) u0) err-insufficient-balance)
            
            ;; Create the proposal
            (map-set proposals proposal-id
                {
                    title: title,
                    description: description,
                    creator: tx-sender,
                    yes-votes: u0,
                    no-votes: u0,
                    end-block: end-block,
                    active: true
                }
            )
            
            ;; Update proposal counter
            (var-set proposal-counter proposal-id)
            
            ;; Print event for indexing
            (print {
                event: "proposal-created",
                proposal-id: proposal-id,
                title: title,
                creator: tx-sender,
                end-block: end-block
            })
            
            (ok proposal-id)
        )
    )
)

;; Function 2: Vote on a proposal with token-weighted power
(define-public (vote (proposal-id uint) (support bool))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) err-invalid-proposal))
            (voter-balance (ft-get-balance governance-token tx-sender))
            (vote-key {proposal-id: proposal-id, voter: tx-sender})
            (existing-vote (map-get? votes vote-key))
        )
        (begin
            ;; Ensure proposal exists and is active
            (asserts! (get active proposal) err-invalid-proposal)
            
            ;; Ensure voting period hasn't ended
            (asserts! (<= block-height (get end-block proposal)) err-voting-ended)
            
            ;; Ensure voter hasn't already voted
            (asserts! (is-none existing-vote) err-already-voted)
            
            ;; Ensure voter has tokens (voting power)
            (asserts! (> voter-balance u0) err-insufficient-balance)
            
            ;; Record the vote with voting power
            (map-set votes vote-key
                {
                    vote: support,
                    power: voter-balance
                }
            )
            
            ;; Update proposal vote counts
            (map-set proposals proposal-id
                (merge proposal
                    (if support
                        {yes-votes: (+ (get yes-votes proposal) voter-balance)}
                        {no-votes: (+ (get no-votes proposal) voter-balance)}
                    )
                )
            )
            
            ;; Print event for indexing
            (print {
                event: "vote-cast",
                proposal-id: proposal-id,
                voter: tx-sender,
                support: support,
                voting-power: voter-balance
            })
            
            (ok true)
        )
    )
)

;; Read-only functions for querying data

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get vote details
(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

;; Get voter's token balance (voting power)
(define-read-only (get-voting-power (voter principal))
    (ft-get-balance governance-token voter)
)

;; Get total number of proposals
(define-read-only (get-proposal-count)
    (var-get proposal-counter)
)

;; Transfer tokens (affects voting power)
(define-public (transfer-tokens (amount uint) (recipient principal))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-transfer? governance-token amount tx-sender recipient))
        (ok true)
    )
)

;; Initialize the contract (should be called once after deployment)
(define-public (init)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (try! (initialize-contract))
        (ok true)
    )
)