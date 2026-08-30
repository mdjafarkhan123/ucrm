# A1 Return-Path — verified state & approved R1 plan

Outbound proven (NOW.md). This packet = receiving side. Verified read-only 2026-08-28.

## Verified reality (corrects earlier wrong claims)

- pg_cron job `communications-provider-callback-processor` (*/2 min) is ACTIVE and SUCCEEDING; 0 unprocessed
  backlog. Processing is NOT missing. Query cron health by JOB NAME, never jobid.
- Durable inbox = `communication_provider_callback_events` (webhook sink) + SQL processor consumer. Inbound
  parse events (event_kind=inbound_email) also land here but message creation is currently INLINE in the
  webhook (bug: acks 200 even if creation fails → reply lost). That fix is R2.
- Suppression today: hard_bounce → blocks ALL; complaint → blocks OPTIONAL only; soft/deferred/blocked →
  outcome only. `unsubscribed` → outcome only, NO suppression, NOT enforced (real gap).
- Reply aliasing fully wired (ensure_communication_reply_alias in both enqueue paths). Returns null + skips
  Reply-To ONLY because no verified `receiving` domain is onboarded. That is the sole canary Reply-To gap. R2.
- replies.upliftcontractor.com: MX→Brevo inbound, authenticated in Brevo, has an inbound-parse webhook whose
  URL/secret don't match code; BREVO_INBOUND_WEBHOOK_TOKEN absent. All R2.
- Legacy transactional webhook id 2021873 `…/events/cs_5jss…` (no auth) → dead route; active one id 2148798
  `…/transactional` bearer token MATCHES .env. Delete 2021873 only after proving 2148798 processes a real event.

## Approved R1 decisions (Jafar 2026-08-28)

- Unsubscribe = layered: Brevo `unsubscribed` → suppression row reason `unsubscribe` (NEW enum value) w/
  evidence+ts; blocks OPTIONAL email only. Do NOT touch contact_policy or category booleans. Release requires
  renewed consent + Brevo reconciliation (not auto). Category metadata deferred to first category lane.
- Complaint scope CORRECTION: complaint suppresses ALL email now (contract = all non-security), not just
  optional. Security lane exemption is later. So hard_bounce AND complaint block all; unsubscribe blocks optional.
- Essential is only LOCALLY eligible — Brevo may still blocklist recipient for a sender. Surface provider
  `blocked`/`invalid` outcomes; alternate-channel handling is future, just make it visible.
- Poison protection = MINIMUM per-row attempt/error state on the callback table + per-row exception handling
  so one bad callback can't block the batch. NO separate queue / generalized dead-letter.
- R2 keeps delivery-event projection and inbound-message creation as SEPARATE functions; don't merge.

## R1 status (2026-08-29)

CODE + DB + tests LANDED & VERIFIED (see NOW.md for files/evidence). Remaining before A1 closes: the LIVE
controlled-bounce proof (real send → user-visible `bounced` → suppression → resend blocked, cron verified
BY JOB NAME) and deleting legacy webhook 2021873 after active 2148798 is proven on a real event. That live
gate is blocked on Brevo MCP auth (401). Owner health RPC `get_communication_provider_callback_health` is
live. Still do NOT touch inbound / receiving domain / Brevo inbound webhook (R2).
