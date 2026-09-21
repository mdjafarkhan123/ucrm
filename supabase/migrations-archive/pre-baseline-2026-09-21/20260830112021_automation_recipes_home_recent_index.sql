-- Contractor Settings Part 6C, slice 1 (verification follow-up): index the all-status home view.
--
-- The home default view lists an organization's recipes newest-first with no status filter. The status-
-- leading index automation_recipes_home_idx (organization_id, status, updated_at desc, id desc) cannot order
-- that view, so EXPLAIN (ANALYZE) at ~500 recipes/org showed a full per-org scan plus a top-N sort
-- (44ms, 3223 shared buffers). With this (organization_id, updated_at desc, id desc) index the same query is
-- a bounded index scan of the 26 rows it returns, no sort (6.5ms, 359 buffers). The status-filtered views
-- keep using the status-leading index's prefix. Both indexes are justified by evidence on a bounded,
-- infrequently-written per-tenant table.
create index automation_recipes_home_recent_idx
  on public.automation_recipes(organization_id, updated_at desc, id desc);
