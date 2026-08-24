# Six vitest failures in quote.spec.ts (rpc mock)

- **Priority:** P1
- **Campaign:** none — found while running the full unit suite during `sales-pipeline` Part 5C-iii,
  2026-08-24. Belongs to the `quotes` campaign's in-progress work; nothing here touches it.
  A second cause (the tax proposal-command test) was fixed 2026-08-24 while closing `contractor-settings`
  Part 2A's Quote/Property tax picker slice — its own `proposal-commands.spec.ts` tests were rewritten to the
  five-source `quoteTaxSchema` shape and now pass. A third cause — `role.spec.ts` and `permissions.spec.ts`
  expecting a stale editor to answer 409 and getting 500 — was fixed 2026-08-24 during `contractor-settings`
  Part 2B: `change_team_member_role` and `save_team_member_permissions` were still raising `40001`
  (Postgres' serialization_failure, which PostgREST retries forever) instead of `P0409`, alongside 19 other
  functions across the app with the identical bug. See
  `supabase/migrations/20260902110000_stale_revision_conflicts_are_not_retryable.sql`. Both specs pass now.

## What is wrong

`src/routes/api/quotes/[id]/quote.spec.ts` (6 failures) — `TypeError: supabase.rpc is not a function`.
The route calls `supabase.rpc('quote_ready_for_job', …)` (`src/routes/api/quotes/[id]/+server.ts`) and the
spec's `locals.supabase` mock has no `rpc`.

`npm run check` is clean (0 errors) — this is only the test suite.

## Reactivation trigger

The `quotes` campaign next runs its own tests, or any campaign needs a green full suite before a handoff.
