# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `README.md` for project overview, what the patches fix/disable, what they leave alone, and how to apply them.

## What this repo is

Per-version patches for the official **WooCommerce PayPal Payments** plugin (`woocommerce-paypal-payments`, "PPCP"). Two kinds of change:

1. **Bug fixes** — crashes/warnings the vendor shipped to production (e.g. fatals that take a storefront down), fixed ahead of an official release.
2. **Privacy / data-sharing suppression** — features that are on by default for existing installs and send store data to third parties (e.g. the `ppcp-store-sync` "Agentic Commerce" catalogue upload to `d.joinhoney.com`).

The patches are deployed across a fleet with [WPatcher](https://github.com/headwalluk/wpatcher); the canonical patch directory on the deployment host is `/opt/headwall-isp/wpatches/plugins/woocommerce-paypal-payments/`. The `patches/` files here are the source of truth and should be byte-identical to what's deployed.

## Creating / updating patches

When a new plugin version is released:

1. Run `./scripts/prepare-analysis.sh` — downloads the latest PPCP release, extracts it, detects the version, creates clean + patched copies in `work/`, and applies the best-match patch.
2. Follow the runbook in `scripts/analyse-paypal-payments.md` to (a) confirm carried-forward hunks still apply and (b) hunt for new bugs and new data-sharing features.
3. Candidate patches are saved to `work/woocommerce-paypal-payments-X.Y.Z-candidate.patch` for testing before promotion to `patches/`.

## Patch format

- Generated with `diff -ruN woocommerce-paypal-payments-X.Y.Z woocommerce-paypal-payments-X.Y.Z-patched` — paths inside the patch are `woocommerce-paypal-payments-X.Y.Z/...`, applied with `patch -p1` from inside the plugin directory (this is what WPatcher does).
- Every patch must include the `// START : wpatcher` … `// END : wpatcher` badge block appended to the main plugin file `woocommerce-paypal-payments.php`. WPatcher uses that marker to detect whether a component is already patched, so **it is required**, not cosmetic. Update its date for each new patch.
- One patch file per plugin version: `patches/woocommerce-paypal-payments-X.Y.Z.patch`.

## Patch style conventions

- Use early returns to disable functions/features rather than deleting code.
- Comment out the original line(s) beneath the change rather than removing them, so the diff documents what was overridden.
- Prefix every change with a `// wpatcher:` comment explaining *why* it's there.
- For bug fixes, prefer real runtime guards (`instanceof`, `isset()`, null checks) over the plugin's `assert()` calls — `assert()` is compiled out in production (`zend.assertions=-1`) and does nothing.
- Keep patches conservative and minimal — fix the bug / disable the unwanted behaviour and nothing else.
- Always `php -l` every changed file, and dry-run `patch -p1` against a pristine extraction before promoting.

## Analysis workflow

To analyse a new PPCP release for patch targets:

1. Run `./scripts/prepare-analysis.sh`.
2. Follow `scripts/analyse-paypal-payments.md` — it covers carrying forward existing hunks, scanning for new outbound HTTP / cron / REST endpoints (the data-sharing angle), and a quick pass for the kind of `assert()`-guarded type bugs that have already bitten us.
3. Promote the candidate to `patches/`, update `CHANGELOG.md` and `docs/patch-targets.md`, and copy the patch to the WPatcher tree for deployment.
