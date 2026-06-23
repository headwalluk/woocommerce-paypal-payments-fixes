# Changelog

All notable changes to the patch set are documented here, grouped by WooCommerce
PayPal Payments version.

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
