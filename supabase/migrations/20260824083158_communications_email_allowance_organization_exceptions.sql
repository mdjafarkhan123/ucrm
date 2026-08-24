-- Communications Part 2B-A: extend the established, audited exception command to
-- the two email capacities. The outbox continues to use the private resolver and
-- remains fail-closed until Part 2B-B explicitly connects it.

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
    raise exception 'The commercial state changed during this command.' using errcode = 'serialization_failure';
  end if;
  insert into public.organization_safe_events (organization_id, commercial_event_id, safe_kind, safe_payload, occurred_at)
  values (target_organization_id, inserted_event.id, 'limit_access_changed',
    jsonb_build_object('limit_key', target_limit_key,
      'limit_state', case when target_limit_state = 'inherit' then 'inherited' else target_limit_state end,
      'limit_value', case when target_limit_state = 'numeric' then target_limit_value else null end), command_time);
  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'change_before', before_json, 'change_after', after_json);
end;
$$;

-- This owner-only read model reports both the current effective value and the
-- package fallback. It deliberately returns a row even before billing has opened
-- a period so the UI can say that sends are still fail-closed.
create or replace function public.get_organization_communication_email_allowances(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  limit_key text,
  period_id uuid,
  period_starts_at timestamptz,
  period_ends_at timestamptz,
  effective_state text,
  effective_value integer,
  effective_source text,
  fallback_state text,
  fallback_value integer,
  override_state text,
  override_value integer,
  override_starts_at timestamptz,
  override_expires_at timestamptz,
  override_reason text,
  override_author_email text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  with keys(limit_key) as (
    values ('operational_email_recipients'::text), ('essential_email_recipients'::text)
  ), current_assignment as (
    select assignment.package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = target_organization_id and assignment.effective_at <= at
    order by assignment.effective_at desc, assignment.id desc
    limit 1
  ), package_limits as (
    select version_limit.limit_key, version_limit.limit_state, version_limit.limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = (select package_version_id from current_assignment)
      and version_limit.limit_key in ('operational_email_recipients', 'essential_email_recipients')
  ), stored_overrides as (
    select override.limit_key, override.limit_state, override.limit_value, override.starts_at,
      override.expires_at, override.reason, override.actor_owner_email,
      override.starts_at <= at and (override.expires_at is null or override.expires_at > at) as is_active
    from public.organization_limit_overrides as override
    where override.organization_id = target_organization_id
      and override.limit_key in ('operational_email_recipients', 'essential_email_recipients')
  ), allowance as (
    select * from private.resolve_communication_email_allowance(target_organization_id, at)
  )
  select
    key.limit_key,
    allowance.period_id,
    allowance.period_starts_at,
    allowance.period_ends_at,
    case key.limit_key
      when 'operational_email_recipients' then coalesce(
        case when override.is_active then override.limit_state end, allowance.operational_limit_state, package_limit.limit_state)
      else coalesce(
        case when override.is_active then override.limit_state end, allowance.essential_limit_state, package_limit.limit_state)
    end,
    case key.limit_key
      when 'operational_email_recipients' then coalesce(
        case when override.is_active then override.limit_value end, allowance.operational_limit_value, package_limit.limit_value)
      else coalesce(
        case when override.is_active then override.limit_value end, allowance.essential_limit_value, package_limit.limit_value)
    end,
    case when override.is_active then 'override' else 'package' end,
    package_limit.limit_state,
    package_limit.limit_value,
    override.limit_state,
    override.limit_value,
    override.starts_at,
    override.expires_at,
    override.reason,
    override.actor_owner_email
  from keys as key
  left join package_limits as package_limit on package_limit.limit_key = key.limit_key
  left join stored_overrides as override on override.limit_key = key.limit_key
  left join allowance on true
  order by key.limit_key;
$$;

revoke all on function public.get_organization_communication_email_allowances(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.get_organization_communication_email_allowances(uuid, timestamptz) to service_role;
