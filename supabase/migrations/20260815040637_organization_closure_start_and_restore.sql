-- Part 9: recoverable closure and strict purge -- closure start and restore command seam.
--
-- Mirrors the apply_organization_lifecycle_change (6D) pattern exactly: per-org row lock via
-- organization_commercial_state, idempotency dedup against organization_commercial_events, and one
-- atomic write across the private event, the current projection, and the contractor-safe event.

create or replace function public.apply_organization_closure_start(
  target_organization_id uuid,
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
  inserted_closure_record public.organization_closure_records%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  target_deadline_at timestamptz;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A private reason is required to start closure.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'Closure cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_closure_start.idempotency_key;
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

  if organization_row.lifecycle_status not in ('active', 'suspended') then
    raise exception 'Only an active or suspended organization can start closure.'
      using errcode = 'check_violation';
  end if;

  target_deadline_at := command_time + interval '30 days';

  insert into public.organization_closure_records (
    organization_id, reason, prior_lifecycle_status, started_at, started_by_owner_email, deadline_at
  ) values (
    target_organization_id, trim(private_reason), organization_row.lifecycle_status, command_time,
    trim(actor_owner_email), target_deadline_at
  ) returning * into inserted_closure_record;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, 'organization_closure_started', command_time, trim(actor_owner_email),
    'Organization closure started.', trim(private_reason),
    'unchanged', current_state.paid_through_date, current_state.paid_through_date, current_state.grace_ends_at,
    jsonb_build_object('lifecycle_status', organization_row.lifecycle_status),
    jsonb_build_object('lifecycle_status', 'pending_closure', 'closure_record_id', inserted_closure_record.id,
      'deadline_at', target_deadline_at),
    idempotency_key
  ) returning * into inserted_event;

  update public.organizations
  set lifecycle_status = 'pending_closure', updated_at = now()
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
    target_organization_id, inserted_event.id, 'closure_started',
    jsonb_build_object('access_status', 'pending_closure', 'closure_deadline_at', target_deadline_at),
    command_time
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id,
    'closure_record_id', inserted_closure_record.id, 'deadline_at', target_deadline_at);
end;
$$;

revoke all on function public.apply_organization_closure_start(
  uuid, text, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.apply_organization_closure_start(
  uuid, text, text, text, timestamptz
) to service_role;

comment on function public.apply_organization_closure_start(
  uuid, text, text, text, timestamptz
) is 'Starts a 30-day recoverable closure window: blocks the organization, opens a closure record, and records immutable reasoned history.';

create or replace function public.apply_organization_closure_restore(
  target_organization_id uuid,
  idempotency_key text,
  restoration_evidence_note text,
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
  open_closure_record public.organization_closure_records%rowtype;
  inserted_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(restoration_evidence_note, ''))) not between 1 and 1000 then
    raise exception 'A safe evidence note is required to restore an organization.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'Restoration cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_closure_restore.idempotency_key;
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

  if organization_row.lifecycle_status <> 'pending_closure' then
    raise exception 'Only a closing organization can be restored.' using errcode = 'check_violation';
  end if;

  select * into open_closure_record
  from public.organization_closure_records
  where organization_id = target_organization_id
    and status = 'pending_closure'
  for update;
  if not found then
    raise exception 'No open closure window was found for this organization.'
      using errcode = 'check_violation';
  end if;

  update public.organization_closure_records
  set status = 'restored',
      restored_at = command_time,
      restored_by_owner_email = trim(actor_owner_email),
      restoration_evidence_note = trim(restoration_evidence_note)
  where id = open_closure_record.id;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, 'organization_closure_restored', command_time, trim(actor_owner_email),
    'Organization closure restored.', trim(restoration_evidence_note),
    'unchanged', current_state.paid_through_date, current_state.paid_through_date, current_state.grace_ends_at,
    jsonb_build_object('lifecycle_status', 'pending_closure'),
    jsonb_build_object('lifecycle_status', open_closure_record.prior_lifecycle_status,
      'closure_record_id', open_closure_record.id),
    idempotency_key
  ) returning * into inserted_event;

  update public.organizations
  set lifecycle_status = open_closure_record.prior_lifecycle_status, updated_at = now()
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
    target_organization_id, inserted_event.id, 'closure_restored',
    jsonb_build_object('access_status', open_closure_record.prior_lifecycle_status),
    command_time
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id,
    'lifecycle_status', open_closure_record.prior_lifecycle_status);
end;
$$;

revoke all on function public.apply_organization_closure_restore(
  uuid, text, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.apply_organization_closure_restore(
  uuid, text, text, text, timestamptz
) to service_role;

comment on function public.apply_organization_closure_restore(
  uuid, text, text, text, timestamptz
) is 'Restores an organization from an open closure window back to its prior lifecycle status, and records immutable reasoned history.';
