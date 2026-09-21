-- Quote money was gated in the routes and in two read functions, but not on the tables themselves. The
-- SELECT policies asked only for `quotes.view`, and `authenticated` held table-wide SELECT, so a member
-- whose "View quote prices" or "View quote costs" switch is off in the Team access editor could still
-- read prices, cost, profit and margin straight off PostgREST with their own session. Jobber's pricing
-- switch is absolute; ours has to be too.
--
-- Two shapes of fix, because the tables are two shapes:
--   * Every row of a deposit schedule item or a deposit receipt is money. Those move to a row filter.
--   * A quote version and its lines carry the customer document as well as its money. Those keep the
--     `quotes.view` row filter and lose the money columns at the grant level; the money comes back
--     through the two gated readers below.

-- 1. Tables whose every row is money -------------------------------------------------------------------

alter policy "permitted members can view quote deposit events" on public.quote_deposit_events
  using (
    private.is_organization_member(organization_id)
    and private.has_permission(organization_id, 'quotes.view_price')
  );

alter policy "permitted members can view quote schedule items" on public.quote_version_schedule_items
  using (
    private.is_organization_member(organization_id)
    and private.has_permission(organization_id, 'quotes.view_price')
  );

-- 2. Money columns leave the authenticated grant --------------------------------------------------------

-- Postgres cannot subtract a column from a table-wide grant, so the table grant goes and every column a
-- reader is still entitled to is named. A column added later is therefore unreadable until it is added
-- here on purpose: the new column fails loudly instead of leaking quietly, which is the safe direction.
revoke select on public.quote_versions from authenticated;
grant select (
  id, organization_id, quote_id, version_number, status, currency_code,
  client_display_name, organization_name, service_address_line1, service_address_line2,
  service_city, service_state_region, service_postal_code, service_country,
  created_by, created_at, updated_at, revision, contract_disclaimer, introduction, client_message,
  show_quantities, show_unit_prices, show_line_totals, show_totals,
  discount_name, discount_type, tax_name, tax_rate_basis_points, tax_source, tax_rate_id,
  document_hash, published_at, deposit_type,
  representative_enabled, representative_name, representative_title,
  representative_signature_object_key, require_customer_signature
) on public.quote_versions to authenticated;

revoke select on public.quote_version_lines from authenticated;
grant select (
  id, organization_id, quote_id, quote_version_id, position, source_catalog_item_id,
  category, is_labor, name, description, unit_label, quantity, is_taxable,
  created_at, updated_at, image_attachment_id, line_kind, selection_kind, is_recommended
) on public.quote_version_lines to authenticated;

-- 3. The gated readers that give the money back ---------------------------------------------------------

-- The totals for a set of versions, keyed by version id. One permission check for the whole call rather
-- than one per row. `discount_value` is in here rather than on the version select because a fixed
-- discount's value is the discount itself, which is customer money like the rest.
create or replace function public.quote_version_money(target_version_ids uuid[])
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
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  if target_version_ids is null or cardinality(target_version_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct version.organization_id) into organizations
  from public.quote_versions as version
  where version.id = any(target_version_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those quote versions do not belong to one organization.'
      using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'quotes.view') then
    raise exception 'You do not have access to these quotes.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'quotes.view_price');
  can_cost := private.member_has_permission(org, caller, 'quotes.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(version.id::text,
      (case when can_price then jsonb_build_object(
         'subtotal_minor', version.subtotal_minor,
         'discount_value', version.discount_value,
         'discount_minor', version.discount_minor,
         'tax_minor', version.tax_minor,
         'total_minor', version.total_minor,
         'deposit_required_minor', version.deposit_required_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'cost_minor', version.cost_minor,
         'profit_minor', version.profit_minor,
         'margin_basis_points', version.margin_basis_points,
         'calculation', version.calculation
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.quote_versions as version
  where version.organization_id = org
    and version.id = any(target_version_ids);

  return answer;
end;
$$;

comment on function public.quote_version_money(uuid[]) is
  'Money for a set of quote versions, keyed by version id. Prices need quotes.view_price and cost, '
  'profit and margin need quotes.view_cost; a reader holding neither gets an empty object.';

revoke all on function public.quote_version_money(uuid[]) from public;
revoke execute on function public.quote_version_money(uuid[]) from anon;
grant execute on function public.quote_version_money(uuid[]) to authenticated;

-- The same answer for one version's lines, keyed by line id.
create or replace function public.quote_line_money(target_version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  can_price boolean;
  can_cost boolean;
  answer jsonb;
begin
  select version.organization_id into org
  from public.quote_versions as version
  where version.id = target_version_id;

  if org is null then
    return '{}'::jsonb;
  end if;

  if not private.member_has_permission(org, caller, 'quotes.view') then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  can_price := private.member_has_permission(org, caller, 'quotes.view_price');
  can_cost := private.member_has_permission(org, caller, 'quotes.view_cost');
  if not can_price and not can_cost then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(line.id::text,
      (case when can_price then jsonb_build_object(
         'unit_price_minor', line.unit_price_minor,
         'line_total_minor', line.line_total_minor
       ) else '{}'::jsonb end)
      ||
      (case when can_cost then jsonb_build_object(
         'unit_cost_minor', line.unit_cost_minor,
         'line_cost_total_minor', line.line_cost_total_minor
       ) else '{}'::jsonb end)
    ), '{}'::jsonb)
  into answer
  from public.quote_version_lines as line
  where line.organization_id = org
    and line.quote_version_id = target_version_id;

  return answer;
end;
$$;

comment on function public.quote_line_money(uuid) is
  'Money for one quote version''s lines, keyed by line id. Prices need quotes.view_price and cost needs '
  'quotes.view_cost; a reader holding neither gets an empty object.';

revoke all on function public.quote_line_money(uuid) from public;
revoke execute on function public.quote_line_money(uuid) from anon;
grant execute on function public.quote_line_money(uuid) to authenticated;

notify pgrst, 'reload schema';
