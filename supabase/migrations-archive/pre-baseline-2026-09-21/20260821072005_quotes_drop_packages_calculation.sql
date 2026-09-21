-- Quotes no longer offer Good/Better/Best packages (part 1 of 2: shape and calculation).

update public.quote_version_lines
set selection_kind = 'required'
where selection_kind = 'package';

alter table public.quote_version_lines
  drop constraint quote_version_lines_package_fk,
  drop constraint quote_version_lines_selection_check,
  drop constraint quote_version_lines_shape_check;

drop index if exists public.quote_version_lines_package_idx;

alter table public.quote_version_lines
  drop column package_id;

alter table public.quote_version_lines
  add constraint quote_version_lines_selection_check
    check (selection_kind in ('required', 'optional')),
  add constraint quote_version_lines_shape_check
    check (
      (
        line_kind = 'priced'
        and category in ('product', 'service')
        and quantity > 0 and quantity <= 1000000
        and unit_price_minor >= 0 and unit_price_minor <= 1000000000000
        and unit_cost_minor >= 0 and unit_cost_minor <= 1000000000000
        and (not is_labor or category = 'service')
      )
      or (
        line_kind in ('text', 'heading')
        and category is null and not is_labor and quantity is null
        and unit_price_minor is null and unit_cost_minor is null and not is_taxable
        and selection_kind = 'required' and not is_recommended
      )
    );

drop function if exists public.preview_quote_version_totals(uuid, uuid, uuid[]);
drop function if exists private.calculate_quote_version(uuid, uuid, uuid[]);

create function private.calculate_quote_version(
  target_version_id uuid,
  selected_addon_ids uuid[] default '{}'::uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.quote_versions;
  selected_subtotal numeric := 0;
  selected_cost numeric := 0;
  non_taxable_subtotal numeric := 0;
  taxable_subtotal numeric := 0;
  discount_amount numeric := 0;
  non_taxable_discount numeric := 0;
  taxable_discount numeric := 0;
  tax_amount numeric := 0;
  revenue numeric := 0;
  profit numeric := 0;
  margin_bps numeric;
  line_count integer := 0;
  line_result jsonb := '[]'::jsonb;
  chosen_addons uuid[] := coalesce(selected_addon_ids, '{}'::uuid[]);
begin
  select * into version_row from public.quote_versions where id = target_version_id;
  if version_row.id is null then
    raise exception 'That quote version was not found.' using errcode = 'no_data_found';
  end if;

  if exists (
    select 1 from unnest(chosen_addons) chosen(id)
    where not exists (
      select 1 from public.quote_version_lines line
      where line.id = chosen.id
        and line.organization_id = version_row.organization_id
        and line.quote_version_id = version_row.id
        and line.line_kind = 'priced' and line.selection_kind = 'optional'
    )
  ) then
    raise exception 'One or more selected add-ons do not belong to this quote version.'
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(line_total_minor), 0), coalesce(sum(line_cost_total_minor), 0),
         coalesce(sum(line_total_minor) filter (where not is_taxable), 0),
         coalesce(sum(line_total_minor) filter (where is_taxable), 0), count(*)
  into selected_subtotal, selected_cost, non_taxable_subtotal, taxable_subtotal, line_count
  from public.quote_version_lines
  where organization_id = version_row.organization_id
    and quote_id = version_row.quote_id
    and quote_version_id = version_row.id
    and line_kind = 'priced'
    and (
      selection_kind = 'required'
      or (selection_kind = 'optional' and id = any(chosen_addons))
    );

  if selected_subtotal > 9223372036854775807 or selected_cost > 9223372036854775807 then
    raise exception 'The selected quote value is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  if version_row.discount_type = 'fixed' then
    discount_amount := least(version_row.discount_value, selected_subtotal);
  elsif version_row.discount_type = 'percentage' then
    discount_amount := round(selected_subtotal * version_row.discount_value / 10000);
  end if;
  non_taxable_discount := least(discount_amount, non_taxable_subtotal);
  taxable_discount := discount_amount - non_taxable_discount;

  with selected as (
    select id, position, is_taxable, line_total_minor
    from public.quote_version_lines
    where organization_id = version_row.organization_id
      and quote_id = version_row.quote_id
      and quote_version_id = version_row.id
      and line_kind = 'priced'
      and (
        selection_kind = 'required'
        or (selection_kind = 'optional' and id = any(chosen_addons))
      )
  ),
  shared as (
    select selected.*,
      case when selected.is_taxable then taxable_subtotal else non_taxable_subtotal end as group_total,
      case when selected.is_taxable then taxable_discount else non_taxable_discount end as group_discount,
      row_number() over (partition by selected.is_taxable order by selected.position, selected.id)
        as group_rank
    from selected
  ),
  rounded as (
    select shared.*,
      case when shared.group_total = 0 or shared.group_discount = 0 then 0
        else floor(shared.group_discount * shared.line_total_minor / shared.group_total)
      end as raw_allocation
    from shared
  ),
  spread as (
    select rounded.*,
      rounded.group_discount - sum(rounded.raw_allocation) over (partition by rounded.is_taxable)
        as group_remainder
    from rounded
  ),
  allocated as (
    select spread.id, spread.position, spread.is_taxable, spread.line_total_minor,
      spread.raw_allocation + case when spread.group_rank <= spread.group_remainder then 1 else 0 end
        as line_discount
    from spread
  ),
  taxed as (
    select allocated.*,
      allocated.line_total_minor - allocated.line_discount as net_amount,
      case when allocated.is_taxable
        then round((allocated.line_total_minor - allocated.line_discount)
          * version_row.tax_rate_basis_points / 10000)
        else 0
      end as line_tax
    from allocated
  )
  select coalesce(sum(line_tax), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'line_id', id,
      'gross_minor', line_total_minor,
      'discount_minor', line_discount::bigint,
      'net_minor', net_amount::bigint,
      'tax_minor', line_tax::bigint,
      'total_minor', (net_amount + line_tax)::bigint
    ) order by position, id), '[]'::jsonb)
  into tax_amount, line_result
  from taxed;

  revenue := selected_subtotal - discount_amount;
  profit := revenue - selected_cost;
  margin_bps := case when revenue = 0 then null else round(profit * 10000 / revenue) end;
  if selected_subtotal - discount_amount + tax_amount > 9223372036854775807 then
    raise exception 'The selected quote total is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  return jsonb_build_object(
    'quote_version_id', version_row.id,
    'selected_addon_ids', to_jsonb(chosen_addons),
    'selected_line_count', line_count,
    'subtotal_minor', selected_subtotal::bigint,
    'discount_minor', discount_amount::bigint,
    'tax_minor', tax_amount::bigint,
    'total_minor', (selected_subtotal - discount_amount + tax_amount)::bigint,
    'cost_minor', selected_cost::bigint,
    'profit_minor', profit::bigint,
    'margin_basis_points', margin_bps::bigint,
    'lines', line_result
  );
end;
$$;

revoke all on function private.calculate_quote_version(uuid, uuid[]) from public;

create or replace function private.refresh_quote_draft_totals(target_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.quote_versions;
  default_addon_ids uuid[];
  calculated jsonb;
begin
  select * into version_row from public.quote_versions where id = target_version_id;

  select coalesce(array_agg(id order by position, id), '{}'::uuid[])
  into default_addon_ids
  from public.quote_version_lines
  where organization_id = version_row.organization_id
    and quote_id = version_row.quote_id
    and quote_version_id = version_row.id
    and line_kind = 'priced' and selection_kind = 'optional' and is_recommended;

  calculated := private.calculate_quote_version(version_row.id, default_addon_ids);

  update public.quote_versions set
    subtotal_minor = (calculated ->> 'subtotal_minor')::bigint,
    discount_minor = (calculated ->> 'discount_minor')::bigint,
    tax_minor = (calculated ->> 'tax_minor')::bigint,
    total_minor = (calculated ->> 'total_minor')::bigint,
    cost_minor = (calculated ->> 'cost_minor')::bigint,
    profit_minor = (calculated ->> 'profit_minor')::bigint,
    margin_basis_points = (calculated ->> 'margin_basis_points')::bigint,
    calculation = calculated
  where id = version_row.id;

  return calculated;
end;
$$;

create function public.preview_quote_version_totals(
  target_quote_id uuid,
  selected_addon_ids uuid[] default '{}'::uuid[]
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_id uuid;
  calculated jsonb;
begin
  select * into quote_row from public.quotes where id = target_quote_id;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.view'
     ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  version_id := coalesce(quote_row.draft_version_id, quote_row.current_published_version_id);
  if version_id is null then
    raise exception 'This quote has nothing to price yet.' using errcode = 'check_violation';
  end if;

  calculated := private.calculate_quote_version(version_id, selected_addon_ids);

  if private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view_cost'
  ) then
    return calculated;
  end if;
  return private.quote_customer_totals(calculated);
end;
$$;

revoke all on function public.preview_quote_version_totals(uuid, uuid[]) from public;
revoke execute on function public.preview_quote_version_totals(uuid, uuid[]) from anon;
grant execute on function public.preview_quote_version_totals(uuid, uuid[]) to authenticated;
