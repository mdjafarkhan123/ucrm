# Communications Activation: Current Checkpoint

## Goal

Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–7 done. Everything stays dark (no live
traffic) until a country launch gate passes.

## Active part

Stage 9 (Twilio Trust Hub ISV registration): 9A/9B/9C are DONE and committed (`89c347d`, `3772b2a`, `44ba025`).
Stage 9D (automatic trigger for 9C's status sync — webhook + daily safety-net poll) is DONE 2026-09-15,
unit-tested against mocks, **files UNCOMMITTED** (Jafar commits explicitly, same pattern as every prior
stage). See ROADMAP.md's "9D" entry for full detail. New files: `trust-hub-status-trigger-store.ts`,
`trust-hub-status-poll-cron.ts` (+ spec), `api/jafar/internal/trust-hub-status-cron/+server.ts` (+ spec),
`api/webhooks/twilio/trust-hub-events/+server.ts` (+ spec); migration `20260920120000_communications_sms_
trust_hub_status_trigger.sql` already **applied to dev DB**; `env.ts` gained two new optional secrets.

Twilio's own guidance recommends the Event Streams push-webhook over polling for exactly this Brand/Campaign
status use case; Jafar approved building both (webhook primary, daily poll as safety net). Because every
contractor's Brand/Campaign lives under UCRM's single ISV Twilio account, only one Event Streams Sink needs
creating platform-wide — **that real (free) action on the live Twilio account is still Jafar's to do**, not
done by this session. Full-project `svelte-check` 0/4218, 19/19 new vitest, Prettier clean.

**Hard constraint, unchanged:** neither the platform nor any contractor has a real registered business yet —
build/test against mocks only, never spend real money firing placeholder data at Twilio's live API.
Business-registration thread stays blocked on Jafar obtaining real Bangladesh business paperwork.

## Exact next action

Independent threads; Jafar picks which to resume:

1. Ask Jafar to review and commit Stage 9D's files (listed above).
2. Jafar creates the one-time Twilio Event Streams Sink + Subscription on the live account (pointed at
   `/api/webhooks/twilio/trust-hub-events`, Basic auth via `TRUST_HUB_EVENTS_WEBHOOK_USERNAME` +
   `TRUST_HUB_EVENTS_WEBHOOK_SECRET`, the 9 Brand/Campaign event types, Batch=false) and sets the matching
   env vars + Vault secrets (`trust_hub_status_cron_target_url`/`_secret`) for the poll route — needed before
   either trigger can actually fire; not required to keep building other Communications work meanwhile.
3. Business registration (blocked on Jafar's paperwork, see above).

Stage 8 (billing reconciliation, recovery and launch proof) stays deferred behind Stage 9's live-proof
prerequisite; its non-blocked pieces (price reconciliation logic, 200-tenant load test) can start in parallel.
A full `vitest run` 2026-09-15 showed 71 pre-existing failures across 11 files, all in quotes/settings-
business/team-invitations — unrelated to Communications, not investigated (out of scope here).

## Constraint

A2P 10DLC cannot be completed for Jafar's test org, or for the platform's own ISV profile, until a real
registered business exists for either. Provider-owned actions (including creating the live Event Streams Sink)
and any real registration fee stay Jafar's explicit call.

Resume: `read memory and continue — communications-activation`.
