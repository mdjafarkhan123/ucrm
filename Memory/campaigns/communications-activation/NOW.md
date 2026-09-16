# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 6D-1 (inbound MMS) is DONE and committed (`876f29c`).

Stage 6D-2 (outbound picture sending) is DONE and browser-verified 2026-09-16 (files UNCOMMITTED — see
ROADMAP.md for the full record, including two real pre-existing bugs found and fixed: outbound SMS messages
had a null `text_content` that crashed the conversation list, and a sent picture never rendered in its own
thread). Client-side auto-shrink polish is descoped, not a blocker.

## Exact next action

Jafar decides: commit Stages 6D-1 + 6D-2 now, or start Stage 6D-3 (MMS pricing + secure-link fallback for
ineligible sends) first — both are already covered by Jafar's 2026-09-16 approval to build all of 6D. No
research or design decision is blocking either path.

Separately, still waiting on a real action from Jafar, not code:

1. Jafar creates the one-time live Twilio Event Streams Sink for Stage 9D (see Stage 9 in ROADMAP.md).
2. Business registration — still blocked on Jafar's Bangladesh paperwork (see Constraint below); blocks live
   proof for Stage 8, Stage 9, and any live MMS test. This is the actual gate on the campaign going live.

Pre-existing, unrelated: several other SMS/email pgTAP tests fail on a truly clean `supabase db reset --local`
because the outbox wake trigger fails closed against a placeholder Vault URL by design (isolated cause:
`net.http_post` rejects the placeholder secret's non-URL string with "Bad scheme" before the row commits). Out
of this campaign's scope to fix repo-wide. Local verification workaround (session-only, not committed): point
`vault.secrets` row `communications_sms_worker_target_url` at any scheme-valid dummy URL before a full-suite
local pgTAP pass, then `supabase db reset --local` again afterward to restore the committed default.

## Constraint

Neither the platform nor any contractor has a real registered business yet. A2P 10DLC cannot complete, and no
live Twilio send/price data can ever exist, until one does. Build and test against mocks only; never spend
real money firing placeholder data at Twilio's live API. Provider-owned actions (creating the live Event
Streams Sink, any real registration fee) stay Jafar's explicit call. The SMS outbox wake cron
(`dispatch_communication_sms_outbox_wake`) is deliberately left inactive in dev for this same reason — do not
enable it without Jafar's explicit sign-off.

Resume: `read memory and continue — communications-activation`.
