-- Click-to-sort table headers on the Clients and Requests lists. Each sortable column needs its own
-- keyset-seekable index — the existing indexes only serve the default (updated_at / created_at) order,
-- so sorting by Name, Status, or Title would otherwise force a full sort on every page fetch.

create index clients_organization_name_idx
  on public.clients (organization_id, display_name, id)
  where deleted_at is null and archived_at is null;

create index clients_organization_lifecycle_status_idx
  on public.clients (organization_id, lifecycle_status, id)
  where deleted_at is null and archived_at is null;

-- Requests carry no soft-delete flag, unlike Clients.
create index requests_organization_title_idx
  on public.requests (organization_id, title, id);
