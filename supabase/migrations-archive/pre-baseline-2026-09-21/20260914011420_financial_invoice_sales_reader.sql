-- CRM launch readiness, financial reconciliation Part 2: the first financial reader.
--
-- This is the row source for the billed-sales report and its later CSV. It deliberately reads the frozen
-- invoice rather than live Jobs or line items: an issued Invoice (or a Draft recognized through full
-- payment) is the sale, and its stored issue_date is the business date. Voided and superseded Invoices stay
-- in their own correction history but do not remain current sales. Write-offs remain sales and historical
-- status-only closures are called out as reconciliation exceptions.
--
-- The read is keyset-paged on the stored business date plus Invoice id, requires an inclusive start and
-- exclusive end date, and caps each call. One partial index matches that exact current-sales predicate. No
-- cache or maintained aggregate is introduced: the frozen Invoice remains the only source of these totals.

create index invoices_current_sales_issue_date_idx
  on public.invoices (organization_id, issue_date, id)
  where (issued_at is not null or recognized_at is not null)
    and voided_at is null
    and replaced_at is null;

create or replace function public.financial_invoice_sales_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_sale_date date default null,
  cursor_invoice_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  invoice_id uuid,
  invoice_number integer,
  root_invoice_id uuid,
  predecessor_invoice_id uuid,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  subject text,
  sale_date date,
  recognition_basis text,
  currency_code text,
  net_sales_minor bigint,
  tax_minor bigint,
  total_minor bigint,
  written_off_at timestamptz,
  has_unsettled_legacy_closure boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  resolved_limit integer;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;

  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_sale_date is null) <> (cursor_invoice_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  -- Callers may ask for one extra row to decide whether another page exists. The database still owns the
  -- hard ceiling, so a malformed or hostile request cannot turn this RPC into an unbounded export.
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  if sort_direction = 'desc' then
    return query
    select
      invoice.id,
      invoice.invoice_number,
      invoice.root_invoice_id,
      invoice.predecessor_invoice_id,
      invoice.client_id,
      invoice.customer_snapshot ->> 'display_name',
      invoice.customer_snapshot ->> 'company_name',
      invoice.subject,
      invoice.issue_date,
      case when invoice.issued_at is not null then 'issued' else 'paid_draft' end,
      invoice.currency_code,
      invoice.total_minor - invoice.tax_minor,
      invoice.tax_minor,
      invoice.total_minor,
      invoice.written_off_at,
      invoice.marked_received_at is not null,
      invoice.created_at
    from public.invoices as invoice
    where invoice.organization_id = target_organization_id
      and (invoice.issued_at is not null or invoice.recognized_at is not null)
      and invoice.voided_at is null
      and invoice.replaced_at is null
      and invoice.issue_date >= report_from
      and invoice.issue_date < report_to
      and (
        cursor_sale_date is null
        or (invoice.issue_date, invoice.id) < (cursor_sale_date, cursor_invoice_id)
      )
    order by invoice.issue_date desc, invoice.id desc
    limit resolved_limit;
    return;
  end if;

  return query
  select
    invoice.id,
    invoice.invoice_number,
    invoice.root_invoice_id,
    invoice.predecessor_invoice_id,
    invoice.client_id,
    invoice.customer_snapshot ->> 'display_name',
    invoice.customer_snapshot ->> 'company_name',
    invoice.subject,
    invoice.issue_date,
    case when invoice.issued_at is not null then 'issued' else 'paid_draft' end,
    invoice.currency_code,
    invoice.total_minor - invoice.tax_minor,
    invoice.tax_minor,
    invoice.total_minor,
    invoice.written_off_at,
    invoice.marked_received_at is not null,
    invoice.created_at
  from public.invoices as invoice
  where invoice.organization_id = target_organization_id
    and (invoice.issued_at is not null or invoice.recognized_at is not null)
    and invoice.voided_at is null
    and invoice.replaced_at is null
    and invoice.issue_date >= report_from
    and invoice.issue_date < report_to
    and (
      cursor_sale_date is null
      or (invoice.issue_date, invoice.id) > (cursor_sale_date, cursor_invoice_id)
    )
  order by invoice.issue_date asc, invoice.id asc
  limit resolved_limit;
end;
$$;

comment on function public.financial_invoice_sales_page(
  uuid, date, date, date, uuid, integer, text
) is
  'Keyset-paged current billed sales from frozen Invoice facts. The date range is start-inclusive and '
  'end-exclusive. Requires invoices.view and invoices.view_price, scopes every row to one organization, '
  'excludes voided and superseded Invoices, retains write-offs, and flags historical status-only closures.';

revoke all on function public.financial_invoice_sales_page(
  uuid, date, date, date, uuid, integer, text
) from public, anon;
grant execute on function public.financial_invoice_sales_page(
  uuid, date, date, date, uuid, integer, text
) to authenticated;

notify pgrst, 'reload schema';
