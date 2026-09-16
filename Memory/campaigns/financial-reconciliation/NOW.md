# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 2 — active. Invoice sales, Client aging/balances, payment-event (incl. refunds/reversals), payment-allocation,
deposit/available-credit, tax, uninvoiced-work, Job profitability, and sales-outcomes readers are complete, committed
(`caaf04c`), applied remotely, and verified against raw sums for Raad LTD with cross-tenant refusal and permission
omission (2026-09-16). Remaining ledger: time entries.

## Exact next action

Implement the time-entries reader per `docs/financial-reconciliation-contract.md`: identity and duration follow the
existing own/team scope (`time.track_team` sees all; `time.track_own` sees only the caller's own rows — mirror the
select policy in `supabase/migrations/20260910100100_field_assigned_scope_policies.sql`, including
`private.can_view_job`); rated cost needs `jobs.view_cost` (omit, never zero); unrated entries disclosed. Follow
`supabase/migrations/20260927100000_financial_job_profitability_reader.sql` and
`src/routes/api/reports/financial/sales-outcomes/` as the pattern (keyset page + whole-range summary, API strips
unauthorized columns). Apply the migration remotely in the same session. When it is live, Part 2's readers are done;
read the roadmap to close Part 2 and select the next part.

## Blockers

Opening balances wait for Part 2's financial readers and reconciliation proof. No implementation blocker.

## Non-obvious risk

MCP `apply_migration` records its own version number, so `supabase_migrations.schema_migrations` never lists the
repo filename version; confirm a reader is live by checking `pg_proc` for its functions instead. Raad LTD has no
time entries or expenses, so labor branches can only be proven with rolled-back seed rows. Scale evidence for all
readers is tiny-org only.

## Essential pointers

- `docs/financial-reconciliation-contract.md`
- `src/lib/server/validation/financial-reports.schema.ts`
