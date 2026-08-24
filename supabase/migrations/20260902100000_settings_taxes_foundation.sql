-- Contractor Settings, Part 2A: Taxes.
--
-- Nothing about tax rates exists yet. Quotes already carry `tax_name` / `tax_rate_basis_points`, but that
-- pair is the frozen snapshot on a version, not a shared rate list -- today it is filled in by hand on every
-- quote (`set_quote_draft_tax`), and "not configured" and "explicitly no tax" collapse to the exact same
-- row (name null, rate zero). This migration gives the business a saved rate list and a Business default,
-- lets a Property pin its own rate or inherit the default, and finally lets a Quote draft tell "nobody has
-- set tax yet" apart from "this document really has none" -- which is what makes the publish gate possible.
--
-- Order: permission, the rate table, the Business default columns, Property's pin, the Quote version's new
-- `tax_source`, the rate commands, the two count reads a confirmation dialog needs, the Business-default
-- command, then three small edits to existing Quote functions (create, draft tax, publish) so the new shape
-- is actually reachable end to end.

-- 1. Permission -------------------------------------------------------------------------------------------

-- Taxes is money-critical and, per the approved blueprint, hidden from every role except owner and admin --
-- unlike Business Profile, there is no broader "view" key here. One permission covers seeing and managing.
insert into public.permissions (key, description)
values ('settings.taxes.manage', 'See and manage saved tax rates and the Business default tax')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.taxes.manage'),
  ('admin', 'settings.taxes.manage')
on conflict (role, permission_key) do nothing;

-- 2. Saved tax rates -------------------------------------------------------------------------------------

create table public.organization_tax_rates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Matches quote_versions.tax_name's own bound: whatever a document freezes must fit what a rate can be
  -- named in the first place.
  name text not null check (char_length(trim(name)) between 1 and 80),
  -- 100 basis points is 1%. Zero is not a valid saved rate -- "No tax" is its own explicit choice below,
  -- never a 0% row sitting in this list.
  rate_basis_points integer not null check (rate_basis_points > 0 and rate_basis_points <= 10000),
  is_active boolean not null default true,
  revision integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint organization_tax_rates_organization_id_unique unique (organization_id, id)
);

comment on table public.organization_tax_rates is
  'Business-owned saved tax rates for Quotes and future Invoices. Written only by the commands below -- '
  'never edited through RLS directly -- so revision conflicts and the Property-reassignment rule before '
  'delete both go through one door.';

create index organization_tax_rates_active_idx
  on public.organization_tax_rates(organization_id, name)
  where is_active;

-- Every write to this table is a SECURITY DEFINER command. The grant buys nothing and only widens what a
-- compromised session could try, matching how organization_settings was hardened.
revoke insert, update, delete, truncate, references, trigger
  on public.organization_tax_rates
  from anon, authenticated;

alter table public.organization_tax_rates enable row level security;

-- Read access is wider than manage access on purpose: a quote editor needs the list to populate the Tax
-- dialog's saved-rate picker, and a property editor needs it for the pin-vs-inherit choice, even though
-- neither may touch Settings -> Taxes itself.
create policy "permitted members can view tax rates"
on public.organization_tax_rates for select to authenticated
using (
  private.is_organization_member(organization_id)
  and (
    private.has_permission(organization_id, 'settings.taxes.manage')
    or private.has_permission(organization_id, 'quotes.edit')
    or private.has_permission(organization_id, 'property.manage')
  )
);

-- 3. Business default ------------------------------------------------------------------------------------

-- Same shape as profile/branding/hours/pipeline: one revision, one editor, one timestamp, so a stale save is
-- refused the same way everywhere in Settings.
alter table public.organization_settings
  add column tax_default_source text not null default 'not_configured'
    check (tax_default_source in ('not_configured', 'rate', 'no_tax')),
  add column tax_default_rate_id uuid references public.organization_tax_rates(id) on delete set null,
  add column tax_revision integer not null default 1,
  add column tax_updated_by uuid references auth.users(id) on delete set null,
  add column tax_updated_at timestamptz,
  add constraint organization_settings_tax_default_consistency check (
    case tax_default_source
      when 'not_configured' then tax_default_rate_id is null
      when 'no_tax' then tax_default_rate_id is null
      else tax_default_rate_id is not null
    end
  );

-- Reuse the same audit trail Business Profile writes to; add the one section this slice introduces.
alter table public.organization_settings_audit drop constraint organization_settings_audit_section_check;
alter table public.organization_settings_audit add constraint organization_settings_audit_section_check
  check (section = any (array['profile', 'branding', 'hours', 'pipeline', 'taxes']));

-- 4. Property's pin ---------------------------------------------------------------------------------------

-- Null is "inherit the Business default" -- not a separate boolean, since the two states can never disagree
-- with each other. Written through the existing property.manage-gated RLS update, same as every other
-- Property field; no new command needed.
alter table public.properties
  add column tax_rate_id uuid references public.organization_tax_rates(id) on delete set null,
  add constraint properties_tax_rate_organization_fk foreign key (organization_id, tax_rate_id)
    references public.organization_tax_rates(organization_id, id) on delete set null;

-- What a rate-edit or rate-delete confirmation counts, and what "how many Properties inherit the Business
-- default" counts. Both are organization_id-first and tenant-scoped.
create index properties_tax_rate_idx
  on public.properties(organization_id, tax_rate_id)
  where tax_rate_id is not null;

-- 5. Quote version: telling "not configured" apart from "no tax" -----------------------------------------

alter table public.quote_versions
  add column tax_source text not null default 'not_configured'
    check (tax_source in (
      'not_configured', 'business_default', 'property_default', 'saved_rate', 'no_tax', 'custom'
    )),
  add column tax_rate_id uuid references public.organization_tax_rates(id) on delete set null,
  add constraint quote_versions_tax_rate_organization_fk foreign key (organization_id, tax_rate_id)
    references public.organization_tax_rates(organization_id, id) on delete set null;

-- Every existing version -- draft or already published -- has tax_name null / rate zero under the old
-- free-text flow, or a real rate someone already typed in. That is also the only signal available to sort
-- them: a draft with a rate keeps it as a real custom entry instead of suddenly asking staff to redo it, and
-- a historical published version is labelled the same way for consistency (the publish gate only ever looks
-- at the current draft, so this never re-blocks anything already sent). Published rows are otherwise frozen
-- by quote_versions_reject_published_change; this one backfill is exempt, then the trigger goes right back.
alter table public.quote_versions disable trigger quote_versions_reject_published_change;

update public.quote_versions
set tax_source = case when tax_rate_basis_points > 0 then 'custom' else 'not_configured' end;

alter table public.quote_versions enable trigger quote_versions_reject_published_change;

-- Added after the backfill above so the constraint's initial validation scan sees corrected data instead of
-- every pre-existing row's default.
-- A rate that is later deleted or deactivated never invalidates a quote that already froze its name and
-- percentage -- documents are exempt from the Property-reassignment rule on purpose. `business_default`
-- and `property_default` can each resolve to either a real rate or to "no tax", because that is what the
-- thing they followed was set to at the moment the quote picked it up.
alter table public.quote_versions add constraint quote_versions_tax_source_consistency check (
  case tax_source
    when 'not_configured' then tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null
    when 'no_tax' then tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null
    when 'custom' then tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is null
    when 'saved_rate' then tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is not null
    else
      (tax_rate_basis_points > 0 and tax_name is not null and tax_rate_id is not null)
      or (tax_rate_basis_points = 0 and tax_name is null and tax_rate_id is null)
  end
);

-- 6. Resolving a Property's effective tax -----------------------------------------------------------------

-- One answer, used both when a new Quote draft is created and, later, whenever a draft asks to follow
-- "the effective default" again. Never exposed directly -- callers already hold the permission and lock
-- they need before asking this.
create or replace function private.resolve_property_tax(
  target_organization_id uuid,
  target_property_id uuid
)
returns table (source text, name text, rate_basis_points integer, rate_id uuid)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  pinned_rate_id uuid;
  rate_row public.organization_tax_rates;
  default_source text;
  default_rate_id uuid;
begin
  select property.tax_rate_id into pinned_rate_id
  from public.properties as property
  where property.id = target_property_id and property.organization_id = target_organization_id;

  if pinned_rate_id is not null then
    select * into rate_row
    from public.organization_tax_rates
    where id = pinned_rate_id and organization_id = target_organization_id;

    if rate_row.id is not null then
      return query select 'property_default'::text, rate_row.name, rate_row.rate_basis_points, rate_row.id;
      return;
    end if;
    -- Fell through: the pinned rate is gone, which the delete command should never allow while pinned.
    -- Treat it the same as never having been configured rather than guess.
  end if;

  select settings.tax_default_source, settings.tax_default_rate_id
  into default_source, default_rate_id
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;

  if default_source = 'rate' then
    select * into rate_row
    from public.organization_tax_rates
    where id = default_rate_id and organization_id = target_organization_id;

    if rate_row.id is not null then
      return query select 'business_default'::text, rate_row.name, rate_row.rate_basis_points, rate_row.id;
      return;
    end if;
  elsif default_source = 'no_tax' then
    return query select 'business_default'::text, null::text, 0, null::uuid;
    return;
  end if;

  return query select 'not_configured'::text, null::text, 0, null::uuid;
end;
$$;

revoke all on function private.resolve_property_tax(uuid, uuid) from public, anon, authenticated;

-- 7. Managing the saved list -------------------------------------------------------------------------------

create or replace function public.create_organization_tax_rate(
  target_organization_id uuid,
  new_name text,
  new_rate_basis_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_name text;
  new_row public.organization_tax_rates;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 80 then
    raise exception 'Give this tax rate a name up to 80 characters.' using errcode = 'check_violation';
  end if;

  if new_rate_basis_points is null or new_rate_basis_points <= 0 or new_rate_basis_points > 10000 then
    raise exception 'A tax rate is greater than 0%% and no more than 100%%.' using errcode = 'check_violation';
  end if;

  insert into public.organization_tax_rates (organization_id, name, rate_basis_points, created_by, updated_by)
  values (target_organization_id, clean_name, new_rate_basis_points, (select auth.uid()), (select auth.uid()))
  returning * into new_row;

  return jsonb_build_object(
    'id', new_row.id, 'name', new_row.name, 'rate_basis_points', new_row.rate_basis_points,
    'is_active', new_row.is_active, 'revision', new_row.revision
  );
end;
$$;

revoke all on function public.create_organization_tax_rate(uuid, text, integer) from public;
revoke execute on function public.create_organization_tax_rate(uuid, text, integer) from anon;
grant execute on function public.create_organization_tax_rate(uuid, text, integer) to authenticated;

create or replace function public.update_organization_tax_rate(
  target_organization_id uuid,
  target_rate_id uuid,
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
  rate_row public.organization_tax_rates;
  clean_name text;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select * into rate_row
  from public.organization_tax_rates
  where id = target_rate_id and organization_id = target_organization_id
  for update;

  if rate_row.id is null then
    raise exception 'That tax rate was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from rate_row.revision then
    raise exception 'Someone else changed this tax rate while you were editing. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 80 then
    raise exception 'Give this tax rate a name up to 80 characters.' using errcode = 'check_violation';
  end if;

  if new_rate_basis_points is null or new_rate_basis_points <= 0 or new_rate_basis_points > 10000 then
    raise exception 'A tax rate is greater than 0%% and no more than 100%%.' using errcode = 'check_violation';
  end if;

  update public.organization_tax_rates
  set name = clean_name, rate_basis_points = new_rate_basis_points,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = rate_row.id
  returning * into rate_row;

  return jsonb_build_object(
    'id', rate_row.id, 'name', rate_row.name, 'rate_basis_points', rate_row.rate_basis_points,
    'is_active', rate_row.is_active, 'revision', rate_row.revision
  );
end;
$$;

revoke all on function public.update_organization_tax_rate(uuid, uuid, integer, text, integer) from public;
revoke execute on function public.update_organization_tax_rate(uuid, uuid, integer, text, integer) from anon;
grant execute on function public.update_organization_tax_rate(uuid, uuid, integer, text, integer)
  to authenticated;

-- One command for both directions: making a rate inactive removes it from new selections without touching
-- the Properties already pinned to it, and reactivating it is the same statement in reverse.
create or replace function public.set_organization_tax_rate_active(
  target_organization_id uuid,
  target_rate_id uuid,
  expected_revision integer,
  new_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  rate_row public.organization_tax_rates;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select * into rate_row
  from public.organization_tax_rates
  where id = target_rate_id and organization_id = target_organization_id
  for update;

  if rate_row.id is null then
    raise exception 'That tax rate was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from rate_row.revision then
    raise exception 'Someone else changed this tax rate while you were editing. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  update public.organization_tax_rates
  set is_active = coalesce(new_is_active, rate_row.is_active),
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = rate_row.id
  returning * into rate_row;

  return jsonb_build_object(
    'id', rate_row.id, 'name', rate_row.name, 'rate_basis_points', rate_row.rate_basis_points,
    'is_active', rate_row.is_active, 'revision', rate_row.revision
  );
end;
$$;

revoke all on function public.set_organization_tax_rate_active(uuid, uuid, integer, boolean) from public;
revoke execute on function public.set_organization_tax_rate_active(uuid, uuid, integer, boolean) from anon;
grant execute on function public.set_organization_tax_rate_active(uuid, uuid, integer, boolean)
  to authenticated;

create or replace function public.delete_organization_tax_rate(
  target_organization_id uuid,
  target_rate_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  rate_row public.organization_tax_rates;
  pinned_count integer;
  is_business_default boolean;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select * into rate_row
  from public.organization_tax_rates
  where id = target_rate_id and organization_id = target_organization_id
  for update;

  if rate_row.id is null then
    raise exception 'That tax rate was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from rate_row.revision then
    raise exception 'Someone else changed this tax rate while you were editing. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  select count(*) into pinned_count
  from public.properties
  where organization_id = target_organization_id and tax_rate_id = target_rate_id;

  if pinned_count > 0 then
    raise exception 'Reassign the % properties using this tax rate before deleting it.', pinned_count
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from public.organization_settings
    where organization_id = target_organization_id and tax_default_rate_id = target_rate_id
  ) into is_business_default;

  if is_business_default then
    raise exception 'This is the Business default tax. Choose a different default before deleting it.'
      using errcode = 'check_violation';
  end if;

  delete from public.organization_tax_rates where id = rate_row.id;

  return jsonb_build_object('status', 'deleted', 'id', rate_row.id);
end;
$$;

revoke all on function public.delete_organization_tax_rate(uuid, uuid, integer) from public;
revoke execute on function public.delete_organization_tax_rate(uuid, uuid, integer) from anon;
grant execute on function public.delete_organization_tax_rate(uuid, uuid, integer) to authenticated;

-- 8. Counts a confirmation dialog needs, never property identities --------------------------------------

create or replace function public.organization_tax_rate_property_count(
  target_organization_id uuid,
  target_rate_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result integer;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into result
  from public.properties
  where organization_id = target_organization_id and tax_rate_id = target_rate_id;

  return result;
end;
$$;

revoke all on function public.organization_tax_rate_property_count(uuid, uuid) from public;
revoke execute on function public.organization_tax_rate_property_count(uuid, uuid) from anon;
grant execute on function public.organization_tax_rate_property_count(uuid, uuid) to authenticated;

create or replace function public.organization_tax_default_property_count(target_organization_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  result integer;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into result
  from public.properties
  where organization_id = target_organization_id and tax_rate_id is null and deleted_at is null;

  return result;
end;
$$;

revoke all on function public.organization_tax_default_property_count(uuid) from public;
revoke execute on function public.organization_tax_default_property_count(uuid) from anon;
grant execute on function public.organization_tax_default_property_count(uuid) to authenticated;

-- 9. The Business default itself -----------------------------------------------------------------------

create or replace function public.set_organization_tax_default(
  target_organization_id uuid,
  expected_revision integer,
  new_source text,
  new_rate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  rate_row public.organization_tax_rates;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  if new_source not in ('rate', 'no_tax') then
    raise exception 'Choose a saved rate or No tax.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.tax_revision then
    select profile.full_name, settings_row.tax_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.tax_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  if new_source = 'rate' then
    select * into rate_row
    from public.organization_tax_rates
    where id = new_rate_id and organization_id = target_organization_id and is_active;

    if rate_row.id is null then
      raise exception 'Choose an active saved tax rate.' using errcode = 'check_violation';
    end if;
  else
    new_rate_id := null;
  end if;

  update public.organization_settings
  set tax_default_source = new_source, tax_default_rate_id = new_rate_id,
      tax_revision = tax_revision + 1, tax_updated_by = (select auth.uid()), tax_updated_at = now()
  where organization_id = target_organization_id
  returning tax_revision into settings_row.tax_revision;

  insert into public.organization_settings_audit (organization_id, section, changed_fields, actor_user_id)
  values (target_organization_id, 'taxes', array['tax_default_source'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'tax_revision', settings_row.tax_revision,
    'tax_default_source', new_source,
    'tax_default_rate_id', new_rate_id
  );
end;
$$;

revoke all on function public.set_organization_tax_default(uuid, integer, text, uuid) from public;
revoke execute on function public.set_organization_tax_default(uuid, integer, text, uuid) from anon;
grant execute on function public.set_organization_tax_default(uuid, integer, text, uuid) to authenticated;

-- 10. A new Quote draft starts from the real answer, not a blank one --------------------------------------

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
  resolved_tax record;
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

  select * into resolved_tax
  from private.resolve_property_tax(client_row.organization_id, property_row.id);

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
    tax_source, tax_name, tax_rate_basis_points, tax_rate_id,
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
    resolved_tax.source, resolved_tax.name, resolved_tax.rate_basis_points, resolved_tax.rate_id,
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

-- 11. The Quote draft's own Tax dialog ----------------------------------------------------------------------

-- Replaces the free-text-only version from Part 4B. A source of 'business_default' or 'property_default'
-- re-resolves the effective answer at the moment of saving rather than trusting a stale client read; 'rate'
-- freezes one chosen saved rate; 'custom' freezes a one-off name and percentage, and may also save it to the
-- shared list -- gated separately, because being allowed to price a quote is not being allowed to manage
-- Settings -> Taxes.
drop function if exists public.set_quote_draft_tax(uuid, integer, text, integer);

create or replace function public.set_quote_draft_tax(
  target_quote_id uuid,
  expected_revision integer,
  new_source text,
  new_rate_id uuid default null,
  new_custom_name text default null,
  new_custom_rate_basis_points integer default null,
  save_as_reusable boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  draft_row public.quote_versions;
  rate_row public.organization_tax_rates;
  resolved_tax record;
  clean_name text;
  clean_rate integer;
  saved_rate_id uuid;
begin
  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  if new_source not in ('business_default', 'property_default', 'saved_rate', 'no_tax', 'custom') then
    raise exception 'Choose a tax option.' using errcode = 'check_violation';
  end if;

  if new_source in ('business_default', 'property_default') then
    select * into resolved_tax
    from private.resolve_property_tax(draft_row.organization_id, (
      select property_id from public.quotes where id = draft_row.quote_id
    ));

    update public.quote_versions
    set tax_source = resolved_tax.source, tax_name = resolved_tax.name,
        tax_rate_basis_points = resolved_tax.rate_basis_points, tax_rate_id = resolved_tax.rate_id
    where id = draft_row.id;

  elsif new_source = 'saved_rate' then
    select * into rate_row
    from public.organization_tax_rates
    where id = new_rate_id and organization_id = draft_row.organization_id and is_active;

    if rate_row.id is null then
      raise exception 'Choose an active saved tax rate.' using errcode = 'check_violation';
    end if;

    update public.quote_versions
    set tax_source = 'saved_rate', tax_name = rate_row.name,
        tax_rate_basis_points = rate_row.rate_basis_points, tax_rate_id = rate_row.id
    where id = draft_row.id;

  elsif new_source = 'no_tax' then
    update public.quote_versions
    set tax_source = 'no_tax', tax_name = null, tax_rate_basis_points = 0, tax_rate_id = null
    where id = draft_row.id;

  else -- custom
    clean_rate := coalesce(new_custom_rate_basis_points, 0);
    if clean_rate <= 0 or clean_rate > 10000 then
      raise exception 'A tax rate is between 0 and 100 percent.' using errcode = 'check_violation';
    end if;

    clean_name := nullif(trim(coalesce(new_custom_name, '')), '');
    if clean_name is null or char_length(clean_name) > 80 then
      raise exception 'Give this tax a name the customer will recognize, under 80 characters.'
        using errcode = 'check_violation';
    end if;

    saved_rate_id := null;
    if coalesce(save_as_reusable, false) then
      if not private.has_permission(draft_row.organization_id, 'settings.taxes.manage') then
        raise exception 'You do not have access to save a reusable tax rate.'
          using errcode = 'insufficient_privilege';
      end if;

      insert into public.organization_tax_rates (
        organization_id, name, rate_basis_points, created_by, updated_by
      ) values (
        draft_row.organization_id, clean_name, clean_rate, (select auth.uid()), (select auth.uid())
      )
      returning id into saved_rate_id;
    end if;

    update public.quote_versions
    set tax_source = 'custom', tax_name = clean_name, tax_rate_basis_points = clean_rate,
        -- Provenance only: a saved-as-reusable custom rate links back to the new row, but the source stays
        -- 'custom' -- this document was still priced as a one-off, not picked from the list.
        tax_rate_id = saved_rate_id
    where id = draft_row.id;
  end if;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

revoke all on function public.set_quote_draft_tax(uuid, integer, text, uuid, text, integer, boolean)
  from public;
revoke execute on function public.set_quote_draft_tax(uuid, integer, text, uuid, text, integer, boolean)
  from anon;
grant execute on function public.set_quote_draft_tax(uuid, integer, text, uuid, text, integer, boolean)
  to authenticated;

-- 12. The publish gate ---------------------------------------------------------------------------------------

create or replace function public.publish_quote(
  target_quote_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  published_row public.quote_versions;
  draft_row public.quote_versions;
  priced_line_count integer;
  frozen jsonb;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.send'
     ) then
    raise exception 'You do not have access to send this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.status = 'awaiting_response' then
    select * into published_row from public.quote_versions
    where id = quote_row.current_published_version_id;
    if published_row.id is not null and published_row.revision = expected_revision then
      return jsonb_build_object(
        'quote_id', quote_row.id, 'quote_version_id', published_row.id,
        'version_number', published_row.version_number, 'document_hash', published_row.document_hash,
        'sent_at', quote_row.sent_at, 'status', quote_row.status,
        'calculation', published_row.calculation, 'already_published', true
      );
    end if;
  end if;

  if quote_row.status <> 'draft' then
    raise exception 'Only a draft quote can be sent.' using errcode = 'check_violation';
  end if;

  select * into draft_row from public.quote_versions
  where organization_id = quote_row.organization_id and quote_id = quote_row.id and status = 'draft'
  for update;

  if draft_row.id is null then
    raise exception 'This quote has no draft to send.' using errcode = 'check_violation';
  end if;
  if expected_revision is distinct from draft_row.revision then
    raise exception 'Someone else changed this quote while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  -- A quote with nothing on it is not a proposal. Everything else the document needs was already required
  -- when the quote was created: a client, a property, a title, and a number.
  -- Named quote first, then version: that is the order quote_version_lines_version_idx is built in, and
  -- leaving quote_id out would drop the count to an organization-wide scan of every line ever quoted.
  select count(*) into priced_line_count
  from public.quote_version_lines
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and quote_version_id = draft_row.id
    and line_kind = 'priced';
  if priced_line_count = 0 then
    raise exception 'Add at least one line before sending this quote.' using errcode = 'check_violation';
  end if;

  -- Priced work needs a real tax answer before a customer sees it. "No tax" is a legitimate answer;
  -- nobody having looked at it yet is not.
  if draft_row.tax_source = 'not_configured' then
    raise exception 'Choose a tax rate or confirm No tax in Settings -> Taxes before sending this quote.'
      using errcode = 'check_violation';
  end if;

  -- The send date is stamped before the freeze, not after. quotes_publication_is_dated is a plain check
  -- constraint, so Postgres tests it the moment freeze points the quote at its new publication - stamping
  -- afterwards would fail on a row that is only half updated. Caught by the Part 5A database test.
  update public.quotes set sent_at = coalesce(sent_at, now()) where id = quote_row.id;

  frozen := public.freeze_quote_version(quote_row.id, expected_revision);

  update public.quotes
  set status = 'awaiting_response',
      decision = null, decided_at = null, decision_method = null,
      decision_note = null, decided_by = null
  where id = quote_row.id
  returning * into quote_row;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.published',
    'Sent version ' || (frozen ->> 'version_number') || ' to the customer',
    (select auth.uid()),
    jsonb_build_object(
      'quote_version_id', frozen ->> 'quote_version_id',
      'version_number', (frozen ->> 'version_number')::integer
    )
  );

  return frozen
    || jsonb_build_object('sent_at', quote_row.sent_at, 'status', quote_row.status,
                          'already_published', false);
end;
$$;

revoke all on function public.publish_quote(uuid, integer) from public;
revoke execute on function public.publish_quote(uuid, integer) from anon;
grant execute on function public.publish_quote(uuid, integer) to authenticated;
