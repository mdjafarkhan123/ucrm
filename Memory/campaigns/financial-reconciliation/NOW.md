# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 3 — accountant-ready CSV package. Part 2 closed 2026-09-16: all ten readers (invoice sales, client aging,
payment events, allocations, deposits/credits, tax, uninvoiced work, Job profitability, sales outcomes, time
entries) are live under `src/routes/api/reports/financial/*` with matching `financial_*_page` /
`financial_*_summary` database functions.

## Exact next action

Design the CSV package before coding (Rule 2): establish how Jobber/QuickBooks-style accountant exports are
shaped (one file per ledger, manifest, fixed two-decimal money with ISO currency, stable IDs), then propose to
Jafar the file list, columns per file, manifest and reconciliation-summary contents, and the delivery shape
(streamed/paged zip from the existing readers, no background queue) per the contract's Scale boundary. After
approval, implement the smallest version and prove it with the contract's seeded acceptance scenarios.

## Blockers

Opening balances (Part 6) wait for Part 3's reconciliation proof. No implementation blocker.

## Non-obvious risk

MCP `apply_migration` records its own version number, so `supabase_migrations.schema_migrations` never lists the
repo filename version; confirm a reader is live by checking `pg_proc` for its functions instead. Raad LTD has no
time entries or expenses, so labor branches can only be proven with rolled-back seed rows (a `do` block ending in
`raise exception` carrying the results works). Scale evidence for all readers is tiny-org only.

## Essential pointers

- `docs/financial-reconciliation-contract.md` (Permission and export rules, Scale boundary, Acceptance scenarios)
- `src/routes/api/reports/financial/` (the readers the package draws from)
