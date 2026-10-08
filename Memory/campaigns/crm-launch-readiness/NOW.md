# CRM Launch Readiness: Current Checkpoint

## Goal

Complete the path to a controlled first launch, then widen access only from measured customer and production
evidence.

## Current state

Parts 1–4 complete; 5–8 wait on launch evidence or dependencies. Agreed 2026-10-08: build and test features
locally; do P9B app packaging alongside (no server, no cost); then an hourly-billed practice server (e.g. Hetzner
CX33) for P9C–P9F; real server and first customers last. No infrastructure is approved.

## Exact next action

Part 10 done 2026-10-08: Jafar agreed the labels and chose to build the Urgent items next, before the server
work, with the client reminder switches made to really send (not hidden). Part 11 runs as campaign
`client-reminders`; resume that campaign for the work.

Open for Jafar: P9A — managed Supabase first (recommended) or self-hosted from day one (he wants CLAUDE.md's
self-hosted destination honored); push alerts before first customers or before advertising.

## Essential pointers

- `docs/crm-launch-implementation-roadmap.md` § Feature checklist — the one list of missing features.
- `docs/research/jobber-feature-catalog-2026-10-08.md` — Jobber features by plan, with sources.
- `docs/production-readiness-plan.md` — Part 9 plan awaiting P9A approval.

Resume command: `read memory and continue crm-launch-readiness`.
