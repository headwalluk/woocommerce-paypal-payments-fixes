# Changelog

All notable changes to the patch set are documented here, grouped by WooCommerce
PayPal Payments version.

---

## 4.2.0 (revised) — 2026-10-28

Two new hunks that reverse the 2026-10-21 decision to accept SDK v6. Badge date
bumped to 2026-10-28.

- **`modules.php`: SDK v6 forced off.** The v6 token refresher in
  `ppcp-sdk-v6-js-boot.js` reschedules itself after any failure and never
  stops. Once the page nonce expires, a product page left open POSTs
  `?wc-ajax=ppc-sdk-v6-client-token` about every 30s indefinitely and gets a 400
  each time ([support thread](https://wordpress.org/support/topic/4-2-0-product-pages-left-open-retry-the-paypal-token-request-every-30-seconds-f/);
  the vendor has acknowledged it and promises 4.2.1). The gate condition is
  replaced with `\false`, so every store runs v5 whatever the filter or
  `woocommerce-ppcp-sdk-v6-eligible` says. This replaces the
  `headwall-ppcp-sdk-v5.php` mu-plugin.
- **`woocommerce-paypal-payments.php`: leftover polls short-circuited.** Tabs
  that loaded under v6 keep polling until they are closed. A guard straight after
  the `namespace` line answers `POST` + `wc-ajax=ppc-sdk-v6-client-token` with
  a `410` and exits, before the remaining plugins, the theme, `init` and the
  main query run.

---

## 4.2.0 — 2026-10-21

Carry-forward of the 4.1.3 patch to plugin v4.2.0. **No new targets** — the same
three hunks apply against the wordpress.org 4.2.0 build with no rejects and no
fuzz (offset -4 in the main plugin file); only the badge date is bumped to
2026-10-21.

Built from the wordpress.org `latest-stable` zip via
`scripts/prepare-analysis.sh`.

A minor-version vendor release (125 changed PHP files across 25 modules, no new
modules), dominated by SDK v6 rollout and checkout fixes.

### Nothing fixed upstream

`SubscriptionHelper.php` is **byte-identical to 4.1.3** — `paypal_subscription_id()`
still relies on dead `assert()` guards, so the `get_type()`-on-`false` fatal is
still live in stock 4.2.0. Notably, every new `wc_get_product()` /
`wc_get_order()` call added in 4.2.0 *does* carry a real `instanceof` guard; this
one is simply not being revisited.

### Reviewed and left alone

- **No new data-sharing anywhere.** No new hosts; the set of files making
  `wp_remote_*` calls is unchanged; no new `register_rest_route` registrations;
  the only Action Scheduler change is a start-time offset in
  `IngestionManager` (behind the store-sync gate).
- **`ppcp-store-sync`** — `AgenticSettingsDataModel`, `StoreSyncModule`,
  `RegistrationEligibility`, `AgenticWebhookConfiguration`, `services.php` and
  `module.php` are all **byte-identical to 4.1.3**, so the gate hunk carries over
  verbatim and still governs REST registration, ingestion and reconciliation.
  The seven changed files (`ProductManager`, `IngestionManager`,
  `ProductsPayload`, `SyncJob`, `AgenticSessionHandler`, `AgenticWcSession`,
  `StorePayPalCart`) are all downstream of the gate. `ProductsPayload` now also
  sends the parent's short description for variations — inert while patched.
  Eligibility is **still US-only**.
- **`ppcp-abilities`** — reworked onto the DI container (#4698), but still
  default-OFF behind `apply_filters( 'woocommerce_paypal_payments_abilities_enabled', \false )`,
  still `manage_woocommerce`, and the permission callback now fails closed when
  unbound. Below the patch bar, as before.
- **Card payment payer data (#4650)** — buyer email, name, phone and billing
  address now sent when creating a card payment. Destination is PayPal; leave
  alone.
- **New AJAX endpoints** — `ppc-frontend-log` (nonce-checked, 1024-char line cap,
  writes to the local WC logger only) and `ppc-free-trial-vault-return`
  (order-bound one-time nonce). Nothing to patch.

### `ppcp-sdk-v6`: existing stores are now migrated to v6

The trigger noted in `docs/patch-targets.md` has fired. 4.2.0 removes the 4.1.3
set-once "existing installs stay on v5" logic from the main plugin file and
inverts the module gate in `modules.php`:

```php
// 4.1.3
'yes' === get_option( 'woocommerce-ppcp-sdk-v6-eligible' )
// 4.2.0
'no' !== get_option( 'woocommerce-ppcp-sdk-v6-eligible' )
```

A new one-time migration, `CompatModule::migrate_sdk_v6_default()` (marker
option `woocommerce_ppcp-is_sdk_v6_default_migrated`), rewrites any value other
than `'yes'` to `'yes'` for supported merchant countries (`'no'` otherwise) on
plugin update. So **every existing store moves to the SDK v6 checkout on upgrade
to 4.2.0.**

**No patch — deliberate decision.** v6 talks only to PayPal and is the vendor's
intended default, so it falls outside this repo's crash/data-sharing remit. We
accept the vendor behaviour and will deal with any client-reported checkout
issues as they arise. A store can be pinned back to v5 with the
`woocommerce.feature-flags.woocommerce_paypal_payments.sdk_v6_enabled` filter.

---

## 4.1.3 — 2026-09-09

Carry-forward of the 4.1.2 patch to plugin v4.1.3. **No new targets** — the same
three hunks apply against the wordpress.org 4.1.3 build with no rejects and no
fuzz (offset +68 in `SubscriptionHelper.php`, +4 in the main plugin file); only
the badge date is bumped to 2026-09-09.

Built from the wordpress.org `latest-stable` zip via
`scripts/prepare-analysis.sh` (published 2026-09-09 13:34 GMT).

4.1.3 is another **large vendor release** (~227 changed paths, one new module,
one heavily expanded module), but nothing lands on our targets and nothing we
patch has been fixed upstream.

### Nothing fixed upstream

`paypal_subscription_id()` is **byte-identical to 4.1.2** — the vendor's dead
`assert($product instanceof WC_Product)` "guards" are still in place, so the
`get_type()`-on-`false` fatal is still live in stock 4.1.3.

### Our fix matters more again in 4.1.3

`SubscriptionHelper.php` was substantially reworked *around* our target (manual-
renewal handling, a new `resolve_subscription_mode()`), and the crash surface
widened for the second release running:

- **New:** `WcGateway\Checkout\DisableGateways::handler()` now calls
  `subscription_cart_processable()` → `paypal_subscription_button_allowed()` →
  `checkout_subscription_product_allowed()` → `paypal_subscription_id()`. That
  handler is on the `woocommerce_available_payment_gateways` filter, so the
  unguarded `wc_get_product($item['product_id'])` loop is now reached during
  **gateway availability** — earlier, and in more contexts (cart, checkout,
  block/Store API checkout, change-payment-method, admin order creation) than
  the 4.1.2 mini-cart/proceed-to-checkout render path.
- **New:** `need_subscription_intent()` now calls `paypal_subscription_id()` on
  the **product page** when Accept Manual Renewals is on.

In 4.1.1 the loop was reached at localize time only. Three releases later it is
on the gateway-availability filter. Keep the guard.

### Reviewed and left alone

- **No new data-sharing anywhere.** Host list is byte-identical between 4.1.2 and
  4.1.3 (no new domains); `wp_remote_*` call sites unchanged; no new
  `register_rest_route` registrations (only line-number drift); no new Action
  Scheduler / `wp_schedule_*` jobs; no `get_defaults()` changed.
- **`ppcp-order-endpoints` (new module)** — a pure refactor, not new surface.
  `AbstractCartEndpoint`, `ApproveOrderEndpoint`, `ChangeCartEndpoint`,
  `CreateOrderEndpoint`, `RequestData`, `CartProductsHelper`,
  `EarlyOrderHandler` and `WooCommerceOrderCreator` moved out of `ppcp-button`
  and `ppcp-blocks` into a shared module (plus `UpdateShippingEndpoint`). Same
  AJAX endpoints, same nonce checks.
- **`ppcp-store-sync` churn** — `CouponValidator`, `ShippingValidator`,
  `CheckoutEndpoint`, `AgenticCheckoutProcessor` and `ProductManager` changed,
  but `AgenticSettingsDataModel` is **byte-identical to 4.1.2**, so the gate
  hunk carries over verbatim. `StoreSyncModule::run()` is structurally unchanged
  (early exit before REST registration and ingestion), and
  `ReconciliationService::reconcile()` still reads the same
  `should_initialize_features()` — so our forced `\false` still governs
  registration and still means "desired = not registered".
  `RegistrationEligibility::is_eligible()` is **still US-only**, `// todo:
  shipping country must be US` and all.
- **New API-client plumbing** — `Helper/ApiHostResolver` and
  `Authentication/ResolvingBearer` resolve the PayPal API host/bearer per request
  instead of freezing them at construction. PayPal hosts only; a correctness fix,
  nothing to patch.
- **`ppcp-compat/WooCommerceBlueprint/ConnectionDataSanitizer` (new)** — strips
  `client_id`, `client_secret`, `merchant_id`, `merchant_email` and onboarding
  flags from Blueprint exports. A privacy *improvement*; leave it alone.
- **`ppcp-compat/PluginDetector` (new)** — local-only detection of first-party
  WooCommerce extensions that customise products (Subscriptions, Gift Cards,
  Bundles, Add-Ons, …). No outbound calls. Registered in `services.php` as
  `compat.product-customization-detector` but **not injected anywhere yet** —
  dead code, almost certainly groundwork for agentic product ingestion. Watch it.
- **`ppcp-abilities`** — **byte-identical to 4.1.2**. Still default-OFF behind
  `apply_filters( 'woocommerce_paypal_payments_abilities_enabled', \false )`.
  Below the patch bar, as before.
- **`ppcp-sdk-v6`** — see below; gained a lot of code and a new arming path, but
  the arming path is the *correct* one.

### `ppcp-sdk-v6`: the new arming path is the right pattern

The module grew substantially (block checkout integration, `CartQuoteEndpoint`,
`SimulateCartEndpoint`, `AddPaymentMethodManager`, Apple Pay / Google Pay /
Fastlane config helpers, and a `SessionRecord` family carrying wallet-sheet
shipping/tax/quote decisions through to the order). Its module gate also changed:

```php
// 4.1.2
getenv( 'PCP_SDK_V6_ENABLED' ) === '1'
// 4.1.3
getenv( 'PCP_SDK_V6_ENABLED' ) === '1' || 'yes' === get_option( 'woocommerce-ppcp-sdk-v6-eligible' )
```

A stored option that arms a module by itself is normally exactly what this repo
patches. **Not here** — `woocommerce-paypal-payments.php` sets it once, on the
version-change hook, as:

```php
update_option( 'woocommerce-ppcp-sdk-v6-eligible', $installed_plugin_version ? 'no' : 'yes' );
```

`$installed_plugin_version` is the previously stored `woocommerce-ppcp-version`,
so an **existing install upgrading to 4.1.3 gets `'no'`** and stays on SDK v5,
while only a **fresh install gets `'yes'`**. It is guarded by
`\false === get_option( … )` so it is computed exactly once and never
recomputed, and `SdkV6Module` self-disables it back to `'no'` for unsupported
merchant countries.

That is on-for-new, off-for-existing — the pattern we have been asking for, and
the opposite of the agentic store-sync default-on behaviour. **No patch.** Note
that a *newly built* store on 4.1.3 will get the v6 checkout path by default,
which is a stability consideration for new client sites rather than a privacy
one. Re-read the gate each release: if a future version flips existing installs
to `'yes'`, or arms the module from PayPal-side eligibility, that becomes a
target.

---

## 4.1.2 — 2026-08-04

Carry-forward of the 4.1.1 patch to plugin v4.1.2. **No new targets** — the same
three hunks apply cleanly (no rejects, no fuzz) against the wordpress.org 4.1.2
build; only the badge date is bumped to 2026-08-04.

Unlike 4.1.0, this one was already downloadable from wordpress.org (published
2026-08-04 15:25 GMT, the same day as the GitHub release), so it was built
against the wordpress.org `latest-stable` zip via `scripts/prepare-analysis.sh`.

The ~24-hour cooling-off is a separate thing: it gates when a release is offered
to sites for **auto-update**, not when the zip appears on wordpress.org. As of
2026-08-04 4.1.2 was not yet showing as available for auto-update, so it is
expected to reach the fleet from the afternoon of **2026-08-05**. That gap is
the useful one — the patch can be deployed to the WPatcher tree a day *ahead*
of the plugin landing on client sites.

4.1.2 is a **large vendor release** (~40 changed PHP files, one new module), but
none of it lands on our targets:

- **`AgenticSettingsDataModel.php`** — byte-identical to 4.1.1, so the
  store-sync gate hunk carries over verbatim.
- **`SubscriptionHelper.php`** — changed, but only by *additions* above our
  target; `paypal_subscription_id()` itself is untouched and both hunks applied
  at offset +40. **Our fix matters more in 4.1.2, not less:** the new
  `paypal_subscription_button_allowed()` helper is called from
  `SmartButton`'s **mini-cart** and **proceed-to-checkout** render hooks
  (`subscription_button_allowed()`), and it reaches
  `checkout_subscription_product_allowed()` → `paypal_subscription_id()` — the
  exact unguarded `wc_get_product($item['product_id'])` loop we patch. In 4.1.1
  that loop was only reached at localize time; in 4.1.2 it is also on the cart
  page and mini-cart render path, so the fatal surface has widened.

### Reviewed and left alone

- **`ppcp-store-sync` churn** — the master gate is unchanged and still the single
  choke point. `StoreSyncModule::run()` dropped its inline
  `ensure_registered()` / `ensure_deregistered()` in favour of a new
  **`Registration/ReconciliationService`**, hooked to the new
  `woocommerce_paypal_payments_settings_saved` action. That reconciler calls the
  same `should_initialize_features()`, so our forced `\false` still governs it —
  and now means "desired = not registered", i.e. an already-registered store is
  actively **deregistered** the next time the agentic settings are saved.
  New `Ingestion/ProductFilter` (product eligibility + "parking" via
  `_ppcp_agentic_last_sync` meta) and the ingestion/validation refactor around it
  are all downstream of the closed gate and therefore inert.
- **`ppcp-sdk-v6` (new module)** — PayPal JS SDK v6 loader: an `SdkV6Manager`
  asset enqueue, a rate-limited `ClientTokenEndpoint`, PayPal hosts only. It is
  **not loaded by default** — `modules.php` gates it behind
  `getenv('PCP_SDK_V6_ENABLED') === '1'` / the
  `woocommerce.feature-flags.woocommerce_paypal_payments.sdk_v6_enabled` filter,
  the same dev-flag pattern as `ppcp-store-sync`. Nothing to patch; watch it as
  it grows.
- **`Settings/Service/MerchantDataResolver` (new)** — backfills an empty
  `merchant_country` from PayPal's own seller-status API, bounded to 3 Action
  Scheduler retries and only on connect/upgrade. Accounts for the two new
  `as_schedule_single_action` call sites. PayPal-only, not telemetry.
- **Vendor bug fixes of the same class we patch** — `Shipment` now guards a
  non-array tracking meta, `AddressFactory` normalises PayPal's `[]`-for-`{}`
  empty address, `IncomingWebhookEndpoint` wraps handling in a catch-all
  `Throwable`, `Capture{Card,PayPal}Payment` retry a success-without-`id`
  response, `CartEndpoint` hardens JSON decoding. Nothing left for us to add.
- **`ppcp-abilities`** (the 4.1.0 watch item) — completely unchanged, still
  default-OFF behind `woocommerce_paypal_payments_abilities_enabled` and
  WC-10.9-gated. Watch item stands.

### Data-sharing scan

Clean: host enumeration is **identical** to 4.1.1 (PayPal hosts only, plus the
already-suppressed `d.joinhoney.com`), `register_rest_route` count unchanged at
37, no new recurring cron, and no new default-on data-sharing setting.

> Cosmetic vendor slip, not patched: 4.1.2's plugin header docblock is mangled —
> the leading asterisks lost their indent and a bare `SHA: e1d36e64…` line was
> injected after `Version: 4.1.2`. It's still inside the comment block and WP
> parses the version fine.

---

## 4.1.1 — 2026-07-07

Carry-forward of the 4.1.0 patch to plugin v4.1.1. **No new targets** — the same
three hunks apply cleanly (no rejects, no fuzz) against the wordpress.org 4.1.1
build; only the badge date is bumped to 2026-07-07. Both functional target files
(`AgenticSettingsDataModel.php`, `SubscriptionHelper.php`) are byte-identical
between 4.1.0 and 4.1.1, and `ppcp-store-sync` as a whole is unchanged, so both
fixes carry over verbatim.

4.1.1 is a small vendor **security-hardening point release**. The 4.1.0 → 4.1.1
delta is seven PHP files, all vendor-side, none touching our targets and none
introducing a new outbound host, cron, or REST endpoint (host enumeration is
identical to 4.1.0). Reviewed and left alone:
- **`ApproveSubscriptionEndpoint`** — now *always* validates `custom_id` ownership
  (binds the supplied PayPal order to the current shopper session), not only in
  the no-subscription branch. IDOR hardening.
- **`UpdateShippingEndpoint`** (+ `ppcp-blocks/services.php` wiring) — now injects
  `SessionHandler` and rejects the request unless `order_id` matches the session
  order. IDOR hardening.
- **`CreditCardGateway::add_payment_token_to_order()`** — only attaches a saved
  payment token when `$payment_token->get_user_id() === get_current_user_id()`,
  i.e. the token belongs to the current user. IDOR hardening.
- **`PUIPaymentMethod`** — early-returns when `WC()->cart` is not a `WC_Cart`
  (Mini-Cart block context), skipping the costly checkout-fields build. Defensive
  bug fix — same shape as our own null-guard fixes, but the vendor did it, so
  nothing for us to add.
- **`PartnersEndpoint`** — backs off the merchant-integrations endpoint after a
  recent failure (via `FailureRegistry`) and refactors the fallback into
  `handle_seller_status_failure()`. **`ProductStatus`** — aligns its failure-registry
  TTL to `PartnersEndpoint::SELLER_STATUS_CACHE_TTL`. Vendor reliability, left alone.
- **`ppcp-abilities`** (the 4.1.0 watch item) — unchanged, still default-OFF and
  WC-10.9-gated. Watch item stands.

---

## 4.1.0 — 2026-06-23

Carry-forward of the 4.0.4 patch to plugin v4.1.0. **No functional changes** —
the same three hunks, which apply cleanly (no rejects, no fuzz). Both functional
target files (`AgenticSettingsDataModel.php`, `SubscriptionHelper.php`) are
byte-identical between 4.0.4 and 4.1.0, so both fixes carry over verbatim; the
badge date is unchanged (same release day).

Built against the GitHub release distributable
(`woocommerce-paypal-payments.zip`) as 4.1.0 had not yet published to
wordpress.org — that asset is the same build that lands on wordpress.org.

Analysis of the 4.0.4 → 4.1.0 delta (two new modules, churn in `ppcp-store-sync`,
`ppcp-settings`, `ppcp-api-client`) found **nothing new to patch**:
- **`ppcp-store-sync`** — our `should_initialize_features() => false` gate still
  fully neutralises it. `StoreSyncModule::run()` consults the same master gate;
  a false result still deregisters and skips all registration, the
  `ppcp_agentic_sync_batch` cron, and the agentic REST endpoints. Eligibility is
  still US-only; no new outbound hosts (still `d.joinhoney.com`). The internal
  surface grew (new `Ingestion/ProductDTO`, per-endpoint action hooks, a
  `…_store_sync_ingestion_completed` action) but it's all transitively dead.
- **`ppcp-abilities`** (new) — exposes read-only abilities (connection status,
  payment methods, order tracking, PayPal order) to in-context AI agents via the
  WC 10.9+ Abilities API. **Default-OFF** (filter
  `woocommerce_paypal_payments_abilities_enabled` defaults `false`, and it
  requires WC 10.9), admin-only (`manage_woocommerce`), with payer-PII/credential
  redaction. Doesn't meet the patch bar (we patch *default-on* data-sharing).
  Recorded as a watch item in `docs/patch-targets.md`.
- **`ppcp-vault-component`** (new) — benign saved-card tokenisation; PayPal-only,
  gated by `VaultComponentApplies`.
- **Performance** — no new cron/Action Scheduler jobs vs 4.0.4; nothing new to
  disable. (`ppcp-api-client` gained a `TokenRateLimiter` that *throttles* PayPal
  auth-token requests — a vendor reliability win, left alone.)
- **Bug-hunt** — the new/changed button code (`SmartButton`,
  `WooCommerceOrderCreator`, `CartProductsHelper`) now uses real `if (!$product)`
  guards rather than assert-only; no new `get_type()`-on-`false` fatal.

---

## 4.0.4 — 2026-06-23

First patch in this project. Two changes:

**Bug fix — fatal `get_type()` on `false`**
- `modules/ppcp-wc-subscriptions/src/Helper/SubscriptionHelper.php` →
  `paypal_subscription_id()`. The method iterates the cart calling
  `wc_get_product($item['product_id'])` and then `$product->get_type()`, "guarded"
  only by `assert($product instanceof WC_Product)`. With `zend.assertions=-1`
  (production default) the assert is compiled out, so a cart item with no
  `product_id` key, or an id that no longer resolves to a product, yields `false`
  and the next line fatals: `Uncaught Error: Call to a member function get_type()
  on false`. Seen live across product, cart, and my-account pages.
  Fix: replace the dead `assert()`s with real guards — `isset()` on the cart
  item's `product_id` (kills the `Undefined array key` warning) and an
  `instanceof WC_Product` check that `continue`s past anything unresolvable. The
  current-product block just above gets the same `instanceof` guard folded into
  its `if`.

**Privacy — disable "Agentic Commerce" store-sync**
- `modules/ppcp-store-sync/src/Setting/AgenticSettingsDataModel.php` →
  `should_initialize_features()` forced to `\false`. Upstream, when this gate is
  open the `ppcp-store-sync` module registers the store with `d.joinhoney.com`
  (handing over a catalogue-download URL), runs a recurring Action Scheduler job
  (`ppcp_agentic_sync_batch`) uploading products to PayPal/Honey, and registers
  public REST endpoints (`create_cart` / `get_cart` / `replace_cart` / `checkout`)
  for AI shopping agents. The feature is **default-on** (`'active' => true`) and
  currently gated to US merchants, but self-arms with no admin action once PayPal
  widens eligibility (note the in-source `// todo: shipping country must be US`).
  Forcing the gate off makes `StoreSyncModule::run()` always take its existing
  early-exit + deregister path: no registration, no ingestion schedule, no REST
  endpoints, and any already-registered store is cleanly deregistered.

Audit note: `d.joinhoney.com` is the only non-PayPal, non-opt-in outbound host in
the plugin. The reCAPTCHA call to `google.com` is opt-in anti-fraud; everything
else is the PayPal API or a WP loopback. No Automattic Tracks / Jetpack / Mixpanel
telemetry. "Upsells" are confined to PayPal's own feature cards inside the plugin's
settings tab plus one Mexico-only WC inbox note — neither is patched (legitimate
settings UI, not a dashboard nag or outbound call).

Also appends the standard `// START : wpatcher` "PATCHED" badge to
`woocommerce-paypal-payments.php`.

---

## Project changes — 2026-06-23

- Initial repository, modelled on
  [woocommerce-debloat](https://github.com/headwalluk/woocommerce-debloat).
- Added `scripts/prepare-analysis.sh` — download, extract, version-detect, and
  best-match patch application for new PPCP releases.
- Added `scripts/analyse-paypal-payments.md` — analysis runbook covering both the
  data-sharing audit and the `assert()`-guarded type-bug hunt.
- Added `docs/patch-targets.md` — current targets, future candidates, and the
  external domains the plugin contacts.
- Added `CLAUDE.md`, `.gitignore`, and GPL v2 `LICENSE`.
