# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 2 — active. Invoice sales, current Client aging/balances, immutable payment-event, payment-allocation,
and deposit/available-credit readers are complete through their server APIs. The next ledger is tax.

## Exact next action

Inspect the authoritative tax behavior in `docs/financial-reconciliation-contract.md`,
`docs/invoice-behavior-contract.md`, and the Invoice calculation/frozen-document schemas, then implement the
smallest tenant- and permission-safe tax reader required by the reconciliation contract. Follow the database
skill gates before SQL.

## Blockers

Opening balances wait for Part 2's financial readers and reconciliation proof. No implementation blocker.

## Essential pointers

- `docs/financial-reconciliation-contract.md`
- `docs/invoice-behavior-contract.md` document money and tax behavior
- `supabase/migrations/20260914011420_financial_invoice_sales_reader.sql`
- Invoice calculation and frozen-document migrations located from current code
