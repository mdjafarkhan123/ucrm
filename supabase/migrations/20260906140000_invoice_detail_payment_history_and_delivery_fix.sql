-- Invoices Part 7a: Collect Payment (single invoice) + the financial-history block on the detail read model.
--
-- Bug fix folded in here rather than filed separately, because it is the same function this part must widen
-- anyway: 6c's migration (20260906130000) recreated public.invoice_detail from the pre-6b-1a body to add
-- contract_disclaimer, and in doing so silently dropped two fields 6b-1a had added --
-- client.email and the whole delivery block (last_sent / views). Nothing caught it because 6c was
-- verified at the type/DB level, not clicked through live. The detail page reads `saved.delivery.last_sent`
-- unconditionally once `saved` exists, so every invoice detail view has been throwing since that migration
-- was applied. This migration restores both fields alongside contract_disclaimer and adds payment_history, so
-- the fix and the new field land in one function body instead of two overlapping rewrites.
--
-- No new command is needed to collect a payment: 3b-1's record_client_payment already records the receipt and
-- (via new_allocations) applies it to one or more invoices in one transaction. Single-invoice Collect Payment
-- is that command called with a one-entry allocation list; nothing here changes it. Spreading one payment
-- across a client's several open invoices is Jobber's real behaviour and is explicitly deferred (Jafar
-- approved starting single-invoice only, 2026-09-06) -- the command already supports it whenever that screen
-- is built, so deferring costs nothing at the database layer.

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
    -- Restored (see file header): Sent / Viewed facts on the detail header.
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

comment on function public.invoice_detail(uuid, uuid) is
  'One whole invoice for the detail screen: its frozen document, derived contract status, revision, money and '
  'payment_history (both gated on invoices.view_price), a delivery block with the last email sent and whether '
  'the customer has opened it, and the client''s email. Definer; checks invoices.view and scopes to the one '
  'organization.';

revoke all on function public.invoice_detail(uuid, uuid) from public, anon;
grant execute on function public.invoice_detail(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
