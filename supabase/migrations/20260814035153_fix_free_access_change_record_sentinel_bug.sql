-- Follow-up fix: testing a `record`-typed variable with IS [NOT] NULL as a "was this assigned"
-- sentinel across separate branches proved unreliable for the folded free-access grant state
-- (confirmed by direct testing: it silently misclassified an already-scheduled future grant as
-- absent, allowing an overlapping second future grant to be created). Replace the three sentinel
-- records with explicit boolean flags plus plain scalar fields, which is reliable.

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
  root_row record;
  has_active_grant boolean := false;
  active_until date;
  has_future_grant boolean := false;
  future_starts_at date;
  future_until date;
  has_acted_grant boolean := false;
  acted_root_id uuid;
  acted_starts_at date;
  acted_package_version_id uuid;
  acted_until date;
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
      has_active_grant := true;
      active_until := root_row.access_until_date;
    elsif root_row.starts_at > command_date then
      has_future_grant := true;
      future_starts_at := root_row.starts_at;
      future_until := root_row.access_until_date;
    end if;
    if target_grant_id is not null and root_row.root_id = target_grant_id then
      has_acted_grant := true;
      acted_root_id := root_row.root_id;
      acted_starts_at := root_row.starts_at;
      acted_package_version_id := root_row.package_version_id;
      acted_until := root_row.access_until_date;
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
      if has_active_grant then
        raise exception 'An active free access grant already exists. Extend it instead of granting a new one.'
          using errcode = 'check_violation';
      end if;
      if has_future_grant then
        if target_access_until_date is null or future_starts_at <= target_access_until_date then
          raise exception 'The new grant would overlap the already scheduled future grant.'
            using errcode = 'check_violation';
        end if;
      end if;
    else
      if has_future_grant then
        raise exception 'A future free access grant is already scheduled. End it before scheduling another.'
          using errcode = 'check_violation';
      end if;
      if has_active_grant then
        if active_until is null or target_starts_at <= active_until then
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
    if not has_acted_grant then
      raise exception 'The referenced free access grant is not currently active or scheduled.'
        using errcode = 'check_violation';
    end if;
    if target_action = 'extend'
       and acted_until is not null
       and target_access_until_date <= acted_until then
      raise exception 'The new end date must be later than the current end date.' using errcode = 'check_violation';
    end if;
    if target_action = 'extend' and target_access_until_date <= command_date then
      raise exception 'The new end date must be later than today.' using errcode = 'check_violation';
    end if;

    effective_root_id := acted_root_id;
    effective_starts_at := acted_starts_at;
    effective_package_version_id := acted_package_version_id;
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
