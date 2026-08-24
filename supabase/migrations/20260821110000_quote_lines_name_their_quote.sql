-- Quotes Part 4B, performance gate follow-up: one index, and every reader names the quote.
--
-- The previous migration turned the line index around so version-only queries would be exact. That left
-- the line-to-version foreign key without a covering index, which the database linter caught: deleting a
-- quote would have had to scan the whole tenant's lines to find its children. Turning an index around to
-- suit two stragglers was the wrong half of the trade. The index goes back to leading with the quote, and
-- the two commands that knew the version but not the quote now pass both — which they always had to hand.

drop index public.quote_version_lines_version_idx;

create index quote_version_lines_version_idx
  on public.quote_version_lines(organization_id, quote_id, quote_version_id, position, id);

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
  draft_row public.quote_versions;
  line jsonb;
  line_index integer := 0;
  clean_kind text;
  clean_selection text;
  clean_package_id uuid;
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
    clean_package_id := nullif(line ->> 'package_id', '')::uuid;
    clean_recommended := coalesce((line ->> 'is_recommended')::boolean, false);

    if clean_kind not in ('priced', 'text', 'heading') then
      raise exception 'Line % is not a kind of line this quote understands.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
      raise exception 'Line % needs a name between 2 and 160 characters.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- A heading or a note is words on the page. It carries no money, no quantity, and no choice, so it can
    -- never quietly change a total.
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

    if clean_selection not in ('required', 'optional', 'package') then
      raise exception 'Line % must be required work, an add-on, or part of a package.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if (clean_selection = 'package') <> (clean_package_id is not null) then
      raise exception 'Line % must name the package it belongs to.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_package_id is not null and not exists (
      select 1 from public.quote_version_packages
      where id = clean_package_id
        and organization_id = draft_row.organization_id
        and quote_version_id = draft_row.id
    ) then
      raise exception 'Line % points at a package that is not on this quote. Save the packages first.',
        line_index + 1 using errcode = 'check_violation';
    end if;
    -- Only an add-on can be recommended: required work is already in, and a package carries its own flag.
    if clean_recommended and clean_selection <> 'optional' then
      raise exception 'Line % cannot be marked as recommended.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- An archived item is still readable, because old lines reference it, but it cannot start a new one.
    if clean_catalog_item_id is not null and not exists (
      select 1 from public.catalog_items
      where id = clean_catalog_item_id
        and organization_id = draft_row.organization_id
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
      image_attachment_id, line_kind, selection_kind, package_id, is_recommended
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
      clean_package_id,
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

  -- `subtotal_minor` stays in the answer because the price block has always read it from here. It is the
  -- calculator's selected subtotal now, which is the same number it was before choices existed.
  return result || jsonb_build_object(
    'line_count', new_count,
    'subtotal_minor', (result -> 'totals' ->> 'subtotal_minor')::bigint
  );
end;
$$;

revoke all on function public.replace_quote_version_lines(uuid, integer, jsonb) from public;
revoke execute on function public.replace_quote_version_lines(uuid, integer, jsonb) from anon;
grant execute on function public.replace_quote_version_lines(uuid, integer, jsonb) to authenticated;
