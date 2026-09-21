-- Onboarding & Data Portability, Part 3 fix: Price Book import Review/Commit were selecting
-- catalog_items.unit_cost_minor straight from the caller's own session client. 20260910151000 (Part 7 B2, a
-- real security fix) deliberately removed unit_cost_minor from the authenticated column-grant on that table,
-- so Postgres refuses the whole query (42501) the moment any named column isn't granted -- RLS never gets a
-- say. A real browser run confirmed every Review/Commit attempt fails, 100% of the time, any role, owner
-- included.
--
-- Same shape as catalog_item_cost (20260911120000's sibling, 20260910151000): a narrow SECURITY DEFINER
-- function hands cost back to whoever is actually allowed to see it, instead of widening the raw grant back
-- open. Gated on settings.price_book.manage -- the same permission both import routes already require before
-- calling this -- rather than quotes.view_cost, because importing IS managing the Price Book, not merely
-- viewing a quote's cost.

create or replace function public.catalog_items_for_price_book_import(target_organization_id uuid)
returns table (
  id uuid,
  revision integer,
  category text,
  name text,
  description text,
  unit_label text,
  unit_price_minor bigint,
  unit_cost_minor bigint,
  is_taxable boolean,
  is_labor boolean
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
    item.id, item.revision, item.category, item.name, item.description, item.unit_label,
    item.unit_price_minor, item.unit_cost_minor, item.is_taxable, item.is_labor
  from public.catalog_items as item
  where item.organization_id = target_organization_id
    and item.archived_at is null;
end;
$$;

comment on function public.catalog_items_for_price_book_import(uuid) is
  'Every active Price Book item, cost included, for the Review/Commit dry-run to match file rows against. '
  'Needs settings.price_book.manage -- importing manages the Price Book, so this is gated the same as '
  'create/update/delete_catalog_item, not the narrower quotes.view_cost catalog_item_cost uses.';

revoke all on function public.catalog_items_for_price_book_import(uuid) from public;
revoke execute on function public.catalog_items_for_price_book_import(uuid) from anon;
grant execute on function public.catalog_items_for_price_book_import(uuid) to authenticated;

notify pgrst, 'reload schema';
