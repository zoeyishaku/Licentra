(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-UNAUTHORIZED (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-DURATION (err u104))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u105))
(define-constant ERR-LICENSE-EXPIRED (err u106))
(define-constant ERR-INVALID-PRODUCT (err u107))
(define-constant ERR-LICENSE-REVOKED (err u108))
(define-constant ERR-LISTING-NOT-FOUND (err u109))
(define-constant ERR-BID-NOT-FOUND (err u110))
(define-constant ERR-INSUFFICIENT-BID (err u111))
(define-constant ERR-LISTING-EXPIRED (err u112))
(define-constant ERR-CANNOT-BID-OWN-LISTING (err u113))
(define-constant ERR-LISTING-NOT-ACTIVE (err u114))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u115))
(define-constant ERR-SUBSCRIPTION-INACTIVE (err u116))
(define-constant ERR-SUBSCRIPTION-EXPIRED (err u117))
(define-constant ERR-INVALID-BILLING-CYCLE (err u118))
(define-constant ERR-SUBSCRIPTION-PAUSED (err u119))

(define-data-var next-product-id uint u1)
(define-data-var next-listing-id uint u1)
(define-data-var next-bid-id uint u1)
(define-data-var next-license-id uint u1)
(define-data-var next-subscription-id uint u1)

(define-map products
  { product-id: uint }
  {
    owner: principal,
    name: (string-ascii 100),
    description: (string-ascii 500),
    price-per-block: uint,
    active: bool,
    created-at: uint
  }
)

(define-map licenses
  { license-id: uint }
  {
    product-id: uint,
    licensee: principal,
    start-block: uint,
    end-block: uint,
    active: bool,
    revoked: bool,
    created-at: uint
  }
)

(define-map user-licenses
  { user: principal, product-id: uint }
  { license-id: uint }
)

(define-map product-revenues
  { product-id: uint }
  { total-revenue: uint }
)

(define-map license-listings
  { listing-id: uint }
  {
    license-id: uint,
    seller: principal,
    price: uint,
    expires-at: uint,
    active: bool,
    created-at: uint
  }
)

(define-map license-bids
  { bid-id: uint }
  {
    listing-id: uint,
    bidder: principal,
    amount: uint,
    expires-at: uint,
    active: bool,
    created-at: uint
  }
)

(define-map listing-highest-bid
  { listing-id: uint }
  { bid-id: uint, amount: uint }
)

(define-map user-listings
  { user: principal, license-id: uint }
  { listing-id: uint }
)

(define-map subscriptions
  { subscription-id: uint }
  {
    product-id: uint,
    subscriber: principal,
    billing-cycle-blocks: uint,
    price-per-cycle: uint,
    start-block: uint,
    last-billing-block: uint,
    next-billing-block: uint,
    active: bool,
    paused: bool,
    grace-period-blocks: uint,
    auto-renew: bool,
    created-at: uint
  }
)

(define-map user-subscriptions
  { user: principal, product-id: uint }
  { subscription-id: uint }
)

(define-map subscription-billing-history
  { subscription-id: uint, billing-cycle: uint }
  {
    amount: uint,
    billing-block: uint,
    success: bool
  }
)

(define-public (create-product (name (string-ascii 100)) (description (string-ascii 500)) (price-per-block uint))
  (let
    (
      (product-id (var-get next-product-id))
      (current-block stacks-block-height)
    )
    (asserts! (> price-per-block u0) ERR-INVALID-DURATION)
    (map-set products
      { product-id: product-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        price-per-block: price-per-block,
        active: true,
        created-at: current-block
      }
    )
    (var-set next-product-id (+ product-id u1))
    (ok product-id)
  )
)

(define-public (purchase-license (product-id uint) (duration-blocks uint))
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (license-id (var-get next-license-id))
      (current-block stacks-block-height)
      (end-block (+ current-block duration-blocks))
      (total-cost (* (get price-per-block product) duration-blocks))
      (existing-license (map-get? user-licenses { user: tx-sender, product-id: product-id }))
    )
    (asserts! (get active product) ERR-INVALID-PRODUCT)
    (asserts! (> duration-blocks u0) ERR-INVALID-DURATION)
    (asserts! (is-none existing-license) ERR-ALREADY-EXISTS)
    
    (try! (stx-transfer? total-cost tx-sender (get owner product)))
    
    (map-set licenses
      { license-id: license-id }
      {
        product-id: product-id,
        licensee: tx-sender,
        start-block: current-block,
        end-block: end-block,
        active: true,
        revoked: false,
        created-at: current-block
      }
    )
    
    (map-set user-licenses
      { user: tx-sender, product-id: product-id }
      { license-id: license-id }
    )
    
    (let
      (
        (current-revenue (default-to u0 (get total-revenue (map-get? product-revenues { product-id: product-id }))))
      )
      (map-set product-revenues
        { product-id: product-id }
        { total-revenue: (+ current-revenue total-cost) }
      )
    )
    
    (var-set next-license-id (+ license-id u1))
    (ok license-id)
  )
)

(define-public (extend-license (product-id uint) (additional-blocks uint))
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (user-license-entry (unwrap! (map-get? user-licenses { user: tx-sender, product-id: product-id }) ERR-NOT-FOUND))
      (license-id (get license-id user-license-entry))
      (license (unwrap! (map-get? licenses { license-id: license-id }) ERR-NOT-FOUND))
      (additional-cost (* (get price-per-block product) additional-blocks))
      (new-end-block (+ (get end-block license) additional-blocks))
    )
    (asserts! (get active product) ERR-INVALID-PRODUCT)
    (asserts! (get active license) ERR-LICENSE-REVOKED)
    (asserts! (not (get revoked license)) ERR-LICENSE-REVOKED)
    (asserts! (> additional-blocks u0) ERR-INVALID-DURATION)
    
    (try! (stx-transfer? additional-cost tx-sender (get owner product)))
    
    (map-set licenses
      { license-id: license-id }
      (merge license { end-block: new-end-block })
    )
    
    (let
      (
        (current-revenue (default-to u0 (get total-revenue (map-get? product-revenues { product-id: product-id }))))
      )
      (map-set product-revenues
        { product-id: product-id }
        { total-revenue: (+ current-revenue additional-cost) }
      )
    )
    
    (ok new-end-block)
  )
)

(define-public (revoke-license (license-id uint))
  (let
    (
      (license (unwrap! (map-get? licenses { license-id: license-id }) ERR-NOT-FOUND))
      (product-id (get product-id license))
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner product)) ERR-UNAUTHORIZED)
    (asserts! (get active license) ERR-LICENSE-REVOKED)
    (asserts! (not (get revoked license)) ERR-LICENSE-REVOKED)
    
    (map-set licenses
      { license-id: license-id }
      (merge license { revoked: true, active: false })
    )
    (ok true)
  )
)

(define-public (deactivate-product (product-id uint))
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner product)) ERR-UNAUTHORIZED)
    
    (map-set products
      { product-id: product-id }
      (merge product { active: false })
    )
    (ok true)
  )
)

(define-public (update-product-price (product-id uint) (new-price-per-block uint))
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner product)) ERR-UNAUTHORIZED)
    (asserts! (> new-price-per-block u0) ERR-INVALID-DURATION)
    
    (map-set products
      { product-id: product-id }
      (merge product { price-per-block: new-price-per-block })
    )
    (ok true)
  )
)

(define-read-only (get-product (product-id uint))
  (map-get? products { product-id: product-id })
)

(define-read-only (get-license (license-id uint))
  (map-get? licenses { license-id: license-id })
)

(define-read-only (get-user-license (user principal) (product-id uint))
  (match (map-get? user-licenses { user: user, product-id: product-id })
    license-entry (map-get? licenses { license-id: (get license-id license-entry) })
    none
  )
)

(define-read-only (is-license-valid (user principal) (product-id uint))
  (match (get-user-license user product-id)
    license (and
      (get active license)
      (not (get revoked license))
      (>= (get end-block license) stacks-block-height)
    )
    false
  )
)

(define-read-only (get-license-remaining-blocks (user principal) (product-id uint))
  (match (get-user-license user product-id)
    license (if (and (get active license) (not (get revoked license)))
      (if (>= (get end-block license) stacks-block-height)
        (some (- (get end-block license) stacks-block-height))
        (some u0)
      )
      none
    )
    none
  )
)

(define-read-only (get-product-revenue (product-id uint))
  (default-to u0 (get total-revenue (map-get? product-revenues { product-id: product-id })))
)

(define-read-only (get-next-product-id)
  (var-get next-product-id)
)

(define-read-only (get-next-license-id)
  (var-get next-license-id)
)

(define-read-only (get-contract-owner)
  CONTRACT-OWNER
)

(define-public (list-license-for-sale (license-id uint) (price uint) (expires-blocks uint))
  (let
    (
      (license (unwrap! (map-get? licenses { license-id: license-id }) ERR-NOT-FOUND))
      (listing-id (var-get next-listing-id))
      (current-block stacks-block-height)
      (expires-at (+ current-block expires-blocks))
      (existing-listing (map-get? user-listings { user: tx-sender, license-id: license-id }))
    )
    (asserts! (is-eq tx-sender (get licensee license)) ERR-UNAUTHORIZED)
    (asserts! (get active license) ERR-LICENSE-REVOKED)
    (asserts! (not (get revoked license)) ERR-LICENSE-REVOKED)
    (asserts! (> (get end-block license) current-block) ERR-LICENSE-EXPIRED)
    (asserts! (> price u0) ERR-INVALID-DURATION)
    (asserts! (> expires-blocks u0) ERR-INVALID-DURATION)
    (asserts! (is-none existing-listing) ERR-ALREADY-EXISTS)
    
    (map-set license-listings
      { listing-id: listing-id }
      {
        license-id: license-id,
        seller: tx-sender,
        price: price,
        expires-at: expires-at,
        active: true,
        created-at: current-block
      }
    )
    
    (map-set user-listings
      { user: tx-sender, license-id: license-id }
      { listing-id: listing-id }
    )
    
    (var-set next-listing-id (+ listing-id u1))
    (ok listing-id)
  )
)

(define-public (cancel-listing (listing-id uint))
  (let
    (
      (listing (unwrap! (map-get? license-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get seller listing)) ERR-UNAUTHORIZED)
    (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE)
    
    (map-set license-listings
      { listing-id: listing-id }
      (merge listing { active: false })
    )
    
    (map-delete user-listings { user: tx-sender, license-id: (get license-id listing) })
    (ok true)
  )
)

(define-public (buy-license-direct (listing-id uint))
  (let
    (
      (listing (unwrap! (map-get? license-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
      (license-id (get license-id listing))
      (license (unwrap! (map-get? licenses { license-id: license-id }) ERR-NOT-FOUND))
      (seller (get seller listing))
      (price (get price listing))
      (current-block stacks-block-height)
    )
    (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE)
    (asserts! (< current-block (get expires-at listing)) ERR-LISTING-EXPIRED)
    (asserts! (get active license) ERR-LICENSE-REVOKED)
    (asserts! (not (get revoked license)) ERR-LICENSE-REVOKED)
    (asserts! (> (get end-block license) current-block) ERR-LICENSE-EXPIRED)
    (asserts! (not (is-eq tx-sender seller)) ERR-UNAUTHORIZED)
    
    (try! (stx-transfer? price tx-sender seller))
    
    (map-set licenses
      { license-id: license-id }
      (merge license { licensee: tx-sender })
    )
    
    (map-delete user-licenses { user: seller, product-id: (get product-id license) })
    (map-set user-licenses
      { user: tx-sender, product-id: (get product-id license) }
      { license-id: license-id }
    )
    
    (map-set license-listings
      { listing-id: listing-id }
      (merge listing { active: false })
    )
    
    (map-delete user-listings { user: seller, license-id: license-id })
    (ok true)
  )
)

(define-public (place-bid (listing-id uint) (amount uint) (expires-blocks uint))
  (let
    (
      (listing (unwrap! (map-get? license-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
      (bid-id (var-get next-bid-id))
      (current-block stacks-block-height)
      (expires-at (+ current-block expires-blocks))
      (current-highest (map-get? listing-highest-bid { listing-id: listing-id }))
    )
    (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE)
    (asserts! (< current-block (get expires-at listing)) ERR-LISTING-EXPIRED)
    (asserts! (not (is-eq tx-sender (get seller listing))) ERR-CANNOT-BID-OWN-LISTING)
    (asserts! (> amount u0) ERR-INVALID-DURATION)
    (asserts! (> expires-blocks u0) ERR-INVALID-DURATION)
    
    (match current-highest
      highest-bid (asserts! (> amount (get amount highest-bid)) ERR-INSUFFICIENT-BID)
      true
    )
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set license-bids
      { bid-id: bid-id }
      {
        listing-id: listing-id,
        bidder: tx-sender,
        amount: amount,
        expires-at: expires-at,
        active: true,
        created-at: current-block
      }
    )
    
    (map-set listing-highest-bid
      { listing-id: listing-id }
      { bid-id: bid-id, amount: amount }
    )
    
    (var-set next-bid-id (+ bid-id u1))
    (ok bid-id)
  )
)

(define-public (accept-bid (listing-id uint) (bid-id uint))
  (let
    (
      (listing (unwrap! (map-get? license-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
      (bid (unwrap! (map-get? license-bids { bid-id: bid-id }) ERR-BID-NOT-FOUND))
      (license-id (get license-id listing))
      (license (unwrap! (map-get? licenses { license-id: license-id }) ERR-NOT-FOUND))
      (seller (get seller listing))
      (bidder (get bidder bid))
      (amount (get amount bid))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender seller) ERR-UNAUTHORIZED)
    (asserts! (get active listing) ERR-LISTING-NOT-ACTIVE)
    (asserts! (get active bid) ERR-BID-NOT-FOUND)
    (asserts! (is-eq listing-id (get listing-id bid)) ERR-BID-NOT-FOUND)
    (asserts! (< current-block (get expires-at bid)) ERR-LISTING-EXPIRED)
    (asserts! (get active license) ERR-LICENSE-REVOKED)
    (asserts! (not (get revoked license)) ERR-LICENSE-REVOKED)
    (asserts! (> (get end-block license) current-block) ERR-LICENSE-EXPIRED)
    
    (try! (as-contract (stx-transfer? amount tx-sender seller)))
    
    (map-set licenses
      { license-id: license-id }
      (merge license { licensee: bidder })
    )
    
    (map-delete user-licenses { user: seller, product-id: (get product-id license) })
    (map-set user-licenses
      { user: bidder, product-id: (get product-id license) }
      { license-id: license-id }
    )
    
    (map-set license-listings
      { listing-id: listing-id }
      (merge listing { active: false })
    )
    
    (map-set license-bids
      { bid-id: bid-id }
      (merge bid { active: false })
    )
    
    (map-delete user-listings { user: seller, license-id: license-id })
    (map-delete listing-highest-bid { listing-id: listing-id })
    (ok true)
  )
)

(define-public (withdraw-bid (bid-id uint))
  (let
    (
      (bid (unwrap! (map-get? license-bids { bid-id: bid-id }) ERR-BID-NOT-FOUND))
      (amount (get amount bid))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get bidder bid)) ERR-UNAUTHORIZED)
    (asserts! (get active bid) ERR-BID-NOT-FOUND)
    (asserts! (>= current-block (get expires-at bid)) ERR-LISTING-EXPIRED)
    
    (try! (as-contract (stx-transfer? amount tx-sender (get bidder bid))))
    
    (map-set license-bids
      { bid-id: bid-id }
      (merge bid { active: false })
    )
    (ok true)
  )
)

(define-read-only (get-listing (listing-id uint))
  (map-get? license-listings { listing-id: listing-id })
)

(define-read-only (get-bid (bid-id uint))
  (map-get? license-bids { bid-id: bid-id })
)

(define-read-only (get-listing-highest-bid (listing-id uint))
  (map-get? listing-highest-bid { listing-id: listing-id })
)

(define-read-only (get-user-listing (user principal) (license-id uint))
  (map-get? user-listings { user: user, license-id: license-id })
)

(define-read-only (get-next-listing-id)
  (var-get next-listing-id)
)

(define-read-only (get-next-bid-id)
  (var-get next-bid-id)
)

(define-public (create-subscription (product-id uint) (billing-cycle-blocks uint) (price-per-cycle uint) (grace-period-blocks uint) (auto-renew bool))
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (subscription-id (var-get next-subscription-id))
      (current-block stacks-block-height)
      (next-billing-block (+ current-block billing-cycle-blocks))
      (existing-subscription (map-get? user-subscriptions { user: tx-sender, product-id: product-id }))
    )
    (asserts! (get active product) ERR-INVALID-PRODUCT)
    (asserts! (> billing-cycle-blocks u0) ERR-INVALID-BILLING-CYCLE)
    (asserts! (> price-per-cycle u0) ERR-INVALID-DURATION)
    (asserts! (is-none existing-subscription) ERR-ALREADY-EXISTS)
    
    (try! (stx-transfer? price-per-cycle tx-sender (get owner product)))
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      {
        product-id: product-id,
        subscriber: tx-sender,
        billing-cycle-blocks: billing-cycle-blocks,
        price-per-cycle: price-per-cycle,
        start-block: current-block,
        last-billing-block: current-block,
        next-billing-block: next-billing-block,
        active: true,
        paused: false,
        grace-period-blocks: grace-period-blocks,
        auto-renew: auto-renew,
        created-at: current-block
      }
    )
    
    (map-set user-subscriptions
      { user: tx-sender, product-id: product-id }
      { subscription-id: subscription-id }
    )
    
    (map-set subscription-billing-history
      { subscription-id: subscription-id, billing-cycle: u1 }
      {
        amount: price-per-cycle,
        billing-block: current-block,
        success: true
      }
    )
    
    (var-set next-subscription-id (+ subscription-id u1))
    (ok subscription-id)
  )
)

(define-public (renew-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (map-get? subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND))
      (product-id (get product-id subscription))
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (current-block stacks-block-height)
      (next-billing (+ (get next-billing-block subscription) (get billing-cycle-blocks subscription)))
      (grace-period-end (+ (get next-billing-block subscription) (get grace-period-blocks subscription)))
      (billing-cycle-count (+ (/ (- current-block (get start-block subscription)) (get billing-cycle-blocks subscription)) u1))
    )
    (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
    (asserts! (not (get paused subscription)) ERR-SUBSCRIPTION-PAUSED)
    (asserts! (>= current-block (get next-billing-block subscription)) ERR-SUBSCRIPTION-EXPIRED)
    (asserts! (<= current-block grace-period-end) ERR-SUBSCRIPTION-EXPIRED)
    
    (try! (stx-transfer? (get price-per-cycle subscription) tx-sender (get owner product)))
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      (merge subscription {
        last-billing-block: current-block,
        next-billing-block: next-billing
      })
    )
    
    (map-set subscription-billing-history
      { subscription-id: subscription-id, billing-cycle: billing-cycle-count }
      {
        amount: (get price-per-cycle subscription),
        billing-block: current-block,
        success: true
      }
    )
    
    (ok next-billing)
  )
)

(define-public (pause-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (map-get? subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) ERR-UNAUTHORIZED)
    (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
    (asserts! (not (get paused subscription)) ERR-SUBSCRIPTION-PAUSED)
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      (merge subscription { paused: true })
    )
    (ok true)
  )
)

(define-public (resume-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (map-get? subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND))
      (current-block stacks-block-height)
      (new-next-billing (+ current-block (get billing-cycle-blocks subscription)))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) ERR-UNAUTHORIZED)
    (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
    (asserts! (get paused subscription) ERR-SUBSCRIPTION-PAUSED)
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      (merge subscription {
        paused: false,
        next-billing-block: new-next-billing
      })
    )
    (ok new-next-billing)
  )
)

(define-public (cancel-subscription (subscription-id uint))
  (let
    (
      (subscription (unwrap! (map-get? subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) ERR-UNAUTHORIZED)
    (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      (merge subscription { active: false })
    )
    
    (map-delete user-subscriptions { user: tx-sender, product-id: (get product-id subscription) })
    (ok true)
  )
)

(define-public (update-subscription-settings (subscription-id uint) (auto-renew bool) (grace-period-blocks uint))
  (let
    (
      (subscription (unwrap! (map-get? subscriptions { subscription-id: subscription-id }) ERR-SUBSCRIPTION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get subscriber subscription)) ERR-UNAUTHORIZED)
    (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
    
    (map-set subscriptions
      { subscription-id: subscription-id }
      (merge subscription {
        auto-renew: auto-renew,
        grace-period-blocks: grace-period-blocks
      })
    )
    (ok true)
  )
)

(define-read-only (get-subscription (subscription-id uint))
  (map-get? subscriptions { subscription-id: subscription-id })
)

(define-read-only (get-user-subscription (user principal) (product-id uint))
  (match (map-get? user-subscriptions { user: user, product-id: product-id })
    subscription-entry (map-get? subscriptions { subscription-id: (get subscription-id subscription-entry) })
    none
  )
)

(define-read-only (is-subscription-active (user principal) (product-id uint))
  (match (get-user-subscription user product-id)
    subscription (and
      (get active subscription)
      (not (get paused subscription))
      (> (+ (get next-billing-block subscription) (get grace-period-blocks subscription)) stacks-block-height)
    )
    false
  )
)

(define-read-only (get-subscription-billing-history (subscription-id uint) (billing-cycle uint))
  (map-get? subscription-billing-history { subscription-id: subscription-id, billing-cycle: billing-cycle })
)

(define-read-only (get-next-subscription-id)
  (var-get next-subscription-id)
)

