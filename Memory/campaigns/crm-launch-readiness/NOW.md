# CRM Launch Readiness: Current Checkpoint

## Goal

Controlled first launch, then wider access only from measured evidence.

## Current state

Parts 1–4, 10, 11 complete. P9B packaging built 2026-10-10 (`docs/production-release-runbook.md`). Practice server
(hourly Hetzner CX33) is for P9C–P9F; real server and first customers last. No infrastructure is approved.

## Exact next action

Jafar's priority order (2026-10-10):

1. **Part 9, production** — the only launch blocker. Needs P9A answer and 3 GitHub variables (first "Release image" run unchecked); then P9C.
2. **Part 12, Alerts** — can be built locally while Part 9 waits.
3. **Part 13, Home screen and Reports.**
4. **Part 14, Customer portal.**
5. **Part 15, Extras**, in this order: Quote templates, auto-archive, automation recipes, bulk Visit move, day clock in/out.
6. **Part 8, final audit**, last. Part 5 follows business registration.

Next session: ask for the P9A answer (managed Supabase first, recommended, or self-hosted from day one); if not given, start Part 12 as its own campaign.

## Essential pointers

- `docs/crm-launch-implementation-roadmap.md` § Feature checklist — the one list of missing features.
- `docs/research/jobber-feature-catalog-2026-10-08.md` — Jobber features by plan, with sources.
- `docs/production-readiness-plan.md` — Part 9 plan awaiting P9A approval.

Resume command: `read memory and continue crm-launch-readiness`.
