-- Deferred launch sweep Part 4c (decision D7): fixing a mistyped payment, Xero-style.
--
-- client_payment_events is append-only, so a payment is never edited. Instead:
--   * correct_client_payment takes every live application of the wrong payment back off its invoices,
--     records the right payment and applies it as staff entered it, then appends the reversing row for the
--     wrong one -- all in one transaction. The reversing row names its replacement (replacement_event_id),
--     so each screen can link the two.
--   * withdraw_client_payment ("Mark as never received") takes every live application back off and appends
--     the reversing row, in one step. reverse_client_payment keeps refusing a payment that is still on a bill;
--     this is the one-click version the payment screen offers.
-- Both refuse a payment with a live refund (undo the refund first) and a Stripe payment (processed money is
-- corrected through Stripe, not by retyping it). The draft-settled refusal in reverse_invoice_allocation still
-- applies.
-- payment_detail gains the correction facts the screen needs.

alter table public.client_payment_events
  add column replacement_event_id uuid,
  add constraint client_payment_events_replacement_fk
    foreign key (organization_id, replacement_event_id)
    references public.client_payment_events (organization_id, id) on delete restrict,
  add constraint client_payment_events_replacement_shape
    check (replacement_event_id is null or event_type = 'reversed');

create index client_payment_events_replacement_idx
  on public.client_payment_events (organization_id, replacement_event_id)
  where replacement_event_id is not null;

comment on column public.client_payment_events.replacement_event_id is
  'On a reversing row written by Fix payment: the corrected payment recorded in its place.';

-- Takes every still-live application of a payment back off its invoice. Invoices are locked in id order so
-- two corrections touching the same bills queue instead of deadlocking.
create or replace function private.unapply_all_payment_allocations(
  target_organization_id uuid,
  target_payment_event_id uuid,
  actor uuid,
  new_reason text
)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  live public.invoice_payment_allocations;
  invoice_row public.invoices;
  total bigint := 0;
begin
  for live in
    select allocation.*
    from public.invoice_payment_allocations as allocation
    where allocation.organization_id = target_organization_id
      and allocation.payment_event_id = target_payment_event_id
      and allocation.entry_type = 'applied'
      and not exists (
        select 1 from public.invoice_payment_allocations as reversal
        where reversal.organization_id = allocation.organization_id
          and reversal.reversed_allocation_id = allocation.id
      )
    order by allocation.invoice_id, allocation.id
  loop
    invoice_row := private.lock_invoice_for_payment(target_organization_id, live.invoice_id);
    perform private.reverse_invoice_allocation(invoice_row, live, actor, new_reason);
    total := total + live.amount_minor;
  end loop;
  return total;
end;
$$;

revoke all on function private.unapply_all_payment_allocations(uuid, uuid, uuid, text) from public;

-- Locks and checks the payment both commands start from.
create or replace function private.lock_payment_for_correction(
  target_organization_id uuid,
  target_payment_event_id uuid
)
returns public.client_payment_events
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  original public.client_payment_events;
begin
  select * into original
  from public.client_payment_events
  where organization_id = target_organization_id and id = target_payment_event_id
  for update;
  if not found or original.event_type <> 'received' then
    raise exception 'That payment could not be found.' using errcode = 'P0404';
  end if;
  if exists (
    select 1 from public.client_payment_events as existing
    where existing.organization_id = target_organization_id
      and existing.original_event_id = original.id
      and existing.event_type = 'reversed'
  ) then
    raise exception 'That payment has already been corrected.' using errcode = 'check_violation';
  end if;
  if original.method in ('stripe_card', 'stripe_bank', 'stripe_other') then
    raise exception 'A payment taken online is corrected by refunding it through Stripe.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.client_payment_events as refund
    where refund.organization_id = target_organization_id
      and refund.original_event_id = original.id
      and refund.event_type = 'refunded'
      and not exists (
        select 1 from public.client_payment_events as undo
        where undo.organization_id = refund.organization_id
          and undo.original_event_id = refund.id
          and undo.event_type = 'reversed'
      )
  ) then
    raise exception 'Part of this payment was refunded. Undo the refund before correcting it.'
      using errcode = 'check_violation';
  end if;
  return original;
end;
$$;

revoke all on function private.lock_payment_for_correction(uuid, uuid) from public;

create or replace function public.correct_client_payment(
  target_organization_id uuid,
  target_payment_event_id uuid,
  new_amount_minor bigint,
  new_method text,
  new_payment_date date,
  new_reference text,
  new_note text,
  new_allocations jsonb,
  new_reason text,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  original public.client_payment_events;
  replacement public.client_payment_events;
  reversal public.client_payment_events;
  invoice_row public.invoices;
  allocation jsonb;
  allocation_amount bigint;
  allocated_total bigint := 0;
  applied jsonb := '[]'::jsonb;
  allocation_id uuid;
  reason text := nullif(trim(coalesce(new_reason, '')), '');
begin
  if caller is null then
    raise exception 'You must be signed in to correct a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.correct_payment') then
    raise exception 'You do not have access to correct payments here.' using errcode = 'insufficient_privilege';
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
    target_organization_id, 'correct_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  original := private.lock_payment_for_correction(target_organization_id, target_payment_event_id);

  perform private.unapply_all_payment_allocations(
    target_organization_id, original.id, caller, coalesce(reason, 'Payment corrected')
  );

  insert into public.client_payment_events (
    organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
    reference, note, actor_user_id
  ) values (
    target_organization_id, original.client_id, 'received', new_amount_minor, original.currency_code,
    new_method, coalesce(new_payment_date, original.payment_date),
    nullif(trim(coalesce(new_reference, '')), ''), nullif(trim(coalesce(new_note, '')), ''), caller
  )
  returning * into replacement;

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
    if invoice_row.client_id <> original.client_id then
      raise exception 'That invoice belongs to a different client.' using errcode = 'check_violation';
    end if;
    if invoice_row.currency_code <> replacement.currency_code then
      raise exception 'That invoice was written in a different currency.' using errcode = 'check_violation';
    end if;
    allocation_id := private.apply_invoice_allocation(
      invoice_row, replacement.id, null, allocation_amount, caller, reason
    );
    applied := applied || jsonb_build_object(
      'allocation_id', allocation_id,
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'amount_minor', allocation_amount
    );
  end loop;

  insert into public.client_payment_events (
    organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
    reference, note, actor_user_id, original_event_id, replacement_event_id
  ) values (
    target_organization_id, original.client_id, 'reversed', original.amount_minor, original.currency_code,
    null, private.organization_today(target_organization_id),
    original.reference, coalesce(reason, 'Payment corrected'), caller, original.id, replacement.id
  )
  returning * into reversal;

  return private.complete_invoice_command(
    target_organization_id, 'correct_client_payment', new_idempotency_key,
    jsonb_build_object(
      'payment_event_id', replacement.id,
      'corrected_payment_event_id', original.id,
      'reversal_event_id', reversal.id,
      'client_id', replacement.client_id,
      'amount_minor', replacement.amount_minor,
      'currency_code', replacement.currency_code,
      'payment_date', replacement.payment_date,
      'allocated_minor', allocated_total,
      'credit_minor', replacement.amount_minor - allocated_total,
      'allocations', applied
    )
  );
end;
$$;

revoke all on function public.correct_client_payment(uuid, uuid, bigint, text, date, text, text, jsonb, text, text, text) from public, anon;
grant execute on function public.correct_client_payment(uuid, uuid, bigint, text, date, text, text, jsonb, text, text, text) to authenticated, service_role;

comment on function public.correct_client_payment(uuid, uuid, bigint, text, date, text, text, jsonb, text, text, text) is
  'Fix payment (D7): atomically takes a mistyped payment off its invoices, records the corrected payment with the allocations given, and appends the reversing row that names it. The original stays in history.';

create or replace function public.withdraw_client_payment(
  target_organization_id uuid,
  target_payment_event_id uuid,
  new_reason text,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  caller uuid := (select auth.uid());
  replayed jsonb;
  original public.client_payment_events;
  reversal public.client_payment_events;
  released bigint;
  reason text := nullif(trim(coalesce(new_reason, '')), '');
begin
  if caller is null then
    raise exception 'You must be signed in to correct a payment.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.correct_payment') then
    raise exception 'You do not have access to correct payments here.' using errcode = 'insufficient_privilege';
  end if;
  perform private.require_invoice_price_access(target_organization_id);

  replayed := private.begin_invoice_command(
    target_organization_id, 'withdraw_client_payment', new_idempotency_key, new_request_hash, caller
  );
  if replayed is not null then
    return replayed;
  end if;

  original := private.lock_payment_for_correction(target_organization_id, target_payment_event_id);

  released := private.unapply_all_payment_allocations(
    target_organization_id, original.id, caller, coalesce(reason, 'Payment never received')
  );

  insert into public.client_payment_events (
    organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
    reference, note, actor_user_id, original_event_id
  ) values (
    target_organization_id, original.client_id, 'reversed', original.amount_minor, original.currency_code,
    null, private.organization_today(target_organization_id),
    original.reference, coalesce(reason, 'Payment never received'), caller, original.id
  )
  returning * into reversal;

  return private.complete_invoice_command(
    target_organization_id, 'withdraw_client_payment', new_idempotency_key,
    jsonb_build_object(
      'reversal_event_id', reversal.id,
      'original_event_id', original.id,
      'client_id', original.client_id,
      'amount_minor', original.amount_minor,
      'released_minor', released
    )
  );
end;
$$;

revoke all on function public.withdraw_client_payment(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.withdraw_client_payment(uuid, uuid, text, text, text) to authenticated, service_role;

comment on function public.withdraw_client_payment(uuid, uuid, text, text, text) is
  'Mark as never received (D7): takes a payment off every invoice it is on and appends its reversing row, in one step. The original stays in history.';

create or replace function "public"."payment_detail"("target_organization_id" "uuid", "target_payment_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  payment_row public.client_payment_events;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this payment.' using errcode = 'insufficient_privilege';
  end if;

  select * into payment_row
  from public.client_payment_events
  where organization_id = target_organization_id and id = target_payment_event_id;

  -- A refund or a reversal is a correction, not a receipt, and this screen is the receipt's home. Same answer
  -- as a payment that does not exist, so the screen cannot be used to find out which is which.
  if payment_row.id is null or payment_row.event_type <> 'received' then
    raise exception 'That payment could not be found.' using errcode = 'P0404';
  end if;

  return jsonb_build_object(
    'payment', jsonb_build_object(
      'id', payment_row.id,
      'amount_minor', payment_row.amount_minor,
      'currency_code', payment_row.currency_code,
      'method', payment_row.method,
      'payment_date', payment_row.payment_date,
      'reference', payment_row.reference,
      'note', payment_row.note,
      'created_at', payment_row.created_at
    ),
    -- Set once this payment has been fixed or marked as never received (D7). replacement_payment_id is the
    -- corrected payment that took its place; null means it was never received.
    'correction', (
      select jsonb_build_object(
        'corrected_at', reversal.created_at,
        'note', reversal.note,
        'replacement_payment_id', reversal.replacement_event_id
      )
      from public.client_payment_events as reversal
      where reversal.organization_id = target_organization_id
        and reversal.original_event_id = payment_row.id
        and reversal.event_type = 'reversed'
      limit 1
    ),
    -- The mistaken payment this one corrected, if it was entered through Fix payment.
    'replaces_payment_id', (
      select reversal.original_event_id
      from public.client_payment_events as reversal
      where reversal.organization_id = target_organization_id
        and reversal.replacement_event_id = payment_row.id
      limit 1
    ),
    -- Money already sent back out of this payment. Fix payment needs that undone first.
    'refunded_minor', (
      select coalesce(sum(refund.amount_minor), 0)
      from public.client_payment_events as refund
      where refund.organization_id = target_organization_id
        and refund.original_event_id = payment_row.id
        and refund.event_type = 'refunded'
        and not exists (
          select 1 from public.client_payment_events as undo
          where undo.organization_id = refund.organization_id
            and undo.original_event_id = refund.id
            and undo.event_type = 'reversed'
        )
    ),
    -- The same client card the invoice screen shows, read the same way: the primary email lives in
    -- client_contact_methods, not on the client row, and the send dialog needs it to say who the receipt
    -- goes to.
    'client', (
      select jsonb_build_object(
        'id', client.id,
        'display_name', client.display_name,
        'company_name', client.company_name,
        'email', (
          select lower(trim(method.value))
          from public.client_contact_methods as method
          where method.organization_id = target_organization_id
            and method.client_id = client.id
            and method.kind = 'email'
          order by method.is_primary desc, method.created_at
          limit 1
        )
      )
      from public.clients as client
      where client.organization_id = target_organization_id and client.id = payment_row.client_id
    ),
    -- What this money was put against. Applications and the entries that take them back both appear, oldest
    -- first, so a payment that was moved off a bill reads as what happened rather than as a gap. The invoice
    -- number is the allocation's own copy, so it still reads as "Invoice #14" after that draft is gone --
    -- and invoice_id is left null for a bill that no longer exists, which is what makes the link safe.
    -- is_reversed is true on an 'applied' row once some later row has taken it back off (unapply or the first
    -- half of a move) -- unapply_client_payment and move_client_payment both refuse a second reversal of the
    -- same allocation, so the screen uses this to stop offering an action that can only fail.
    'applied_to', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'allocation_id', allocation.id,
        'invoice_id', invoice.id,
        'invoice_number', allocation.invoice_number,
        'subject', invoice.subject,
        'entry_type', allocation.entry_type,
        'amount_minor', allocation.amount_minor,
        'created_at', allocation.created_at,
        'is_reversed', exists (
          select 1 from public.invoice_payment_allocations as reversal
          where reversal.organization_id = allocation.organization_id
            and reversal.reversed_allocation_id = allocation.id
        )
      ) order by allocation.created_at, allocation.id), '[]'::jsonb)
      from public.invoice_payment_allocations as allocation
      left join public.invoices as invoice
        on invoice.organization_id = allocation.organization_id and invoice.id = allocation.invoice_id
      where allocation.organization_id = target_organization_id
        and allocation.payment_event_id = target_payment_event_id
    )
  );
end;
$$;
