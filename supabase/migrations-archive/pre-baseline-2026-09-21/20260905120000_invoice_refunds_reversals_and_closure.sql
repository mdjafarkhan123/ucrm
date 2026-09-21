-- Invoices Part 3b-2: giving money back, correcting what was recorded, and closing a bill.
--
--   refund_client_payment            money actually sent back, against exactly one original receipt
--   reverse_client_payment           an entry that never should have existed, cancelled by a pointing row
--   void_invoice                     an invalid bill cancelled for good, releasing its deposits
--   write_off_invoice / restore      bad debt, and taking that write-off back
--   mark_invoice_received / reopen   status-only closure, and undoing it
--
-- 3b-1 built the ledger and the four commands that move money between a client's credit and their bills.
-- Everything here is about money leaving, or a bill ending, and each one leans on a number 3b-1 already
-- computes rather than doing its own arithmetic: how much of a receipt is unspent, how much a bill still
-- owes, and whether a bill still counts as money owed.
--
-- Three rules carried forward without exception. Money history is append-only, so a mistake is corrected by
-- a row that points at the mistake. Every command claims a retry receipt before it does any work. And locks
-- are taken in the order the design fixed -- settings, then invoices in id order, then the receipt -- so
-- nothing here can deadlock against the commands that came before it.

-- 1. A refund that was itself a mistake --------------------------------------------------------------------

-- 3b-1 subtracted every refund from what a receipt still has left, which was right when a refund was the
-- last word. It is not the last word any more: this file lets a refund recorded in error be reversed, and a
-- reversed refund gave nothing back, so it must stop counting. Both availability readers are corrected here
-- rather than left to disagree with the commands below.
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
          -- A refund somebody took back returned nothing, so it is not money out of this receipt.
          and not exists (
            select 1 from public.client_payment_events as undo
            where undo.organization_id = refund.organization_id
              and undo.original_event_id = refund.id
              and undo.event_type = 'reversed'
          )
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
          and not exists (
            select 1 from public.client_payment_events as undo
            where undo.organization_id = refund.organization_id
              and undo.original_event_id = refund.id
              and undo.event_type = 'reversed'
          )
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

-- The client-level credit number has the same hole for the same reason: a reversed refund is not money that
-- left. Everything else about this reader is unchanged from 3b-1.
create or replace function public.client_account_balance(target_client_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_client_ids is null or cardinality(target_client_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct client.organization_id) into organizations
  from public.clients as client
  where client.id = any(target_client_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those clients do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'invoices.view') then
    raise exception 'You do not have access to these clients'' billing.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(org, caller, 'invoices.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(client.id::text, jsonb_build_object(
      'currency_code', settings.currency_code,
      'outstanding_minor', outstanding.amount_minor,
      'available_credit_minor', credit.amount_minor,
      'account_balance_minor', outstanding.amount_minor - credit.amount_minor
    )), '{}'::jsonb)
  into answer
  from public.clients as client
  cross join public.organization_settings as settings
  cross join lateral (
    select coalesce(sum(invoice.total_minor - coalesce(entry.applied_minor, 0)), 0)::bigint as amount_minor
    from public.invoices as invoice
    left join lateral (
      select sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end) as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id
        and entry.invoice_id = invoice.id
    ) as entry on true
    where invoice.organization_id = client.organization_id
      and invoice.client_id = client.id
      and invoice.is_effective_receivable
  ) as outstanding
  cross join lateral (
    select (
      coalesce((
        select sum(receipt.amount_minor)
        from public.client_payment_events as receipt
        where receipt.organization_id = client.organization_id
          and receipt.client_id = client.id
          and receipt.event_type = 'received'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = receipt.organization_id
              and correction.original_event_id = receipt.id
              and correction.event_type = 'reversed'
          )
      ), 0)
      + coalesce((
        select sum(deposit.amount_minor)
        from public.quote_deposit_events as deposit
        join public.quotes as quote
          on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
        where deposit.organization_id = client.organization_id
          and quote.client_id = client.id
          and deposit.event_type = 'received'
          and not exists (
            select 1 from public.quote_deposit_events as reversal
            where reversal.organization_id = deposit.organization_id
              and reversal.reversed_event_id = deposit.id
          )
      ), 0)
      -- Money actually sent back is no longer the client's to spend, unless the refund itself was reversed.
      - coalesce((
        select sum(refund.amount_minor)
        from public.client_payment_events as refund
        where refund.organization_id = client.organization_id
          and refund.client_id = client.id
          and refund.event_type = 'refunded'
          and not exists (
            select 1 from public.client_payment_events as undo
            where undo.organization_id = refund.organization_id
              and undo.original_event_id = refund.id
              and undo.event_type = 'reversed'
          )
      ), 0)
      - coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = client.organization_id
          and entry.client_id = client.id
      ), 0)
    )::bigint as amount_minor
  ) as credit
  where client.organization_id = org
    and client.id = any(target_client_ids)
    and settings.organization_id = org;

  return answer;
end;
$$;

comment on function public.client_account_balance(uuid[]) is
  'The two client-level money numbers the contract keeps apart: what their effective bills still ask for, '
  'and money of theirs that is neither refunded nor already committed to a bill. Never counts a receipt '
  'twice and never counts a voided, superseded or written-off bill.';

revoke all on function public.client_account_balance(uuid[]) from public;
revoke execute on function public.client_account_balance(uuid[]) from anon;
grant execute on function public.client_account_balance(uuid[]) to authenticated;

-- 2. Money sent back -----------------------------------------------------------------------------------------

-- A refund records that money physically went back to the client, against exactly one original receipt: a
-- manual payment, or a deposit already recorded on a quote. Like every method in this product, none of these
-- moves money by itself; the contractor sent it and is recording that they did.
--
-- The cap is the number 3b-1 already owns: what that receipt still has left after earlier refunds and after
-- whatever is committed to bills. That is the design's two conditions -- no more than was received, no more
-- than is currently unapplied -- in one reading, so they cannot come apart. Money sitting on a bill must be
-- taken off it explicitly first; a refund never quietly unapplies anything.
create or replace function public.refund_client_payment(
  target_organization_id uuid,
  target_payment_event_id uuid,
  target_deposit_event_id uuid,
  new_amount_minor bigint,
  new_method text,
  new_refund_date date,
  new_reference text,
  new_note text,
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
  deposit public.quote_deposit_events;
  source_client_id uuid;
  source_currency text;
  available bigint;
  refund public.client_payment_events;
begin
  if caller is null then
    raise exception 'You must be signed in to record a refund.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.correct_payment') then
    raise exception 'You do not have access to refund payments here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  if (target_payment_event_id is not null) = (target_deposit_event_id is not null) then
    raise exception 'Refund either a recorded payment or a quote deposit, not both.'
      using errcode = 'check_violation';
  end if;
  -- Money went back by some route, and which route it was is part of the record.
  if new_method is null
     or new_method not in ('other', 'bank_transfer', 'cash', 'check', 'card_external', 'paypal') then
    raise exception 'That is not a refund method this product records.' using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'refund_client_payment', new_idempotency_key, new_request_hash, caller
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

  -- The original receipt is the row that has to be held: two refunds of the same money serialize here, and
  -- so does a refund racing an application of the same receipt.
  if target_payment_event_id is not null then
    select * into receipt
    from public.client_payment_events
    where organization_id = target_organization_id and id = target_payment_event_id
    for update;
    if not found then
      raise exception 'That payment could not be found.' using errcode = 'P0404';
    end if;
    if receipt.event_type <> 'received' then
      raise exception 'Only money that was received can be refunded.' using errcode = 'check_violation';
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
    if deposit.event_type <> 'received' then
      raise exception 'Only a deposit that was received can be refunded.' using errcode = 'check_violation';
    end if;
    select quote.client_id into source_client_id
    from public.quotes as quote
    where quote.organization_id = target_organization_id and quote.id = deposit.quote_id;
    -- A deposit exists only on a published quote, which locks the organization's currency permanently, so
    -- the settings currency is still the currency that deposit arrived in.
    source_currency := settings_row.currency_code;
    available := private.deposit_event_available_minor(target_organization_id, deposit.id);
  end if;

  if source_client_id is null then
    raise exception 'That money is not attached to a client.' using errcode = 'check_violation';
  end if;
  if new_amount_minor is null or new_amount_minor <= 0 then
    raise exception 'A refund amount must be more than zero.' using errcode = 'check_violation';
  end if;
  if new_amount_minor > available then
    -- Deliberately one message for both causes. Money already refunded and money sitting on a bill are the
    -- same thing from here: it is not available to send back until somebody takes it off the bill.
    raise exception 'That is more than this payment has left to refund.'
      using errcode = 'check_violation',
      detail = format('%s available, %s offered', available, new_amount_minor),
      hint = 'Money applied to an invoice must be taken off that invoice before it can be refunded.';
  end if;

  insert into public.client_payment_events (
    organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
    reference, note, actor_user_id, original_event_id, original_deposit_event_id
  ) values (
    target_organization_id, source_client_id, 'refunded', new_amount_minor, source_currency,
    new_method, coalesce(new_refund_date, private.organization_today(target_organization_id)),
    nullif(trim(coalesce(new_reference, '')), ''), nullif(trim(coalesce(new_note, '')), ''), caller,
    target_payment_event_id, target_deposit_event_id
  )
  returning * into refund;

  return private.complete_invoice_command(
    target_organization_id, 'refund_client_payment', new_idempotency_key,
    jsonb_build_object(
      'refund_event_id', refund.id,
      'client_id', refund.client_id,
      'amount_minor', refund.amount_minor,
      'currency_code', refund.currency_code,
      'refund_date', refund.payment_date,
      'source', case when target_deposit_event_id is not null then 'quote_deposit' else 'payment' end,
      'original_event_id', target_payment_event_id,
      'original_deposit_event_id', target_deposit_event_id,
      'remaining_refundable_minor', available - refund.amount_minor
    )
  );
end;
$$;

comment on function public.refund_client_payment(
  uuid, uuid, uuid, bigint, text, date, text, text, text, text
) is
  'Records money actually sent back to a client against one original receipt -- a recorded payment or a '
  'quote deposit -- never more than that receipt still has unspent and unrefunded. The original receipt is '
  'kept exactly as it was; the refund is a new row pointing at it.';

revoke all on function public.refund_client_payment(
  uuid, uuid, uuid, bigint, text, date, text, text, text, text
) from public;
revoke execute on function public.refund_client_payment(
  uuid, uuid, uuid, bigint, text, date, text, text, text, text
) from anon;
grant execute on function public.refund_client_payment(
  uuid, uuid, uuid, bigint, text, date, text, text, text, text
) to authenticated;

-- 3. An entry that should never have existed ---------------------------------------------------------------

-- Reversal is the other kind of correction, and it means something stronger than a refund: this money never
-- moved at all. A receipt entered against the wrong client, a payment that turned out to have bounced, a
-- refund recorded in error.
--
-- Because it says the entry never happened, it is only allowed while the entry has no consequences hanging
-- off it. A receipt with money on a bill, or with a refund already recorded, must have those undone first --
-- otherwise reversing it would leave allocations pointing at money the ledger now denies receiving.
create or replace function public.reverse_client_payment(
  target_organization_id uuid,
  target_payment_event_id uuid,
  new_note text,
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
  original public.client_payment_events;
  available bigint;
  reversal public.client_payment_events;
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
    target_organization_id, 'reverse_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  select * into original
  from public.client_payment_events
  where organization_id = target_organization_id and id = target_payment_event_id
  for update;
  if not found then
    raise exception 'That payment could not be found.' using errcode = 'P0404';
  end if;

  if original.event_type = 'reversed' then
    raise exception 'A correction cannot itself be corrected away.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.client_payment_events as existing
    where existing.organization_id = target_organization_id
      and existing.original_event_id = original.id
      and existing.event_type = 'reversed'
  ) then
    raise exception 'That entry has already been corrected.' using errcode = 'check_violation';
  end if;

  -- A receipt may only be taken back while it is untouched. Anything else has to be unwound explicitly,
  -- which is exactly what the unapply and refund commands are for.
  if original.event_type = 'received' then
    available := private.payment_event_available_minor(target_organization_id, original.id);
    if available <> original.amount_minor then
      raise exception 'That payment has already been used, so it cannot be marked as never received.'
        using errcode = 'check_violation',
        hint = 'Take it off any invoices, and undo any refund of it, before correcting it away.';
    end if;
  end if;

  insert into public.client_payment_events (
    organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
    reference, note, actor_user_id, original_event_id
  ) values (
    target_organization_id, original.client_id, 'reversed', original.amount_minor, original.currency_code,
    null, private.organization_today(target_organization_id),
    original.reference, nullif(trim(coalesce(new_note, '')), ''), caller, original.id
  )
  returning * into reversal;

  return private.complete_invoice_command(
    target_organization_id, 'reverse_client_payment', new_idempotency_key,
    jsonb_build_object(
      'reversal_event_id', reversal.id,
      'original_event_id', original.id,
      'original_event_type', original.event_type,
      'client_id', reversal.client_id,
      'amount_minor', reversal.amount_minor,
      'currency_code', reversal.currency_code
    )
  );
end;
$$;

comment on function public.reverse_client_payment(uuid, uuid, text, text, text) is
  'Records that a payment or a refund never actually happened, by appending a reversing row that points at '
  'it. The original stays visible. A receipt can only be reversed while nothing is sitting on a bill and '
  'nothing has been refunded out of it.';

revoke all on function public.reverse_client_payment(uuid, uuid, text, text, text) from public;
revoke execute on function public.reverse_client_payment(uuid, uuid, text, text, text) from anon;
grant execute on function public.reverse_client_payment(uuid, uuid, text, text, text) to authenticated;

-- 4. Cancelling a bill for good ------------------------------------------------------------------------------

-- Void is the approved departure from Jobber: an issued bill is never deleted, it is retained and marked
-- cancelled with a reason, so the original and its correction trail both survive.
--
-- Decision D2 is the whole shape of the refusal here. Ordinary payments on the bill block the void, and the
-- user resolves them explicitly -- unapply to credit, move to another bill, or refund. Void implies none of
-- those. Deposits are the single approved exception: they are released back to the client's credit in this
-- same transaction, because a cancelled bill has no claim on a deposit it never earned.
--
-- Progress invoices are excluded from ordinary Void by the contract. There is no installment link to test
-- until Jobs 11c gives one, so that exclusion arrives with the correction chains in 3c rather than being
-- guessed at here.
create or replace function public.void_invoice(
  target_organization_id uuid,
  target_invoice_id uuid,
  new_reason text,
  new_note text,
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
  invoice_row public.invoices;
  ordinary_minor bigint;
  remaining_minor bigint;
  deposit_entry public.invoice_payment_allocations;
  released_minor bigint := 0;
  released_count integer := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to void an invoice.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.void') then
    raise exception 'You do not have access to void invoices here.'
      using errcode = 'insufficient_privilege';
  end if;
  -- Whether this bill may be voided depends on what is sitting on it, so price visibility is part of the
  -- decision rather than only part of the display.
  perform private.require_invoice_price_access(target_organization_id);

  if new_reason is null
     or new_reason not in ('duplicate', 'created_in_error', 'client_request', 'other') then
    raise exception 'A void needs one of the four reasons.' using errcode = 'check_violation';
  end if;

  replayed := private.begin_invoice_command(
    target_organization_id, 'void_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  -- Already-voided is refused inside the lock helper, in the words the customer-facing product uses.
  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if invoice_row.issued_at is null and invoice_row.recognized_at is null then
    raise exception 'A draft is deleted rather than voided.' using errcode = 'check_violation';
  end if;
  if invoice_row.replaced_at is not null then
    raise exception 'That bill has already been replaced, so it is history rather than an open bill.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.written_off_at is not null then
    raise exception 'Undo the write-off before voiding this bill.' using errcode = 'check_violation';
  end if;
  if invoice_row.marked_received_at is not null then
    raise exception 'Reopen this bill before voiding it.' using errcode = 'check_violation';
  end if;

  -- D2: ordinary money only. Deposits are counted separately because they are the one thing void resolves
  -- on the user's behalf.
  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into ordinary_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id
    and entry.invoice_id = invoice_row.id
    and entry.payment_event_id is not null;

  if ordinary_minor > 0 then
    raise exception 'This bill still has payments on it, so it cannot be voided yet.'
      using errcode = 'check_violation',
      detail = format('%s still applied to invoice #%s', ordinary_minor, invoice_row.invoice_number),
      hint = 'Take the payment back to client credit, move it to another invoice, or refund it first.';
  end if;

  remaining_minor := invoice_row.total_minor
    - private.invoice_allocated_minor(target_organization_id, invoice_row.id);
  if remaining_minor <= 0 then
    raise exception 'This bill is fully paid, so it cannot be voided.' using errcode = 'check_violation',
      hint = 'Take the money off it first if this bill should not have existed.';
  end if;

  -- The approved deposit release, in the same transaction as the void itself. Each live application gets
  -- the same retained unapplication an explicit unapply would have written.
  for deposit_entry in
    select entry.*
    from public.invoice_payment_allocations as entry
    where entry.organization_id = target_organization_id
      and entry.invoice_id = invoice_row.id
      and entry.entry_type = 'applied'
      and entry.deposit_event_id is not null
      and not exists (
        select 1 from public.invoice_payment_allocations as undone
        where undone.organization_id = entry.organization_id
          and undone.reversed_allocation_id = entry.id
      )
    order by entry.id
  loop
    perform private.reverse_invoice_allocation(
      invoice_row, deposit_entry, caller, 'Released because the invoice was voided'
    );
    released_minor := released_minor + deposit_entry.amount_minor;
    released_count := released_count + 1;
  end loop;

  update public.invoices
  set voided_at = now(),
      voided_by = caller,
      void_reason = new_reason,
      void_note = nullif(trim(coalesce(new_note, '')), ''),
      revision = invoice_row.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id and id = invoice_row.id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.voided', caller, invoice_row.revision + 1, new_note,
    jsonb_build_object(
      'reason', new_reason,
      'released_deposit_count', released_count,
      'released_deposit_minor', released_minor
    ),
    true, null
  );

  -- The cancellation notice to the client is a Communications send, queued after the state is secured. That
  -- seam belongs to Part 6 with the rest of invoice delivery; nothing is sent from inside these locks.
  return private.complete_invoice_command(
    target_organization_id, 'void_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'client_id', invoice_row.client_id,
      'reason', new_reason,
      'released_deposit_count', released_count,
      'released_deposit_minor', released_minor
    )
  );
end;
$$;

comment on function public.void_invoice(uuid, uuid, text, text, text, text) is
  'Cancels an issued bill for good, keeping it and its reason forever. Refuses while ordinary payments are '
  'still applied to it, and releases any quote deposits back to client credit in the same transaction.';

revoke all on function public.void_invoice(uuid, uuid, text, text, text, text) from public;
revoke execute on function public.void_invoice(uuid, uuid, text, text, text, text) from anon;
grant execute on function public.void_invoice(uuid, uuid, text, text, text, text) to authenticated;

-- 5. Bad debt --------------------------------------------------------------------------------------------------

-- Valid work that will not be collected. Unlike a void, it says nothing was wrong with the bill; it says the
-- remaining balance is not coming. The invoice keeps its money history, and its stamp flips
-- is_effective_receivable to false on its own, so nothing anywhere subtracts write-offs by hand.
--
-- Reversible on purpose, following Jobber's unmark behavior, which is why these are nullable stamps rather
-- than an irreversible fact like issuance.
create or replace function public.write_off_invoice(
  target_organization_id uuid,
  target_invoice_id uuid,
  new_note text,
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
  invoice_row public.invoices;
  remaining_minor bigint;
begin
  if caller is null then
    raise exception 'You must be signed in to write off a balance.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.bad_debt') then
    raise exception 'You do not have access to write off balances here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'write_off_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if invoice_row.issued_at is null and invoice_row.recognized_at is null then
    raise exception 'Only a bill the client has been given can be written off.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.replaced_at is not null then
    raise exception 'That bill has already been replaced, so it is history rather than an open bill.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.written_off_at is not null then
    raise exception 'This balance is already written off.' using errcode = 'check_violation';
  end if;
  -- The two closures make different financial statements. A bill cannot say both.
  if invoice_row.marked_received_at is not null then
    raise exception 'This bill is already closed as received. Reopen it before writing it off.'
      using errcode = 'check_violation';
  end if;

  remaining_minor := invoice_row.total_minor
    - private.invoice_allocated_minor(target_organization_id, invoice_row.id);
  if remaining_minor <= 0 then
    raise exception 'There is nothing left on this bill to write off.' using errcode = 'check_violation';
  end if;

  update public.invoices
  set written_off_at = now(),
      written_off_by = caller,
      write_off_note = nullif(trim(coalesce(new_note, '')), ''),
      revision = invoice_row.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id and id = invoice_row.id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.written_off', caller, invoice_row.revision + 1, new_note,
    jsonb_build_object('written_off_minor', remaining_minor), true, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'write_off_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'client_id', invoice_row.client_id,
      'written_off_minor', remaining_minor
    )
  );
end;
$$;

comment on function public.write_off_invoice(uuid, uuid, text, text, text) is
  'Writes off the remaining balance of a bill that will not be collected. The bill and its payments stay '
  'exactly as they were; it simply stops counting as money the client owes.';

revoke all on function public.write_off_invoice(uuid, uuid, text, text, text) from public;
revoke execute on function public.write_off_invoice(uuid, uuid, text, text, text) from anon;
grant execute on function public.write_off_invoice(uuid, uuid, text, text, text) to authenticated;

-- Taking the write-off back, which puts the remaining balance back into what the client owes.
create or replace function public.restore_invoice_from_write_off(
  target_organization_id uuid,
  target_invoice_id uuid,
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
  invoice_row public.invoices;
  restored_minor bigint;
begin
  if caller is null then
    raise exception 'You must be signed in to undo a write-off.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.bad_debt') then
    raise exception 'You do not have access to undo write-offs here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'restore_invoice_from_write_off', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if invoice_row.written_off_at is null then
    raise exception 'This bill is not written off.' using errcode = 'check_violation';
  end if;

  restored_minor := invoice_row.total_minor
    - private.invoice_allocated_minor(target_organization_id, invoice_row.id);

  update public.invoices
  set written_off_at = null,
      written_off_by = null,
      write_off_note = null,
      revision = invoice_row.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id and id = invoice_row.id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.write_off_reversed', caller, invoice_row.revision + 1, new_reason,
    jsonb_build_object('restored_minor', restored_minor), true, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'restore_invoice_from_write_off', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'client_id', invoice_row.client_id,
      'restored_minor', restored_minor
    )
  );
end;
$$;

comment on function public.restore_invoice_from_write_off(uuid, uuid, text, text, text) is
  'Undoes a write-off, putting the bill''s remaining balance back into what the client owes. The write-off '
  'and the undo both stay in the invoice''s history.';

revoke all on function public.restore_invoice_from_write_off(uuid, uuid, text, text, text) from public;
revoke execute on function public.restore_invoice_from_write_off(uuid, uuid, text, text, text) from anon;
grant execute on function public.restore_invoice_from_write_off(uuid, uuid, text, text, text) to authenticated;

-- 6. Closing a bill without recording money --------------------------------------------------------------------

-- The contract is blunt about this one: it changes the status to Paid and settles nothing. No receipt, no
-- allocation, no reduction in what the client owes -- which is why is_effective_receivable deliberately
-- stays true through it. It is a label for a bill somebody has decided not to chase any further, and it is
-- kept apart from both real payment and write-off on purpose.
create or replace function public.mark_invoice_received(
  target_organization_id uuid,
  target_invoice_id uuid,
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
  invoice_row public.invoices;
  remaining_minor bigint;
begin
  if caller is null then
    raise exception 'You must be signed in to close an invoice.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.record_payment') then
    raise exception 'You do not have access to close invoices here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'mark_invoice_received', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if invoice_row.issued_at is null and invoice_row.recognized_at is null then
    raise exception 'Only a bill the client has been given can be closed this way.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.replaced_at is not null then
    raise exception 'That bill has already been replaced, so it is history rather than an open bill.'
      using errcode = 'check_violation';
  end if;
  if invoice_row.marked_received_at is not null then
    raise exception 'This bill is already closed as received.' using errcode = 'check_violation';
  end if;
  if invoice_row.written_off_at is not null then
    raise exception 'This balance is written off. Undo the write-off before closing it as received.'
      using errcode = 'check_violation';
  end if;

  remaining_minor := invoice_row.total_minor
    - private.invoice_allocated_minor(target_organization_id, invoice_row.id);
  if remaining_minor <= 0 then
    raise exception 'This bill is already paid in full.' using errcode = 'check_violation';
  end if;

  update public.invoices
  set marked_received_at = now(),
      marked_received_by = caller,
      revision = invoice_row.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id and id = invoice_row.id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.marked_received', caller, invoice_row.revision + 1, new_reason,
    jsonb_build_object('unsettled_minor', remaining_minor), true, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'mark_invoice_received', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'client_id', invoice_row.client_id,
      'unsettled_minor', remaining_minor
    )
  );
end;
$$;

comment on function public.mark_invoice_received(uuid, uuid, text, text, text) is
  'Closes a bill by hand without recording any money. It shows as Paid and the client''s debt is unchanged, '
  'which is exactly what the contract means by a status-only closure.';

revoke all on function public.mark_invoice_received(uuid, uuid, text, text, text) from public;
revoke execute on function public.mark_invoice_received(uuid, uuid, text, text, text) from anon;
grant execute on function public.mark_invoice_received(uuid, uuid, text, text, text) to authenticated;

-- Undoing that closure. The bill goes back to awaiting payment or past due, depending only on its due date.
create or replace function public.reopen_invoice(
  target_organization_id uuid,
  target_invoice_id uuid,
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
  invoice_row public.invoices;
begin
  if caller is null then
    raise exception 'You must be signed in to reopen an invoice.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.record_payment') then
    raise exception 'You do not have access to reopen invoices here.'
      using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'reopen_invoice', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  invoice_row := private.lock_invoice_for_payment(target_organization_id, target_invoice_id);

  if invoice_row.marked_received_at is null then
    raise exception 'This bill was not closed by hand, so there is nothing to reopen.'
      using errcode = 'check_violation';
  end if;

  update public.invoices
  set marked_received_at = null,
      marked_received_by = null,
      revision = invoice_row.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id and id = invoice_row.id;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.reopened', caller, invoice_row.revision + 1, new_reason, '{}'::jsonb, false, null
  );

  return private.complete_invoice_command(
    target_organization_id, 'reopen_invoice', new_idempotency_key,
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'client_id', invoice_row.client_id
    )
  );
end;
$$;

comment on function public.reopen_invoice(uuid, uuid, text, text, text) is
  'Undoes a by-hand closure, putting the bill back to awaiting payment or past due according to its due '
  'date. Both the closure and the reopening stay in its history.';

revoke all on function public.reopen_invoice(uuid, uuid, text, text, text) from public;
revoke execute on function public.reopen_invoice(uuid, uuid, text, text, text) from anon;
grant execute on function public.reopen_invoice(uuid, uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';
