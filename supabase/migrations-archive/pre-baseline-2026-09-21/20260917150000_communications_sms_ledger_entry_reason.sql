-- Communications A2 / Stage 2C (part 6b prerequisite): store the reason behind an SMS credit adjustment or
-- refund. The record_adjustment/record_refund commands (20260917120000, made retry-safe by 20260917130000)
-- already require and validate a non-empty reason, but never persisted it on the ledger entry -- the owner's
-- adjustment/refund history (2C-6b) would show amount and balance with no way to see why. Purely additive: a
-- nullable reason column, filled going forward by the two commands below. Other entry kinds (credit, charge)
-- still write no reason -- a top-up credit's reason already lives on its topup_requests.decision_reason, and
-- an ordinary charge has none.

alter table public.communication_sms_credit_ledger_entries
  add column reason text;

alter table public.communication_sms_credit_ledger_entries
  add constraint communication_sms_credit_ledger_entries_reason_check
    check (reason is null or char_length(trim(reason)) between 1 and 2000);

comment on column public.communication_sms_credit_ledger_entries.reason is
  'The reasoned note behind an adjustment or refund entry. Null for credit/charge entries, which carry no '
  'separate reason of their own.';

drop function if exists public.communication_sms_record_adjustment(uuid, bigint, text, text, uuid, text);

create function public.communication_sms_record_adjustment(
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
  reason text,
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
      organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at, reason
    ) values (
      p_organization_id, v_source_key, 'adjustment', p_amount_minor, new_balance, now(), trim(p_reason)
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

drop function if exists public.communication_sms_record_refund(uuid, bigint, text, text, uuid);

create function public.communication_sms_record_refund(
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
  reason text,
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
      organization_id, source_key, entry_kind, amount_minor, balance_after_minor, occurred_at, reason
    ) values (
      p_organization_id, v_source_key, 'refund', -p_amount_minor, new_balance, now(), trim(p_reason)
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

revoke all on function public.communication_sms_record_adjustment(uuid, bigint, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_adjustment(uuid, bigint, text, text, uuid, text)
  to service_role;

revoke all on function public.communication_sms_record_refund(uuid, bigint, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.communication_sms_record_refund(uuid, bigint, text, text, uuid)
  to service_role;
