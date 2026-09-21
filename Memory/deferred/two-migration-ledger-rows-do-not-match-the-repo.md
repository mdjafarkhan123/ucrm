# The repo's migration files cannot rebuild the live database

- **Priority:** P1 candidate — blocks the managed-to-self-hosted rehearsal (a self-hosted database must be rebuildable from the repo).
- **Measured 2026-09-21:** 690 ledger rows, 351 mismatched (162 repo files vs 189 remote versions differ). Of 159 files matching a
  remote row by name, 82 have different SQL; 19 remote rows carry SQL found nowhere in the repo text.
- **Proof it fails:** `npx supabase db diff --linked` (throwaway container; leaves the running local stack alone) stops replaying the
  repo at `20260916110000_financial_uninvoiced_work_reader.sql`: two files share version `20260916110000`
  (`client_import_mapping_rpc` and `financial_uninvoiced_work_reader`), the only such pair. More failures may follow it.
- **Effect:** `supabase db push` is blocked; blind re-runs could overwrite live function bodies edited after their files.
- **Recommended fix — a baseline (needs Jafar's approval, live ledger rows change):**
  1. `supabase db dump --linked` works here (Docker is available): 3.4 MB, 231 tables, 801 functions, 161 policies.
  2. Commit it as one baseline migration; move the old 500 files out of `supabase/migrations/` (git keeps them).
  3. Also carry what a structure dump omits: seed/reference rows (packages, permission defaults, templates) and the `pg_cron`
     schedules the old migrations created. Vault secret values stay per-environment.
  4. Back up the ledger table, then `supabase migration repair` so remote history reads as the baseline.
  5. Proof: `supabase db diff --linked` against a fresh rebuild must come back empty, and the pgTAP files must pass on it.
- **Until then:** apply migrations through `mcp__supabase__apply_migration` and rename the local file to the version the ledger records;
  base any `create or replace` on `pg_get_functiondef`.
