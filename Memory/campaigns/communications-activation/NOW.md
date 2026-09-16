# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 6D-3 (MMS pricing + secure-link fallback) is DONE: code-complete, locally verified (pgTAP/vitest/
svelte-check/Prettier all green last session), and now browser-verified this session. Still UNCOMMITTED —
`git status`/`git diff` show every touched/new file, same set as before plus one bug fix below.

This session: pushed the three migrations remote dev was missing (`20260923100000` claim-fix,
`20260924100000` 6D-1 inbound media, `20260926100000` 6D-3) via Supabase MCP `apply_migration`, matching the
Stage 3C-1/3C-2 precedent. `20260925100000` (6D-2 outbound media) turned out to already be live on remote
under an earlier version number (`20260916005142`) — confirmed by the 6D-3 migration's own `drop function
... boolean` statements succeeding against it, so it was left alone.

All three original punch-list items are now browser-verified in the Raad LTD test org:
1. Composer's attach control is always visible with the hint text "A file attaches as a secure link in the
   text for this number." — confirmed in the real Conversations UI.
2. MMS rate picker (`SmsRetailRateActions.svelte`) — published a real `US · long_code · mms` rate through the
   Jafar owner UI and confirmed it shows as current after take-effect. Found and fixed a real bug while
   verifying: the retail-rate `<Input>` had `min="0.000001"` against `step="0.0001"`, which are not
   step-aligned, so the native number input rejected almost any normal price (e.g. `0.02`, `0.05`) with "the
   two nearest valid values are X.XX9901/X.XX0001". This is pre-existing code, untouched by this stage's own
   diff, so it silently blocked the segment-rate flow too, not just the new MMS option. Fixed by changing
   `min` to `"0"` (server already enforces `.positive()` in `owner.schema.ts`, so zero still can't publish).
3. Secure-link round trip through `/m/<token>` — verified for real: uploaded a real file through the
   composer to R2 (captured the real presigned object key via a console-logged fetch patch, since the
   extension's network-request tool doesn't see this app's fetch calls), then built one temporary, fully
   isolated `communication_delivery_intents` → `communication_outbound_attachments` (`delivery_mode =
   'secure_link'`) → `communication_sms_attachment_access_links` chain in SQL against Marta Olsen's real
   client/contact/sender rows, generated a real token+hash the same way the app does, and opened
   `/m/<token>` in Chrome — it streamed the real PNG back (browser tab titled "(1×1)"). Deleted the temporary
   intent row immediately after (cascade took the attachment and link with it); verified 0 rows remain.

The org's SMS sender stayed in its real `pending_setup` state throughout (not flipped to fake-ready) — the
full compose→enqueue→claim send path still cannot be exercised end-to-end in the browser until a real
business is registered, per the standing constraint below. The secure-link plumbing itself is proven; only
the surrounding "is this number allowed to send yet" gate is still blocked on that.

## Exact next action

Commit this session's work (Stage 6D-3 migration/code + the `SmsRetailRateActions.svelte` min-attribute fix).
Nothing else is blocking. After commit, decide with Jafar whether Stage 6D is fully closed or whether the
compose→send path deserves a follow-up once a real business/number exists to test against.

Separately, still waiting on Jafar directly (not code): (1) create the live Twilio Event Streams Sink for
Stage 9D; (2) Bangladesh business registration — blocks all live proof (Stage 8, 9, any live MMS test, and
now also blocks ever exercising a real SMS send end-to-end in this environment).

Pre-existing and unrelated to this campaign, found last session, do not re-investigate: a full local pgTAP
run and a full `vitest run` both surface dozens of failures outside communications (stale Stage-1 SMS
fixture, quotes/team/settings specs, website_chat/jobs/quotes pgTAP) — confirmed unrelated by running the
affected files individually.

## Constraint

Neither the platform nor any contractor has a real registered business yet. A2P 10DLC cannot complete, and no
live Twilio send/price data can ever exist, until one does. Build and test against mocks only; never spend
real money firing placeholder data at Twilio's live API. Provider-owned actions (creating the live Event
Streams Sink, any real registration fee) stay Jafar's explicit call. The SMS outbox wake cron
(`dispatch_communication_sms_outbox_wake`) is deliberately left inactive in dev for this same reason — do not
enable it without Jafar's explicit sign-off. Do not flip any organization's SMS sender to a fake `ready`
state to work around this — verify new plumbing with isolated, cleaned-up test rows instead (see this
session's secure-link verification above for the pattern).

Resume: `read memory and continue — communications-activation`.
