-- Invoices Part 3b-1, file 2 of 2: the four commands that move money.
--
--   record_client_payment    money arrived, and optionally where it goes
--   apply_client_payment     put existing credit -- a receipt or a quote deposit -- onto a bill
--   unapply_client_payment   take an application back off, returning that money to credit
--   move_client_payment      take it off one bill and put it on another, in one transaction
--
-- Every one of them is a single transaction, claims a command receipt before doing any work so a retry
-- returns the first result instead of moving the money twice, and takes its locks in the order the design
-- fixed: organization settings, then invoices in id order, then the receipt. Nothing here calls out to a
-- provider, because nothing here processes a payment; these record money that moved somewhere else.
--
-- Refunds, reversal of a mistaken receipt, Void, Bad debt and Mark received are 3b-2.

-- 1. Shared checks ------------------------------------------------------------------------------------------

-- The entry check for anything that moves money onto or off a bill. Not lock_invoice_for_edit: money
-- commands carry no expected revision, because applying a payment does not change the document, and a
-- replaced bill still accepts corrections to money that was already sitting on it (decision D3).
create or replace function private.lock_invoice_for_payment(
  target_organization_id uuid,
  target_invoice_id uuid
)
returns public.invoices
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invoice_row public.invoices;
begin
  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id
  for update;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  if invoice_row.voided_at is not null then
    raise exception 'A voided invoice cannot take or give up money.' using errcode = 'check_violation';
  end if;

  return invoice_row;
end;
$$;

revoke all on function private.lock_invoice_for_payment(uuid, uuid) from public;
revoke execute on function private.lock_invoice_for_payment(uuid, uuid) from anon, authenticated;

-- How much of one manual receipt is still the client's to spend: what arrived, less what was actually
-- refunded, less what is already committed to a bill. A reversed receipt is money that never arrived, so
-- it is worth nothing here at all.
create or replace function private.payment_event_available_minor(
  target_organization_id uuid,
  target_payment_event_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when receipt.event_type <> 'received' then 0
    when exists (
      select 1 from public.client_payment_events as correction
      where correction.organization_id = receipt.organization_id
        and correction.original_event_id = receipt.id
        and correction.event_type = 'reversed'
    ) then 0
    else receipt.amount_minor
      - coalesce((
        select sum(refund.amount_minor)
        from public.client_payment_events as refund
        where refund.organization_id = receipt.organization_id
          and refund.original_event_id = receipt.id
          and refund.event_type = 'refunded'
      ), 0)
      - coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = receipt.organization_id
          and entry.payment_event_id = receipt.id
      ), 0)
  end::bigint
  from public.client_payment_events as receipt
  where receipt.organization_id = target_organization_id
    and receipt.id = target_payment_event_id;
$$;

revoke all on function private.payment_event_available_minor(uuid, uuid) from public;
revoke execute on function private.payment_event_available_minor(uuid, uuid) from anon, authenticated;

-- The same question for a deposit already recorded on a quote. Reused where it lives rather than copied
-- into a second receipt table, so the quote workspace's own reversal keeps its meaning here.
create or replace function private.deposit_event_available_minor(
  target_organization_id uuid,
  target_deposit_event_id uuid
)
returns bigint
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case
    when deposit.event_type <> 'received' then 0
    when exists (
      select 1 from public.quote_deposit_events as reversal
      where reversal.organization_id = deposit.organization_id
        and reversal.reversed_event_id = deposit.id
    ) then 0
    else deposit.amount_minor
      - coalesce((
        select sum(refund.amount_minor)
        from public.client_payment_events as refund
        where refund.organization_id = deposit.organization_id
          and refund.original_deposit_event_id = deposit.id
          and refund.event_type = 'refunded'
      ), 0)
      - coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = deposit.organization_id
          and entry.deposit_event_id = deposit.id
      ), 0)
  end::bigint
  from public.quote_deposit_events as deposit
  where deposit.organization_id = target_organization_id
    and deposit.id = target_deposit_event_id;
$$;

revoke all on function private.deposit_event_available_minor(uuid, uuid) from public;
revoke execute on function private.deposit_event_available_minor(uuid, uuid) from anon, authenticated;

-- Putting money on a bill, in one place: the entry, the history, and the D1 check that a draft which has
-- just been paid in full becomes a settled bill. Its caller has already locked the invoice and proved the
-- money is available; this is what every one of them does afterwards, identically.
create or replace function private.apply_invoice_allocation(
  invoice_row public.invoices,
  target_payment_event_id uuid,
  target_deposit_event_id uuid,
  new_amount_minor bigint,
  actor uuid,
  new_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  allocation_id uuid;
  remaining bigint;
begin
  if new_amount_minor is null or new_amount_minor <= 0 then
    raise exception 'A payment amount must be more than zero.' using errcode = 'check_violation';
  end if;

  remaining := invoice_row.total_minor
    - private.invoice_allocated_minor(invoice_row.organization_id, invoice_row.id);
  if new_amount_minor > remaining then
    raise exception 'That is more than invoice #% still owes.', invoice_row.invoice_number
      using errcode = 'check_violation',
      detail = format('%s remaining, %s offered', remaining, new_amount_minor);
  end if;

  insert into public.invoice_payment_allocations (
    organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
    payment_event_id, deposit_event_id, reason, actor_user_id
  ) values (
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'applied', new_amount_minor, invoice_row.currency_code,
    target_payment_event_id, target_deposit_event_id, nullif(trim(coalesce(new_reason, '')), ''), actor
  )
  returning id into allocation_id;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.payment_applied', actor, invoice_row.revision, new_reason,
    jsonb_build_object(
      'allocation_id', allocation_id,
      'amount_minor', new_amount_minor,
      'source', case when target_deposit_event_id is not null then 'quote_deposit' else 'payment' end
    ),
    true, null
  );

  -- D1: a draft that has just become fully paid is a settled bill, without pretending it was ever sent.
  perform private.recognize_invoice_if_settled(
    invoice_row.organization_id, invoice_row.id, actor
  );

  return allocation_id;
end;
$$;

revoke all on function private.apply_invoice_allocation(public.invoices, uuid, uuid, bigint, uuid, text)
  from public;
revoke execute on function private.apply_invoice_allocation(public.invoices, uuid, uuid, bigint, uuid, text)
  from anon, authenticated;

-- Taking money back off a bill, in one place. The invoice is already locked by the caller.
create or replace function private.reverse_invoice_allocation(
  invoice_row public.invoices,
  allocation_row public.invoice_payment_allocations,
  actor uuid,
  new_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reversal_id uuid;
begin
  if allocation_row.entry_type <> 'applied' then
    raise exception 'Only a payment that was applied to an invoice can be taken back off.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.invoice_payment_allocations as existing
    where existing.organization_id = allocation_row.organization_id
      and existing.reversed_allocation_id = allocation_row.id
  ) then
    raise exception 'That payment has already been taken off this invoice.' using errcode = 'check_violation';
  end if;
  -- 3a made recognition irreversible: a draft settled by this money cannot be un-settled, so the money
  -- that settled it cannot be pulled back out from under it either.
  if invoice_row.recognized_at is not null then
    raise exception 'This draft was settled by that payment, so it cannot be taken back off.'
      using errcode = 'check_violation';
  end if;

  insert into public.invoice_payment_allocations (
    organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
    payment_event_id, deposit_event_id, reversed_allocation_id, reason, actor_user_id
  ) values (
    allocation_row.organization_id, allocation_row.invoice_id, allocation_row.invoice_number,
    allocation_row.client_id, 'unapplied', allocation_row.amount_minor, allocation_row.currency_code,
    allocation_row.payment_event_id, allocation_row.deposit_event_id, allocation_row.id,
    nullif(trim(coalesce(new_reason, '')), ''), actor
  )
  returning id into reversal_id;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.payment_unapplied', actor, invoice_row.revision, new_reason,
    jsonb_build_object(
      'allocation_id', reversal_id,
      'reversed_allocation_id', allocation_row.id,
      'amount_minor', allocation_row.amount_minor,
      'source', case when allocation_row.deposit_event_id is not null then 'quote_deposit' else 'payment' end
    ),
    true, null
  );

  return reversal_id;
end;
$$;

revoke all on function private.reverse_invoice_allocation(
  public.invoices, public.invoice_payment_allocations, uuid, text
) from public;
revoke execute on function private.reverse_invoice_allocation(
  public.invoices, public.invoice_payment_allocations, uuid, text
) from anon, authenticated;

-- 2. Money arrived --------------------------------------------------------------------------------------------

-- Jobber's Collect Payment in one command: record what came in, and say which bills it pays. Both parts are
-- optional in the sense that money may arrive with nowhere to put it yet -- that is client credit, and
-- decision D1 says money sitting on a draft is exactly that until the draft is issued.
create or replace function public.record_client_payment(
  target_organization_id uuid,
  target_client_id uuid,
  new_amount_minor bigint,
  new_method text,
  new_payment_date date,
  new_reference text,
  new_note text,
  new_allocations jsonb,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  settings_row public.organization_settings;
  receipt public.client_payment_events;
  invoice_row public.invoices;
  allocation jsonb;
  allocation_amount bigint;
  allocated_total bigint := 0;
  applied jsonb := '[]'::jsonb;
  allocation_id uuid;
begin
  if caller is null then
    raise exception 'You must be signed in to record a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.record_payment') then
    raise exception 'You do not have access to record payments here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  if new_amount_minor is null or new_amount_minor <= 0 then
    raise exception 'A payment amount must be more than zero.' using errcode = 'check_violation';
  end if;
  if new_method is null
     or new_method not in ('other', 'bank_transfer', 'cash', 'check', 'card_external', 'paypal') then
    raise exception 'That is not a payment method this product records.' using errcode = 'check_violation';
  end if;
  if new_allocations is not null and jsonb_typeof(new_allocations) <> 'array' then
    raise exception 'Payment allocations must be a list.' using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'record_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Settings first, always: this receipt is about to lock the organization's currency, and holding the row
  -- is what stops a currency change from committing between reading it and writing the money.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  if not exists (
    select 1 from public.clients
    where organization_id = target_organization_id and id = target_client_id and deleted_at is null
  ) then
    raise exception 'That client could not be found.' using errcode = 'P0404';
  end if;

  insert into public.client_payment_events (
    organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
    reference, note, actor_user_id
  ) values (
    target_organization_id, target_client_id, 'received', new_amount_minor, settings_row.currency_code,
    new_method, coalesce(new_payment_date, private.organization_today(target_organization_id)),
    nullif(trim(coalesce(new_reference, '')), ''), nullif(trim(coalesce(new_note, '')), ''), caller
  )
  returning * into receipt;

  -- Invoices in id order, so two payments touching the same two bills cannot deadlock each other.
  for allocation in
    select entry.value
    from jsonb_array_elements(coalesce(new_allocations, '[]'::jsonb)) as entry(value)
    order by (entry.value->>'invoice_id')::uuid
  loop
    allocation_amount := (allocation->>'amount_minor')::bigint;
    allocated_total := allocated_total + coalesce(allocation_amount, 0);
    if allocated_total > new_amount_minor then
      raise exception 'That is more than the payment received.' using errcode = 'check_violation';
    end if;

    invoice_row := private.lock_invoice_for_payment(
      target_organization_id, (allocation->>'invoice_id')::uuid
    );
    if invoice_row.client_id <> target_client_id then
      raise exception 'That invoice belongs to a different client.' using errcode = 'check_violation';
    end if;
    if invoice_row.currency_code <> receipt.currency_code then
      raise exception 'That invoice was written in a different currency.' using errcode = 'check_violation';
    end if;

    allocation_id := private.apply_invoice_allocation(
      invoice_row, receipt.id, null, allocation_amount, caller, allocation->>'reason'
    );
    applied := applied || jsonb_build_object(
      'allocation_id', allocation_id,
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'amount_minor', allocation_amount
    );
  end loop;

  return private.complete_invoice_command(
    target_organization_id, 'record_client_payment', new_idempotency_key,
    jsonb_build_object(
      'payment_event_id', receipt.id,
      'client_id', receipt.client_id,
      'amount_minor', receipt.amount_minor,
      'currency_code', receipt.currency_code,
      'payment_date', receipt.payment_date,
      'allocated_minor', allocated_total,
      'credit_minor', receipt.amount_minor - allocated_total,
      'allocations', applied
    )
  );
end;
$$;

comment on function public.record_client_payment(
  uuid, uuid, bigint, text, date, text, text, jsonb, text, text
) is
  'Records money received from a client and, optionally, which of their bills it pays, in one transaction. '
  'Anything not allocated stays as client credit. A retry carrying the same key returns the first receipt '
  'rather than recording the money twice.';

revoke all on function public.record_client_payment(
  uuid, uuid, bigint, text, date, text, text, jsonb, text, text
) from public;
revoke execute on function public.record_client_payment(
  uuid, uuid, bigint, text, date, text, text, jsonb, text, text
) from anon;
grant execute on function public.record_client_payment(
  uuid, uuid, bigint, text, date, text, text, jsonb, text, text
) to authenticated;

-- 3. Putting existing credit on a bill ---------------------------------------------------------------------

-- Money already received -- a manual receipt, or a deposit recorded on a quote -- goes onto a bill. Exactly
-- one source, checked against what that source still has left rather than against what it originally was.
create or replace function public.apply_client_payment(
  target_organization_id uuid,
  target_invoice_id uuid,
  target_payment_event_id uuid,
  target_deposit_event_id uuid,
  new_amount_minor bigint,
  new_reason text,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  settings_row public.organization_settings;
  invoice_row public.invoices;
  receipt public.client_payment_events;
  deposit public.quote_deposit_events;
  source_client_id uuid;
  source_currency text;
  available bigint;
  allocation_id uuid;
begin
  if caller is null then
    raise exception 'You must be signed in to apply a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.record_payment') then
    raise exception 'You do not have access to apply payments here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  if (target_payment_event_id is not null) = (target_deposit_event_id is not null) then
    raise exception 'Apply either a recorded payment or a quote deposit, not both.'
      using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'apply_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for share;
  if not found then
    raise exception 'That organization could not be found.' using errcode = 'P0404';
  end if;

  -- Invoice before receipt, the order every money command uses.
  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if target_payment_event_id is not null then
    select * into receipt
    from public.client_payment_events
    where organization_id = target_organization_id and id = target_payment_event_id
    for update;
    if not found then
      raise exception 'That payment could not be found.' using errcode = 'P0404';
    end if;
    source_client_id := receipt.client_id;
    source_currency := receipt.currency_code;
    available := private.payment_event_available_minor(target_organization_id, receipt.id);
  else
    select * into deposit
    from public.quote_deposit_events
    where organization_id = target_organization_id and id = target_deposit_event_id
    for update;
    if not found then
      raise exception 'That deposit could not be found.' using errcode = 'P0404';
    end if;
    select quote.client_id into source_client_id
    from public.quotes as quote
    where quote.organization_id = target_organization_id and quote.id = deposit.quote_id;
    -- A deposit exists only on a published quote, and publishing a quote locks the organization's currency
    -- permanently, so the deposit's currency is the settings currency and cannot have moved since.
    source_currency := settings_row.currency_code;
    available := private.deposit_event_available_minor(target_organization_id, deposit.id);
  end if;

  if source_client_id is distinct from invoice_row.client_id then
    raise exception 'That money belongs to a different client.' using errcode = 'check_violation';
  end if;
  if source_currency is distinct from invoice_row.currency_code then
    raise exception 'That money was received in a different currency.' using errcode = 'check_violation';
  end if;
  if new_amount_minor is null or new_amount_minor <= 0 then
    raise exception 'A payment amount must be more than zero.' using errcode = 'check_violation';
  end if;
  if new_amount_minor > available then
    raise exception 'That money is already spent or refunded.' using errcode = 'check_violation',
      detail = format('%s available, %s offered', available, new_amount_minor);
  end if;

  allocation_id := private.apply_invoice_allocation(
    invoice_row, target_payment_event_id, target_deposit_event_id, new_amount_minor, caller, new_reason
  );

  return private.complete_invoice_command(
    target_organization_id, 'apply_client_payment', new_idempotency_key,
    jsonb_build_object(
      'allocation_id', allocation_id,
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'amount_minor', new_amount_minor,
      'source', case when target_deposit_event_id is not null then 'quote_deposit' else 'payment' end
    )
  );
end;
$$;

comment on function public.apply_client_payment(uuid, uuid, uuid, uuid, bigint, text, text, text) is
  'Puts money the client has already given -- a recorded payment or a quote deposit -- onto one of their '
  'bills, never more than that money still has left and never more than the bill still owes.';

revoke all on function public.apply_client_payment(uuid, uuid, uuid, uuid, bigint, text, text, text)
  from public;
revoke execute on function public.apply_client_payment(uuid, uuid, uuid, uuid, bigint, text, text, text)
  from anon;
grant execute on function public.apply_client_payment(uuid, uuid, uuid, uuid, bigint, text, text, text)
  to authenticated;

-- 4. Taking it back off ---------------------------------------------------------------------------------------

-- Returns an application to client credit. Correcting where money sits is its own permission: someone who
-- may record a payment is not thereby someone who may move one that is already on a bill.
create or replace function public.unapply_client_payment(
  target_organization_id uuid,
  target_allocation_id uuid,
  new_reason text,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  allocation_row public.invoice_payment_allocations;
  invoice_row public.invoices;
  reversal_id uuid;
begin
  if caller is null then
    raise exception 'You must be signed in to correct a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.correct_payment') then
    raise exception 'You do not have access to correct payments here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'unapply_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Read the entry first only to learn which invoice to lock; the entry itself is immutable, so it is the
  -- invoice lock that serialises two people correcting the same bill.
  select * into allocation_row
  from public.invoice_payment_allocations
  where organization_id = target_organization_id and id = target_allocation_id;
  if not found then
    raise exception 'That payment entry could not be found.' using errcode = 'P0404';
  end if;

  invoice_row := private.lock_invoice_for_payment(target_organization_id, allocation_row.invoice_id);

  reversal_id := private.reverse_invoice_allocation(invoice_row, allocation_row, caller, new_reason);

  return private.complete_invoice_command(
    target_organization_id, 'unapply_client_payment', new_idempotency_key,
    jsonb_build_object(
      'allocation_id', reversal_id,
      'reversed_allocation_id', allocation_row.id,
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'amount_minor', allocation_row.amount_minor
    )
  );
end;
$$;

comment on function public.unapply_client_payment(uuid, uuid, text, text, text) is
  'Returns money from a bill to the client''s available credit, keeping both the original application and '
  'the entry that took it back. The money itself is untouched: this changes where it sits, not that it '
  'arrived.';

revoke all on function public.unapply_client_payment(uuid, uuid, text, text, text) from public;
revoke execute on function public.unapply_client_payment(uuid, uuid, text, text, text) from anon;
grant execute on function public.unapply_client_payment(uuid, uuid, text, text, text) to authenticated;

-- 5. Moving it to another bill ----------------------------------------------------------------------------

-- One transaction, two retained entries: off the first bill and onto the second. Moving less than was on
-- the first bill leaves the difference as client credit rather than losing it.
create or replace function public.move_client_payment(
  target_organization_id uuid,
  target_allocation_id uuid,
  target_invoice_id uuid,
  new_amount_minor bigint,
  new_reason text,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  allocation_row public.invoice_payment_allocations;
  from_invoice public.invoices;
  to_invoice public.invoices;
  first_id uuid;
  second_id uuid;
  reversal_id uuid;
  allocation_id uuid;
  moved bigint;
begin
  if caller is null then
    raise exception 'You must be signed in to move a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.correct_payment') then
    raise exception 'You do not have access to correct payments here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'move_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  select * into allocation_row
  from public.invoice_payment_allocations
  where organization_id = target_organization_id and id = target_allocation_id;
  if not found then
    raise exception 'That payment entry could not be found.' using errcode = 'P0404';
  end if;
  if allocation_row.invoice_id = target_invoice_id then
    raise exception 'That payment is already on that invoice.' using errcode = 'check_violation';
  end if;

  -- Both invoices, in id order, before anything changes.
  first_id := least(allocation_row.invoice_id, target_invoice_id);
  second_id := greatest(allocation_row.invoice_id, target_invoice_id);
  perform private.lock_invoice_for_payment(target_organization_id, first_id);
  perform private.lock_invoice_for_payment(target_organization_id, second_id);

  -- Both rows are held now, so these two reads see the locked versions.
  select * into from_invoice from public.invoices
  where organization_id = target_organization_id and id = allocation_row.invoice_id;
  select * into to_invoice from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;

  if to_invoice.client_id <> from_invoice.client_id then
    raise exception 'Money can only move between the same client''s invoices.'
      using errcode = 'check_violation';
  end if;
  if to_invoice.currency_code <> allocation_row.currency_code then
    raise exception 'That invoice was written in a different currency.' using errcode = 'check_violation';
  end if;

  moved := coalesce(new_amount_minor, allocation_row.amount_minor);
  if moved > allocation_row.amount_minor then
    raise exception 'That is more than the payment on invoice #%.', from_invoice.invoice_number
      using errcode = 'check_violation',
      detail = format('%s on the invoice, %s offered', allocation_row.amount_minor, moved);
  end if;

  reversal_id := private.reverse_invoice_allocation(from_invoice, allocation_row, caller, new_reason);
  allocation_id := private.apply_invoice_allocation(
    to_invoice, allocation_row.payment_event_id, allocation_row.deposit_event_id, moved, caller, new_reason
  );

  return private.complete_invoice_command(
    target_organization_id, 'move_client_payment', new_idempotency_key,
    jsonb_build_object(
      'reversed_allocation_id', allocation_row.id,
      'unapplied_allocation_id', reversal_id,
      'allocation_id', allocation_id,
      'from_invoice_id', from_invoice.id,
      'from_invoice_number', from_invoice.invoice_number,
      'invoice_id', to_invoice.id,
      'invoice_number', to_invoice.invoice_number,
      'amount_minor', moved,
      'returned_to_credit_minor', allocation_row.amount_minor - moved
    )
  );
end;
$$;

comment on function public.move_client_payment(uuid, uuid, uuid, bigint, text, text, text) is
  'Moves money from one of a client''s bills to another in one transaction, leaving both the entry that '
  'took it off and the entry that put it on. Moving part of it returns the rest to available credit.';

revoke all on function public.move_client_payment(uuid, uuid, uuid, bigint, text, text, text) from public;
revoke execute on function public.move_client_payment(uuid, uuid, uuid, bigint, text, text, text) from anon;
grant execute on function public.move_client_payment(uuid, uuid, uuid, bigint, text, text, text)
  to authenticated;

notify pgrst, 'reload schema';
