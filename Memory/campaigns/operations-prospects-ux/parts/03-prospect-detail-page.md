# Part 3: Dedicated Prospect Detail Page

## Approved behavior

Move existing Prospect detail and owner actions to /jafar/prospects/[prospectId], following the current organization-detail structure. Add no API, schema, authorization, or business-rule changes.

## Work

- Reinspect current Prospect UI, routes, tests, mutations, and invalidations.
- Account for every existing field, action, state, confirmation, notification, and affected cache.
- Present the updated movement plan and obtain approval.
- Build the route and stop before trimming the list page.

## Acceptance checks

- Row navigation, direct load, refresh, invalid/missing record, loading, error, and partial-failure states work.
- Every permitted action retains its validation, confirmation, permission, and invalidation behavior.
- Keyboard and mobile use remain accessible.
- No backend, schema, permission, or RLS behavior changes.
