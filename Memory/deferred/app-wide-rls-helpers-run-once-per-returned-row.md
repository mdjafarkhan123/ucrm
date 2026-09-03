# Growing-table RLS helpers run per returned row

- **Priority:** P2
- **Why postponed:** Fixing this crosses Clients, Requests, collaboration, and other growing tables; tiny fixed-size Settings tables do not benefit from the same rewrite.
- **Reactivate when:** A growing list slows down or its policies are already being changed.
- **Constraint:** Preserve assigned-work visibility. Collaboration notes need the linked-entity helper itself optimized; changing only the policy shape made it worse.
- **Constraint:** Wrapping the call in `(select ...)` is not enough on its own. Measured on `job_visits`: the
  subselect stayed correlated on `organization_id` and still ran per row (48.9 ms, unchanged). Only a form the
  planner can hoist to a One-Time Filter collapsed it, so any rewrite must remove the row-column dependency.
- **Measured 2026-09-02 (Schedule Part 2b, 506 rows, one 42-day window):** 52.7 ms / 5023 buffers with the
  policy, 1.1 ms / 434 buffers without it, 3.9 ms when hoisted — the helpers are ~97% of the query's time and
  grow linearly with rows returned. Schedule is the first screen to read 500 rows at once, so it shows the cost
  first; the policy shape is shared, not Schedule-specific.
- **Pointer:** supabase/migrations/20260818133726_pipeline_rls_permission_lookup_once_per_query.sql.
