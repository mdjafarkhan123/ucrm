-- Contractor Settings, Part 2B: Price Book management.
--
-- The catalog table and its picker already exist (Quotes Part 2). This slice adds the Settings-management
-- authority beside that picker without replacing it: a new Owner/Administrator-only permission, the
-- revision/editor metadata every other Settings surface already carries, case-insensitive active-name
-- uniqueness, the indexes the approved management list's three sort orders need, and revision-protected
-- create/update/delete commands that mirror `settings.taxes.manage`'s shape. The picker's plain
-- `catalog.edit` insert/update stay exactly as they are: a Quote editor still creates or updates a saved
-- item in place from the drawer, unprotected by revision, exactly as approved for that slice.
--
-- Order: permission, revision/editor columns, active-name uniqueness, list indexes, then the three commands.

-- 1. Permission ------------------------------------------------------------------------------------------

-- Money-adjacent and, per the approved blueprint, hidden from every role except owner and admin until
-- Roles & Permissions provides finer control -- the same boundary Taxes drew.
insert into public.permissions (key, description)
values ('settings.price_book.manage', 'Add, edit, and permanently delete shared Price Book items in Settings')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.price_book.manage'),
  ('admin', 'settings.price_book.manage')
on conflict (role, permission_key) do nothing;

-- 2. Revision and editor metadata -------------------------------------------------------------------------

-- Same shape as `organization_tax_rates`: one revision, one editor, so a stale Settings save is refused the
-- same way everywhere in Settings. `created_by`, `created_at`, and `updated_at` already exist.
alter table public.catalog_items
  add column revision integer not null default 1,
  add column updated_by uuid references auth.users(id) on delete set null;

comment on column public.catalog_items.revision is
  'Bumped once by every accepted update_catalog_item or delete_catalog_item call. A stale expected_revision '
  'is refused so two Settings managers editing the same item cannot silently overwrite or resurrect it.';

-- 3. Active-name uniqueness -------------------------------------------------------------------------------

-- "Active item names are unique without regard to capitalization; deleting an item makes its name available
-- again" (blueprint). Deletion here is a real DELETE, not an archive, so this only ever excludes the
-- picker's own archived rows -- it is not a second deletion mechanism.
create unique index catalog_items_active_name_unique
  on public.catalog_items(organization_id, lower(name))
  where archived_at is null;

-- 4. Settings-management list indexes ---------------------------------------------------------------------

-- The list's default order (no category filter) already has a home in the existing, non-partial
-- `catalog_items_organization_name_idx(organization_id, name, id)` -- Settings simply filters archived rows
-- out of that same scan, exactly as the picker already does. Only the other two approved sort orders are
-- new. Name and description search stay unindexed `ILIKE`, matching the existing picker: a contractor's
-- price book is a bounded, per-tenant list, not a corpus that needs trigram or full-text support.
create index catalog_items_active_price_idx
  on public.catalog_items(organization_id, unit_price_minor, id)
  where archived_at is null;

create index catalog_items_active_updated_idx
  on public.catalog_items(organization_id, updated_at, id)
  where archived_at is null;

-- 5. Managing the list -------------------------------------------------------------------------------------

create or replace function public.create_catalog_item(
  target_organization_id uuid,
  new_category text,
  new_name text,
  new_description text,
  new_unit_label text,
  new_is_labor boolean,
  new_unit_price_minor bigint,
  new_unit_cost_minor bigint,
  new_is_taxable boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_name text;
  new_row public.catalog_items;
begin
  if not private.has_permission(target_organization_id, 'settings.price_book.manage') then
    raise exception 'You do not have access to manage the Price Book.' using errcode = 'insufficient_privilege';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
    raise exception 'Give this item a name between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from public.catalog_items
    where organization_id = target_organization_id
      and archived_at is null
      and lower(name) = lower(clean_name)
  ) then
    raise exception 'An active Price Book item is already named "%".', clean_name
      using errcode = 'unique_violation';
  end if;

  insert into public.catalog_items (
    organization_id, category, name, description, unit_label, is_labor,
    unit_price_minor, unit_cost_minor, is_taxable, created_by, updated_by
  )
  values (
    target_organization_id, new_category, clean_name, new_description, new_unit_label,
    coalesce(new_is_labor, false), coalesce(new_unit_price_minor, 0), coalesce(new_unit_cost_minor, 0),
    coalesce(new_is_taxable, true), (select auth.uid()), (select auth.uid())
  )
  returning * into new_row;

  return jsonb_build_object('id', new_row.id, 'name', new_row.name, 'revision', new_row.revision);
end;
$$;

revoke all on function public.create_catalog_item(
  uuid, text, text, text, text, boolean, bigint, bigint, boolean
) from public;
revoke execute on function public.create_catalog_item(
  uuid, text, text, text, text, boolean, bigint, bigint, boolean
) from anon;
grant execute on function public.create_catalog_item(
  uuid, text, text, text, text, boolean, bigint, bigint, boolean
) to authenticated;

create or replace function public.update_catalog_item(
  target_organization_id uuid,
  target_item_id uuid,
  expected_revision integer,
  new_category text,
  new_name text,
  new_description text,
  new_unit_label text,
  new_is_labor boolean,
  new_unit_price_minor bigint,
  new_unit_cost_minor bigint,
  new_is_taxable boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  item_row public.catalog_items;
  clean_name text;
begin
  if not private.has_permission(target_organization_id, 'settings.price_book.manage') then
    raise exception 'You do not have access to manage the Price Book.' using errcode = 'insufficient_privilege';
  end if;

  select * into item_row
  from public.catalog_items
  where id = target_item_id and organization_id = target_organization_id
  for update;

  if item_row.id is null then
    raise exception 'That Price Book item was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from item_row.revision then
    raise exception 'Someone else changed this item while you were editing. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
    raise exception 'Give this item a name between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  if item_row.archived_at is null and exists (
    select 1 from public.catalog_items
    where organization_id = target_organization_id
      and archived_at is null
      and id <> item_row.id
      and lower(name) = lower(clean_name)
  ) then
    raise exception 'An active Price Book item is already named "%".', clean_name
      using errcode = 'unique_violation';
  end if;

  update public.catalog_items
  set category = new_category, name = clean_name, description = new_description,
      unit_label = new_unit_label, is_labor = coalesce(new_is_labor, item_row.is_labor),
      unit_price_minor = coalesce(new_unit_price_minor, item_row.unit_price_minor),
      unit_cost_minor = coalesce(new_unit_cost_minor, item_row.unit_cost_minor),
      is_taxable = coalesce(new_is_taxable, item_row.is_taxable),
      revision = revision + 1, updated_by = (select auth.uid())
  where id = item_row.id
  returning * into item_row;

  return jsonb_build_object('id', item_row.id, 'name', item_row.name, 'revision', item_row.revision);
end;
$$;

revoke all on function public.update_catalog_item(
  uuid, uuid, integer, text, text, text, text, boolean, bigint, bigint, boolean
) from public;
revoke execute on function public.update_catalog_item(
  uuid, uuid, integer, text, text, text, text, boolean, bigint, bigint, boolean
) from anon;
grant execute on function public.update_catalog_item(
  uuid, uuid, integer, text, text, text, text, boolean, bigint, bigint, boolean
) to authenticated;

-- Permanent, on purpose (see the header): `request_pricing_lines.catalog_item_id` and
-- `quote_version_lines.catalog_item_id` are both `on delete set null`, so every document line that already
-- copied this item's name, price, and cost keeps that copy untouched. There is nothing left to block on --
-- no property pin, no business default -- so, unlike Taxes, this command has no reassignment check.
create or replace function public.delete_catalog_item(
  target_organization_id uuid,
  target_item_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  item_row public.catalog_items;
begin
  if not private.has_permission(target_organization_id, 'settings.price_book.manage') then
    raise exception 'You do not have access to manage the Price Book.' using errcode = 'insufficient_privilege';
  end if;

  select * into item_row
  from public.catalog_items
  where id = target_item_id and organization_id = target_organization_id
  for update;

  if item_row.id is null then
    raise exception 'That Price Book item was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from item_row.revision then
    raise exception 'Someone else changed this item while you were editing. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  delete from public.catalog_items where id = item_row.id;

  return jsonb_build_object('status', 'deleted', 'id', item_row.id);
end;
$$;

revoke all on function public.delete_catalog_item(uuid, uuid, integer) from public;
revoke execute on function public.delete_catalog_item(uuid, uuid, integer) from anon;
grant execute on function public.delete_catalog_item(uuid, uuid, integer) to authenticated;
