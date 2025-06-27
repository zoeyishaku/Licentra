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

(define-data-var next-product-id uint u1)
(define-data-var next-license-id uint u1)

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
