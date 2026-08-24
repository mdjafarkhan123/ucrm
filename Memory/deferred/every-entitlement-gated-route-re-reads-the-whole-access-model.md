# Every entitlement-gated route re-reads the whole access model

- **Priority:** P2


- **Campaign:** found during `sales-pipeline` Part 1 on 2026-08-18; the fix belongs to the access layer, so
  whichever campaign next touches `src/lib/server/access/effective.ts` should own it.
- **Reason:** The pipeline routes need entitlement checked server-side, and the only resolver available is
  the same one clients, properties and tags already use. Rewriting it is cross-cutting work that would
  touch every gated route and the Jafar panel's write paths, so Part 1 uses it as is.
- **What is wrong:** `resolveOrganizationAccess` runs roughly twelve queries in four sequential waves on
  **every** gated request — packages, features, package features, package limits, feature overrides, limit
  overrides, commercial state, settings, free access, membership, role permissions, member overrides. The
  first four are global reference tables identical for every user in the product.
- **Measured 2026-08-18** against remote Supabase from local dev, median of five: `/api/pipeline/summary`
  623 ms and `/api/clients` 783 ms, both gated, against `/api/requests` 304 ms and `/api/requests/counts`
  219 ms, which only check membership. The gap is the resolver, not the queries the routes actually make —
  the pipeline board's own database work measures 2.7 ms.
- **Reactivation trigger:** A gated page feels slow, or the app moves to the VPS phase where connection
  count matters, or any campaign is already editing the access resolver.
- **Prerequisites:** Decide with Jafar how stale entitlement may be. Likely shape: cache the global
  reference tables in process with a TTL, keep the per-organization and per-member parts live, and flush on
  the Jafar-panel writes that change packages, overrides, or roles. Never cache per-user data across users.
- **Checkpoint:** `src/lib/server/access/effective.ts`, `src/lib/server/access/permission.ts`.

