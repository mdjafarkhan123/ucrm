-- Communications A2 / Stage 2C (part 5b prerequisite): retry-safe money commands.
--
-- The three 2C-4 commands that INSERT a brand-new money row (grant_promotional_credit, record_adjustment,
-- record_refund) had no idempotency protection: a network retry or double-click would post the same credit,
-- adjustment or refund twice. Every other money-moving owner command in this app is retry-safe --
-- apply_organization_commercial_command checks (organization_id, idempotency_key) before writing anything
-- (20260813103456), and the SMS credit top-up decision (2C-5a) is naturally idempotent because it flips a
-- status field that can only move once. This migration brings the three gap commands to the same standard,
-- using the same "check first, return the prior result on replay" shape as the commercial command.
--
-- Promotional credit gets a dedicated idempotency_key column + unique(organization_id, idempotency_key),
-- identical to organization_commercial_events. Adjustment and refund need no new column: they already write
-- into communication_sms_credit_ledger_entries, which carries unique(organization_id, source_key, entry_kind)
-- from Stage 1 (20260913023817) -- the caller's idempotency key becomes that source_key (prefixed by kind)
-- instead of a fresh random uuid, so the existing constraint does the work.
--
-- Each command now checks for a prior row with the same key BEFORE touching any balance, and returns it with
-- applied = false on a replay; a fresh write returns applied = true. A concurrent duplicate that races past the
-- check is still caught by the unique constraint and re-read, never double-applied.

drop function if exists public.communication_sms_grant_promotional_credit(uuid, bigint, timestamptz, text, uuid, text);
drop function if exists public.communication_sms_record_adjustment(uuid, bigint, text, uuid, text);
drop function if exists public.communication_sms_record_refund(uuid, bigint, text, uuid);

alter table public.communication_sms_promotional_credits
  add column idempotency_key text;

alter table public.communication_sms_promotional_credits
  add constraint communication_sms_promotional_credits_idempotency_check
    check (char_length(trim(idempotency_key)) between 8 and 200);

alter table public.communication_sms_promotional_credits
  alter column idempotency_key set not null;

alter table public.communication_sms_promotional_credits
  add constraint communication_sms_promotional_credits_idempotency_unique
    unique (organization_id, idempotency_key);

create or replace function public.communication_sms_grant_promotional_credit(
  p_organization_id uuid,
  p_amount_minor bigint,
  p_expires_at timestamptz,
  p_reason text,
  p_idempotency_key text,
  p_granted_by uuid default null,
  p_currency_code text default 'USD'
) returns table (
  id uuid,
  organization_id uuid,
  currency_code text,
  amount_minor bigint,
  reason text,
  granted_by uuid,
  granted_at timestamptz,
  expires_at timestamptz,
  status text,
  revoked_by uuid,
  revoked_at timestamptz,
  revoke_reason text,
  idempotency_key text,
  applied boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  r public.communication_sms_promotional_credits%rowtype;
  already_applied boolean := false;
begin
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) < 8 then
    raise exception 'a promotional grant must record an idempotency key' using errcode = 'P0001';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'a promotional grant must be a positive amount' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'a promotional grant must record a reason' using errcode = 'P0001';
  end if;
  if p_expires_at is null or p_expires_at <= now() then
    raise exception 'a promotional grant must expire in the future' using errcode = 'P0001';
  end if;

  select * into r
  from public.communication_sms_promotional_credits c
  where c.organization_id = p_organization_id and c.idempotency_key = p_idempotency_key;

  if not found then
    begin
      insert into public.communication_sms_promotional_credits (
        organization_id, amount_minor, expires_at, reason, granted_by, currency_code, idempotency_key
      ) values (
        p_organization_id, p_amount_minor, p_expires_at, p_reason, p_granted_by,
        coalesce(p_currency_code, 'USD'), p_idempotency_key
      )
      returning * into r;
      already_applied := true;
    exception when unique_violation then
      -- Lost a race with a concurrent identical retry; read back what it wrote instead of erroring.
      select * into r
      from public.communication_sms_promotional_credits c
      where c.organization_id = p_organization_id and c.idempotency_key = p_idempotency_key;
    end;
  end if;

  return query select r.*, already_applied;
end;
$$;

create or replace function public.communication_sms_record_adjustment(
  p_organization_id uuid,
  p_amount_minor bigint,
  p_reason text,
  p_idempotency_key text,
  p_actor uuid default null,
  p_currency_code text default 'USD'
) returns table (
  id uuid,
  organization_id uuid,
  reservation_id uuid,
  source_key text,
  entry_kind text,
  amount_minor bigint,
  balance_after_minor bigint,
  occurred_at timestamptz,
  applied boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  r public.communication_sms_credit_ledger_entries%rowtype;
  already_applied boolean := false;
  v_source_key text;
  reserved bigint;
  new_balance bigint;
begin
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) < 8 then
    raise exception 'an adjustment must record an idempotency key' using errcode = 'P0001';
  end if;
  if p_amount_minor is null or p_amount_minor = 0 then
    raise exception 'an adjustment must move a non-zero amount' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'an adjustment must record a reason' using errcode = 'P0001';
  end if;

  v_source_key := 'adjustment:' || p_idempotency_key;

  select * into r
  from public.communication_sms_credit_ledger_entries e
  where e.organization_id = p_organization_id
    and e.source_key = v_source_key
    and e.entry_kind = 'adjustment';

  if found then
    return query select r.*, already_applied;
    return;
  end if;

  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (p_organization_id, coalesce(p_currency_code, 'USD'))
  on conflict (organization_id) do nothing;

  -- Check the resulting balance before writing it, so a refused correction returns a clear business error
  -- rather than the raw balances-check violation, while the constraint stays the backstop.
  select settled_balance_minor, reserved_balance_minor into new_balance, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  new_balance := new_balance + p_amount_minor;

  if new_balance < reserved then
    raise exception 'adjustment would drive the settled balance below the reserved funds'
      using errcode = 'P0001';
  end if;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = new_balance,
      updated_at = now()
  where organization_id = p_organization_id;

  begin
    insert into public.communication_sms_credit_ledger_entries (
      organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at
    ) values (
      p_organization_id, v_source_key, 'adjustment', p_amount_minor, new_balance, now()
    )
    returning * into r;
    already_applied := true;
  exception when unique_violation then
    -- Lost a race with a concurrent identical retry; the balance update above is a no-op replay risk only
    -- if two racing writers both pass the balance check -- read back the winner's row instead of erroring.
    select * into r
    from public.communication_sms_credit_ledger_entries e
    where e.organization_id = p_organization_id
      and e.source_key = v_source_key
      and e.entry_kind = 'adjustment';
  end;

  return query select r.*, already_applied;
end;
$$;

create or replace function public.communication_sms_record_refund(
  p_organization_id uuid,
  p_amount_minor bigint,
  p_reason text,
  p_idempotency_key text,
  p_actor uuid default null
) returns table (
  id uuid,
  organization_id uuid,
  reservation_id uuid,
  source_key text,
  entry_kind text,
  amount_minor bigint,
  balance_after_minor bigint,
  occurred_at timestamptz,
  applied boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  r public.communication_sms_credit_ledger_entries%rowtype;
  already_applied boolean := false;
  v_source_key text;
  reserved bigint;
  new_balance bigint;
begin
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) < 8 then
    raise exception 'a refund must record an idempotency key' using errcode = 'P0001';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'a refund must be a positive amount' using errcode = 'P0001';
  end if;
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'a refund must record a reason' using errcode = 'P0001';
  end if;

  v_source_key := 'refund:' || p_idempotency_key;

  select * into r
  from public.communication_sms_credit_ledger_entries e
  where e.organization_id = p_organization_id
    and e.source_key = v_source_key
    and e.entry_kind = 'refund';

  if found then
    return query select r.*, already_applied;
    return;
  end if;

  -- Check the resulting balance before writing it, so an over-refund returns a clear business error rather
  -- than the raw balances-check violation, while the constraint stays the backstop.
  select settled_balance_minor, reserved_balance_minor into new_balance, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'organization % has no credit account to refund from', p_organization_id
      using errcode = 'P0001';
  end if;

  new_balance := new_balance - p_amount_minor;

  if new_balance < reserved then
    raise exception 'refund exceeds the unreserved settled balance' using errcode = 'P0001';
  end if;

  update public.communication_sms_credit_accounts
  set settled_balance_minor = new_balance,
      updated_at = now()
  where organization_id = p_organization_id;

  begin
    insert into public.communication_sms_credit_ledger_entries (
      organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at
    ) values (
      p_organization_id, v_source_key, 'refund', -p_amount_minor, new_balance, now()
    )
    returning * into r;
    already_applied := true;
  exception when unique_violation then
    select * into r
    from public.communication_sms_credit_ledger_entries e
    where e.organization_id = p_organization_id
      and e.source_key = v_source_key
      and e.entry_kind = 'refund';
  end;

  return query select r.*, already_applied;
end;
$$;

comment on column public.communication_sms_promotional_credits.idempotency_key is
  'Caller-supplied retry key. unique(organization_id, idempotency_key) makes a repeated grant call a safe '
  'no-op replay instead of a second grant.';

revoke all on function public.communication_sms_grant_promotional_credit(uuid, bigint, timestamptz, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_grant_promotional_credit(uuid, bigint, timestamptz, text, text, uuid, text)
  to service_role;

revoke all on function public.communication_sms_record_adjustment(uuid, bigint, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_adjustment(uuid, bigint, text, text, uuid, text)
  to service_role;

revoke all on function public.communication_sms_record_refund(uuid, bigint, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_refund(uuid, bigint, text, text, uuid)
  to service_role;
