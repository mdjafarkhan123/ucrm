-- Stage 10 Part 4b (docs/global-sms-behavior-contract.md § Part 4): the toll-free check. US and Canadian
-- toll-free numbers text only after carriers approve the business behind them (Twilio's Toll-Free Verification).
-- GoHighLevel asks for this after a toll-free number is bought; Uplift does the same, reusing the business's
-- registration answers.
--
-- 1. One check per toll-free number. It keeps the answers sent (the business, its contact, how it texts and how
--    customers agree), Twilio's verification record, and what carriers said, so a dropped connection or a fix
--    reuses the same Twilio record instead of making a second one.
-- 2. Its history: every send, check and outcome, never edited.
-- 3. The switch-on command now turns on a toll-free number once its check is approved.
--
-- No browser reads these tables: row level security is on with no policies. The server checks who is asking.

-- 1. Checks --------------------------------------------------------------------------------------------------

create table public.communication_sms_tollfree_verifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sender_identity_id uuid not null,
  -- draft: being filled in. sending: Uplift is passing it to Twilio right now. under_review: carriers have it.
  -- approved: the number can text. needs_fix: carriers turned it down; the reason says what to change.
  status text not null default 'draft',
  -- What the business filled in, in the shape of the toll-free answers schema.
  answers jsonb not null default '{}'::jsonb,
  -- Raised by every saved change, so two open tabs cannot quietly overwrite each other.
  revision integer not null default 1,
  provider_verification_sid text,
  provider_status text,
  failure_reason text,
  provider_error_code integer,
  -- Carriers let some turned-down checks be edited and sent again until a date; others must start over.
  edit_allowed boolean,
  edit_expires_at timestamptz,
  sending_claim_token uuid,
  sending_claimed_at timestamptz,
  submitted_at timestamptz,
  decided_at timestamptz,
  last_checked_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_tollfree_verifications_org_id_key unique (organization_id, id),
  constraint communication_sms_tollfree_verifications_sender_key unique (sender_identity_id),
  constraint communication_sms_tollfree_verifications_sender_fkey
    foreign key (organization_id, sender_identity_id)
    references public.communication_sms_sender_identities (organization_id, id) on delete cascade,
  constraint communication_sms_tollfree_verifications_status_check
    check (status in ('draft', 'sending', 'under_review', 'approved', 'needs_fix')),
  constraint communication_sms_tollfree_verifications_answers_check check (
    jsonb_typeof(answers) = 'object' and pg_column_size(answers) <= 32768
  ),
  constraint communication_sms_tollfree_verifications_revision_check check (revision >= 1),
  constraint communication_sms_tollfree_verifications_sid_check
    check (provider_verification_sid is null or provider_verification_sid ~ '^HH[0-9A-Fa-f]{32}$'),
  constraint communication_sms_tollfree_verifications_reason_check
    check (failure_reason is null or char_length(failure_reason) <= 4000),
  -- Only a check being sent holds a claim, and a claim always has its time.
  constraint communication_sms_tollfree_verifications_claim_check check (
    (sending_claim_token is null) = (sending_claimed_at is null)
    and (status = 'sending' or sending_claim_token is null)
  ),
  -- A check carriers have, or had, always has its Twilio record.
  constraint communication_sms_tollfree_verifications_record_check check (
    status not in ('under_review', 'approved') or provider_verification_sid is not null
  )
);

comment on table public.communication_sms_tollfree_verifications is
  'Stage 10 Part 4b: a toll-free number''s carrier check (Twilio Toll-Free Verification). Server only.';

-- The record Twilio's status events name, and the daily check's waiting checks.
create unique index communication_sms_tollfree_verifications_sid_idx
  on public.communication_sms_tollfree_verifications (provider_verification_sid)
  where provider_verification_sid is not null;
create index communication_sms_tollfree_verifications_waiting_idx
  on public.communication_sms_tollfree_verifications (last_checked_at nulls first)
  where status = 'under_review';

alter table public.communication_sms_tollfree_verifications enable row level security;
revoke all on table public.communication_sms_tollfree_verifications from anon, authenticated;

-- 2. History -------------------------------------------------------------------------------------------------

create table public.communication_sms_tollfree_verification_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  verification_id uuid not null,
  -- sent, refused, provider_unavailable, under_review, approved, needs_fix, replaced
  action text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint communication_sms_tollfree_verification_events_check_fkey
    foreign key (organization_id, verification_id)
    references public.communication_sms_tollfree_verifications (organization_id, id) on delete cascade,
  constraint communication_sms_tollfree_verification_events_action_check
    check (action ~ '^[a-z][a-z_]{1,59}$'),
  constraint communication_sms_tollfree_verification_events_detail_check check (
    jsonb_typeof(detail) = 'object' and pg_column_size(detail) <= 8192
  )
);

create index communication_sms_tollfree_verification_events_check_idx
  on public.communication_sms_tollfree_verification_events (verification_id, created_at);

alter table public.communication_sms_tollfree_verification_events enable row level security;
revoke all on table public.communication_sms_tollfree_verification_events from anon, authenticated;

-- 3. Switch-on -----------------------------------------------------------------------------------------------

-- Unchanged from 20261224090000 for local numbers; a toll-free number now goes live once its own check is
-- approved. Still only `pending_setup` senders move, and only forwards to `ready`.
create or replace function public.communication_sms_reconcile_sender_readiness(
  p_organization_id uuid,
  p_us_use_case text
) returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  us_registration_id uuid;
  changed integer := 0;
  moved integer;
begin
  select r.id into us_registration_id
  from public.communication_sms_registrations r
  where r.organization_id = p_organization_id
    and r.country_code = 'US'
    and r.sender_type = 'long_code'
    and r.use_case = p_us_use_case
    and r.status = 'approved';

  with candidates as (
    select s.id
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id
      and s.lifecycle_state = 'pending_setup'
      and s.capable_sms
      and s.sender_type = 'long_code'
      and s.country_code is not null
      and (s.country_code <> 'US' or us_registration_id is not null)
      -- Paperwork the number was bought with must still be approved and in date.
      and not exists (
        select 1
        from public.communication_sms_number_orders o
        where o.organization_id = s.organization_id
          and o.sender_identity_id = s.id
          and (o.bundle_sid is not null or o.address_sid is not null)
          and not exists (
            select 1
            from public.communication_sms_number_paperwork p
            where p.organization_id = o.organization_id
              and p.country_code = o.country_code
              and p.number_type = o.number_type
              and p.status = 'approved'
              and (p.valid_until is null or p.valid_until > now())
          )
      )
    for update of s
  )
  update public.communication_sms_sender_identities s
  set lifecycle_state = 'ready',
      registration_id = case when s.country_code = 'US' then us_registration_id else s.registration_id end,
      updated_at = now()
  from candidates c
  where s.id = c.id;
  get diagnostics moved = row_count;
  changed := changed + moved;

  with candidates as (
    select s.id
    from public.communication_sms_sender_identities s
    join public.communication_sms_tollfree_verifications v
      on v.organization_id = s.organization_id
     and v.sender_identity_id = s.id
     and v.status = 'approved'
    where s.organization_id = p_organization_id
      and s.lifecycle_state = 'pending_setup'
      and s.capable_sms
      and s.sender_type = 'toll_free'
    for update of s
  )
  update public.communication_sms_sender_identities s
  set lifecycle_state = 'ready',
      updated_at = now()
  from candidates c
  where s.id = c.id;
  get diagnostics moved = row_count;
  changed := changed + moved;

  return changed;
end;
$$;

comment on function public.communication_sms_reconcile_sender_readiness(uuid, text) is
  'Stage 10 Part 4: switches pending_setup senders to ready once their route''s approval has passed (US local: the approved US registration; other local: approved, in-date paperwork; toll-free: its approved toll-free check). Idempotent.';

revoke all on function public.communication_sms_reconcile_sender_readiness(uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_reconcile_sender_readiness(uuid, text) to service_role;
