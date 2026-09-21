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
- **Not yet checked:** whether every local-only file's content is truly applied remotely (a repair must prove it before
  marking rows applied).
