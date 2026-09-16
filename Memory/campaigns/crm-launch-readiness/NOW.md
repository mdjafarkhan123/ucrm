# CRM Launch Readiness: Current Checkpoint

## Goal

Complete the nine-part path to a controlled first launch, then widen access only from measured customer and
production evidence.

## Current state

- Part 1 is complete.
- Part 2 is complete except for opening balances. That block is now cleared: `financial-reconciliation` Part 6
  landed the schema, rules and export column. Only the assisted-import screen remains.
- Part 3 is complete 2026-09-16 — `financial-reconciliation` campaign closed all 6 parts; its Memory folder is
  removed. Detail lives in code, migrations, tests and `docs/financial-reconciliation-contract.md`.
- Part 4 is now part of the controlled-first-launch promise.
- Part 9 preparation may run beside remaining parts, but infrastructure implementation still needs Jafar's
  separate topology and migration approval.
- Parts 5–7 follow the controlled first launch; Part 8 is chosen from evidence from those early customers.

## Exact next action

Open `Memory/campaigns/onboarding-and-data-portability/NOW.md` and perform its exact next action (Part 4 —
build the 4-screen opening-balances import wizard). This is the owning sub-campaign for the last piece of
launch Part 2. Jafar does not need to name or track the sub-campaign separately.

When Part 4 closes, Part 2 is complete. Return to this main campaign, read its roadmap, update the nine-part
status, and select the next dependency-ready part (Part 4: minimum website speed-to-lead) automatically.

## Essential pointers

- `Memory/campaigns/onboarding-and-data-portability/NOW.md`
- `docs/crm-launch-implementation-roadmap.md`

Jafar's only required resume command: `continue the CRM launch-readiness campaign`.
