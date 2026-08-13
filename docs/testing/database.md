# Database Test Execution

## Default path

Prefer the local Supabase test runner because it isolates fixtures from shared data:

```text
npx supabase start
npx supabase test db --local
```

Run a focused file when the active part names one. Database tests must be self-contained, start a transaction, call `finish()`, and roll back their fixtures.

## Linked remote fallback

Use a linked remote database only when local execution is unavailable, the test has been inspected for shared-data assumptions, and Jafar explicitly approves touching that environment.

For a self-contained pgTAP SQL file:

1. Verify it begins a transaction and rolls back.
2. Check fixture inserts against seeded and live uniqueness constraints.
3. Check assertion count matches `plan()`.
4. Execute the file through the approved Supabase SQL tool.
5. Confirm every assertion result, not only the final statement.
6. Verify no fixture rows remain afterward.

When a multi-statement SQL tool returns only the final result, collect assertion output in a temporary table and select it last. If the test changes roles, grant only the temporary-table access required by those roles. Keep the entire operation inside the rollback transaction.

Remote rollback reduces persistence risk but does not make remote execution harmless. Never run an uninspected database test against shared data.
