-- Part 6B: payments and paid-through control.
--
-- Closes two gaps left by the 6A foundation, then adds the one function 6B needs beyond the
-- existing single command seam:
--   1. original_confirmation_id pointed at the legacy organization_payment_confirmations table.
--      Nothing populated it yet, so repointing it at organization_commercial_events (the actual
--      immutable ledger going forward) is a clean schema change, not a data migration.
--   2. provision_organization_from_application wrote initial payment straight into the legacy
--      organization_billing_accounts / organization_payment_confirmations tables, bypassing the
--      commercial-command seam entirely. Every organization provisioned after 6A shipped and
--      before this migration has no commercial-event history as a result -- that interim window
--      needs manual reconciliation, tracked in the Part 6B packet, not fixed by this migration.
--   3. apply_organization_late_renewal_reactivation: the only 6B action that touches more than
--      the commercial seam. It records a renewal event and, only when explicitly requested,
--      reactivates a suspended organization in the same transaction -- distinct chained records,
--      one atomic write.

-- ---------------------------------------------------------------------------
-- Repoint original_confirmation_id at the commercial-events ledger
-- ---------------------------------------------------------------------------

alter table public.organization_commercial_events
  drop constraint organization_commercial_events_original_confirmation_id_fkey;

alter table public.organization_commercial_events
  add constraint organization_commercial_events_original_confirmation_id_fkey
  foreign key (original_confirmation_id) references public.organization_commercial_events(id);

alter table public.organization_commercial_events
  add constraint organization_commercial_events_self_confirmation_check
  check (original_confirmation_id <> id);

create or replace function private.validate_organization_commercial_event()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.occurred_at > now() then
    raise exception 'Commercial events cannot be dated in the future.'
      using errcode = 'check_violation';
  end if;

  if new.original_confirmation_id is not null and not exists (
    select 1
    from public.organization_commercial_events as origin
    where origin.id = new.original_confirmation_id
      and origin.organization_id = new.organization_id
      and origin.event_kind in ('initial_payment_confirmed', 'renewal_confirmed')
  ) then
    raise exception 'A commercial adjustment must reference an initial-payment or renewal event for the same organization.'
      using errcode = 'check_violation';
  end if;

  if new.source_event_id is not null and not exists (
    select 1
    from public.organization_commercial_events as source
    where source.id = new.source_event_id
      and source.organization_id = new.organization_id
  ) then
    raise exception 'A commercial event must reference a source event for the same organization.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_organization_commercial_event() from public;

-- ---------------------------------------------------------------------------
-- Provisioning now writes through the commercial-command seam
-- ---------------------------------------------------------------------------

-- Redefines the version from 20260813180000_onboarding_payment_reversal.sql: the two direct
-- inserts into the legacy billing tables are replaced with one apply_organization_commercial_command
-- call, and the organization_settings timezone update moves earlier so the commercial-timezone
-- baseline import (inside the command call) picks up the real operational timezone instead of the
-- table default.
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

  update public.organization_settings
  set timezone = coalesce(nullif(trim(app_time_zone), ''), timezone)
  where organization_id = target_organization_id;

  perform public.apply_organization_commercial_command(
    target_organization_id => target_organization_id,
    event_kind => 'initial_payment_confirmed',
    idempotency_key => 'application:' || target_application_id::text || ':initial_payment',
    summary => 'Initial payment confirmed during provisioning.',
    paid_through_effect => 'set',
    paid_through_date => paid_through,
    actor_owner_email => target_actor_owner_email,
    occurred_at => payment.confirmed_at,
    private_reason => payment.mismatch_reason,
    private_reference => payment.private_reference,
    amount_usd_cents => payment.amount_usd_cents,
    safe_kind => 'payment_recorded',
    safe_payload => jsonb_build_object('paid_through_date', paid_through)
  );

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

revoke all on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.provision_organization_from_application(uuid, uuid, text, text, uuid, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Late renewal with optional, explicit reactivation
-- ---------------------------------------------------------------------------

-- A plain renewal never touches lifecycle_status. reactivate must be true and the organization
-- must currently be suspended, or the whole call fails and nothing is written -- there is no
-- partial state where a renewal is recorded but reactivation silently didn't happen.
create or replace function public.apply_organization_late_renewal_reactivation(
  target_organization_id uuid,
  idempotency_key text,
  summary text,
  paid_through_effect text,
  paid_through_date date default null,
  actor_owner_email text default null,
  occurred_at timestamptz default now(),
  private_reason text default null,
  private_reference text default null,
  amount_usd_cents integer default null,
  original_confirmation_id uuid default null,
  reactivate boolean default false,
  safe_kind text default null,
  safe_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_lifecycle_status text;
  renewal_result jsonb;
  renewal_event_id uuid;
  reactivation_result jsonb;
begin
  if reactivate and (actor_owner_email is null or char_length(trim(actor_owner_email)) = 0) then
    raise exception 'An acting owner email is required to reactivate an organization.'
      using errcode = 'check_violation';
  end if;

  if reactivate then
    select lifecycle_status into current_lifecycle_status
    from public.organizations
    where id = target_organization_id
    for update;

    if current_lifecycle_status is null then
      raise exception 'Organization % was not found.', target_organization_id
        using errcode = 'foreign_key_violation';
    end if;

    if current_lifecycle_status <> 'suspended' then
      raise exception 'Only a suspended organization can be reactivated.'
        using errcode = 'check_violation';
    end if;
  end if;

  renewal_result := public.apply_organization_commercial_command(
    target_organization_id => target_organization_id,
    event_kind => 'renewal_confirmed',
    idempotency_key => idempotency_key,
    summary => summary,
    paid_through_effect => paid_through_effect,
    paid_through_date => paid_through_date,
    actor_owner_email => actor_owner_email,
    occurred_at => occurred_at,
    private_reason => private_reason,
    private_reference => private_reference,
    amount_usd_cents => amount_usd_cents,
    original_confirmation_id => original_confirmation_id,
    safe_kind => safe_kind,
    safe_payload => safe_payload
  );

  -- Not requested, or an idempotent replay of an already-applied renewal: reactivation (if any)
  -- already happened on the original call. Never reactivate on a retry.
  if not reactivate or (renewal_result ->> 'applied') <> 'true' then
    return renewal_result || jsonb_build_object('reactivated', false);
  end if;

  renewal_event_id := (renewal_result ->> 'event_id')::uuid;

  update public.organizations
  set lifecycle_status = 'active', updated_at = now()
  where id = target_organization_id;

  reactivation_result := public.apply_organization_commercial_command(
    target_organization_id => target_organization_id,
    event_kind => 'organization_reactivated',
    idempotency_key => idempotency_key || ':reactivation',
    summary => 'Organization reactivated after late renewal.',
    paid_through_effect => 'unchanged',
    actor_owner_email => actor_owner_email,
    occurred_at => occurred_at,
    private_reason => coalesce(private_reason, 'Reactivated after late renewal.'),
    source_event_id => renewal_event_id,
    safe_kind => 'account_reactivated'
  );

  insert into public.access_audit_events (
    organization_id, actor_kind, actor_owner_email, event_type, target_type, target_key,
    before_state, after_state
  ) values (
    target_organization_id, 'platform_owner', actor_owner_email, 'organization.lifecycle_changed',
    'organization.lifecycle_status', target_organization_id::text,
    jsonb_build_object('lifecycle_status', 'suspended'),
    jsonb_build_object('lifecycle_status', 'active')
  );

  return renewal_result || jsonb_build_object(
    'reactivated', true,
    'reactivation_event_id', reactivation_result ->> 'event_id'
  );
end;
$$;

revoke all on function public.apply_organization_late_renewal_reactivation(
  uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb
) from public, anon, authenticated;

grant execute on function public.apply_organization_late_renewal_reactivation(
  uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb
) to service_role;

comment on function public.apply_organization_late_renewal_reactivation(
  uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb
) is
  'Records a renewal commercial event and, only when explicitly requested, reactivates a suspended organization in the same transaction as a distinct chained event.';
