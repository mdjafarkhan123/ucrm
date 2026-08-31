-- Quotes, Part 2: performance review of the migration and API layers.
--
-- Every pricing index in this campaign leads with organization_id, which is right: it is what keeps one
-- tenant's rows away from another's. But five lookups inside the two write functions asked for a row by
-- request, version, or quote alone. A security definer function gets no RLS predicate added for it, so
-- those statements had no organization_id to match on and could not use the leading column of any index --
-- Postgres fell back to walking the whole index for every save and every conversion.
--
-- Measured on a 300,000-row copy of request_pricing_lines (50 organizations, 6 lines per request):
-- by request alone, 214 ms and 2,807 buffers to find 6 rows; with the organization added, 0.18 ms and
-- 4 buffers. Same rows, same index. That cost is paid on every single pricing save, and it grows with the
-- whole table rather than with the tenant.
--
-- Nothing about the behavior of either function changes here. The organization is already known at each of
-- these points, from the request row the function locked at the start, so this only tells Postgres what it
-- was allowed to assume anyway.

-- 1. The pipeline card lookup ---------------------------------------------------------------------------------

-- convert_request_to_quote locks the request's pipeline card before its request, matching the outcome
-- engine's lock order, and at that moment it does not know the organization yet. The pipeline resync
-- trigger asks the same question on every request status change -- including the one this conversion makes.
-- Neither can use opportunities_request_unique, whose leading column is organization_id, so both get this
-- narrow partial index instead. Cards for quotes and standalone opportunities are not in it.
create index opportunities_request_lookup_idx
  on public.opportunities(request_id)
  where request_id is not null;

-- 2. The request pricing write path ----------------------------------------------------------------------------

create or replace function public.replace_request_pricing_lines(
  target_request_id uuid,
  expected_revision integer,
  new_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.requests;
  line jsonb;
  line_index integer := 0;
  clean_quantity numeric;
  clean_price bigint;
  clean_cost bigint;
  clean_category text;
  clean_name text;
  clean_catalog_item_id uuid;
  clean_image_attachment_id uuid;
  new_revision integer;
  new_subtotal bigint;
  new_count integer;
begin
  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'Pricing must be sent as a list of lines.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_lines) > 200 then
    raise exception 'A request can hold up to 200 pricing lines.' using errcode = 'program_limit_exceeded';
  end if;

  select * into request_row from public.requests where id = target_request_id for update;

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way.
  if request_row.id is null
     or not private.is_organization_member(request_row.organization_id) then
    raise exception 'You do not have access to price this request.' using errcode = 'insufficient_privilege';
  end if;

  if request_row.status in ('converted', 'archived') then
    raise exception 'This request is closed and its pricing cannot be changed.'
      using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from request_row.pricing_revision then
    raise exception 'Someone else changed this pricing while you were editing. Reload and try again.'
      using errcode = '40001';
  end if;

  delete from public.request_pricing_lines
  where organization_id = request_row.organization_id
    and request_id = target_request_id;

  for line in select * from jsonb_array_elements(new_lines)
  loop
    clean_name := nullif(trim(coalesce(line ->> 'name', '')), '');
    clean_category := coalesce(line ->> 'category', 'service');
    clean_quantity := coalesce((line ->> 'quantity')::numeric, 0);
    clean_price := coalesce((line ->> 'unit_price_minor')::bigint, 0);
    clean_cost := coalesce((line ->> 'unit_cost_minor')::bigint, 0);
    clean_catalog_item_id := nullif(line ->> 'catalog_item_id', '')::uuid;
    clean_image_attachment_id := nullif(line ->> 'image_attachment_id', '')::uuid;

    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
      raise exception 'Line % needs a name between 2 and 160 characters.', line_index + 1
        using errcode = 'check_violation';
    end if;
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

    -- An archived item is still readable, because old lines reference it, but it cannot start a new one.
    if clean_catalog_item_id is not null and not exists (
      select 1 from public.catalog_items
      where id = clean_catalog_item_id
        and organization_id = request_row.organization_id
        and archived_at is null
    ) then
      raise exception 'Line % points at a price list item that is no longer available.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- A line may only claim a photo that was actually uploaded for this request, not some other record the
    -- caller happens to know the id of.
    if clean_image_attachment_id is not null and not exists (
      select 1 from public.attachments
      where id = clean_image_attachment_id
        and organization_id = request_row.organization_id
        and entity_type = 'request'
        and entity_id = target_request_id
    ) then
      raise exception 'Line % points at an image that was not uploaded for this request.', line_index + 1
        using errcode = 'check_violation';
    end if;

    insert into public.request_pricing_lines (
      organization_id, request_id, position, catalog_item_id, category, is_labor,
      name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
      image_attachment_id
    ) values (
      request_row.organization_id,
      target_request_id,
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
      clean_image_attachment_id
    );

    line_index := line_index + 1;
  end loop;

  select coalesce(sum(line_total_minor), 0), count(*)
  into new_subtotal, new_count
  from public.request_pricing_lines
  where organization_id = request_row.organization_id
    and request_id = target_request_id;

  update public.requests
  set pricing_revision = pricing_revision + 1,
      pricing_subtotal_minor = new_subtotal
  where id = target_request_id
  returning pricing_revision into new_revision;

  return jsonb_build_object(
    'revision', new_revision,
    'line_count', new_count,
    'subtotal_minor', new_subtotal
  );
end;
$$;

-- 3. The conversion command -----------------------------------------------------------------------------------

create or replace function public.convert_request_to_quote(
  target_request_id uuid,
  idempotency_key text,
  request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  request_row public.requests;
  source_opportunity public.opportunities;
  existing_quote public.quotes;
  new_quote public.quotes;
  new_version public.quote_versions;
  new_opportunity_id uuid;
  allocated_number integer;
  organization_currency text;
  organization_name text;
  client_name text;
  property_row public.properties;
  copied_count integer;
  copied_subtotal bigint;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- Lock order matches the outcome engine: the pipeline card first, then its request. Two commands racing
  -- on the same work therefore queue up instead of deadlocking against each other.
  select * into source_opportunity
  from public.opportunities
  where request_id = target_request_id
  for update;

  select * into request_row
  from public.requests
  where id = target_request_id
  for update;

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way.
  if request_row.id is null
     or not private.member_has_permission(
       request_row.organization_id, (select auth.uid()), 'quotes.create'
     ) then
    raise exception 'You do not have access to create a quote from this request.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotency is checked before state. A retry that arrives after the first call already succeeded must
  -- be recognised as the same command, not rejected as "already converted".
  select * into existing_quote
  from public.quotes
  where organization_id = request_row.organization_id
    and request_id = target_request_id
  for update;

  if found then
    if existing_quote.conversion_idempotency_key is not distinct from idempotency_key
       and existing_quote.conversion_request_hash is not distinct from request_hash then
      return jsonb_build_object(
        'applied', false,
        'quote_id', existing_quote.id,
        'quote_number', existing_quote.quote_number,
        'quote_version_id', existing_quote.draft_version_id,
        'status', existing_quote.status
      );
    end if;

    raise exception 'This request already has a quote.' using errcode = '40001';
  end if;

  -- A finished assessment is still convertible: in Jobber that is exactly the moment the office is meant
  -- to price the work. Completed, converted, and archived requests are not live work any more.
  if request_row.status not in ('new', 'unscheduled', 'assessment_completed') then
    raise exception 'This request cannot be turned into a quote right now.' using errcode = 'check_violation';
  end if;

  select settings.currency_code into organization_currency
  from public.organization_settings as settings
  where settings.organization_id = request_row.organization_id;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = request_row.organization_id;

  select client.display_name into client_name
  from public.clients as client
  where client.id = request_row.client_id;

  select * into property_row
  from public.properties
  where id = request_row.property_id;

  allocated_number := private.allocate_quote_number(request_row.organization_id);

  insert into public.quotes (
    organization_id, client_id, property_id, request_id, quote_number, title, currency_code,
    conversion_idempotency_key, conversion_request_hash, created_by
  ) values (
    request_row.organization_id,
    request_row.client_id,
    request_row.property_id,
    target_request_id,
    allocated_number,
    request_row.title,
    coalesce(organization_currency, 'USD'),
    idempotency_key,
    request_hash,
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code,
    client_display_name, organization_name,
    service_address_line1, service_address_line2, service_city,
    service_state_region, service_postal_code, service_country,
    created_by
  ) values (
    new_quote.organization_id,
    new_quote.id,
    1,
    'draft',
    new_quote.currency_code,
    client_name,
    organization_name,
    property_row.address_line1,
    property_row.address_line2,
    property_row.city,
    property_row.state_region,
    property_row.postal_code,
    property_row.country,
    (select auth.uid())
  )
  returning * into new_version;

  -- The copy is what makes the quote its own document. From here the catalog and the request can change
  -- as much as anyone likes and these numbers do not move.
  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_attachment_id
  )
  select
    line.organization_id, new_quote.id, new_version.id, line.position, line.catalog_item_id,
    line.category, line.is_labor, line.name, line.description, line.unit_label,
    line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id
  from public.request_pricing_lines as line
  where line.organization_id = request_row.organization_id
    and line.request_id = target_request_id;

  select coalesce(sum(line.line_total_minor), 0), count(*)
  into copied_subtotal, copied_count
  from public.quote_version_lines as line
  where line.organization_id = new_quote.organization_id
    and line.quote_id = new_quote.id
    and line.quote_version_id = new_version.id;

  update public.quote_versions set subtotal_minor = copied_subtotal where id = new_version.id;
  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- The quote gets its own card. The stage trigger parks it off the board.
  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title)
  returning id into new_opportunity_id;

  -- Only work still to be done follows the quote. A task somebody already finished belongs to the request
  -- as history and stays where it happened. No limit check is needed: the new card starts empty and the
  -- old one already respected the five-open cap.
  if source_opportunity.id is not null then
    update public.tasks
    set opportunity_id = new_opportunity_id
    where organization_id = new_quote.organization_id
      and opportunity_id = source_opportunity.id
      and status = 'open';
  end if;

  -- This one update is also what takes the original request card off the board: the Part 1 resync trigger
  -- recomputes its stage from the new status without any extra code here.
  update public.requests set status = 'converted' where id = target_request_id;

  return jsonb_build_object(
    'applied', true,
    'quote_id', new_quote.id,
    'quote_number', new_quote.quote_number,
    'quote_version_id', new_version.id,
    'status', new_quote.status,
    'line_count', copied_count,
    'subtotal_minor', copied_subtotal
  );
end;
$$;
