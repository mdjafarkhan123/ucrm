-- Marketing M1: the Marketing email allowance is one more versioned package limit.
--
-- Marketing sends draw on a monthly allowance that is separate from operational/essential email, so an
-- announcement campaign can never use up the mail a contractor needs for quotes and invoices. The billing
-- window itself is the one every organization already gets automatically (communication_email_allowance_periods);
-- no second window table is created. Usage counting arrives with the launch command in M3, when there is
-- something to count.
--
-- "Unset" is deliberate: no package carries this limit until Jafar sets it, and a missing row resolves to
-- not_included, so Marketing launch stays blocked ("Marketing allowance not configured").

-- 1. Widen the two limit_key check constraints. ---------------------------------------------------------
alter table public.platform_package_version_limits
  drop constraint platform_package_version_limits_limit_key_check;

alter table public.platform_package_version_limits
  add constraint platform_package_version_limits_limit_key_check
  check (limit_key in (
    'employee_seats', 'operational_email_recipients', 'essential_email_recipients',
    'website_chat_widgets', 'website_chat_accepted_conversations',
    'automation_active_recipes', 'automation_max_conditions_per_recipe',
    'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
    'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
    'automation_max_enrollment_duration_days',
    'marketing_email_recipients'
  ));

alter table public.organization_limit_overrides
  drop constraint organization_limit_overrides_limit_key_check;

alter table public.organization_limit_overrides
  add constraint organization_limit_overrides_limit_key_check
  check (limit_key in (
    'employee_seats', 'operational_email_recipients', 'essential_email_recipients',
    'website_chat_widgets', 'website_chat_accepted_conversations',
    'automation_active_recipes', 'automation_max_conditions_per_recipe',
    'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
    'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
    'automation_max_enrollment_duration_days',
    'marketing_email_recipients'
  ));

-- 2. Let the audited organization exception command admit the new key. -----------------------------------
-- Body is the current live definition (Automation Part 6B); only the guarded key list changes.
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
  if target_limit_key not in (
    'employee_seats', 'operational_email_recipients', 'essential_email_recipients',
    'website_chat_widgets', 'website_chat_accepted_conversations',
    'automation_active_recipes', 'automation_max_conditions_per_recipe',
    'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
    'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
    'automation_max_enrollment_duration_days',
    'marketing_email_recipients'
  ) then
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

-- 3. Single authority for the Marketing allowance, shaped like effective_website_chat_widgets_limit. ------
-- Active override wins, else the current package version's row, else not_included (the "unset" state).
create or replace function private.effective_marketing_email_limit(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  state text,
  value integer,
  is_unlimited boolean,
  source text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with assignment as (
    select assignment.package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = target_organization_id
    order by assignment.effective_at desc, assignment.id desc
    limit 1
  ), active_override as (
    select override.limit_state, override.limit_value, override.is_unlimited
    from public.organization_limit_overrides as override
    where override.organization_id = target_organization_id
      and override.limit_key = 'marketing_email_recipients'
      and override.starts_at <= at
      and (override.expires_at is null or override.expires_at > at)
  ), package_limit as (
    select version_limit.limit_state, version_limit.limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = (select package_version_id from assignment)
      and version_limit.limit_key = 'marketing_email_recipients'
  )
  select
    coalesce(override.limit_state, package.limit_state, 'not_included'),
    case
      when override.limit_state is not null then override.limit_value
      when package.limit_state = 'numeric' then package.limit_value
    end,
    coalesce(override.is_unlimited, package.limit_state = 'unlimited', false),
    case when override.limit_state is not null then 'override' else 'package' end
  from (select 1) as one
  left join active_override as override on true
  left join package_limit as package on true;
$$;

comment on function private.effective_marketing_email_limit(uuid, timestamptz) is
  'Single authority for the marketing_email_recipients limit. A missing row is not_included (unset).';

revoke all on function private.effective_marketing_email_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function private.effective_marketing_email_limit(uuid, timestamptz) to service_role;

-- 4. Owner-managed package default, draft-only and audited. ----------------------------------------------
create or replace function public.manage_platform_package_marketing_allowance(
  target_version_id uuid,
  target_state text,
  target_value integer,
  actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.platform_package_versions%rowtype;
begin
  if char_length(trim(coalesce(actor_email, ''))) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if target_state not in ('unlimited', 'not_included', 'numeric') then
    raise exception 'Choose a valid Marketing allowance type.' using errcode = 'check_violation';
  end if;
  if (target_state = 'numeric' and coalesce(target_value, 0) < 1)
    or (target_state <> 'numeric' and target_value is not null) then
    raise exception 'A numeric Marketing allowance must be at least one recipient.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.platform_package_versions
  where id = target_version_id
  for update;
  if not found or version_row.status <> 'draft' then
    raise exception 'The Marketing allowance can only be changed on a draft package version.' using errcode = 'check_violation';
  end if;

  delete from public.platform_package_version_limits
  where package_version_id = version_row.id
    and limit_key = 'marketing_email_recipients';

  insert into public.platform_package_version_limits (package_version_id, limit_key, limit_state, limit_value)
  values (version_row.id, 'marketing_email_recipients', target_state,
    case when target_state = 'numeric' then target_value end);

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    lower(trim(actor_email)), 'package.marketing_allowance_changed', 'platform_package_version', version_row.id::text,
    jsonb_build_object('state', target_state, 'value', target_value)
  );
  return version_row.id;
end;
$$;

revoke all on function public.manage_platform_package_marketing_allowance(uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.manage_platform_package_marketing_allowance(uuid, text, integer, text)
  to service_role;
