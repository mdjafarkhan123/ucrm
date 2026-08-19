-- Clients list moves from offset pagination (page numbers, exact COUNT) to keyset pagination on
-- (updated_at desc, id desc), matching the Requests list. Offset pagination is not allowed in this app.
-- Neither existing index carries id, so a cursor tied on updated_at (bulk imports, bulk edits) could
-- skip or repeat rows.

drop index if exists public.clients_organization_active_idx;

create index clients_organization_active_idx
  on public.clients (organization_id, updated_at desc, id desc)
  where deleted_at is null and archived_at is null;

-- The status filter chip narrows the same keyset scan. The old (organization_id, lifecycle_status)
-- index could not serve the cursor without forcing a sort.
drop index if exists public.clients_organization_status_idx;

create index clients_organization_status_active_idx
  on public.clients (organization_id, lifecycle_status, updated_at desc, id desc)
  where deleted_at is null and archived_at is null;
