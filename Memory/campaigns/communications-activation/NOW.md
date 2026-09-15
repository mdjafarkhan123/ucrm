# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 9 (Trust Hub ISV registration): 9A–9D all DONE and committed (`89c347d`, `3772b2a`, `44ba025`, `7c91e84`).

Stage 8 (billing reconciliation): **8-1 Price reconciliation** and **8-2 Account usage-window reconciliation**
both DONE 2026-09-15, unit-tested, full-project `svelte-check` 0/4230, Prettier clean, applied to dev DB,
Supabase advisors show only expected baseline noise, and **COMMITTED** (`494424e`).

## Exact next action

Independent threads; Jafar picks which to resume:

1. **Build Stage 8-3**, the 200-tenant scale evidence run — not started, independent of everything else.
2. Jafar creates the one-time live Twilio Event Streams Sink for Stage 9D (see Stage 9 in ROADMAP.md) — real
   action on the live account, not automatable.
3. Business registration — still blocked on Jafar's Bangladesh paperwork (see Constraint below); blocks live
   proof for both Stage 8 and Stage 9.

## Constraint

Neither the platform nor any contractor has a real registered business yet. A2P 10DLC cannot complete, and no
live Twilio send/price data can ever exist, until one does. Build and test against mocks only; never spend
real money firing placeholder data at Twilio's live API. Provider-owned actions (creating the live Event
Streams Sink, any real registration fee) stay Jafar's explicit call.

Resume: `read memory and continue — communications-activation`.
