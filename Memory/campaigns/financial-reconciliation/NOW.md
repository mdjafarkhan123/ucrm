# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 3 — accountant-ready CSV package. **Built, live and browser-verified 2026-09-16; not yet closed.**
Design approved by Jafar 2026-09-16 (research: QuickBooks "Export data" zip, Stripe balance reports, Jobber
per-report CSV). Delivered: `GET /api/exports/financial?from&to` (max 366 days, rate-limited) streaming a zip
from the `financial_*_page` readers at 500 rows/page; 12 CSVs + `manifest.json` + `reconciliation_summary.json`
(15 summary-vs-rows agreement checks); new read-only `financial_expenses_page` (applied remotely, index
`job_expenses_date_idx`); download card in Settings → Invoices. Unit spec passes; real Raad LTD year package:
22 RPCs, 1.7 s, all 15 checks agree; expenses function proven with rolled-back seed rows, cross-tenant and
sales-role refusal.

## Exact next action

Close Part 3's completion gate: run the contract's seeded acceptance scenarios (void, rebill chain, write-off
and restore, Mark Received, reversal, moved allocation, rated/unrated labor, expense, uninvoiced Visit) as one
rolled-back `do` block against Raad LTD and confirm each traces into its CSV via the readers' paged functions and
that every summary-vs-rows check still agrees. Also review the package with the `office`/`finance` test logins
(Settings → Invoices → Download package) to confirm omitted files/columns match their permissions. Then record
the outcome in the roadmap, close Part 3, and select Part 4 (batch Invoice creation).

## Blockers

Opening balances (Part 6) wait for Part 3's reconciliation proof. No implementation blocker.

## Non-obvious risk

MCP `apply_migration` records its own version number, so `supabase_migrations.schema_migrations` never lists the
repo filename version; confirm a reader is live via `pg_proc`. Raad LTD has no time entries or expenses, so
labor/expense branches can only be proven with rolled-back seed rows (insert as the admin connection, then
`set_config('request.jwt.claims', …)` to impersonate — setting `role` first blocks the insert). Chrome's
extension reports a download navigation as "503" even when the file saved (Downloads land in
`/mnt/storage/Downloads`). `client_balances.csv` is a current snapshot aged as of the download day, not a
period-end balance — the manifest says so. Scale evidence is tiny-org only.

## Essential pointers

- `docs/financial-reconciliation-contract.md` (Acceptance scenarios, Scale boundary)
- `src/lib/server/exports/financial-export.ts` and its `.spec.ts`
- `src/routes/api/exports/financial/+server.ts`
