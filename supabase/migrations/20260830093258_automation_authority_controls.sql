-- Contractor Settings Part 6B, slice 3 (foundation): Platform Owner Automation authority.
--
-- docs/automation-behavior-contract.md § Entitlement, permissions, and commands: "Automation authority
-- is distinct from entitlement. Its platform-controlled state is Enabled, Operationally disabled, or
-- Security suspended, with a safe reason and audit." The two conditions are independent axes -- a
-- security suspension outranks an operational disable -- and both fail writes closed while read-only
-- history is retained.
--
-- Shape follows the Website Chat authority pattern (20260908130000): an append-only, service-only event
-- stream is the immutable history, and a small current-state projection is what enforcement reads. Here
-- the projection is its own one-row-per-organization table (Website Chat reused website_chat_widgets),
-- because it must be readable by an organization member -- the contractor access module reads it under
-- RLS -- while the reasoned history stays owner-only.

-- Current-state projection: one row per organization, member-readable. Absent row = fully enabled. ------
create table public.organization_automation_authority (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  operational_state text not null default 'enabled' check (operational_state in ('enabled', 'disabled')),
  security_state text not null default 'active' check (security_state in ('active', 'suspended')),
  operational_reason text check (operational_reason is null or char_length(btrim(operational_reason)) between 3 and 500),
  security_reason text check (security_reason is null or char_length(btrim(security_reason)) between 3 and 500),
  operational_changed_at timestamptz,
  security_changed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint organization_automation_authority_operational_reason_state_check
    check ((operational_state = 'disabled') = (operational_reason is not null)),
  constraint organization_automation_authority_security_reason_state_check
    check ((security_state = 'suspended') = (security_reason is not null))
);

create trigger organization_automation_authority_set_updated_at
before update on public.organization_automation_authority
for each row execute function public.set_updated_at();

-- Append-only reasoned history, owner-only. ------------------------------------------------------------
create table public.automation_authority_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  axis text not null check (axis in ('operational', 'security')),
  event_kind text not null check (event_kind in (
    'operational_disable_engaged', 'operational_disable_released',
    'security_suspension_engaged', 'security_suspension_released'
  )),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  actor_owner_email text not null check (char_length(btrim(actor_owner_email)) between 3 and 320),
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  constraint automation_authority_events_idempotency_key unique (organization_id, idempotency_key)
);

create index automation_authority_events_org_history_idx
  on public.automation_authority_events (organization_id, created_at desc, id desc);

alter table public.organization_automation_authority enable row level security;
alter table public.automation_authority_events enable row level security;

create policy "members can view their organization automation authority"
on public.organization_automation_authority for select to authenticated
using (private.is_organization_member(organization_id));

revoke all on public.organization_automation_authority from anon, authenticated;
grant select on public.organization_automation_authority to authenticated;
grant select, insert, update on public.organization_automation_authority to service_role;

revoke all on public.automation_authority_events from anon, authenticated;
grant select, insert on public.automation_authority_events to service_role;

-- Owner writer: engage or release one axis, idempotent, advisory-locked, audited. ----------------------
create or replace function public.set_organization_automation_authority(
  p_organization_id uuid,
  p_axis text,
  p_engage boolean,
  p_reason text,
  p_actor_email text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_reason text := btrim(coalesce(p_reason, ''));
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  existing_event public.automation_authority_events%rowtype;
  authority public.organization_automation_authority%rowtype;
  inserted_event public.automation_authority_events%rowtype;
  current_engaged boolean;
  event_kind text;
  before_json jsonb;
  after_json jsonb;
begin
  if p_axis not in ('operational', 'security') then
    raise exception 'An automation authority axis of operational or security is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.organizations where id = p_organization_id) then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('automation-authority:' || p_organization_id::text));

  select * into existing_event
  from public.automation_authority_events
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id);
  end if;

  insert into public.organization_automation_authority (organization_id)
  values (p_organization_id)
  on conflict (organization_id) do nothing;

  select * into authority
  from public.organization_automation_authority
  where organization_id = p_organization_id
  for update;

  current_engaged := case p_axis
    when 'operational' then authority.operational_state = 'disabled'
    else authority.security_state = 'suspended'
  end;

  before_json := jsonb_build_object(
    'operational_state', authority.operational_state, 'security_state', authority.security_state
  );

  if current_engaged = p_engage then
    return jsonb_build_object('applied', false, 'no_change', true,
      'operational_state', authority.operational_state, 'security_state', authority.security_state);
  end if;

  if p_axis = 'operational' then
    update public.organization_automation_authority
    set operational_state = case when p_engage then 'disabled' else 'enabled' end,
        operational_reason = case when p_engage then clean_reason else null end,
        operational_changed_at = now()
    where organization_id = p_organization_id
    returning * into authority;
    event_kind := case when p_engage then 'operational_disable_engaged' else 'operational_disable_released' end;
  else
    update public.organization_automation_authority
    set security_state = case when p_engage then 'suspended' else 'active' end,
        security_reason = case when p_engage then clean_reason else null end,
        security_changed_at = now()
    where organization_id = p_organization_id
    returning * into authority;
    event_kind := case when p_engage then 'security_suspension_engaged' else 'security_suspension_released' end;
  end if;

  after_json := jsonb_build_object(
    'operational_state', authority.operational_state, 'security_state', authority.security_state
  );

  insert into public.automation_authority_events (
    organization_id, axis, event_kind, reason, actor_owner_email, before_state, after_state, idempotency_key
  ) values (
    p_organization_id, p_axis, event_kind, clean_reason, actor, before_json, after_json, p_idempotency_key
  ) returning * into inserted_event;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'automations.authority_' || event_kind, 'organization', p_organization_id::text,
    before_json, after_json || jsonb_build_object('reason', clean_reason, 'authority_event_id', inserted_event.id)
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id,
    'operational_state', authority.operational_state, 'security_state', authority.security_state);
end;
$$;

revoke all on function public.set_organization_automation_authority(uuid, text, boolean, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.set_organization_automation_authority(uuid, text, boolean, text, text, uuid)
  to service_role;

comment on function public.set_organization_automation_authority(uuid, text, boolean, text, text, uuid) is
  'Owner-only writer for one Automation authority axis (operational|security). Idempotent, advisory-locked, audited.';

-- Owner read model for the organization detail surface: current state plus recent reasoned history. -----
create or replace function public.get_organization_automation_authority(
  p_organization_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'operational_state', coalesce(authority.operational_state, 'enabled'),
    'security_state', coalesce(authority.security_state, 'active'),
    'operational_reason', authority.operational_reason,
    'security_reason', authority.security_reason,
    'operational_changed_at', authority.operational_changed_at,
    'security_changed_at', authority.security_changed_at,
    'recent_events', coalesce((
      select jsonb_agg(to_jsonb(history) order by history.created_at desc, history.id desc)
      from (
        select id, axis, event_kind, reason, actor_owner_email, created_at
        from public.automation_authority_events
        where organization_id = p_organization_id
        order by created_at desc, id desc
        limit 20
      ) history
    ), '[]'::jsonb)
  )
  from (select 1) as one
  left join public.organization_automation_authority as authority
    on authority.organization_id = p_organization_id;
$$;

revoke all on function public.get_organization_automation_authority(uuid)
  from public, anon, authenticated;
grant execute on function public.get_organization_automation_authority(uuid) to service_role;

comment on function public.get_organization_automation_authority(uuid) is
  'Owner-only read model: current Automation authority state and recent reasoned history for one organization.';
