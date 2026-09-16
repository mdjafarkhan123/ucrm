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
3. Committed (`8b195fe`): the opening-balance migration + the 8-check journey trace addition to
   `financial_accounting_package_acceptance.sql`. `CLAUDE.md` stayed out of that commit — confirmed it is
   Jafar's own pre-existing edit (renumbered Non-Negotiable Rules), untouched by this session.
4. Worker RPC built and applied remotely:
   `supabase/migrations/20261002100000_client_opening_balances_worker_rpc.sql` teaches the existing shared
   `process_next_import_row()` (previously Client-only) a second `entity_type`: `'opening_balance'` rows insert
   a fresh `client_opening_balances` fact (`planned_action='create'`) or a correction that inserts the
   corrected fact and marks the predecessor replaced in the same transaction (`planned_action='update'`,
   carrying `predecessor_opening_balance_id`). Locked the `resolved_payload` contract for this entity type in
   the migration's header comment (onboarding-and-data-portability Part 4's Review step must produce this
   shape). Verified remotely in rolled-back transactions: fresh-fact create, correction (predecessor marked
   replaced, root chain intact), correcting an already-replaced fact fails cleanly (row failed, batch
   error_count bumped, queue not wedged) — and regression-checked the untouched Client paths (create, update,
   duplicate-email unique_violation, batch finalization) all still behave identically. Security advisors: no
   findings on the new table or function. **Not yet committed to git.**

## Exact next action

1. Commit `supabase/migrations/20261002100000_client_opening_balances_worker_rpc.sql` (ask Jafar first, per
   the standing rule for schema/DB-writing changes — this session applied it remotely already with his
   continue/"go" approval but the file itself isn't in git yet).
2. Then: wire opening balances into the accountant CSV package (a new CSV + manifest/reconciliation-summary
   entry, per `docs/financial-reconciliation-contract.md`'s "Permission and export rules") and the reconciled
   Client balance (a reader that sums each client's active, unreplaced facts). Both are read-only additions
   layered on the now-stable `client_opening_balances` table.
3. Then hand the 4-screen import UI (Upload/Map/Review/Done for opening balances) to
   `onboarding-and-data-portability` Part 4, pointing it at the `resolved_payload` contract this migration
   fixed.

## Blockers

None — next action is finishing verification, not waiting on anyone.

## Essential pointers

- `docs/financial-reconciliation-contract.md` (see "Opening balances" and "Permission and export rules")
- `supabase/migrations/20260916090000_client_import_foundation.sql` (existing import_batches/import_rows pattern
  the opening-balance rows will reuse)
- `Memory/campaigns/onboarding-and-data-portability/NOW.md` (Part 4 — same underlying work, waiting on this
  campaign)
