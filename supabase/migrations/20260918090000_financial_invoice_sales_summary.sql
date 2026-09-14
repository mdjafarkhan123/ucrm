-- CRM launch readiness, financial reconciliation Part 2: whole-range billed-sales totals.
--
-- This summary deliberately repeats the current-sale predicate owned by financial_invoice_sales_page. It
-- answers for the full requested date range rather than whichever page is visible in the browser. The
-- existing partial index supports the tenant and business-date range; no stored aggregate or cache is
-- introduced until representative measurements show that the live aggregate misses its budget.

create or replace function public.financial_invoice_sales_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  net_sales_minor bigint,
  tax_minor bigint,
  billed_total_minor bigint,
  write_off_count bigint,
  historical_status_only_closure_count bigint
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
  select
    coalesce(sum(invoice.total_minor - invoice.tax_minor), 0)::bigint,
    coalesce(sum(invoice.tax_minor), 0)::bigint,
    coalesce(sum(invoice.total_minor), 0)::bigint,
    count(*) filter (where invoice.written_off_at is not null),
    count(*) filter (where invoice.marked_received_at is not null)
  from public.invoices as invoice
  where invoice.organization_id = target_organization_id
    and (invoice.issued_at is not null or invoice.recognized_at is not null)
    and invoice.voided_at is null
    and invoice.replaced_at is null
    and invoice.issue_date >= report_from
    and invoice.issue_date < report_to;
end;
$$;

comment on function public.financial_invoice_sales_summary(uuid, date, date) is
  'Whole-range current billed-sales totals from the same frozen Invoice predicate as '
  'financial_invoice_sales_page. Requires invoices.view and invoices.view_price, scopes every row to one '
  'organization, retains write-offs, and counts historical status-only closures as exceptions.';

revoke all on function public.financial_invoice_sales_summary(uuid, date, date)
  from public, anon;
grant execute on function public.financial_invoice_sales_summary(uuid, date, date)
  to authenticated;

notify pgrst, 'reload schema';
