-- Part 6E: legacy pending_setup organization reconciliation.
--
-- New paid organizations never use pending_setup; only rows that predate the versioned onboarding
-- flow do. This is a one-time review queue: each legacy row is deliberately converted to active or
-- suspended with a reason, never assumed in bulk. The 6A foundation migration already allowlisted
-- the 'pending_setup_resolved' event kind and exempted it from the legacy-import-only reasonless
-- path, anticipating this part.
--
-- Two functions:
--   organization_legacy_readiness             -- read-only checklist for the review screen
--   apply_organization_pending_setup_reconciliation -- the one-time transition itself

-- ---------------------------------------------------------------------------
-- Read-only readiness checklist
-- ---------------------------------------------------------------------------

create or replace function public.organization_legacy_readiness(target_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  package_assigned boolean;
  administrator_exists boolean;
  administrator_login_ready boolean;
  paid_through_eligible boolean;
  free_access_active boolean;
  commercial_timezone text;
  today_date date;
begin
  perform private.ensure_organization_commercial_rows(target_organization_id);

  select exists (
    select 1 from public.organization_package_assignments
    where organization_id = target_organization_id
  ) into package_assigned;

  select exists (
    select 1 from public.organization_members
    where organization_id = target_organization_id and role in ('owner', 'admin')
  ) into administrator_exists;

  select exists (
    select 1
    from public.organization_members as member
    join auth.users as owner_user on owner_user.id = member.user_id
    where member.organization_id = target_organization_id
      and member.role in ('owner', 'admin')
      and owner_user.encrypted_password is not null
  ) into administrator_login_ready;

  select commercial.commercial_timezone into commercial_timezone
  from public.organization_commercial_settings as commercial
  where commercial.organization_id = target_organization_id;

  today_date := (now() at time zone coalesce(commercial_timezone, 'UTC'))::date;

  select (
    state.paid_through_date is not null
    and (
      state.paid_through_date >= today_date
      or (state.grace_ends_at is not null and state.grace_ends_at >= now())
    )
  ) into paid_through_eligible
  from public.organization_commercial_state as state
  where state.organization_id = target_organization_id;

  select exists (
    select 1
    from public.organization_free_access_events as grant_row
    join lateral (
      select event.action, event.access_until_date
      from public.organization_free_access_events as event
      where event.organization_id = target_organization_id
        and coalesce(event.target_grant_id, event.id) = grant_row.id
      order by event.occurred_at desc, event.id desc
      limit 1
    ) as latest on true
    where grant_row.organization_id = target_organization_id
      and grant_row.target_grant_id is null
      and latest.action <> 'end'
      and grant_row.starts_at <= today_date
      and (latest.access_until_date is null or latest.access_until_date >= today_date)
  ) into free_access_active;

  return jsonb_build_object(
    'package_assigned', coalesce(package_assigned, false),
    'administrator_exists', coalesce(administrator_exists, false),
    'administrator_login_ready', coalesce(administrator_login_ready, false),
    'paid_through_eligible', coalesce(paid_through_eligible, false),
    'free_access_active', coalesce(free_access_active, false)
  );
end;
$$;

revoke all on function public.organization_legacy_readiness(uuid) from public, anon, authenticated;
grant execute on function public.organization_legacy_readiness(uuid) to service_role;

comment on function public.organization_legacy_readiness(uuid) is
  'Read-only checklist (package assignment, administrator, login readiness, paid-through/free-access eligibility) backing the legacy pending_setup review screen.';

-- ---------------------------------------------------------------------------
-- The one-time reconciliation command
-- ---------------------------------------------------------------------------

create or replace function public.apply_organization_pending_setup_reconciliation(
  target_organization_id uuid,
  target_status text,
  target_suspension_category text,
  idempotency_key text,
  private_reason text,
  actor_owner_email text,
  occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_state public.organization_commercial_state%rowtype;
  existing_event public.organization_commercial_events%rowtype;
  organization_row public.organizations%rowtype;
  inserted_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  readiness jsonb;
begin
  if target_status not in ('active', 'suspended') then
    raise exception 'The organization status is invalid.' using errcode = 'check_violation';
  end if;
  if target_status = 'suspended'
     and coalesce(target_suspension_category, '') not in ('nonpayment', 'payment_dispute', 'security', 'support', 'other') then
    raise exception 'A suspension requires a valid category.' using errcode = 'check_violation';
  end if;
  if target_status = 'active' and target_suspension_category is not null then
    raise exception 'Activation cannot include a suspension category.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A reconciliation reason is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'A reconciliation cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_pending_setup_reconciliation.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'change_after', existing_event.change_after);
  end if;

  select * into organization_row
  from public.organizations
  where id = target_organization_id
  for update;
  if not found then
    raise exception 'Organization was not found.' using errcode = 'foreign_key_violation';
  end if;

  if organization_row.lifecycle_status <> 'pending_setup' then
    raise exception 'Only a legacy pending organization can be reconciled here.'
      using errcode = 'check_violation';
  end if;

  if target_status = 'active' then
    readiness := public.organization_legacy_readiness(target_organization_id);

    if not (readiness ->> 'package_assigned')::boolean then
      raise exception 'Assign a published package version before activating.' using errcode = 'check_violation';
    end if;
    if not (readiness ->> 'administrator_exists')::boolean then
      raise exception 'This organization needs an owner or admin before activating.' using errcode = 'check_violation';
    end if;
    if not (readiness ->> 'administrator_login_ready')::boolean then
      raise exception 'The administrator has not completed login setup yet.' using errcode = 'check_violation';
    end if;
    if not (
      (readiness ->> 'paid_through_eligible')::boolean
      or (readiness ->> 'free_access_active')::boolean
    ) then
      raise exception 'Record a paid-through date or active free access before activating.'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    suspension_category, paid_through_effect, paid_through_before, paid_through_after,
    grace_ends_at_after, change_before, change_after, idempotency_key
  ) values (
    target_organization_id,
    'pending_setup_resolved',
    command_time, trim(actor_owner_email),
    case when target_status = 'suspended'
      then 'Legacy organization reviewed and suspended.'
      else 'Legacy organization reviewed and activated.'
    end,
    trim(private_reason),
    case when target_status = 'suspended' then target_suspension_category else null end,
    'unchanged', current_state.paid_through_date, current_state.paid_through_date, current_state.grace_ends_at,
    jsonb_build_object('lifecycle_status', organization_row.lifecycle_status),
    jsonb_build_object('lifecycle_status', target_status),
    idempotency_key
  ) returning * into inserted_event;

  update public.organizations
  set lifecycle_status = target_status, updated_at = now()
  where id = target_organization_id;

  update public.organization_commercial_state
  set last_event_id = inserted_event.id,
      state_version = current_state.state_version + 1
  where organization_id = target_organization_id
    and state_version = current_state.state_version;
  if not found then
    raise exception 'The commercial state changed during this command. Retry the command.'
      using errcode = 'serialization_failure';
  end if;

  insert into public.organization_safe_events (
    organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at
  ) values (
    target_organization_id, inserted_event.id,
    case when target_status = 'suspended' then 'account_suspended' else 'account_reactivated' end,
    jsonb_build_object('access_status', target_status),
    command_time
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'lifecycle_status', target_status);
end;
$$;

revoke all on function public.apply_organization_pending_setup_reconciliation(
  uuid, text, text, text, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.apply_organization_pending_setup_reconciliation(
  uuid, text, text, text, text, text, timestamptz
) to service_role;

comment on function public.apply_organization_pending_setup_reconciliation(
  uuid, text, text, text, text, text, timestamptz
) is
  'One-time transition of a legacy pending_setup organization to active or suspended. Activation requires the readiness checklist to pass; suspension only requires a category and reason. Distinct from apply_organization_lifecycle_change, which refuses pending_setup organizations.';
