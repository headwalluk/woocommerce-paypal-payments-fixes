# WooCommerce PayPal Payments — Fixes

**Bug fixes and privacy patches for the official WooCommerce PayPal Payments plugin (`woocommerce-paypal-payments`, "PPCP").**

WooCommerce PayPal Payments is the official PayPal gateway for WooCommerce. It's also a large, fast-moving codebase with a habit of shipping bugs that take down storefronts, and — more recently — turning on data-sharing features by default for *existing* installations rather than asking them to opt in.

This project provides surgical, per-version patches that:

1. **Fix crashes and warnings** the vendor has shipped to production, so client stores stop throwing 500s while we wait for an official release.
2. **Suppress data-sharing features that are on by default** — most notably the "Agentic Commerce" store-sync that uploads your product catalogue to PayPal's Honey infrastructure (`d.joinhoney.com`) and opens public checkout endpoints for AI shopping agents.

The changes are conservative and commented. Payment processing, subscriptions, and all core gateway functionality remain fully intact.

**Important**: This is NOT an attempt to nullify or crack a commercial product — PayPal Payments is free and GPL. These patches exist to keep client stores online and to stop store data being sent to third parties without meaningful consent. If something here breaks a feature you actually want, don't apply that hunk.

---

## What the patches do

Each patch targets a specific version of the plugin. Here's what the current set covers (see `docs/patch-targets.md` for the file/function detail and `CHANGELOG.md` for the per-version history):

**Bug fixes**
- `SubscriptionHelper::paypal_subscription_id()` — guards against cart items that don't resolve to a `WC_Product`. Unpatched, a cart item with no `product_id` (or a deleted product) makes `wc_get_product()` return `false`, and the plugin then calls `->get_type()` on it → `Uncaught Error: Call to a member function get_type() on false`, a hard 500 on the storefront. The vendor "guards" this with `assert()`, which is compiled out in production (`zend.assertions=-1`) and does nothing.

**Privacy / data-sharing**
- `AgenticSettingsDataModel::should_initialize_features()` — hard-disables the `ppcp-store-sync` ("Agentic Commerce") module. Upstream this registers the store with `d.joinhoney.com`, hands over a catalogue-download URL, runs a recurring job uploading products to PayPal/Honey, and registers public REST endpoints (`create_cart` / `get_cart` / `replace_cart` / `checkout`) for AI agents. It is **default-on** (`'active' => true`) and currently US-gated, but self-arms the moment PayPal widens eligibility — with no admin action. We neutralise it at the vendor's own gate so the module always takes its existing early-exit + deregister path.

**What the patches deliberately leave alone**
- All PayPal API traffic (`api-m.paypal.com`) — order creation, capture, refunds, webhooks, subscriptions.
- The opt-in reCAPTCHA fraud-protection integration (only fires if the merchant configures keys).
- PayPal's feature/upsell cards *inside* the plugin's own settings tab (annoying, but it's the legitimate settings UI, not a dashboard nag or an outbound call).

---

## Compatibility

Patches are provided per plugin version. Check the `patches/` directory for your version.

| WooCommerce PayPal Payments | Patch file |
|---|---|
| 4.1.0 | `patches/woocommerce-paypal-payments-4.1.0.patch` |
| 4.0.4 | `patches/woocommerce-paypal-payments-4.0.4.patch` |
| Older / newer versions | See `patches/` directory |

Patches are maintained on a best-effort basis, typically updated within a few days of a new plugin release. Because the plugin is heavily namespaced and modular, line numbers move between releases — always use the patch that matches your installed version, or re-generate one (see below).

---

## How to apply

You'll need the original plugin files and `patch` available on your system.

```bash
# From your WordPress plugins directory
cd /path/to/wp-content/plugins

# Apply the patch (paths inside the patch are relative to the plugin dir)
patch -p1 --directory=woocommerce-paypal-payments < /path/to/woocommerce-paypal-payments-4.0.4.patch

# Verify no rejects
find woocommerce-paypal-payments -name '*.rej' 2>/dev/null | grep -q . && echo "Check rejects!" || echo "Clean apply"
```

> **Note:** Always test on a staging environment before applying to production. After applying, check your error log and place a test order.

### Using WPatcher

These patches are written to be deployed with [WPatcher](https://github.com/headwalluk/wpatcher) — the patch carries the `// START : wpatcher` marker block, so WPatcher can detect, deploy, and revert it across a fleet:

```bash
wpatch -p /path/to/wordpress -c woocommerce-paypal-payments patch
```

---

## After applying

You should see a **PATCHED** badge on the WooCommerce PayPal Payments entry in your plugins list (`wp-admin/plugins.php`), showing the date the patch was applied.

To verify the privacy patch is working:
- No recurring `ppcp_agentic_sync_batch` action is scheduled
  (`wp action-scheduler list --hook=ppcp_agentic_sync_batch` is empty)
- No outbound requests to `d.joinhoney.com` appear in your server logs

---

## Background

This project started from a real incident: a client storefront throwing `500`s across product, cart, and account pages. The fatal traced to PayPal Payments calling `get_type()` on a `false` return from `wc_get_product()` — the plugin's only "guard" was an `assert()`, which production PHP compiles out entirely.

While fixing that we audited the rest of the plugin and found the `ppcp-store-sync` "Agentic Commerce" module: default-on data-sharing that uploads the product catalogue to PayPal's Honey servers and opens public agent-checkout endpoints. It's gated to US merchants *today*, but it's enabled by default and clearly being widened. New data-sharing features being **on by default for existing installs** — rather than on for new installs and opt-in for everyone else — is exactly the pattern this project exists to push back on.

A detailed write-up is available at [headwall-hosting.com](https://headwall-hosting.com/blog/woocommerce-paypal-payments-patch/)

This is a sibling project to [woocommerce-debloat](https://github.com/headwalluk/woocommerce-debloat), which does the same job for WooCommerce core.

---

## Contributing

Found something that should be patched? Open an issue with the file, line number, and what it does. PRs welcome — please include the plugin version and a brief explanation of what the change fixes/removes and why it's safe.

---

## Licence

GPL v2 — the same licence as WooCommerce PayPal Payments itself.
