# WooCommerce PayPal Payments Analysis Runbook

This document guides Claude Code through analysing a WooCommerce PayPal Payments
(PPCP) release for patch targets. Two goals, in priority order:

1. **Carry forward the existing fixes** — confirm every hunk in the current patch
   still applies (or rebase it) against the new version.
2. **Find new targets** — (a) crash/warning bugs the vendor has shipped, and
   (b) data-sharing features that are on by default and send store data to third
   parties.

## Prerequisites

Run `./scripts/prepare-analysis.sh` first. You should have:
- `work/woocommerce-paypal-payments-X.Y.Z/` — clean source
- `work/woocommerce-paypal-payments-X.Y.Z-patched/` — with best-match patch applied

If the patch applied with rejects, resolve those first before continuing.

## How to use this runbook

Start a Claude Code session and say:

> Follow the analysis runbook in `scripts/analyse-paypal-payments.md` against the working directories in `work/`.

## Phase 1: Understand the current patch

Read the existing patch that was applied. Identify every file and function it
modifies — this is your baseline. List each target with:
- File path (relative to plugin root)
- Function/method name
- What the patch does (guard added, early return, etc.) and whether it's a **bug
  fix** or **data-sharing suppression**

If any hunk failed to apply (`.rej`), rebase it by hand against the new source —
the plugin is heavily namespaced and line numbers drift every release.

> Note: PPCP ships **compiled/transpiled** PHP — `declare(strict_types=1)` files,
> `\true`/`\false`/`\null` literals, and the `WooCommerce\PayPalCommerce\Vendor\…`
> namespace. Match that style in patched lines so diffs stay minimal.

## Phase 2: Re-verify known data-sharing modules

The headline target is the **`ppcp-store-sync`** module ("Agentic Commerce").
Re-read it every release — the surface is actively expanding.

- Master gate: `modules/ppcp-store-sync/src/Setting/AgenticSettingsDataModel.php`
  → `should_initialize_features()`. Our patch forces this to `false`. Confirm the
  method still exists with that name/signature; if it's been renamed or the gate
  logic moved, re-point the patch.
- Eligibility: `modules/ppcp-store-sync/src/Registration/RegistrationEligibility.php`
  → `is_eligible()`. Check whether the US-only restriction (`store_country` /
  `merchant_country` === `'US'`, plus the `// todo: shipping country must be US`)
  has been widened — that's what arms the feature for more stores.
- Endpoints it talks to: `modules/ppcp-store-sync/src/Config/AgenticWebhookConfiguration.php`
  (`d.joinhoney.com` / `d-staging.joinhoney.com`).

## Phase 3: Search for outbound HTTP calls

Search the **clean** source for outbound requests. The plugin legitimately talks
to the PayPal API a lot — the job is to separate that from data-sharing.

```
wp_remote_get
wp_remote_post
wp_remote_request
wp_remote_head
wp_safe_remote_get
wp_safe_remote_post
```

For each match: read the function, find the destination host, and classify it.

**Legitimate — do NOT patch:**
- `api-m.paypal.com` / `api-m.sandbox.paypal.com` and other `*.paypal.com` API
  calls — order create/capture/refund, webhooks, subscriptions, JWKS key fetch.
- `www.google.com/recaptcha/api/siteverify` — opt-in anti-fraud; only fires when
  the merchant has configured reCAPTCHA keys.
- WP loopback self-calls to the site's own REST API (e.g. `InternalRestService`).

**Flag as a candidate** if the call:
- Goes to a non-PayPal host (e.g. `joinhoney.com`) to register the store or upload
  catalogue/order/customer data.
- Fires on every page load, on cron, or on product/stock changes.
- Is not required to take a payment.

To enumerate every host referenced in the source quickly:

```bash
grep -rhoE 'https?://[a-zA-Z0-9._/-]+' work/woocommerce-paypal-payments-X.Y.Z --include='*.php' \
  | sed -E 's#https?://##; s#[/?].*##' | sort | uniq -c | sort -rn
```

## Phase 4: Search for scheduled tasks (cron / Action Scheduler)

Data uploads usually run out-of-band. Search for:

```
as_schedule_recurring_action
as_schedule_single_action
as_next_scheduled_action
wp_schedule_event
wp_schedule_single_event
```

For each: what action does it schedule, and does that action make a non-PayPal
outbound call? (The store-sync ingestion uses `ppcp_agentic_sync_batch`.)

## Phase 5: Search for new REST endpoint registrations

Look for endpoints that let external parties drive the store:

```
register_rest_route
->register_routes(
```

Flag endpoints that create carts, mutate orders, or expose customer/catalogue data
to unauthenticated or third-party-authenticated callers (the agentic
`create_cart` / `get_cart` / `replace_cart` / `checkout` endpoints are the known
example — they're disabled transitively when the store-sync gate is off, but a new
module could register its own).

## Phase 6: Search for default-on data-sharing settings

New features that default to on for existing installs are the whole reason this
repo exists. Search for setting models / defaults:

```
get_defaults
'enabled' => \true
'active' => \true
enabled_by_default
```

For each new data-related toggle, determine its default and whether anything sends
data when it's on. A privacy feature that defaults **on** for existing installs is
a candidate even if it's currently geo-gated.

## Phase 7: Bug-hunt — the patterns that have already bitten us

The crash we first patched came from the vendor relying on `assert()` for runtime
safety. `assert()` is compiled out in production (`zend.assertions=-1`), so any
`assert($x instanceof SomeClass)` is a **no-op** and the next line dereferences a
possibly-`false`/`null` value.

```
assert(
wc_get_product(
->get_type()
['product_id']
['variation_id']
```

Flag any spot where the result of `wc_get_product()` (or similar) is used as an
object without a real `instanceof` / null guard, especially where the only
"guard" is an `assert()`. Also watch for undefined-array-key access on cart items
(`$item['product_id']` etc.) that aren't guaranteed to exist for third-party cart
contents.

Cross-check against the live error logs if you have them — real fatals beat
theoretical ones.

## Phase 8: Diff against the previously patched version

If the new version is newer than the last patch, diff the two clean trees to find
what actually changed:

```bash
cd work/
curl -sSL -o ppcp-PREV.zip "https://downloads.wordpress.org/plugin/woocommerce-paypal-payments.<PREV-VERSION>.zip"
unzip -qo ppcp-PREV.zip && mv woocommerce-paypal-payments woocommerce-paypal-payments-<PREV>-clean

diff -rq woocommerce-paypal-payments-<PREV>-clean woocommerce-paypal-payments-<NEW> \
  | grep -v '\.min\.js' | grep -v '/assets/' | grep -v 'changelog\|readme'
```

Focus on: new modules under `modules/` (especially anything `*-sync`, `*-store`,
`*-agentic`, `*-tracking`), new `Config` classes with external base URLs, new cron
handlers, and new REST endpoints. New module directories are the highest-signal
thing to read first.

## Phase 9: Apply candidate patches and generate the diff

For each approved candidate, in the `-patched/` directory:
1. Make the change following the style conventions in `CLAUDE.md` (real guards for
   bugs; early-return at the vendor's own gate for features; `// wpatcher:` comment;
   original line commented beneath).
2. Ensure the `// START : wpatcher` … `// END : wpatcher` badge block is present in
   `woocommerce-paypal-payments.php` with the current date.
3. `php -l` every changed file.

Delete any stray `.orig` / `.rej` before diffing (they leak into `diff -ruN` as
fake net-new files):

```bash
cd work/
find woocommerce-paypal-payments-X.Y.Z-patched -name '*.orig' -delete
find woocommerce-paypal-payments-X.Y.Z-patched -name '*.rej' -delete

diff -ruN woocommerce-paypal-payments-X.Y.Z woocommerce-paypal-payments-X.Y.Z-patched \
  > woocommerce-paypal-payments-X.Y.Z-candidate.patch
```

Sanity-check it applies cleanly on a fresh extraction:

```bash
rm -rf /tmp/ppcp-verify && cp -a woocommerce-paypal-payments-X.Y.Z /tmp/ppcp-verify
cd /tmp/ppcp-verify && patch -p1 --dry-run < ../woocommerce-paypal-payments-X.Y.Z-candidate.patch
```

## Phase 10: Promote and document

1. Move the candidate to `patches/woocommerce-paypal-payments-X.Y.Z.patch`.
2. Update `CHANGELOG.md` (per-version entry — bump-only or new targets) and
   `docs/patch-targets.md` (current targets / future candidates / domains).
3. Copy the patch into the WPatcher tree for deployment
   (`/opt/headwall-isp/wpatches/plugins/woocommerce-paypal-payments/`).
4. If a hunk was **dropped** (fixed upstream or no longer needed), check
   `dev-notes/` (local, git-ignored) for fleet-side workarounds tied to it —
   mu-plugins, vhost rules, CDN blocks — and remove those too.
