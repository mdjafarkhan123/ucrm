# Part 3: Dedicated Prospect Detail Page

## Approved behavior

Create `/jafar/prospects/[prospectId]` as the home for the existing Prospect detail and owner actions. Follow the current organization-detail route’s structural pattern without copying unrelated organization behavior.

This is a UI structure change. It adds no API, schema, authorization, or business-rule changes.

## Dependencies

- The user explicitly reactivates this deferred work.
- Current Prospect APIs and mutations are audited before planning.
- The existing list/detail behavior is captured from code and tests, not stale line references.

## Checklist

- [ ] Reinspect the Prospect list page, related API routes, unit tests, and organization-detail route.
- [ ] Enumerate every detail field, mutation, pending/error state, confirmation, notification, and cache invalidation currently owned by the list page.
- [ ] Present the updated route/state movement plan and obtain approval.
- [ ] Build the dedicated detail route with breadcrumb, loading, not-found, error, and partial-failure behavior.
- [ ] Move existing Prospect actions without changing their server contracts or authorization.
- [ ] Keep private owner details and raw failures within the existing protected boundary.
- [ ] Stop at the detail-route completion gate before trimming the list page in Part 4.

## Acceptance checks

- A valid row can navigate to the dedicated detail route.
- Direct navigation, refresh, invalid ID, missing record, loading, and API error states are handled.
- Every existing permitted owner action remains available with its existing validation and confirmation behavior.
- Successful mutations refresh the detail and every affected list, dashboard, notification, or operation cache.
- Keyboard and mobile interaction remain usable.
- No backend, schema, permission, or RLS behavior changes.

## Source pointers

- Current Prospect list and API routes under `src/routes/jafar/(protected)/prospects` and `src/routes/api/jafar/prospects`.
- Current `src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte` for route structure only.
- Shared Dialog and confirmation wrappers under `src/lib/components/ui`.
- Relevant permanent owner and onboarding documents named by the Jafar campaign checkpoint.

## Non-discoverable risks

- Moving mutations can leave stale list or notification caches if invalidations remain coupled to component-local state.
- The old external `.claude` plan contained line-number instructions that are no longer authoritative; current code must be re-audited.
