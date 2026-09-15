-- Resolve output-column names as CTE columns inside the PL/pgSQL summary query.
create or replace function public.financial_client_aging_summary(
  target_organization_id uuid,
  report_as_of date
)
returns table (
  outstanding_minor bigint,
  not_due_minor bigint,
  overdue_1_30_minor bigint,
  overdue_31_60_minor bigint,
  overdue_61_90_minor bigint,
  overdue_91_plus_minor bigint,
  available_credit_minor bigint,
  client_balance_minor bigint,
  client_count bigint,
  open_invoice_count bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
#variable_conflict use_column
declare
  caller uuid := (select auth.uid());
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view')
     or not private.member_has_permission(target_organization_id, caller, 'invoices.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_as_of is null then
    raise exception 'Choose a valid aging date.' using errcode = 'invalid_parameter_value';
  end if;

  return query
  with allocation_by_invoice as (
    select allocation.invoice_id,
      sum(case when allocation.entry_type = 'applied'
        then allocation.amount_minor else -allocation.amount_minor end)::bigint as allocated_minor
    from public.invoice_payment_allocations as allocation
    where allocation.organization_id = target_organization_id
    group by allocation.invoice_id
  ),
  receivables as (
    select invoice.client_id,
      sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))::bigint as outstanding_minor,
      coalesce(sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date >= report_as_of), 0)::bigint as not_due_minor,
      coalesce(sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of
          and invoice.due_date >= report_as_of - 30), 0)::bigint as overdue_1_30_minor,
      coalesce(sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of - 30
          and invoice.due_date >= report_as_of - 60), 0)::bigint as overdue_31_60_minor,
      coalesce(sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of - 60
          and invoice.due_date >= report_as_of - 90), 0)::bigint as overdue_61_90_minor,
      coalesce(sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of - 90), 0)::bigint as overdue_91_plus_minor,
      count(*)::bigint as open_invoice_count
    from public.invoices as invoice
    left join allocation_by_invoice as allocation on allocation.invoice_id = invoice.id
    where invoice.organization_id = target_organization_id and invoice.is_effective_receivable
    group by invoice.client_id
  ),
  manual_credit as (
    select receipt.client_id,
      (coalesce(sum(receipt.amount_minor) filter (
        where receipt.event_type = 'received'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = receipt.organization_id
              and correction.original_event_id = receipt.id and correction.event_type = 'reversed'
          )
      ), 0) - coalesce(sum(receipt.amount_minor) filter (
        where receipt.event_type = 'refunded'
      ), 0))::bigint as received_minor
    from public.client_payment_events as receipt
    where receipt.organization_id = target_organization_id
    group by receipt.client_id
  ),
  deposit_credit as (
    select quote.client_id, sum(deposit.amount_minor)::bigint as received_minor
    from public.quote_deposit_events as deposit
    join public.quotes as quote
      on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
    where deposit.organization_id = target_organization_id and deposit.event_type = 'received'
      and not exists (
        select 1 from public.quote_deposit_events as reversal
        where reversal.organization_id = deposit.organization_id
          and reversal.reversed_event_id = deposit.id
      )
    group by quote.client_id
  ),
  client_allocations as (
    select allocation.client_id,
      sum(case when allocation.entry_type = 'applied'
        then allocation.amount_minor else -allocation.amount_minor end)::bigint as allocated_minor
    from public.invoice_payment_allocations as allocation
    where allocation.organization_id = target_organization_id
    group by allocation.client_id
  ),
  balances as (
    select coalesce(receivable.outstanding_minor, 0)::bigint as outstanding_minor,
      coalesce(receivable.not_due_minor, 0)::bigint as not_due_minor,
      coalesce(receivable.overdue_1_30_minor, 0)::bigint as overdue_1_30_minor,
      coalesce(receivable.overdue_31_60_minor, 0)::bigint as overdue_31_60_minor,
      coalesce(receivable.overdue_61_90_minor, 0)::bigint as overdue_61_90_minor,
      coalesce(receivable.overdue_91_plus_minor, 0)::bigint as overdue_91_plus_minor,
      (coalesce(manual.received_minor, 0) + coalesce(deposit.received_minor, 0)
        - coalesce(committed.allocated_minor, 0))::bigint as available_credit_minor,
      coalesce(receivable.open_invoice_count, 0)::bigint as open_invoice_count
    from public.clients as client
    left join receivables as receivable on receivable.client_id = client.id
    left join manual_credit as manual on manual.client_id = client.id
    left join deposit_credit as deposit on deposit.client_id = client.id
    left join client_allocations as committed on committed.client_id = client.id
    where client.organization_id = target_organization_id
  ),
  reportable as (
    select * from balances where outstanding_minor <> 0 or available_credit_minor <> 0
  )
  select coalesce(sum(report_row.outstanding_minor), 0)::bigint,
    coalesce(sum(report_row.not_due_minor), 0)::bigint,
    coalesce(sum(report_row.overdue_1_30_minor), 0)::bigint,
    coalesce(sum(report_row.overdue_31_60_minor), 0)::bigint,
    coalesce(sum(report_row.overdue_61_90_minor), 0)::bigint,
    coalesce(sum(report_row.overdue_91_plus_minor), 0)::bigint,
    coalesce(sum(report_row.available_credit_minor), 0)::bigint,
    coalesce(sum(report_row.outstanding_minor - report_row.available_credit_minor), 0)::bigint,
    count(*)::bigint,
    coalesce(sum(report_row.open_invoice_count), 0)::bigint
  from reportable as report_row;
end;
$$;

comment on function public.financial_client_aging_summary(uuid, date) is
  'Whole-result current Client aging totals. Uses the same permission-checked balance reader and does not '
  'depend on the visible API page.';

revoke all on function public.financial_client_aging_summary(uuid, date) from public, anon;
grant execute on function public.financial_client_aging_summary(uuid, date) to authenticated;
