# Changelog

All notable changes to the patch set are documented here, grouped by WooCommerce
PayPal Payments version.

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
