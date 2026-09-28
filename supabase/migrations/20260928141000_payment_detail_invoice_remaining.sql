-- Deferred launch sweep Part 4c: payment_detail's applied_to rows also say what each bill still owes, so
-- Fix payment can cap what it puts back on it. Otherwise identical to 20260928140000's definition.

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
        -- What the bill still owes now, so Fix payment knows how much it can put back on it.
        'invoice_remaining_minor', case when invoice.id is null then null
          else invoice.total_minor - private.invoice_allocated_minor(target_organization_id, invoice.id) end,
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
