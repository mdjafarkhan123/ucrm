-- Contractor Settings Part 1: Business Profile, Branding, and Business Hours.
-- Extends the one-row organization_settings record with shared business identity, adds the weekly
-- business-hours table, and closes the RLS gap that currently lets every member update organization
-- settings. All writes move behind one revisioned, permission-checked command; every table keeps only
-- the SELECT grant a page needs to read it.

-- 1. Shared business identity, branding, and address -------------------------------------------------

alter table public.organization_settings
  add column trade text check (trade is null or char_length(trim(trade)) between 1 and 120),
  add column phone text check (phone is null or char_length(trim(phone)) between 1 and 32),
  add column website text check (website is null or char_length(trim(website)) between 1 and 2048),
  add column description text check (description is null or char_length(trim(description)) between 1 and 500),
  add column address_line1 text check (address_line1 is null or char_length(trim(address_line1)) between 1 and 160),
  add column address_line2 text check (address_line2 is null or char_length(trim(address_line2)) between 1 and 160),
  add column city text check (city is null or char_length(trim(city)) between 1 and 120),
  add column region text check (region is null or char_length(trim(region)) between 1 and 120),
  add column postal_code text check (postal_code is null or char_length(trim(postal_code)) between 1 and 20),
  add column country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  add column brand_color text check (brand_color is null or brand_color ~ '^#[0-9A-Fa-f]{6}$'),
  add column logo_object_key text unique,
  add column revision integer not null default 1 check (revision >= 1);

-- 2. Business hours: exactly seven weekday rows per organization -------------------------------------
-- weekday follows Postgres extract(dow): 0 = Sunday .. 6 = Saturday.

create table public.organization_business_hours (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  is_open boolean not null default true,
  opens_at time,
  closes_at time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, weekday),
  check (not is_open or (opens_at is not null and closes_at is not null and closes_at > opens_at))
);

create trigger organization_business_hours_set_updated_at
before update on public.organization_business_hours
for each row execute function public.set_updated_at();

-- Seeds Mon-Fri 8:00-17:00 open, weekend closed. A contractor changes this on the Business Hours page;
-- it is a starting default, not a product opinion.
create or replace function private.create_organization_business_hours()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.organization_business_hours (organization_id, weekday, is_open, opens_at, closes_at)
  select
    new.id,
    weekday,
    weekday between 1 and 5,
    case when weekday between 1 and 5 then time '08:00' end,
    case when weekday between 1 and 5 then time '17:00' end
  from generate_series(0, 6) as weekday
  on conflict (organization_id, weekday) do nothing;
  return new;
end;
$$;

create trigger organizations_create_business_hours
after insert on public.organizations
for each row execute function private.create_organization_business_hours();

revoke all on function private.create_organization_business_hours() from public;

insert into public.organization_business_hours (organization_id, weekday, is_open, opens_at, closes_at)
select
  organization.id,
  weekday,
  weekday between 1 and 5,
  case when weekday between 1 and 5 then time '08:00' end,
  case when weekday between 1 and 5 then time '17:00' end
from public.organizations as organization
cross join generate_series(0, 6) as weekday
on conflict (organization_id, weekday) do nothing;

-- 3. Permission catalog -------------------------------------------------------------------------------

insert into public.permissions (key, description)
values
  ('settings.business.view', 'See business profile, branding, and business hours'),
  ('settings.business.edit', 'Change business profile, branding, and business hours')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'settings.business.view'),
  ('owner', 'settings.business.edit'),
  ('admin', 'settings.business.view'),
  ('admin', 'settings.business.edit'),
  ('office', 'settings.business.view'),
  ('sales', 'settings.business.view'),
  ('field', 'settings.business.view'),
  ('finance', 'settings.business.view')
on conflict (role, permission_key) do nothing;

-- 4. Tighten RLS: replace the blanket member-update policy with permission-checked access ------------

drop policy "members can view organization settings" on public.organization_settings;
drop policy "members can update organization settings" on public.organization_settings;

create policy "permitted members can view organization settings"
on public.organization_settings for select to authenticated
using (private.has_permission(organization_id, 'settings.business.view'));

-- No update policy: every write goes through save_organization_business_settings below, which is the
-- only place the currency-lock and revision-conflict rules are enforced. Granting table UPDATE here
-- would let a client bypass both.
revoke update on public.organization_settings from authenticated;

alter table public.organization_business_hours enable row level security;

create policy "permitted members can view business hours"
on public.organization_business_hours for select to authenticated
using (private.has_permission(organization_id, 'settings.business.view'));

grant select on public.organization_business_hours to authenticated;

-- 5. Atomic Business Profile, Branding, and Business Hours save ----------------------------------------
-- One command, one revision counter. Every settings page reads the full current record, edits its own
-- fields, and sends the whole object back so a stale tab on any page conflicts instead of overwriting.

create or replace function public.save_organization_business_settings(
  target_organization_id uuid,
  expected_revision integer,
  new_name text,
  new_trade text,
  new_phone text,
  new_website text,
  new_description text,
  new_address_line1 text,
  new_address_line2 text,
  new_city text,
  new_region text,
  new_postal_code text,
  new_country_code text,
  new_timezone text,
  new_currency_code text,
  new_brand_color text,
  new_hours jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  clean_name text;
  clean_trade text;
  clean_phone text;
  clean_website text;
  clean_description text;
  clean_address_line1 text;
  clean_address_line2 text;
  clean_city text;
  clean_region text;
  clean_postal_code text;
  clean_country_code text;
  clean_brand_color text;
  new_revision integer;
  hour_row jsonb;
  hour_weekday_count integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 120 then
    raise exception 'Business name must be between 2 and 120 characters.' using errcode = 'check_violation';
  end if;

  clean_trade := nullif(trim(coalesce(new_trade, '')), '');
  clean_phone := nullif(trim(coalesce(new_phone, '')), '');
  clean_website := nullif(trim(coalesce(new_website, '')), '');
  clean_description := nullif(trim(coalesce(new_description, '')), '');
  clean_address_line1 := nullif(trim(coalesce(new_address_line1, '')), '');
  clean_address_line2 := nullif(trim(coalesce(new_address_line2, '')), '');
  clean_city := nullif(trim(coalesce(new_city, '')), '');
  clean_region := nullif(trim(coalesce(new_region, '')), '');
  clean_postal_code := nullif(trim(coalesce(new_postal_code, '')), '');
  clean_country_code := nullif(upper(trim(coalesce(new_country_code, ''))), '');
  clean_brand_color := nullif(trim(coalesce(new_brand_color, '')), '');

  if clean_country_code is not null and clean_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Choose a country from the list.' using errcode = 'check_violation';
  end if;

  if clean_brand_color is not null and clean_brand_color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Brand color must be a hex color.' using errcode = 'check_violation';
  end if;

  if new_timezone is null or not exists (
    select 1 from pg_timezone_names where name = new_timezone
  ) then
    raise exception 'Choose a valid timezone.' using errcode = 'check_violation';
  end if;

  if new_currency_code is null or new_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'Choose a valid currency.' using errcode = 'check_violation';
  end if;

  if new_hours is null or jsonb_typeof(new_hours) <> 'array' or jsonb_array_length(new_hours) <> 7 then
    raise exception 'Business hours must include all seven days.' using errcode = 'check_violation';
  end if;

  select count(distinct (item ->> 'weekday')::int) into hour_weekday_count
  from jsonb_array_elements(new_hours) as item;
  if hour_weekday_count <> 7 then
    raise exception 'Business hours must include each day exactly once.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.revision then
    raise exception 'Someone else changed these settings while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  if new_currency_code is distinct from settings_row.currency_code
     and exists (select 1 from public.quotes where organization_id = target_organization_id)
  then
    raise exception 'Currency cannot change once a Quote exists.' using errcode = 'check_violation';
  end if;

  update public.organizations set name = clean_name where id = target_organization_id;

  update public.organization_settings
  set
    trade = clean_trade,
    phone = clean_phone,
    website = clean_website,
    description = clean_description,
    address_line1 = clean_address_line1,
    address_line2 = clean_address_line2,
    city = clean_city,
    region = clean_region,
    postal_code = clean_postal_code,
    country_code = clean_country_code,
    timezone = new_timezone,
    currency_code = new_currency_code,
    brand_color = clean_brand_color,
    revision = revision + 1
  where organization_id = target_organization_id
  returning revision into new_revision;

  for hour_row in select * from jsonb_array_elements(new_hours)
  loop
    insert into public.organization_business_hours (
      organization_id, weekday, is_open, opens_at, closes_at
    )
    values (
      target_organization_id,
      (hour_row ->> 'weekday')::smallint,
      coalesce((hour_row ->> 'is_open')::boolean, false),
      nullif(hour_row ->> 'opens_at', '')::time,
      nullif(hour_row ->> 'closes_at', '')::time
    )
    on conflict (organization_id, weekday) do update
    set
      is_open = excluded.is_open,
      opens_at = excluded.opens_at,
      closes_at = excluded.closes_at;
  end loop;

  return jsonb_build_object('revision', new_revision, 'name', clean_name);
end;
$$;

revoke all on function public.save_organization_business_settings(
  uuid, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, text, jsonb
) from public;
revoke execute on function public.save_organization_business_settings(
  uuid, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, text, jsonb
) from anon;
grant execute on function public.save_organization_business_settings(
  uuid, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, text, jsonb
) to authenticated;

-- 6. Logo commands -------------------------------------------------------------------------------------
-- The object key is scoped under "<organization_id>/logo/", the same org-prefix trust boundary attachment
-- keys already use, so a guessed or leaked key can never be pointed at another organization's row.

create or replace function public.set_organization_logo(
  target_organization_id uuid,
  new_object_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  previous_object_key text;
  new_revision integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_object_key is null
     or new_object_key !~ ('^' || target_organization_id::text || '/logo/')
  then
    raise exception 'That logo upload is invalid.' using errcode = 'check_violation';
  end if;

  select logo_object_key into previous_object_key
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  update public.organization_settings
  set logo_object_key = new_object_key, revision = revision + 1
  where organization_id = target_organization_id
  returning revision into new_revision;

  return jsonb_build_object(
    'revision', new_revision,
    'logo_object_key', new_object_key,
    'previous_object_key', previous_object_key
  );
end;
$$;

create or replace function public.remove_organization_logo(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  previous_object_key text;
  new_revision integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  select logo_object_key into previous_object_key
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  update public.organization_settings
  set logo_object_key = null, revision = revision + 1
  where organization_id = target_organization_id
  returning revision into new_revision;

  return jsonb_build_object('revision', new_revision, 'previous_object_key', previous_object_key);
end;
$$;

revoke all on function public.set_organization_logo(uuid, text) from public;
revoke execute on function public.set_organization_logo(uuid, text) from anon;
grant execute on function public.set_organization_logo(uuid, text) to authenticated;

revoke all on function public.remove_organization_logo(uuid) from public;
revoke execute on function public.remove_organization_logo(uuid) from anon;
grant execute on function public.remove_organization_logo(uuid) to authenticated;
