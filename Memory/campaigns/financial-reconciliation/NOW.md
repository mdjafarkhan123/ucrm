# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 2 — deliver the required permission-aware operational and financial views/exports.

## Exact next action

Design and add the aging/client-balance reader from the approved receivables rules: effective Invoice balance,
unused Client credit, and net Client balance, with explicit aging buckets, tenant/financial permissions, bounded
pagination, and totals that do not depend on the visible page. Verify it on remote Supabase.

## Blockers

Opening balances wait for Part 2's financial readers and reconciliation proof. No blocker on the next reader.

## Essential pointers

- `docs/financial-reconciliation-contract.md`
- Invoice balance authority in `supabase/migrations/20260905100000_invoice_payments_ledger_and_balances.sql`
- Invoice correction reads in `supabase/migrations/20260910180000_invoice_payment_correction_read_and_filter.sql`
