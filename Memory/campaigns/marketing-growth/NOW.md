# Marketing Growth: Current Checkpoint

## Goal

Ship simple, safe contractor Marketing: one-off email first, with every approved later growth feature preserved.

## State

M1-M4 complete and committed. M4 stage 6 (Marketing-only reputation pause) is live (`20260923120000`).

## Exact next action

Plan M5 (results, replies, attribution) from plan §3 M5 and the roadmap row; present it to Jafar for approval.

## Blockers / open findings (raise with Jafar)

- Both marketing wake cron jobs are active and fail every minute (Vault target URLs unset). Harmless; noisy.
- DLQ alert and warmup-cap starvation in `claim_marketing_campaign_recipient` are recorded as M6 gates.
- M9 SMS marketing blocked on Communications A2. Raad LTD Marketing override + allowance expire 2026-09-24.

## Pointers

`ROADMAP.md`, `docs/marketing-first-release-plan.md` §3. Resume: `continue marketing growth`.
