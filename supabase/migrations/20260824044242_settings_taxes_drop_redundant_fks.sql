-- Contractor Settings, Part 2A follow-up: the security/performance advisor run after the foundation
-- migration caught two mistakes.
--
-- `properties.tax_rate_id` and `quote_versions.tax_rate_id` were each declared with an inline
-- `references organization_tax_rates(id)` *and* a separate composite `(organization_id, tax_rate_id)`
-- foreign key. The single-column one is redundant -- the composite key already enforces both tenant safety
-- and referential integrity -- and having both means every insert/update/delete pays for two FK checks
-- instead of one. Drop the redundant ones; every other table in this schema (request_pricing_lines,
-- quote_versions.discount, etc.) already follows the composite-only convention.
--
-- `quote_versions` is also a high-volume table, unlike the two small settings tables, so its composite FK
-- gets the covering index the advisor asked for.

alter table public.properties drop constraint properties_tax_rate_id_fkey;
alter table public.quote_versions drop constraint quote_versions_tax_rate_id_fkey;

create index quote_versions_tax_rate_idx
  on public.quote_versions(organization_id, tax_rate_id)
  where tax_rate_id is not null;
