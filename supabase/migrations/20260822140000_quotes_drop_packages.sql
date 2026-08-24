-- Quotes no longer offer Good/Better/Best packages.
--
-- A quote line is now either work the customer has to take or an add-on they may take, and nothing else.
-- Every function that had to ask which package was chosen loses that question, so the calculator, the
-- freeze, the clone, the preview and the customer document all come back one argument and one branch
-- simpler. The only package rows in the database are test rows and no line belongs to one.

-- 1. No line belongs to a package any more --------------------------------------------------------------

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

-- 2. The calculator only weighs required work and chosen add-ons ----------------------------------------

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

-- 3. Draft totals default to the recommended add-ons and nothing else ------------------------------------

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

-- 4. Staff preview prices an add-on scenario only --------------------------------------------------------

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

-- 5. Publishing no longer waits on a recommended package -------------------------------------------------
--
-- The frozen document keeps the same shape minus its packages list, so hashes taken from here on differ
-- from hashes taken before. Every already published version keeps the hash it was stamped with.

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
      'total_minor','cost_minor','profit_minor','margin_basis_points'
    ],
    'lines', (select coalesce(jsonb_agg(to_jsonb(line_row) - array[
      'id','organization_id','quote_id','quote_version_id','source_catalog_item_id','unit_cost_minor',
      'line_cost_total_minor','created_at','updated_at'
    ] order by position, id), '[]'::jsonb)
      from public.quote_version_lines line_row where quote_version_id = draft_row.id),
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

-- 6. A new version copies lines and attachments, and that is all -----------------------------------------

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
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points
  ) values (
    source_row.organization_id, source_row.quote_id, 0, 'draft', source_row.currency_code,
    source_row.client_display_name, source_row.organization_name, source_row.service_address_line1,
    source_row.service_address_line2, source_row.service_city, source_row.service_state_region,
    source_row.service_postal_code, source_row.service_country, source_row.subtotal_minor,
    (select auth.uid()), 1, source_row.contract_disclaimer, source_row.introduction,
    source_row.client_message, source_row.show_quantities, source_row.show_unit_prices,
    source_row.show_line_totals, source_row.show_totals, source_row.discount_name,
    source_row.discount_type, source_row.discount_value, source_row.tax_name, source_row.tax_rate_basis_points
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
  where line.quote_version_id = source_row.id order by line.position, line.id;

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
  ) select organization_id, quote_id, new_draft.id, attachment_id, position, customer_visible, display_name
  from public.quote_version_attachments where quote_version_id = source_row.id order by position, id;

  perform private.refresh_quote_draft_totals(new_draft.id);

  update public.quotes set draft_version_id = new_draft.id where id = quote_row.id;
  return jsonb_build_object('quote_id', quote_row.id, 'quote_version_id', new_draft.id, 'revision', 1);
end;
$$;

-- 7. A saved line is required work or an add-on ----------------------------------------------------------

create or replace function public.replace_quote_version_lines(
  target_quote_id uuid,
  expected_revision integer,
  new_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  line jsonb;
  line_index integer := 0;
  clean_kind text;
  clean_selection text;
  clean_recommended boolean;
  clean_quantity numeric;
  clean_price bigint;
  clean_cost bigint;
  clean_category text;
  clean_name text;
  clean_catalog_item_id uuid;
  clean_image_attachment_id uuid;
  new_count integer;
  result jsonb;
begin
  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'Lines must be sent as a list.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_lines) > 200 then
    raise exception 'A quote can hold up to 200 lines.' using errcode = 'program_limit_exceeded';
  end if;

  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  delete from public.quote_version_lines
  where organization_id = draft_row.organization_id
    and quote_id = draft_row.quote_id
    and quote_version_id = draft_row.id;

  for line in select * from jsonb_array_elements(new_lines)
  loop
    clean_name := nullif(trim(coalesce(line ->> 'name', '')), '');
    clean_kind := coalesce(nullif(line ->> 'line_kind', ''), 'priced');
    clean_selection := coalesce(nullif(line ->> 'selection_kind', ''), 'required');
    clean_recommended := coalesce((line ->> 'is_recommended')::boolean, false);

    if clean_kind not in ('priced', 'text', 'heading') then
      raise exception 'Line % is not a kind of line this quote understands.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
      raise exception 'Line % needs a name between 2 and 160 characters.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_kind <> 'priced' then
      insert into public.quote_version_lines (
        organization_id, quote_id, quote_version_id, position, name, description, is_taxable,
        line_kind, selection_kind
      ) values (
        draft_row.organization_id, draft_row.quote_id, draft_row.id, line_index, clean_name,
        nullif(trim(coalesce(line ->> 'description', '')), ''), false, clean_kind, 'required'
      );
      line_index := line_index + 1;
      continue;
    end if;

    clean_category := coalesce(line ->> 'category', 'service');
    clean_quantity := coalesce((line ->> 'quantity')::numeric, 0);
    clean_price := coalesce((line ->> 'unit_price_minor')::bigint, 0);
    clean_cost := coalesce((line ->> 'unit_cost_minor')::bigint, 0);
    clean_catalog_item_id := nullif(line ->> 'catalog_item_id', '')::uuid;
    clean_image_attachment_id := nullif(line ->> 'image_attachment_id', '')::uuid;

    if clean_category not in ('product', 'service') then
      raise exception 'Line % must be a product or a service.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_quantity <= 0 or clean_quantity > 1000000 then
      raise exception 'Line % needs a quantity above zero.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_price < 0 or clean_price > 1000000000000 or clean_cost < 0 or clean_cost > 1000000000000 then
      raise exception 'Line % has a price or cost outside the allowed range.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_selection not in ('required', 'optional') then
      raise exception 'Line % must be required work or an add-on.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_recommended and clean_selection <> 'optional' then
      raise exception 'Line % cannot be marked as recommended.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_catalog_item_id is not null and not exists (
      select 1 from public.catalog_items
      where id = clean_catalog_item_id
        and organization_id = draft_row.organization_id
        and archived_at is null
    ) then
      raise exception 'Line % points at a price list item that is no longer available.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_image_attachment_id is not null
       and not exists (
         select 1 from public.attachments
         where id = clean_image_attachment_id
           and organization_id = draft_row.organization_id
           and entity_type = 'quote'
           and entity_id = target_quote_id
       )
       and not exists (
         select 1 from public.quote_version_lines
         where organization_id = draft_row.organization_id
           and quote_id = target_quote_id
           and image_attachment_id = clean_image_attachment_id
       ) then
      raise exception 'Line % points at an image that was not uploaded for this quote.', line_index + 1
        using errcode = 'check_violation';
    end if;

    insert into public.quote_version_lines (
      organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
      name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
      image_attachment_id, line_kind, selection_kind, is_recommended
    ) values (
      draft_row.organization_id,
      draft_row.quote_id,
      draft_row.id,
      line_index,
      clean_catalog_item_id,
      clean_category,
      coalesce((line ->> 'is_labor')::boolean, false),
      clean_name,
      nullif(trim(coalesce(line ->> 'description', '')), ''),
      nullif(trim(coalesce(line ->> 'unit_label', '')), ''),
      clean_quantity,
      clean_price,
      clean_cost,
      coalesce((line ->> 'is_taxable')::boolean, true),
      clean_image_attachment_id,
      'priced',
      clean_selection,
      clean_recommended
    );

    line_index := line_index + 1;
  end loop;

  select count(*) into new_count
  from public.quote_version_lines
  where organization_id = draft_row.organization_id
    and quote_id = draft_row.quote_id
    and quote_version_id = draft_row.id;

  result := private.bump_quote_draft(draft_row.id);

  return result || jsonb_build_object(
    'line_count', new_count,
    'subtotal_minor', (result -> 'totals' ->> 'subtotal_minor')::bigint
  );
end;
$$;

-- 8. The customer document has no packages to group by ---------------------------------------------------

create or replace function private.quote_customer_document(
  quote_row public.quotes,
  version_row public.quote_versions,
  recipient_name text,
  recipient_email text,
  include_money boolean
) returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'quote', jsonb_build_object(
      'quote_number', quote_row.quote_number,
      'status', quote_row.status,
      'sent_at', quote_row.sent_at,
      'decision', quote_row.decision,
      'decided_at', quote_row.decided_at
    ),
    'recipient', jsonb_build_object(
      'name', recipient_name,
      'email', recipient_email
    ),
    'business', jsonb_build_object('name', version_row.organization_name),
    'document', jsonb_build_object(
      'version_number', version_row.version_number,
      'published_at', version_row.published_at,
      'currency_code', version_row.currency_code,
      'client_display_name', version_row.client_display_name,
      'service_address_line1', version_row.service_address_line1,
      'service_address_line2', version_row.service_address_line2,
      'service_city', version_row.service_city,
      'service_state_region', version_row.service_state_region,
      'service_postal_code', version_row.service_postal_code,
      'service_country', version_row.service_country,
      'introduction', version_row.introduction,
      'client_message', version_row.client_message,
      'contract_disclaimer', version_row.contract_disclaimer,
      'show_quantities', version_row.show_quantities,
      'show_unit_prices', version_row.show_unit_prices and include_money,
      'show_line_totals', version_row.show_line_totals and include_money,
      'show_totals', version_row.show_totals and include_money
    ),
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', line.id, 'position', line.position, 'line_kind', line.line_kind,
            'selection_kind', line.selection_kind,
            'is_recommended', line.is_recommended, 'category', line.category,
            'name', line.name, 'description', line.description, 'unit_label', line.unit_label,
            'image_attachment_id', line.image_attachment_id
          )
          || case when version_row.show_quantities
               then jsonb_build_object('quantity', line.quantity) else '{}'::jsonb end
          || case when version_row.show_unit_prices and include_money
               then jsonb_build_object('unit_price_minor', line.unit_price_minor) else '{}'::jsonb end
          || case when version_row.show_line_totals and include_money
               then jsonb_build_object('line_total_minor', line.line_total_minor) else '{}'::jsonb end
          order by line.position, line.id
        )
        from public.quote_version_lines as line
        where line.organization_id = version_row.organization_id
          and line.quote_id = version_row.quote_id
          and line.quote_version_id = version_row.id
      ),
      '[]'::jsonb
    ),
    'attachments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', version_attachment.attachment_id,
            'name', version_attachment.display_name,
            'mime_type', file.mime_type,
            'size_bytes', file.size_bytes
          )
          order by version_attachment.position, version_attachment.id
        )
        from public.quote_version_attachments as version_attachment
        join public.attachments as file on file.id = version_attachment.attachment_id
        where version_attachment.organization_id = version_row.organization_id
          and version_attachment.quote_id = version_row.quote_id
          and version_attachment.quote_version_id = version_row.id
          and version_attachment.customer_visible
      ),
      '[]'::jsonb
    ),
    'totals', case when version_row.show_totals and include_money then jsonb_build_object(
      'subtotal_minor', version_row.subtotal_minor,
      'discount_name', version_row.discount_name,
      'discount_minor', version_row.discount_minor,
      'tax_name', version_row.tax_name,
      'tax_rate_basis_points', version_row.tax_rate_basis_points,
      'tax_minor', version_row.tax_minor,
      'total_minor', version_row.total_minor
    ) else null end
  );
$$;

-- 9. Nothing owns packages any more ----------------------------------------------------------------------

drop function if exists public.replace_quote_version_packages(uuid, integer, jsonb);

drop table public.quote_version_packages;
