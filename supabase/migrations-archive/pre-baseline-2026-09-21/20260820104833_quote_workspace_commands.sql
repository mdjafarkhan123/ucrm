-- Quotes, Part 3A: the staff workspace's data layer.
--
-- Part 2 could only make a quote by converting a request, and nothing could change one afterwards. This adds
-- the four things the workspace needs: a quote somebody starts directly, a draft they can keep editing, a way
-- to put a mistake out of sight, and the counts the list's Overview card reads. It also lets the existing
-- Notes and Attachments cards point at a quote, which is what makes the detail page a reuse job rather than
-- a rebuild.
--
-- Nothing here sends, approves, or prices beyond the subtotal. Discount, tax, deposits, published versions,
-- and delivery stay with the parts that own them.

-- 1. What a draft needs to be editable -------------------------------------------------------------------

-- The same optimistic-lock shape request pricing already uses. One number per draft covers both write
-- paths below, so two people editing the same quote from different tabs cannot silently overwrite each
-- other whichever field they touched.
alter table public.quote_versions
  add column revision integer not null default 1 check (revision >= 1),
  add column contract_disclaimer text
    check (contract_disclaimer is null or char_length(contract_disclaimer) <= 5000);

comment on column public.quote_versions.revision is
  'Bumped by every command that changes this draft. A writer sends the revision it read; a mismatch is '
  'refused with P0409 so the loser reloads instead of overwriting work they never saw.';

comment on column public.quote_versions.contract_disclaimer is
  'The terms block on the quote document (Design/Quotes new.jpg). Plain text the writer types; there is no '
  'settings-backed default to inherit from yet.';

-- 2. Putting a quote out of sight ------------------------------------------------------------------------

-- Archive is reversible, so the row has to remember what it was before. Delete is not offered at all: a
-- quote owns an allocated number, and numbers are never reused.
alter table public.quotes
  add column previous_status text,
  add column archived_at timestamptz,
  add column archive_reason text
    check (archive_reason is null or char_length(trim(archive_reason)) between 3 and 500);

alter table public.quotes
  add constraint quotes_archive_fields_agree check (
    (status = 'archived') = (archived_at is not null)
  );

comment on column public.quotes.previous_status is
  'Where restore puts the quote back. Null unless the quote is archived.';

-- 3. Indexes the list actually scans ---------------------------------------------------------------------

-- Two questions, two indexes, and no third: "this org's quotes newest first" and the same thing narrowed to
-- a status. The second also answers the Overview card's group-by without touching the table. Sorting by
-- quote number rides the existing quotes_number_unique index, and there is no sort that either one cannot
-- serve, so keyset paging never degrades into a sort of the whole tenant.
create index quotes_organization_created_idx
  on public.quotes(organization_id, created_at desc, id desc);

create index quotes_organization_status_created_idx
  on public.quotes(organization_id, status, created_at desc, id desc);

-- 4. Quotes become linkable ------------------------------------------------------------------------------

-- Exactly what 20260818065913 did for requests. The Notes and Attachments cards on the quote page are the
-- ones already shipped; they only needed the seam widened and a rule for who may reach a quote.
alter table public.note_links drop constraint note_links_entity_type_check;
alter table public.note_links add constraint note_links_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote')) not valid;
alter table public.note_links validate constraint note_links_entity_type_check;

alter table public.tag_assignments drop constraint tag_assignments_entity_type_check;
alter table public.tag_assignments add constraint tag_assignments_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote')) not valid;
alter table public.tag_assignments validate constraint tag_assignments_entity_type_check;

alter table public.attachments drop constraint attachments_entity_type_check;
alter table public.attachments add constraint attachments_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote')) not valid;
alter table public.attachments validate constraint attachments_entity_type_check;

alter table public.activity_events drop constraint activity_events_entity_type_check;
alter table public.activity_events add constraint activity_events_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote')) not valid;
alter table public.activity_events validate constraint activity_events_entity_type_check;

-- Unlike a request, a quote has its own permission key, so this is not "any member".
create or replace function private.can_view_quote(
  target_organization_id uuid,
  target_quote_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.has_permission(target_organization_id, 'quotes.view')
    and exists (
      select 1
      from public.quotes
      where id = target_quote_id
        and organization_id = target_organization_id
    );
$$;

revoke all on function private.can_view_quote(uuid, uuid) from public;
grant execute on function private.can_view_quote(uuid, uuid) to authenticated;

create or replace function private.can_view_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    case target_entity_type
      when 'client' then private.can_view_client(target_organization_id, target_entity_id)
      when 'property' then private.can_view_property(target_organization_id, target_entity_id)
      when 'request' then private.can_view_request(target_organization_id, target_entity_id)
      when 'quote' then private.can_view_quote(target_organization_id, target_entity_id)
      else false
    end,
    false
  );
$$;

create or replace function private.can_manage_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_view_linked_entity(target_organization_id, target_entity_type, target_entity_id)
    and case target_entity_type
      when 'client' then private.has_permission(target_organization_id, 'customers.edit')
      when 'property' then private.has_permission(target_organization_id, 'property.manage')
      when 'request' then true
      when 'quote' then private.has_permission(target_organization_id, 'quotes.edit')
      else false
    end;
$$;

-- 5. Starting a quote from nothing -------------------------------------------------------------------------

-- The direct twin of convert_request_to_quote: same number allocation, same frozen snapshot, same pipeline
-- card. A quote made this way has no request_id and never gets one.
create or replace function public.create_quote(
  target_client_id uuid,
  target_property_id uuid,
  quote_title text,
  disclaimer text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  client_row public.clients;
  property_row public.properties;
  new_quote public.quotes;
  new_version public.quote_versions;
  allocated_number integer;
  organization_currency text;
  organization_display_name text;
  clean_title text;
  clean_disclaimer text;
begin
  clean_title := nullif(trim(coalesce(quote_title, '')), '');
  if clean_title is null or char_length(clean_title) < 2 or char_length(clean_title) > 160 then
    raise exception 'A quote needs a title between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  clean_disclaimer := nullif(trim(coalesce(disclaimer, '')), '');
  if clean_disclaimer is not null and char_length(clean_disclaimer) > 5000 then
    raise exception 'The contract disclaimer is too long.' using errcode = 'check_violation';
  end if;

  select * into client_row from public.clients where id = target_client_id;

  -- One answer for "no such client" and "not your client": a stranger learns nothing either way.
  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'quotes.create'
     ) then
    raise exception 'You do not have access to create a quote for this client.'
      using errcode = 'insufficient_privilege';
  end if;

  if client_row.deleted_at is not null then
    raise exception 'That client is no longer available.' using errcode = 'check_violation';
  end if;
  if client_row.archived_at is not null then
    raise exception 'That client is archived. Restore them before quoting new work.'
      using errcode = 'check_violation';
  end if;

  select * into property_row
  from public.properties
  where id = target_property_id
    and organization_id = client_row.organization_id
    and client_id = client_row.id;

  if property_row.id is null
     or property_row.deleted_at is not null
     or property_row.archived_at is not null then
    raise exception 'Choose a live property belonging to this client.' using errcode = 'check_violation';
  end if;

  select settings.currency_code into organization_currency
  from public.organization_settings as settings
  where settings.organization_id = client_row.organization_id;

  select organization.name into organization_display_name
  from public.organizations as organization
  where organization.id = client_row.organization_id;

  allocated_number := private.allocate_quote_number(client_row.organization_id);

  insert into public.quotes (
    organization_id, client_id, property_id, quote_number, title, currency_code, created_by
  ) values (
    client_row.organization_id,
    client_row.id,
    property_row.id,
    allocated_number,
    clean_title,
    coalesce(organization_currency, 'USD'),
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code,
    client_display_name, organization_name, contract_disclaimer,
    service_address_line1, service_address_line2, service_city,
    service_state_region, service_postal_code, service_country,
    created_by
  ) values (
    new_quote.organization_id,
    new_quote.id,
    1,
    'draft',
    new_quote.currency_code,
    client_row.display_name,
    organization_display_name,
    clean_disclaimer,
    property_row.address_line1,
    property_row.address_line2,
    property_row.city,
    property_row.state_region,
    property_row.postal_code,
    property_row.country,
    (select auth.uid())
  )
  returning * into new_version;

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- Same card the conversion command creates, for the same reason: every quote is one piece of commercial
  -- work with one identity. The stage trigger parks it off the board until the Quote columns exist.
  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title);

  return jsonb_build_object(
    'quote_id', new_quote.id,
    'quote_number', new_quote.quote_number,
    'quote_version_id', new_version.id,
    'status', new_quote.status,
    'revision', new_version.revision
  );
end;
$$;

revoke all on function public.create_quote(uuid, uuid, text, text) from public;
revoke execute on function public.create_quote(uuid, uuid, text, text) from anon;
grant execute on function public.create_quote(uuid, uuid, text, text) to authenticated;

-- 6. Editing the draft's own words ---------------------------------------------------------------------------

create or replace function public.update_quote_draft(
  target_quote_id uuid,
  expected_revision integer,
  new_title text,
  new_disclaimer text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  draft_row public.quote_versions;
  clean_title text;
  clean_disclaimer text;
  new_revision integer;
begin
  clean_title := nullif(trim(coalesce(new_title, '')), '');
  if clean_title is null or char_length(clean_title) < 2 or char_length(clean_title) > 160 then
    raise exception 'A quote needs a title between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  clean_disclaimer := nullif(trim(coalesce(new_disclaimer, '')), '');
  if clean_disclaimer is not null and char_length(clean_disclaimer) > 5000 then
    raise exception 'The contract disclaimer is too long.' using errcode = 'check_violation';
  end if;

  -- Quote first, then its draft. Every command in this file takes the two in that order, so two of them
  -- racing on one quote queue up instead of deadlocking.
  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.edit'
     ) then
    raise exception 'You do not have access to change this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be changed.' using errcode = 'check_violation';
  end if;

  select * into draft_row
  from public.quote_versions
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and status = 'draft'
  for update;

  if draft_row.id is null then
    raise exception 'This quote has no draft to change.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  update public.quote_versions
  set contract_disclaimer = clean_disclaimer, revision = revision + 1
  where id = draft_row.id
  returning revision into new_revision;

  update public.quotes set title = clean_title where id = quote_row.id;

  -- The pipeline card carries the quote's name, so it follows a rename rather than keeping the old one.
  update public.opportunities
  set title = clean_title
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id;

  return jsonb_build_object('revision', new_revision, 'title', clean_title);
end;
$$;

revoke all on function public.update_quote_draft(uuid, integer, text, text) from public;
revoke execute on function public.update_quote_draft(uuid, integer, text, text) from anon;
grant execute on function public.update_quote_draft(uuid, integer, text, text) to authenticated;

-- 7. Editing the draft's lines --------------------------------------------------------------------------------

-- The quote-side twin of replace_request_pricing_lines: same whole-set replacement, same validation, same
-- money rules. The subtotal is recounted from the rows that were actually written, never from the caller.
create or replace function public.replace_quote_version_lines(
  target_quote_id uuid,
  expected_revision integer,
  new_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  draft_row public.quote_versions;
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
    raise exception 'Lines must be sent as a list.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_lines) > 200 then
    raise exception 'A quote can hold up to 200 lines.' using errcode = 'program_limit_exceeded';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.edit'
     ) then
    raise exception 'You do not have access to change this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be changed.' using errcode = 'check_violation';
  end if;

  select * into draft_row
  from public.quote_versions
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and status = 'draft'
  for update;

  if draft_row.id is null then
    raise exception 'This quote has no draft to change.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  delete from public.quote_version_lines
  where organization_id = quote_row.organization_id
    and quote_version_id = draft_row.id;

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
        and organization_id = quote_row.organization_id
        and archived_at is null
    ) then
      raise exception 'Line % points at a price list item that is no longer available.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- A line may only claim a photo uploaded for this quote, not some other record the caller knows the id
    -- of. A line carried over from a request keeps the request's attachment id, which is why an existing
    -- reference is left alone when the caller sends it back unchanged.
    if clean_image_attachment_id is not null
       and not exists (
         select 1 from public.attachments
         where id = clean_image_attachment_id
           and organization_id = quote_row.organization_id
           and entity_type = 'quote'
           and entity_id = target_quote_id
       )
       and not exists (
         select 1 from public.quote_version_lines
         where organization_id = quote_row.organization_id
           and quote_id = target_quote_id
           and image_attachment_id = clean_image_attachment_id
       ) then
      raise exception 'Line % points at an image that was not uploaded for this quote.', line_index + 1
        using errcode = 'check_violation';
    end if;

    insert into public.quote_version_lines (
      organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
      name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
      image_attachment_id
    ) values (
      quote_row.organization_id,
      quote_row.id,
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
      clean_image_attachment_id
    );

    line_index := line_index + 1;
  end loop;

  select coalesce(sum(line_total_minor), 0), count(*)
  into new_subtotal, new_count
  from public.quote_version_lines
  where organization_id = quote_row.organization_id
    and quote_version_id = draft_row.id;

  update public.quote_versions
  set subtotal_minor = new_subtotal, revision = revision + 1
  where id = draft_row.id
  returning revision into new_revision;

  return jsonb_build_object(
    'revision', new_revision,
    'line_count', new_count,
    'subtotal_minor', new_subtotal
  );
end;
$$;

revoke all on function public.replace_quote_version_lines(uuid, integer, jsonb) from public;
revoke execute on function public.replace_quote_version_lines(uuid, integer, jsonb) from anon;
grant execute on function public.replace_quote_version_lines(uuid, integer, jsonb) to authenticated;

-- 8. Out of sight, and back again -----------------------------------------------------------------------------

create or replace function public.archive_quote(
  target_quote_id uuid,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  clean_reason text;
begin
  clean_reason := nullif(trim(coalesce(reason, '')), '');

  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.edit'
     ) then
    raise exception 'You do not have access to archive this quote.' using errcode = 'insufficient_privilege';
  end if;

  -- A retry of the same command gets the same answer rather than an error.
  if quote_row.status = 'archived' then
    return jsonb_build_object('applied', false, 'status', quote_row.status);
  end if;

  if quote_row.status = 'converted' then
    raise exception 'A converted quote cannot be archived.' using errcode = 'check_violation';
  end if;

  -- Filing away work a customer already agreed to is a decision somebody has to explain.
  if quote_row.status = 'approved' and clean_reason is null then
    raise exception 'Give a reason for archiving an approved quote.' using errcode = 'check_violation';
  end if;

  update public.quotes
  set previous_status = quote_row.status,
      status = 'archived',
      archived_at = now(),
      archive_reason = clean_reason
  where id = quote_row.id;

  return jsonb_build_object('applied', true, 'status', 'archived');
end;
$$;

revoke all on function public.archive_quote(uuid, text) from public;
revoke execute on function public.archive_quote(uuid, text) from anon;
grant execute on function public.archive_quote(uuid, text) to authenticated;

create or replace function public.restore_quote(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  restored_status text;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.edit'
     ) then
    raise exception 'You do not have access to restore this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status <> 'archived' then
    return jsonb_build_object('applied', false, 'status', quote_row.status);
  end if;

  -- Draft is the honest fallback. A quote whose old state cannot be trusted comes back as something
  -- nobody has been told about yet, never as approved or awaiting an answer.
  restored_status := coalesce(quote_row.previous_status, 'draft');
  if restored_status not in ('draft', 'awaiting_response', 'changes_requested', 'approved', 'declined') then
    restored_status := 'draft';
  end if;

  update public.quotes
  set status = restored_status,
      previous_status = null,
      archived_at = null,
      archive_reason = null
  where id = quote_row.id;

  return jsonb_build_object('applied', true, 'status', restored_status);
end;
$$;

revoke all on function public.restore_quote(uuid) from public;
revoke execute on function public.restore_quote(uuid) from anon;
grant execute on function public.restore_quote(uuid) to authenticated;

-- 9. The Overview card's numbers --------------------------------------------------------------------------

-- Security invoker on purpose: the quotes RLS policy already decides which organizations a reader may
-- count, so this cannot become a way to count somebody else's work. Counted live, like the Requests card,
-- and served by quotes_organization_status_created_idx without reading the table.
create or replace function public.quote_status_counts(target_organization_id uuid)
returns table(status text, total bigint)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select quote.status, count(*) as total
  from public.quotes as quote
  where quote.organization_id = target_organization_id
  group by quote.status;
$$;

revoke all on function public.quote_status_counts(uuid) from public, anon;
grant execute on function public.quote_status_counts(uuid) to authenticated;
