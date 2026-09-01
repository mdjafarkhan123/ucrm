# Two migration ledger rows do not match the repo

`supabase db push` is blocked: the remote ledger holds `20260831071453` and `20260831083814`, while the repo
holds `20260831071500_automation_worker_wake_dispatch_ambiguous_column_fix.sql` and
`20260831080000_automation_stop_reason_no_placeholder_when_blank.sql`. Same fixes, different timestamps —
almost certainly applied through the MCP, which assigns its own version.

Deferred because repairing schema history is not this campaign's work, and re-running the two local files
could overwrite live function bodies that were edited after those files were written.

Reactivates when someone needs `supabase db push`, or when Jafar approves a history repair. Until then,
apply migrations through `mcp__supabase__apply_migration` and rename the local file to the version the
ledger records.

Known constraint: base any `create or replace` on `pg_get_functiondef`, not on the repo migration file.
