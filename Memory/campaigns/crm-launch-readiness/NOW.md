# CRM Launch Readiness: Current Checkpoint

## Goal

Controlled first launch, then wider access only from measured evidence.

## Current state

Parts 1–4, 10, 11 complete. P9B built 2026-10-10 (`docs/production-release-runbook.md`). Practice server for
P9C–P9F; real server last. No infrastructure is approved.

## Exact next action

Jafar's plan (2026-10-10): finish the whole app first, then production. Real-world tests happen after
production; every test possible before it is run before it. Order:

1. ~~Part 16, Time clock~~ — done 2026-10-12.
2. **Part 12, Alerts** — web build done 2026-10-12 on branch `codex/alerts-part-12` (worktree `.worktrees/alerts-part-12`), NOT yet merged to main. See "Part 12 handover" below.
3. **Part 13, Home screen and Reports.**
4. **Part 14, Customer portal.**
5. **Part 15, Extras**: Quote templates, auto-archive, automation recipes, bulk Visit move, custom fields.
6. **Part 8, final audit** — plus the postponed-work P1 items and every test possible without a server.
7. **Part 9, production** (P9A answer needed first), then real-world tests, then launch.

Part 16 ran as campaign `time-clock` and closed 2026-10-12 (`docs/research/time-clock-final-proof-2026-10-12/final-proof.md`).

## Essential pointers

- `docs/crm-launch-implementation-roadmap.md` § Feature checklist — the one list of missing features.
- `docs/research/jobber-feature-catalog-2026-10-08.md` — Jobber features by plan, with sources.
- `docs/production-readiness-plan.md` — Part 9 plan awaiting P9A approval.

Resume command: `read memory and continue crm-launch-readiness`.


## Part 12 handover (2026-10-12)

Plan: `docs/alerts-behavior-contract.md` (approved; web only, phone push waits for native apps). Built and committed on
`codex/alerts-part-12`: migrations `20261212090000_alert_channels_and_schedule_alerts.sql` and
`20261212100000_alert_followups.sql` (**already applied to the remote database**), the My alerts page
(`/settings/alerts`, linked from the account menu), browser alerts (`src/service-worker.ts`,
`src/lib/team/browser-alerts.ts`, `src/lib/server/team/browser-alerts.ts`), `/api/notifications/preferences` and
`/api/notifications/push`, and the worker hook in `/api/internal/automation/worker`.

Proven: type check 0 errors; 102 unit tests pass; database rules tested on real data (series of 26 Visits = one alert,
move/remove/cancel, Email switch, per-computer delivery, shared computer takeover, gone computer removed, leaver,
12-hour timer, customer message); server delivery proven end to end with a stand-in browser (real keys, decrypted
payload, VAPID header, opens the Job, nothing sent twice); My alerts screen checked at 1568px and 390px.

Left for the next session:
1. **Merge to main** (follow `docs/agent-concurrency.md`), then run `npm install` in main (the branch added
   `web-push`; main's node_modules lacks it), push to GitHub, release the claim `b096b7d7a185`, remove the worktree.
2. **Real-Chrome proof of the pop-up.** Jafar's Brave blocks push by default (needs Settings, Privacy and security,
   "Use Google services for push messaging" on, then restart). Prove in Chrome/Edge/Firefox or Brave with that on:
   turn on, put a teammate on a Visit, see the pop-up, click opens the Job.
3. `src/lib/server/team/invitations.spec.ts` has 4 old lint errors (unused `_` args), not from this work.
4. Update the Pipeline contract (`docs/sales-pipeline-behavior-contract.md` Opportunity Brief actions): Task and mention
   alerts now follow My alerts, as the deferred note required, then delete
   `Memory/deferred/push-alerts-and-per-person-notification-settings.md`.
5. Not built (deliberately): phone push, quiet hours, owner-forced alerts.
