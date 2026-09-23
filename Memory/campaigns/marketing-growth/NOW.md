# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M3 complete. M4 stages 1-5 committed (`b4f800b`) and proven end to end on Raad LTD 2026-09-23: test email
received, schedule+cancel, send-now+cancel-while-sending, and one real campaign launched -> dispatcher -> SES ->
SQS events -> recipient `delivered`, campaign `completed`, reservation settled 1/1. SQS redrive (5 receives ->
`ucrm-ses-events-dlq`) confirmed working.

## Exact next action

M4 is NOT closed: its gate and plan §3 M4 ("reputation pause stops new Marketing release") are unmet.
`evaluate_communication_email_reputation` measures only operational sends; Marketing bounces/complaints
never trigger a pause (stage 4 deferred this). Proposed stage 6, awaiting Jafar's approval: a Marketing-only
reputation evaluation (bounce/complaint rates over Marketing recipients, rolling windows) that engages a pause
applying to Marketing only, never operational email; only Jafar resumes. Needs SQL/migration approval.
Then close M4 (promote the M4 decisions -- `news.<root>`, `bounce.news.<root>`, `marketing_sending` purpose,
per-org SES tenant/config set -- into plan §3 M4, delete `parts/M4.md`).

## Blockers / open findings (raise with Jafar)

- Both marketing wake cron jobs are active and fail every minute (Vault target URLs unset). Harmless; noisy.
- No alert when anything reaches `ucrm-ses-events-dlq` -- add to M6 gates.
- M9 SMS marketing blocked on Communications A2. Raad LTD Marketing override + allowance expire 2026-09-24.

## Pointers

`parts/M4.md`, `docs/marketing-first-release-plan.md` §3 M4. Resume: `continue marketing growth`.
