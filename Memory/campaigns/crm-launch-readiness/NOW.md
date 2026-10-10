# CRM Launch Readiness: Current Checkpoint

## Goal

Complete the path to a controlled first launch, then widen access only from measured customer and production
evidence.

## Current state

Parts 1–4 complete; 5–8 wait on launch evidence or dependencies. Agreed 2026-10-08: hourly-billed practice server (e.g. Hetzner CX33) for P9C–P9F; real server and first
customers last. No infrastructure is approved.

## Exact next action

Parts 10 and 11 done (2026-10-10: Quote-approval team alert; visit, overdue-invoice, job
follow-up and booking reminders). P9B packaging built 2026-10-10: Node server build, Dockerfile, health routes, GitHub
workflow, `docs/production-release-runbook.md`. Waiting on: Jafar adds 3 GitHub variables and checks the first
"Release image" run goes green (Docker was not available locally). Then the practice server (P9C) after P9A approval.

Open for Jafar: P9A — managed Supabase first (recommended) or self-hosted from day one (he wants CLAUDE.md's
self-hosted destination honored); push alerts before first customers or before advertising.

## Essential pointers

- `docs/crm-launch-implementation-roadmap.md` § Feature checklist — the one list of missing features.
- `docs/research/jobber-feature-catalog-2026-10-08.md` — Jobber features by plan, with sources.
- `docs/production-readiness-plan.md` — Part 9 plan awaiting P9A approval.

Resume command: `read memory and continue crm-launch-readiness`.
