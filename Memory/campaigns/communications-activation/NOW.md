# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–3 are complete. Stage 4 (4A/4B/4C) is done.
Everything stays dark (no send UI, no live traffic) until Stage 5 webhooks + a country launch gate pass.

## Active part
Stage 4 (4A, 4B, 4C) is DONE, verified, and committed (`bcef0aa`, 2026-09-15). **Next dependency-ready part:
Stage 5 (signed inbound + status webhooks).**

**Not verified (carried forward, still open):** no browser check of the SMS worker-health card in the Jafar
control room (no browser tool available in that session) and no live end-to-end pg_net wake (the cron stays
inactive and Stage 5 + the country launch gate are still pending, same constraint 4A/4B had).

## Exact next action
Start **Stage 5: signed inbound and status webhooks** (`docs/communications-a2-implementation-plan.md` §5) —
separate form-encoded Twilio inbound and status routes, official-SDK signature validation against the exact
public URL, token-rotation overlap, durable dedupe, and normalized-number identity resolution (STOP/START/HELP
before identity; one match / no match → Lead+Unassigned / multiple matches → Needs identification). Load the
`twilio-webhook-architecture` and `twilio-messaging-webhooks` skills before writing the routes.

## Constraint
A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay Jafar's.
Stage 4's wake stays inactive (cron created but not scheduled) until Stage 5 + the launch gate.

Resume: `read memory and continue — communications-activation`.
