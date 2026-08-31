-- Contractor Settings, Part 2B follow-up: the stale-revision conflict code that made a refused save hang
-- forever, everywhere else in the app that used it.
--
-- Found while browser-verifying Price Book (Part 2B): saving a stale-revision edit never returned a
-- response. Root cause, confirmed with an isolated PostgREST probe (a throwaway function that only raises
-- SQLSTATE 40001, no permission check, no row lock, called directly with the anon key): the call never
-- answers, 0 bytes, timing out past 15s. The same probe raising a plain exception with no errcode answers
-- in ~0.2s with a normal 400. 40001 is Postgres' own serialization_failure -- the standard signal for
-- "two transactions collided, retry the whole transaction" -- and PostgREST reads it exactly that way.
-- These conflicts are not transient: a stale revision stays stale, an invalid lease stays invalid, so the
-- retry raises the same 40001 again, forever. Reproduced live against Price Book: one stale save produced
-- 75,000+ identical raises against the database in under 90 seconds, and the browser tab never got a
-- response at all.
--
-- This same bug, and this same fix (SQLSTATE P0409, a code of our own that nothing retries), already
-- shipped once for Quotes (20260820150000_quotes_conflict_code_is_not_a_retry_signal.sql) and once for
-- Team member details (20260902091400_team_member_profile_conflict_is_not_retryable.sql). Every other
-- revision-protected command in the app was still on 40001 -- Price Book and Taxes (both Settings), the
-- Jafar commercial-control suite (closure, free access, lifecycle, limits, features, package, pending-setup
-- reconciliation, commercial command), team role/permission changes, and the invitation cleanup/reconciliation
-- worker. This migration moves all of them to P0409. Nothing else in any of these functions changes --
-- confirmed by diffing against pg_get_functiondef() for each function before this migration was written.
-- The matching API error mappers are updated in the same change so each stale/invalid-lease response keeps
-- returning its existing 409, just keyed off P0409 instead of 40001.

CREATE OR REPLACE FUNCTION public.apply_organization_closure_restore(target_organization_id uuid, idempotency_key text, restoration_evidence_note text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
      restoration_evidence_note = trim(apply_organization_closure_restore.restoration_evidence_note)
  where id = open_closure_record.id;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, 'organization_closure_restored', command_time, trim(actor_owner_email),
    'Organization closure restored.', trim(apply_organization_closure_restore.restoration_evidence_note),
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
      using errcode = 'P0409';
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
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_closure_start(target_organization_id uuid, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
      using errcode = 'P0409';
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
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_commercial_command(target_organization_id uuid, event_kind text, idempotency_key text, summary text, paid_through_effect text, paid_through_date date DEFAULT NULL::date, actor_owner_email text DEFAULT NULL::text, occurred_at timestamp with time zone DEFAULT now(), private_reason text DEFAULT NULL::text, private_reference text DEFAULT NULL::text, amount_usd_cents integer DEFAULT NULL::integer, original_confirmation_id uuid DEFAULT NULL::uuid, source_event_id uuid DEFAULT NULL::uuid, suspension_category text DEFAULT NULL::text, commercial_timezone text DEFAULT NULL::text, recalculate_deadline boolean DEFAULT false, is_legacy_import boolean DEFAULT false, safe_kind text DEFAULT NULL::text, safe_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_state public.organization_commercial_state%rowtype;
  current_settings public.organization_commercial_settings%rowtype;
  existing_event public.organization_commercial_events%rowtype;
  next_paid_through date;
  next_paid_through_source text;
  next_timezone text;
  next_grace_ends_at timestamptz;
  next_grace_timezone text;
  inserted_event public.organization_commercial_events%rowtype;
begin
  if paid_through_effect not in ('set', 'unchanged') then
    raise exception 'The paid-through effect must be confirmed as set or unchanged.'
      using errcode = 'check_violation';
  end if;

  if paid_through_effect = 'set' and paid_through_date is null then
    raise exception 'A confirmed paid-through change requires the resulting paid-through date.'
      using errcode = 'check_violation';
  end if;

  if event_kind = 'commercial_timezone_changed' and commercial_timezone is null then
    raise exception 'A commercial timezone change requires the new timezone.'
      using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  -- Serializes concurrent commands for one organization. Every command path takes this lock before
  -- reading the projection it is about to advance.
  select * into current_state
  from public.organization_commercial_state
  where organization_commercial_state.organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events as event
  where event.organization_id = target_organization_id
    and event.idempotency_key = apply_organization_commercial_command.idempotency_key;

  if found then
    return jsonb_build_object(
      'applied', false,
      'event_id', existing_event.id,
      'organization_id', target_organization_id,
      'paid_through_date', current_state.paid_through_date,
      'paid_through_source', current_state.paid_through_source,
      'grace_ends_at', current_state.grace_ends_at,
      'state_version', current_state.state_version
    );
  end if;

  select * into current_settings
  from public.organization_commercial_settings
  where organization_commercial_settings.organization_id = target_organization_id;

  next_timezone := case
    when event_kind = 'commercial_timezone_changed' then commercial_timezone
    else current_settings.commercial_timezone
  end;

  next_paid_through := case
    when paid_through_effect = 'set' then paid_through_date
    else current_state.paid_through_date
  end;

  next_paid_through_source := case
    when paid_through_effect <> 'set' then current_state.paid_through_source
    when event_kind = 'initial_payment_confirmed' then 'provisioning'
    when event_kind = 'renewal_confirmed' then 'renewal'
    when event_kind = 'refund_recorded' then 'refund'
    when event_kind = 'payment_reversal_recorded' then 'reversal'
    else 'manual_correction'
  end;

  -- A commercial-timezone change preserves the existing deadline unless recalculation is confirmed.
  if event_kind = 'commercial_timezone_changed' and not recalculate_deadline then
    next_grace_ends_at := current_state.grace_ends_at;
    next_grace_timezone := current_state.grace_basis_timezone;
    if next_paid_through is not null and next_grace_ends_at is null then
      next_grace_ends_at := private.organization_grace_ends_at(next_paid_through, next_timezone);
      next_grace_timezone := next_timezone;
    end if;
  else
    next_grace_ends_at := private.organization_grace_ends_at(next_paid_through, next_timezone);
    next_grace_timezone := case when next_paid_through is null then null else next_timezone end;
  end if;

  insert into public.organization_commercial_events (
    organization_id,
    event_kind,
    occurred_at,
    actor_owner_email,
    summary,
    private_reason,
    private_reference,
    amount_usd_cents,
    original_confirmation_id,
    source_event_id,
    suspension_category,
    is_legacy_import,
    paid_through_effect,
    paid_through_before,
    paid_through_after,
    commercial_timezone_before,
    commercial_timezone_after,
    deadline_recalculated,
    grace_ends_at_after,
    idempotency_key
  )
  values (
    target_organization_id,
    apply_organization_commercial_command.event_kind,
    apply_organization_commercial_command.occurred_at,
    apply_organization_commercial_command.actor_owner_email,
    apply_organization_commercial_command.summary,
    apply_organization_commercial_command.private_reason,
    apply_organization_commercial_command.private_reference,
    apply_organization_commercial_command.amount_usd_cents,
    apply_organization_commercial_command.original_confirmation_id,
    apply_organization_commercial_command.source_event_id,
    apply_organization_commercial_command.suspension_category,
    apply_organization_commercial_command.is_legacy_import,
    apply_organization_commercial_command.paid_through_effect,
    current_state.paid_through_date,
    next_paid_through,
    case when event_kind = 'commercial_timezone_changed' then current_settings.commercial_timezone end,
    case when event_kind = 'commercial_timezone_changed' then next_timezone end,
    event_kind = 'commercial_timezone_changed' and recalculate_deadline,
    next_grace_ends_at,
    apply_organization_commercial_command.idempotency_key
  )
  returning * into inserted_event;

  if event_kind = 'commercial_timezone_changed' then
    update public.organization_commercial_settings
    set commercial_timezone = next_timezone,
        timezone_source = 'owner_set'
    where organization_commercial_settings.organization_id = target_organization_id;
  end if;

  update public.organization_commercial_state
  set paid_through_date = next_paid_through,
      paid_through_source = next_paid_through_source,
      grace_ends_at = next_grace_ends_at,
      grace_basis_timezone = next_grace_timezone,
      last_event_id = inserted_event.id,
      state_version = current_state.state_version + 1
  where organization_commercial_state.organization_id = target_organization_id
    and organization_commercial_state.state_version = current_state.state_version;

  if not found then
    raise exception 'The commercial state changed during this command. Retry the command.'
      using errcode = 'P0409';
  end if;

  if safe_kind is not null then
    insert into public.organization_safe_events (
      organization_id,
      commercial_event_id,
      safe_kind,
      safe_payload,
      occurred_at
    )
    values (
      target_organization_id,
      inserted_event.id,
      apply_organization_commercial_command.safe_kind,
      coalesce(apply_organization_commercial_command.safe_payload, '{}'::jsonb),
      apply_organization_commercial_command.occurred_at
    );
  end if;

  return jsonb_build_object(
    'applied', true,
    'event_id', inserted_event.id,
    'organization_id', target_organization_id,
    'paid_through_date', next_paid_through,
    'paid_through_source', next_paid_through_source,
    'grace_ends_at', next_grace_ends_at,
    'commercial_timezone', next_timezone,
    'state_version', current_state.state_version + 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_feature_exception(target_organization_id uuid, target_feature_key text, target_override_state text, target_starts_at timestamp with time zone, target_expires_at timestamp with time zone, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_state public.organization_commercial_state%rowtype;
  before_row public.organization_feature_overrides%rowtype;
  has_before boolean := false;
  before_json jsonb := '{}'::jsonb;
  after_json jsonb := '{}'::jsonb;
  inserted_event public.organization_commercial_events%rowtype;
  existing_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
begin
  if target_override_state not in ('on', 'off', 'inherit') then
    raise exception 'The feature exception state is invalid.' using errcode = 'check_violation';
  end if;
  if target_starts_at is null or (target_expires_at is not null and target_expires_at <= target_starts_at) then
    raise exception 'A feature exception needs a valid start and optional later expiry.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A private reason is required for a feature exception.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.features where feature_key = target_feature_key) then
    raise exception 'The feature was not found.' using errcode = 'foreign_key_violation';
  end if;
  perform private.ensure_organization_commercial_rows(target_organization_id);
  select * into current_state from public.organization_commercial_state
  where organization_id = target_organization_id for update;
  select * into existing_event from public.organization_commercial_events
  where organization_id = target_organization_id and organization_commercial_events.idempotency_key = apply_organization_feature_exception.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'change_after', existing_event.change_after);
  end if;

  select * into before_row from public.organization_feature_overrides
  where organization_id = target_organization_id and feature_key = target_feature_key for update;
  has_before := found;
  if has_before then
    before_json := jsonb_build_object('feature_key', before_row.feature_key, 'override_state', before_row.override_state,
      'starts_at', before_row.starts_at, 'expires_at', before_row.expires_at,
      'reason', before_row.reason, 'is_legacy_import', before_row.is_legacy_import);
  end if;

  if target_override_state = 'inherit' then
    delete from public.organization_feature_overrides
    where organization_id = target_organization_id and feature_key = target_feature_key;
    after_json := jsonb_build_object('feature_key', target_feature_key, 'override_state', 'inherit');
  else
    insert into public.organization_feature_overrides (
      organization_id, feature_key, override_state, starts_at, expires_at, reason, actor_owner_email, is_legacy_import
    ) values (
      target_organization_id, target_feature_key, target_override_state, target_starts_at, target_expires_at,
      trim(private_reason), trim(actor_owner_email), false
    )
    on conflict (organization_id, feature_key) do update set
      override_state = excluded.override_state, starts_at = excluded.starts_at, expires_at = excluded.expires_at,
      reason = excluded.reason, actor_owner_email = excluded.actor_owner_email, is_legacy_import = false;
    after_json := jsonb_build_object('feature_key', target_feature_key, 'override_state', target_override_state,
      'starts_at', target_starts_at, 'expires_at', target_expires_at);
  end if;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, 'feature_exception_changed', command_time, trim(actor_owner_email),
    'Feature access exception changed.', trim(private_reason), 'unchanged', current_state.paid_through_date,
    current_state.paid_through_date, current_state.grace_ends_at, before_json, after_json, idempotency_key
  ) returning * into inserted_event;
  update public.organization_commercial_state
  set last_event_id = inserted_event.id, state_version = current_state.state_version + 1
  where organization_id = target_organization_id and state_version = current_state.state_version;
  if not found then raise exception 'The commercial state changed during this command. Retry the command.' using errcode = 'P0409'; end if;
  insert into public.organization_safe_events (organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at)
  values (target_organization_id, inserted_event.id, 'feature_access_changed',
    jsonb_build_object('feature_key', target_feature_key,
      'access_status', case when target_override_state = 'inherit' then 'inherited' else target_override_state end), command_time);
  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'change_before', before_json, 'change_after', after_json);
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_free_access_change(target_organization_id uuid, target_action text, target_grant_id uuid, target_starts_at date, target_access_until_date date, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    if target_action in ('extend', 'convert_to_forever')
       and acted_starts_at <= command_date
       and has_future_grant then
      if target_action = 'convert_to_forever' or target_access_until_date >= future_starts_at then
        raise exception 'This change would overlap the already scheduled future grant.'
          using errcode = 'check_violation';
      end if;
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
      using errcode = 'P0409';
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
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_lifecycle_change(target_organization_id uuid, target_status text, target_suspension_category text, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
      using errcode = 'P0409';
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
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_limit_exception(target_organization_id uuid, target_limit_key text, target_limit_state text, target_limit_value integer, target_starts_at timestamp with time zone, target_expires_at timestamp with time zone, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_state public.organization_commercial_state%rowtype;
  before_row public.organization_limit_overrides%rowtype;
  before_json jsonb := '{}'::jsonb;
  after_json jsonb := '{}'::jsonb;
  inserted_event public.organization_commercial_events%rowtype;
  existing_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
begin
  if target_limit_key not in ('employee_seats', 'operational_email_recipients', 'essential_email_recipients') then
    raise exception 'The limit was not found.' using errcode = 'foreign_key_violation';
  end if;
  if target_limit_state not in ('unlimited', 'not_included', 'numeric', 'inherit') then
    raise exception 'The limit exception state is invalid.' using errcode = 'check_violation';
  end if;
  if target_limit_state = 'numeric' and (target_limit_value is null or target_limit_value < 0) then
    raise exception 'A numeric limit must be zero or greater.' using errcode = 'check_violation';
  end if;
  if target_limit_state <> 'numeric' and target_limit_value is not null then
    raise exception 'Only numeric limits can include a value.' using errcode = 'check_violation';
  end if;
  if target_starts_at is null or (target_expires_at is not null and target_expires_at <= target_starts_at) then
    raise exception 'A limit exception needs a valid start and optional later expiry.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A private reason is required for a limit exception.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);
  select * into current_state from public.organization_commercial_state
  where organization_id = target_organization_id for update;
  select * into existing_event from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_limit_exception.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'change_after', existing_event.change_after);
  end if;

  select * into before_row from public.organization_limit_overrides
  where organization_id = target_organization_id and limit_key = target_limit_key for update;
  if found then
    before_json := jsonb_build_object('limit_key', before_row.limit_key, 'limit_state', before_row.limit_state,
      'limit_value', before_row.limit_value, 'starts_at', before_row.starts_at, 'expires_at', before_row.expires_at,
      'reason', before_row.reason, 'is_legacy_import', before_row.is_legacy_import);
  end if;

  if target_limit_state = 'inherit' then
    delete from public.organization_limit_overrides
    where organization_id = target_organization_id and limit_key = target_limit_key;
    after_json := jsonb_build_object('limit_key', target_limit_key, 'limit_state', 'inherit');
  else
    insert into public.organization_limit_overrides (
      organization_id, limit_key, limit_state, limit_value, is_unlimited, starts_at, expires_at,
      reason, actor_owner_email, is_legacy_import
    ) values (
      target_organization_id, target_limit_key, target_limit_state,
      case when target_limit_state = 'numeric' then target_limit_value else null end,
      target_limit_state = 'unlimited', target_starts_at, target_expires_at,
      trim(private_reason), trim(actor_owner_email), false
    )
    on conflict (organization_id, limit_key) do update set
      limit_state = excluded.limit_state, limit_value = excluded.limit_value,
      is_unlimited = excluded.is_unlimited, starts_at = excluded.starts_at, expires_at = excluded.expires_at,
      reason = excluded.reason, actor_owner_email = excluded.actor_owner_email, is_legacy_import = false;
    after_json := jsonb_build_object('limit_key', target_limit_key, 'limit_state', target_limit_state,
      'limit_value', case when target_limit_state = 'numeric' then target_limit_value else null end,
      'starts_at', target_starts_at, 'expires_at', target_expires_at);
  end if;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, 'limit_exception_changed', command_time, trim(actor_owner_email),
    'Limit access exception changed.', trim(private_reason), 'unchanged', current_state.paid_through_date,
    current_state.paid_through_date, current_state.grace_ends_at, before_json, after_json, idempotency_key
  ) returning * into inserted_event;
  update public.organization_commercial_state
  set last_event_id = inserted_event.id, state_version = current_state.state_version + 1
  where organization_id = target_organization_id and state_version = current_state.state_version;
  if not found then
    raise exception 'The commercial state changed during this command.' using errcode = 'P0409';
  end if;
  insert into public.organization_safe_events (organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at)
  values (target_organization_id, inserted_event.id, 'limit_access_changed',
    jsonb_build_object('limit_key', target_limit_key,
      'limit_state', case when target_limit_state = 'inherit' then 'inherited' else target_limit_state end,
      'limit_value', case when target_limit_state = 'numeric' then target_limit_value else null end), command_time);
  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'change_before', before_json, 'change_after', after_json);
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_package_change(target_organization_id uuid, target_package_version_id uuid, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_state public.organization_commercial_state%rowtype;
  current_assignment public.organization_package_assignments%rowtype;
  current_version_id uuid;
  current_version jsonb;
  target_version record;
  inserted_assignment public.organization_package_assignments%rowtype;
  inserted_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  existing_event public.organization_commercial_events%rowtype;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(private_reason, ''))) not between 1 and 1000 then
    raise exception 'A private reason is required for a package change.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(actor_owner_email, ''))) not between 3 and 320 then
    raise exception 'An acting owner email is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'Commercial changes cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  perform private.ensure_organization_commercial_rows(target_organization_id);

  select * into current_state
  from public.organization_commercial_state
  where organization_id = target_organization_id
  for update;

  select * into existing_event
  from public.organization_commercial_events
  where organization_id = target_organization_id
    and organization_commercial_events.idempotency_key = apply_organization_package_change.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id,
      'organization_id', target_organization_id, 'change_after', existing_event.change_after);
  end if;

  select version.id, version.version_number, version.display_name, version.package_id,
         package.package_key, package.display_name as package_display_name,
         version.status as version_status, package.status as package_status
  into target_version
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = target_package_version_id;
  if not found then
    raise exception 'The package version was not found.' using errcode = 'foreign_key_violation';
  end if;
  if target_version.version_status <> 'published' or target_version.package_status <> 'published' then
    raise exception 'A package change must use a published package version.' using errcode = 'check_violation';
  end if;

  select * into current_assignment
  from public.organization_package_assignments
  where organization_id = target_organization_id
  order by effective_at desc, id desc
  limit 1;

  current_version_id := current_assignment.package_version_id;
  if current_version_id is null then
    select version.id into current_version_id
    from public.platform_package_versions as version
    join public.platform_packages as package on package.package_id = version.package_id
    join public.organizations as organization on organization.id = target_organization_id
    where package.package_key = organization.package_key
      and version.status = 'published'
      and package.status = 'published'
    order by version.version_number desc
    limit 1;
  end if;
  if current_version_id = target_package_version_id then
    raise exception 'The organization already uses this package version.' using errcode = 'check_violation';
  end if;

  select jsonb_build_object('package_version_id', version.id, 'version_number', version.version_number,
    'package_display_name', version.display_name)
  into current_version
  from public.platform_package_versions as version
  where version.id = current_version_id;

  insert into public.organization_package_assignments (
    organization_id, package_version_id, effective_at, assignment_source, reason
  ) values (
    target_organization_id, target_package_version_id, command_time, 'package_change', trim(private_reason)
  ) returning * into inserted_assignment;

  insert into public.organization_commercial_events (
    organization_id, event_kind, occurred_at, actor_owner_email, summary, private_reason,
    paid_through_effect, paid_through_before, paid_through_after, grace_ends_at_after,
    change_before, change_after, idempotency_key
  ) values (
    target_organization_id, 'package_version_changed', command_time, trim(actor_owner_email),
    'Package version changed.', trim(private_reason), 'unchanged', current_state.paid_through_date,
    current_state.paid_through_date, current_state.grace_ends_at, coalesce(current_version, '{}'::jsonb),
    jsonb_build_object('package_version_id', target_version.id, 'version_number', target_version.version_number,
      'package_display_name', target_version.display_name), idempotency_key
  ) returning * into inserted_event;

  update public.organization_commercial_state
  set last_event_id = inserted_event.id,
      state_version = current_state.state_version + 1
  where organization_id = target_organization_id
    and state_version = current_state.state_version;
  if not found then
    raise exception 'The commercial state changed during this command. Retry the command.'
      using errcode = 'P0409';
  end if;

  insert into public.organization_safe_events (
    organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at
  ) values (
    target_organization_id, inserted_event.id, 'package_changed',
    jsonb_build_object('package_display_name', target_version.display_name,
      'package_version_number', target_version.version_number, 'effective_at', command_time), command_time
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id,
    'assignment_id', inserted_assignment.id, 'change_before', coalesce(current_version, '{}'::jsonb),
    'change_after', jsonb_build_object('package_version_id', target_version.id,
      'version_number', target_version.version_number, 'package_display_name', target_version.display_name));
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_organization_pending_setup_reconciliation(target_organization_id uuid, target_status text, target_suspension_category text, idempotency_key text, private_reason text, actor_owner_email text, occurred_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
      using errcode = 'P0409';
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
$function$;

CREATE OR REPLACE FUNCTION public.change_team_member_role(target_organization_id uuid, actor_user_id uuid, target_user_id uuid, new_role text, keep_adjustments boolean, expected_access_revision integer)
 RETURNS organization_members
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  actor_role text;
  membership public.organization_members;
  previous_role text;
  dropped_keys text[];
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );
  perform private.assert_membership_is_editable(membership);

  if expected_access_revision is null or expected_access_revision <> membership.access_revision then
    raise exception 'Someone else changed this person''s access while you were editing.'
      using errcode = 'P0409';
  end if;

  -- Ownership has one road, and this is not it.
  if new_role = 'owner' then
    raise exception 'Ownership is handed over, never assigned.' using errcode = 'check_violation';
  end if;

  if new_role is null or new_role not in ('admin', 'office', 'sales', 'field', 'finance') then
    raise exception '% is not a role.', coalesce(new_role, 'nothing') using errcode = 'check_violation';
  end if;

  select membership_actor.role into actor_role
  from public.organization_members as membership_actor
  where membership_actor.organization_id = target_organization_id
    and membership_actor.user_id = actor_user_id;

  if new_role = 'admin' and actor_role <> 'owner' then
    raise exception 'Only the owner can make someone an administrator.' using errcode = 'check_violation';
  end if;

  if new_role = membership.role then
    raise exception 'That person already has this role.' using errcode = 'check_violation';
  end if;

  previous_role := membership.role;

  with dropped as (
    delete from public.organization_member_permission_overrides as override
    where override.organization_id = target_organization_id
      and override.user_id = target_user_id
      and (
        keep_adjustments is not true
        or (
          override.override_state = 'grant'
          and exists (
            select 1
            from public.role_permissions as role_permission
            where role_permission.role = new_role
              and role_permission.permission_key = override.permission_key
          )
        )
        or (
          override.override_state = 'deny'
          and not exists (
            select 1
            from public.role_permissions as role_permission
            where role_permission.role = new_role
              and role_permission.permission_key = override.permission_key
          )
        )
      )
    returning override.permission_key
  )
  select coalesce(array_agg(dropped.permission_key order by dropped.permission_key), '{}'::text[])
  into dropped_keys
  from dropped;

  update public.organization_members as membership_row
  set role = new_role,
      access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.role_changed', 'member', actor_user_id, target_user_id,
    jsonb_build_object('previous_role', previous_role, 'new_role', new_role)
  );

  -- A second line, only when adjustments actually went. One Save that both changed the role and dropped
  -- three adjustments should read as both facts in the history, not as a role change that quietly did more.
  if array_length(dropped_keys, 1) is not null then
    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
    )
    values (
      target_organization_id, 'member.permissions_changed', 'member', actor_user_id, target_user_id,
      jsonb_build_object('removed_permissions', to_jsonb(dropped_keys))
    );
  end if;

  return membership;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_team_member_permissions(target_organization_id uuid, actor_user_id uuid, target_user_id uuid, desired_overrides jsonb, expected_access_revision integer)
 RETURNS organization_members
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  membership public.organization_members;
  added_keys text[];
  removed_keys text[];
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );
  perform private.assert_membership_is_editable(membership);

  if expected_access_revision is null or expected_access_revision <> membership.access_revision then
    raise exception 'Someone else changed this person''s access while you were editing.'
      using errcode = 'P0409';
  end if;

  if desired_overrides is null or jsonb_typeof(desired_overrides) <> 'array' then
    raise exception 'The permission adjustments must be a list.' using errcode = 'check_violation';
  end if;

  -- Every entry names a real permission and one of the two states. An unknown key would be caught by the
  -- foreign key anyway, but the message it produces is not one anybody could act on.
  if exists (
    select 1
    from jsonb_array_elements(desired_overrides) as entry(item)
    where jsonb_typeof(entry.item) <> 'object'
      or (entry.item ->> 'permission_key') is null
      or (entry.item ->> 'override_state') not in ('grant', 'deny')
      or not exists (
        select 1 from public.permissions as permission
        where permission.key = entry.item ->> 'permission_key'
      )
  ) then
    raise exception 'One of those permission adjustments is not something we can save.'
      using errcode = 'check_violation';
  end if;

  -- The packet's rule, restated where it would be broken: no domain enforces "Assigned work only" yet, so
  -- the only scope this command will store is 'all'. A caller asking for anything else is refused here
  -- rather than by the scope trigger, which cannot explain itself as clearly.
  if exists (
    select 1
    from jsonb_array_elements(desired_overrides) as entry(item)
    where coalesce(entry.item ->> 'access_scope', 'all') <> 'all'
  ) then
    raise exception 'Assigned-only access is not available yet.' using errcode = 'check_violation';
  end if;

  if exists (
    select entry.item ->> 'permission_key'
    from jsonb_array_elements(desired_overrides) as entry(item)
    group by entry.item ->> 'permission_key'
    having count(*) > 1
  ) then
    raise exception 'The same permission was adjusted twice in one save.' using errcode = 'check_violation';
  end if;

  -- Added and removed are worked out against what is stored right now, before anything is written. A
  -- grant that becomes a deny appears in both lists, which is the truth: one adjustment left, another came.
  -- The wanted set is read straight out of the argument each time rather than staged in a temporary table:
  -- these are a handful of rows per member, and a temporary table on a transaction-pooled connection is
  -- catalog churn nobody asked for.
  select
    coalesce(array_agg(distinct changed.permission_key) filter (where changed.direction = 'added'), '{}'),
    coalesce(array_agg(distinct changed.permission_key) filter (where changed.direction = 'removed'), '{}')
  into added_keys, removed_keys
  from (
    select entry.item ->> 'permission_key' as permission_key, 'added' as direction
    from jsonb_array_elements(desired_overrides) as entry(item)
    where not exists (
      select 1
      from public.organization_member_permission_overrides as existing
      where existing.organization_id = target_organization_id
        and existing.user_id = target_user_id
        and existing.permission_key = entry.item ->> 'permission_key'
        and existing.override_state = entry.item ->> 'override_state'
    )
    union all
    select existing.permission_key, 'removed'
    from public.organization_member_permission_overrides as existing
    where existing.organization_id = target_organization_id
      and existing.user_id = target_user_id
      and not exists (
        select 1
        from jsonb_array_elements(desired_overrides) as entry(item)
        where entry.item ->> 'permission_key' = existing.permission_key
          and entry.item ->> 'override_state' = existing.override_state
      )
  ) as changed;

  -- Adjustments the save left out are gone. One that only changed sides is left to the upsert below, so a
  -- grant becoming a deny never passes through a moment of having no adjustment at all.
  delete from public.organization_member_permission_overrides as override
  where override.organization_id = target_organization_id
    and override.user_id = target_user_id
    and not exists (
      select 1
      from jsonb_array_elements(desired_overrides) as entry(item)
      where entry.item ->> 'permission_key' = override.permission_key
    );

  insert into public.organization_member_permission_overrides (
    organization_id, user_id, permission_key, override_state, access_scope
  )
  select
    target_organization_id,
    target_user_id,
    entry.item ->> 'permission_key',
    entry.item ->> 'override_state',
    'all'
  from jsonb_array_elements(desired_overrides) as entry(item)
  on conflict (organization_id, user_id, permission_key) do update
  set override_state = excluded.override_state,
      access_scope = excluded.access_scope,
      updated_at = now();

  -- Nothing moved, so nothing is recorded and no editor is invalidated. Saving an unchanged form is not an
  -- access change, and a history full of "changed nothing" lines is a history nobody reads.
  if array_length(added_keys, 1) is null and array_length(removed_keys, 1) is null then
    return membership;
  end if;

  update public.organization_members as membership_row
  set access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.permissions_changed', 'member', actor_user_id, target_user_id,
    jsonb_strip_nulls(
      jsonb_build_object(
        'added_permissions',
          case when array_length(added_keys, 1) is null then null else to_jsonb(added_keys) end,
        'removed_permissions',
          case when array_length(removed_keys, 1) is null then null else to_jsonb(removed_keys) end
      )
    )
  );

  return membership;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_cancelled_team_invitation_cleanup(target_organization_id uuid, target_invitation_id uuid, target_lease_nonce uuid, target_lease_seconds integer DEFAULT 300)
 RETURNS organization_member_invitations
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  claimed_row public.organization_member_invitations;
begin
  if target_lease_seconds not between 30 and 1800 then
    raise exception 'The reconciliation lease is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  update public.organization_member_invitations
  set reconciliation_nonce = target_lease_nonce,
      reconciliation_lease_expires_at = now() + make_interval(secs => target_lease_seconds)
  where id = target_invitation_id
    and organization_id = target_organization_id
    and state = 'cancelled'
    and identity_cleanup_state = 'required'
    and invited_user_id is not null
    and (
      reconciliation_lease_expires_at is null
      or reconciliation_lease_expires_at < now()
    )
  returning * into claimed_row;

  if not found then
    raise exception 'The cancelled invitation is not available for cleanup.'
      using errcode = 'P0409';
  end if;

  return claimed_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.finalize_reconciled_team_invitation(target_invitation_id uuid, target_lease_nonce uuid)
 RETURNS organization_member_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  current_row public.organization_member_invitations;
begin
  select invitation.* into current_row
  from public.organization_member_invitations as invitation
  join auth.users as auth_user on auth_user.id = invitation.invited_user_id
  where invitation.id = target_invitation_id
    and invitation.state = 'accepting'
    and invitation.identity_cleanup_state = 'required'
    and invitation.reconciliation_nonce = target_lease_nonce
    and invitation.reconciliation_lease_expires_at > now()
    and auth_user.raw_app_meta_data ->> 'team_invitation_identity_for' = invitation.id::text
    and auth_user.raw_app_meta_data ->> 'invitation_password_set_for' = invitation.id::text
  for update of invitation;

  if not found then
    raise exception 'The invitation reconciliation receipt is not valid.'
      using errcode = 'P0409';
  end if;

  update public.organization_member_invitations
  set password_set_at = coalesce(password_set_at, now()),
      identity_cleanup_state = 'not_required',
      identity_cleanup_error = null,
      reconciliation_nonce = null,
      reconciliation_lease_expires_at = null
  where id = target_invitation_id;

  return private.finalize_accepted_invitation(target_invitation_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_team_invitation_identity_cleanup(target_invitation_id uuid, target_lease_nonce uuid)
 RETURNS organization_member_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  target_invited_user_id uuid;
  prepared_row public.organization_member_invitations;
begin
  select invitation.invited_user_id
  into target_invited_user_id
  from public.organization_member_invitations as invitation
  where invitation.id = target_invitation_id
    and invitation.state in ('reserving', 'invited', 'accepting', 'cancelled', 'expired', 'abandoned')
    and invitation.identity_cleanup_state = 'required'
    and invitation.reconciliation_nonce = target_lease_nonce
    and invitation.reconciliation_lease_expires_at > now()
  for update;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.'
      using errcode = 'P0409';
  end if;

  update public.organization_member_invitations
  set state = case
        when state in ('cancelled', 'expired', 'abandoned') then state
        else 'reserving'
      end,
      invited_user_id = null,
      token_hash = null,
      lease_nonce = null,
      lease_expires_at = null
  where id = target_invitation_id
  returning * into prepared_row;

  delete from public.organization_members
  where organization_id = prepared_row.organization_id
    and user_id = target_invited_user_id
    and status = 'pending';

  return prepared_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.release_team_invitation_reconciliation(target_invitation_id uuid, target_lease_nonce uuid, target_safe_error text)
 RETURNS organization_member_invitations
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  released_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set identity_cleanup_error = left(nullif(trim(target_safe_error), ''), 240),
      reconciliation_nonce = null,
      reconciliation_lease_expires_at = null
  where id = target_invitation_id
    and identity_cleanup_state = 'required'
    and reconciliation_nonce = target_lease_nonce
    and reconciliation_lease_expires_at > now()
  returning * into released_row;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'P0409';
  end if;
  return released_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.settle_team_invitation_identity_cleanup(target_invitation_id uuid, target_lease_nonce uuid)
 RETURNS organization_member_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  settled_row public.organization_member_invitations;
begin
  update public.organization_member_invitations
  set state = case when state in ('reserving', 'invited', 'accepting') then 'abandoned' else state end,
      token_hash = null,
      lease_nonce = null,
      lease_expires_at = null,
      identity_cleanup_state = 'done',
      identity_cleanup_error = null,
      reconciliation_nonce = null,
      reconciliation_lease_expires_at = null
  where id = target_invitation_id
    and identity_cleanup_state = 'required'
    and reconciliation_nonce = target_lease_nonce
    and reconciliation_lease_expires_at > now()
  returning * into settled_row;

  if not found then
    raise exception 'The invitation cleanup lease is no longer valid.' using errcode = 'P0409';
  end if;

  return settled_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_catalog_item(target_organization_id uuid, target_item_id uuid, expected_revision integer, new_category text, new_name text, new_description text, new_unit_label text, new_is_labor boolean, new_unit_price_minor bigint, new_unit_cost_minor bigint, new_is_taxable boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  item_row public.catalog_items;
  clean_name text;
begin
  if not private.has_permission(target_organization_id, 'settings.price_book.manage') then
    raise exception 'You do not have access to manage the Price Book.' using errcode = 'insufficient_privilege';
  end if;

  select * into item_row
  from public.catalog_items
  where id = target_item_id and organization_id = target_organization_id
  for update;

  if item_row.id is null then
    raise exception 'That Price Book item was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from item_row.revision then
    raise exception 'Someone else changed this item while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
    raise exception 'Give this item a name between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  if item_row.archived_at is null and exists (
    select 1 from public.catalog_items
    where organization_id = target_organization_id
      and archived_at is null
      and id <> item_row.id
      and lower(name) = lower(clean_name)
  ) then
    raise exception 'An active Price Book item is already named "%".', clean_name
      using errcode = 'unique_violation';
  end if;

  update public.catalog_items
  set category = new_category, name = clean_name, description = new_description,
      unit_label = new_unit_label, is_labor = coalesce(new_is_labor, item_row.is_labor),
      unit_price_minor = coalesce(new_unit_price_minor, item_row.unit_price_minor),
      unit_cost_minor = coalesce(new_unit_cost_minor, item_row.unit_cost_minor),
      is_taxable = coalesce(new_is_taxable, item_row.is_taxable),
      revision = revision + 1, updated_by = (select auth.uid())
  where id = item_row.id
  returning * into item_row;

  return jsonb_build_object('id', item_row.id, 'name', item_row.name, 'revision', item_row.revision);
end;
$function$;

CREATE OR REPLACE FUNCTION public.delete_catalog_item(target_organization_id uuid, target_item_id uuid, expected_revision integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  item_row public.catalog_items;
begin
  if not private.has_permission(target_organization_id, 'settings.price_book.manage') then
    raise exception 'You do not have access to manage the Price Book.' using errcode = 'insufficient_privilege';
  end if;

  select * into item_row
  from public.catalog_items
  where id = target_item_id and organization_id = target_organization_id
  for update;

  if item_row.id is null then
    raise exception 'That Price Book item was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from item_row.revision then
    raise exception 'Someone else changed this item while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  delete from public.catalog_items where id = item_row.id;

  return jsonb_build_object('status', 'deleted', 'id', item_row.id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_organization_tax_rate(target_organization_id uuid, target_rate_id uuid, expected_revision integer, new_name text, new_rate_basis_points integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  rate_row public.organization_tax_rates;
  clean_name text;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select * into rate_row
  from public.organization_tax_rates
  where id = target_rate_id and organization_id = target_organization_id
  for update;

  if rate_row.id is null then
    raise exception 'That tax rate was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from rate_row.revision then
    raise exception 'Someone else changed this tax rate while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 80 then
    raise exception 'Give this tax rate a name up to 80 characters.' using errcode = 'check_violation';
  end if;

  if new_rate_basis_points is null or new_rate_basis_points <= 0 or new_rate_basis_points > 10000 then
    raise exception 'A tax rate is greater than 0%% and no more than 100%%.' using errcode = 'check_violation';
  end if;

  update public.organization_tax_rates
  set name = clean_name, rate_basis_points = new_rate_basis_points,
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = rate_row.id
  returning * into rate_row;

  return jsonb_build_object(
    'id', rate_row.id, 'name', rate_row.name, 'rate_basis_points', rate_row.rate_basis_points,
    'is_active', rate_row.is_active, 'revision', rate_row.revision
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.delete_organization_tax_rate(target_organization_id uuid, target_rate_id uuid, expected_revision integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  rate_row public.organization_tax_rates;
  pinned_count integer;
  is_business_default boolean;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select * into rate_row
  from public.organization_tax_rates
  where id = target_rate_id and organization_id = target_organization_id
  for update;

  if rate_row.id is null then
    raise exception 'That tax rate was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from rate_row.revision then
    raise exception 'Someone else changed this tax rate while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  select count(*) into pinned_count
  from public.properties
  where organization_id = target_organization_id and tax_rate_id = target_rate_id;

  if pinned_count > 0 then
    raise exception 'Reassign the % properties using this tax rate before deleting it.', pinned_count
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from public.organization_settings
    where organization_id = target_organization_id and tax_default_rate_id = target_rate_id
  ) into is_business_default;

  if is_business_default then
    raise exception 'This is the Business default tax. Choose a different default before deleting it.'
      using errcode = 'check_violation';
  end if;

  delete from public.organization_tax_rates where id = rate_row.id;

  return jsonb_build_object('status', 'deleted', 'id', rate_row.id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_organization_tax_rate_active(target_organization_id uuid, target_rate_id uuid, expected_revision integer, new_is_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  rate_row public.organization_tax_rates;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select * into rate_row
  from public.organization_tax_rates
  where id = target_rate_id and organization_id = target_organization_id
  for update;

  if rate_row.id is null then
    raise exception 'That tax rate was not found.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from rate_row.revision then
    raise exception 'Someone else changed this tax rate while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  update public.organization_tax_rates
  set is_active = coalesce(new_is_active, rate_row.is_active),
      revision = revision + 1, updated_by = (select auth.uid()), updated_at = now()
  where id = rate_row.id
  returning * into rate_row;

  return jsonb_build_object(
    'id', rate_row.id, 'name', rate_row.name, 'rate_basis_points', rate_row.rate_basis_points,
    'is_active', rate_row.is_active, 'revision', rate_row.revision
  );
end;
$function$;
