# Quote write routes have no rate limit

- **Priority:** P1


- **Campaign:** none — found 2026-08-21 during the `quotes` Part 4B API performance review.
- **Reason:** the eight quote command routes follow the app's existing convention and enforce permission and
  validation but no per-organization rate limit. Each save now recalculates the whole draft in the database,
  so a browser stuck in a save loop can hold pooled connections for one tenant and starve the rest. This is
  the whole app's convention, not a 4B decision, which is why fixing it here would have been the wrong scope.
- **Reactivation trigger:** before the first real tenants, or the first time connection use passes 80% of
  `max_connections`.
- **Prerequisites:** one shared limiter keyed by organization used by every `/api/*` mutation, not a
  per-route one. Decide the store (in-process now, Redis at the VPS phase) with the caching approach.
- **Checkpoint:** `src/lib/server/quotes/commands.ts`, `src/routes/api/quotes/[id]/*`.

