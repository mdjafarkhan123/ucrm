-- Onboarding & Data Portability, Part 3 fix, continued: the Price Book export hits the exact same wall as
-- Review/Commit did -- src/lib/server/exports/catalog-export.ts selects unit_cost_minor straight from the
-- caller's own session client, and 20260910151000 (Part 7 B2) removed that column from the authenticated
-- grant. Confirmed live: exporting after the Review/Commit fix still 500s with the same 42501.
--
-- A second narrow function rather than reusing catalog_items_for_price_book_import: export needs every item
-- including archived ones (the Archived column tells them apart), name-ordered to match the Settings list's
-- default sort, and never filters to active-only the way the import dry-run's identity match does.

create or replace function public.catalog_items_for_price_book_export(target_organization_id uuid)
returns table (
  category text,
  name text,
  description text,
  unit_label text,
  unit_price_minor bigint,
  unit_cost_minor bigint,
  is_taxable boolean,
  is_labor boolean,
  archived_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.has_permission(target_organization_id, 'settings.price_book.manage') then
    raise exception 'You do not have access to manage the Price Book.' using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    item.category, item.name, item.description, item.unit_label,
    item.unit_price_minor, item.unit_cost_minor, item.is_taxable, item.is_labor, item.archived_at
  from public.catalog_items as item
  where item.organization_id = target_organization_id
  order by item.name asc;
end;
$$;

comment on function public.catalog_items_for_price_book_export(uuid) is
  'Every Price Book item, active and archived, cost included, for the CSV export. Gated on '
  'settings.price_book.manage, same as the import RPCs -- exporting manages/reads the whole Price Book.';

revoke all on function public.catalog_items_for_price_book_export(uuid) from public;
revoke execute on function public.catalog_items_for_price_book_export(uuid) from anon;
grant execute on function public.catalog_items_for_price_book_export(uuid) to authenticated;

notify pgrst, 'reload schema';
