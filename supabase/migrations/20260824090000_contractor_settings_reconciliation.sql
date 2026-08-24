-- Contractor Settings Part 1 reconciliation.
--
-- The first foundation migration was written against an earlier contract. This one brings the database to
-- the behavior Jafar confirmed: the three settings pages save independently, a stale save can name who
-- saved before you, business hours can be genuinely unconfigured, split across up to three periods, run
-- overnight, or run all day, currency locks only once a customer has actually seen a Quote, and the address
-- has a say in whether customers see it.

-- 1. Per-section revisions, editor stamps, and the new settings columns ------------------------------
-- Three counters instead of one: someone editing hours can no longer collide with someone editing the logo.

alter table public.organization_settings
  add column profile_revision integer not null default 1 check (profile_revision >= 1),
  add column branding_revision integer not null default 1 check (branding_revision >= 1),
  add column hours_revision integer not null default 1 check (hours_revision >= 1),
  -- Part 1 shows only the latest editor per section. The audit table below is the history.
  add column profile_updated_by uuid references auth.users(id) on delete set null,
  add column profile_updated_at timestamptz,
  add column branding_updated_by uuid references auth.users(id) on delete set null,
  add column branding_updated_at timestamptz,
  add column hours_updated_by uuid references auth.users(id) on delete set null,
  add column hours_updated_at timestamptz,
  -- Both columns are not-null with a default because Quotes and Requests already read them. These stamps
  -- are what separates "we guessed UTC and USD at signup" from "a person confirmed this".
  add column timezone_confirmed_at timestamptz,
  add column currency_confirmed_at timestamptz,
  -- Off means customer surfaces show city and state/region only. On means they may show the full address.
  add column address_is_public boolean not null default false,
  add column hours_mode text not null default 'not_configured'
    check (hours_mode in ('not_configured', 'weekly', 'appointment_only'));

update public.organization_settings
set profile_revision = revision, branding_revision = revision, hours_revision = revision;

alter table public.organization_settings drop column revision;

-- The advisor flags all three editor foreign keys as uncovered: without these, removing a user seq-scans
-- organization_settings looking for rows to null out. Partial, because most rows have never been edited.
create index organization_settings_profile_editor_idx
  on public.organization_settings (profile_updated_by)
  where profile_updated_by is not null;

create index organization_settings_branding_editor_idx
  on public.organization_settings (branding_updated_by)
  where branding_updated_by is not null;

create index organization_settings_hours_editor_idx
  on public.organization_settings (hours_updated_by)
  where hours_updated_by is not null;

-- 2. Business hours: real states instead of one same-day interval -------------------------------------

alter table public.organization_business_hours
  add column period_index smallint not null default 0 check (period_index between 0 and 2),
  add column is_open_24h boolean not null default false;

alter table public.organization_business_hours drop constraint organization_business_hours_pkey;
alter table public.organization_business_hours add primary key (organization_id, weekday, period_index);

-- The old rule forbade a closing time at or before the opening time, which is exactly how a period that
-- crosses midnight reads. It also had no way to say "open all day" that was not a zero-length interval.
alter table public.organization_business_hours drop constraint organization_business_hours_check;

alter table public.organization_business_hours
  add constraint organization_business_hours_shape check (
    -- Closed: no times at all.
    (not is_open and not is_open_24h and opens_at is null and closes_at is null)
    -- Open all day: an explicit state, never 00:00-00:00.
    or (is_open and is_open_24h and opens_at is null and closes_at is null)
    -- A real period. closes_at earlier than opens_at means it runs into the next day.
    or (is_open and not is_open_24h
        and opens_at is not null and closes_at is not null and opens_at <> closes_at)
  );

-- A new organization gets no rows and no opinion. The Business Hours page offers Mon-Fri 8-5 as a
-- suggestion the owner has to save; nothing is confirmed on their behalf. Existing seeded rows stay
-- exactly as they are, but their hours_mode is 'not_configured' until someone saves.
drop trigger organizations_create_business_hours on public.organizations;
drop function private.create_organization_business_hours();

-- 3. Settings audit trail ------------------------------------------------------------------------------
-- Field names, actor, and time. Not values: Part 1 answers "who changed what and when" without keeping a
-- growing second copy of every setting.

create table public.organization_settings_audit (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  section text not null check (section in ('profile', 'branding', 'hours')),
  changed_fields text[] not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index organization_settings_audit_recent_idx
  on public.organization_settings_audit (organization_id, created_at desc);

-- Same shape the deposit events needed: without this, removing a user seq-scans every audit row.
create index organization_settings_audit_actor_idx
  on public.organization_settings_audit (actor_user_id)
  where actor_user_id is not null;

alter table public.organization_settings_audit enable row level security;

create policy "permitted members can view settings history"
on public.organization_settings_audit for select to authenticated
using (private.has_permission(organization_id, 'settings.business.view'));

-- Select only. Every row is written by one of the commands below.
grant select on public.organization_settings_audit to authenticated;

-- 4. Currency lock: published or sent, never a draft ---------------------------------------------------

-- Keeps the lock question an index probe rather than a scan of every quote in the organization.
create index quotes_organization_shared_idx
  on public.quotes (organization_id)
  where current_published_version_id is not null or sent_at is not null;

create or replace function public.organization_currency_is_locked(target_organization_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.has_permission(target_organization_id, 'settings.business.view') then
    raise exception 'You do not have access to business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  -- A draft nobody has seen carries no promise. The moment a customer can read the document, its currency
  -- is a statement we made to them.
  return exists (
    select 1 from public.quotes
    where organization_id = target_organization_id
      and (current_published_version_id is not null or sent_at is not null)
  );
end;
$$;

-- 5. Business Profile save ------------------------------------------------------------------------------

create or replace function public.save_organization_business_profile(
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
  new_address_is_public boolean,
  new_timezone text,
  new_currency_code text,
  confirm_timezone boolean,
  confirm_currency boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  current_name text;
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
  clean_address_is_public boolean;
  changed text[] := '{}';
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
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
  clean_address_is_public := coalesce(new_address_is_public, false);

  if clean_country_code is not null and clean_country_code !~ '^[A-Z]{2}$' then
    raise exception 'Choose a country from the list.' using errcode = 'check_violation';
  end if;

  if new_timezone is null or not exists (select 1 from pg_timezone_names where name = new_timezone) then
    raise exception 'Choose a valid timezone.' using errcode = 'check_violation';
  end if;

  if new_currency_code is null or new_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'Choose a valid currency.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  -- Not a failure. Somebody else saved while this page was open, so the answer names them and the browser
  -- offers to look at their version instead of silently flattening it.
  if expected_revision is distinct from settings_row.profile_revision then
    select profile.full_name, settings_row.profile_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.profile_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  -- The browser's timezone and the country's currency are suggestions on the page. Neither is saved unless
  -- the person actually chose it, so an unconfirmed value can only be sent back unchanged.
  if not coalesce(confirm_timezone, false) and new_timezone is distinct from settings_row.timezone then
    raise exception 'Confirm the timezone before saving it.' using errcode = 'check_violation';
  end if;

  if not coalesce(confirm_currency, false) and new_currency_code is distinct from settings_row.currency_code
  then
    raise exception 'Confirm the currency before saving it.' using errcode = 'check_violation';
  end if;

  if new_currency_code is distinct from settings_row.currency_code
     and exists (
       select 1 from public.quotes
       where organization_id = target_organization_id
         and (current_published_version_id is not null or sent_at is not null)
     )
  then
    raise exception 'Currency cannot change once a Quote has been sent to a customer.'
      using errcode = 'check_violation';
  end if;

  select organization.name into current_name
  from public.organizations as organization
  where organization.id = target_organization_id;

  changed := changed
    || case when clean_name is distinct from current_name then array['name'] else '{}' end
    || case when clean_trade is distinct from settings_row.trade then array['trade'] else '{}' end
    || case when clean_phone is distinct from settings_row.phone then array['phone'] else '{}' end
    || case when clean_website is distinct from settings_row.website then array['website'] else '{}' end
    || case when clean_description is distinct from settings_row.description
         then array['description'] else '{}' end
    || case when clean_address_line1 is distinct from settings_row.address_line1
         then array['address_line1'] else '{}' end
    || case when clean_address_line2 is distinct from settings_row.address_line2
         then array['address_line2'] else '{}' end
    || case when clean_city is distinct from settings_row.city then array['city'] else '{}' end
    || case when clean_region is distinct from settings_row.region then array['region'] else '{}' end
    || case when clean_postal_code is distinct from settings_row.postal_code
         then array['postal_code'] else '{}' end
    || case when clean_country_code is distinct from settings_row.country_code
         then array['country_code'] else '{}' end
    || case when clean_address_is_public is distinct from settings_row.address_is_public
         then array['address_is_public'] else '{}' end
    || case when new_timezone is distinct from settings_row.timezone then array['timezone'] else '{}' end
    || case when new_currency_code is distinct from settings_row.currency_code
         then array['currency_code'] else '{}' end
    -- Confirming a suggested timezone or currency is itself a change worth recording, even when the value
    -- it settles on is the one that was already sitting there.
    || case when coalesce(confirm_timezone, false) and settings_row.timezone_confirmed_at is null
         then array['timezone_confirmed'] else '{}' end
    || case when coalesce(confirm_currency, false) and settings_row.currency_confirmed_at is null
         then array['currency_confirmed'] else '{}' end;

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
    address_is_public = clean_address_is_public,
    timezone = new_timezone,
    currency_code = new_currency_code,
    timezone_confirmed_at = case
      when coalesce(confirm_timezone, false) then now() else timezone_confirmed_at end,
    currency_confirmed_at = case
      when coalesce(confirm_currency, false) then now() else currency_confirmed_at end,
    profile_revision = profile_revision + 1,
    profile_updated_by = (select auth.uid()),
    profile_updated_at = now()
  where organization_id = target_organization_id
  returning profile_revision into new_revision;

  if array_length(changed, 1) is not null then
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (target_organization_id, 'profile', changed, (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'profile_revision', new_revision,
    'name', clean_name,
    'timezone_confirmed', coalesce(confirm_timezone, false) or settings_row.timezone_confirmed_at is not null,
    'currency_confirmed',
      coalesce(confirm_currency, false) or settings_row.currency_confirmed_at is not null
  );
end;
$$;

-- 6. Business Hours save ---------------------------------------------------------------------------------
-- Rows are replaced wholesale, then the rules one row cannot see are checked against the table. An
-- exception here rolls the whole command back, so a refused save leaves the old week untouched.

create or replace function public.save_organization_business_hours(
  target_organization_id uuid,
  expected_revision integer,
  new_mode text,
  new_hours jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
  offending_weekday smallint;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Saving is what configures the week. 'not_configured' is a starting state, not something to save.
  if new_mode is null or new_mode not in ('weekly', 'appointment_only') then
    raise exception 'Choose weekly hours or appointment only.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.hours_revision then
    select profile.full_name, settings_row.hours_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.hours_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  delete from public.organization_business_hours where organization_id = target_organization_id;

  if new_mode = 'weekly' then
    if new_hours is null or jsonb_typeof(new_hours) <> 'array' then
      raise exception 'Business hours must include all seven days.' using errcode = 'check_violation';
    end if;

    -- The per-row shape constraint fires here: a closed row with times, or a 24-hour row with times, or a
    -- period whose two times are equal, cannot get in.
    insert into public.organization_business_hours (
      organization_id, weekday, period_index, is_open, is_open_24h, opens_at, closes_at
    )
    select
      target_organization_id,
      (item ->> 'weekday')::smallint,
      coalesce((item ->> 'period_index')::smallint, 0),
      coalesce((item ->> 'is_open')::boolean, false),
      coalesce((item ->> 'is_open_24h')::boolean, false),
      nullif(item ->> 'opens_at', '')::time,
      nullif(item ->> 'closes_at', '')::time
    from jsonb_array_elements(new_hours) as item;

    if (
      select count(distinct weekday) from public.organization_business_hours
      where organization_id = target_organization_id
    ) <> 7 then
      raise exception 'Business hours must cover every day of the week.' using errcode = 'check_violation';
    end if;

    -- Up to three periods a day, numbered from zero with no gaps.
    select weekday into offending_weekday
    from public.organization_business_hours
    where organization_id = target_organization_id
    group by weekday
    having count(*) > 3 or max(period_index) <> count(*) - 1
    limit 1;

    if offending_weekday is not null then
      raise exception 'A day can have up to three time periods, one after another.'
        using errcode = 'check_violation';
    end if;

    -- A closed day and an all-day day are the whole day. They cannot share it with another period.
    select weekday into offending_weekday
    from public.organization_business_hours
    where organization_id = target_organization_id
    group by weekday
    having bool_or(not is_open or is_open_24h) and count(*) > 1
    limit 1;

    if offending_weekday is not null then
      raise exception 'A day that is closed or open 24 hours cannot also have time periods.'
        using errcode = 'check_violation';
    end if;

    -- Periods run in clock order and never overlap. A period that crosses midnight ends past 1440, so
    -- nothing else can follow it on the same day, which is what makes it the last one.
    select ordered.weekday into offending_weekday
    from (
      select
        weekday,
        extract(epoch from opens_at) / 60 as start_minute,
        lag(extract(epoch from opens_at) / 60)
          over (partition by weekday order by period_index) as previous_start,
        lag(case
              when closes_at <= opens_at then extract(epoch from closes_at) / 60 + 1440
              else extract(epoch from closes_at) / 60
            end)
          over (partition by weekday order by period_index) as previous_end
      from public.organization_business_hours
      where organization_id = target_organization_id and is_open and not is_open_24h
    ) as ordered
    where ordered.previous_start is not null
      and (ordered.start_minute <= ordered.previous_start or ordered.start_minute < ordered.previous_end)
    limit 1;

    if offending_weekday is not null then
      raise exception 'Time periods on the same day have to run in order without overlapping.'
        using errcode = 'check_violation';
    end if;
  end if;

  update public.organization_settings
  set
    hours_mode = new_mode,
    hours_revision = hours_revision + 1,
    hours_updated_by = (select auth.uid()),
    hours_updated_at = now()
  where organization_id = target_organization_id
  returning hours_revision into new_revision;

  insert into public.organization_settings_audit (
    organization_id, section, changed_fields, actor_user_id
  )
  values (
    target_organization_id,
    'hours',
    case when new_mode is distinct from settings_row.hours_mode
      then array['hours_mode', 'hours'] else array['hours'] end,
    (select auth.uid())
  );

  return jsonb_build_object('status', 'saved', 'hours_revision', new_revision, 'hours_mode', new_mode);
end;
$$;

-- 7. Branding: color, logo, logo removal ----------------------------------------------------------------

create or replace function public.save_organization_branding(
  target_organization_id uuid,
  expected_revision integer,
  new_brand_color text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  settings_row public.organization_settings;
  clean_brand_color text;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  clean_brand_color := nullif(trim(coalesce(new_brand_color, '')), '');
  if clean_brand_color is not null and clean_brand_color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Brand color must be a hex color.' using errcode = 'check_violation';
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from settings_row.branding_revision then
    select profile.full_name, settings_row.branding_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.branding_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  update public.organization_settings
  set
    brand_color = clean_brand_color,
    branding_revision = branding_revision + 1,
    branding_updated_by = (select auth.uid()),
    branding_updated_at = now()
  where organization_id = target_organization_id
  returning branding_revision into new_revision;

  if clean_brand_color is distinct from settings_row.brand_color then
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (target_organization_id, 'branding', array['brand_color'], (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved', 'branding_revision', new_revision, 'brand_color', clean_brand_color
  );
end;
$$;

-- The logo is committed after its bytes are already in storage, so there is no earlier state for a second
-- tab to overwrite. These two move the branding counter without a conflict check.

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
  set
    logo_object_key = new_object_key,
    branding_revision = branding_revision + 1,
    branding_updated_by = (select auth.uid()),
    branding_updated_at = now()
  where organization_id = target_organization_id
  returning branding_revision into new_revision;

  insert into public.organization_settings_audit (
    organization_id, section, changed_fields, actor_user_id
  )
  values (target_organization_id, 'branding', array['logo'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'branding_revision', new_revision,
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
  set
    logo_object_key = null,
    branding_revision = branding_revision + 1,
    branding_updated_by = (select auth.uid()),
    branding_updated_at = now()
  where organization_id = target_organization_id
  returning branding_revision into new_revision;

  insert into public.organization_settings_audit (
    organization_id, section, changed_fields, actor_user_id
  )
  values (target_organization_id, 'branding', array['logo'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'branding_revision', new_revision,
    'previous_object_key', previous_object_key
  );
end;
$$;

-- 8. Retire the single whole-record command and set grants ----------------------------------------------

drop function public.save_organization_business_settings(
  uuid, integer, text, text, text, text, text, text, text, text, text, text, text, text, text, text, jsonb
);

revoke all on function public.save_organization_business_profile(
  uuid, integer, text, text, text, text, text, text, text, text, text, text, text, boolean, text, text,
  boolean, boolean
) from public;
grant execute on function public.save_organization_business_profile(
  uuid, integer, text, text, text, text, text, text, text, text, text, text, text, boolean, text, text,
  boolean, boolean
) to authenticated;

revoke all on function public.save_organization_business_hours(uuid, integer, text, jsonb) from public;
grant execute on function public.save_organization_business_hours(uuid, integer, text, jsonb) to authenticated;

revoke all on function public.save_organization_branding(uuid, integer, text) from public;
grant execute on function public.save_organization_branding(uuid, integer, text) to authenticated;

revoke all on function public.set_organization_logo(uuid, text) from public;
grant execute on function public.set_organization_logo(uuid, text) to authenticated;

revoke all on function public.remove_organization_logo(uuid) from public;
grant execute on function public.remove_organization_logo(uuid) to authenticated;

revoke all on function public.organization_currency_is_locked(uuid) from public;
grant execute on function public.organization_currency_is_locked(uuid) to authenticated;
