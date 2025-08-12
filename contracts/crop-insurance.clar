;; Crop Insurance Management Contract
;; Processes agricultural insurance claims based on weather data and yield reports

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-FARM-NOT-FOUND (err u401))
(define-constant ERR-CROP-NOT-FOUND (err u402))
(define-constant ERR-INVALID-AMOUNT (err u403))
(define-constant ERR-CLAIM-NOT-FOUND (err u404))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u405))
(define-constant ERR-INSUFFICIENT-COVERAGE (err u406))
(define-constant ERR-INVALID-YIELD (err u407))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var claim-counter uint u0)
(define-data-var total-crop-payouts uint u0)

;; Data Maps
(define-map crop-policies
  { policy-id: uint }
  {
    farmer: principal,
    farm-location: (string-ascii 100),
    crop-type: (string-ascii 30),
    acreage: uint,
    expected-yield: uint,
    coverage-per-acre: uint,
    premium-rate: uint,
    coordinates-lat: int,
    coordinates-lng: int,
    planting-date: uint,
    harvest-date: uint,
    active: bool,
    created-at: uint
  }
)

(define-map crop-claims
  { claim-id: uint }
  {
    policy-id: uint,
    farmer: principal,
    loss-type: (string-ascii 30),
    affected-acreage: uint,
    actual-yield: uint,
    loss-percentage: uint,
    weather-verified: bool,
    satellite-confirmed: bool,
    status: (string-ascii 20),
    payout-amount: uint,
    submitted-at: uint,
    processed-at: (optional uint)
  }
)

(define-map weather-events
  { coordinates-lat: int, coordinates-lng: int, date: uint }
  {
    event-type: (string-ascii 20),
    severity: uint,
    duration-hours: uint,
    temperature-min: int,
    temperature-max: int,
    precipitation: uint,
    wind-speed: uint,
    hail-size: uint
  }
)

(define-map yield-reports
  { policy-id: uint, harvest-date: uint }
  {
    actual-yield: uint,
    quality-grade: (string-ascii 10),
    moisture-content: uint,
    harvest-completed: bool,
    verified: bool
  }
)

;; Authorization check
(define-private (is-authorized)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Create crop insurance policy
(define-public (create-crop-policy (policy-id uint) (farm-location (string-ascii 100)) (crop-type (string-ascii 30)) (acreage uint) (expected-yield uint) (coverage-per-acre uint) (premium-rate uint) (coordinates-lat int) (coordinates-lng int) (planting-date uint) (harvest-date uint))
  (begin
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> acreage u0) ERR-INVALID-AMOUNT)
    (asserts! (> expected-yield u0) ERR-INVALID-YIELD)
    (asserts! (> coverage-per-acre u0) ERR-INVALID-AMOUNT)
    (asserts! (> harvest-date planting-date) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? crop-policies { policy-id: policy-id })) ERR-FARM-NOT-FOUND)

    (map-set crop-policies
      { policy-id: policy-id }
      {
        farmer: tx-sender,
        farm-location: farm-location,
        crop-type: crop-type,
        acreage: acreage,
        expected-yield: expected-yield,
        coverage-per-acre: coverage-per-acre,
        premium-rate: premium-rate,
        coordinates-lat: coordinates-lat,
        coordinates-lng: coordinates-lng,
        planting-date: planting-date,
        harvest-date: harvest-date,
        active: true,
        created-at: block-height
      }
    )
    (ok policy-id)
  )
)

;; Record weather event
(define-public (record-weather-event (coordinates-lat int) (coordinates-lng int) (event-type (string-ascii 20)) (severity uint) (duration-hours uint) (temperature-min int) (temperature-max int) (precipitation uint) (wind-speed uint) (hail-size uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (<= severity u10) ERR-INVALID-AMOUNT)
    (asserts! (<= duration-hours u168) ERR-INVALID-AMOUNT)

    (map-set weather-events
      { coordinates-lat: coordinates-lat, coordinates-lng: coordinates-lng, date: block-height }
      {
        event-type: event-type,
        severity: severity,
        duration-hours: duration-hours,
        temperature-min: temperature-min,
        temperature-max: temperature-max,
        precipitation: precipitation,
        wind-speed: wind-speed,
        hail-size: hail-size
      }
    )
    (ok true)
  )
)

;; Submit yield report
(define-public (submit-yield-report (policy-id uint) (actual-yield uint) (quality-grade (string-ascii 10)) (moisture-content uint))
  (let
    (
      (policy (unwrap! (map-get? crop-policies { policy-id: policy-id }) ERR-FARM-NOT-FOUND))
    )
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get farmer policy) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active policy) ERR-FARM-NOT-FOUND)
    (asserts! (<= moisture-content u100) ERR-INVALID-AMOUNT)

    (map-set yield-reports
      { policy-id: policy-id, harvest-date: (get harvest-date policy) }
      {
        actual-yield: actual-yield,
        quality-grade: quality-grade,
        moisture-content: moisture-content,
        harvest-completed: true,
        verified: false
      }
    )
    (ok true)
  )
)

;; Submit crop insurance claim
(define-public (submit-crop-claim (policy-id uint) (loss-type (string-ascii 30)) (affected-acreage uint) (actual-yield uint))
  (let
    (
      (policy (unwrap! (map-get? crop-policies { policy-id: policy-id }) ERR-FARM-NOT-FOUND))
      (claim-id (+ (var-get claim-counter) u1))
      (expected-yield (get expected-yield policy))
      (total-acreage (get acreage policy))
      (loss-percentage (if (> expected-yield actual-yield)
                        (/ (* (- expected-yield actual-yield) u100) expected-yield)
                        u0))
    )
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get farmer policy) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active policy) ERR-FARM-NOT-FOUND)
    (asserts! (<= affected-acreage total-acreage) ERR-INVALID-AMOUNT)
    (asserts! (> loss-percentage u10) ERR-INVALID-YIELD)

    (var-set claim-counter claim-id)

    (map-set crop-claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        farmer: tx-sender,
        loss-type: loss-type,
        affected-acreage: affected-acreage,
        actual-yield: actual-yield,
        loss-percentage: loss-percentage,
        weather-verified: false,
        satellite-confirmed: false,
        status: "submitted",
        payout-amount: u0,
        submitted-at: block-height,
        processed-at: none
      }
    )
    (ok claim-id)
  )
)

;; Process crop insurance claim
(define-public (process-crop-claim (claim-id uint) (weather-verified bool) (satellite-confirmed bool))
  (let
    (
      (claim (unwrap! (map-get? crop-claims { claim-id: claim-id }) ERR-CLAIM-NOT-FOUND))
      (policy (unwrap! (map-get? crop-policies { policy-id: (get policy-id claim) }) ERR-FARM-NOT-FOUND))
      (affected-acreage (get affected-acreage claim))
      (coverage-per-acre (get coverage-per-acre policy))
      (loss-percentage (get loss-percentage claim))
      (verification-bonus (if (and weather-verified satellite-confirmed) u20 u0))
      (adjusted-loss-percentage (+ loss-percentage verification-bonus))
      (max-payout (* affected-acreage coverage-per-acre))
      (payout-amount (/ (* max-payout adjusted-loss-percentage) u100))
    )
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status claim) "submitted") ERR-CLAIM-ALREADY-PROCESSED)

    ;; Update claim with processing results
    (map-set crop-claims
      { claim-id: claim-id }
      (merge claim {
        weather-verified: weather-verified,
        satellite-confirmed: satellite-confirmed,
        status: (if (> payout-amount u0) "approved" "denied"),
        payout-amount: payout-amount,
        processed-at: (some block-height)
      })
    )

    ;; Update total payouts
    (var-set total-crop-payouts (+ (var-get total-crop-payouts) payout-amount))

    (ok payout-amount)
  )
)

;; Get crop policy details
(define-read-only (get-crop-policy (policy-id uint))
  (map-get? crop-policies { policy-id: policy-id })
)

;; Get crop claim details
(define-read-only (get-crop-claim (claim-id uint))
  (map-get? crop-claims { claim-id: claim-id })
)

;; Get weather event data
(define-read-only (get-weather-event (coordinates-lat int) (coordinates-lng int) (date uint))
  (map-get? weather-events { coordinates-lat: coordinates-lat, coordinates-lng: coordinates-lng, date: date })
)

;; Get yield report
(define-read-only (get-yield-report (policy-id uint) (harvest-date uint))
  (map-get? yield-reports { policy-id: policy-id, harvest-date: harvest-date })
)

;; Get contract statistics
(define-read-only (get-crop-stats)
  {
    total-claims: (var-get claim-counter),
    total-payouts: (var-get total-crop-payouts),
    contract-active: (var-get contract-active)
  }
)

;; Emergency pause
(define-public (toggle-crop-contract)
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok (var-get contract-active))
  )
)
