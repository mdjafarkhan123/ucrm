-- Organization commercial-control foundation.
--
-- One trustworthy database seam for organization commercial state. Owner routes submit commands
-- through public.apply_organization_commercial_command; the database owns locking, validation,
-- immutable private history, the current projection, and the contractor-safe stream.
--
-- Three separated concerns:
--   organization_commercial_settings -- owner-controlled commercial timezone (never the contractor one)
--   organization_commercial_events   -- immutable private history with reasons and references
--   organization_commercial_state    -- serialized current paid-through and grace projection
--   organization_safe_events         -- immutable contractor-safe outcomes, written atomically

-- ---------------------------------------------------------------------------
-- Commercial timezone
-- ---------------------------------------------------------------------------

create table public.organization_commercial_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  commercial_timezone text not null check (char_length(trim(commercial_timezone)) between 1 and 64),
  timezone_source text not null default 'imported_operational' check (
    timezone_source in ('imported_operational', 'owner_set')
  ),
  imported_operational_timezone text,
  imported_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_commercial_settings_import_pair_check check (
    (imported_operational_timezone is null) = (imported_at is null)
  ),
  constraint organization_commercial_settings_import_trace_check check (
    timezone_source <> 'imported_operational'
    or (imported_operational_timezone is not null and imported_at is not null)
  )
);

create trigger organization_commercial_settings_set_updated_at
before update on public.organization_commercial_settings
for each row execute function public.set_updated_at();

create or replace function private.validate_organization_commercial_timezone()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1 from pg_catalog.pg_timezone_names as zone where zone.name = new.commercial_timezone
  ) then
    raise exception 'Commercial timezone % is not a recognised timezone.', new.commercial_timezone
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_organization_commercial_timezone() from public;

create trigger organization_commercial_settings_validate_timezone
before insert or update on public.organization_commercial_settings
for each row execute function private.validate_organization_commercial_timezone();

-- Grace ends at the end of the seventh calendar day after the paid-through day, measured in the
-- commercial timezone. The end of day (paid_through + 7) is the start of day (paid_through + 8),
-- which the timezone conversion resolves correctly across DST transitions.
create or replace function private.organization_grace_ends_at(
  paid_through date,
  commercial_timezone text
)
returns timestamptz
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when paid_through is null then null
    else ((paid_through + 8)::timestamp) at time zone commercial_timezone
  end;
$$;

revoke all on function private.organization_grace_ends_at(date, text) from public;

-- ---------------------------------------------------------------------------
-- Immutable private commercial events
-- ---------------------------------------------------------------------------

create table public.organization_commercial_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_kind text not null check (
    event_kind in (
      'initial_payment_confirmed',
      'renewal_confirmed',
      'payment_correction_recorded',
      'refund_recorded',
      'payment_reversal_recorded',
      'paid_through_adjusted',
      'commercial_timezone_changed',
      'free_access_granted',
      'free_access_extended',
      'free_access_converted_forever',
      'free_access_ended',
      'organization_suspended',
      'organization_reactivated',
      'pending_setup_resolved'
    )
  ),
  occurred_at timestamptz not null default now(),
  actor_kind text not null default 'platform_owner' check (actor_kind = 'platform_owner'),
  actor_owner_email text check (
    actor_owner_email is null or char_length(trim(actor_owner_email)) between 3 and 320
  ),
  summary text not null check (char_length(trim(summary)) between 1 and 300),
  private_reason text check (
    private_reason is null or char_length(trim(private_reason)) between 1 and 1000
  ),
  private_reference text check (
    private_reference is null or char_length(trim(private_reference)) between 1 and 240
  ),
  amount_usd_cents integer check (amount_usd_cents is null or amount_usd_cents <> 0),
  original_confirmation_id uuid references public.organization_payment_confirmations(id),
  source_event_id uuid references public.organization_commercial_events(id),
  suspension_category text check (
    suspension_category in ('nonpayment', 'payment_dispute', 'security', 'support', 'other')
  ),
  is_legacy_import boolean not null default false,
  paid_through_effect text not null check (paid_through_effect in ('set', 'unchanged')),
  paid_through_before date,
  paid_through_after date,
  commercial_timezone_before text,
  commercial_timezone_after text,
  deadline_recalculated boolean not null default false,
  grace_ends_at_after timestamptz,
  idempotency_key text not null check (char_length(trim(idempotency_key)) between 8 and 200),
  created_at timestamptz not null default now(),
  constraint organization_commercial_events_paid_through_result_check check (
    (paid_through_effect = 'set' and paid_through_after is not null)
    or (paid_through_effect = 'unchanged' and paid_through_after is not distinct from paid_through_before)
  ),
  -- Every adjustment points back at the initial-payment or renewal confirmation it corrects.
  constraint organization_commercial_events_adjustment_origin_check check (
    event_kind not in ('payment_correction_recorded', 'refund_recorded', 'payment_reversal_recorded')
    or original_confirmation_id is not null
  ),
  constraint organization_commercial_events_suspension_check check (
    (event_kind = 'organization_suspended') = (suspension_category is not null)
  ),
  -- Reasonless exceptions are only tolerated on rows explicitly marked as legacy imports.
  constraint organization_commercial_events_reason_check check (
    is_legacy_import
    or event_kind not in (
      'organization_suspended',
      'organization_reactivated',
      'paid_through_adjusted',
      'refund_recorded',
      'payment_reversal_recorded',
      'payment_correction_recorded',
      'commercial_timezone_changed',
      'pending_setup_resolved'
    )
    or char_length(trim(coalesce(private_reason, ''))) > 0
  ),
  constraint organization_commercial_events_timezone_change_check check (
    event_kind <> 'commercial_timezone_changed'
    or (
      commercial_timezone_before is not null
      and commercial_timezone_after is not null
      and commercial_timezone_before <> commercial_timezone_after
    )
  ),
  constraint organization_commercial_events_deadline_recalculated_check check (
    not deadline_recalculated or event_kind = 'commercial_timezone_changed'
  ),
  constraint organization_commercial_events_self_source_check check (source_event_id <> id),
  constraint organization_commercial_events_idempotency_unique unique (organization_id, idempotency_key)
);

create index organization_commercial_events_history_idx
  on public.organization_commercial_events (organization_id, occurred_at desc, id desc);

create index organization_commercial_events_original_confirmation_idx
  on public.organization_commercial_events (original_confirmation_id)
  where original_confirmation_id is not null;

create index organization_commercial_events_source_event_idx
  on public.organization_commercial_events (source_event_id)
  where source_event_id is not null;

create or replace function private.validate_organization_commercial_event()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.occurred_at > now() then
    raise exception 'Commercial events cannot be dated in the future.'
      using errcode = 'check_violation';
  end if;

  if new.original_confirmation_id is not null and not exists (
    select 1
    from public.organization_payment_confirmations as confirmation
    where confirmation.id = new.original_confirmation_id
      and confirmation.organization_id = new.organization_id
  ) then
    raise exception 'A commercial adjustment must reference a confirmation for the same organization.'
      using errcode = 'check_violation';
  end if;

  if new.source_event_id is not null and not exists (
    select 1
    from public.organization_commercial_events as source
    where source.id = new.source_event_id
      and source.organization_id = new.organization_id
  ) then
    raise exception 'A commercial event must reference a source event for the same organization.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_organization_commercial_event() from public;

create trigger organization_commercial_events_validate
before insert on public.organization_commercial_events
for each row execute function private.validate_organization_commercial_event();

create or replace function private.prevent_organization_commercial_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Commercial history is append-only.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_organization_commercial_event_mutation() from public;

create trigger organization_commercial_events_immutable
before update or delete on public.organization_commercial_events
for each row execute function private.prevent_organization_commercial_event_mutation();

-- ---------------------------------------------------------------------------
-- Contractor-safe events
-- ---------------------------------------------------------------------------

create or replace function private.organization_safe_event_payload_is_allowed(payload jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(
    bool_and(
      payload_key in (
        'paid_through_date',
        'grace_ends_at',
        'access_status',
        'effective_at',
        'package_display_name',
        'free_access_until_date',
        'commercial_timezone'
      )
      and jsonb_typeof(payload -> payload_key) in ('string', 'number', 'boolean', 'null')
    ),
    true
  )
  from jsonb_object_keys(payload) as payload_key;
$$;

revoke all on function private.organization_safe_event_payload_is_allowed(jsonb) from public;
grant execute on function private.organization_safe_event_payload_is_allowed(jsonb) to authenticated, service_role;

create table public.organization_safe_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  commercial_event_id uuid not null unique references public.organization_commercial_events(id),
  safe_kind text not null check (
    safe_kind in (
      'payment_recorded',
      'renewal_recorded',
      'access_period_updated',
      'account_suspended',
      'account_reactivated',
      'free_access_updated',
      'commercial_timezone_updated'
    )
  ),
  safe_payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint organization_safe_events_payload_object_check check (jsonb_typeof(safe_payload) = 'object'),
  constraint organization_safe_events_payload_allowlist_check check (
    private.organization_safe_event_payload_is_allowed(safe_payload)
  )
);

create index organization_safe_events_history_idx
  on public.organization_safe_events (organization_id, occurred_at desc, id desc);

create or replace function private.prevent_organization_safe_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Contractor-safe history is append-only.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_organization_safe_event_mutation() from public;

create trigger organization_safe_events_immutable
before update or delete on public.organization_safe_events
for each row execute function private.prevent_organization_safe_event_mutation();

-- ---------------------------------------------------------------------------
-- Serialized current projection
-- ---------------------------------------------------------------------------

create table public.organization_commercial_state (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  paid_through_date date,
  paid_through_source text check (
    paid_through_source in (
      'legacy_owner_action',
      'provisioning',
      'renewal',
      'manual_correction',
      'refund',
      'reversal'
    )
  ),
  grace_ends_at timestamptz,
  grace_basis_timezone text,
  last_event_id uuid references public.organization_commercial_events(id),
  state_version bigint not null default 0 check (state_version >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_commercial_state_paid_through_state_check check (
    (paid_through_date is null and paid_through_source is null)
    or (paid_through_date is not null and paid_through_source is not null)
  ),
  constraint organization_commercial_state_grace_state_check check (
    (paid_through_date is null and grace_ends_at is null and grace_basis_timezone is null)
    or (paid_through_date is not null and grace_ends_at is not null and grace_basis_timezone is not null)
  )
);

create trigger organization_commercial_state_set_updated_at
before update on public.organization_commercial_state
for each row execute function public.set_updated_at();

create index organization_commercial_state_paid_through_idx
  on public.organization_commercial_state (paid_through_date, organization_id)
  where paid_through_date is not null;

create index organization_commercial_state_attention_idx
  on public.organization_commercial_state (grace_ends_at, organization_id)
  where grace_ends_at is not null;

create index organization_commercial_state_last_event_idx
  on public.organization_commercial_state (last_event_id)
  where last_event_id is not null;

-- ---------------------------------------------------------------------------
-- Command seam
-- ---------------------------------------------------------------------------

-- Creates the commercial rows on first use. The commercial timezone baseline is imported once from
-- the contractor operational timezone and then stays independent of later operational changes.
create or replace function private.ensure_organization_commercial_rows(target_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  operational_timezone text;
  baseline_timezone text;
begin
  if not exists (select 1 from public.organizations where id = target_organization_id) then
    raise exception 'Organization % was not found.', target_organization_id
      using errcode = 'foreign_key_violation';
  end if;

  select settings.timezone
  into operational_timezone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;

  baseline_timezone := coalesce(nullif(trim(coalesce(operational_timezone, '')), ''), 'UTC');
  if not exists (
    select 1 from pg_catalog.pg_timezone_names as zone where zone.name = baseline_timezone
  ) then
    baseline_timezone := 'UTC';
  end if;

  insert into public.organization_commercial_settings (
    organization_id,
    commercial_timezone,
    timezone_source,
    imported_operational_timezone,
    imported_at
  )
  values (
    target_organization_id,
    baseline_timezone,
    'imported_operational',
    baseline_timezone,
    now()
  )
  on conflict (organization_id) do nothing;

  insert into public.organization_commercial_state (organization_id)
  values (target_organization_id)
  on conflict (organization_id) do nothing;
end;
$$;

revoke all on function private.ensure_organization_commercial_rows(uuid) from public;

comment on function private.ensure_organization_commercial_rows(uuid) is
  'Creates the commercial settings and projection rows for an organization, importing the operational timezone once as the commercial baseline.';

-- The single write seam. One call either writes the private event, the projection change, and the
-- contractor-safe event together, or writes none of them.
create or replace function public.apply_organization_commercial_command(
  target_organization_id uuid,
  event_kind text,
  idempotency_key text,
  summary text,
  paid_through_effect text,
  paid_through_date date default null,
  actor_owner_email text default null,
  occurred_at timestamptz default now(),
  private_reason text default null,
  private_reference text default null,
  amount_usd_cents integer default null,
  original_confirmation_id uuid default null,
  source_event_id uuid default null,
  suspension_category text default null,
  commercial_timezone text default null,
  recalculate_deadline boolean default false,
  is_legacy_import boolean default false,
  safe_kind text default null,
  safe_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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
      using errcode = 'serialization_failure';
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
$$;

revoke all on function public.apply_organization_commercial_command(
  uuid, text, text, text, text, date, text, timestamptz, text, text, integer, uuid, uuid, text, text,
  boolean, boolean, text, jsonb
) from public, anon, authenticated;

grant execute on function public.apply_organization_commercial_command(
  uuid, text, text, text, text, date, text, timestamptz, text, text, integer, uuid, uuid, text, text,
  boolean, boolean, text, jsonb
) to service_role;

comment on function public.apply_organization_commercial_command(
  uuid, text, text, text, text, date, text, timestamptz, text, text, integer, uuid, uuid, text, text,
  boolean, boolean, text, jsonb
) is
  'Applies one owner commercial command atomically: private event, current projection, and contractor-safe event. Idempotent per organization and idempotency key.';

-- ---------------------------------------------------------------------------
-- Row level security and privileges
-- ---------------------------------------------------------------------------

alter table public.organization_commercial_settings enable row level security;
alter table public.organization_commercial_events enable row level security;
alter table public.organization_commercial_state enable row level security;
alter table public.organization_safe_events enable row level security;

revoke all on public.organization_commercial_settings from anon, authenticated;
revoke all on public.organization_commercial_events from anon, authenticated;
revoke all on public.organization_commercial_state from anon, authenticated;
revoke all on public.organization_safe_events from anon, authenticated;

grant select, insert, update on public.organization_commercial_settings to service_role;
grant select, insert on public.organization_commercial_events to service_role;
grant select, insert, update on public.organization_commercial_state to service_role;
grant select, insert on public.organization_safe_events to service_role;

-- Contractors read only the safe stream, and only for their own organization.
grant select on public.organization_safe_events to authenticated;

create policy "members can view safe organization events"
on public.organization_safe_events for select to authenticated
using (private.is_organization_member(organization_id));

-- ---------------------------------------------------------------------------
-- One-time baseline import
-- ---------------------------------------------------------------------------

insert into public.organization_commercial_settings (
  organization_id,
  commercial_timezone,
  timezone_source,
  imported_operational_timezone,
  imported_at
)
select
  organization.id,
  coalesce(valid_zone.name, 'UTC'),
  'imported_operational',
  coalesce(valid_zone.name, 'UTC'),
  now()
from public.organizations as organization
left join public.organization_settings as settings
  on settings.organization_id = organization.id
left join lateral (
  select zone.name
  from pg_catalog.pg_timezone_names as zone
  where zone.name = nullif(trim(coalesce(settings.timezone, '')), '')
  limit 1
) as valid_zone on true
on conflict (organization_id) do nothing;

insert into public.organization_commercial_state (
  organization_id,
  paid_through_date,
  paid_through_source,
  grace_ends_at,
  grace_basis_timezone
)
select
  organization.id,
  billing.paid_through_date,
  billing.paid_through_source,
  private.organization_grace_ends_at(billing.paid_through_date, commercial.commercial_timezone),
  case when billing.paid_through_date is null then null else commercial.commercial_timezone end
from public.organizations as organization
join public.organization_commercial_settings as commercial
  on commercial.organization_id = organization.id
left join public.organization_billing_accounts as billing
  on billing.organization_id = organization.id
on conflict (organization_id) do nothing;
