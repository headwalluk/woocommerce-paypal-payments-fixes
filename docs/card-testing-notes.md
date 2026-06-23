# Card-testing attacks on PPCP — investigation notes

Research notes from the 2026-06-23 investigation into credit-card-testing
attacks that abuse WooCommerce PayPal Payments (PPCP) checkout endpoints.

**Decision up front:** the defence belongs in the **Spam Shield** plugin
(`spam-shield/integrations/integration-woocommerce.php`), *not* in this PPCP
patch repo. Rationale and signal design below. This file is the parked record so
the Spam Shield work can pick up without re-deriving it.

---

## Why not a PPCP patch

- Spam Shield already owns the correct interception point:
  `woo_maybe_block_order_by_customer_data()` fires on `init` with an exact-URI
  match on the payment endpoints and `wp_die()`s. PPCP registers those endpoints
  with `add_action('wc_ajax_ppc-create-order', …)` at priority 10
  (`modules/ppcp-button/src/ButtonModule.php:134`), so the `init` gate runs
  first. **Hook placement is already right — the gap is the detection signals.**
- This repo's patches *remove* vendor behaviour, stay minimal, and are rebased
  every PPCP release. Anti-carding is additive, cross-cutting, signal-driven, and
  Spam Shield is already deployed fleet-wide. Wrong home.
- PPCP offers nothing better to hook (`do_action(
  'woocommerce_paypal_payments_create_order_request_started')` inside
  `CreateOrderEndpoint::handle_request()` is later and weaker than the existing
  gate).

**ACDC stays ON.** Clients need Advanced Card Processing (guest card-without-
PayPal-login), so disabling it — the biggest single surface reduction — is off
the table. That makes the request-time gate the primary defence.

---

## The attack(s)

PPCP's smart-button / ACDC endpoints (`?wc-ajax=ppc-create-order`,
`ppc-approve-order`, `checkout`) are abused to fire stolen PANs at PayPal and
read approve/decline as a liveness oracle. `ppc-create-order` mints a real
PayPal order; the ACDC card-fields submit goes browser→PayPal (PAN never hits
our server), so the only server-side evidence is endpoint hits + velocity.

### Pattern A — single-IP replay (21 Jun dump)

One IP runs the whole cycle in 8–14s, no real navigation first (parachutes into
`update_order_review` — no product GET, no `add_to_cart`, no `GET /checkout/`):

```
POST /?wc-ajax=update_order_review     (referer /checkout/)
POST /?wc-ajax=ppc-data-client-id
POST /?wc-ajax=ppc-create-order        200 ~613B
POST /?wc-ajax=ppc-approve-order       200 ~632B  (1st card)
POST /?wc-ajax=ppc-approve-order       200 ~4580B (decline retry — large body)
POST /?wc-ajax=checkout
```

IPs: `91.240.67.8`, `195.86.12.159` (hosting/proxy ranges). `ppc-*` requests
carry `referer: -`.

### Pattern B — warmed cookie + mid-session IP rotation (23 Jun dump)

The evasion of the current Spam Shield gate. One logical session split across two
AWS IPs:

```
54.236.242.91  GET /product/apple-...keyboard-overlay   ← warmup
54.236.242.91  POST add_to_cart                         ← sets woocommerce_items_in_cart
54.236.242.91  GET /checkout/                           ← sets spmshld cookie
54.236.242.91  update_order_review … ppc-approve-order
13.238.143.19  POST ppc-approve-order  (4579B decline)  ← IP HOPS, same session
13.238.143.19  POST checkout
```

This one passed the gate, then was only stopped by PayPal's own anti-fraud. We
should have blocked it.

---

## Why the current Spam Shield gate failed on Pattern B

Two independent reasons, both engineered by the attacker:

1. **Cookie-presence test defeated by warming.** They do a real `add_to_cart` +
   `GET /checkout/` first, so both `woocommerce_items_in_cart` and `spmshld`
   (`HAS_RUN_AJAX_MAGIC`) are legitimately set, then replayed. The
   `OPT_WOO_REQUIRE_COOKIES_AT_CHECKOUT` check passes.
2. **Failed-order velocity defeated by rotation.**
   `woo_maybe_block_create_order()` queries `wc_get_orders(['customer_ip_address'
   => $ip])`. The IP rotates every order, so no single IP reaches the 5-failure
   threshold. The counter is keyed on the one field the attacker controls.

---

## Signals that survive cookie-theft AND IP-rotation (ranked)

1. **Datacenter / hosting-ASN check on the payment endpoints — highest value,
   and the chosen direction.** Every attacker IP across both dumps is cloud/
   hosting (`54.236.x`, `13.238.x` AWS; `91.240.67.8`, `195.86.12.159` hosting).
   Real retail buyers essentially never check out from AWS/GCP/Azure/OVH/DO. Near-
   zero false positives. Catches the AWS→AWS hop that session-pinning alone might
   miss. **Plan: Spam Shield SaaS IP-reputation returns `isDataCenter: true|false`
   (see below); Woo integration gets a checkbox "block checkout interactions from
   data-centre IPs".** A prior DNS-based ASN attempt was not robust and was
   dropped — use the SaaS reputation API, not DNS.
2. **Session→IP binding (backstop, no external data).** Bind the WC session /
   `spmshld` cookie to the first IP that established it; reject `ppc-*`/`checkout`
   when the presenting IP changes mid-session. Kills mid-session rotation *and* a
   stolen cookie replayed from another IP. **FP guard:** pin on `/24` (v4) /
   `/64` (v6), not exact IP, so a mobile WiFi↔cellular handover doesn't trip it;
   or only hard-block when the new IP is also datacenter.
3. **Velocity keyed on session + product, not just IP.** Re-key the failed-order
   counter off session token / cart fingerprint / targeted SKU so rotation can't
   reset it. The same SKU (`apple-ultrathin-photoshop-shortcut-keyboard-overlay`)
   is hit on both 21 Jun and 23 Jun — carders pick one cheap product and hammer
   it. Natural `spam_shield_woo_is_cart_probably_fake` rule.
4. **`approve-order` retry counter.** A genuine buy approves once; carders fire
   `ppc-approve-order` twice (2nd = ~4579B decline body). Count per session, block
   the 2nd within N seconds.

The existing cookie test stays as *one* layer — no longer load-bearing.
Signals 1+2 are what de-blunt it.

---

## The concrete plan (Spam Shield)

1. **Back end — DONE.** IP-reputation API (`api2.spamshield.cloud/ip/<ip>`,
   surfaced in the plugin via `spam_shield_get_ip_address_info()`) now returns
   `isDataCenter: true|false` plus `asn`, `asnOrg`, `isAlwaysAllowed`,
   `isHardBlocked`, `score`. (The `net-ip-lookup.sh` CLI prints `null` due to an
   HTTPie quirk — ignore; the PHP path is correct.)
2. **Plugin — DONE (2026-06-23).** `integration-woocommerce.php` extended with:
   - New gate `woo_maybe_block_checkout_from_datacenter()` on `init` (priority 10),
     which looks up the client IP and `wp_die()`s on `isDataCenter` (unless
     `isAlwaysAllowed`).
   - **Two independent checkboxes** (per-path scope — the agreed decision, so a
     site can protect classic endpoints without blocking VPN shoppers on Block
     checkout, and vice-versa):
     - `OPT_WOO_BLOCK_DC_CLASSIC` → `/?wc-ajax=ppc-create-order|ppc-approve-order|checkout`
     - `OPT_WOO_BLOCK_DC_REST` → `/wp-json/wc/store/checkout`
   - **Fails open** (only an explicit `isDataCenter === true` blocks; API outage
     can't stop checkouts), honours `is_spam_checking_required()`, and reports the
     IP via `report_ip_activity()` + a `SpamWooBlock IP=… DATACENTER=<asnOrg>` log
     line. Filters: `spam_shield_woo_datacenter_guarded_endpoints`,
     `spam_shield_woo_is_datacenter_checkout`.
   - **Defaults OFF** (admin opts in; labels say "recommended"). Not wired into
     `woo_first_time_configuration` — revisit if we want new installs default-on.
3. Later, layer in session-IP pinning (#2) and session/product-keyed velocity
   (#3) as additional scored signals.

### Resolved open items
- Caching: already handled inside `spam_shield_get_ip_address_info()` (transient
  `ss_ip_<ip>`, TTL filter `spam_shield_ip_cache_ttl`) — one lookup per IP per
  window, not per request.
- Fail-open: chosen and implemented.
- Proxy IP: `pp_get_browser_ip_address()` walks
  `X-Real-IP → Client-IP → X-Forwarded-For → REMOTE_ADDR`, so it returns the true
  client IP behind the reverse proxy.

### Note on the data
`38.213.129.131` — earlier mis-classified as a legit shopper in the 21 Jun dump —
is actually `isDataCenter: true` ("OCTOPUS WEB SOLUTION INC"). So even the
well-behaved warm-up sessions are bots; the data-centre signal catches them.
