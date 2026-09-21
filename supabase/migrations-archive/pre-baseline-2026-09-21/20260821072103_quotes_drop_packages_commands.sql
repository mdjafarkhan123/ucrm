-- Quotes no longer offer Good/Better/Best packages (part 2 of 2: commands, document, table).

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

drop function if exists public.replace_quote_version_packages(uuid, integer, jsonb);

drop table public.quote_version_packages;
