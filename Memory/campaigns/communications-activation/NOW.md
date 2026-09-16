# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 6D-1 (inbound MMS picture receiving) is DONE (unit-tested against mocks, all gates met — see
ROADMAP.md's 6D-1 entry for the full verification record). Files are UNCOMMITTED (Jafar commits each stage
explicitly, per this campaign's established pattern).

Next up: Stage 6D-2 (outbound picture sending), not started. Its scope is summarized in ROADMAP.md's 6D-2
entry — no packet exists yet; research it fresh (Rule 2) before writing any code, the same way 6D-1 was
researched before its packet was written.

Stage 9 (Trust Hub ISV registration): 9A–9D all DONE and committed (`89c347d`, `3772b2a`, `44ba025`,
`7c91e84`). Stage 8 (billing reconciliation): 8-1/8-2/8-3 all DONE, committed (`494424e`, `e9db5a6`); full
evidence in `docs/research/communications-stage8-3-scale-evidence-2026-09-15.md`.

## Exact next action

Ask Jafar whether to commit 6D-1 now or continue straight into researching/building 6D-2 first. Either way,
6D-2 needs its own research-first pass (Twilio MMS send limits, GHL's outbound-picture behavior) before a
technical plan or packet is written — do not skip straight to coding from the one-paragraph roadmap summary.

Separately, still waiting on a real action from Jafar, not code:
1. Jafar creates the one-time live Twilio Event Streams Sink for Stage 9D (see Stage 9 in ROADMAP.md).
2. Business registration — still blocked on Jafar's Bangladesh paperwork (see Constraint below); blocks live
   proof for Stage 8, Stage 9, and any live MMS test. This is the actual gate on the campaign going live.

Pre-existing, unrelated: several other SMS/email pgTAP tests fail on a truly clean `supabase db reset --local`
because the outbox wake trigger fails closed against a placeholder Vault URL by design. Out of this campaign's
scope to fix repo-wide; not caused by anything here.

## Constraint

Neither the platform nor any contractor has a real registered business yet. A2P 10DLC cannot complete, and no
live Twilio send/price data can ever exist, until one does. Build and test against mocks only; never spend
real money firing placeholder data at Twilio's live API. Provider-owned actions (creating the live Event
Streams Sink, any real registration fee) stay Jafar's explicit call.

Resume: `read memory and continue — communications-activation`.
