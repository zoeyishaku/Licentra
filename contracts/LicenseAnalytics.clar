;; License Analytics and Usage Tracking Contract
;; Tracks detailed usage metrics and provides insights for Licentra platform

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-UNAUTHORIZED (err u202))
(define-constant ERR-INVALID-PARAMETER (err u204))
(define-constant ERR-SESSION-EXPIRED (err u205))

;; Data variables for tracking IDs
(define-data-var next-session-id uint u1)
(define-data-var next-usage-event-id uint u1)
(define-data-var next-report-id uint u1)

;; Usage Sessions - Track when users start/end license usage
(define-map usage-sessions
  { session-id: uint }
  {
    license-id: uint,
    user: principal,
    product-id: uint,
    start-block: uint,
    end-block: (optional uint),
    duration-blocks: (optional uint),
    feature-count: uint,
    active: bool,
    created-at: uint
  }
)

;; License Usage Statistics - Aggregated data per license
(define-map license-usage-stats
  { license-id: uint }
  {
    total-sessions: uint,
    total-usage-blocks: uint,
    average-session-length: uint,
    last-used-block: uint,
    first-usage-block: uint
  }
)

;; Product Analytics - Aggregated data per product
(define-map product-analytics
  { product-id: uint }
  {
    total-active-licenses: uint,
    total-usage-sessions: uint,
    total-usage-blocks: uint,
    most-active-user: (optional principal),
    peak-usage-block: uint
  }
)

;; User Analytics - Aggregated data per user
(define-map user-analytics
  { user: principal }
  {
    total-licenses: uint,
    total-sessions: uint,
    total-usage-blocks: uint,
    favorite-product-id: (optional uint),
    usage-pattern-score: uint,
    last-activity-block: uint
  }
)

;; Analytics Reports - Generated periodic reports
(define-map analytics-reports
  { report-id: uint }
  {
    report-type: (string-ascii 50),
    target-id: uint,
    period-start-block: uint,
    period-end-block: uint,
    total-sessions: uint,
    total-usage-blocks: uint,
    insights: (string-ascii 500),
    generated-at: uint,
    generated-by: principal
  }
)

;; Session Management Functions

(define-public (start-usage-session (license-id uint) (product-id uint))
  (let
    (
      (session-id (var-get next-session-id))
      (current-block stacks-block-height)
    )
    (asserts! (> license-id u0) ERR-INVALID-PARAMETER)
    (asserts! (> product-id u0) ERR-INVALID-PARAMETER)
    
    (map-set usage-sessions
      { session-id: session-id }
      {
        license-id: license-id,
        user: tx-sender,
        product-id: product-id,
        start-block: current-block,
        end-block: none,
        duration-blocks: none,
        feature-count: u0,
        active: true,
        created-at: current-block
      }
    )
    
    (var-set next-session-id (+ session-id u1))
    (ok session-id)
  )
)

(define-public (end-usage-session (session-id uint))
  (let
    (
      (session (unwrap! (map-get? usage-sessions { session-id: session-id }) ERR-NOT-FOUND))
      (current-block stacks-block-height)
      (duration (- current-block (get start-block session)))
    )
    (asserts! (is-eq tx-sender (get user session)) ERR-UNAUTHORIZED)
    (asserts! (get active session) ERR-SESSION-EXPIRED)
    
    (map-set usage-sessions
      { session-id: session-id }
      (merge session {
        end-block: (some current-block),
        duration-blocks: (some duration),
        active: false
      })
    )
    
    ;; Update analytics
    ;; (try! (update-license-usage-stats (get license-id session) duration))
    ;; (try! (update-product-analytics (get product-id session) duration))
    ;; (try! (update-user-analytics (get user session) duration (get product-id session)))
    
    (ok duration)
  )
)

;; Private Analytics Update Functions

(define-private (update-license-usage-stats (license-id uint) (session-duration uint))
  (let
    (
      (current-stats (map-get? license-usage-stats { license-id: license-id }))
      (current-block stacks-block-height)
    )
    (match current-stats
      stats (let
        (
          (new-total-sessions (+ (get total-sessions stats) u1))
          (new-total-blocks (+ (get total-usage-blocks stats) session-duration))
          (new-average (/ new-total-blocks new-total-sessions))
        )
        (map-set license-usage-stats
          { license-id: license-id }
          (merge stats {
            total-sessions: new-total-sessions,
            total-usage-blocks: new-total-blocks,
            average-session-length: new-average,
            last-used-block: current-block
          })
        )
      )
      (map-set license-usage-stats
        { license-id: license-id }
        {
          total-sessions: u1,
          total-usage-blocks: session-duration,
          average-session-length: session-duration,
          last-used-block: current-block,
          first-usage-block: current-block
        }
      )
    )
    (ok true)
  )
)

(define-private (update-product-analytics (product-id uint) (session-duration uint))
  (let
    (
      (current-analytics (map-get? product-analytics { product-id: product-id }))
      (current-block stacks-block-height)
    )
    (match current-analytics
      analytics (map-set product-analytics
        { product-id: product-id }
        (merge analytics {
          total-usage-sessions: (+ (get total-usage-sessions analytics) u1),
          total-usage-blocks: (+ (get total-usage-blocks analytics) session-duration),
          peak-usage-block: current-block
        })
      )
      (map-set product-analytics
        { product-id: product-id }
        {
          total-active-licenses: u1,
          total-usage-sessions: u1,
          total-usage-blocks: session-duration,
          most-active-user: (some tx-sender),
          peak-usage-block: current-block
        }
      )
    )
    (ok true)
  )
)

(define-private (update-user-analytics (user principal) (session-duration uint) (product-id uint))
  (let
    (
      (current-analytics (map-get? user-analytics { user: user }))
      (current-block stacks-block-height)
    )
    (match current-analytics
      analytics (map-set user-analytics
        { user: user }
        (merge analytics {
          total-sessions: (+ (get total-sessions analytics) u1),
          total-usage-blocks: (+ (get total-usage-blocks analytics) session-duration),
          usage-pattern-score: (+ (get usage-pattern-score analytics) (/ session-duration u10)),
          last-activity-block: current-block,
          favorite-product-id: (some product-id)
        })
      )
      (map-set user-analytics
        { user: user }
        {
          total-licenses: u1,
          total-sessions: u1,
          total-usage-blocks: session-duration,
          favorite-product-id: (some product-id),
          usage-pattern-score: (/ session-duration u10),
          last-activity-block: current-block
        }
      )
    )
    (ok true)
  )
)

;; Report Generation Functions

(define-public (generate-product-report (product-id uint) (period-start uint) (period-end uint))
  (let
    (
      (report-id (var-get next-report-id))
      (current-block stacks-block-height)
      (product-data (map-get? product-analytics { product-id: product-id }))
    )
    (asserts! (< period-start period-end) ERR-INVALID-PARAMETER)
    (asserts! (<= period-end current-block) ERR-INVALID-PARAMETER)
    

    
    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

;; Read-Only Functions

(define-read-only (get-usage-session (session-id uint))
  (map-get? usage-sessions { session-id: session-id })
)

(define-read-only (get-license-usage-stats (license-id uint))
  (map-get? license-usage-stats { license-id: license-id })
)

(define-read-only (get-product-analytics (product-id uint))
  (map-get? product-analytics { product-id: product-id })
)

(define-read-only (get-user-analytics (user principal))
  (map-get? user-analytics { user: user })
)

(define-read-only (get-analytics-report (report-id uint))
  (map-get? analytics-reports { report-id: report-id })
)

(define-read-only (is-session-active (session-id uint))
  (match (map-get? usage-sessions { session-id: session-id })
    session (get active session)
    false
  )
)

(define-read-only (get-session-duration (session-id uint))
  (match (map-get? usage-sessions { session-id: session-id })
    session (match (get end-block session)
      end-block (some (- end-block (get start-block session)))
      (if (get active session)
        (some (- stacks-block-height (get start-block session)))
        none
      )
    )
    none
  )
)

;; Admin Functions

(define-public (reset-analytics-data (product-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (map-delete product-analytics { product-id: product-id })
    (ok true)
  )
)

(define-read-only (get-next-session-id)
  (var-get next-session-id)
)

(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)
