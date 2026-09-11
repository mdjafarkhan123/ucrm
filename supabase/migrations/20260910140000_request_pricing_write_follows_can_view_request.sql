-- Paid-launch trust, Part 4: close the write hole Part 3 flagged and left open.
--
-- public.replace_request_pricing_lines authorized on plain organization membership
-- (private.is_organization_member), not private.can_view_request. Since Part 3 narrowed can_view_request to
-- an assigned-only rule for a Field member, a Field member who can no longer see a Request could still call
-- this function directly and edit its pricing -- the same write-hole lesson Jobs Part 15a-2 paid for on visit
-- completion (20260910100300_field_assigned_scope_commands.sql). The precondition goes immediately after the
-- request is locked, before anything else is read or changed, mirroring that precedent.
--
-- Notes, tags, attachments and activity events on a Request are not touched here: they already read
-- private.can_view_request through private.can_view_linked_entity (wired in
-- 20260818065913_link_notes_to_requests.sql), so Part 3 narrowed them for free. This migration only proves
-- the one seam that did not inherit -- the pricing write RPC calls can_view_request directly rather than
-- through a policy.

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

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way. Now the
  -- same decision the parent Request's own RLS makes, not plain membership.
  if request_row.id is null
     or not private.can_view_request(request_row.organization_id, target_request_id) then
    raise exception 'You do not have access to price this request.' using errcode = 'insufficient_privilege';
  end if;

  if request_row.status in ('converted', 'archived') then
    raise exception 'This request is closed and its pricing cannot be changed.'
      using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from request_row.pricing_revision then
    raise exception 'Someone else changed this pricing while you were editing. Reload and try again.'
      using errcode = 'P0409';
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
