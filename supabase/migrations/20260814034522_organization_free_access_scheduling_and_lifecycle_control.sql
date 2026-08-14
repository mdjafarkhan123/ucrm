-- Part 6D: scheduled free access and categorized, eligibility-checked lifecycle control.
--
-- Free access gains a durable business start date and grant identity, so a currently active grant
-- and one non-overlapping future grant can coexist. Lifecycle suspension/reactivation moves onto the
-- shared commercial command seam that 6A already allowlisted event/safe kinds and the
-- suspension_category column for.

-- ---------------------------------------------------------------------------
-- Free access: grant identity and business start date
-- ---------------------------------------------------------------------------

alter table public.organization_free_access_events
  add column starts_at date,
  add column target_grant_id uuid references public.organization_free_access_events(id);

update public.organization_free_access_events
set starts_at = occurred_at::date
where starts_at is null;

alter table public.organization_free_access_events
  alter column starts_at set not null;

alter table public.organization_free_access_events
  add constraint organization_free_access_events_target_grant_check check (
    (action = 'grant') = (target_grant_id is null)
  ),
  add constraint organization_free_access_events_self_target_check check (
    target_grant_id is null or target_grant_id <> id
  );

create index organization_free_access_events_root_idx
  on public.organization_free_access_events (
    organization_id, (coalesce(target_grant_id, id)), occurred_at desc, id desc
  );

-- Extend structural validation: a continuation action must reference a root grant event
-- (target_grant_id is null on the referenced row) for the same organization.
create or replace function private.validate_organization_free_access_event()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  package_assignment_exists boolean;
  target_is_root boolean;
begin
  if new.occurred_at > now() then
    raise exception 'Free access events cannot be dated in the future.'
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1
    from public.organization_package_assignments as assignment
    where assignment.organization_id = new.organization_id
      and assignment.package_version_id = new.package_version_id
  )
  into package_assignment_exists;

  if not package_assignment_exists then
    raise exception 'Free access must use a package version assigned to the organization.'
      using errcode = 'check_violation';
  end if;

  if new.target_grant_id is not null then
    select exists (
      select 1
      from public.organization_free_access_events as root
      where root.id = new.target_grant_id
        and root.organization_id = new.organization_id
        and root.target_grant_id is null
    )
    into target_is_root;

    if not target_is_root then
      raise exception 'The referenced free access grant was not found for this organization.'
        using errcode = 'foreign_key_violation';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Require a reason for free access events at the schema level too (defense in depth,
-- matching how 6C already requires it for lifecycle and other reasoned events).
-- ---------------------------------------------------------------------------

alter table public.organization_commercial_events
  drop constraint if exists organization_commercial_events_reason_check;

alter table public.organization_commercial_events
  add constraint organization_commercial_events_reason_check check (
    is_legacy_import
    or event_kind not in (
      'organization_suspended',
      'organization_reactivated',
      'paid_through_adjusted',
      'refund_recorded',
      'payment_reversal_recorded',
      'payment_correction_recorded',
      'commercial_timezone_changed',
      'pending_setup_resolved',
      'package_version_changed',
      'feature_exception_changed',
      'limit_exception_changed',
      'free_access_granted',
      'free_access_extended',
      'free_access_converted_forever',
      'free_access_ended'
    )
    or char_length(trim(coalesce(private_reason, ''))) > 0
  );

-- ---------------------------------------------------------------------------
-- Free access command seam
-- ---------------------------------------------------------------------------

create or replace function public.apply_organization_free_access_change(
  target_organization_id uuid,
  target_action text,
  target_grant_id uuid,
  target_starts_at date,
  target_access_until_date date,
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
  inserted_grant_event public.organization_free_access_events%rowtype;
  inserted_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  command_date date;
  current_package_version_id uuid;
  active_root record;
  future_root record;
  acted_root record;
  root_row record;
  effective_root_id uuid;
  effective_starts_at date;
  effective_package_version_id uuid;
  effective_until date;
  event_kind_value text;
  safe_kind_value text := 'free_access_updated';
  safe_status text;
begin
  if target_action not in ('grant', 'extend', 'convert_to_forever', 'end') then
    raise exception 'The free access action is invalid.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 500 then
    raise exception 'A private reason is required for a free access change.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'Free access changes cannot be dated in the future.' using errcode = 'check_violation';
  end if;
  command_date := command_time::date;

  if target_action = 'grant' then
    if target_grant_id is not null then
      raise exception 'A new grant cannot reference an existing grant.' using errcode = 'check_violation';
    end if;
    if target_starts_at is null or target_starts_at < command_date then
      raise exception 'A free access grant needs a start date that is today or later.' using errcode = 'check_violation';
    end if;
  else
    if target_grant_id is null then
      raise exception 'This action must reference the grant it changes.' using errcode = 'check_violation';
    end if;
    if target_starts_at is not null then
      raise exception 'Only a new grant can set a start date.' using errcode = 'check_violation';
    end if;
  end if;

  if target_action in ('convert_to_forever', 'end') and target_access_until_date is not null then
    raise exception 'This action cannot include an end date.' using errcode = 'check_violation';
  end if;
  if target_action = 'extend' and target_access_until_date is null then
    raise exception 'An extension needs a new end date.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_free_access_change.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'change_after', existing_event.change_after);
  end if;

  -- Fold every non-ended grant chain for this organization to its latest state.
  for root_row in
    select grant_row.id as root_id, grant_row.starts_at, grant_row.package_version_id,
           latest.action, latest.access_until_date
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
  loop
    if root_row.starts_at <= command_date
       and (root_row.access_until_date is null or root_row.access_until_date >= command_date) then
      active_root := root_row;
    elsif root_row.starts_at > command_date then
      future_root := root_row;
    end if;
    if target_grant_id is not null and root_row.root_id = target_grant_id then
      acted_root := root_row;
    end if;
  end loop;

  if target_action = 'grant' then
    select assignment.package_version_id into current_package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = target_organization_id
    order by assignment.effective_at desc, assignment.id desc
    limit 1;
    if current_package_version_id is null then
      raise exception 'Assign a published package version before granting free access.' using errcode = 'check_violation';
    end if;

    if target_starts_at <= command_date then
      if active_root is not null then
        raise exception 'An active free access grant already exists. Extend it instead of granting a new one.'
          using errcode = 'check_violation';
      end if;
      if future_root is not null then
        if target_access_until_date is null or future_root.starts_at <= target_access_until_date then
          raise exception 'The new grant would overlap the already scheduled future grant.'
            using errcode = 'check_violation';
        end if;
      end if;
    else
      if future_root is not null then
        raise exception 'A future free access grant is already scheduled. End it before scheduling another.'
          using errcode = 'check_violation';
      end if;
      if active_root is not null then
        if active_root.access_until_date is null or target_starts_at <= active_root.access_until_date then
          raise exception 'The scheduled grant would overlap the currently active grant.'
            using errcode = 'check_violation';
        end if;
      end if;
    end if;

    effective_root_id := null;
    effective_starts_at := target_starts_at;
    effective_package_version_id := current_package_version_id;
    effective_until := target_access_until_date;
    event_kind_value := 'free_access_granted';
  else
    if acted_root is null then
      raise exception 'The referenced free access grant is not currently active or scheduled.'
        using errcode = 'check_violation';
    end if;
    if target_action = 'extend'
       and acted_root.access_until_date is not null
       and target_access_until_date <= acted_root.access_until_date then
      raise exception 'The new end date must be later than the current end date.' using errcode = 'check_violation';
    end if;
    if target_action = 'extend' and target_access_until_date <= command_date then
      raise exception 'The new end date must be later than today.' using errcode = 'check_violation';
    end if;

    effective_root_id := acted_root.root_id;
    effective_starts_at := acted_root.starts_at;
    effective_package_version_id := acted_root.package_version_id;
    effective_until := case when target_action = 'extend' then target_access_until_date else null end;
    event_kind_value := case target_action
      when 'extend' then 'free_access_extended'
      when 'convert_to_forever' then 'free_access_converted_forever'
      else 'free_access_ended'
    end;
  end if;

  insert into public.organization_free_access_events (
    organization_id, package_version_id, action, access_until_date, starts_at, target_grant_id,
    reason, actor_owner_email, occurred_at
  ) values (
    target_organization_id, effective_package_version_id, target_action, effective_until,
    effective_starts_at, effective_root_id, trim(private_reason), trim(actor_owner_email), command_time
  ) returning * into inserted_grant_event;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, event_kind_value, command_time, trim(actor_owner_email),
    'Free access changed.', trim(private_reason), 'unchanged', current_state.paid_through_date,
    current_state.paid_through_date, current_state.grace_ends_at,
    coalesce(jsonb_build_object('grant_id', target_grant_id), '{}'::jsonb),
    jsonb_build_object('grant_id', coalesce(effective_root_id, inserted_grant_event.id), 'action', target_action,
      'starts_at', effective_starts_at, 'access_until_date', effective_until),
    idempotency_key
  ) returning * into inserted_event;

  update public.organization_commercial_state
  set last_event_id = inserted_event.id,
      state_version = current_state.state_version + 1
  where organization_id = target_organization_id
    and state_version = current_state.state_version;
  if not found then
    raise exception 'The commercial state changed during this command. Retry the command.'
      using errcode = 'serialization_failure';
  end if;

  safe_status := case
    when target_action = 'end' then 'ended'
    when effective_until is null then 'forever'
    else 'until_date'
  end;

  insert into public.organization_safe_events (
    organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at
  ) values (
    target_organization_id, inserted_event.id, safe_kind_value,
    jsonb_build_object('access_status', safe_status, 'free_access_until_date', effective_until,
      'effective_at', effective_starts_at),
    command_time
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id,
    'grant_id', coalesce(effective_root_id, inserted_grant_event.id),
    'starts_at', effective_starts_at, 'access_until_date', effective_until);
end;
$$;

revoke all on function public.apply_organization_free_access_change(
  uuid, text, uuid, date, date, text, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.apply_organization_free_access_change(
  uuid, text, uuid, date, date, text, text, text, timestamptz
) to service_role;

comment on function public.apply_organization_free_access_change(
  uuid, text, uuid, date, date, text, text, text, timestamptz
) is 'Atomically applies one free access command, enforcing at most one active and one non-overlapping future grant, and records immutable reasoned history.';

-- ---------------------------------------------------------------------------
-- Lifecycle command seam
-- ---------------------------------------------------------------------------

create or replace function public.apply_organization_lifecycle_change(
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
  command_date date;
  last_suspension public.organization_commercial_events%rowtype;
  commercial_timezone text;
  is_eligible boolean;
  active_owner_count integer;
begin
  if target_status not in ('active', 'suspended') then
    raise exception 'The organization status is invalid.' using errcode = 'check_violation';
  end if;
  if target_status = 'suspended'
     and coalesce(target_suspension_category, '') not in ('nonpayment', 'payment_dispute', 'security', 'support', 'other') then
    raise exception 'A suspension requires a valid category.' using errcode = 'check_violation';
  end if;
  if target_status = 'active' and target_suspension_category is not null then
    raise exception 'Reactivation cannot include a suspension category.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A private reason is required for a lifecycle change.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'Lifecycle changes cannot be dated in the future.' using errcode = 'check_violation';
  end if;
  command_date := command_time::date;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_lifecycle_change.idempotency_key;
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

  if organization_row.lifecycle_status = target_status then
    raise exception 'The organization already has this status.' using errcode = 'check_violation';
  end if;
  if organization_row.lifecycle_status = 'pending_setup' then
    raise exception 'Legacy pending organizations must be reviewed before a lifecycle change.'
      using errcode = 'check_violation';
  end if;

  if target_status = 'active' then
    select count(*) into active_owner_count
    from public.organization_members
    where organization_id = target_organization_id and role = 'owner';
    if active_owner_count = 0 then
      raise exception 'Invite the first administrator before activation.' using errcode = 'check_violation';
    end if;

    select * into last_suspension
    from public.organization_commercial_events
    where organization_id = target_organization_id
      and event_kind = 'organization_suspended'
    order by organization_commercial_events.occurred_at desc, organization_commercial_events.id desc
    limit 1;

    if found and last_suspension.suspension_category in ('nonpayment', 'payment_dispute') then
      select commercial.commercial_timezone into commercial_timezone
      from public.organization_commercial_settings as commercial
      where commercial.organization_id = target_organization_id;

      is_eligible := current_state.paid_through_date is not null
        and (
          current_state.paid_through_date >= (now() at time zone coalesce(commercial_timezone, 'UTC'))::date
          or (current_state.grace_ends_at is not null and current_state.grace_ends_at >= now())
        );

      if not is_eligible then
        is_eligible := exists (
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
            and grant_row.starts_at <= command_date
            and (latest.access_until_date is null or latest.access_until_date >= command_date)
        );
      end if;

      if not is_eligible then
        raise exception 'Restore paid-through eligibility or active free access before reactivating.'
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    suspension_category, paid_through_effect, paid_through_before, paid_through_after,
    grace_ends_at_after, change_before, change_after, idempotency_key
  ) values (
    target_organization_id,
    case when target_status = 'suspended' then 'organization_suspended' else 'organization_reactivated' end,
    command_time, trim(actor_owner_email),
    case when target_status = 'suspended' then 'Organization suspended.' else 'Organization reactivated.' end,
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

revoke all on function public.apply_organization_lifecycle_change(
  uuid, text, text, text, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.apply_organization_lifecycle_change(
  uuid, text, text, text, text, text, timestamptz
) to service_role;

comment on function public.apply_organization_lifecycle_change(
  uuid, text, text, text, text, text, timestamptz
) is 'Atomically applies one categorized suspend/reactivate command with eligibility-checked reactivation, and records immutable reasoned history.';
