-- Quotes Part 6A: deposit and payment-schedule foundation -- schema and calculation only.
--
-- A quote has either no deposit requirement or one payment schedule: deposit-only carries its single
-- required installment directly, and a milestone schedule carries ordered installments whose first one is
-- the required deposit. Percentage installments recalculate from whatever total the customer's current
-- add-on selection actually produces, so the amount is computed here the same way discount and tax already
-- are -- nothing outside the database owns this arithmetic. Configuring a schedule, recording an offline
-- deposit, and showing any of this to staff or the customer are separately gated work in Part 6B and 6C.

-- 1. A version's own ordered installments -------------------------------------------------------------------

create table public.quote_version_schedule_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  quote_id uuid not null,
  quote_version_id uuid not null,
  position integer not null check (position >= 0),
  description text not null check (char_length(trim(description)) between 2 and 160),
  value_type text not null check (value_type in ('fixed', 'percentage')),
  value bigint not null,
  is_deposit boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_version_schedule_items_organization_id_unique unique (organization_id, id),
  constraint quote_version_schedule_items_version_scoped_unique
    unique (organization_id, quote_id, quote_version_id, id),
  constraint quote_version_schedule_items_position_unique
    unique (organization_id, quote_version_id, position),
  constraint quote_version_schedule_items_version_fk
    foreign key (organization_id, quote_id, quote_version_id)
    references public.quote_versions(organization_id, quote_id, id) on delete cascade,
  constraint quote_version_schedule_items_value_range_check check (
    (value_type = 'percentage' and value between 1 and 10000)
    or (value_type = 'fixed' and value between 1 and 1000000000000)
  )
);

comment on table public.quote_version_schedule_items is
  'A version''s own ordered payment installments. Deposit-only carries exactly one row; a milestone schedule '
  'carries several. The is_deposit row is the one approval must collect before the job is ready.';

-- Exactly one row per version may be the deposit -- deposit-only has nothing else to be, and a milestone
-- schedule points its first installment at it.
create unique index quote_version_schedule_items_one_deposit_idx
  on public.quote_version_schedule_items(organization_id, quote_version_id)
  where is_deposit;

create index quote_version_schedule_items_version_idx
  on public.quote_version_schedule_items(organization_id, quote_id, quote_version_id, position, id);

create trigger quote_version_schedule_items_set_updated_at
before update on public.quote_version_schedule_items
for each row execute function public.set_updated_at();

-- 2. A version knows its own deposit shape --------------------------------------------------------------------

alter table public.quote_versions
  add column deposit_type text,
  add column deposit_required_minor bigint not null default 0,
  add constraint quote_versions_deposit_type_check check (
    deposit_type is null or deposit_type in ('deposit_only', 'schedule')
  );

alter table public.quote_versions
  drop constraint quote_versions_totals_check,
  add constraint quote_versions_totals_check check (
    subtotal_minor >= 0 and discount_minor >= 0 and tax_minor >= 0 and total_minor >= 0
    and cost_minor >= 0 and discount_minor <= subtotal_minor
    and deposit_required_minor >= 0 and deposit_required_minor <= total_minor
  );

comment on column public.quote_versions.deposit_required_minor is
  'Database-owned, same as subtotal/discount/tax/total: the calculator''s answer for the current selection, '
  'not a value anything else may write.';

-- 3. The calculator prices the deposit the same way it prices tax ----------------------------------------------

create or replace function private.calculate_quote_version(
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
  total_amount numeric := 0;
  deposit_amount numeric := 0;
  deposit_item public.quote_version_schedule_items;
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

  total_amount := selected_subtotal - discount_amount + tax_amount;
  if total_amount > 9223372036854775807 then
    raise exception 'The selected quote total is too large.' using errcode = 'numeric_value_out_of_range';
  end if;

  -- A percentage deposit is a share of what the customer's current selection actually totals, so it moves
  -- with add-ons exactly like tax does; a fixed deposit is capped the same way a fixed discount is.
  if version_row.deposit_type is not null then
    select * into deposit_item
    from public.quote_version_schedule_items
    where organization_id = version_row.organization_id
      and quote_version_id = version_row.id
      and is_deposit;
    if deposit_item.id is null then
      raise exception 'This quote''s deposit is missing its required installment.'
        using errcode = 'check_violation';
    end if;
    if deposit_item.value_type = 'fixed' then
      deposit_amount := least(deposit_item.value, total_amount);
    else
      deposit_amount := round(total_amount * deposit_item.value / 10000);
    end if;
  end if;

  revenue := selected_subtotal - discount_amount;
  profit := revenue - selected_cost;
  margin_bps := case when revenue = 0 then null else round(profit * 10000 / revenue) end;

  return jsonb_build_object(
    'quote_version_id', version_row.id,
    'selected_addon_ids', to_jsonb(chosen_addons),
    'selected_line_count', line_count,
    'subtotal_minor', selected_subtotal::bigint,
    'discount_minor', discount_amount::bigint,
    'tax_minor', tax_amount::bigint,
    'total_minor', total_amount::bigint,
    'deposit_required_minor', deposit_amount::bigint,
    'cost_minor', selected_cost::bigint,
    'profit_minor', profit::bigint,
    'margin_basis_points', margin_bps::bigint,
    'lines', line_result
  );
end;
$$;

revoke all on function private.calculate_quote_version(uuid, uuid[]) from public;
revoke execute on function private.calculate_quote_version(uuid, uuid[]) from anon, authenticated;

-- 4. Draft totals and the frozen document both persist the deposit the same way they persist tax --------------

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
    deposit_required_minor = (calculated ->> 'deposit_required_minor')::bigint,
    cost_minor = (calculated ->> 'cost_minor')::bigint,
    profit_minor = (calculated ->> 'profit_minor')::bigint,
    margin_basis_points = (calculated ->> 'margin_basis_points')::bigint,
    calculation = calculated
  where id = version_row.id;

  return calculated;
end;
$$;

revoke all on function private.refresh_quote_draft_totals(uuid) from public;
revoke execute on function private.refresh_quote_draft_totals(uuid) from anon, authenticated;

create or replace function public.freeze_quote_version(target_quote_id uuid, expected_revision integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  draft_row public.quote_versions;
  default_addon_ids uuid[];
  next_version_number integer;
  calculated jsonb;
  canonical jsonb;
  frozen_hash text;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to publish this quote.' using errcode = 'insufficient_privilege';
  end if;
  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be frozen.' using errcode = 'check_violation';
  end if;

  select * into draft_row from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'draft'
  for update;
  if draft_row.id is null then
    raise exception 'This quote has no draft to freeze.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  select coalesce(array_agg(id order by position, id), '{}'::uuid[])
  into default_addon_ids
  from public.quote_version_lines
  where organization_id = quote_row.organization_id and quote_version_id = draft_row.id
    and line_kind = 'priced' and selection_kind = 'optional' and is_recommended;

  calculated := private.calculate_quote_version(draft_row.id, default_addon_ids);
  select coalesce(max(version_number), 0) + 1 into next_version_number
  from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'published';

  canonical := jsonb_build_object(
    'quote', jsonb_build_object('number', quote_row.quote_number, 'title', quote_row.title),
    'version', to_jsonb(draft_row) - array[
      'id','organization_id','quote_id','revision','status','version_number','created_by','created_at',
      'updated_at','published_at','document_hash','calculation','subtotal_minor','discount_minor','tax_minor',
      'total_minor','deposit_required_minor','cost_minor','profit_minor','margin_basis_points'
    ],
    'lines', (select coalesce(jsonb_agg(to_jsonb(line_row) - array[
      'id','organization_id','quote_id','quote_version_id','source_catalog_item_id','unit_cost_minor',
      'line_cost_total_minor','created_at','updated_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_lines line_row where quote_version_id = draft_row.id),
    'schedule_items', (select coalesce(jsonb_agg(to_jsonb(item_row) - array[
      'id','organization_id','quote_id','quote_version_id','created_at','updated_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_schedule_items item_row where quote_version_id = draft_row.id),
    'attachments', (select coalesce(jsonb_agg(to_jsonb(attachment_row) - array[
      'id','organization_id','quote_id','quote_version_id','created_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_attachments attachment_row
      where quote_version_id = draft_row.id and customer_visible),
    'calculation', calculated
  );
  frozen_hash := encode(extensions.digest(canonical::text, 'sha256'), 'hex');

  update public.quote_versions set
    status = 'published', version_number = next_version_number,
    subtotal_minor = (calculated ->> 'subtotal_minor')::bigint,
    discount_minor = (calculated ->> 'discount_minor')::bigint,
    tax_minor = (calculated ->> 'tax_minor')::bigint,
    total_minor = (calculated ->> 'total_minor')::bigint,
    deposit_required_minor = (calculated ->> 'deposit_required_minor')::bigint,
    cost_minor = (calculated ->> 'cost_minor')::bigint,
    profit_minor = (calculated ->> 'profit_minor')::bigint,
    margin_basis_points = (calculated ->> 'margin_basis_points')::bigint,
    calculation = calculated, document_hash = frozen_hash, published_at = now()
  where id = draft_row.id;

  update public.quotes set draft_version_id = null, current_published_version_id = draft_row.id
  where id = quote_row.id;

  return jsonb_build_object(
    'quote_id', quote_row.id, 'quote_version_id', draft_row.id,
    'version_number', next_version_number, 'document_hash', frozen_hash,
    'calculation', calculated
  );
end;
$$;

-- 5. A revised draft and a similar quote keep their deposit shape, same as they keep discount and tax ----------
--
-- Both copies also pick up a fix from the deferred index while every line of them is being touched anyway:
-- the line and attachment copy now names organization_id and quote_id, not just quote_version_id, so it
-- matches the leading columns of quote_version_lines_version_idx / quote_version_attachments_version_idx
-- instead of falling back to a sequential scan. create_similar_quote already had this; clone_quote_version_to
-- _draft did not.

create or replace function public.clone_quote_version_to_draft(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  source_row public.quote_versions;
  new_draft public.quote_versions;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to revise this quote.' using errcode = 'insufficient_privilege';
  end if;
  if quote_row.draft_version_id is not null then
    raise exception 'This quote already has a draft.' using errcode = 'P0409';
  end if;
  select * into source_row from public.quote_versions
  where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
  for share;
  if source_row.id is null or source_row.status <> 'published' then
    raise exception 'This quote has no published version to revise.' using errcode = 'check_violation';
  end if;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code, client_display_name,
    organization_name, service_address_line1, service_address_line2, service_city, service_state_region,
    service_postal_code, service_country, subtotal_minor, created_by, revision, contract_disclaimer,
    introduction, client_message, show_quantities, show_unit_prices, show_line_totals, show_totals,
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points, deposit_type
  ) values (
    source_row.organization_id, source_row.quote_id, 0, 'draft', source_row.currency_code,
    source_row.client_display_name, source_row.organization_name, source_row.service_address_line1,
    source_row.service_address_line2, source_row.service_city, source_row.service_state_region,
    source_row.service_postal_code, source_row.service_country, source_row.subtotal_minor,
    (select auth.uid()), 1, source_row.contract_disclaimer, source_row.introduction,
    source_row.client_message, source_row.show_quantities, source_row.show_unit_prices,
    source_row.show_line_totals, source_row.show_totals, source_row.discount_name,
    source_row.discount_type, source_row.discount_value, source_row.tax_name, source_row.tax_rate_basis_points,
    source_row.deposit_type
  ) returning * into new_draft;

  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_attachment_id, line_kind, selection_kind, is_recommended
  ) select line.organization_id, line.quote_id, new_draft.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id, line.line_kind, line.selection_kind, line.is_recommended
  from public.quote_version_lines line
  where line.organization_id = source_row.organization_id
    and line.quote_id = source_row.quote_id
    and line.quote_version_id = source_row.id
  order by line.position, line.id;

  insert into public.quote_version_schedule_items (
    organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
  ) select item.organization_id, item.quote_id, new_draft.id, item.position, item.description,
    item.value_type, item.value, item.is_deposit
  from public.quote_version_schedule_items item
  where item.organization_id = source_row.organization_id
    and item.quote_id = source_row.quote_id
    and item.quote_version_id = source_row.id
  order by item.position, item.id;

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
  ) select attachment.organization_id, attachment.quote_id, new_draft.id, attachment.attachment_id,
    attachment.position, attachment.customer_visible, attachment.display_name
  from public.quote_version_attachments attachment
  where attachment.organization_id = source_row.organization_id
    and attachment.quote_id = source_row.quote_id
    and attachment.quote_version_id = source_row.id
  order by attachment.position, attachment.id;

  perform private.refresh_quote_draft_totals(new_draft.id);

  update public.quotes set draft_version_id = new_draft.id where id = quote_row.id;
  return jsonb_build_object('quote_id', quote_row.id, 'quote_version_id', new_draft.id, 'revision', 1);
end;
$$;

create or replace function public.create_similar_quote(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  source_quote public.quotes;
  source_version public.quote_versions;
  organization_display_name text;
  allocated_number integer;
  new_quote public.quotes;
  new_version public.quote_versions;
begin
  select * into source_quote from public.quotes where id = target_quote_id;
  if source_quote.id is null or not private.member_has_permission(
    source_quote.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to copy this quote.' using errcode = 'insufficient_privilege';
  end if;

  select * into source_version from public.quote_versions
  where organization_id = source_quote.organization_id
    and id = coalesce(source_quote.draft_version_id, source_quote.current_published_version_id);
  if source_version.id is null then
    raise exception 'This quote has no version to copy.' using errcode = 'check_violation';
  end if;

  select organization.name into organization_display_name
  from public.organizations as organization
  where organization.id = source_quote.organization_id;

  allocated_number := private.allocate_quote_number(source_quote.organization_id);

  insert into public.quotes (
    organization_id, client_id, property_id, quote_number, title, currency_code, created_by
  ) values (
    source_quote.organization_id,
    source_quote.client_id,
    source_quote.property_id,
    allocated_number,
    left(source_quote.title || ' (copy)', 160),
    source_quote.currency_code,
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code, client_display_name,
    organization_name, service_address_line1, service_address_line2, service_city, service_state_region,
    service_postal_code, service_country, subtotal_minor, created_by, revision, contract_disclaimer,
    introduction, client_message, show_quantities, show_unit_prices, show_line_totals, show_totals,
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points, deposit_type
  ) values (
    new_quote.organization_id, new_quote.id, 1, 'draft', source_version.currency_code,
    source_version.client_display_name, coalesce(organization_display_name, source_version.organization_name),
    source_version.service_address_line1, source_version.service_address_line2, source_version.service_city,
    source_version.service_state_region, source_version.service_postal_code, source_version.service_country,
    source_version.subtotal_minor, (select auth.uid()), 1, source_version.contract_disclaimer,
    source_version.introduction, source_version.client_message, source_version.show_quantities,
    source_version.show_unit_prices, source_version.show_line_totals, source_version.show_totals,
    source_version.discount_name, source_version.discount_type, source_version.discount_value,
    source_version.tax_name, source_version.tax_rate_basis_points, source_version.deposit_type
  )
  returning * into new_version;

  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_attachment_id, line_kind, selection_kind, is_recommended
  )
  select line.organization_id, new_quote.id, new_version.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id, line.line_kind, line.selection_kind, line.is_recommended
  from public.quote_version_lines line
  where line.organization_id = source_version.organization_id
    and line.quote_id = source_version.quote_id
    and line.quote_version_id = source_version.id
  order by line.position, line.id;

  insert into public.quote_version_schedule_items (
    organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
  )
  select item.organization_id, new_quote.id, new_version.id, item.position, item.description,
    item.value_type, item.value, item.is_deposit
  from public.quote_version_schedule_items item
  where item.organization_id = source_version.organization_id
    and item.quote_id = source_version.quote_id
    and item.quote_version_id = source_version.id
  order by item.position, item.id;

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
  )
  select att.organization_id, new_quote.id, new_version.id, att.attachment_id, att.position,
    att.customer_visible, att.display_name
  from public.quote_version_attachments att
  where att.organization_id = source_version.organization_id
    and att.quote_id = source_version.quote_id
    and att.quote_version_id = source_version.id
  order by att.position, att.id;

  perform private.refresh_quote_draft_totals(new_version.id);

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (
    new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title
  );

  return jsonb_build_object('quote_id', new_quote.id, 'quote_number', new_quote.quote_number);
end;
$$;

-- 6. Row level security ------------------------------------------------------------------------------------

alter table public.quote_version_schedule_items enable row level security;

create policy "permitted members can view quote schedule items"
on public.quote_version_schedule_items for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'quotes.view')
);

revoke all on public.quote_version_schedule_items from anon, authenticated;
grant select on public.quote_version_schedule_items to authenticated;
