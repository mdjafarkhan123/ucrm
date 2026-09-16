# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 4 — prove batch Invoice creation and delivery failure handling. Not started. Parts 1–3 are complete and
committed; Part 3's acceptance list lives in
`supabase/tests/database/financial_accounting_package_acceptance.sql` and passes (57 checks).

## Exact next action

Read the existing batch surfaces before designing anything: `src/routes/api/invoices/batch/+server.ts`,
`src/routes/api/invoices/batch/deliver/+server.ts` (+ its `.spec.ts`), `src/routes/api/invoices/ready-to-bill/`
and the `src/routes/(app)/invoices/ready-to-bill` and `/send` pages. Establish what each already guarantees
per item — visible per-item result, idempotency key, and retry that cannot double-bill the same claimed work —
then report the gap to Jafar with a recommendation before implementing. Add the mixed-batch scenario (a failed
item stays visible and is safely retryable without duplicating successful work) to the Part 3 acceptance test
file as part of closing Part 4.

## Blockers

None. Opening balances (Part 6) are unblocked on the reconciliation side: Part 3 proved the ledgers agree, and
opening balances stay out of export schema version 1 by design.

## Non-obvious risk

Invoice claims are the duplicate-billing guard: `public.invoice_sources` is append-only and immutable, and
`private.job_uninvoiced_work` treats a claimed Visit/Job as billed. Any retry path must lean on that claim
rather than on its own bookkeeping. MCP `apply_migration` records its own version number, so
`supabase_migrations.schema_migrations` never lists the repo filename version; confirm a function is live via
`pg_proc`. In the stock role matrix only Owner and Admin hold `invoices.view`, so invoice work cannot be
role-tested with the office/sales/finance logins — use per-member permission overrides.

## Essential pointers

- `docs/financial-reconciliation-contract.md` (Acceptance scenarios, Permission and export rules)
- `supabase/tests/database/financial_accounting_package_acceptance.sql`
