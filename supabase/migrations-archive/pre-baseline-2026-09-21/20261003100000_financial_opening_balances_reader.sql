-- Financial reconciliation, Part 6: opening balances join the accountant CSV package and reconciled Client
-- balance.
--
-- Contract (docs/financial-reconciliation-contract.md, "Opening balances"): these facts "appear in their own
-- export and in reconciled Client balances. They do not enter current-period sales, cash, tax, Job
-- profitability, or Pipeline results." Client balance's own definition never changes: "outstanding less
-- available credit" -- an active (unreplaced) opening receivable is additional outstanding, an active opening
-- credit is additional available credit, so both existing balance readers only need their input totals
-- widened, not their formula. A replaced (corrected) fact is invisible everywhere; only its replacement counts.
--
-- Bucketing: opening receivables have no due date, so there is no invoice-style aging bucket for them. They are
-- folded into overdue_91_plus_minor -- an imported balance predates the tracked ledger, so treating it as the
-- oldest money owed is the conservative, defensible choice -- which keeps the existing invariant that the four
-- due-date buckets still sum to outstanding_minor.
--
-- One helper avoids writing this sum three times (the aging page, the aging summary, and the invoice-page
-- balance) and disagreeing with itself later.

create or replace function private.client_opening_balance_totals(
  target_organization_id uuid,
  target_client_ids uuid[] default null
)
returns table (
  client_id uuid,
  receivable_minor bigint,
  credit_minor bigint
)
language sql
stable
set search_path = pg_catalog, public
as $$
  select fact.client_id,
    coalesce(sum(fact.amount_minor) filter (where fact.balance_type = 'receivable'), 0)::bigint,
    coalesce(sum(fact.amount_minor) filter (where fact.balance_type = 'credit'), 0)::bigint
  from public.client_opening_balances as fact
  where fact.organization_id = target_organization_id
    and fact.replaced_at is null
    and (target_client_ids is null or fact.client_id = any(target_client_ids))
  group by fact.client_id;
$$;

comment on function private.client_opening_balance_totals(uuid, uuid[]) is
  'Each named Client''s active (unreplaced) opening-balance facts, summed by type. The one place this sum is '
  'written; every balance reader that includes opening balances calls this instead of repeating the filter.';

revoke all on function private.client_opening_balance_totals(uuid, uuid[]) from public;
revoke execute on function private.client_opening_balance_totals(uuid, uuid[]) from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Current receivables aging (feeds client_balances.csv and the Part 2 aging screen).
-- ---------------------------------------------------------------------------------------------------------

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
  opening as (
    select * from private.client_opening_balance_totals(target_organization_id)
  ),
  balances as (
    select client.id as client_id,
      client.display_name,
      client.company_name,
      lower(coalesce(nullif(client.company_name, ''), client.display_name, '')) as sort_name,
      settings.currency_code,
      (coalesce(receivable.outstanding_minor, 0) + coalesce(opening.receivable_minor, 0))::bigint
        as outstanding_minor,
      coalesce(receivable.not_due_minor, 0)::bigint as not_due_minor,
      coalesce(receivable.overdue_1_30_minor, 0)::bigint as overdue_1_30_minor,
      coalesce(receivable.overdue_31_60_minor, 0)::bigint as overdue_31_60_minor,
      coalesce(receivable.overdue_61_90_minor, 0)::bigint as overdue_61_90_minor,
      (coalesce(receivable.overdue_91_plus_minor, 0) + coalesce(opening.receivable_minor, 0))::bigint
        as overdue_91_plus_minor,
      (coalesce(manual.received_minor, 0) + coalesce(deposit.received_minor, 0)
        - coalesce(committed.allocated_minor, 0) + coalesce(opening.credit_minor, 0))::bigint
        as available_credit_minor,
      coalesce(receivable.open_invoice_count, 0)::bigint as open_invoice_count
    from public.clients as client
    join public.organization_settings as settings on settings.organization_id = client.organization_id
    left join receivables as receivable on receivable.client_id = client.id
    left join manual_credit as manual on manual.client_id = client.id
    left join deposit_credit as deposit on deposit.client_id = client.id
    left join client_allocations as committed on committed.client_id = client.id
    left join opening on opening.client_id = client.id
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
  'Keyset-paged current Client receivables as of an organization business date. Effective Invoice balance, '
  'plus any active opening receivable, is split into not-due, 1-30, 31-60, 61-90 and 91+ day buckets (opening '
  'receivables fall in 91+); unused credit (including opening credit) and net Client balance stay separate. '
  'Requires invoices.view and invoices.view_price and scopes every source row to one organization.';

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
  opening as (
    select * from private.client_opening_balance_totals(target_organization_id)
  ),
  balances as (
    select coalesce(receivable.outstanding_minor, 0)::bigint as base_outstanding_minor,
      (coalesce(receivable.outstanding_minor, 0) + coalesce(opening.receivable_minor, 0))::bigint
        as outstanding_minor,
      coalesce(receivable.not_due_minor, 0)::bigint as not_due_minor,
      coalesce(receivable.overdue_1_30_minor, 0)::bigint as overdue_1_30_minor,
      coalesce(receivable.overdue_31_60_minor, 0)::bigint as overdue_31_60_minor,
      coalesce(receivable.overdue_61_90_minor, 0)::bigint as overdue_61_90_minor,
      (coalesce(receivable.overdue_91_plus_minor, 0) + coalesce(opening.receivable_minor, 0))::bigint
        as overdue_91_plus_minor,
      (coalesce(manual.received_minor, 0) + coalesce(deposit.received_minor, 0)
        - coalesce(committed.allocated_minor, 0) + coalesce(opening.credit_minor, 0))::bigint
        as available_credit_minor,
      coalesce(receivable.open_invoice_count, 0)::bigint as open_invoice_count
    from public.clients as client
    left join receivables as receivable on receivable.client_id = client.id
    left join manual_credit as manual on manual.client_id = client.id
    left join deposit_credit as deposit on deposit.client_id = client.id
    left join client_allocations as committed on committed.client_id = client.id
    left join opening on opening.client_id = client.id
    where client.organization_id = target_organization_id
  ),
  reportable as (
    select * from balances where balances.outstanding_minor <> 0 or balances.available_credit_minor <> 0
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
  'Whole-result current Client aging totals, including active opening balances. Uses the same '
  'permission-checked balance reader and does not depend on the visible API page.';

revoke all on function public.financial_client_aging_summary(uuid, date) from public, anon;
grant execute on function public.financial_client_aging_summary(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- The invoice-page balance (public.client_account_balance) gains the same opening totals.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.client_account_balance(target_client_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_client_ids is null or cardinality(target_client_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct client.organization_id) into organizations
  from public.clients as client
  where client.id = any(target_client_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those clients do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'invoices.view') then
    raise exception 'You do not have access to these clients'' billing.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(org, caller, 'invoices.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(client.id::text, jsonb_build_object(
      'currency_code', settings.currency_code,
      'outstanding_minor', outstanding.amount_minor + coalesce(opening.receivable_minor, 0),
      'available_credit_minor', credit.amount_minor + coalesce(opening.credit_minor, 0),
      'account_balance_minor',
        (outstanding.amount_minor + coalesce(opening.receivable_minor, 0))
        - (credit.amount_minor + coalesce(opening.credit_minor, 0))
    )), '{}'::jsonb)
  into answer
  from public.clients as client
  cross join public.organization_settings as settings
  -- What the effective bills still ask for. The partial index on is_effective_receivable is what keeps this
  -- to the client's open ledger instead of their whole billing history.
  cross join lateral (
    select coalesce(sum(invoice.total_minor - coalesce(entry.applied_minor, 0)), 0)::bigint as amount_minor
    from public.invoices as invoice
    left join lateral (
      select sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end) as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id
        and entry.invoice_id = invoice.id
    ) as entry on true
    where invoice.organization_id = client.organization_id
      and invoice.client_id = client.id
      and invoice.is_effective_receivable
  ) as outstanding
  cross join lateral (
    select (
      -- Manual receipts that were not reversed away.
      coalesce((
        select sum(receipt.amount_minor)
        from public.client_payment_events as receipt
        where receipt.organization_id = client.organization_id
          and receipt.client_id = client.id
          and receipt.event_type = 'received'
          and not exists (
            select 1 from public.client_payment_events as correction
            where correction.organization_id = receipt.organization_id
              and correction.original_event_id = receipt.id
              and correction.event_type = 'reversed'
          )
      ), 0)
      -- Quote deposits, reused where they already live, minus the ones the quote workspace reversed.
      + coalesce((
        select sum(deposit.amount_minor)
        from public.quote_deposit_events as deposit
        join public.quotes as quote
          on quote.organization_id = deposit.organization_id and quote.id = deposit.quote_id
        where deposit.organization_id = client.organization_id
          and quote.client_id = client.id
          and deposit.event_type = 'received'
          and not exists (
            select 1 from public.quote_deposit_events as reversal
            where reversal.organization_id = deposit.organization_id
              and reversal.reversed_event_id = deposit.id
          )
      ), 0)
      -- Money actually sent back is no longer the client's to spend.
      - coalesce((
        select sum(refund.amount_minor)
        from public.client_payment_events as refund
        where refund.organization_id = client.organization_id
          and refund.client_id = client.id
          and refund.event_type = 'refunded'
      ), 0)
      -- Money committed to a bill is not available, whichever kind of receipt it came from.
      - coalesce((
        select sum(case when entry.entry_type = 'applied'
          then entry.amount_minor else -entry.amount_minor end)
        from public.invoice_payment_allocations as entry
        where entry.organization_id = client.organization_id
          and entry.client_id = client.id
      ), 0)
    )::bigint as amount_minor
  ) as credit
  left join lateral (
    select receivable_minor, credit_minor
    from private.client_opening_balance_totals(org, array[client.id])
  ) as opening on true
  where client.organization_id = org
    and client.id = any(target_client_ids)
    and settings.organization_id = org;

  return answer;
end;
$$;

comment on function public.client_account_balance(uuid[]) is
  'The two client-level money numbers the contract keeps apart: what their effective bills still ask for, '
  'and money of theirs that is neither refunded nor already committed to a bill -- each widened by the '
  'Client''s active opening-balance facts. Never counts a receipt twice and never counts a voided, superseded, '
  'written-off or replaced fact.';

revoke all on function public.client_account_balance(uuid[]) from public;
revoke execute on function public.client_account_balance(uuid[]) from anon;
grant execute on function public.client_account_balance(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- opening_balances.csv: the currently active facts themselves, for the accountant package.
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.financial_opening_balances_page(
  target_organization_id uuid,
  cursor_as_of_date date default null,
  cursor_opening_balance_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  opening_balance_id uuid,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  currency_code text,
  balance_type text,
  receivable_minor bigint,
  credit_minor bigint,
  as_of_date date,
  source_note text,
  root_opening_balance_id uuid,
  predecessor_opening_balance_id uuid,
  import_batch_id uuid,
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
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_as_of_date is null) <> (cursor_opening_balance_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select fact.id, client.id, client.display_name, client.company_name, fact.currency_code, fact.balance_type,
    case when fact.balance_type = 'receivable' then fact.amount_minor else 0 end::bigint,
    case when fact.balance_type = 'credit' then fact.amount_minor else 0 end::bigint,
    fact.as_of_date, fact.source_note, fact.root_opening_balance_id, fact.predecessor_opening_balance_id,
    fact.import_batch_id, fact.created_at
  from public.client_opening_balances as fact
  join public.clients as client
    on client.organization_id = fact.organization_id and client.id = fact.client_id
  where fact.organization_id = target_organization_id
    and fact.replaced_at is null
    and (
      cursor_as_of_date is null
      or (sort_direction = 'asc' and (fact.as_of_date, fact.id) > (cursor_as_of_date, cursor_opening_balance_id))
      or (sort_direction = 'desc' and (fact.as_of_date, fact.id) < (cursor_as_of_date, cursor_opening_balance_id))
    )
  order by
    case when sort_direction = 'asc' then fact.as_of_date end asc,
    case when sort_direction = 'asc' then fact.id end asc,
    case when sort_direction = 'desc' then fact.as_of_date end desc,
    case when sort_direction = 'desc' then fact.id end desc
  limit resolved_limit;
end;
$$;

comment on function public.financial_opening_balances_page(uuid, date, uuid, integer, text) is
  'Keyset-paged active (unreplaced) opening-balance facts. A correction retires its predecessor, which drops '
  'out of this page but stays traceable via root_opening_balance_id/predecessor_opening_balance_id. Requires '
  'invoices.view and invoices.view_price and scopes every row to one organization.';

revoke all on function public.financial_opening_balances_page(uuid, date, uuid, integer, text) from public, anon;
grant execute on function public.financial_opening_balances_page(uuid, date, uuid, integer, text)
  to authenticated;

create or replace function public.financial_opening_balances_summary(
  target_organization_id uuid
)
returns table (
  receivable_total_minor bigint,
  credit_total_minor bigint,
  net_minor bigint,
  fact_count bigint
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

  return query
  select
    coalesce(sum(fact.amount_minor) filter (where fact.balance_type = 'receivable'), 0)::bigint,
    coalesce(sum(fact.amount_minor) filter (where fact.balance_type = 'credit'), 0)::bigint,
    coalesce(sum(case when fact.balance_type = 'receivable' then fact.amount_minor else -fact.amount_minor end), 0)
      ::bigint,
    count(*)::bigint
  from public.client_opening_balances as fact
  where fact.organization_id = target_organization_id
    and fact.replaced_at is null;
end;
$$;

comment on function public.financial_opening_balances_summary(uuid) is
  'Whole-result totals over the same active opening-balance facts financial_opening_balances_page reads.';

revoke all on function public.financial_opening_balances_summary(uuid) from public, anon;
grant execute on function public.financial_opening_balances_summary(uuid) to authenticated;

notify pgrst, 'reload schema';
