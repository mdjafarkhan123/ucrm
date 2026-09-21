-- Invoices Part 6c: the contract disclaimer.
--
-- Quotes already let a contractor write a disclaimer -- the terms the client agrees to -- shown on the
-- document, separate from anything else, frozen once the client can see it. Invoices promised the same thing
-- (docs/invoice-behavior-contract.md lines 127, 129) but never got the column or the command. This adds
-- exactly that, on the invoice row itself: unlike a quote, an invoice has no separate draft-version row, so
-- the disclaimer lives directly on public.invoices next to subject and dates.
--
-- It deliberately does not reuse update_invoice_details. That command stays editable after issue because the
-- previous document is retained in history first -- the bill's numbers and dates may legitimately be
-- corrected post-issue. The disclaimer is different: once a customer could have seen it, its wording is fixed,
-- the same rule quotes enforce by refusing any edit once a quote leaves draft.

-- 1. The column --------------------------------------------------------------------------------------------

alter table public.invoices
  add column contract_disclaimer text
    check (contract_disclaimer is null or char_length(contract_disclaimer) <= 5000);

comment on column public.invoices.contract_disclaimer is
  'The terms the customer is agreeing to by paying this bill. Plain text the contractor types on the draft. '
  'Frozen the moment the invoice is issued (document_frozen_at set) -- update_invoice_contract_disclaimer is '
  'the only writer and refuses once that is set, same rule quotes use for their contract_disclaimer.';

-- 2. Carry it through every reader that already assembles the document -----------------------------------

-- History: the snapshot invoices already keep before a permitted post-issue edit to another field. This just
-- means a corrected subject or due date does not silently drop the disclaimer from the retained copy.
create or replace function private.invoice_document_snapshot(target_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  invoice_row public.invoices;
begin
  select * into invoice_row from public.invoices where id = target_invoice_id;
  if not found then
    raise exception 'That invoice was not found.' using errcode = 'P0404';
  end if;

  return jsonb_build_object(
    'invoice_id', invoice_row.id,
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
    'discount', jsonb_build_object(
      'name', invoice_row.discount_name,
      'type', invoice_row.discount_type,
      'value', invoice_row.discount_value
    ),
    'tax', jsonb_build_object(
      'source', invoice_row.tax_source,
      'name', invoice_row.tax_name,
      'rate_basis_points', invoice_row.tax_rate_basis_points
    ),
    'totals', jsonb_build_object(
      'subtotal_minor', invoice_row.subtotal_minor,
      'discount_minor', invoice_row.discount_minor,
      'tax_minor', invoice_row.tax_minor,
      'total_minor', invoice_row.total_minor
    ),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'line_id', line.id,
        'position', line.position,
        'line_kind', line.line_kind,
        'category', line.category,
        'name', line.name,
        'description', line.description,
        'unit_label', line.unit_label,
        'quantity', line.quantity,
        'unit_price_minor', line.unit_price_minor,
        'is_taxable', line.is_taxable,
        'service_date', line.service_date,
        'line_total_minor', line.line_total_minor
      ) order by line.position, line.id), '[]'::jsonb)
      from public.invoice_lines as line
      where line.organization_id = invoice_row.organization_id
        and line.invoice_id = invoice_row.id
    )
  );
end;
$$;

-- The staff detail read model: add the field next to the other frozen header facts.
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
  else
    money := null;
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
        'company_name', client.company_name
      ) end
      from public.clients as client
      where client.organization_id = target_organization_id and client.id = invoice_row.client_id
    ),
    'money', money,
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

-- The customer-facing document: shown next to (never merged with) the payment-term line the screen already
-- renders as its own footer.
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

-- 3. The one writer -----------------------------------------------------------------------------------------

-- Entering, saving and editing the disclaimer on a draft. Refuses once the document has frozen (issued, or
-- settled while still a draft), the same freeze quotes get by refusing any edit once the quote leaves draft --
-- an invoice needs its own check because every other field on this row stays editable after that point.
create or replace function public.update_invoice_contract_disclaimer(
  target_organization_id uuid,
  target_invoice_id uuid,
  expected_revision integer,
  new_disclaimer text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  invoice_row public.invoices;
  clean_disclaimer text := nullif(trim(coalesce(new_disclaimer, '')), '');
  new_revision integer;
begin
  invoice_row := private.lock_invoice_for_edit(
    target_organization_id, target_invoice_id, expected_revision
  );

  if invoice_row.document_frozen_at is not null then
    raise exception 'This invoice has been issued, so its contract disclaimer cannot be changed.'
      using errcode = 'check_violation';
  end if;

  if clean_disclaimer is not null and char_length(clean_disclaimer) > 5000 then
    raise exception 'The contract disclaimer is too long.' using errcode = 'check_violation';
  end if;

  update public.invoices
  set contract_disclaimer = clean_disclaimer, revision = invoice_row.revision + 1
  where organization_id = target_organization_id and id = target_invoice_id
  returning revision into new_revision;

  perform private.record_invoice_event(
    target_organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.disclaimer_updated', caller, new_revision, null, '{}'::jsonb, false, null
  );

  return jsonb_build_object('revision', new_revision);
end;
$$;

comment on function public.update_invoice_contract_disclaimer(uuid, uuid, integer, text) is
  'Enters, saves or clears the draft''s contract disclaimer. Refused once the document has frozen -- the '
  'wording a customer could have already seen never quietly changes underneath them.';

revoke all on function public.update_invoice_contract_disclaimer(uuid, uuid, integer, text) from public;
revoke execute on function public.update_invoice_contract_disclaimer(uuid, uuid, integer, text) from anon;
grant execute on function public.update_invoice_contract_disclaimer(uuid, uuid, integer, text)
  to authenticated;

notify pgrst, 'reload schema';
