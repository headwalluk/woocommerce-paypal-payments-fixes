# Patch Targets

Research notes on what we patch in WooCommerce PayPal Payments (PPCP), why, and
what we might patch in the future.

Last updated: 2026-10-21 (plugin v4.2.0)

---

## Currently Patched

### Bug fixes

| File | Target | Patch | Why |
|------|--------|-------|-----|
| `modules/ppcp-wc-subscriptions/src/Helper/SubscriptionHelper.php` | `paypal_subscription_id()` | Replace dead `assert()`s with real `isset()` + `instanceof WC_Product` guards (`continue` on miss) | Cart item with no `product_id`, or an id that no longer resolves to a product, makes `wc_get_product()` return `false`; the next line calls `->get_type()` on it → `Uncaught Error: Call to a member function get_type() on false` (hard 500). `assert()` is compiled out in production so the vendor's guard does nothing. **Reach widened in 4.1.2:** also called from `SmartButton`'s mini-cart and proceed-to-checkout render hooks via `paypal_subscription_button_allowed()` → `checkout_subscription_product_allowed()`, not just at localize time. **Widened again in 4.1.3:** `DisableGateways::handler()` (on the `woocommerce_available_payment_gateways` filter) now reaches it via `subscription_cart_processable()`, and `need_subscription_intent()` reaches it on the product page under Accept Manual Renewals. Still unfixed upstream — `SubscriptionHelper.php` is byte-identical in 4.1.3 and 4.2.0. |

### Privacy / data-sharing

| File | Target | Patch | Why |
|------|--------|-------|-----|
| `modules/ppcp-store-sync/src/Setting/AgenticSettingsDataModel.php` | `should_initialize_features()` | Early return `\false` | Master gate for the `ppcp-store-sync` "Agentic Commerce" module. Off → `StoreSyncModule::run()` takes its early-exit + deregister path: no Honey registration, no catalogue ingestion job, no agent REST endpoints. Default-on upstream and self-arms once US-only eligibility is widened. |

### Visual indicator

| File | Target | Patch | Why |
|------|--------|-------|-----|
| `woocommerce-paypal-payments.php` | `plugin_row_meta` filter | Appended `// START : wpatcher` badge block | Purple "PATCHED" badge with date in the plugins list, and the marker WPatcher uses to detect an already-patched component. |

---

## How the Agentic Commerce / store-sync module works (reference)

So future analysis doesn't have to re-derive it. When the master gate
(`should_initialize_features()` = `eligible && is_active()`) is open:

1. **Registration** — `Registration/RegistrationService::register()` POSTs an
   (unsigned `HS256`/`'no-signature'`) JWT to
   `https://d.joinhoney.com/webhooks/ws/install`. Payload includes `storeName`,
   `storeUrl`, `paypalMerchantId`, `country`, `currency`, and a
   **`catalogDownloadUrl`** — a URL Honey can pull the whole catalogue from.
2. **Ingestion** — `Ingestion/IngestionManager` schedules a recurring Action
   Scheduler job `ppcp_agentic_sync_batch` that batches products and POSTs them to
   `https://d.joinhoney.com/webhooks/products`, and re-marks products for sync on
   `woocommerce_update_product` / `woocommerce_product_set_stock`.
3. **Agent endpoints** — `Endpoint/AgenticRestEndpoint` subclasses register
   `create_cart` / `get_cart` / `replace_cart` / `checkout` REST routes on
   `rest_api_init` so external agents can transact against the store.

Eligibility (`Registration/RegistrationEligibility::is_eligible()`) currently
requires a connected merchant **and** `store_country === 'US'` **and**
`merchant_country === 'US'`, with a `// todo: shipping country must be US`. So on a
non-US store the gate is closed today — but `is_active()` defaults to `true`, so
the day eligibility widens, sync begins with no further action. That's why we kill
it at the gate rather than relying on geo-dormancy.

Since **4.1.2**, registration is no longer driven from `StoreSyncModule::run()`
(`ensure_registered()` / `ensure_deregistered()` are gone). It is handled by
`Registration/ReconciliationService::reconcile()`, hooked to the new
`woocommerce_paypal_payments_settings_saved` action. It reads the same
`should_initialize_features()` gate, so our patch still governs it — and because
the patched gate reports "desired = not registered", a store that had already
registered gets **deregistered** on the next agentic settings save. Also new in
4.1.2: `Ingestion/ProductFilter`, which decides product eligibility and "parks"
ineligible products via the `_ppcp_agentic_last_sync` meta key; it is downstream
of the gate and inert while the gate is shut.

Off-switches that are **not** sufficient on their own:
- `define( 'PPCP_AGENTIC_AUTO_REGISTER', false )` — only blocks auto-registration,
  not the ingestion schedule or REST endpoints once the feature is active.
- The per-site "agentic" settings toggle — default-on, per-site, and re-enable-able
  by an update.

---

## Future Candidates

Targets identified during analysis that are not yet patched.

### `ppcp-abilities` — AI-agent data exposure (WATCH, added v4.1.0)

- **Module:** `modules/ppcp-abilities/` (new in 4.1.0).
- **What it is:** registers read-only "abilities" via the WooCommerce 10.9+
  Abilities API (for in-context AI agents / MCP) — `get-connection-status`,
  `get-payment-methods`, `get-order-tracking`, `get-paypal-order`. They delegate
  to existing REST controllers and to PayPal API calls.
- **Why NOT patched yet:** it does **not** meet the patch bar. It is
  **default-OFF** — gated behind `apply_filters(
  'woocommerce_paypal_payments_abilities_enabled', \false)`
  (`src/AbilitiesRegistrar.php`, "Default false during rollout") **and** requires
  WC 10.9 (`class_exists(...AbilitiesLoader)`). It's admin-only
  (`manage_woocommerce`) and redacts payer PII, `payment_source`, and API
  credentials. We patch *default-on* data-sharing; this is opt-in and off.
- **Trigger to patch:** if a future release flips the filter default to `\true`,
  drops the WC-version gate, or widens the permission below `manage_woocommerce`.
  Then early-return `AbilitiesRegistrar::init()` (or force the
  `…_abilities_enabled` filter to `\false`) — same playbook as the store-sync
  gate. Re-read this module every release.

### `ppcp-sdk-v6` — PayPal JS SDK v6 (ACCEPTED, added v4.1.2, decided v4.2.0)

- **Module:** `modules/ppcp-sdk-v6/` (new in 4.1.2, substantially expanded in
  4.1.3, default for all stores from 4.2.0).
- **What it is:** loader for PayPal's JS SDK v6, plus block-checkout integration,
  `CartQuoteEndpoint` / `SimulateCartEndpoint`, `AddPaymentMethodManager`,
  Apple Pay / Google Pay / Fastlane config helpers, and a `SessionRecord` family
  (`RecordedQuote`, `RecordedShippingRate`, `RecordedTaxBasis`) that carries a
  wallet sheet's shipping/tax/quote decisions through to the resulting order.
  PayPal hosts only; no third-party destination.
- **Arming history:**
  - 4.1.2: `getenv('PCP_SDK_V6_ENABLED') === '1'` only.
  - 4.1.3: `|| 'yes' === get_option('woocommerce-ppcp-sdk-v6-eligible')`, with the
    option set once on the version-change hook to `'no'` for upgrades and `'yes'`
    for fresh installs (on-for-new, off-for-existing).
  - 4.2.0: `|| 'no' !== get_option('woocommerce-ppcp-sdk-v6-eligible')` (a missing
    option now means v6). The set-once logic is gone, and
    `CompatModule::migrate_sdk_v6_default()` runs once on update (marker
    `woocommerce_ppcp-is_sdk_v6_default_migrated`), rewriting anything not `'yes'`
    to `'yes'` for supported merchant countries and `'no'` otherwise.
    `SdkV6Module` still writes `'no'` for unsupported countries on merchant
    authentication.
- **Decision (2026-10-21): not patched.** 4.2.0 tripped the trigger we had
  recorded (existing installs flipped to v6), but v6 talks only to PayPal and is
  the vendor's intended default, so it is outside this repo's crash/data-sharing
  remit. We accept the migration and handle any client-reported checkout issues
  as they arise.
- **Per-store escape hatch:** the
  `woocommerce.feature-flags.woocommerce_paypal_payments.sdk_v6_enabled` filter
  pins a store to v5 (or v6). Setting the option to `'no'` also works once the
  migration marker is set.
- **Re-assess if:** the module grows a non-PayPal destination, or v6 produces
  crashes we would otherwise patch.

### `ppcp-compat/PluginDetector` — unconsumed product scanner (WATCH, added v4.1.3)

- **Files:** `modules/ppcp-compat/src/PluginDetector/PluginDetector.php`,
  `ProductCustomizationDetector.php`.
- **What it is:** local-only detection of whether a product has been customised
  by a first-party WooCommerce extension (Subscriptions, Gift Cards, Product
  Bundles, Product Add-Ons, Min/Max Quantities, Composite Products, Shipping Per
  Product, Deposits). Makes no outbound calls.
- **Why NOT patched:** nothing consumes it (still true in 4.2.0). It is registered in
  `ppcp-compat/services.php` as `compat.product-customization-detector` and that
  service id appears **nowhere else in the tree** — dead code shipped ahead of
  its consumer.
- **Trigger to patch:** when a consumer appears. A per-product customisation scan
  is the shape of thing agentic catalogue ingestion wants (deciding which
  products an external agent can be sold), so check what wires it up — if it is
  `ppcp-store-sync`, it is inert behind our gate patch and needs nothing; if it
  is anything that reports outward, re-assess.

### Agent REST endpoints (defensive double-disable)

- **Files:** `modules/ppcp-store-sync/src/Endpoint/*`
- **Status:** transitively disabled — they're only registered when the store-sync
  gate is open, which our patch forces shut.
- **Why not patched directly:** redundant while the gate patch holds. If the vendor
  ever registers these endpoints outside the gate, add a direct early-return in the
  endpoint registration.

### Settings toggle default

- **File:** `modules/ppcp-store-sync/src/Setting/AgenticSettingsDataModel.php` →
  `get_defaults()` (`'active' => \true`).
- **Why not patched:** the `should_initialize_features()` override already makes the
  default irrelevant. Flipping the default to `\false` as well would be belt-and-
  braces but adds a second hunk to maintain for no behavioural gain while the gate
  override stands.

---

## Domains Contacted by Unpatched PPCP

| Domain | Purpose | Status |
|--------|---------|--------|
| `api-m.paypal.com` / `api-m.sandbox.paypal.com` | PayPal REST API — orders, capture, refunds, webhooks, subscriptions | Legitimate — leave alone |
| `www.paypal.com` / `www.sandbox.paypal.com` | Hosted assets, bizsignup flows, JWKS | Legitimate — leave alone |
| `www.paypalobjects.com` | Static SDK/image assets | Legitimate — leave alone |
| `d.joinhoney.com` / `d-staging.joinhoney.com` | "Agentic Commerce" store registration + product catalogue ingestion (PayPal-owned Honey) | **Suppressed** by the store-sync gate patch |
| `www.google.com/recaptcha` | reCAPTCHA verification | Opt-in anti-fraud — only fires with merchant-configured keys; leave alone |

No Automattic Tracks / Jetpack / `pixel.wp.com` / `public-api.wordpress.com`
telemetry is present in this plugin (unlike WooCommerce core — see
[woocommerce-debloat](https://github.com/headwalluk/woocommerce-debloat)).
