# CRM Launch Readiness: Current Checkpoint

## Goal

Complete the nine-part path to a controlled first launch, then widen access only from measured customer and
production evidence.

## Current state

- Parts 1–4 complete. Parts 5–8 wait on controlled-launch evidence or their named dependencies.
- Part 9 planning resumed 2026-09-20. No infrastructure has been built or changed.
- The corrected plan recommends the easiest robust pilot: immutable app image on one VPS, managed Supabase for
  database/Auth during the pilot, external R2, current DB-driven jobs, and no speculative Redis/BullMQ.
- Self-hosted Supabase remains a later rehearsed destination rather than a first-customer dependency.

## Exact next action

Obtain Jafar's explicit P9A approval or requested changes for the hybrid pilot topology, proposed 15-minute RPO,
four-hour RTO, one-VPS application limitation, separate staging/restore resource, and staged delivery gates.
After approval, start P9B application packaging only. Do not provision infrastructure or touch production data.

## Essential pointers

- `docs/production-readiness-plan.md` — corrected recommendation awaiting P9A approval.
- `docs/research/production-operations-pattern-2026-09-20.md` — current primary-source operations research.
- `Memory/campaigns/crm-launch-readiness/ROADMAP.md` Part 9 row.

Resume command: `continue CRM launch-readiness Part 9 from the P9A approval gate`.
