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
- **Proven fix, 2026-09-07 (Jobs 15a-4):** the whole job family was fixed with
  `supabase/migrations/20260910120000_permission_checks_run_once_per_query.sql`. Split each policy into a
  caller half with no row argument (`private.current_organization()`,
  `private.current_permission_scope(key)`, called as `(select …)` → one InitPlan per statement) and a per-row
  half (`private.is_assigned_to_job`, one index probe, skipped for `all` scope). Schedule one-week window
  161 → 13.7 ms. The clients family is the same defect and the same fix — `private.can_view_client(organization_id, id)`
  still runs per row, and the jobs list plan shows it as a Seq Scan on `clients` and `properties`. Left alone
  in 15a to keep that change to one family.
