-- Paid-launch trust, Part 7 (B2): the price book's cost gate was bypassable.
--
-- src/lib/server/quotes/selects.ts correctly drops unit_cost_minor from the select list when a member lacks
-- quotes.view_cost, so the app UI is clean. But catalog_items.unit_cost_minor was still in the table-wide
-- `authenticated` SELECT grant, and the RLS row filter (`catalog.view`, held by office and sales too) filters
-- rows, not columns. So office and sales could read the price book's cost column directly through PostgREST
-- with their own session, bypassing the server-side select entirely. Same bug, same fix as
-- 20260831135855_quote_money_columns_leave_the_authenticated_grant.sql: the column leaves the grant, and a
-- narrow gated function hands cost back to whoever is actually allowed to see it.

revoke select on public.catalog_items from authenticated;
grant select (
  id, category, name, description, unit_label, unit_price_minor,
  is_taxable, is_labor, archived_at, created_at, updated_at, revision, updated_by
) on public.catalog_items to authenticated;

-- Cost for a set of price-book items, keyed by item id. catalog.view proves the item is visible at all;
-- quotes.view_cost is the one switch that governs cost everywhere in Quotes and the Price Book, request
-- pricing included, so it is reused here rather than adding a second permission for the same idea.
create or replace function public.catalog_item_cost(target_item_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  can_cost boolean;
  answer jsonb;
begin
  if target_item_ids is null or cardinality(target_item_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct item.organization_id) into organizations
  from public.catalog_items as item
  where item.id = any(target_item_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those price list items do not belong to one organization.'
      using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'catalog.view') then
    raise exception 'You do not have access to this price list.' using errcode = 'insufficient_privilege';
  end if;

  can_cost := private.member_has_permission(org, caller, 'quotes.view_cost');
  if not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(item.id::text, item.unit_cost_minor), '{}'::jsonb)
  into answer
  from public.catalog_items as item
  where item.organization_id = org
    and item.id = any(target_item_ids);

  return answer;
end;
$$;

comment on function public.catalog_item_cost(uuid[]) is
  'Internal cost for a set of price-book items, keyed by item id. Needs catalog.view to see the items exist '
  'and quotes.view_cost to see their cost; a reader holding the first but not the second gets an empty object.';

revoke all on function public.catalog_item_cost(uuid[]) from public;
revoke execute on function public.catalog_item_cost(uuid[]) from anon;
grant execute on function public.catalog_item_cost(uuid[]) to authenticated;

notify pgrst, 'reload schema';
