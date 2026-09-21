-- Paid-launch trust, Part 7 (B1): request pricing hands internal cost to office, sales, and now assigned
-- field.
--
-- GET /api/requests/[id]/pricing selected unit_cost_minor and line_cost_total_minor straight into the
-- response, and the same rows are readable directly through PostgREST with the member's own token. The row
-- filter (`private.can_view_request`) is held by owner, admin, finance, office, sales, and field; the money
-- switch (`quotes.view_cost`) is owner, admin, finance only. Same bug, same fix as
-- 20260910151000_catalog_cost_column_leaves_the_authenticated_grant.sql: the two cost columns leave the
-- grant, and a narrow gated function hands them back to whoever is actually allowed to see them.

revoke select on public.request_pricing_lines from authenticated;
grant select (
  id, organization_id, request_id, position, catalog_item_id, category, is_labor,
  name, description, unit_label, quantity, unit_price_minor, is_taxable, line_total_minor,
  image_attachment_id, created_at, updated_at
) on public.request_pricing_lines to authenticated;

-- Cost for one request's pricing lines, keyed by line id. private.can_view_request is the same row-level
-- door the pricing read and write already use; quotes.view_cost is the one switch that governs cost
-- everywhere in Quotes, the Price Book, and now request pricing.
create or replace function public.request_pricing_line_money(target_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  can_cost boolean;
  answer jsonb;
begin
  select request.organization_id into org
  from public.requests as request
  where request.id = target_request_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.can_view_request(org, target_request_id) then
    raise exception 'You do not have access to this request.' using errcode = 'insufficient_privilege';
  end if;

  can_cost := private.member_has_permission(org, caller, 'quotes.view_cost');
  if not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(line.id::text, jsonb_build_object(
      'unit_cost_minor', line.unit_cost_minor,
      'line_cost_total_minor', line.line_cost_total_minor
    )), '{}'::jsonb)
  into answer
  from public.request_pricing_lines as line
  where line.organization_id = org
    and line.request_id = target_request_id;

  return answer;
end;
$$;

comment on function public.request_pricing_line_money(uuid) is
  'Cost for one request''s pricing lines, keyed by line id. Needs the same view access as the pricing read '
  'itself, plus quotes.view_cost to see the cost; a caller holding the first but not the second gets an '
  'empty object.';

revoke all on function public.request_pricing_line_money(uuid) from public;
revoke execute on function public.request_pricing_line_money(uuid) from anon;
grant execute on function public.request_pricing_line_money(uuid) to authenticated;

notify pgrst, 'reload schema';
