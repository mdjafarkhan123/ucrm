# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 6 — close the controlled-launch CRM journey and unblock opening balances. Parts 1–5 are complete and
committed (Part 5 closed 2026-09-16 via the now-finished `sales-pipeline` campaign's final audit; see
ROADMAP.md for the outcome).

## Exact next action

Scope Part 6 before building anything:

1. Decide whether Part 3's CSV acceptance suite (`financial_accounting_package_acceptance.sql`, 68 checks) plus
   Sales Pipeline's own test suite already prove the full Request → Quote → Job → Invoice → Payment chain
   end-to-end, or whether one additional seeded scenario tracing a single record through every stage into the
   export is needed to honestly call the journey-reconciles gate met.
2. Opening-balance implementation is the same work as `onboarding-and-data-portability` Part 4 — read its
   NOW.md, confirm this campaign owns the gate/rules (`docs/financial-reconciliation-contract.md`'s "Opening
   balances" section) while that campaign builds the assisted-import UI, and consolidate under one owner
   before writing any code, the same way Part 5 was tracked once through `sales-pipeline`.
3. Opening balances touch schema (new Client-linked records) — confirm the concrete design with Jafar before
   implementing, per the project's schema-change approval rule.

## Blockers

None to start scoping. Implementation is blocked on the schema-design confirmation in step 3 above.

## Essential pointers

- `docs/financial-reconciliation-contract.md` (see "Opening balances" and "Permission and export rules")
- `Memory/campaigns/onboarding-and-data-portability/NOW.md` (Part 4 — same underlying work, currently paused
  and waiting on this campaign)
