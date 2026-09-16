-- CRM launch readiness, financial reconciliation Part 2: Job profitability reader.
--
-- One row per Job that earned or cost money inside the report range, so an accountant can trace operational
-- profit back to the Job. Job profit is operational analysis: it is neither billed sales nor cash received.
--
-- Revenue and cost are paired exactly the way public.job_costing (Jobs Parts 14d/14e) pairs them, with the
-- report range standing in for the costing card's rolling 30-day window, so this report cannot disagree with
-- the Job page about what a Job earned:
--
--   job_total        -- a whole-price one-off Job, measured over its whole life once it closes. It belongs to
--                       the range its closure instant falls in (organization timezone). Revenue is Job total
--                       less Job tax; item cost is the Job's snapshotted line cost; every recorded hour and
--                       expense counts, whatever its date. An open one-off Job is work in progress.
--   per_visit        -- every completed Visit dated inside the range (stored service date, falling back to
--                       the completion instant), valued at its effective priced lines. Item cost is those lines'
--                       snapshotted unit cost. No completed Visit means zero revenue, as on the costing card.
--   fixed_per_period -- every billing period (month-end or custom-date reminder, any status) due inside the
--                       range, valued at the Job's priced lines. No period in range means revenue, profit and
--                       margin are null: the range's real costs are stated, never read as a pure loss.
--
-- Labor is dated by started_at against the range's timezone-resolved instants; expenses by expense_date.
-- Unrated hours (no rate on file when recorded) are disclosed as a count and minutes and stay out of the cost
-- total rather than being valued at zero.
--
-- Prices need jobs.view and jobs.view_price. Cost, labor, expenses, profit and margin need jobs.view_cost:
-- without it those columns are null, never zero. Every read is explicitly organization scoped.

-- 1. Which Jobs belong to the range --------------------------------------------------------------------

-- Five range scans on already organization-prefixed indexes (jobs_closed_report_idx, job_visits_calendar_idx,
-- job_invoice_reminders_job_due_idx, job_time_entries_job_started_idx, job_expenses_job_date_idx), unioned
-- into one distinct set of Job ids. Nothing is aggregated here; that waits for the page's own Jobs.
create or replace function private.financial_job_profitability_candidates(
  target_organization_id uuid,
  report_from date,
  report_to date,
  zone text,
  window_start timestamptz,
  window_end timestamptz
)
returns table (job_id uuid)
language sql
stable
set search_path = pg_catalog, public
as $$
  select job.id
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.status = 'closed'
    and job.price_basis = 'job_total'
    and job.closed_at >= window_start and job.closed_at < window_end
  union
  select visit.job_id
  from public.job_visits as visit
  join public.jobs as job
    on job.organization_id = visit.organization_id and job.id = visit.job_id
  where visit.organization_id = target_organization_id
    and visit.completed_at is not null
    and job.price_basis = 'per_visit'
    and coalesce(visit.visit_date, (visit.completed_at at time zone zone)::date) >= report_from
    and coalesce(visit.visit_date, (visit.completed_at at time zone zone)::date) < report_to
  union
  select reminder.job_id
  from public.job_invoice_reminders as reminder
  join public.jobs as job
    on job.organization_id = reminder.organization_id and job.id = reminder.job_id
  where reminder.organization_id = target_organization_id
    and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
    and reminder.due_on >= report_from and reminder.due_on < report_to
    and job.price_basis = 'fixed_per_period'
  union
  select entry.job_id
  from public.job_time_entries as entry
  join public.jobs as job
    on job.organization_id = entry.organization_id and job.id = entry.job_id
  where entry.organization_id = target_organization_id
    and entry.started_at >= window_start and entry.started_at < window_end
    and job.price_basis <> 'job_total'
  union
  select expense.job_id
  from public.job_expenses as expense
  join public.jobs as job
    on job.organization_id = expense.organization_id and job.id = expense.job_id
  where expense.organization_id = target_organization_id
    and expense.expense_date >= report_from and expense.expense_date < report_to
    and job.price_basis <> 'job_total';
$$;

comment on function private.financial_job_profitability_candidates(uuid, date, date, text, timestamptz, timestamptz) is
  'Distinct Jobs with revenue, labor or expenses inside a report range: closed whole-price Jobs by closure '
  'instant, recurring Jobs by in-range completed Visits, due periods, labor or expenses.';

revoke all on function private.financial_job_profitability_candidates(uuid, date, date, text, timestamptz, timestamptz)
  from public;
revoke execute on function private.financial_job_profitability_candidates(uuid, date, date, text, timestamptz, timestamptz)
  from anon, authenticated;

-- 2. What each of those Jobs earned and cost -------------------------------------------------------------

-- Bounded by the Job ids it is handed: the page function passes one page, the summary passes the range's
-- candidates. Every lateral block is one Job's own rows on that Job's index prefix. The per-visit block is
-- the one place work multiplies -- private.job_visit_effective_lines once per completed in-range Visit, each
-- capped at 100 lines by the line tables' own trigger.
create or replace function private.financial_job_profitability_rows(
  target_organization_id uuid,
  target_job_ids uuid[],
  report_from date,
  report_to date,
  zone text,
  window_start timestamptz,
  window_end timestamptz
)
returns table (
  job_id uuid,
  unit_count integer,
  revenue_minor bigint,
  item_cost_minor bigint,
  labor_cost_minor bigint,
  labor_minutes bigint,
  unrated_labor_count bigint,
  unrated_labor_minutes bigint,
  expense_cost_minor bigint
)
language sql
stable
set search_path = pg_catalog, public
as $$
  select
    job.id,
    case job.price_basis
      when 'job_total' then null::integer
      when 'per_visit' then visits.unit_count
      else periods.unit_count
    end,
    case job.price_basis
      when 'job_total' then job.total_minor - job.tax_minor
      when 'per_visit' then visits.revenue_minor
      else case when periods.unit_count > 0 then period_lines.price_minor * periods.unit_count end
    end,
    case job.price_basis
      when 'job_total' then job.cost_minor
      when 'per_visit' then visits.item_cost_minor
      else period_lines.cost_minor * periods.unit_count
    end,
    labor.cost_minor,
    labor.minutes,
    labor.unrated_count,
    labor.unrated_minutes,
    expense.cost_minor
  from public.jobs as job
  cross join lateral (
    select count(*)::integer as unit_count,
      coalesce(sum(priced.revenue_minor), 0)::bigint as revenue_minor,
      coalesce(sum(priced.item_cost_minor), 0)::bigint as item_cost_minor
    from public.job_visits as visit
    cross join lateral (
      select coalesce(sum(line.line_total_minor), 0) as revenue_minor,
        coalesce(sum(public.pricing_line_total_minor(line.quantity, line.unit_cost_minor)), 0) as item_cost_minor
      from private.job_visit_effective_lines(job.organization_id, job.id, visit.id) as line
      where line.line_kind = 'priced'
    ) as priced
    where job.price_basis = 'per_visit'
      and visit.organization_id = job.organization_id
      and visit.job_id = job.id
      and visit.completed_at is not null
      and coalesce(visit.visit_date, (visit.completed_at at time zone zone)::date) >= report_from
      and coalesce(visit.visit_date, (visit.completed_at at time zone zone)::date) < report_to
  ) as visits
  cross join lateral (
    select count(*)::integer as unit_count
    from public.job_invoice_reminders as reminder
    where job.price_basis = 'fixed_per_period'
      and reminder.organization_id = job.organization_id
      and reminder.job_id = job.id
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and reminder.due_on >= report_from and reminder.due_on < report_to
  ) as periods
  cross join lateral (
    select coalesce(sum(line.line_total_minor), 0)::bigint as price_minor,
      coalesce(sum(line.line_cost_total_minor), 0)::bigint as cost_minor
    from public.job_line_items as line
    where job.price_basis = 'fixed_per_period'
      and line.organization_id = job.organization_id
      and line.job_id = job.id
      and line.line_kind = 'priced'
  ) as period_lines
  cross join lateral (
    select coalesce(sum(entry.cost_total_minor), 0)::bigint as cost_minor,
      coalesce(sum(entry.minutes), 0)::bigint as minutes,
      count(*) filter (where entry.cost_per_hour_minor is null) as unrated_count,
      coalesce(sum(entry.minutes) filter (where entry.cost_per_hour_minor is null), 0)::bigint as unrated_minutes
    from public.job_time_entries as entry
    where entry.organization_id = job.organization_id
      and entry.job_id = job.id
      and (job.price_basis = 'job_total'
        or (entry.started_at >= window_start and entry.started_at < window_end))
  ) as labor
  cross join lateral (
    select coalesce(sum(expense.total_minor), 0)::bigint as cost_minor
    from public.job_expenses as expense
    where expense.organization_id = job.organization_id
      and expense.job_id = job.id
      and (job.price_basis = 'job_total'
        or (expense.expense_date >= report_from and expense.expense_date < report_to))
  ) as expense
  where job.organization_id = target_organization_id
    and job.id = any(target_job_ids);
$$;

comment on function private.financial_job_profitability_rows(uuid, uuid[], date, date, text, timestamptz, timestamptz) is
  'Per-Job revenue, unit count, item cost, rated labor, unrated labor disclosure and expenses for a report '
  'range, paired per pricing basis exactly as public.job_costing pairs them. Revenue is null for a '
  'fixed-per-period Job with no period in range.';

revoke all on function private.financial_job_profitability_rows(uuid, uuid[], date, date, text, timestamptz, timestamptz)
  from public;
revoke execute on function private.financial_job_profitability_rows(uuid, uuid[], date, date, text, timestamptz, timestamptz)
  from anon, authenticated;

-- 3. The paged ledger ------------------------------------------------------------------------------------

-- Keyset on job_number, unique per organization (jobs_number_unique), so one integer is a complete marker.
create or replace function public.financial_job_profitability_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_job_number integer default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  job_id uuid,
  job_number integer,
  job_title text,
  job_type text,
  price_basis text,
  job_status text,
  closed_on date,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  currency_code text,
  unit_count integer,
  revenue_minor bigint,
  item_cost_minor bigint,
  labor_cost_minor bigint,
  expense_cost_minor bigint,
  total_cost_minor bigint,
  profit_minor bigint,
  margin_basis_points integer,
  labor_minutes bigint,
  unrated_labor_count bigint,
  unrated_labor_minutes bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_view_cost boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
  resolved_limit integer;
  page_job_ids uuid[];
begin
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view')
     or not private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  select array_agg(page.id) into page_job_ids
  from (
    select job.id
    from private.financial_job_profitability_candidates(
      target_organization_id, report_from, report_to, zone, window_start, window_end
    ) as candidate
    join public.jobs as job
      on job.organization_id = target_organization_id and job.id = candidate.job_id
    where cursor_job_number is null
      or (sort_direction = 'asc' and job.job_number > cursor_job_number)
      or (sort_direction = 'desc' and job.job_number < cursor_job_number)
    order by
      case when sort_direction = 'asc' then job.job_number end asc,
      case when sort_direction = 'desc' then job.job_number end desc
    limit resolved_limit
  ) as page;

  if page_job_ids is null then
    return;
  end if;

  return query
  select job.id, job.job_number, job.title, job.job_type, job.price_basis, job.status,
    (job.closed_at at time zone zone)::date,
    job.client_id, client.display_name, client.company_name, job.currency_code,
    figures.unit_count,
    figures.revenue_minor,
    case when can_view_cost then figures.item_cost_minor end,
    case when can_view_cost then figures.labor_cost_minor end,
    case when can_view_cost then figures.expense_cost_minor end,
    case when can_view_cost then cost.total_minor end,
    case when can_view_cost then figures.revenue_minor - cost.total_minor end,
    case when can_view_cost and figures.revenue_minor > 0
      then round((figures.revenue_minor - cost.total_minor)::numeric * 10000 / figures.revenue_minor)::integer
    end,
    case when can_view_cost then figures.labor_minutes end,
    case when can_view_cost then figures.unrated_labor_count end,
    case when can_view_cost then figures.unrated_labor_minutes end
  from private.financial_job_profitability_rows(
    target_organization_id, page_job_ids, report_from, report_to, zone, window_start, window_end
  ) as figures
  join public.jobs as job
    on job.organization_id = target_organization_id and job.id = figures.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  cross join lateral (
    select (figures.item_cost_minor + figures.labor_cost_minor + figures.expense_cost_minor)::bigint as total_minor
  ) as cost
  order by
    case when sort_direction = 'asc' then job.job_number end asc,
    case when sort_direction = 'desc' then job.job_number end desc;
end;
$$;

-- 4. The whole-range totals ------------------------------------------------------------------------------

create or replace function public.financial_job_profitability_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  job_count bigint,
  one_off_count bigint,
  per_visit_count bigint,
  fixed_per_period_count bigint,
  unpriced_job_count bigint,
  revenue_minor bigint,
  item_cost_minor bigint,
  labor_cost_minor bigint,
  expense_cost_minor bigint,
  total_cost_minor bigint,
  profit_minor bigint,
  unpriced_cost_minor bigint,
  labor_minutes bigint,
  unrated_labor_count bigint,
  unrated_labor_minutes bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_view_cost boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
  candidate_job_ids uuid[];
begin
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view')
     or not private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  select array_agg(candidate.job_id) into candidate_job_ids
  from private.financial_job_profitability_candidates(
    target_organization_id, report_from, report_to, zone, window_start, window_end
  ) as candidate;

  -- Profit sums only Jobs whose revenue is defined; the cost of unpriced Jobs is named separately so the
  -- accountant sees it without it being read as a loss against nothing.
  return query
  select count(*)::bigint,
    count(*) filter (where job.price_basis = 'job_total'),
    count(*) filter (where job.price_basis = 'per_visit'),
    count(*) filter (where job.price_basis = 'fixed_per_period'),
    count(*) filter (where figures.revenue_minor is null),
    coalesce(sum(figures.revenue_minor), 0)::bigint,
    case when can_view_cost then coalesce(sum(figures.item_cost_minor), 0)::bigint end,
    case when can_view_cost then coalesce(sum(figures.labor_cost_minor), 0)::bigint end,
    case when can_view_cost then coalesce(sum(figures.expense_cost_minor), 0)::bigint end,
    case when can_view_cost then coalesce(sum(cost.total_minor), 0)::bigint end,
    case when can_view_cost
      then coalesce(sum(figures.revenue_minor - cost.total_minor) filter (where figures.revenue_minor is not null), 0)::bigint
    end,
    case when can_view_cost
      then coalesce(sum(cost.total_minor) filter (where figures.revenue_minor is null), 0)::bigint
    end,
    case when can_view_cost then coalesce(sum(figures.labor_minutes), 0)::bigint end,
    case when can_view_cost then coalesce(sum(figures.unrated_labor_count), 0)::bigint end,
    case when can_view_cost then coalesce(sum(figures.unrated_labor_minutes), 0)::bigint end
  from private.financial_job_profitability_rows(
    target_organization_id, coalesce(candidate_job_ids, '{}'::uuid[]), report_from, report_to, zone,
    window_start, window_end
  ) as figures
  join public.jobs as job
    on job.organization_id = target_organization_id and job.id = figures.job_id
  cross join lateral (
    select (figures.item_cost_minor + figures.labor_cost_minor + figures.expense_cost_minor)::bigint as total_minor
  ) as cost;
end;
$$;

comment on function public.financial_job_profitability_page(uuid, date, date, integer, integer, text) is
  'Keyset-paged Job profitability ledger for a report range: revenue paired with item, labor and expense cost '
  'per pricing basis, as public.job_costing pairs them. Requires jobs.view and jobs.view_price; cost, profit, '
  'margin and labor columns are null without jobs.view_cost. Every row is explicitly organization scoped.';
comment on function public.financial_job_profitability_summary(uuid, date, date) is
  'Whole-range Job profitability totals over the same Job set as financial_job_profitability_page.';

revoke all on function public.financial_job_profitability_page(uuid, date, date, integer, integer, text)
  from public, anon;
grant execute on function public.financial_job_profitability_page(uuid, date, date, integer, integer, text)
  to authenticated;
revoke all on function public.financial_job_profitability_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_job_profitability_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
