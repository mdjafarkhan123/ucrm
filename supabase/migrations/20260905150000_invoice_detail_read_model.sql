-- Invoices Part 4b: the detail screen's read model.
--
-- The detail page needs one whole invoice: its frozen document (customer, billing and service-property
-- snapshots, terms, lines), its derived contract status, its optimistic-lock revision, and -- for a reader
-- allowed to see it -- its money. private.invoice_document_snapshot already assembles the document, but it is
-- SECURITY DEFINER in the `private` schema (not reachable from PostgREST) and returns every price
-- unconditionally, so it cannot be handed to the browser. The money columns are deliberately off the grant to
-- `authenticated`, exactly as for the list.
--
-- So this is the single-row twin of public.invoice_list_page: one SECURITY DEFINER read that checks
-- invoices.view itself, scopes to the one organization, derives the status through the shared
-- private.invoice_live_status rule (so the detail and the list can never disagree), and gates every amount --
-- line prices, totals, discount and tax figures -- behind invoices.view_price. A reader without that
-- permission still gets the document and the status; the money simply comes back null, the same contract the
-- list and public.invoice_money already follow. It is a bounded point read: the invoice by primary key, its
-- lines by (organization, invoice) -- capped at 100 -- and one inline allocation probe.

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

  -- The same applied-money probe the list uses: applications add, reversals subtract.
  select coalesce(sum(case when entry.entry_type = 'applied'
    then entry.amount_minor else -entry.amount_minor end), 0)::bigint
  into applied_minor
  from public.invoice_payment_allocations as entry
  where entry.organization_id = target_organization_id and entry.invoice_id = target_invoice_id;

  -- A replaced bill keeps the label it was frozen with, so history never ages into Past Due; every other bill
  -- is derived live from the one shared rule.
  derived_status := case
    when invoice_row.replaced_at is not null then invoice_row.frozen_status_label
    else private.invoice_live_status(
      invoice_row.voided_at, invoice_row.written_off_at, invoice_row.issued_at, invoice_row.recognized_at,
      invoice_row.marked_received_at, invoice_row.total_minor, applied_minor, invoice_row.due_date, today)
  end;

  -- Every amount lives here and is withheld whole from a reader without invoices.view_price -- the same shape
  -- public.invoice_money returns, plus the tax's own name and rate so the Tax card can show what was frozen.
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
        -- Prices ride the same gate as the totals: null for a reader without invoices.view_price, never a
        -- misleading zero.
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
  'One whole invoice for the detail screen: its frozen document, derived contract status (via the shared '
  'private.invoice_live_status rule), revision, and -- gated on invoices.view_price -- its money. Definer so a '
  'reader without price access still sees the document and status without ever selecting an amount; checks '
  'invoices.view and scopes to the one organization. The single-row twin of public.invoice_list_page.';

revoke all on function public.invoice_detail(uuid, uuid) from public, anon;
grant execute on function public.invoice_detail(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
