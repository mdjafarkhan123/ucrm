# Part 2: Shared Query-Key Conventions

## Outcome

Give existing server-state domains stable key families so mutations invalidate every affected view without broad resets.

## Work

- Inventory every query key and invalidation caller at resume time.
- Group by domain, collection/detail boundary, tenant or owner scope, and filters.
- Identify mutations affecting multiple views.
- Propose the smallest explicit key-family interface and obtain approval.
- Implement without unrelated query refactors and add focused tests.

## Acceptance checks

- Keys are deterministic and include every input that changes returned data.
- Contractor and Platform Owner data cannot share ambiguous keys.
- Collection invalidation reaches filtered variants without touching unrelated domains.
- Mutations update or invalidate every affected collection/detail cache.
- Per-app QueryClient ownership remains intact; Realtime stays out of this part.
