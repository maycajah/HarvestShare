;; HarvestShare - Decentralized Crop Insurance & Yield Prediction Marketplace
;; Aligns with SDG 2: Zero Hunger & SDG 13: Climate Action
;; Enables farmers to hedge crop risks and community to invest in local agriculture

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-season-active (err u105))
(define-constant err-season-not-active (err u106))
(define-constant err-already-claimed (err u107))
(define-constant err-insufficient-pool (err u108))
(define-constant err-oracle-not-set (err u109))
(define-constant err-invalid-yield (err u110))
(define-constant err-coverage-exceeded (err u111))
(define-constant err-invalid-dates (err u112))

;; Data Variables
(define-data-var oracle-address (optional principal) none)
(define-data-var season-counter uint u0)
(define-data-var total-farmers uint u0)
(define-data-var total-coverage-provided uint u0)
(define-data-var platform-fee-percentage uint u30) ;; 3% platform fee
(define-data-var min-yield-threshold uint u70) ;; 70% of expected yield triggers payout

;; Data Maps
(define-map farmers
    principal
    {
        farm-id: (string-ascii 50),
        location: (string-ascii 100),
        total-hectares: uint,
        verified: bool,
        reputation-score: uint,
        seasons-participated: uint
    }
)

(define-map seasons
    uint ;; season-id
    {
        farmer: principal,
        crop-type: (string-ascii 30),
        hectares: uint,
        expected-yield-per-hectare: uint, ;; in kg
        coverage-amount: uint, ;; in microSTX
        premium-paid: uint,
        start-block: uint,
        end-block: uint,
        actual-yield: (optional uint),
        claim-paid: bool,
        supporters: (list 100 principal),
        total-pool: uint
    }
)

(define-map season-supporters
    {season-id: uint, supporter: principal}
    {
        amount-contributed: uint,
        potential-return: uint,
        paid-out: bool
    }
)

(define-map crop-yield-history
    {farmer: principal, crop-type: (string-ascii 30)}
    {
        total-seasons: uint,
        average-yield: uint,
        best-yield: uint,
        worst-yield: uint
    }
)

(define-map community-pools
    (string-ascii 30) ;; crop-type
    {
        total-liquidity: uint,
        active-coverage: uint,
        total-payouts: uint,
        supporter-count: uint
    }
)

;; Private Functions
(define-private (calculate-premium (coverage-amount uint) (reputation-score uint))
    (let
        (
            (base-rate u50) ;; 5% base premium
            (reputation-discount (if (> reputation-score u80) u10 u0))
            (final-rate (- base-rate reputation-discount))
        )
        (/ (* coverage-amount final-rate) u1000)
    )
)

(define-private (calculate-payout (expected-yield uint) (actual-yield uint) (coverage-amount uint))
    (let
        (
            (yield-percentage (/ (* actual-yield u100) expected-yield))
            (payout-percentage (if (< yield-percentage (var-get min-yield-threshold))
                                  (- u100 yield-percentage)
                                  u0))
        )
        (/ (* coverage-amount payout-percentage) u100)
    )
)

(define-private (distribute-returns (season-id uint) (total-return uint))
    (let
        (
            (season (unwrap! (map-get? seasons season-id) err-not-found))
            (platform-fee (/ (* total-return (var-get platform-fee-percentage)) u1000))
            (supporter-returns (- total-return platform-fee))
        )
        ;; Platform fee goes to contract owner
        (try! (as-contract (stx-transfer? platform-fee (as-contract tx-sender) contract-owner)))
        (ok supporter-returns)
    )
)

;; Public Functions

;; Farmer Registration
(define-public (register-farmer (farm-id (string-ascii 50)) (location (string-ascii 100)) (hectares uint))
    (begin
        (asserts! (is-none (map-get? farmers tx-sender)) err-already-exists)
        (asserts! (> hectares u0) err-invalid-amount)
        
        (map-set farmers tx-sender {
            farm-id: farm-id,
            location: location,
            total-hectares: hectares,
            verified: false,
            reputation-score: u50, ;; Start with neutral score
            seasons-participated: u0
        })
        
        (var-set total-farmers (+ (var-get total-farmers) u1))
        (ok true)
    )
)

;; Create Insurance Season
(define-public (create-season (crop-type (string-ascii 30)) 
                            (hectares uint)
                            (expected-yield-per-hectare uint)
                            (coverage-amount uint)
                            (duration-blocks uint))
    (let
        (
            (farmer-info (unwrap! (map-get? farmers tx-sender) err-not-found))
            (season-id (var-get season-counter))
            (premium (calculate-premium coverage-amount (get reputation-score farmer-info)))
            (start-block block-height)
            (end-block (+ block-height duration-blocks))
        )
        (asserts! (<= hectares (get total-hectares farmer-info)) err-invalid-amount)
        (asserts! (> expected-yield-per-hectare u0) err-invalid-amount)
        (asserts! (> coverage-amount u0) err-invalid-amount)
        (asserts! (> duration-blocks u1000) err-invalid-dates) ;; Minimum season length
        
        ;; Pay premium
        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
        
        (map-set seasons season-id {
            farmer: tx-sender,
            crop-type: crop-type,
            hectares: hectares,
            expected-yield-per-hectare: expected-yield-per-hectare,
            coverage-amount: coverage-amount,
            premium-paid: premium,
            start-block: start-block,
            end-block: end-block,
            actual-yield: none,
            claim-paid: false,
            supporters: (list),
            total-pool: premium
        })
        
        ;; Update farmer seasons
        (map-set farmers tx-sender 
            (merge farmer-info {seasons-participated: (+ (get seasons-participated farmer-info) u1)}))
        
        ;; Update community pool
        (let
            (
                (pool (default-to {total-liquidity: u0, active-coverage: u0, total-payouts: u0, supporter-count: u0}
                      (map-get? community-pools crop-type)))
            )
            (map-set community-pools crop-type
                (merge pool {
                    active-coverage: (+ (get active-coverage pool) coverage-amount)
                }))
        )
        
        (var-set season-counter (+ season-id u1))
        (ok season-id)
    )
)

;; Support a Season (Provide Coverage)
(define-public (support-season (season-id uint) (amount uint))
    (let
        (
            (season (unwrap! (map-get? seasons season-id) err-not-found))
            (potential-return (+ amount (/ (* amount u20) u100))) ;; 20% potential return
        )
        (asserts! (< block-height (get end-block season)) err-season-not-active)
        (asserts! (not (is-eq tx-sender (get farmer season))) err-unauthorized)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= (+ (get total-pool season) amount) 
                     (* (get coverage-amount season) u2)) err-coverage-exceeded) ;; Max 2x coverage
        
        ;; Transfer support amount
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update season
        (map-set seasons season-id
            (merge season {
                supporters: (unwrap! (as-max-len? (append (get supporters season) tx-sender) u100) err-coverage-exceeded),
                total-pool: (+ (get total-pool season) amount)
            }))
        
        ;; Record supporter contribution
        (map-set season-supporters {season-id: season-id, supporter: tx-sender} {
            amount-contributed: amount,
            potential-return: potential-return,
            paid-out: false
        })
        
        ;; Update community pool
        (let
            (
                (crop-type (get crop-type season))
                (pool (unwrap! (map-get? community-pools crop-type) err-not-found))
            )
            (map-set community-pools crop-type
                (merge pool {
                    total-liquidity: (+ (get total-liquidity pool) amount),
                    supporter-count: (+ (get supporter-count pool) u1)
                }))
        )
        
        (ok true)
    )
)

;; Oracle Reports Yield
(define-public (report-yield (season-id uint) (actual-yield-per-hectare uint))
    (let
        (
            (oracle (unwrap! (var-get oracle-address) err-oracle-not-set))
            (season (unwrap! (map-get? seasons season-id) err-not-found))
        )
        (asserts! (is-eq tx-sender oracle) err-unauthorized)
        (asserts! (>= block-height (get end-block season)) err-season-active)
        (asserts! (is-none (get actual-yield season)) err-already-claimed)
        
        (map-set seasons season-id
            (merge season {actual-yield: (some actual-yield-per-hectare)}))
        
        ;; Update yield history
        (let
            (
                (history-key {farmer: (get farmer season), crop-type: (get crop-type season)})
                (history (default-to {total-seasons: u0, average-yield: u0, best-yield: u0, worst-yield: u999999}
                        (map-get? crop-yield-history history-key)))
                (new-total-seasons (+ (get total-seasons history) u1))
                (new-average (/ (+ (* (get average-yield history) (get total-seasons history)) actual-yield-per-hectare) 
                               new-total-seasons))
            )
            (map-set crop-yield-history history-key {
                total-seasons: new-total-seasons,
                average-yield: new-average,
                best-yield: (if (> actual-yield-per-hectare (get best-yield history)) 
                               actual-yield-per-hectare 
                               (get best-yield history)),
                worst-yield: (if (< actual-yield-per-hectare (get worst-yield history)) 
                                actual-yield-per-hectare 
                                (get worst-yield history))
            })
        )
        
        (ok true)
    )
)

;; Process Season Claim
(define-public (process-claim (season-id uint))
    (let
        (
            (season (unwrap! (map-get? seasons season-id) err-not-found))
            (actual-yield (unwrap! (get actual-yield season) err-oracle-not-set))
            (total-expected-yield (* (get expected-yield-per-hectare season) (get hectares season)))
            (total-actual-yield (* actual-yield (get hectares season)))
            (payout (calculate-payout total-expected-yield total-actual-yield (get coverage-amount season)))
        )
        (asserts! (not (get claim-paid season)) err-already-claimed)
        (asserts! (is-eq tx-sender (get farmer season)) err-unauthorized)
        
        (if (> payout u0)
            ;; Pay out claim
            (begin
                (asserts! (<= payout (get total-pool season)) err-insufficient-pool)
                (try! (as-contract (stx-transfer? payout (as-contract tx-sender) (get farmer season))))
                
                ;; Update season
                (map-set seasons season-id (merge season {claim-paid: true}))
                
                ;; Update community pool
                (let
                    (
                        (pool (unwrap! (map-get? community-pools (get crop-type season)) err-not-found))
                    )
                    (map-set community-pools (get crop-type season)
                        (merge pool {
                            active-coverage: (- (get active-coverage pool) (get coverage-amount season)),
                            total-payouts: (+ (get total-payouts pool) payout)
                        }))
                )
                
                ;; Return remaining pool to supporters proportionally
                (let ((remaining-pool (- (get total-pool season) payout)))
                    (if (> remaining-pool u0)
                        (begin 
                            (try! (distribute-returns season-id remaining-pool))
                            (ok true)
                        )
                        (ok true)
                    )
                )
            )
            ;; Good harvest - reward supporters
            (begin
                (map-set seasons season-id (merge season {claim-paid: true}))
                
                ;; Distribute all pool funds to supporters as profit
                (try! (distribute-returns season-id (get total-pool season)))
                
                ;; Update farmer reputation
                (let
                    (
                        (farmer-info (unwrap! (map-get? farmers (get farmer season)) err-not-found))
                        (new-reputation (if (< (get reputation-score farmer-info) u95)
                                           (+ (get reputation-score farmer-info) u5)
                                           u100))
                    )
                    (map-set farmers (get farmer season)
                        (merge farmer-info {reputation-score: new-reputation}))
                )
                
                (ok true)
            )
        )
    )
)

;; Supporter Withdrawal
(define-public (withdraw-support (season-id uint))
    (let
        (
            (season (unwrap! (map-get? seasons season-id) err-not-found))
            (support-info (unwrap! (map-get? season-supporters {season-id: season-id, supporter: tx-sender}) err-not-found))
        )
        (asserts! (get claim-paid season) err-season-active)
        (asserts! (not (get paid-out support-info)) err-already-claimed)
        
        ;; Calculate proportional return
        (let
            (
                (proportion (/ (* (get amount-contributed support-info) u10000) (get total-pool season)))
                (return-amount (/ (* (get total-pool season) proportion) u10000))
            )
            (try! (as-contract (stx-transfer? return-amount (as-contract tx-sender) tx-sender)))
            
            (map-set season-supporters {season-id: season-id, supporter: tx-sender}
                (merge support-info {paid-out: true}))
            
            (ok return-amount)
        )
    )
)

;; Oracle Management
(define-public (set-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set oracle-address (some oracle))
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-farmer-info (farmer principal))
    (map-get? farmers farmer)
)

(define-read-only (get-season-info (season-id uint))
    (map-get? seasons season-id)
)

(define-read-only (get-support-info (season-id uint) (supporter principal))
    (map-get? season-supporters {season-id: season-id, supporter: supporter})
)

(define-read-only (get-crop-pool-info (crop-type (string-ascii 30)))
    (map-get? community-pools crop-type)
)

(define-read-only (get-yield-history (farmer principal) (crop-type (string-ascii 30)))
    (map-get? crop-yield-history {farmer: farmer, crop-type: crop-type})
)

(define-read-only (calculate-premium-quote (coverage-amount uint) (farmer principal))
    (match (map-get? farmers farmer)
        farmer-info (ok (calculate-premium coverage-amount (get reputation-score farmer-info)))
        (err err-not-found)
    )
)

(define-read-only (get-platform-stats)
    (ok {
        total-farmers: (var-get total-farmers),
        total-seasons: (var-get season-counter),
        total-coverage: (var-get total-coverage-provided),
        platform-fee: (var-get platform-fee-percentage),
        min-yield-threshold: (var-get min-yield-threshold)
    })
)