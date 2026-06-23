# Patch Targets

Research notes on what we patch in WooCommerce PayPal Payments (PPCP), why, and
what we might patch in the future.

Last updated: 2026-06-23 (plugin v4.0.4)

---

## Currently Patched

### Bug fixes

| File | Target | Patch | Why |
|------|--------|-------|-----|
| `modules/ppcp-wc-subscriptions/src/Helper/SubscriptionHelper.php` | `paypal_subscription_id()` | Replace dead `assert()`s with real `isset()` + `instanceof WC_Product` guards (`continue` on miss) | Cart item with no `product_id`, or an id that no longer resolves to a product, makes `wc_get_product()` return `false`; the next line calls `->get_type()` on it → `Uncaught Error: Call to a member function get_type() on false` (hard 500). `assert()` is compiled out in production so the vendor's guard does nothing. |

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

Off-switches that are **not** sufficient on their own:
- `define( 'PPCP_AGENTIC_AUTO_REGISTER', false )` — only blocks auto-registration,
  not the ingestion schedule or REST endpoints once the feature is active.
- The per-site "agentic" settings toggle — default-on, per-site, and re-enable-able
  by an update.

---

## Future Candidates

Targets identified during analysis that are not yet patched.

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
