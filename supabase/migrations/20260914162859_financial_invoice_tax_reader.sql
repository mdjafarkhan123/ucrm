-- CRM launch readiness, financial reconciliation Part 2: tax reader.
--
-- Tax is reported from the same effective Invoice population as billed sales. The stored Invoice tax is
-- the sole authority: this reader never recalculates tax from today's rates or mutable source work. The
-- existing invoices_current_sales_issue_date_idx supports this tenant/date predicate and keyset order.

create or replace function public.financial_invoice_tax_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_tax_date date default null,
  cursor_invoice_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  invoice_id uuid,
  invoice_number integer,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  subject text,
  tax_date date,
  recognition_basis text,
  currency_code text,
  tax_source text,
  tax_name text,
  tax_rate_basis_points integer,
  net_sales_minor bigint,
  tax_minor bigint,
  total_minor bigint,
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
  if (cursor_tax_date is null) <> (cursor_invoice_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  if sort_direction = 'desc' then
    return query
    select invoice.id, invoice.invoice_number, invoice.client_id,
      invoice.customer_snapshot ->> 'display_name', invoice.customer_snapshot ->> 'company_name',
      invoice.subject, invoice.issue_date,
      case when invoice.issued_at is not null then 'issued' else 'paid_draft' end,
      invoice.currency_code, invoice.tax_source, invoice.tax_name, invoice.tax_rate_basis_points,
      invoice.total_minor - invoice.tax_minor, invoice.tax_minor, invoice.total_minor, invoice.created_at
    from public.invoices as invoice
    where invoice.organization_id = target_organization_id
      and (invoice.issued_at is not null or invoice.recognized_at is not null)
      and invoice.voided_at is null and invoice.replaced_at is null
      and invoice.issue_date >= report_from and invoice.issue_date < report_to
      and (cursor_tax_date is null or (invoice.issue_date, invoice.id) < (cursor_tax_date, cursor_invoice_id))
    order by invoice.issue_date desc, invoice.id desc
    limit resolved_limit;
    return;
  end if;

  return query
  select invoice.id, invoice.invoice_number, invoice.client_id,
    invoice.customer_snapshot ->> 'display_name', invoice.customer_snapshot ->> 'company_name',
    invoice.subject, invoice.issue_date,
    case when invoice.issued_at is not null then 'issued' else 'paid_draft' end,
    invoice.currency_code, invoice.tax_source, invoice.tax_name, invoice.tax_rate_basis_points,
    invoice.total_minor - invoice.tax_minor, invoice.tax_minor, invoice.total_minor, invoice.created_at
  from public.invoices as invoice
  where invoice.organization_id = target_organization_id
    and (invoice.issued_at is not null or invoice.recognized_at is not null)
    and invoice.voided_at is null and invoice.replaced_at is null
    and invoice.issue_date >= report_from and invoice.issue_date < report_to
    and (cursor_tax_date is null or (invoice.issue_date, invoice.id) > (cursor_tax_date, cursor_invoice_id))
  order by invoice.issue_date asc, invoice.id asc
  limit resolved_limit;
end;
$$;

create or replace function public.financial_invoice_tax_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  net_sales_minor bigint,
  tax_minor bigint,
  billed_total_minor bigint,
  invoice_count bigint,
  taxed_invoice_count bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  return query
  select coalesce(sum(invoice.total_minor - invoice.tax_minor), 0)::bigint,
    coalesce(sum(invoice.tax_minor), 0)::bigint,
    coalesce(sum(invoice.total_minor), 0)::bigint,
    count(*), count(*) filter (where invoice.tax_minor > 0)
  from public.invoices as invoice
  where invoice.organization_id = target_organization_id
    and (invoice.issued_at is not null or invoice.recognized_at is not null)
    and invoice.voided_at is null and invoice.replaced_at is null
    and invoice.issue_date >= report_from and invoice.issue_date < report_to;
end;
$$;

comment on function public.financial_invoice_tax_page(uuid, date, date, date, uuid, integer, text) is
  'Keyset-paged tax ledger from effective frozen Invoices. Requires invoices.view and invoices.view_price; '
  'the date range is inclusive/exclusive and all rows are explicitly organization scoped.';
comment on function public.financial_invoice_tax_summary(uuid, date, date) is
  'Whole-range tax totals from the same effective frozen Invoice predicate as financial_invoice_tax_page.';

revoke all on function public.financial_invoice_tax_page(uuid, date, date, date, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_invoice_tax_page(uuid, date, date, date, uuid, integer, text)
  to authenticated;
revoke all on function public.financial_invoice_tax_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_invoice_tax_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
