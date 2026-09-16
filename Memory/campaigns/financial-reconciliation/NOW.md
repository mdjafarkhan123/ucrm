# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 2 — active. Invoice sales, Client aging/balances, payment-event (incl. refunds/reversals), payment-allocation,
deposit/available-credit, tax, uninvoiced-work, and Job profitability readers are complete, committed (`1ace123`),
applied remotely, and verified against raw sums for Raad LTD with cross-tenant refusal and cost-permission omission
(2026-09-16). Remaining ledgers: sales outcomes, time entries.

## Exact next action

Implement the sales-outcomes reader per `docs/financial-reconciliation-contract.md`: Pipeline value and Won outcomes
are sales estimates, never revenue, and require Pipeline access (`pipeline.view`; values need `pipeline.view_value`
— omit, never zero). Establish the outcome and value sources from `docs/sales-pipeline-behavior-contract.md` and
current migrations before SQL. Follow `supabase/migrations/20260927100000_financial_job_profitability_reader.sql`
and `src/routes/api/reports/financial/job-profitability/` as the pattern (keyset page + whole-range summary, API
strips unauthorized columns). Apply the migration remotely in the same session.

## Blockers

Opening balances wait for Part 2's financial readers and reconciliation proof. No implementation blocker.

## Non-obvious risk

MCP `apply_migration` records its own version number, so `supabase_migrations.schema_migrations` never lists the
repo filename version; confirm a reader is live by checking `pg_proc` for its functions instead. Job profitability
pairs revenue with cost per pricing basis exactly as `public.job_costing` does; Raad LTD has no time entries or
expenses, so the labor/expense/unrated branches were proven only with rolled-back seed rows. Scale evidence for all
readers is tiny-org only.

## Essential pointers

- `docs/financial-reconciliation-contract.md`
- `docs/sales-pipeline-behavior-contract.md`
- `src/lib/server/validation/financial-reports.schema.ts`
