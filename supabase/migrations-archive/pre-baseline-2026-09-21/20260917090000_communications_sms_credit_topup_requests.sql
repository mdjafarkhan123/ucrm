-- Communications A2 / Stage 2C (part 1): offsite credit top-up requests.
--
-- Approved money model (docs/research/communications-a2-stage6-settings-owner-controls-plan.md, 2026-09-12):
-- a contractor submits a Top-up Request with the offsite payment reference. It creates NO spendable credit
-- until Jafar verifies the money arrived and confirms it. Confirming posts exactly one immutable credit into
-- the Stage 1 ledger for the amount actually received (which may differ from the requested amount) and raises
-- the settled balance atomically. A contractor may cancel only a still-awaiting request; confirmed money is
-- corrected later through a recorded adjustment, never by editing history. No saved cards, no auto-recharge.
--
-- This part adds the request lifecycle only. Promotional credit, retail rates, distinct holds, standalone
-- adjustments/refunds and the owner API/UI are later Stage 2C parts. The table is server-owned: writes flow
-- through the security-definer commands below; the /api/* layer scopes reads to the caller's organization.

create table public.communication_sms_credit_topup_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null,
  requested_amount_minor bigint not null,
  currency_code text not null default 'USD',
  offsite_reference text,
  note text,
  status text not null default 'awaiting_confirmation',
  requested_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz,
  decision_reason text,
  settled_amount_minor bigint,
  constraint communication_sms_credit_topup_requests_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint communication_sms_credit_topup_requests_requested_amount_check
    check (requested_amount_minor > 0),
  constraint communication_sms_credit_topup_requests_reference_check
    check (offsite_reference is null or char_length(trim(offsite_reference)) between 1 and 500),
  constraint communication_sms_credit_topup_requests_note_check
    check (note is null or char_length(note) <= 2000),
  constraint communication_sms_credit_topup_requests_reason_check
    check (decision_reason is null or char_length(decision_reason) <= 2000),
  constraint communication_sms_credit_topup_requests_status_check
    check (status in ('awaiting_confirmation', 'confirmed', 'rejected', 'cancelled')),
  -- Each terminal status carries exactly the decision evidence it should, and an awaiting request carries none.
  constraint communication_sms_credit_topup_requests_lifecycle_check check (
    (status = 'awaiting_confirmation'
      and decided_at is null and decided_by is null and settled_amount_minor is null)
    or (status = 'confirmed'
      and decided_at is not null and decided_by is not null
      and settled_amount_minor is not null and settled_amount_minor > 0)
    or (status = 'rejected'
      and decided_at is not null and decided_by is not null and settled_amount_minor is null)
    or (status = 'cancelled'
      and decided_at is not null and settled_amount_minor is null)
  )
);

-- Bounded, ordered listing of a single organization's requests (Commercial access history + contractor page).
create index communication_sms_credit_topup_requests_org_history_idx
  on public.communication_sms_credit_topup_requests (organization_id, requested_at desc, id desc);

-- The Platform Owner's confirm queue: awaiting requests across organizations, oldest first.
create index communication_sms_credit_topup_requests_awaiting_idx
  on public.communication_sms_credit_topup_requests (requested_at, id)
  where status = 'awaiting_confirmation';

comment on table public.communication_sms_credit_topup_requests is
  'Offsite SMS credit top-up requests. Creates no spendable credit until Jafar confirms receipt; confirming '
  'posts one immutable ledger credit and raises the settled balance. Server-owned; writes via the '
  'communication_sms_*_credit_topup command functions only.';

-- A contractor (org owner/admin) submits a request. It is worth nothing until confirmed.
create or replace function public.communication_sms_request_credit_topup(
  p_organization_id uuid,
  p_requested_by uuid,
  p_requested_amount_minor bigint,
  p_currency_code text default 'USD',
  p_offsite_reference text default null,
  p_note text default null
) returns public.communication_sms_credit_topup_requests
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  req public.communication_sms_credit_topup_requests;
begin
  insert into public.communication_sms_credit_topup_requests (
    organization_id, requested_by, requested_amount_minor, currency_code, offsite_reference, note
  ) values (
    p_organization_id, p_requested_by, p_requested_amount_minor,
    coalesce(p_currency_code, 'USD'), p_offsite_reference, p_note
  )
  returning * into req;

  return req;
end;
$$;

-- Jafar confirms the money actually arrived. Atomically: post one immutable purchased-credit ledger entry for
-- the settled amount, raise the settled balance, and mark the request confirmed. The Stage 1 ledger's
-- (organization_id, source_key, entry_kind) uniqueness makes a repeated confirm impossible to double-credit;
-- the awaiting-status guard makes the state transition single-shot.
create or replace function public.communication_sms_confirm_credit_topup(
  p_request_id uuid,
  p_decided_by uuid,
  p_settled_amount_minor bigint,
  p_decision_reason text default null
) returns public.communication_sms_credit_topup_requests
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  req public.communication_sms_credit_topup_requests;
  new_balance bigint;
begin
  if p_settled_amount_minor is null or p_settled_amount_minor <= 0 then
    raise exception 'a confirmed top-up must record a positive settled amount'
      using errcode = 'P0001';
  end if;

  select * into req
  from public.communication_sms_credit_topup_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'top-up request % not found', p_request_id using errcode = 'P0001';
  end if;
  if req.status <> 'awaiting_confirmation' then
    raise exception 'top-up request % is % and can no longer be confirmed', p_request_id, req.status
      using errcode = 'P0001';
  end if;

  -- Ensure the organization has a credit account, then raise its settled balance.
  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (req.organization_id, req.currency_code)
  on conflict (organization_id) do nothing;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = settled_balance_minor + p_settled_amount_minor,
      updated_at = now()
  where organization_id = req.organization_id
  returning settled_balance_minor into new_balance;

  -- One immutable purchased-credit entry, keyed to this request so a retry cannot post twice.
  insert into public.communication_sms_credit_ledger_entries (
    organization_id, source_key, entry_kind, amount_minor, balance_after_minor
  ) values (
    req.organization_id, 'topup:' || req.id::text, 'credit', p_settled_amount_minor, new_balance
  );

  update public.communication_sms_credit_topup_requests
  set status = 'confirmed',
      decided_by = p_decided_by,
      decided_at = now(),
      decision_reason = p_decision_reason,
      settled_amount_minor = p_settled_amount_minor
  where id = p_request_id
  returning * into req;

  return req;
end;
$$;

-- Jafar rejects a request (money never arrived, or it was submitted in error). No credit is ever posted.
create or replace function public.communication_sms_reject_credit_topup(
  p_request_id uuid,
  p_decided_by uuid,
  p_decision_reason text
) returns public.communication_sms_credit_topup_requests
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  req public.communication_sms_credit_topup_requests;
begin
  if p_decision_reason is null or char_length(trim(p_decision_reason)) = 0 then
    raise exception 'a rejected top-up must record a reason' using errcode = 'P0001';
  end if;

  update public.communication_sms_credit_topup_requests
  set status = 'rejected',
      decided_by = p_decided_by,
      decided_at = now(),
      decision_reason = p_decision_reason
  where id = p_request_id and status = 'awaiting_confirmation'
  returning * into req;

  if not found then
    raise exception 'top-up request % is not awaiting confirmation and cannot be rejected', p_request_id
      using errcode = 'P0001';
  end if;

  return req;
end;
$$;

-- A contractor cancels their own request. Only an awaiting request may be cancelled; confirmed money stands.
create or replace function public.communication_sms_cancel_credit_topup(
  p_request_id uuid,
  p_cancelled_by uuid
) returns public.communication_sms_credit_topup_requests
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  req public.communication_sms_credit_topup_requests;
begin
  update public.communication_sms_credit_topup_requests
  set status = 'cancelled',
      decided_by = p_cancelled_by,
      decided_at = now()
  where id = p_request_id and status = 'awaiting_confirmation'
  returning * into req;

  if not found then
    raise exception 'top-up request % is not awaiting confirmation and cannot be cancelled', p_request_id
      using errcode = 'P0001';
  end if;

  return req;
end;
$$;

-- Server-owned. RLS on and deny-all to client roles; the /api/* layer reads with service_role and scopes to
-- the caller's organization, and every write goes through the security-definer commands above.
alter table public.communication_sms_credit_topup_requests enable row level security;

revoke all on table public.communication_sms_credit_topup_requests from public, anon, authenticated;
revoke all on table public.communication_sms_credit_topup_requests from service_role;
grant select, insert, update on table public.communication_sms_credit_topup_requests to service_role;

revoke all on function public.communication_sms_request_credit_topup(uuid, uuid, bigint, text, text, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_request_credit_topup(uuid, uuid, bigint, text, text, text)
  to service_role;

revoke all on function public.communication_sms_confirm_credit_topup(uuid, uuid, bigint, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_confirm_credit_topup(uuid, uuid, bigint, text)
  to service_role;

revoke all on function public.communication_sms_reject_credit_topup(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_reject_credit_topup(uuid, uuid, text)
  to service_role;

revoke all on function public.communication_sms_cancel_credit_topup(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_cancel_credit_topup(uuid, uuid)
  to service_role;
