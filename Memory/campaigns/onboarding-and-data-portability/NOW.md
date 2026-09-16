# Onboarding & Data Portability: Current Checkpoint

## Goal

Safe assisted import of a new contractor's core records (no duplicates) and full export out — launch-roadmap
Step 2, the second unstarted gate before the first paying customer.

## Where things stand

**Parts 1–3 and 5 are all DONE, COMMITTED-PENDING, and browser-verified.** Only Part 4 (opening balances)
remains. Campaign is **Paused**. `financial-reconciliation` Part 6 closed 2026-09-16 (campaign complete,
Memory folder removed) — schema, correction-chain rules, permission-aware readers and the CSV export column
are all live and verified. Part 4 is now unblocked: it owns only the assisted-import screen that lets an
office user enter the two opening facts (receivable / credit) once.

## Next action

Build the 4-screen wizard (Upload → Map → Review → Done) on the existing assisted-import pipeline
(`import_batches`/`import_rows`, `entity_type = 'opening_balance'`), pointing at the `resolved_payload`
contract the worker RPC already implements (`supabase/migrations/20261002100000_client_opening_balances_worker_rpc.sql`).
One model only: unpaid Invoices OR a starting balance, never both, per the contract. Follow the Part 1 4-screen
pattern already shipped for client import.

## Blockers

None. Ready to build.

## Essential pointers

- `docs/financial-reconciliation-contract.md` ("Opening balances")
- `supabase/migrations/20261002100000_client_opening_balances_worker_rpc.sql` (worker RPC, `resolved_payload`)
- `supabase/migrations/20261003100000_financial_opening_balances_reader.sql` (readers; not yet committed to
  git, already applied and verified remotely)
- `src/lib/server/exports/financial-export.ts` (`opening_balances.csv` ledger, for column/shape reference)
- Part 1's shipped 4-screen wizard (client import) as the UI pattern to reuse

Resume command: `continue onboarding and data portability`.
