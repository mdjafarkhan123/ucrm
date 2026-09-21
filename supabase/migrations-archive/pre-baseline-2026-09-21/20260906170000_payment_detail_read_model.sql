-- Invoices Part 6b-2b: the payment detail screen's read model.
--
-- Jobber has a payment screen and Send Receipt lives on it. Ours is read-only: one recorded receipt, what it
-- settled, and the two things staff can do with it afterwards -- send the customer their receipt again, or
-- print it. Editing and deleting a payment is ledger-correction work and is deliberately not here; the
-- ledger is append-only on purpose.
--
-- Two functions, each with one job:
--   * public.payment_detail       -- the screen's data.
--   * public.payment_receipt_preview -- the same receipt the customer gets, for the staff print page.
-- Plus one field added to public.invoice_detail's payment history so its rows can link to the screen.
--
-- Money gate: a payment IS an amount. A member without invoices.view_price cannot open this screen at all --
-- unlike an invoice, where the document and status still mean something with the prices withheld, a payment
-- with its amount removed is nothing. So the permission check refuses rather than nulling fields.

-- 1. The screen's read model -------------------------------------------------------------------------------

-- Definer, checking its own permissions and scoped to the one organization, exactly like invoice_detail. It
-- is a bounded point read: the payment by primary key, its client by primary key, and its allocations by
-- (organization, payment) -- an index that already exists, and a list that is one row today because a
-- payment settles a single invoice.
create or replace function public.payment_detail(
  target_organization_id uuid,
  target_payment_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
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
    'applied_to', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'allocation_id', allocation.id,
        'invoice_id', invoice.id,
        'invoice_number', allocation.invoice_number,
        'subject', invoice.subject,
        'entry_type', allocation.entry_type,
        'amount_minor', allocation.amount_minor,
        'created_at', allocation.created_at
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

comment on function public.payment_detail(uuid, uuid) is
  'One recorded payment for its detail screen: the receipt fields, the client, and the invoices it was '
  'applied to. Definer; requires invoices.view and invoices.view_price, because a payment with its amount '
  'withheld is nothing. Refunds and reversals are not found here -- this screen is the receipt''s home.';

revoke all on function public.payment_detail(uuid, uuid) from public, anon;
grant execute on function public.payment_detail(uuid, uuid) to authenticated;

-- 2. The staff print page ----------------------------------------------------------------------------------

-- The twin of public.invoice_customer_preview: staff read the customer's own receipt from the one function
-- that defines it, so what is printed here is what was emailed, not a second rendering that agrees today and
-- drifts tomorrow. It creates nothing -- no link, no token: printing your own receipt is not sending it.
create or replace function public.payment_receipt_preview(target_payment_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  payment_row public.client_payment_events;
  business_name text;
begin
  select * into payment_row
  from public.client_payment_events
  where id = target_payment_event_id;

  if payment_row.id is null
     or payment_row.event_type <> 'received'
     or not private.member_has_permission(payment_row.organization_id, caller, 'invoices.view')
     or not private.member_has_permission(payment_row.organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this payment.' using errcode = 'insufficient_privilege';
  end if;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = payment_row.organization_id;

  return private.payment_receipt_document(payment_row, business_name);
end;
$$;

comment on function public.payment_receipt_preview(uuid) is
  'The customer''s receipt document for a signed-in member to print, without creating a link. Same builder '
  'the token page uses, so the printed copy and the emailed one can never disagree.';

revoke all on function public.payment_receipt_preview(uuid) from public;
revoke execute on function public.payment_receipt_preview(uuid) from anon;
grant execute on function public.payment_receipt_preview(uuid) to authenticated;

-- 3. The invoice's money history learns which payment each row came from -----------------------------------

-- Unchanged from 20260906150000 except for one added field: payment_event_id, so a "Payment received" row on
-- the invoice screen can link to that payment's page. Null on a deposit row -- a quote deposit is not a
-- payment record and has no screen of its own.
create or replace function public.invoice_detail(
  target_organization_id uuid,
  target_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_see_price boolean;
  today date;
  invoice_row public.invoices;
  applied_minor bigint;
  derived_status text;
  money jsonb;
  payment_history jsonb;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  can_see_price := private.member_has_permission(target_organization_id, caller, 'invoices.view_price');
  today := private.organization_today(target_organization_id);

  select * into invoice_row
  from public.invoices
  where organization_id = target_organization_id and id = target_invoice_id;
  if not found then
    raise exception 'That invoice could not be found.' using errcode = 'P0404';
  end if;

  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into applied_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id and entry.invoice_id = target_invoice_id;

  derived_status := case
    when invoice_row.replaced_at is not null then invoice_row.frozen_status_label
    else private.invoice_live_status(
      invoice_row.voided_at, invoice_row.written_off_at, invoice_row.issued_at, invoice_row.recognized_at,
      invoice_row.marked_received_at, invoice_row.total_minor, applied_minor, invoice_row.due_date, today)
  end;

  if can_see_price then
    money := jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount_minor', invoice_row.discount_minor,
      'discount_name', invoice_row.discount_name,
      'discount_type', invoice_row.discount_type,
      'discount_value', invoice_row.discount_value,
      'tax_minor', invoice_row.tax_minor,
      'tax_source', invoice_row.tax_source,
      'tax_name', invoice_row.tax_name,
      'tax_rate_id', invoice_row.tax_rate_id,
      'tax_rate_basis_points', invoice_row.tax_rate_basis_points,
      'total_minor', invoice_row.total_minor,
      'allocated_minor', applied_minor,
      'remaining_minor', invoice_row.total_minor - applied_minor
    );

    -- The bill's money history: one row per application/unapplication, newest last so the list reads
    -- top-to-bottom as it happened. A source is either a manual receipt (client_payment_events) or a reused
    -- quote deposit (quote_deposit_events); exactly one side of the two left joins is ever populated, per
    -- invoice_payment_allocations_one_source. Gated the same as money -- this is money, not just a fact of
    -- the bill's existence.
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', allocation.id,
      'payment_event_id', allocation.payment_event_id,
      'entry_type', allocation.entry_type,
      'amount_minor', allocation.amount_minor,
      'created_at', allocation.created_at,
      'source', case when allocation.deposit_event_id is not null then 'deposit' else 'payment' end,
      'method', coalesce(payment.method, deposit.method),
      'payment_date', coalesce(payment.payment_date, deposit.created_at::date),
      'reference', coalesce(payment.reference, deposit.reference),
      'note', coalesce(payment.note, deposit.note),
      'reason', allocation.reason
    ) order by allocation.created_at, allocation.id), '[]'::jsonb)
    into payment_history
    from public.invoice_payment_allocations as allocation
    left join public.client_payment_events as payment
      on payment.organization_id = target_organization_id and payment.id = allocation.payment_event_id
    left join public.quote_deposit_events as deposit
      on deposit.organization_id = target_organization_id and deposit.id = allocation.deposit_event_id
    where allocation.organization_id = target_organization_id
      and allocation.invoice_id = target_invoice_id;
  else
    money := null;
    payment_history := null;
  end if;

  return jsonb_build_object(
    'invoice', jsonb_build_object(
      'id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'revision', invoice_row.revision,
      'subject', invoice_row.subject,
      'currency_code', invoice_row.currency_code,
      'issue_date', invoice_row.issue_date,
      'due_date', invoice_row.due_date,
      'due_date_source', invoice_row.due_date_source,
      'payment_term_snapshot', invoice_row.payment_term_snapshot,
      'contract_disclaimer', invoice_row.contract_disclaimer,
      'customer_snapshot', invoice_row.customer_snapshot,
      'billing_address_snapshot', invoice_row.billing_address_snapshot,
      'service_properties', invoice_row.service_properties,
      'issued_at', invoice_row.issued_at,
      'issue_method', invoice_row.issue_method,
      'voided_at', invoice_row.voided_at,
      'void_reason', invoice_row.void_reason,
      'void_note', invoice_row.void_note,
      'written_off_at', invoice_row.written_off_at,
      'write_off_note', invoice_row.write_off_note,
      'marked_received_at', invoice_row.marked_received_at,
      'recognized_at', invoice_row.recognized_at,
      'replaced_at', invoice_row.replaced_at,
      'replaced_by_invoice_id', invoice_row.replaced_by_invoice_id,
      'predecessor_invoice_id', invoice_row.predecessor_invoice_id,
      'replacement_kind', invoice_row.replacement_kind,
      'is_replaced', invoice_row.replaced_at is not null,
      'derived_status', derived_status,
      'client_id', invoice_row.client_id,
      'created_at', invoice_row.created_at
    ),
    'client', (
      select case when client.id is null then null else jsonb_build_object(
        'id', client.id,
        'display_name', client.display_name,
        'company_name', client.company_name,
        -- Restored (see file header): the send dialog needs this to show who the invoice goes to.
        'email', (
          select lower(trim(method.value))
          from public.client_contact_methods as method
          where method.organization_id = target_organization_id
            and method.client_id = client.id
            and method.kind = 'email'
          order by method.is_primary desc, method.created_at
          limit 1
        )
      ) end
      from public.clients as client
      where client.organization_id = target_organization_id and client.id = invoice_row.client_id
    ),
    'money', money,
    'payment_history', payment_history,
    'delivery', jsonb_build_object(
      'last_sent', (
        select case when intent.id is null then null else jsonb_build_object(
          'sent_at', intent.created_at,
          'status', intent.status,
          'recipient_email', intent.recipient_email
        ) end
        from public.communication_delivery_intents as intent
        where intent.organization_id = target_organization_id and intent.invoice_id = target_invoice_id
        order by intent.created_at desc, intent.id desc
        limit 1
      ),
      'views', (
        select jsonb_build_object(
          'first_viewed_at', min(link.first_viewed_at),
          'last_viewed_at', max(link.last_viewed_at),
          'view_count', coalesce(sum(link.view_count), 0)
        )
        from public.invoice_access_links as link
        where link.organization_id = target_organization_id and link.invoice_id = target_invoice_id
      )
    ),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', line.id,
        'position', line.position,
        'line_kind', line.line_kind,
        'category', line.category,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'is_taxable', line.is_taxable,
        'service_date', line.service_date,
        'unit_price_minor', case when can_see_price then line.unit_price_minor else null end,
        'line_total_minor', case when can_see_price then line.line_total_minor else null end
      ) order by line.position, line.id), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = target_organization_id and line.invoice_id = target_invoice_id
    )
  );
end;
$$;

notify pgrst, 'reload schema';
