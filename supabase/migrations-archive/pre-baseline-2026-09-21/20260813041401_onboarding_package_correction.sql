-- Pre-payment package correction: lets the owner change which package version an
-- onboarding application will activate, before payment is confirmed. Re-snapshots
-- the package the same way submission does; the original submission snapshot in
-- platform_onboarding_application_submissions is never touched, so the prospect's
-- very first choice stays recoverable. Reuses the existing corrections history
-- table -- this is a correction, not a new kind of record.

create or replace function public.correct_onboarding_application_package(
  target_application_id uuid,
  actor_email text,
  new_package_version_id uuid,
  correction_reason text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  current record;
  already_paid boolean;
  version_status text;
  package_status text;
  new_snapshot jsonb;
  before_state jsonb;
  after_state jsonb;
begin
  select stage, package_version_id, package_snapshot
  into current
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if current.stage not in ('new', 'awaiting_payment', 'needs_attention') then
    raise exception 'This application can no longer be corrected.' using errcode = 'check_violation';
  end if;

  select exists (
    select 1
    from public.platform_onboarding_application_payment_confirmations
    where application_id = target_application_id
  ) into already_paid;

  if already_paid then
    raise exception 'The package can no longer be changed after payment is confirmed.' using errcode = 'check_violation';
  end if;

  if new_package_version_id = current.package_version_id then
    raise exception 'Choose a different package to change.' using errcode = 'check_violation';
  end if;

  select version.status, package.status, jsonb_build_object(
    'display_name', version.display_name,
    'public_description', version.public_description,
    'value_explanation', version.value_explanation,
    'price_usd_cents', version.price_usd_cents,
    'currency', version.currency,
    'billing_period', version.billing_period,
    'version_number', version.version_number
  )
  into version_status, package_status, new_snapshot
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = new_package_version_id;

  if version_status is null then
    raise exception 'The selected package no longer exists.' using errcode = 'foreign_key_violation';
  end if;
  if version_status <> 'published' or package_status <> 'published' then
    raise exception 'The selected package is not available.' using errcode = 'check_violation';
  end if;

  before_state := jsonb_build_object(
    'package_version_id', current.package_version_id,
    'package_snapshot', current.package_snapshot
  );
  after_state := jsonb_build_object(
    'package_version_id', new_package_version_id,
    'package_snapshot', new_snapshot
  );

  update public.platform_onboarding_applications
  set package_version_id = new_package_version_id,
    package_snapshot = new_snapshot
  where id = target_application_id;

  insert into public.platform_onboarding_application_corrections (
    application_id, actor_owner_email, reason, before_state, after_state
  ) values (
    target_application_id, actor_email, correction_reason, before_state, after_state
  );

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor_email, 'onboarding_application.package_corrected', 'onboarding_application',
    target_application_id::text, before_state, after_state || jsonb_build_object('reason', correction_reason)
  );
end;
$$;

revoke all on function public.correct_onboarding_application_package(uuid, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.correct_onboarding_application_package(uuid, text, uuid, text)
  to service_role;
