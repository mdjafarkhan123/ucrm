-- Quotes Part 4B: the checked draft commands behind the proposal editor.
-- Part 4A built the proposal shape, the calculator, and the guards, then left every new table read-only on
-- purpose. This file is the only way staff content reaches them: one preamble that locks the quote and its
-- draft in the same order as every earlier command, one refresh that lets the database own the money, and
-- one command per thing a person edits. Nothing here publishes a version; that stays with Part 5.

-- 1. The shared preamble -------------------------------------------------------------------------------------

-- Every command below opens the same way, so it is written once: find the quote, check the person may edit
-- it, take the quote lock first and the draft lock second, and refuse a save that was typed against an
-- older copy. A missing quote and somebody else's quote answer identically on purpose.
create or replace function private.lock_quote_draft(
  target_quote_id uuid,
  expected_revision integer
)
returns public.quote_versions
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  draft_row public.quote_versions;
begin
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

  return draft_row;
end;
$$;

revoke all on function private.lock_quote_draft(uuid, integer) from public;
revoke execute on function private.lock_quote_draft(uuid, integer) from anon, authenticated;

-- 2. The database keeps the money ------------------------------------------------------------------------

-- After anything on a draft changes, its stored totals are recomputed by the same calculator freezing uses,
-- against the same default selection freezing would pick: the recommended package and the recommended
-- add-ons. A draft the customer has not answered yet therefore already shows the numbers its first
-- published version will show. Nothing outside the database ever writes these columns.
create or replace function private.refresh_quote_draft_totals(target_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.quote_versions;
  default_package_id uuid;
  default_addon_ids uuid[];
  calculated jsonb;
begin
  select * into version_row from public.quote_versions where id = target_version_id;

  -- Freeze insists on a recommended package. A draft in the middle of being built may not have chosen one
  -- yet, so the first package stands in until it does, and the totals stay honest either way.
  select id into default_package_id
  from public.quote_version_packages
  where organization_id = version_row.organization_id and quote_version_id = version_row.id
  order by is_recommended desc, position, id
  limit 1;

  select coalesce(array_agg(id order by position, id), '{}'::uuid[])
  into default_addon_ids
  from public.quote_version_lines
  where organization_id = version_row.organization_id
    and quote_version_id = version_row.id
    and line_kind = 'priced' and selection_kind = 'optional' and is_recommended;

  calculated := private.calculate_quote_version(version_row.id, default_package_id, default_addon_ids);

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

revoke all on function private.refresh_quote_draft_totals(uuid) from public;
revoke execute on function private.refresh_quote_draft_totals(uuid) from anon, authenticated;

-- Editing a quote needs `quotes.edit`; seeing what it costs the business needs `quotes.view_cost`. They are
-- different permissions, so a command's answer carries the customer's side of the calculation only. Cost,
-- profit, and margin come back through the quote read, which knows which of the two the reader holds.
create or replace function private.quote_customer_totals(calculated jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select calculated - 'cost_minor' - 'profit_minor' - 'margin_basis_points';
$$;

revoke all on function private.quote_customer_totals(jsonb) from public;
revoke execute on function private.quote_customer_totals(jsonb) from anon, authenticated;

-- Bumping the revision is the last thing every command does, and the shared answer is the same shape:
-- the number the next save must send back, and what the money now says.
create or replace function private.bump_quote_draft(target_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_revision integer;
  calculated jsonb;
begin
  calculated := private.refresh_quote_draft_totals(target_version_id);
  update public.quote_versions set revision = revision + 1
  where id = target_version_id
  returning revision into new_revision;
  return jsonb_build_object('revision', new_revision, 'totals', private.quote_customer_totals(calculated));
end;
$$;

revoke all on function private.bump_quote_draft(uuid) from public;
revoke execute on function private.bump_quote_draft(uuid) from anon, authenticated;

-- 3. The rail's own dialogs ----------------------------------------------------------------------------------

-- One discount per quote, with the name the customer reads on it. A null type is the Remove button: the
-- name and the value go with it, because a discount without a value is not a discount.
create or replace function public.set_quote_draft_discount(
  target_quote_id uuid,
  expected_revision integer,
  new_name text,
  new_type text,
  new_value bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  clean_name text;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  if new_type is null then
    update public.quote_versions
    set discount_name = null, discount_type = null, discount_value = null
    where id = draft_row.id;
    return private.bump_quote_draft(draft_row.id);
  end if;

  if new_type not in ('fixed', 'percentage') then
    raise exception 'A discount is either a fixed amount or a percentage.' using errcode = 'check_violation';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 80 then
    raise exception 'Give this discount a name the customer will understand, under 80 characters.'
      using errcode = 'check_violation';
  end if;

  if new_value is null or new_value < 0 then
    raise exception 'Enter a discount amount.' using errcode = 'check_violation';
  end if;
  if new_type = 'percentage' and new_value > 10000 then
    raise exception 'A discount cannot be more than 100 percent.' using errcode = 'check_violation';
  end if;
  if new_type = 'fixed' and new_value > 1000000000000 then
    raise exception 'That discount is too large.' using errcode = 'check_violation';
  end if;

  update public.quote_versions
  set discount_name = clean_name, discount_type = new_type, discount_value = new_value
  where id = draft_row.id;

  -- A fixed discount larger than the work itself is capped by the calculator rather than refused here, so
  -- removing a line never leaves the quote in a state the database will not store.
  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.set_quote_draft_discount(uuid, integer, text, text, bigint) from public;
revoke execute on function public.set_quote_draft_discount(uuid, integer, text, text, bigint) from anon;
grant execute on function public.set_quote_draft_discount(uuid, integer, text, text, bigint) to authenticated;

-- One named rate, or No tax. Zero and a name cannot travel together: No tax has nothing to call itself.
create or replace function public.set_quote_draft_tax(
  target_quote_id uuid,
  expected_revision integer,
  new_name text,
  new_rate_basis_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  clean_name text;
  clean_rate integer;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  clean_rate := coalesce(new_rate_basis_points, 0);
  if clean_rate < 0 or clean_rate > 10000 then
    raise exception 'A tax rate is between 0 and 100 percent.' using errcode = 'check_violation';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_rate = 0 then
    clean_name := null;
  elsif clean_name is null or char_length(clean_name) > 80 then
    raise exception 'Give this tax a name the customer will recognize, under 80 characters.'
      using errcode = 'check_violation';
  end if;

  update public.quote_versions
  set tax_name = clean_name, tax_rate_basis_points = clean_rate
  where id = draft_row.id;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.set_quote_draft_tax(uuid, integer, text, integer) from public;
revoke execute on function public.set_quote_draft_tax(uuid, integer, text, integer) from anon;
grant execute on function public.set_quote_draft_tax(uuid, integer, text, integer) to authenticated;

-- What the customer's copy of this quote shows. The numbers stay the same either way; these four switches
-- only decide how much of the arithmetic the customer is shown.
create or replace function public.set_quote_draft_visibility(
  target_quote_id uuid,
  expected_revision integer,
  new_show_quantities boolean,
  new_show_unit_prices boolean,
  new_show_line_totals boolean,
  new_show_totals boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  update public.quote_versions set
    show_quantities = coalesce(new_show_quantities, true),
    show_unit_prices = coalesce(new_show_unit_prices, true),
    show_line_totals = coalesce(new_show_line_totals, true),
    show_totals = coalesce(new_show_totals, true)
  where id = draft_row.id;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.set_quote_draft_visibility(uuid, integer, boolean, boolean, boolean, boolean)
  from public;
revoke execute on function public.set_quote_draft_visibility(uuid, integer, boolean, boolean, boolean, boolean)
  from anon;
grant execute on function public.set_quote_draft_visibility(uuid, integer, boolean, boolean, boolean, boolean)
  to authenticated;

-- The words above and below the price table. The contract disclaimer keeps its existing home in
-- `update_quote_draft` alongside the title, so no field has two owners.
create or replace function public.set_quote_draft_copy(
  target_quote_id uuid,
  expected_revision integer,
  new_introduction text,
  new_client_message text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  clean_introduction text;
  clean_client_message text;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  clean_introduction := nullif(trim(coalesce(new_introduction, '')), '');
  clean_client_message := nullif(trim(coalesce(new_client_message, '')), '');
  if clean_introduction is not null and char_length(clean_introduction) > 10000 then
    raise exception 'That introduction is too long.' using errcode = 'check_violation';
  end if;
  if clean_client_message is not null and char_length(clean_client_message) > 5000 then
    raise exception 'That client message is too long.' using errcode = 'check_violation';
  end if;

  update public.quote_versions
  set introduction = clean_introduction, client_message = clean_client_message
  where id = draft_row.id;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.set_quote_draft_copy(uuid, integer, text, text) from public;
revoke execute on function public.set_quote_draft_copy(uuid, integer, text, text) from anon;
grant execute on function public.set_quote_draft_copy(uuid, integer, text, text) to authenticated;

-- 4. Packages -------------------------------------------------------------------------------------------

-- Reordering three packages means two of them briefly hold each other's position. Checking that at the end
-- of the statement instead of in the middle of it is the whole reason this constraint is deferred; the rule
-- itself has not changed.
alter table public.quote_version_packages
  drop constraint quote_version_packages_position_unique,
  add constraint quote_version_packages_position_unique
    unique (organization_id, quote_version_id, position) deferrable initially deferred;

-- Good, Better, Best: at most three, in the order the customer reads them, at most one marked as the one
-- you would pick. The whole set is sent every time, like the lines are, and the ids come back so the line
-- editor can point its package lines at them in the save that follows.
create or replace function public.replace_quote_version_packages(
  target_quote_id uuid,
  expected_revision integer,
  new_packages jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  package jsonb;
  package_index integer := 0;
  kept_ids uuid[] := '{}'::uuid[];
  clean_id uuid;
  clean_name text;
  clean_description text;
  recommended_count integer := 0;
  orphaned_name text;
  result jsonb;
begin
  if new_packages is null or jsonb_typeof(new_packages) <> 'array' then
    raise exception 'Packages must be sent as a list.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_packages) > 3 then
    raise exception 'A quote can offer up to three packages.' using errcode = 'check_violation';
  end if;

  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  for package in select * from jsonb_array_elements(new_packages)
  loop
    clean_id := nullif(package ->> 'id', '')::uuid;
    if clean_id is not null then
      if not exists (
        select 1 from public.quote_version_packages
        where id = clean_id
          and organization_id = draft_row.organization_id
          and quote_version_id = draft_row.id
      ) then
        raise exception 'One of those packages is no longer part of this quote. Reload and try again.'
          using errcode = 'P0409';
      end if;
      kept_ids := kept_ids || clean_id;
    end if;
    if coalesce((package ->> 'is_recommended')::boolean, false) then
      recommended_count := recommended_count + 1;
    end if;
  end loop;

  if recommended_count > 1 then
    raise exception 'Only one package can be the recommended one.' using errcode = 'check_violation';
  end if;

  -- A package that still holds lines cannot just disappear, or those lines would point at nothing. The
  -- editor moves or deletes them first, and this says so in a sentence rather than as a foreign key error.
  select existing.name into orphaned_name
  from public.quote_version_packages existing
  where existing.organization_id = draft_row.organization_id
    and existing.quote_version_id = draft_row.id
    and not (existing.id = any(kept_ids))
    and exists (
      select 1 from public.quote_version_lines line
      where line.organization_id = draft_row.organization_id
        and line.quote_version_id = draft_row.id
        and line.package_id = existing.id
    )
  limit 1;
  if orphaned_name is not null then
    raise exception 'Move or remove the lines in "%" before deleting it.', orphaned_name
      using errcode = 'check_violation';
  end if;

  delete from public.quote_version_packages
  where organization_id = draft_row.organization_id
    and quote_version_id = draft_row.id
    and not (id = any(kept_ids));

  -- Only one package may carry the flag, and that index is not deferred, so every flag comes off before any
  -- goes back on.
  update public.quote_version_packages
  set is_recommended = false
  where organization_id = draft_row.organization_id
    and quote_version_id = draft_row.id
    and is_recommended;

  for package in select * from jsonb_array_elements(new_packages)
  loop
    clean_id := nullif(package ->> 'id', '')::uuid;
    clean_name := nullif(trim(coalesce(package ->> 'name', '')), '');
    clean_description := nullif(trim(coalesce(package ->> 'description', '')), '');

    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 80 then
      raise exception 'Package % needs a name between 2 and 80 characters.', package_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_description is not null and char_length(clean_description) > 2000 then
      raise exception 'The description on "%" is too long.', clean_name using errcode = 'check_violation';
    end if;

    if clean_id is null then
      insert into public.quote_version_packages (
        organization_id, quote_id, quote_version_id, position, name, description
      ) values (
        draft_row.organization_id, draft_row.quote_id, draft_row.id, package_index,
        clean_name, clean_description
      );
    else
      update public.quote_version_packages
      set position = package_index, name = clean_name, description = clean_description
      where id = clean_id;
    end if;

    package_index := package_index + 1;
  end loop;

  update public.quote_version_packages target
  set is_recommended = true
  from (
    select row_number() over () - 1 as position, element
    from jsonb_array_elements(new_packages) element
  ) sent
  where target.organization_id = draft_row.organization_id
    and target.quote_version_id = draft_row.id
    and target.position = sent.position
    and coalesce((sent.element ->> 'is_recommended')::boolean, false);

  result := private.bump_quote_draft(draft_row.id);

  return result || jsonb_build_object('packages', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'position', position, 'name', name,
      'description', description, 'is_recommended', is_recommended
    ) order by position, id), '[]'::jsonb)
    from public.quote_version_packages
    where organization_id = draft_row.organization_id and quote_version_id = draft_row.id
  ));
end;
$$;

revoke all on function public.replace_quote_version_packages(uuid, integer, jsonb) from public;
revoke execute on function public.replace_quote_version_packages(uuid, integer, jsonb) from anon;
grant execute on function public.replace_quote_version_packages(uuid, integer, jsonb) to authenticated;

-- 5. Which uploaded files the customer sees ---------------------------------------------------------------

-- The files themselves stay where they are, private, on the quote. This only records which of them belong
-- in the customer's copy, under what name, in what order. Nothing is copied and nothing is made public.
create or replace function public.replace_quote_version_attachments(
  target_quote_id uuid,
  expected_revision integer,
  new_attachments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  attachment jsonb;
  attachment_index integer := 0;
  clean_attachment_id uuid;
  clean_display_name text;
  seen_ids uuid[] := '{}'::uuid[];
begin
  if new_attachments is null or jsonb_typeof(new_attachments) <> 'array' then
    raise exception 'Files must be sent as a list.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_attachments) > 50 then
    raise exception 'A quote can show up to 50 files.' using errcode = 'check_violation';
  end if;

  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  delete from public.quote_version_attachments
  where organization_id = draft_row.organization_id
    and quote_version_id = draft_row.id;

  for attachment in select * from jsonb_array_elements(new_attachments)
  loop
    clean_attachment_id := nullif(attachment ->> 'attachment_id', '')::uuid;
    clean_display_name := nullif(trim(coalesce(attachment ->> 'display_name', '')), '');

    if clean_attachment_id is null then
      raise exception 'File % is missing.', attachment_index + 1 using errcode = 'check_violation';
    end if;
    if clean_attachment_id = any(seen_ids) then
      raise exception 'The same file was listed twice.' using errcode = 'check_violation';
    end if;
    seen_ids := seen_ids || clean_attachment_id;

    -- A file may only be shown if it was uploaded to this quote. An id from somewhere else in the tenant is
    -- refused, which is what keeps one quote's private paperwork out of another's customer copy.
    if not exists (
      select 1 from public.attachments
      where id = clean_attachment_id
        and organization_id = draft_row.organization_id
        and entity_type = 'quote'
        and entity_id = target_quote_id
    ) then
      raise exception 'File % was not uploaded to this quote.', attachment_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_display_name is null or char_length(clean_display_name) > 255 then
      raise exception 'File % needs a name under 255 characters.', attachment_index + 1
        using errcode = 'check_violation';
    end if;

    insert into public.quote_version_attachments (
      organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
    ) values (
      draft_row.organization_id, draft_row.quote_id, draft_row.id, clean_attachment_id, attachment_index,
      coalesce((attachment ->> 'customer_visible')::boolean, false), clean_display_name
    );

    attachment_index := attachment_index + 1;
  end loop;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.replace_quote_version_attachments(uuid, integer, jsonb) from public;
revoke execute on function public.replace_quote_version_attachments(uuid, integer, jsonb) from anon;
grant execute on function public.replace_quote_version_attachments(uuid, integer, jsonb) to authenticated;

-- 6. Lines learn about choices ------------------------------------------------------------------------------

-- The same whole-set replacement as before, with three things added to each row: whether it is priced work
-- or just words, whether the customer must take it, may take it, or gets it inside a package, and which
-- package that is. The subtotal is no longer a sum of every row — with choices on the table, only the
-- calculator knows what "the total" means, so it is asked.
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

-- 7. What the customer would pay if they picked this ------------------------------------------------------

-- Staff need to see the effect of a package or an add-on before anyone has chosen anything. This answers
-- that question and changes nothing: it records no decision, writes no row, and bumps no revision. Cost,
-- profit, and margin are in the answer only for someone allowed to see them.
create or replace function public.preview_quote_version_totals(
  target_quote_id uuid,
  selected_package_id uuid default null,
  selected_addon_ids uuid[] default '{}'::uuid[]
)
returns jsonb
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

  calculated := private.calculate_quote_version(version_id, selected_package_id, selected_addon_ids);

  if private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view_cost'
  ) then
    return calculated;
  end if;
  return private.quote_customer_totals(calculated);
end;
$$;

revoke all on function public.preview_quote_version_totals(uuid, uuid, uuid[]) from public;
revoke execute on function public.preview_quote_version_totals(uuid, uuid, uuid[]) from anon;
grant execute on function public.preview_quote_version_totals(uuid, uuid, uuid[]) to authenticated;

-- 8. Existing drafts pick up their calculation -------------------------------------------------------------

-- Drafts written before this file have zeroed proposal totals and an empty calculation, because nothing had
-- filled them in yet. One pass over the drafts that exist puts every one of them on the same footing, so no
-- screen has to know whether a quote is older than its own money columns.
do $$
declare
  draft_id uuid;
begin
  for draft_id in
    select id from public.quote_versions where status = 'draft'
  loop
    perform private.refresh_quote_draft_totals(draft_id);
  end loop;
end;
$$;
