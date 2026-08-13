# Part 2: Shared Query-Key Conventions

## Approved outcome

Give existing server-state domains stable, reusable query-key families so mutations invalidate every affected view without broad cache resets.

## Dependencies

- Per-layout QueryClient ownership from Part 1 remains intact.
- Existing API routes and server-state ownership remain authoritative.

## Checklist

- [ ] Inventory every query key and invalidation call.
- [ ] Group keys by domain, collection/detail boundary, tenant or owner scope, and filters.
- [ ] Identify mutations that affect more than one collection or detail view.
- [ ] Propose the smallest explicit key-factory interface and obtain approval before implementation.
- [ ] Replace ad hoc keys without unrelated query refactors.
- [ ] Add focused tests for key generation and affected invalidation behavior.
- [ ] Run Svelte/type checks and relevant unit tests.

## Acceptance checks

- Keys are serializable, deterministic, and contain every input that changes returned data.
- Tenant and Platform Owner data cannot share an ambiguous key family.
- Collection invalidation reaches filtered variants without invalidating unrelated domains.
- Detail mutations update or invalidate every affected collection and detail cache.
- No module-level QueryClient singleton is reintroduced.

## Source pointers

- `AGENTS.md` engineering rule 5.
- `src/lib/query-client.ts`.
- `src/routes/+layout.svelte`.
- Current query and mutation call sites discovered at resume time.

## Non-discoverable risks

- Existing domain prefixes such as `crm` and `jafar` are useful but do not by themselves prove tenant separation or complete invalidation.
- Realtime is outside this part and must not be added while key ownership is unsettled.
