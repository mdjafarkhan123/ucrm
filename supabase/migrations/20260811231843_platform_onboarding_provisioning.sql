-- Idempotent provisioning: turns a paid onboarding application into a real organization.
--
-- This table is the durable retry anchor (unlike the other onboarding tables, it is
-- operational state, not immutable history: a failed attempt is reset and reused by
-- the next retry rather than appended to). The actual organization/package/billing/
-- membership creation runs inside one Postgres function so it either fully commits or
-- fully rolls back -- no partial organization can ever exist from a failed attempt.
-- Creating the Supabase Auth administrator happens outside Postgres (in the API route)
-- before this function is called, so a failure inside this function only ever leaves an
-- orphaned Auth user to clean up, never a half-created organization.

create table public.platform_onboarding_application_provisions (
  application_id uuid primary key references public.platform_onboarding_applications(id),
  status text not null default 'pending' check (status in ('pending', 'succeeded', 'failed')),
  organization_id uuid references public.organizations(id),
  administrator_user_id uuid,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger platform_onboarding_application_provisions_set_updated_at
before update on public.platform_onboarding_application_provisions
for each row execute function public.set_updated_at();

alter table public.platform_onboarding_application_provisions enable row level security;

revoke all on public.platform_onboarding_application_provisions from anon, authenticated;
grant select, insert, update on public.platform_onboarding_application_provisions to service_role;

-- Runs every Postgres write for provisioning as one transaction: creates the
-- organization, its package assignment, its billing account and initial payment
-- record (copied from the 4b payment confirmation as an 'initial' payment), sets its
-- timezone from the application, adds the first membership, and marks the application
-- account_created. The administrator Auth user must already exist by the time this is
-- called -- the caller passes its id and a pre-generated organization id so the two
-- can be created consistently without a second update step.
create or replace function public.provision_organization_from_application(
  target_application_id uuid,
  target_organization_id uuid,
  target_organization_name text,
  target_slug text,
  target_administrator_user_id uuid,
  target_administrator_role text default 'owner'
)
returns uuid
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_package_version_id uuid;
  app_time_zone text;
  version_status text;
  package_status text;
  payment record;
  paid_through date;
begin
  if target_organization_name is null or char_length(trim(target_organization_name)) = 0 then
    raise exception 'An organization name is required for provisioning.' using errcode = 'check_violation';
  end if;
  if target_slug is null or char_length(trim(target_slug)) = 0 then
    raise exception 'An organization slug is required for provisioning.' using errcode = 'check_violation';
  end if;

  select stage, package_version_id, time_zone
  into app_stage, app_package_version_id, app_time_zone
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('payment_confirmed', 'needs_attention') then
    raise exception 'This application is not ready for provisioning.' using errcode = 'check_violation';
  end if;

  select version.status, package.status
  into version_status, package_status
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = app_package_version_id;

  if version_status is null or package_status is null then
    raise exception 'The activated package version does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if version_status = 'draft' or package_status = 'draft' then
    raise exception 'The activated package version was never published.' using errcode = 'check_violation';
  end if;

  select amount_usd_cents, currency, private_reference, confirmed_at, mismatch_reason
  into payment
  from public.platform_onboarding_application_payment_confirmations
  where application_id = target_application_id;

  if not found then
    raise exception 'Payment must be confirmed before provisioning.' using errcode = 'check_violation';
  end if;

  paid_through := (payment.confirmed_at::date + interval '1 month')::date;

  insert into public.organizations (id, name, slug, lifecycle_status)
  values (target_organization_id, trim(target_organization_name), target_slug, 'active');

  insert into public.organization_package_assignments (
    organization_id, package_version_id, assignment_source, reason
  ) values (
    target_organization_id, app_package_version_id, 'provisioning',
    'Initial provisioning from paid onboarding application.'
  );

  insert into public.organization_billing_accounts (
    organization_id, paid_through_date, paid_through_source
  ) values (
    target_organization_id, paid_through, 'provisioning'
  );

  insert into public.organization_payment_confirmations (
    organization_id, payment_kind, amount_usd_cents, currency,
    private_reference, confirmed_at, paid_through_date, mismatch_reason
  ) values (
    target_organization_id, 'initial', payment.amount_usd_cents, payment.currency,
    payment.private_reference, payment.confirmed_at, paid_through, payment.mismatch_reason
  );

  update public.organization_settings
  set timezone = coalesce(nullif(trim(app_time_zone), ''), timezone)
  where organization_id = target_organization_id;

  insert into public.organization_members (organization_id, user_id, role)
  values (target_organization_id, target_administrator_user_id, target_administrator_role);

  update public.platform_onboarding_applications
  set stage = 'account_created'
  where id = target_application_id;

  return target_organization_id;
end;
$$;

revoke all on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text)
  to service_role;
