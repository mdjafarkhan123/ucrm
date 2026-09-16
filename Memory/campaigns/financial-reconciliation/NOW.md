# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 2 — active. Invoice sales, Client aging/balances, payment-event (incl. refunds/reversals), payment-allocation,
deposit/available-credit, tax, and uninvoiced-work readers are complete, applied remotely, and verified against raw
sums for Raad LTD with cross-tenant refusal (2026-09-16). Remaining ledgers: Job/Visit profitability, sales
outcomes, time entries.

## Exact next action

Implement the Job profitability reader per `docs/financial-reconciliation-contract.md`: operational revenue is Job
total less Job tax; cost is snapshotted item cost + rated labor + recorded expenses; unrated labor is disclosed and
excluded. Prices need `jobs.view_price`; costs/profit need `jobs.view_cost` (omit, never zero). Establish the
labor-rate and expense sources from `docs/jobs-behavior-contract.md` and current migrations before SQL. Follow
`supabase/migrations/20260916110000_financial_uninvoiced_work_reader.sql` and
`src/routes/api/reports/financial/uninvoiced-work/` as the pattern. Apply the migration remotely in the same session.

## Blockers

Opening balances wait for Part 2's financial readers and reconciliation proof. No implementation blocker.

## Non-obvious risk

Always confirm `supabase_migrations.schema_migrations` before marking a reader done; three readers once sat committed
but unapplied. Uninvoiced-work amounts are estimates at current Job pricing (same rule as the ready-to-bill queue);
an open whole-price Job is deliberately excluded as work in progress. Scale evidence for the readers is tiny-org only.

## Essential pointers

- `docs/financial-reconciliation-contract.md`
- `docs/jobs-behavior-contract.md`
- `src/lib/server/validation/financial-reports.schema.ts`
