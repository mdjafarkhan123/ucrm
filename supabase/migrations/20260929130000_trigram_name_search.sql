-- List and global search match names with a leading wildcard (`ilike '%term%'`), which no b-tree index can
-- serve: a term that matches little walks the organization's whole table before giving up (measured
-- 2026-09-28: 2.2 ms at 10,000 clients, growing linearly). Jafar chose on 2026-09-28 to add trigram indexes
-- now rather than wait for a large tenant.
--
-- Every search here is scoped to one organization, so each index leads with organization_id through
-- btree_gin: the scan only ever reads trigram entries inside the caller's own tenant, instead of matching
-- every tenant's rows and filtering afterwards. A term shorter than three characters has no trigram and the
-- planner keeps using the existing b-tree indexes, as it does today.
--
-- Supabase installs extensions into the `extensions` schema.
create extension if not exists pg_trgm with schema extensions;
create extension if not exists btree_gin with schema extensions;

-- Clients list, global search, and duplicate detection: display_name OR company_name.
create index if not exists clients_name_trgm_idx
  on public.clients using gin (organization_id, display_name extensions.gin_trgm_ops,
    company_name extensions.gin_trgm_ops);

-- Global search finds a client by any email or phone it carries.
create index if not exists client_contact_methods_value_trgm_idx
  on public.client_contact_methods using gin (organization_id, value extensions.gin_trgm_ops);

-- Requests list and global search: title OR service_type.
create index if not exists requests_title_trgm_idx
  on public.requests using gin (organization_id, title extensions.gin_trgm_ops,
    service_type extensions.gin_trgm_ops);

-- Quotes and Jobs lists and global search: title (a number search uses the existing number indexes).
create index if not exists quotes_title_trgm_idx
  on public.quotes using gin (organization_id, title extensions.gin_trgm_ops);

create index if not exists jobs_title_trgm_idx
  on public.jobs using gin (organization_id, title extensions.gin_trgm_ops);

-- Global search: invoice subject.
create index if not exists invoices_subject_trgm_idx
  on public.invoices using gin (organization_id, subject extensions.gin_trgm_ops);

-- Catalog picker and list: name OR description.
create index if not exists catalog_items_name_trgm_idx
  on public.catalog_items using gin (organization_id, name extensions.gin_trgm_ops,
    description extensions.gin_trgm_ops);

-- File Manager search: display_name OR caption.
create index if not exists files_name_trgm_idx
  on public.files using gin (organization_id, display_name extensions.gin_trgm_ops,
    caption extensions.gin_trgm_ops);
