-- CRM launch readiness, financial reconciliation Part 3: expenses reader.
--
-- One row per recorded Job expense whose expense_date falls inside the report range, so the accountant
-- package can trace the expense cost on the Job profitability report back to each receipt. Expenses are
-- dated by expense_date, a stored business date, exactly as financial_job_profitability_rows dates them,
-- so the two cannot disagree about which month a receipt belongs to.
--
-- Who sees which rows is the expense table's own select policy, restated here because this function is
-- definer and the policy no longer stands between the reader and the rows. Resolved once for the caller:
--
--   jobs.view              -- required to read anything; an 'assigned'-scope member only reaches expenses
--                             on Jobs they are assigned to.
--   expenses.manage_team   -- everyone's expenses. Without it, expenses.record reaches the caller's own
--                             expenses only, and neither means no rows.
--   jobs.view_cost         -- required outright. An expense row is nothing but its amount, so unlike the
--                             time ledger there is no identity-only view to offer; the contract gates
--                             expenses on cost visibility and the package omits the file without it.
--
-- Every read is explicitly organization scoped.

create or replace function public.financial_expenses_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_expense_date date default null,
  cursor_expense_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  expense_id uuid,
  expense_date date,
  name text,
  description text,
  accounting_code text,
  total_minor bigint,
  currency_code text,
  job_id uuid,
  job_number integer,
  job_title text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  reimburse_to_user_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_team boolean;
  can_own boolean;
  assigned_only boolean;
  resolved_limit integer;
begin
  can_team := private.member_has_permission(target_organization_id, caller, 'expenses.manage_team');
  can_own := private.member_has_permission(target_organization_id, caller, 'expenses.record');
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view')
     or not private.member_has_permission(target_organization_id, caller, 'jobs.view_cost')
     or not (can_team or can_own) then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_expense_date is null) <> (cursor_expense_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  assigned_only := private.member_permission_scope(target_organization_id, caller, 'jobs.view') = 'assigned';
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select expense.id,
    expense.expense_date,
    expense.name,
    expense.description,
    expense.accounting_code,
    expense.total_minor,
    job.currency_code,
    expense.job_id,
    job.job_number,
    job.title,
    job.client_id,
    client.display_name,
    client.company_name,
    reimbursee.full_name,
    expense.created_at
  from public.job_expenses as expense
  join public.jobs as job
    on job.organization_id = expense.organization_id and job.id = expense.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  left join public.profiles as reimbursee
    on reimbursee.id = expense.reimburse_to_user_id
  where expense.organization_id = target_organization_id
    and expense.expense_date >= report_from and expense.expense_date < report_to
    and (can_team or expense.created_by = caller)
    and (
      not assigned_only
      or exists (
        select 1
        from public.job_visit_assignments as assignment
        where assignment.organization_id = expense.organization_id
          and assignment.user_id = caller
          and assignment.job_id = expense.job_id
      )
    )
    and (
      cursor_expense_date is null
      or (sort_direction = 'asc' and (expense.expense_date, expense.id) > (cursor_expense_date, cursor_expense_id))
      or (sort_direction = 'desc' and (expense.expense_date, expense.id) < (cursor_expense_date, cursor_expense_id))
    )
  order by
    case when sort_direction = 'asc' then expense.expense_date end asc,
    case when sort_direction = 'asc' then expense.id end asc,
    case when sort_direction = 'desc' then expense.expense_date end desc,
    case when sort_direction = 'desc' then expense.id end desc
  limit resolved_limit;
end;
$$;

comment on function public.financial_expenses_page(uuid, date, date, date, uuid, integer, text) is
  'Keyset-paged Job expense ledger for a report range, dated by expense_date as Job profitability dates '
  'expenses. Requires jobs.view, jobs.view_cost and expenses.manage_team (everyone''s) or expenses.record '
  '(own only); an assigned-scope member sees only assigned Jobs. Every row is explicitly organization scoped.';

revoke all on function public.financial_expenses_page(uuid, date, date, date, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_expenses_page(uuid, date, date, date, uuid, integer, text)
  to authenticated;

-- The existing indexes prefix on job_id, created_by and reimburse_to_user_id; a team-scope range over the
-- whole organization had nothing to walk but the table. This is the keyset order itself.
create index if not exists job_expenses_date_idx
  on public.job_expenses(organization_id, expense_date, id);

notify pgrst, 'reload schema';
