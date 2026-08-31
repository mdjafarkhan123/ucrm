-- Contractor Settings Part 6B, slice 1: Automation feature key and the seven versioned limits.
--
-- Extends the established versioned-access seams exactly as Website Chat (WC1) did for its two limits:
-- the two limit_key check constraints, the audited organization exception command, a single effective
-- resolver, and an owner draft-only package writer. No generic limit-catalog table is introduced.
--
-- The `automations` feature is added to the catalog but attached to no package. In 6B every contractor
-- package therefore resolves `automations` = false, so no dead Automation destination is exposed. The
-- legacy `automation.workflows` key is left untouched for immutable package history and grants no
-- Automation runtime access.

-- 1. Feature catalog: add automations, keep automation.workflows for history only. ---------------------
insert into public.features (feature_key, description)
values ('automations', 'Automation recipes and enrollments')
on conflict (feature_key) do nothing;

-- 2. Widen the two limit_key check constraints to admit the seven explicit Automation keys. ------------
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
    'automation_max_enrollment_duration_days'
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
    'automation_max_enrollment_duration_days'
  ));

-- 3. Extend the audited organization exception command to admit the seven Automation keys. -------------
-- Body is the current live definition (pg_get_functiondef 2026-09-13); only the guarded key list
-- changes, so the commercial-event, idempotency, optimistic-version, and safe-event behaviour is
-- preserved verbatim.
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
    'automation_max_enrollment_duration_days'
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

-- 4. Single effective resolver for all seven Automation limits, one snapshot, one round trip. ----------
-- Mirrors effective_website_chat_widgets_limit's precedence (active override wins, else the current
-- package version, else not_included) but resolves the whole family in one set-based query. The seven
-- keys are a fixed VALUES list; no key is ever taken from a caller argument, and there is no dynamic
-- SQL. security invoker means an authenticated caller only ever sees their own organization's assignment
-- and overrides through existing RLS -- naming another tenant yields no rows and every key fails closed
-- to not_included. The assignment is selected exactly as resolveOrganizationAccess selects it (latest by
-- effective_at, id) so a package's features and its limits always come from the same version.
create or replace function public.effective_automation_limits(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  limit_key text,
  state text,
  value integer,
  is_unlimited boolean,
  source text
)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  with keys (limit_key) as (
    values
      ('automation_active_recipes'),
      ('automation_max_conditions_per_recipe'),
      ('automation_max_steps_per_recipe'),
      ('automation_max_customer_messages_per_enrollment'),
      ('automation_min_customer_message_spacing_minutes'),
      ('automation_max_delay_days'),
      ('automation_max_enrollment_duration_days')
  ),
  current_assignment as (
    select assignment.package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = target_organization_id
    order by assignment.effective_at desc, assignment.id desc
    limit 1
  ),
  package_limit as (
    select version_limit.limit_key, version_limit.limit_state, version_limit.limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = (select package_version_id from current_assignment)
      and version_limit.limit_key in (
        'automation_active_recipes', 'automation_max_conditions_per_recipe',
        'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
        'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
        'automation_max_enrollment_duration_days'
      )
  ),
  active_override as (
    select override.limit_key, override.limit_state, override.limit_value, override.is_unlimited
    from public.organization_limit_overrides as override
    where override.organization_id = target_organization_id
      and override.limit_key in (
        'automation_active_recipes', 'automation_max_conditions_per_recipe',
        'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
        'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
        'automation_max_enrollment_duration_days'
      )
      and override.starts_at <= at
      and (override.expires_at is null or override.expires_at > at)
  )
  select
    keys.limit_key,
    coalesce(active_override.limit_state, package_limit.limit_state, 'not_included') as state,
    case
      when active_override.limit_key is not null then
        case when active_override.limit_state = 'numeric' then active_override.limit_value end
      when package_limit.limit_key is not null then
        case when package_limit.limit_state = 'numeric' then package_limit.limit_value end
      else null
    end as value,
    case
      when active_override.limit_key is not null then active_override.is_unlimited
      when package_limit.limit_key is not null then package_limit.limit_state = 'unlimited'
      else false
    end as is_unlimited,
    case when active_override.limit_key is not null then 'override' else 'package' end as source
  from keys
  left join package_limit on package_limit.limit_key = keys.limit_key
  left join active_override on active_override.limit_key = keys.limit_key
  order by keys.limit_key;
$$;

comment on function public.effective_automation_limits(uuid, timestamptz) is
  'Single authority for the seven Automation limits. One snapshot; override then package then not_included.';

revoke all on function public.effective_automation_limits(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.effective_automation_limits(uuid, timestamptz) to authenticated;
grant execute on function public.effective_automation_limits(uuid, timestamptz) to service_role;

-- 5. Owner-managed package defaults for the seven Automation limits together, draft-only and audited. --
-- Mirrors manage_platform_package_website_chat_limits: explicit positional pairs (no browser-supplied
-- keys), numeric floor of one to match platform_package_version_limits_value_check, and a rewrite of all
-- seven rows on a draft version only.
create or replace function public.manage_platform_package_automation_limits(
  target_version_id uuid,
  target_active_recipes_state text,
  target_active_recipes_value integer,
  target_conditions_state text,
  target_conditions_value integer,
  target_steps_state text,
  target_steps_value integer,
  target_customer_messages_state text,
  target_customer_messages_value integer,
  target_message_spacing_state text,
  target_message_spacing_value integer,
  target_max_delay_state text,
  target_max_delay_value integer,
  target_max_duration_state text,
  target_max_duration_value integer,
  actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.platform_package_versions%rowtype;
  states text[] := array[
    target_active_recipes_state, target_conditions_state, target_steps_state,
    target_customer_messages_state, target_message_spacing_state, target_max_delay_state,
    target_max_duration_state
  ];
  values_in integer[] := array[
    target_active_recipes_value, target_conditions_value, target_steps_value,
    target_customer_messages_value, target_message_spacing_value, target_max_delay_value,
    target_max_duration_value
  ];
  keys text[] := array[
    'automation_active_recipes', 'automation_max_conditions_per_recipe',
    'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
    'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
    'automation_max_enrollment_duration_days'
  ];
  i integer;
begin
  if char_length(trim(coalesce(actor_email, ''))) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;

  for i in 1 .. array_length(keys, 1) loop
    if states[i] not in ('unlimited', 'not_included', 'numeric') then
      raise exception 'Choose a valid Automation limit type.' using errcode = 'check_violation';
    end if;
    if states[i] = 'numeric' and coalesce(values_in[i], 0) < 1 then
      raise exception 'A numeric Automation limit must be at least one.' using errcode = 'check_violation';
    end if;
    if states[i] <> 'numeric' and values_in[i] is not null then
      raise exception 'Only a numeric Automation limit can include a value.' using errcode = 'check_violation';
    end if;
  end loop;

  select * into version_row
  from public.platform_package_versions
  where id = target_version_id
  for update;
  if not found or version_row.status <> 'draft' then
    raise exception 'Automation limits can only be changed on a draft package version.' using errcode = 'check_violation';
  end if;

  delete from public.platform_package_version_limits
  where package_version_id = version_row.id
    and limit_key = any (keys);

  for i in 1 .. array_length(keys, 1) loop
    insert into public.platform_package_version_limits (package_version_id, limit_key, limit_state, limit_value)
    values (
      version_row.id, keys[i], states[i],
      case when states[i] = 'numeric' then values_in[i] end
    );
  end loop;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    lower(trim(actor_email)), 'package.automation_limits_changed', 'platform_package_version', version_row.id::text,
    jsonb_build_object(
      'active_recipes', jsonb_build_object('state', target_active_recipes_state, 'value', target_active_recipes_value),
      'conditions_per_recipe', jsonb_build_object('state', target_conditions_state, 'value', target_conditions_value),
      'steps_per_recipe', jsonb_build_object('state', target_steps_state, 'value', target_steps_value),
      'customer_messages_per_enrollment', jsonb_build_object('state', target_customer_messages_state, 'value', target_customer_messages_value),
      'message_spacing_minutes', jsonb_build_object('state', target_message_spacing_state, 'value', target_message_spacing_value),
      'max_delay_days', jsonb_build_object('state', target_max_delay_state, 'value', target_max_delay_value),
      'max_enrollment_duration_days', jsonb_build_object('state', target_max_duration_state, 'value', target_max_duration_value)
    )
  );
  return version_row.id;
end;
$$;

comment on function public.manage_platform_package_automation_limits(uuid, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text) is
  'Owner-managed draft-only write for the seven Automation package limits.';

revoke all on function public.manage_platform_package_automation_limits(uuid, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.manage_platform_package_automation_limits(uuid, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text)
  to service_role;
