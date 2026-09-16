# Financial Reconciliation: Current Checkpoint

## Goal

Make launch totals agree from source records through accountant-ready CSV, then prove the complete Request →
recorded Payment journey.

## Active part

Part 6 — close the controlled-launch CRM journey and unblock opening balances. Parts 1–5 are complete and
committed (Part 5 closed 2026-09-16 via the now-finished `sales-pipeline` campaign's final audit; see
ROADMAP.md for the outcome).

## Scoping decision (2026-09-16)

1. **Journey-reconciles gate:** existing suites do NOT already prove it. `financial_accounting_package_acceptance.sql`
   seeds Invoices/Jobs directly (not via Request/Quote conversion); the `pipeline_*` suites cover Quote-stage
   transitions but stop before Invoice/Payment. Nothing traces one record from Request through Payment into the
   CSV export. Decision: add exactly one such seeded scenario to close this gate.
2. **Opening-balance ownership:** confirmed. This campaign (Part 6) owns the rules/gate
   (`docs/financial-reconciliation-contract.md`, "Opening balances"). `onboarding-and-data-portability` Part 4 owns
   the assisted-import screen work and stays paused until this campaign's schema/rules land — same pattern Part 5
   used with `sales-pipeline`. Its own `NOW.md` updated to point back here.
3. **Schema:** touches new tables, so needs Jafar's confirmation before implementing (asked this session — see his
   answer before writing any migration).

## Progress (2026-09-16)

1. Jafar approved the opening-balance schema. Applied remotely and confirmed via `pg_constraint` query (all 16
   constraints present, no security advisories):
   `supabase/migrations/20261001100000_client_opening_balances_foundation.sql` — `client_opening_balances`
   table (schema only, mirrors `invoices`' root/predecessor/replaced correction chain), read-gated by
   `invoices.view`, and `import_batches.entity_type` widened to accept `'opening_balance'`.
2. Added the missing single-record trace scenario (Request → Quote → Job → Invoice → recorded Payment → CSV
   export, a dedicated fourth "Package D" org) to
   `supabase/tests/database/financial_accounting_package_acceptance.sql`, bumping `plan(68)` to `plan(76)`.
   Ran the full 76-check file remotely: no SQL error, final assertion `ok 76`. **Independently re-verified**
   by re-running the isolated 8-check trace block alone (`plan(8)`, own transaction, rolled back) and reading
   each TAP line individually — all 8 say `ok` by name. The temp-table grant snag is resolved (no serial
   column, explicit `grant insert, select on tap_log to authenticated`).
3. Nothing committed to git yet. `git status` shows: the new migration file (untracked), the edited test file,
   and this campaign's + `onboarding-and-data-portability`'s `NOW.md`/`ROADMAP.md`. `CLAUDE.md` also shows
   modified — confirmed this is Jafar's own pre-existing edit (renumbered Non-Negotiable Rules, moved the
   "no guesswork" rule up from Working Procedure), not something this session touched or needs to change.

## Exact next action

1. Verification is done. Ask Jafar whether to commit the migration + test file now (nothing committed this
   session yet).
2. Then: write the assisted-import worker RPC that turns a mapped `import_rows` row into a
   `client_opening_balances` insert (the processor half of the table-then-processor split; mirrors the
   client-import worker comment in `20260916090000_client_import_foundation.sql`), wire opening balances into
   the accountant CSV package and reconciled Client balance, and hand the 4-screen import UI to
   `onboarding-and-data-portability` Part 4.

## Blockers

None — next action is finishing verification, not waiting on anyone.

## Essential pointers

- `docs/financial-reconciliation-contract.md` (see "Opening balances" and "Permission and export rules")
- `supabase/migrations/20260916090000_client_import_foundation.sql` (existing import_batches/import_rows pattern
  the opening-balance rows will reuse)
- `Memory/campaigns/onboarding-and-data-portability/NOW.md` (Part 4 — same underlying work, waiting on this
  campaign)
