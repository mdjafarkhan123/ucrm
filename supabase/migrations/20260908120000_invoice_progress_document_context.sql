-- Invoices Part 5c-4: progress documents.
--
-- 5c-3 shipped the handoff that turns one payment stage into a Draft invoice. The bill it produces is
-- correct but anonymous: on screen and on the customer's copy it looks like an ordinary invoice whose line
-- amounts happen to be smaller than the job's. Two facts are missing.
--
-- The first is which stage this is. It already exists, frozen, in two places nobody can move: the claim row
-- carries `installment_number`, and the stage row's description cannot change once a claim points at it
-- (job_payment_schedule_items_guard_locked refuses description, value, position and is_deposit alike). So
-- the stage identity is read live and is still permanent -- no snapshot column, and a later job edit cannot
-- rewrite an issued customer document. Deliberately absent: how many stages the schedule has. That number
-- is *not* frozen -- an unbilled stage may still be added or removed -- so "Payment 2 of 3" would be a
-- promise the schedule can break. The document says "Payment 2" and stops there, which also keeps it inside
-- the contract's rule that future installment values never appear on the customer's copy.
--
-- The second is the pair of amounts. `invoice_lines.progress_original_amount_minor` has held the job line's
-- full customer value since Part 3b; the line's own `line_total_minor` holds the share this stage bills.
-- Neither reader has ever returned the first one. Both do now, under the money gate that already governs
-- every other amount they return: `invoices.view_price` on the staff read, `include_money` on the customer
-- document. The contract names them "Item total" and "Due this invoice"; that naming lives in the browser,
-- because these two functions return facts, not labels.
--
-- The chain matters here. Claims attach to the root of a correction chain, not to the invoice that happens
-- to be live, so a D3 correction of a progress bill finds the same stage and keeps the same context -- which
-- is exactly what makes correction, rather than void, the right answer for these bills.

-- 1. The stage a bill belongs to ------------------------------------------------------------------------------

create or replace function private.invoice_progress_context(invoice_row public.invoices)
returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $$
  -- Served by invoice_sources_root_idx (organization_id, root_invoice_id, source_kind, id), then the stage's
  -- own (organization_id, id) unique constraint. At most one installment claim exists per chain.
  select jsonb_build_object(
    'job_id', claim.job_id,
    'installment_id', claim.installment_id,
    'installment_number', claim.installment_number,
    'description', stage.description,
    'is_deposit', stage.is_deposit
  )
  from public.invoice_sources as claim
  join public.job_payment_schedule_items as stage
    on stage.organization_id = claim.organization_id and stage.id = claim.installment_id
  where claim.organization_id = invoice_row.organization_id
    and claim.root_invoice_id = invoice_row.root_invoice_id
    and claim.source_kind = 'installment'
  limit 1;
$$;

comment on function private.invoice_progress_context(public.invoices) is
  'The payment stage a progress invoice bills, or null for an ordinary bill. Read live because both facts '
  'it returns are already permanent: the claim freezes the stage number and the guard trigger freezes the '
  'stage description once a claim exists. Carries no amount -- the money is on the invoice.';

revoke all on function private.invoice_progress_context(public.invoices) from public, anon, authenticated;

-- 2. The staff read model ---------------------------------------------------------------------------------

-- Unchanged from 20260906170000 except: a `progress` key on the document, and
-- `progress_original_amount_minor` on each line, gated with the rest of the money.
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
    -- Null on an ordinary bill, which is how the screen decides whether any of this is a progress invoice.
    -- Identity only, so it needs no money gate of its own.
    'progress', private.invoice_progress_context(invoice_row),
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
        'line_total_minor', case when can_see_price then line.line_total_minor else null end,
        -- The job line's whole value, on a progress bill only. Money, so it follows the money gate: a reader
        -- without invoices.view_price sees the stage this bill belongs to and no amounts at all.
        'progress_original_amount_minor',
          case when can_see_price then line.progress_original_amount_minor else null end
      ) order by line.position, line.id), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = target_organization_id and line.invoice_id = target_invoice_id
    )
  );
end;
$$;

-- 3. The customer's copy ------------------------------------------------------------------------------------

-- Unchanged from 20260906130000 except for the same two additions, gated on include_money rather than a
-- permission: a customer reading their own bill always gets amounts; a price-withheld staff previewer does
-- not, and the numbers stay in the database rather than being sent and then not drawn.
create or replace function private.invoice_customer_document(
  invoice_row public.invoices,
  business_name text,
  derived_status text,
  include_money boolean
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  deposit_applied_minor bigint := 0;
  payment_received_minor bigint := 0;
  progress jsonb;
begin
  if include_money then
    select
      coalesce(sum(case when entry.deposit_event_id is not null then signed else 0 end), 0),
      coalesce(sum(case when entry.payment_event_id is not null then signed else 0 end), 0)
    into deposit_applied_minor, payment_received_minor
    from (
      select
        allocation.deposit_event_id,
        allocation.payment_event_id,
        case when allocation.entry_type = 'applied'
          then allocation.amount_minor else -allocation.amount_minor end as signed
      from public.invoice_payment_allocations as allocation
      where allocation.organization_id = invoice_row.organization_id
        and allocation.invoice_id = invoice_row.id
    ) as entry;
  end if;

  progress := private.invoice_progress_context(invoice_row);

  return jsonb_build_object(
    'business', jsonb_build_object('name', business_name),
    'invoice', jsonb_build_object(
      'invoice_number', invoice_row.invoice_number,
      'subject', invoice_row.subject,
      'currency_code', invoice_row.currency_code,
      'status', derived_status,
      'issue_date', invoice_row.issue_date,
      'due_date', invoice_row.due_date,
      'due_date_source', invoice_row.due_date_source,
      'payment_term_snapshot', invoice_row.payment_term_snapshot,
      'contract_disclaimer', invoice_row.contract_disclaimer
    ),
    'customer', invoice_row.customer_snapshot,
    'billing_address', invoice_row.billing_address_snapshot,
    'service_properties', invoice_row.service_properties,
    -- Which stage of the agreed payment schedule this bill is. Named, numbered, and nothing about the
    -- stages that come after it.
    'progress', case when progress is null then null else jsonb_build_object(
      'installment_number', progress -> 'installment_number',
      'description', progress -> 'description',
      'is_deposit', progress -> 'is_deposit'
    ) end,
    'lines', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'line_id', line.id,
          'position', line.position,
          'line_kind', line.line_kind,
          'name', line.name,
          'description', line.description,
          'unit_label', line.unit_label,
          'quantity', line.quantity,
          'service_date', line.service_date
        )
        || case when include_money
             then jsonb_build_object(
               'unit_price_minor', line.unit_price_minor,
               'line_total_minor', line.line_total_minor)
             else '{}'::jsonb end
        -- The whole item, beside the share this bill asks for. Only on a progress bill, and only with the
        -- rest of the money.
        || case when include_money and progress is not null
             then jsonb_build_object(
               'progress_original_amount_minor', line.progress_original_amount_minor)
             else '{}'::jsonb end
        order by line.position, line.id
      ), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = invoice_row.organization_id
        and line.invoice_id = invoice_row.id
    ),
    'money', case when include_money then jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount', case when invoice_row.discount_minor > 0 then jsonb_build_object(
        'name', invoice_row.discount_name,
        'type', invoice_row.discount_type,
        'value', invoice_row.discount_value,
        'amount_minor', invoice_row.discount_minor
      ) else null end,
      'tax', case when invoice_row.tax_minor > 0 then jsonb_build_object(
        'name', invoice_row.tax_name,
        'rate_basis_points', invoice_row.tax_rate_basis_points,
        'amount_minor', invoice_row.tax_minor
      ) else null end,
      'total_minor', invoice_row.total_minor,
      'deposit_applied_minor', deposit_applied_minor,
      'payment_received_minor', payment_received_minor,
      'balance_due_minor', invoice_row.total_minor - deposit_applied_minor - payment_received_minor
    ) else null end
  );
end;
$$;

notify pgrst, 'reload schema';
