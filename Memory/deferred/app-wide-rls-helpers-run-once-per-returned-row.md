# App-wide RLS helpers run once per returned row

- **Priority:** P2


- **Campaign:** found during `sales-pipeline` Part 1 on 2026-08-18; the fix belongs to whichever campaign
  next touches those tables.
- **Reason:** Fixing it properly means rewriting the policies on clients, properties, client contacts,
  contact methods, communication preferences, requests, assessments, and assessment assignees — all outside
  Part 1's scope. Pipeline was fixed in place because it was the layer being built.
- **What is wrong:** Policies written as `private.is_organization_member(organization_id)` and
  `private.has_permission(organization_id, '...')` reference a column, so Postgres calls them once for every
  row the query returns instead of once for the query. Measured on 50,000 rows: a 50-row page cost 11 ms and
  766 buffers with the per-row helpers, against 2.8 ms and 392 buffers for a 200-row page after the fix —
  and the old cost keeps climbing with page size while the new one stays flat.
- **The fix that worked:** `private.permitted_organizations(permission)` returns a set of organization ids
  and reads no column, so `organization_id in (select private.permitted_organizations('x'))` becomes one
  hashed subplan per query. It already exists and is granted to `authenticated`, so adopting it elsewhere is
  policy rewrites only, no new helper.
- **Reactivation trigger:** Any list page over a table using the per-row helpers gets slow, a tenant passes
  a few thousand rows in `clients` or `requests`, or a campaign is already rewriting those policies.
- **Prerequisites:** `private.can_view_client` mixes membership, permission, and the assigned-work seam, so
  clients and properties need that seam preserved rather than replaced — check it before converting them.
  Re-verify cross-tenant and permission-denied reads on every table converted.
- **Checkpoint:** `supabase/migrations/20260818133726_pipeline_rls_permission_lookup_once_per_query.sql`,
  `supabase/migrations/20260816110139_client_property_permissions.sql`.
- **Measured again on notes, 2026-08-25, during `contractor-settings` 3A.** 5,000 notes hanging off one
  client, a 25-row page: **6,765 ms**. The cost is `private.can_view_linked_entity` called once per row and
  twice per note, not the notes query itself. Converting the policy's author branch to the set-returning
  form made it **worse** (10,059 ms), because a hashable first branch lets the planner hash the whole `OR`,
  which hoists the `EXISTS` into a hashed subplan and evaluates `can_view_linked_entity` across every row of
  `note_links` in the database — work that stops shrinking when the page does. The per-row form keeps a
  lazy nested loop. So the fix for notes is to make `can_view_linked_entity` itself cheap, not to convert
  the policy around it. Owner: whichever campaign next touches the collaboration policies.
- **Do not apply this to tiny fixed-size tables.** Measured 2026-08-21 on `organization_business_hours`
  (7 rows per organization, forever): the per-row `has_permission` form cost 417 buffers / 2.61 ms, the
  `permitted_organizations` form 526 buffers / 2.97 ms. `permitted_organizations` is the heavier function
  and pays its cost once whatever the row count, so it only wins past roughly nine rows. The settings
  policies were converted, measured, and converted back for exactly this reason — leave them alone. The
  fix above is for list tables that grow.

