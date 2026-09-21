# The remote migration ledger no longer matches the repo's migration files

- **Priority:** P2 (see the production-cutover constraint below)
- **Measured 2026-09-21** (`npx supabase migration list --linked`): 690 rows, 351 mismatched — 162 repo files with no
  identical remote version, 189 remote versions with no identical repo file. Recent ones are the same fixes under
  different timestamps (the MCP assigns its own version on apply; the repo file was then renamed or kept its own).
  This note used to say "two rows"; it has grown with every migration applied through the MCP.
- **Effect:** `supabase db push` is blocked, and pushing blindly could re-run migrations whose objects were edited
  after their files were written.
- **Reactivate when:** someone needs `supabase db push`, Jafar approves a history repair, or the managed-to-self-hosted
  migration is rehearsed — a self-hosted database has to be rebuildable from the repo, so this must be settled first.
- **Constraint:** Until repaired, apply migrations through `mcp__supabase__apply_migration` and rename the local file to
  the version the ledger records. Base any `create or replace` on `pg_get_functiondef`, not on the repo file.
- **Checked 2026-09-21 (read-only):** repo has 500 files, remote ledger 528 rows. Of the 161 repo files with no identical
  remote version, 159 match a remote row by name but only 77 have the same SQL; 82 differ (the repo file is usually the
  longer, later-edited one). 30 remote rows have no same-named file and 19 of those have SQL found nowhere in the repo
  text (e.g. `financial_uninvoiced_work_reader`, `online_invoice_payments_outcome_fix`). So renaming files is NOT a safe
  repair: the repo cannot be proven to rebuild the live database.
- **Likely fix (needs Jafar's approval):** take an exact structure snapshot of the live database (needs `pg_dump`; no Docker
  or `psql` here), commit it as a new baseline migration, mark the older ledger rows as covered with
  `supabase migration repair`, and rehearse a rebuild from scratch in staging. Old files stay in git history.
