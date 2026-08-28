-- Communications Website Chat, Part WC1 (smallest slice): platform entitlement authority only.
-- No widget, session, or public-facing table exists yet. This adds the two new limit_keys,
-- their own SQL authority functions (following the employee_seats / email-allowance pattern
-- exactly), and the owner package-editor write path. The accepted-conversations read model
-- reports no active period, since nothing creates a real usage period until later work opens one.

alter table public.platform_package_version_limits
  drop constraint platform_package_version_limits_limit_key_check;

alter table public.platform_package_version_limits
  add constraint platform_package_version_limits_limit_key_check
  check (limit_key in (
    'employee_seats', 'operational_email_recipients', 'essential_email_recipients',
    'website_chat_widgets', 'website_chat_accepted_conversations'
  ));

alter table public.organization_limit_overrides
  drop constraint organization_limit_overrides_limit_key_check;

alter table public.organization_limit_overrides
  add constraint organization_limit_overrides_limit_key_check
  check (limit_key in (
    'employee_seats', 'operational_email_recipients', 'essential_email_recipients',
    'website_chat_widgets', 'website_chat_accepted_conversations'
  ));

-- Extend the established, audited exception command to the two Website Chat limits.
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
    'website_chat_widgets', 'website_chat_accepted_conversations'
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

-- Single-value entitlement (widget count), resolved from the current package version plus an
-- active override -- shaped exactly like effective_employee_seat_limit so effective.ts and the
-- organization-detail block can reuse the same rendering path. Versioned-package resolution only:
-- every organization eligible for Website Chat is already on a package version assignment.
create or replace function private.effective_website_chat_widgets_limit(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  state text,
  value integer,
  is_unlimited boolean,
  source text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  assignment_package_version_id uuid;
  override_limit_state text;
  override_limit_value integer;
  override_is_unlimited boolean;
  override_found boolean;
  package_limit_state text;
  package_limit_value integer;
  package_found boolean;
begin
  select assignment.package_version_id
  into assignment_package_version_id
  from public.organization_package_assignments as assignment
  where assignment.organization_id = target_organization_id
  order by assignment.effective_at desc, assignment.id desc
  limit 1;

  select override.limit_state, override.limit_value, override.is_unlimited
  into override_limit_state, override_limit_value, override_is_unlimited
  from public.organization_limit_overrides as override
  where override.organization_id = target_organization_id
    and override.limit_key = 'website_chat_widgets'
    and override.starts_at <= at
    and (override.expires_at is null or override.expires_at > at);
  override_found := found;

  if assignment_package_version_id is not null then
    select version_limit.limit_state, version_limit.limit_value
    into package_limit_state, package_limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = assignment_package_version_id
      and version_limit.limit_key = 'website_chat_widgets';
    package_found := found;
  else
    package_found := false;
  end if;

  if override_found then
    state := override_limit_state;
    value := override_limit_value;
    is_unlimited := override_is_unlimited;
  elsif package_found then
    state := package_limit_state;
    value := case when package_limit_state = 'numeric' then package_limit_value else null end;
    is_unlimited := package_limit_state = 'unlimited';
  else
    state := 'not_included';
    value := null;
    is_unlimited := false;
  end if;

  source := case when override_found then 'override' else 'package' end;

  return next;
  return;
end;
$function$;

comment on function private.effective_website_chat_widgets_limit(uuid, timestamptz) is
  'Single authority for the website_chat_widgets limit. Mirrors effective_employee_seat_limit.';

revoke all on function private.effective_website_chat_widgets_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function private.effective_website_chat_widgets_limit(uuid, timestamptz) to authenticated;

-- Owner-only read model for the accepted-conversations allowance, shaped like
-- get_organization_communication_email_allowances so WebsiteChatAllowanceActions.svelte can be a
-- direct structural copy of EmailAllowanceActions.svelte. No period table exists yet -- period
-- fields are always null until later work opens a real usage period; the UI already renders that
-- as "not opened" for the email allowances today.
create or replace function public.get_organization_communication_website_chat_allowance(
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
set search_path = pg_catalog, public
as $$
  with current_assignment as (
    select assignment.package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = target_organization_id and assignment.effective_at <= at
    order by assignment.effective_at desc, assignment.id desc
    limit 1
  ), package_limit as (
    select version_limit.limit_state, version_limit.limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = (select package_version_id from current_assignment)
      and version_limit.limit_key = 'website_chat_accepted_conversations'
  ), stored_override as (
    select override.limit_state, override.limit_value, override.starts_at, override.expires_at,
      override.reason, override.actor_owner_email,
      override.starts_at <= at and (override.expires_at is null or override.expires_at > at) as is_active
    from public.organization_limit_overrides as override
    where override.organization_id = target_organization_id
      and override.limit_key = 'website_chat_accepted_conversations'
  )
  select
    'website_chat_accepted_conversations'::text,
    null::uuid,
    null::timestamptz,
    null::timestamptz,
    coalesce(case when stored_override.is_active then stored_override.limit_state end, package_limit.limit_state, 'not_included'),
    case when stored_override.is_active then stored_override.limit_value else package_limit.limit_value end,
    case when stored_override.is_active then 'override' else 'package' end,
    package_limit.limit_state,
    package_limit.limit_value,
    stored_override.limit_state,
    stored_override.limit_value,
    stored_override.starts_at,
    stored_override.expires_at,
    stored_override.reason,
    stored_override.actor_owner_email
  from (select 1) as one
  left join package_limit on true
  left join stored_override on true;
$$;

revoke all on function public.get_organization_communication_website_chat_allowance(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.get_organization_communication_website_chat_allowance(uuid, timestamptz) to service_role;

-- Owner-managed package defaults for both Website Chat limits together, mirroring
-- manage_platform_package_email_allowances exactly.
create or replace function public.manage_platform_package_website_chat_limits(
  target_version_id uuid,
  target_widgets_state text,
  target_widgets_value integer,
  target_accepted_conversations_state text,
  target_accepted_conversations_value integer,
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
  if target_widgets_state not in ('unlimited', 'not_included', 'numeric')
    or target_accepted_conversations_state not in ('unlimited', 'not_included', 'numeric') then
    raise exception 'Choose a valid Website Chat limit type.' using errcode = 'check_violation';
  end if;
  if (target_widgets_state = 'numeric' and coalesce(target_widgets_value, 0) < 0)
    or (target_widgets_state <> 'numeric' and target_widgets_value is not null)
    or (target_accepted_conversations_state = 'numeric' and coalesce(target_accepted_conversations_value, 0) < 0)
    or (target_accepted_conversations_state <> 'numeric' and target_accepted_conversations_value is not null) then
    raise exception 'A numeric Website Chat limit must be zero or greater.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.platform_package_versions
  where id = target_version_id
  for update;
  if not found or version_row.status <> 'draft' then
    raise exception 'Website Chat limits can only be changed on a draft package version.' using errcode = 'check_violation';
  end if;

  delete from public.platform_package_version_limits
  where package_version_id = version_row.id
    and limit_key in ('website_chat_widgets', 'website_chat_accepted_conversations');

  insert into public.platform_package_version_limits (package_version_id, limit_key, limit_state, limit_value)
  values
    (version_row.id, 'website_chat_widgets', target_widgets_state,
      case when target_widgets_state = 'numeric' then target_widgets_value end),
    (version_row.id, 'website_chat_accepted_conversations', target_accepted_conversations_state,
      case when target_accepted_conversations_state = 'numeric' then target_accepted_conversations_value end);

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    lower(trim(actor_email)), 'package.website_chat_limits_changed', 'platform_package_version', version_row.id::text,
    jsonb_build_object(
      'widgets_state', target_widgets_state, 'widgets_value', target_widgets_value,
      'accepted_conversations_state', target_accepted_conversations_state,
      'accepted_conversations_value', target_accepted_conversations_value
    )
  );
  return version_row.id;
end;
$$;

revoke all on function public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text)
  to service_role;

comment on function public.apply_organization_limit_exception(uuid, text, text, integer, timestamptz, timestamptz, text, text, text, timestamptz)
  is 'Atomically changes a limit exception projection and records immutable reasoned history.';
comment on function public.get_organization_communication_website_chat_allowance(uuid, timestamptz)
  is 'Owner-only read model for the website_chat_accepted_conversations allowance. Period fields are null until real usage periods exist.';
comment on function public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text)
  is 'Owner-managed draft-only write for the two Website Chat package limits.';
