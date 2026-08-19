-- Part 6C follow-up: the idempotency-key lookup in the three new command functions compared an
-- unqualified `idempotency_key` against both the table column and the identically named
-- parameter, which Postgres rejects as ambiguous. Qualify the table column explicitly.

create or replace function public.apply_organization_package_change(
  target_organization_id uuid,
  target_package_version_id uuid,
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
      using errcode = 'serialization_failure';
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
$$;

create or replace function public.apply_organization_feature_exception(
  target_organization_id uuid,
  target_feature_key text,
  target_override_state text,
  target_starts_at timestamptz,
  target_expires_at timestamptz,
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
  if not found then raise exception 'The commercial state changed during this command. Retry the command.' using errcode = 'serialization_failure'; end if;
  insert into public.organization_safe_events (organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at)
  values (target_organization_id, inserted_event.id, 'feature_access_changed',
    jsonb_build_object('feature_key', target_feature_key,
      'access_status', case when target_override_state = 'inherit' then 'inherited' else target_override_state end), command_time);
  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'change_before', before_json, 'change_after', after_json);
end;
$$;

create or replace function public.apply_organization_limit_exception(
  target_organization_id uuid,
  target_limit_key text,
  target_limit_state text,
  target_limit_value integer,
  target_starts_at timestamptz,
  target_expires_at timestamptz,
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
  before_row public.organization_limit_overrides%rowtype;
  has_before boolean := false;
  before_json jsonb := '{}'::jsonb;
  after_json jsonb := '{}'::jsonb;
  inserted_event public.organization_commercial_events%rowtype;
  existing_event public.organization_commercial_events%rowtype;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
begin
  if target_limit_key <> 'employee_seats' then
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
  where organization_id = target_organization_id and organization_commercial_events.idempotency_key = apply_organization_limit_exception.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'change_after', existing_event.change_after);
  end if;

  select * into before_row from public.organization_limit_overrides
  where organization_id = target_organization_id and limit_key = target_limit_key for update;
  has_before := found;
  if has_before then
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
  if not found then raise exception 'The commercial state changed during this command. Retry the command.' using errcode = 'serialization_failure'; end if;
  insert into public.organization_safe_events (organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at)
  values (target_organization_id, inserted_event.id, 'limit_access_changed',
    jsonb_build_object('limit_key', target_limit_key,
      'limit_state', case when target_limit_state = 'inherit' then 'inherited' else target_limit_state end,
      'limit_value', case when target_limit_state = 'numeric' then target_limit_value else null end), command_time);
  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'change_before', before_json, 'change_after', after_json);
end;
$$;
