-- Payment reversal: before an organization exists, a confirmed payment can turn out to be
-- bad (bounced, disputed, sent to the wrong reference) and Jafar needs to undo the confirmation
-- without deleting evidence of it. A reversal is its own append-only record, not an edit or
-- delete of the original confirmation -- history stays intact either way.
--
-- Reversal blocks provisioning until payment is confirmed again, but the application can still
-- be re-paid: platform_onboarding_application_payment_confirmations previously allowed at most
-- one row per application (unique application_id), which made a second, later confirmation for
-- the same application impossible. That uniqueness is dropped here in favor of ordering by
-- confirmed_at -- the latest confirmation is the one that counts, everything earlier is history.

alter table public.platform_onboarding_application_payment_confirmations
  drop constraint platform_onboarding_application_payment_conf_application_id_key;

alter table public.platform_onboarding_applications
  add column payment_reversed_at timestamptz;

create table public.platform_onboarding_application_payment_reversals (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.platform_onboarding_applications(id),
  confirmation_id uuid not null references public.platform_onboarding_application_payment_confirmations(id),
  actor_owner_email text not null,
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  reversed_amount_usd_cents integer not null check (reversed_amount_usd_cents > 0),
  reversed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index platform_onboarding_application_payment_reversals_app_idx
  on public.platform_onboarding_application_payment_reversals (application_id, reversed_at desc);

alter table public.platform_onboarding_application_payment_reversals enable row level security;

revoke all on public.platform_onboarding_application_payment_reversals from anon, authenticated;
grant select, insert on public.platform_onboarding_application_payment_reversals to service_role;

create trigger platform_onboarding_application_payment_reversals_immutable
before update or delete on public.platform_onboarding_application_payment_reversals
for each row execute function private.prevent_platform_onboarding_history_mutation();

create or replace function public.reverse_onboarding_application_payment(
  target_application_id uuid,
  actor_email text,
  reason text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app record;
  confirmation record;
begin
  select stage, payment_reversed_at
  into app
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app.stage not in ('payment_confirmed', 'needs_attention') then
    raise exception 'Only a confirmed payment can be reversed.' using errcode = 'check_violation';
  end if;
  if app.payment_reversed_at is not null then
    raise exception 'This payment was already reversed.' using errcode = 'check_violation';
  end if;

  select id, amount_usd_cents
  into confirmation
  from public.platform_onboarding_application_payment_confirmations
  where application_id = target_application_id
  order by confirmed_at desc
  limit 1;

  if not found then
    raise exception 'No payment confirmation exists for this application.' using errcode = 'check_violation';
  end if;

  insert into public.platform_onboarding_application_payment_reversals (
    application_id, confirmation_id, actor_owner_email, reason, reversed_amount_usd_cents
  ) values (
    target_application_id, confirmation.id, actor_email, reason, confirmation.amount_usd_cents
  );

  update public.platform_onboarding_applications
  set stage = 'needs_attention', payment_reversed_at = now()
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    actor_email, 'onboarding_application.payment_reversed', 'onboarding_application',
    target_application_id::text,
    jsonb_build_object('reason', reason, 'reversed_amount_usd_cents', confirmation.amount_usd_cents)
  );
end;
$$;

revoke all on function public.reverse_onboarding_application_payment(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.reverse_onboarding_application_payment(uuid, text, text)
  to service_role;

-- Re-confirming payment after a reversal must clear the flag, or provisioning would stay
-- blocked forever even once a good payment is on file.
create or replace function public.confirm_onboarding_application_payment(
  target_application_id uuid,
  actor_email text,
  amount_usd_cents integer,
  private_reference text,
  mismatch_reason text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_package_version_id uuid;
begin
  select stage, package_version_id into app_stage, app_package_version_id
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('new', 'awaiting_payment', 'needs_attention') then
    raise exception 'This application can no longer be confirmed for payment.' using errcode = 'check_violation';
  end if;

  insert into public.platform_onboarding_application_payment_confirmations (
    application_id, actor_owner_email, amount_usd_cents, private_reference,
    package_version_id, mismatch_reason
  ) values (
    target_application_id, actor_email, amount_usd_cents, private_reference,
    app_package_version_id, mismatch_reason
  );

  update public.platform_onboarding_applications
  set stage = 'payment_confirmed', payment_reversed_at = null
  where id = target_application_id;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    actor_email, 'onboarding_application.payment_confirmed', 'onboarding_application',
    target_application_id::text,
    jsonb_build_object('amount_usd_cents', amount_usd_cents, 'mismatch_reason', mismatch_reason)
  );
end;
$$;

-- Provisioning must also refuse a reversed payment (not just the route-level stage gate, which
-- shares the same 'needs_attention' value with an unrelated retry-after-failure case), and must
-- read the latest confirmation now that more than one can exist per application.
create or replace function public.provision_organization_from_application(
  target_application_id uuid,
  target_organization_id uuid,
  target_organization_name text,
  target_slug text,
  target_administrator_user_id uuid,
  target_administrator_role text default 'owner',
  target_actor_owner_email text default null
)
returns uuid
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  app_stage text;
  app_payment_reversed_at timestamptz;
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
  if target_actor_owner_email is null or char_length(trim(target_actor_owner_email)) = 0 then
    raise exception 'An acting owner email is required for provisioning.' using errcode = 'check_violation';
  end if;

  select stage, payment_reversed_at, package_version_id, time_zone
  into app_stage, app_payment_reversed_at, app_package_version_id, app_time_zone
  from public.platform_onboarding_applications
  where id = target_application_id
  for update;

  if not found then
    raise exception 'The onboarding application does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if app_stage not in ('payment_confirmed', 'needs_attention') then
    raise exception 'This application is not ready for provisioning.' using errcode = 'check_violation';
  end if;
  if app_payment_reversed_at is not null then
    raise exception 'The payment for this application was reversed. Confirm payment again before provisioning.'
      using errcode = 'check_violation';
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
  where application_id = target_application_id
  order by confirmed_at desc
  limit 1;

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

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    target_actor_owner_email, 'onboarding_application.provisioned', 'organization',
    target_organization_id::text, jsonb_build_object('application_id', target_application_id)
  );

  return target_organization_id;
end;
$$;
