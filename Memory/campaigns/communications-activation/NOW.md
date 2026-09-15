# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–3 done, Stage 4 (4A/4B/4C) done.
Everything stays dark (no send UI, no live traffic) until Stage 5 webhooks + a country launch gate pass.

## Active part
**Stage 5A — signed Twilio SMS status callbacks — DONE and verified, ready to commit in this session.**
Helper `src/lib/server/communications/twilio-webhook.ts` (URL builder, `orderedValidationTokens`,
`validateTwilioSignature` via the official `twilio` lib, param parse), route
`src/routes/api/webhooks/twilio/status/+server.ts`, unit + route specs (43 green), pgTAP DB test
`supabase/tests/database/communications_sms_signed_status_webhook.sql` (21 checks; verified live via MCP
begin/rollback, 18/18 pass). Migration `20260919160000` applied to dev; types + advisors clean.

## Next part: Stage 5B — inbound messages
Read the packet `parts/stage-5.md` (5B section). Route `/api/webhooks/twilio/inbound`. Reuse 5A's
`validateTwilioSignature` + `orderedValidationTokens` + AccountSid-lookup-then-validate. STOP/START/HELP
handled before identity; normalized-number identity resolution (one match / none → Lead+Unassigned /
multiple → Needs identification). **Verify the SMS conversation/inbound tables exist before building 5B** —
the schema has moved ahead of older notes (see packet).

## Constraint
A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay
Jafar's. Stage 4's wake stays inactive (cron created, not scheduled) until Stage 5 + the launch gate.

Resume: `read memory and continue — communications-activation`.
