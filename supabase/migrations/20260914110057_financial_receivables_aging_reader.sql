-- CRM launch readiness, financial reconciliation Part 2: current receivables aging by Client.
--
-- This is a current snapshot grouped by an explicit organization business date. It does not reconstruct a
-- historical balance: allocations and unused credit are read in their current corrected state. Effective
-- Invoice balances are aged by due date into not due, 1-30, 31-60, 61-90 and 91+ days. Client credit stays
-- separate so a contractor can see both the bills and the customer's unused money before the net balance.
--
-- Both functions deliberately repeat one set-based balance expression. The page is keyset-bounded and the
-- summary runs over the full result, so changing the visible page never changes the totals. Existing indexes
-- cover effective Invoices, allocations, receipts, Quotes and deposit reversals; verification decides whether
-- any additional index has earned its write cost.

create or replace function public.financial_client_aging_page(
  target_organization_id uuid,
  report_as_of date,
  cursor_sort_name text default null,
  cursor_client_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  client_id uuid,
  client_display_name text,
  client_company_name text,
  sort_name text,
  currency_code text,
  outstanding_minor bigint,
  not_due_minor bigint,
  overdue_1_30_minor bigint,
  overdue_31_60_minor bigint,
  overdue_61_90_minor bigint,
  overdue_91_plus_minor bigint,
  available_credit_minor bigint,
  client_balance_minor bigint,
  open_invoice_count bigint
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
  if report_as_of is null then
    raise exception 'Choose a valid aging date.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_sort_name is null) <> (cursor_client_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

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
      sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date >= report_as_of)::bigint as not_due_minor,
      sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of
          and invoice.due_date >= report_as_of - 30)::bigint as overdue_1_30_minor,
      sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of - 30
          and invoice.due_date >= report_as_of - 60)::bigint as overdue_31_60_minor,
      sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of - 60
          and invoice.due_date >= report_as_of - 90)::bigint as overdue_61_90_minor,
      sum(invoice.total_minor - coalesce(allocation.allocated_minor, 0))
        filter (where invoice.due_date < report_as_of - 90)::bigint as overdue_91_plus_minor,
      count(*)::bigint as open_invoice_count
    from public.invoices as invoice
    left join allocation_by_invoice as allocation on allocation.invoice_id = invoice.id
    where invoice.organization_id = target_organization_id
      and invoice.is_effective_receivable
    group by invoice.client_id
  ),
  manual_credit as (
    select receipt.client_id,
      (sum(receipt.amount_minor) filter (
        where receipt.event_type = 'received'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = receipt.organization_id
              and correction.original_event_id = receipt.id
              and correction.event_type = 'reversed'
          )
      ) - coalesce(sum(receipt.amount_minor) filter (where receipt.event_type = 'refunded'), 0))::bigint
        as received_minor
    from public.client_payment_events as receipt
    where receipt.organization_id = target_organization_id
    group by receipt.client_id
  ),
  deposit_credit as (
    select quote.client_id, sum(deposit.amount_minor)::bigint as received_minor
    from public.quote_deposit_events as deposit
    join public.quotes as quote
      on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
    where deposit.organization_id = target_organization_id
      and deposit.event_type = 'received'
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
    select client.id as client_id,
      client.display_name,
      client.company_name,
      lower(coalesce(nullif(client.company_name, ''), client.display_name, '')) as sort_name,
      settings.currency_code,
      coalesce(receivable.outstanding_minor, 0)::bigint as outstanding_minor,
      coalesce(receivable.not_due_minor, 0)::bigint as not_due_minor,
      coalesce(receivable.overdue_1_30_minor, 0)::bigint as overdue_1_30_minor,
      coalesce(receivable.overdue_31_60_minor, 0)::bigint as overdue_31_60_minor,
      coalesce(receivable.overdue_61_90_minor, 0)::bigint as overdue_61_90_minor,
      coalesce(receivable.overdue_91_plus_minor, 0)::bigint as overdue_91_plus_minor,
      (coalesce(manual.received_minor, 0) + coalesce(deposit.received_minor, 0)
        - coalesce(committed.allocated_minor, 0))::bigint as available_credit_minor,
      coalesce(receivable.open_invoice_count, 0)::bigint as open_invoice_count
    from public.clients as client
    join public.organization_settings as settings on settings.organization_id = client.organization_id
    left join receivables as receivable on receivable.client_id = client.id
    left join manual_credit as manual on manual.client_id = client.id
    left join deposit_credit as deposit on deposit.client_id = client.id
    left join client_allocations as committed on committed.client_id = client.id
    where client.organization_id = target_organization_id
  )
  select balance.client_id, balance.display_name, balance.company_name, balance.sort_name,
    balance.currency_code, balance.outstanding_minor, balance.not_due_minor,
    balance.overdue_1_30_minor, balance.overdue_31_60_minor, balance.overdue_61_90_minor,
    balance.overdue_91_plus_minor, balance.available_credit_minor,
    balance.outstanding_minor - balance.available_credit_minor, balance.open_invoice_count
  from balances as balance
  where (balance.outstanding_minor <> 0 or balance.available_credit_minor <> 0)
    and (
      cursor_sort_name is null
      or (sort_direction = 'asc' and (balance.sort_name, balance.client_id) > (cursor_sort_name, cursor_client_id))
      or (sort_direction = 'desc' and (balance.sort_name, balance.client_id) < (cursor_sort_name, cursor_client_id))
    )
  order by
    case when sort_direction = 'asc' then balance.sort_name end asc,
    case when sort_direction = 'asc' then balance.client_id end asc,
    case when sort_direction = 'desc' then balance.sort_name end desc,
    case when sort_direction = 'desc' then balance.client_id end desc
  limit resolved_limit;
end;
$$;

comment on function public.financial_client_aging_page(uuid, date, text, uuid, integer, text) is
  'Keyset-paged current Client receivables as of an organization business date. Effective Invoice balance '
  'is split into not-due, 1-30, 31-60, 61-90 and 91+ day buckets; unused credit and net Client balance stay '
  'separate. Requires invoices.view and invoices.view_price and scopes every source row to one organization.';

revoke all on function public.financial_client_aging_page(uuid, date, text, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_client_aging_page(uuid, date, text, uuid, integer, text)
  to authenticated;

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

notify pgrst, 'reload schema';
