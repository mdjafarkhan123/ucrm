# CRM Launch Readiness: Current Checkpoint

## Goal

Controlled first launch, then wider access only from measured evidence.

## Current state

Parts 1–4, 10, 11, 12 (web) and 16 complete. P9B built 2026-10-10 (`docs/production-release-runbook.md`). No
infrastructure is approved. Classic design system in `classic.pen` approved 2026-10-12.

## Exact next action

Jafar's plan (2026-10-10): finish the whole app, then production, then real-world tests. Order:

1. **Part 13, Home and Reports** — plan approved 2026-10-12 (`docs/home-and-reports-behavior-contract.md`). Six
   desktop screens and a states board drawn in `classic.pen` 2026-10-12; waiting for Jafar's yes — see
   `parts/part-13-home-reports.md`.
2. **Part 14, Customer portal.**
3. **Part 15, Extras** — Quote templates, auto-archive, automation recipes, bulk Visit move, custom fields,
   week-start setting.
4. **Part 8, final audit**, plus postponed-work P1 items and every test possible without a server.
5. **Part 9, production** (P9A answer first), then real-world tests, then launch.

Open from Part 12: Jafar has not decided on an in-page "ding" while the CRM tab is open; `invitations.spec.ts` has 4
old lint errors.

## Essential pointers

- `docs/crm-launch-implementation-roadmap.md` § Feature checklist — the one list of missing features.
- `docs/production-readiness-plan.md` — Part 9 plan awaiting P9A approval.

Resume command: `read memory and continue crm-launch-readiness`.
