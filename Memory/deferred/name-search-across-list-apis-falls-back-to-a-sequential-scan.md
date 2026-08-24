# Name search across list APIs falls back to a sequential scan

- **Priority:** P2


- **Campaign:** found during `quotes` Part 2 API review on 2026-08-20. The fix belongs to whichever
  campaign next reworks list search as a whole.
- **Reason:** every list route searches with `ilike '%term%'` — Clients, Requests, and now the catalog
  picker. A leading wildcard cannot use a B-tree, so the search path seq-scans the tenant's rows while the
  unsearched list uses its index. Measured on `catalog_items` seeded to 20,000 rows in a rolled-back
  transaction: unsearched first page 4 buffers / 0.09 ms on `catalog_items_organization_name_idx`, deep
  cursor page 40 buffers / 0.13 ms, the same query with `name ilike '%9500%'` 657 buffers / 36 ms with
  19,998 rows removed by filter.
- **What is at risk:** nothing at a realistic price list or client list size — a few hundred rows stays
  sub-millisecond. The cost is linear in tenant rows, so it becomes real for a large organization, and it
  becomes real on every list at once.
- **Reactivation trigger:** any tenant list passes a few thousand rows, search latency shows up in Query
  Performance, or a campaign is already reworking the shared search helpers.
- **Prerequisites:** `pg_trgm` is not installed on the project. Enabling it plus a GIN trigram index per
  searched column is one decision made once for every list, not per route, and it needs Jafar's schema
  approval like any other migration.
- **Checkpoint:** `src/routes/api/catalog-items/+server.ts`, `src/routes/api/clients/+server.ts`,
  `src/routes/api/requests/+server.ts`.

