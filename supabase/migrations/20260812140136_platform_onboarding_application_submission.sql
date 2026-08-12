-- Atomic public submission for the onboarding application form.
-- Snapshots the package as published right now, saves the application and its
-- immutable submission record together, and flags an obvious repeat submitter
-- as a review warning only (never merges or blocks the submission).

create or replace function public.submit_onboarding_application(
  target_business_name text,
  target_main_contact_name text,
  target_main_contact_email text,
  target_main_contact_phone text,
  target_initial_administrator_name text,
  target_initial_administrator_email text,
  target_trade text,
  target_city_country text,
  target_time_zone text,
  target_note text,
  target_package_version_id uuid,
  target_privacy_policy_version text,
  target_submitted_data jsonb
)
returns uuid
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  version_status text;
  package_status text;
  package_snapshot jsonb;
  clean_business_name text;
  clean_contact_email text;
  clean_admin_email text;
  is_duplicate boolean;
  new_application_id uuid;
begin
  select version.status, package.status, jsonb_build_object(
    'display_name', version.display_name,
    'public_description', version.public_description,
    'value_explanation', version.value_explanation,
    'price_usd_cents', version.price_usd_cents,
    'currency', version.currency,
    'billing_period', version.billing_period,
    'version_number', version.version_number
  )
  into version_status, package_status, package_snapshot
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = target_package_version_id;

  if version_status is null then
    raise exception 'The selected package no longer exists.' using errcode = 'foreign_key_violation';
  end if;
  if version_status <> 'published' or package_status <> 'published' then
    raise exception 'The selected package is no longer available.' using errcode = 'check_violation';
  end if;

  clean_business_name := trim(target_business_name);
  clean_contact_email := lower(trim(target_main_contact_email));
  clean_admin_email := nullif(lower(trim(coalesce(target_initial_administrator_email, ''))), '');

  select exists (
    select 1
    from public.platform_onboarding_applications as existing
    where lower(existing.main_contact_email) = clean_contact_email
       or lower(existing.business_name) = lower(clean_business_name)
       or (clean_admin_email is not null
           and lower(existing.initial_administrator_email) = clean_admin_email)
  ) into is_duplicate;

  insert into public.platform_onboarding_applications (
    business_name, main_contact_name, main_contact_email, main_contact_phone,
    initial_administrator_name, initial_administrator_email, trade, city_country, time_zone,
    note, package_version_id, package_snapshot, possible_duplicate
  ) values (
    clean_business_name, trim(target_main_contact_name), clean_contact_email, trim(target_main_contact_phone),
    nullif(trim(coalesce(target_initial_administrator_name, '')), ''), clean_admin_email,
    trim(target_trade), trim(target_city_country), trim(target_time_zone),
    nullif(trim(coalesce(target_note, '')), ''), target_package_version_id, package_snapshot, is_duplicate
  )
  returning id into new_application_id;

  insert into public.platform_onboarding_application_submissions (
    application_id, submitted_data, package_snapshot, privacy_policy_version, agreement_accepted_at
  ) values (
    new_application_id, target_submitted_data, package_snapshot, target_privacy_policy_version, now()
  );

  return new_application_id;
end;
$$;

revoke all on function public.submit_onboarding_application(
  text, text, text, text, text, text, text, text, text, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.submit_onboarding_application(
  text, text, text, text, text, text, text, text, text, text, uuid, text, jsonb
) to service_role;
