-- Communications A2 / Stage 2C (part 3): SMS readiness and registration.
--
-- Approved behavior (docs/research/communications-a2-stage6-settings-owner-controls-plan.md, 2026-09-12,
-- "Readiness summary" + "Jafar: organization controls"; ROADMAP "Stage 2C parts / 2C-3"). This part stores the
-- data behind the plain readiness states a contractor sees and Jafar manages, without exposing provider codes:
--
--   * supported sender capabilities  — what each assigned business number can do (country, sender type,
--     SMS/MMS/Voice) and the registration it belongs to. Stored on the existing sender-identity record.
--   * registration submission + history — one current A2P/toll-free registration per (org, country, sender
--     type, use case), plus an append-only, immutable history of every submission, provider outcome and check.
--   * effective SMS mode — the org's chosen mode, capped by its package maximum, overridable only by Jafar. No
--     configured mode means SMS is not included (off) until Jafar enables it.
--   * country readiness — a computed plain state (not_included / needs_setup / waiting_for_info / under_review /
--     action_needed / finishing_setup / ready) derived from the above. It is computed on read, never stored, so
--     it can never go stale. The 'outbound_paused' state is a hold and belongs to Stage 2C part 4, not here; per
--     message live gates (consent, balance, quiet hours) stay separate runtime checks.
--
-- A2 supports operational one-to-one and automated SMS only, so the SMS mode is 'off' or 'operational'; a
-- marketing mode is out of A2 scope and will widen the enum in its own migration when it ships (same approach as
-- the retail-rate message unit). This part adds data + commands only; the owner /api layer and Jafar UI are
-- Stage 2C parts 5 and 6. Everything is server-owned: writes flow through the security-definer commands below and
-- the /api/* layer reads with service_role and scopes to the caller's organization, hiding provider detail.

-- ---------------------------------------------------------------------------------------------------------------
-- Registration: one current registration per (org, country, sender type, use case), with immutable history.
-- ---------------------------------------------------------------------------------------------------------------

create table public.communication_sms_registrations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  country_code text not null,
  sender_type text not null,
  use_case text not null,
  status text not null default 'waiting_for_info',
  -- Safe provider reference for the registration (e.g. a Twilio brand/campaign or toll-free verification SID).
  -- Never a secret; only an identifier used to look the registration up with the provider.
  provider_registration_sid text,
  -- The contractor attests the submitted business/messaging information is truthful before it is submitted.
  attested_by uuid,
  attested_at timestamptz,
  submitted_at timestamptz,
  -- The safe carrier/provider outcome text shown once a decision arrives; never a raw provider payload.
  provider_outcome text,
  -- The safe correction reasons a contractor must fix when the registration comes back as action_needed.
  required_fixes text,
  -- When the real provider readiness was last checked, so the page can show "last checked" without promising.
  last_checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_registrations_org_id_key unique (organization_id, id),
  -- One current registration per key. Re-submissions reuse this row; the history table keeps every attempt.
  constraint communication_sms_registrations_key
    unique (organization_id, country_code, sender_type, use_case),
  constraint communication_sms_registrations_country_check
    check (country_code ~ '^[A-Z]{2}$'),
  constraint communication_sms_registrations_sender_type_check
    check (sender_type in ('long_code', 'toll_free', 'short_code', 'alphanumeric')),
  constraint communication_sms_registrations_use_case_check
    check (char_length(trim(use_case)) between 1 and 200),
  constraint communication_sms_registrations_status_check
    check (status in ('waiting_for_info', 'under_review', 'action_needed', 'approved')),
  constraint communication_sms_registrations_provider_sid_check
    check (provider_registration_sid is null or char_length(trim(provider_registration_sid)) between 1 and 100),
  constraint communication_sms_registrations_outcome_check
    check (provider_outcome is null or char_length(provider_outcome) <= 2000),
  constraint communication_sms_registrations_fixes_check
    check (required_fixes is null or char_length(required_fixes) <= 2000),
  constraint communication_sms_registrations_attestation_check
    check ((attested_at is null) = (attested_by is null)),
  -- Each status carries exactly the evidence it should. A submitted registration is always attested; an
  -- action_needed registration always names the fixes; an approved registration always records the outcome.
  constraint communication_sms_registrations_lifecycle_check check (
    (status = 'waiting_for_info'
      and submitted_at is null and provider_outcome is null and required_fixes is null)
    or (status = 'under_review'
      and submitted_at is not null and attested_at is not null and required_fixes is null)
    or (status = 'action_needed'
      and submitted_at is not null and attested_at is not null and required_fixes is not null)
    or (status = 'approved'
      and submitted_at is not null and attested_at is not null and provider_outcome is not null)
  )
);

-- Bounded, ordered listing of a single organization's registrations (contractor page + Jafar Integrations).
create index communication_sms_registrations_org_idx
  on public.communication_sms_registrations (organization_id, country_code, sender_type, use_case);

comment on table public.communication_sms_registrations is
  'Current SMS sender registration per (org, country, sender type, use case). Drives the plain readiness state; '
  're-submissions reuse the row and communication_sms_registration_events keeps the immutable history. '
  'Server-owned; writes via the communication_sms_*_registration commands only.';

-- Append-only, immutable history of registration attempts, provider outcomes and readiness checks.
create table public.communication_sms_registration_events (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null,
  organization_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  detail text,
  provider_outcome text,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint communication_sms_registration_events_registration_fk
    foreign key (organization_id, registration_id)
    references public.communication_sms_registrations (organization_id, id) on delete cascade,
  constraint communication_sms_registration_events_type_check
    check (event_type in ('started', 'info_updated', 'submitted', 'resubmitted',
                          'approved', 'action_needed', 'readiness_checked')),
  constraint communication_sms_registration_events_detail_check
    check (detail is null or char_length(detail) <= 2000),
  constraint communication_sms_registration_events_outcome_check
    check (provider_outcome is null or char_length(provider_outcome) <= 2000)
);

create index communication_sms_registration_events_history_idx
  on public.communication_sms_registration_events (organization_id, registration_id, created_at desc, id desc);

comment on table public.communication_sms_registration_events is
  'Immutable, append-only history of SMS registration submissions, provider outcomes and readiness checks. '
  'Server-owned; service_role may read and insert but never update or delete a history row.';

-- ---------------------------------------------------------------------------------------------------------------
-- Supported sender capabilities: what each assigned business number can do, and its registration.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_sender_identities
  add column country_code text,
  add column sender_type text,
  add column capable_sms boolean not null default false,
  add column capable_mms boolean not null default false,
  add column capable_voice boolean not null default false,
  add column registration_id uuid,
  add constraint communication_sms_sender_identities_country_check
    check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  add constraint communication_sms_sender_identities_sender_type_check
    check (sender_type is null or sender_type in ('long_code', 'toll_free', 'short_code', 'alphanumeric')),
  -- The registration must belong to the same organization as the number it covers.
  add constraint communication_sms_sender_identities_registration_fk
    foreign key (organization_id, registration_id)
    references public.communication_sms_registrations (organization_id, id) on delete set null;

-- Count live SMS-capable numbers attached to a registration (the "ready" test), org-scoped.
create index communication_sms_sender_identities_registration_idx
  on public.communication_sms_sender_identities (organization_id, registration_id)
  where registration_id is not null;

-- ---------------------------------------------------------------------------------------------------------------
-- Effective SMS mode: chosen mode capped by package maximum, overridable only by Jafar. No row means 'off'.
-- ---------------------------------------------------------------------------------------------------------------

create table public.communication_sms_org_modes (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  -- The ceiling the organization's package allows. The chosen mode can never exceed it.
  package_max_mode text not null default 'operational',
  -- The mode the contractor has chosen, within the package ceiling.
  chosen_mode text not null default 'operational',
  -- A reasoned Jafar override that takes precedence over the chosen/package result (up or down).
  override_mode text,
  override_reason text,
  set_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_org_modes_package_check check (package_max_mode in ('off', 'operational')),
  constraint communication_sms_org_modes_chosen_check check (chosen_mode in ('off', 'operational')),
  constraint communication_sms_org_modes_override_check
    check (override_mode is null or override_mode in ('off', 'operational')),
  constraint communication_sms_org_modes_override_reason_check
    check (override_reason is null or char_length(override_reason) <= 2000)
);

comment on table public.communication_sms_org_modes is
  'Per-organization SMS mode inputs: package ceiling, contractor choice and an optional Jafar override. The '
  'effective mode is derived by communication_sms_effective_mode; a missing row means SMS is off (not included).';

-- ---------------------------------------------------------------------------------------------------------------
-- Commands (security definer). All writes to the tables above happen only through these.
-- ---------------------------------------------------------------------------------------------------------------

-- Start (or reopen) a registration. Creates the current row in waiting_for_info and logs the start; if the row
-- already exists it only records that its information was updated, so a repeated start never loses history.
create or replace function public.communication_sms_start_registration(
  p_organization_id uuid,
  p_country_code text,
  p_sender_type text,
  p_use_case text,
  p_actor uuid default null
) returns public.communication_sms_registrations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reg public.communication_sms_registrations;
  existed boolean := false;
begin
  select * into reg
  from public.communication_sms_registrations
  where organization_id = p_organization_id
    and country_code = p_country_code
    and sender_type = p_sender_type
    and use_case = p_use_case
  for update;

  existed := found;

  if not existed then
    insert into public.communication_sms_registrations (
      organization_id, country_code, sender_type, use_case
    ) values (
      p_organization_id, p_country_code, p_sender_type, p_use_case
    )
    returning * into reg;
  else
    update public.communication_sms_registrations
    set updated_at = now()
    where id = reg.id
    returning * into reg;
  end if;

  insert into public.communication_sms_registration_events (
    registration_id, organization_id, event_type, to_status, created_by
  ) values (
    reg.id, reg.organization_id,
    case when existed then 'info_updated' else 'started' end,
    reg.status, p_actor
  );

  return reg;
end;
$$;

-- Attest and submit a registration for review. Allowed from waiting_for_info (first submission) or action_needed
-- (a corrected re-submission). Records the attestation and submission time and logs the (re)submission.
create or replace function public.communication_sms_submit_registration(
  p_registration_id uuid,
  p_attested_by uuid,
  p_provider_registration_sid text default null
) returns public.communication_sms_registrations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reg public.communication_sms_registrations;
  prior_status text;
begin
  if p_attested_by is null then
    raise exception 'a registration submission must be attested by a user' using errcode = 'P0001';
  end if;

  select * into reg
  from public.communication_sms_registrations
  where id = p_registration_id
  for update;

  if not found then
    raise exception 'registration % not found', p_registration_id using errcode = 'P0001';
  end if;
  if reg.status not in ('waiting_for_info', 'action_needed') then
    raise exception 'registration % is % and cannot be submitted', p_registration_id, reg.status
      using errcode = 'P0001';
  end if;

  prior_status := reg.status;

  update public.communication_sms_registrations
  set status = 'under_review',
      attested_by = p_attested_by,
      attested_at = now(),
      submitted_at = now(),
      provider_registration_sid = coalesce(p_provider_registration_sid, provider_registration_sid),
      required_fixes = null,
      updated_at = now()
  where id = reg.id
  returning * into reg;

  insert into public.communication_sms_registration_events (
    registration_id, organization_id, event_type, from_status, to_status, created_by
  ) values (
    reg.id, reg.organization_id,
    case when prior_status = 'action_needed' then 'resubmitted' else 'submitted' end,
    prior_status, reg.status, p_attested_by
  );

  return reg;
end;
$$;

-- Record the provider/carrier decision on a registration under review: approved with a safe outcome, or
-- action_needed with the safe fixes the contractor must correct. Only an under_review registration can be decided.
create or replace function public.communication_sms_record_registration_outcome(
  p_registration_id uuid,
  p_status text,
  p_decided_by uuid default null,
  p_provider_outcome text default null,
  p_required_fixes text default null
) returns public.communication_sms_registrations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reg public.communication_sms_registrations;
begin
  if p_status not in ('approved', 'action_needed') then
    raise exception 'a registration outcome must be approved or action_needed, not %', p_status
      using errcode = 'P0001';
  end if;
  if p_status = 'approved' and (p_provider_outcome is null or char_length(trim(p_provider_outcome)) = 0) then
    raise exception 'an approved registration must record a provider outcome' using errcode = 'P0001';
  end if;
  if p_status = 'action_needed' and (p_required_fixes is null or char_length(trim(p_required_fixes)) = 0) then
    raise exception 'an action_needed registration must record the required fixes' using errcode = 'P0001';
  end if;

  select * into reg
  from public.communication_sms_registrations
  where id = p_registration_id
  for update;

  if not found then
    raise exception 'registration % not found', p_registration_id using errcode = 'P0001';
  end if;
  if reg.status <> 'under_review' then
    raise exception 'registration % is % and has no pending review to decide', p_registration_id, reg.status
      using errcode = 'P0001';
  end if;

  update public.communication_sms_registrations
  set status = p_status,
      provider_outcome = case when p_status = 'approved' then p_provider_outcome else null end,
      required_fixes = case when p_status = 'action_needed' then p_required_fixes else null end,
      last_checked_at = now(),
      updated_at = now()
  where id = reg.id
  returning * into reg;

  insert into public.communication_sms_registration_events (
    registration_id, organization_id, event_type, from_status, to_status, provider_outcome, detail, created_by
  ) values (
    reg.id, reg.organization_id, p_status, 'under_review', reg.status,
    case when p_status = 'approved' then p_provider_outcome else null end,
    case when p_status = 'action_needed' then p_required_fixes else null end,
    p_decided_by
  );

  return reg;
end;
$$;

-- Record that the real provider readiness was checked, without changing the registration status. Logs the check
-- and refreshes last_checked_at so the page can show when readiness was last confirmed against the provider.
create or replace function public.communication_sms_record_registration_check(
  p_registration_id uuid,
  p_checked_by uuid default null,
  p_detail text default null
) returns public.communication_sms_registrations
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reg public.communication_sms_registrations;
begin
  update public.communication_sms_registrations
  set last_checked_at = now(),
      updated_at = now()
  where id = p_registration_id
  returning * into reg;

  if not found then
    raise exception 'registration % not found', p_registration_id using errcode = 'P0001';
  end if;

  insert into public.communication_sms_registration_events (
    registration_id, organization_id, event_type, from_status, to_status, detail, created_by
  ) values (
    reg.id, reg.organization_id, 'readiness_checked', reg.status, reg.status, p_detail, p_checked_by
  );

  return reg;
end;
$$;

-- Record the safe provider capabilities of an assigned business number, and optionally the registration it
-- belongs to. The registration must be in the same organization (enforced by the composite foreign key).
create or replace function public.communication_sms_set_sender_capabilities(
  p_sender_identity_id uuid,
  p_country_code text,
  p_sender_type text,
  p_capable_sms boolean,
  p_capable_mms boolean default false,
  p_capable_voice boolean default false,
  p_registration_id uuid default null
) returns public.communication_sms_sender_identities
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  sender public.communication_sms_sender_identities;
begin
  update public.communication_sms_sender_identities
  set country_code = p_country_code,
      sender_type = p_sender_type,
      capable_sms = coalesce(p_capable_sms, false),
      capable_mms = coalesce(p_capable_mms, false),
      capable_voice = coalesce(p_capable_voice, false),
      registration_id = p_registration_id,
      updated_at = now()
  where id = p_sender_identity_id
  returning * into sender;

  if not found then
    raise exception 'sender identity % not found', p_sender_identity_id using errcode = 'P0001';
  end if;

  return sender;
end;
$$;

-- Set an organization's SMS mode inputs. Any argument left null keeps its current value (or the table default on
-- first insert). A chosen mode above the package ceiling is refused; the Jafar override is the only way past it.
create or replace function public.communication_sms_set_org_mode(
  p_organization_id uuid,
  p_set_by uuid default null,
  p_package_max_mode text default null,
  p_chosen_mode text default null,
  p_override_mode text default null,
  p_override_reason text default null,
  p_clear_override boolean default false
) returns public.communication_sms_org_modes
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  mode public.communication_sms_org_modes;
  effective_package text;
  effective_chosen text;
begin
  insert into public.communication_sms_org_modes (organization_id, set_by)
  values (p_organization_id, p_set_by)
  on conflict (organization_id) do nothing;

  select * into mode
  from public.communication_sms_org_modes
  where organization_id = p_organization_id
  for update;

  effective_package := coalesce(p_package_max_mode, mode.package_max_mode);
  effective_chosen := coalesce(p_chosen_mode, mode.chosen_mode);

  -- 'off' < 'operational'. The contractor's chosen mode may not exceed the package ceiling.
  if effective_package = 'off' and effective_chosen = 'operational' then
    raise exception 'chosen SMS mode operational exceeds the package maximum off' using errcode = 'P0001';
  end if;

  update public.communication_sms_org_modes
  set package_max_mode = effective_package,
      chosen_mode = effective_chosen,
      override_mode = case
        when p_clear_override then null
        when p_override_mode is not null then p_override_mode
        else mode.override_mode
      end,
      override_reason = case
        when p_clear_override then null
        when p_override_mode is not null then p_override_reason
        else mode.override_reason
      end,
      set_by = coalesce(p_set_by, mode.set_by),
      updated_at = now()
  where organization_id = p_organization_id
  returning * into mode;

  return mode;
end;
$$;

-- The effective SMS mode for an organization: the Jafar override if set, otherwise the lesser of the chosen mode
-- and the package ceiling. No configured row means SMS is off (not included).
create or replace function public.communication_sms_effective_mode(
  p_organization_id uuid
) returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when m.organization_id is null then 'off'
    when m.override_mode is not null then m.override_mode
    when m.chosen_mode = 'off' or m.package_max_mode = 'off' then 'off'
    else 'operational'
  end
  from (select p_organization_id as org) q
  left join public.communication_sms_org_modes m on m.organization_id = q.org;
$$;

-- The plain readiness state for one (org, country, sender type, use case), computed from the effective mode, the
-- current registration and whether a live SMS-capable number is attached. Never stored, so it cannot go stale.
-- 'outbound_paused' (a hold) is Stage 2C part 4; per-message gates stay separate runtime checks.
create or replace function public.communication_sms_readiness(
  p_organization_id uuid,
  p_country_code text,
  p_sender_type text,
  p_use_case text
) returns table (
  readiness_state text,
  effective_mode text,
  registration_status text,
  live_sender_count integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  mode text := public.communication_sms_effective_mode(p_organization_id);
  reg public.communication_sms_registrations;
  live_count integer := 0;
begin
  effective_mode := mode;

  if mode = 'off' then
    readiness_state := 'not_included';
    registration_status := null;
    live_sender_count := 0;
    return next;
    return;
  end if;

  select * into reg
  from public.communication_sms_registrations
  where organization_id = p_organization_id
    and country_code = p_country_code
    and sender_type = p_sender_type
    and use_case = p_use_case;

  if not found then
    readiness_state := 'needs_setup';
    registration_status := null;
    live_sender_count := 0;
    return next;
    return;
  end if;

  registration_status := reg.status;

  if reg.status <> 'approved' then
    readiness_state := reg.status;  -- waiting_for_info / under_review / action_needed
    live_sender_count := 0;
    return next;
    return;
  end if;

  select count(*) into live_count
  from public.communication_sms_sender_identities s
  where s.organization_id = p_organization_id
    and s.registration_id = reg.id
    and s.capable_sms
    and s.lifecycle_state = 'ready';

  live_sender_count := live_count;
  readiness_state := case when live_count >= 1 then 'ready' else 'finishing_setup' end;
  return next;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Server-owned access: RLS on and deny-all to client roles. The registration and mode records may be read and
-- written by service_role; the history table is append-only (select + insert, never update or delete). The
-- /api/* layer reads with service_role, scopes to the caller's organization and hides provider detail.
-- ---------------------------------------------------------------------------------------------------------------

alter table public.communication_sms_registrations enable row level security;
alter table public.communication_sms_registration_events enable row level security;
alter table public.communication_sms_org_modes enable row level security;

revoke all on table public.communication_sms_registrations from public, anon, authenticated;
revoke all on table public.communication_sms_registrations from service_role;
grant select, insert, update on table public.communication_sms_registrations to service_role;

revoke all on table public.communication_sms_registration_events from public, anon, authenticated;
revoke all on table public.communication_sms_registration_events from service_role;
grant select, insert on table public.communication_sms_registration_events to service_role;

revoke all on table public.communication_sms_org_modes from public, anon, authenticated;
revoke all on table public.communication_sms_org_modes from service_role;
grant select, insert, update on table public.communication_sms_org_modes to service_role;

revoke all on function public.communication_sms_start_registration(uuid, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_start_registration(uuid, text, text, text, uuid)
  to service_role;

revoke all on function public.communication_sms_submit_registration(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_submit_registration(uuid, uuid, text)
  to service_role;

revoke all on function public.communication_sms_record_registration_outcome(uuid, text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_registration_outcome(uuid, text, uuid, text, text)
  to service_role;

revoke all on function public.communication_sms_record_registration_check(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_registration_check(uuid, uuid, text)
  to service_role;

revoke all on function public.communication_sms_set_sender_capabilities(uuid, text, text, boolean, boolean, boolean, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_sender_capabilities(uuid, text, text, boolean, boolean, boolean, uuid)
  to service_role;

revoke all on function public.communication_sms_set_org_mode(uuid, uuid, text, text, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.communication_sms_set_org_mode(uuid, uuid, text, text, text, text, boolean)
  to service_role;

revoke all on function public.communication_sms_effective_mode(uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_effective_mode(uuid)
  to service_role;

revoke all on function public.communication_sms_readiness(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_readiness(uuid, text, text, text)
  to service_role;
