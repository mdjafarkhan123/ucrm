# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M3 complete. M4 stages 1-4 committed and live. Stage 5 (send/schedule/cancel/test email) is built and was
browser-verified on Raad LTD on 2026-09-23 (test send, schedule then cancel, send now then cancel while sending;
the database confirms recipients were cancelled and allowance returned). It is **not committed yet**. It sits
alongside two owner-panel buttons and grant-fix migration `20260923090100`. Details: `parts/M4.md`.

## Exact next action

Jafar confirms the test email reached `info.socialmediauser1@gmail.com`, then approves the commit of the
uncommitted marketing work (only marketing/owner-panel/access files and migrations `20260923090000` and
`20260923090100`; other campaigns' files are also uncommitted, so leave them out). Then close M4 in ROADMAP and
choose the next part.

## Blockers / open findings

- Cron jobs `communications-marketing-outbox-wake-one-minute` and `...-events-wake-one-minute` are active and
  raise every minute because Vault `communications_marketing_worker_target_url` and
  `communications_marketing_events_worker_target_url` are unset. Nothing sends; it only makes noise. Ask Jafar
  whether to turn them off until deployment.
- M9 (SMS marketing) stays blocked until Communications A2 passes the live SMS checks.
- The Raad LTD Marketing override and the 1000/month allowance expire September 24, 2026.

## Pointers

`parts/M4.md`, `docs/marketing-first-release-plan.md` §3 M4. Resume: `continue marketing growth`.
