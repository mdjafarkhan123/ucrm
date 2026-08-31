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
