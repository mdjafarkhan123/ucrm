-- Jobs Part 14d: one authoritative profit for a one-off job.
--
-- 14a built the costing tables, 14b and 14c filled them with recorded labor and expenses. Nothing has ever
-- added those numbers up against what the job sells for. The "Job total" card still shows "Cost $0.00" and a
-- profit that counts only the item cost off the scope lines -- record $500 of materials and a day of labor
-- and the card still says the job cost nothing.
--
-- This migration does two things:
--
--   1. public.job_costing  -- the gated reader behind a new Job costing card: item + labor + expense cost,
--      revenue before tax, profit, and margin, for a one-off job.
--   2. public.job_money    -- stops reporting cost_minor and profit_minor. That profit excluded labor and
--      expenses and so always understated the true cost; the honest number now comes from job_costing.
--
-- Rules from the behavior contract that shape the reader:
--
--   * Revenue is the selling total minus tax. Tax is collected for the government, never earned.
--   * Unrated hours are unrated, not free. A time entry with no rate on file carries a null cost and stays
--     out of the labor total rather than being valued at zero -- the same rule job_labor already applies.
--   * Cost, profit and margin are one permission: jobs.view_cost, the same key the Labor and Expenses
--     sections check before they put a number on a row.
--   * 14d is one-off jobs only. A recurring job's revenue is defined per period by its pricing basis, so an
--     all-time cost total set against it would mislead; 14e pairs each basis with its rolling window.

-- 1. The gated costing reader ------------------------------------------------------------------------------

-- Everything the Job costing card needs in one call. Definer, because it reads money columns of jobs,
-- job_time_entries and job_expenses that carry no authenticated grant -- this is the only door those numbers
-- come through, and it checks jobs.view_cost for itself.
--
-- Bounded to one job: the jobs row is a primary-key lookup, and the two cost sums and the labor-line check
-- run over one job's rows on job_time_entries_job_started_idx, job_expenses_job_date_idx and
-- job_line_items_job_idx respectively. This is the same per-job aggregate shape job_labor and
-- job_expenses_list already run on the same page load.
create or replace function public.job_costing(
  target_organization_id uuid,
  target_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  labor_cost bigint;
  unrated_count integer;
  has_time boolean;
  expense_cost bigint;
  has_labor_line boolean;
  revenue bigint;
  total_cost bigint;
  profit bigint;
  margin_bp integer;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view') then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- No jobs.view_cost, nothing to show. The card only renders when the reader confirmed this right, and the
  -- API route only calls here then, so reaching this branch is a real error rather than an ordinary state.
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view_cost') then
    raise exception 'You do not have access to this job''s costs.' using errcode = 'insufficient_privilege';
  end if;

  -- A recurring job gets no numbers from 14d. The card says so and waits for 14e.
  if current_job.job_type <> 'one_off' then
    return jsonb_build_object(
      'costing_basis', 'recurring',
      'job_closed', current_job.status <> 'active'
    );
  end if;

  -- Every recorded hour's cost. cost_total_minor is already null for an unrated entry, so sum() skips it;
  -- unrated_count carries how many hours are sitting outside the total so the card can say so.
  select coalesce(sum(entry.cost_total_minor), 0),
         count(*) filter (where entry.cost_per_hour_minor is null),
         count(*) > 0
  into labor_cost, unrated_count, has_time
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id;

  select coalesce(sum(expense.total_minor), 0)
  into expense_cost
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id;

  -- Jobber counts a labor line item and tracked time both, and shows a heads-up rather than reconciling.
  select exists (
    select 1
    from public.job_line_items as line
    where line.organization_id = target_organization_id
      and line.job_id = target_job_id
      and line.is_labor
  ) into has_labor_line;

  revenue := current_job.total_minor - current_job.tax_minor;
  total_cost := current_job.cost_minor + labor_cost + expense_cost;
  profit := revenue - total_cost;
  -- Margin needs revenue to divide by. At zero revenue the card shows a dash, not a number.
  margin_bp := case when revenue > 0
    then round(profit::numeric * 10000 / revenue)::integer
    else null
  end;

  return jsonb_build_object(
    'costing_basis', 'one_off',
    'job_closed', current_job.status <> 'active',
    'revenue_minor', revenue,
    'item_cost_minor', current_job.cost_minor,
    'labor_cost_minor', labor_cost,
    'expense_cost_minor', expense_cost,
    'total_cost_minor', total_cost,
    'profit_minor', profit,
    'margin_basis_points', margin_bp,
    'unrated_labor_count', unrated_count,
    'labor_line_and_time', has_labor_line and has_time
  );
end;
$$;

comment on function public.job_costing(uuid, uuid) is
  'One job''s costing: item, labor and expense cost, revenue before tax, profit and margin, for a one-off '
  'job. Needs jobs.view_cost. A recurring job returns only costing_basis = recurring; its per-period '
  'profitability arrives in Part 14e.';

revoke all on function public.job_costing(uuid, uuid) from public;
revoke execute on function public.job_costing(uuid, uuid) from anon;
grant execute on function public.job_costing(uuid, uuid) to authenticated;

-- 2. job_money stops carrying a cost it always understated -----------------------------------------------

-- Unchanged from 20260901102141 except that cost_minor and profit_minor are gone. That profit was
-- total - tax - item_cost, which ignored every recorded hour and every expense, so it was wrong on any job
-- that tracked either. The Job costing card reads job_costing now; this reader is the selling side only.
create or replace function public.job_money(target_job_ids uuid[])
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  organizations uuid[];
  org uuid;
  answer jsonb;
begin
  if target_job_ids is null or cardinality(target_job_ids) = 0 then
    return '{}'::jsonb;
  end if;

  select array_agg(distinct job.organization_id) into organizations
  from public.jobs as job
  where job.id = any(target_job_ids);

  if organizations is null then
    return '{}'::jsonb;
  end if;
  if array_length(organizations, 1) > 1 then
    raise exception 'Those jobs do not belong to one organization.' using errcode = 'check_violation';
  end if;
  org := organizations[1];

  if not private.member_has_permission(org, caller, 'jobs.view') then
    raise exception 'You do not have access to these jobs.' using errcode = 'insufficient_privilege';
  end if;

  if not private.member_has_permission(org, caller, 'jobs.view_price') then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(job.id::text,
      jsonb_build_object(
        'subtotal_minor', job.subtotal_minor,
        'discount_minor', job.discount_minor,
        'discount_name', job.discount_name,
        'discount_type', job.discount_type,
        'discount_value', job.discount_value,
        'tax_minor', job.tax_minor,
        'tax_name', job.tax_name,
        'tax_source', job.tax_source,
        'tax_rate_id', job.tax_rate_id,
        'tax_rate_basis_points', job.tax_rate_basis_points,
        'total_minor', job.total_minor
      )
    ), '{}'::jsonb)
  into answer
  from public.jobs as job
  where job.organization_id = org
    and job.id = any(target_job_ids);

  return answer;
end;
$$;

comment on function public.job_money(uuid[]) is
  'Selling-side money for a set of jobs, keyed by job id: subtotal, discount, tax and total. Needs '
  'jobs.view_price; a reader without it gets an empty object. Cost, profit and margin moved to job_costing '
  'in Part 14d.';

revoke all on function public.job_money(uuid[]) from public;
revoke execute on function public.job_money(uuid[]) from anon;
grant execute on function public.job_money(uuid[]) to authenticated;

notify pgrst, 'reload schema';
