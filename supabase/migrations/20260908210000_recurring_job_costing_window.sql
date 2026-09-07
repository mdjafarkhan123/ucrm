-- Jobs Part 14e: recurring Job costing over the rolling 30-day window.
--
-- 14d gave a one-off job one authoritative profit. A recurring job got nothing but a sentence, because a
-- recurring agreement has no end to total up against: it earns money per unit of work, forever. An all-time
-- cost set against an all-time revenue would be a number nobody can act on.
--
-- So a recurring job is measured over a window instead: the last 30 days, inclusive, in the organization's own
-- calendar timezone, with the exact dates named on screen. The window is our product choice, not a Jobber rule.
--
-- Inside that window each pricing basis pairs cost with the revenue its own basis defines -- the same
-- definition the biller uses, so the costing card and the invoice can never disagree about what the work sold
-- for:
--
--   per_visit         -- one completed visit's effective priced lines, per completed in-window visit. Effective
--                        means private.job_visit_effective_lines: the visit's own rows if it has any, else the
--                        job's. That is the same question the visit editor, the composer and the batch planner
--                        ask, so a week we mowed five lawns is worth five lawns here too.
--   fixed_per_period  -- the job's own priced lines, once per in-window billing period. A period is a
--                        month-end or custom-date invoice reminder, of any status: an already-invoiced period
--                        still happened and still earned its money, so resolving a reminder must not make the
--                        revenue vanish.
--
-- Manual billing defines no periods at all. Then there is no revenue to state, so the card states none: it
-- shows what the window cost and leaves revenue, profit and margin blank rather than inventing a figure.
--
-- Which side of the window a record falls on is decided by when the thing happened, never by when it was typed
-- in:
--
--   revenue  -- the visit's visit_date, the same service date the invoice stamps, or the period's due_on.
--   labor    -- started_at, compared against the window's own timezone-resolved instants so the index is used.
--   expenses -- expense_date.
--
-- Keying revenue to visit_date rather than completed_at is what makes the pairing honest: a visit worked on the
-- 5th and ticked complete on the 20th belongs in the window that carries the hours logged on the 5th.
--
-- Carried forward from 14d unchanged: unrated hours are unrated and not free, cost is gated on jobs.view_cost,
-- and a labor line item sitting alongside tracked time raises a heads-up rather than being reconciled.

-- 1. The index the period read needs ------------------------------------------------------------------------

-- Periods are counted across every status, and every existing index on this table is partial on
-- status = 'pending'. Without this the window count degrades to a sequential scan of every organization's
-- reminders on each job page load. Same columns as job_invoice_reminders_pending_due_idx, minus the predicate;
-- the partial one stays because the ready-to-bill queue reads pending rows far more often and pays less for a
-- smaller index.
create index if not exists job_invoice_reminders_job_due_idx
  on public.job_invoice_reminders(organization_id, job_id, due_on);

comment on index public.job_invoice_reminders_job_due_idx is
  'One job''s reminders by date, whatever their status. Serves recurring job costing, which counts billing '
  'periods that fell in a window whether or not they have since been invoiced.';

-- 2. The reader learns the two recurring bases ---------------------------------------------------------------

-- Unchanged from 20260908200000 except that the recurring branch now returns figures instead of a placeholder.
-- Still one call behind one card, still definer for the same reason: jobs, job_time_entries, job_expenses and
-- job_line_items carry money columns with no authenticated grant, and this is the only door they come through.
--
-- Bounded by one job and one window. The jobs row is a primary-key lookup. Labor and expenses are range scans
-- of this job's own rows on job_time_entries_job_started_idx and job_expenses_job_date_idx. Periods are a range
-- scan on the index above. The per-visit branch is the one place work multiplies: it runs
-- job_visit_effective_lines once per completed in-window visit, and each of those is capped at 100 lines by the
-- line tables' own trigger. The window is what bounds it -- 30 days of visits, not the job's whole history --
-- so a daily agreement is the worst case at roughly 30 visits, and a weekly one costs four.
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
  zone text;
  window_start date;
  window_end date;
  labor_from timestamptz;
  labor_until timestamptz;
  unit_count integer := 0;
  period_price bigint;
  period_cost bigint;
  labor_cost bigint;
  unrated_count integer;
  has_time boolean;
  expense_cost bigint;
  has_labor_line boolean;
  item_cost bigint;
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

  -- A one-off job is measured over its whole life, exactly as 14d shipped it: it has an end, so it can have a
  -- final answer. Nothing below this block applies to it.
  if current_job.price_basis = 'job_total' then
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
  end if;

  -- The window. Thirty days ending today, both ends inclusive, on the organization's own calendar -- a
  -- contractor in Los Angeles and one in London do not agree about when today started, and a costing figure
  -- that moved at UTC midnight would be wrong for both of them at some hour.
  window_end := private.organization_today(target_organization_id);
  window_start := window_end - 29;

  -- The same timezone again, this time to turn those two dates into the instants labor is compared against.
  -- Comparing started_at to a pair of timestamptz keeps job_time_entries_job_started_idx in play; casting the
  -- column to a local date instead would throw the index away for no gain.
  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');

  labor_from := (window_start::timestamp) at time zone zone;
  labor_until := ((window_end + 1)::timestamp) at time zone zone;

  if current_job.price_basis = 'per_visit' then
    -- What the completed visits in this window are worth, priced the way the biller prices them. bool_or over
    -- the same rows answers the labor-line question for exactly the work being counted.
    with in_window as (
      select visit.id
      from public.job_visits as visit
      where visit.organization_id = target_organization_id
        and visit.job_id = target_job_id
        and visit.completed_at is not null
        and visit.visit_date between window_start and window_end
    ),
    priced_lines as (
      select line.line_total_minor, line.quantity, line.unit_cost_minor, line.is_labor
      from in_window
      cross join lateral private.job_visit_effective_lines(
        target_organization_id, target_job_id, in_window.id
      ) as line
      where line.line_kind = 'priced'
    )
    select
      (select count(*) from in_window)::integer,
      coalesce(sum(priced_lines.line_total_minor), 0),
      coalesce(sum(public.pricing_line_total_minor(
        priced_lines.quantity, priced_lines.unit_cost_minor
      )), 0),
      coalesce(bool_or(priced_lines.is_labor), false)
    into unit_count, revenue, item_cost, has_labor_line
    from priced_lines;

  else
    -- fixed_per_period. Every billing period whose date landed in the window, invoiced or not.
    select count(*)::integer
    into unit_count
    from public.job_invoice_reminders as reminder
    where reminder.organization_id = target_organization_id
      and reminder.job_id = target_job_id
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and reminder.due_on between window_start and window_end;

    -- What one period sells for and costs in materials: the job's own priced lines, which is precisely the set
    -- private.job_batch_billing_payload stamps onto a period invoice.
    select coalesce(sum(line.line_total_minor), 0),
           coalesce(sum(line.line_cost_total_minor), 0),
           coalesce(bool_or(line.is_labor), false)
    into period_price, period_cost, has_labor_line
    from public.job_line_items as line
    where line.organization_id = target_organization_id
      and line.job_id = target_job_id
      and line.line_kind = 'priced';

    if unit_count > 0 then
      revenue := period_price * unit_count;
      item_cost := period_cost * unit_count;
    else
      -- Manual billing, or simply no period fell in these 30 days. Either way there is no revenue to state and
      -- no item cost to draw down, so the card shows the recorded costs and leaves the rest blank.
      revenue := null;
      item_cost := 0;
    end if;
  end if;

  -- Labor and expenses are recorded against the job whatever its basis, so both bases count them the same way:
  -- everything that happened inside the window.
  select coalesce(sum(entry.cost_total_minor), 0),
         count(*) filter (where entry.cost_per_hour_minor is null),
         count(*) > 0
  into labor_cost, unrated_count, has_time
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and entry.started_at >= labor_from
    and entry.started_at < labor_until;

  select coalesce(sum(expense.total_minor), 0)
  into expense_cost
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and expense.expense_date between window_start and window_end;

  total_cost := item_cost + labor_cost + expense_cost;
  -- No revenue means no profit and no margin. A window that cost $400 and sold nothing it can name is not a
  -- $400 loss; it is a window we cannot price, and saying so is the only honest answer.
  profit := case when revenue is null then null else revenue - total_cost end;
  margin_bp := case when revenue is not null and revenue > 0
    then round((revenue - total_cost)::numeric * 10000 / revenue)::integer
    else null
  end;

  return jsonb_build_object(
    'costing_basis', current_job.price_basis,
    'job_closed', current_job.status <> 'active',
    'window_start', window_start,
    'window_end', window_end,
    'unit_kind', case when current_job.price_basis = 'per_visit' then 'visits' else 'periods' end,
    'unit_count', unit_count,
    'revenue_minor', revenue,
    'item_cost_minor', item_cost,
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
  'One job''s costing. A one-off job is measured over its whole life. A recurring job is measured over the '
  'last 30 days in the organization''s timezone, pairing costs with the revenue its pricing basis defines: '
  'per completed visit, or per billing period. Needs jobs.view_cost. Revenue, profit and margin are null when '
  'no period defines revenue in the window.';

revoke all on function public.job_costing(uuid, uuid) from public;
revoke execute on function public.job_costing(uuid, uuid) from anon;
grant execute on function public.job_costing(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
