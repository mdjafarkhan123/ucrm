# Communications Activation: Current Checkpoint

## Goal
Make Communications deliver email and SMS through a GHL-style unified inbox and provide safe delivery channels
to dependent products such as Marketing. Email is live; SMS Stages 1–3 are complete. Stage 4 is in progress and
stays dark (no send UI, no live traffic) until Stage 5 webhooks + a country launch gate pass.

## Active part
Stage 4A and 4B are DONE and verified. **Next dependency-ready part: 4C (SMS wake + basic owner health).**

## 4B status (done, verified, NOT committed)
Implemented, applied to dev DB, green. Files on disk, UNCOMMITTED (tree entangled with other campaigns — Jafar
commits in batches):
- `supabase/migrations/20260919120000_communications_sms_bounded_worker.sql` — SMS claim/finalize/quarantine +
  release helper; scopes the email quarantine to `channel='email'`. Applied via MCP `apply_migration` (it stamps
  its own history version; disk keeps the future-dated planning filename). Same for 4A's two migrations.
- `src/lib/server/communications/twilio.ts` — added `submitTwilioSms` (Messages adapter, one call, no retries).
- `src/lib/server/communications/sms-worker.ts` + `sms-worker.spec.ts` + `twilio-sms-submit.spec.ts`.
Verified: 19/19 vitest, svelte-check 0/3436, and a rolled-back dev-DB integration proof (finalize money math,
email/SMS quarantine channel isolation, idempotent replay, foreign-lease rejection all OK).

## Exact next action
Start **4C: SMS wake and basic owner health** (`docs/communications-a2-implementation-plan.md` §4C). Mirror the
email autodrain (`20260829030837_communications_email_autodrain_activation.sql`) and its wake-on-insert trigger
(`20260830043551_...`): a separately authenticated `/api/internal/communications/sms-worker` route calling
`runMonitoredSmsWake` (worker name `communications-sms-outbox`), a `dispatch_communication_sms_outbox_wake` cron
function + inactive cron job, a wake-on-insert trigger for `channel='sms'`, and a `get_communication_sms_worker_
health()` read surfaced in the Jafar Communications control room. **Must fix while here:** scope the existing
`get_communication_email_worker_health()` outbox counts to `channel='email'` (today it counts SMS rows too) and
give SMS its own counts. Load `supabase-postgres-best-practices` before the migration. Stage 4 stays dark.
(Optional first: ask Jafar whether to commit 4A+4B before 4C.)

## Constraint
A2P 10DLC cannot be completed for Jafar's test org; nothing actually sends. Provider-owned actions stay Jafar's.
The 4B gate needs no live provider call, and 4C's wake stays inactive (cron created but not scheduled) until the
Stage 5 + launch gate.

## Key reuse pointers (for 4C)
- Generic worker plumbing already exists and is worker-name-keyed: `acquire/release_communication_worker_lease`,
  `record_communication_worker_wake_dispatch/_result`, private `communication_worker_wake_ledger` (20260829030837).
- SMS worker entry point: `runMonitoredSmsWake` in `src/lib/server/communications/sms-worker.ts`.
- Worker route + auth pattern to mirror: `src/routes/api/internal/communications/email-worker/+server.ts`
  (Bearer `COMMUNICATIONS_WORKER_SECRET`, timing-safe compare, `X-Wake-Correlation-Id`).

Resume: `read memory and continue — communications-activation`.
