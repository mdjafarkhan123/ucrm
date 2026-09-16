# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 2 — active. Invoice sales, Client aging/balances, payment-event (incl. refunds/reversals), payment-allocation,
deposit/available-credit, and tax readers are complete: migrations applied remotely, summaries verified against raw
sums for Raad LTD, cross-tenant call refused (2026-09-16). Remaining ledgers: uninvoiced work, Job/Visit
profitability, sales outcomes, time entries.

## Exact next action

Implement the uninvoiced-work reader: completed Visits and other eligible uninvoiced work per
`docs/financial-reconciliation-contract.md` (reported separately, never as revenue). Establish the eligibility rule
from `docs/jobs-behavior-contract.md` (Requires invoicing) and `docs/invoice-behavior-contract.md` (per-visit
billing) before SQL. Follow the pattern of `supabase/migrations/20260914162859_financial_invoice_tax_reader.sql` and
`src/routes/api/reports/financial/invoice-tax/`. Apply the migration remotely in the same session it is written.

## Blockers

Opening balances wait for Part 2's financial readers and reconciliation proof. No implementation blocker.

## Non-obvious risk

Three reader migrations (allocations, deposits, tax) sat committed but unapplied for two days because a prior session
stopped before applying them. Always confirm `supabase_migrations.schema_migrations` before marking a reader done.

## Essential pointers

- `docs/financial-reconciliation-contract.md`
- `docs/jobs-behavior-contract.md`, `docs/invoice-behavior-contract.md`
- `src/lib/server/validation/financial-reports.schema.ts`
