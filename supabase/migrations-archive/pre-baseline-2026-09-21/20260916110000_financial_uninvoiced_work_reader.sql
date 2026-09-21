-- CRM launch readiness, financial reconciliation Part 2: uninvoiced-work reader.
--
-- Work that is done but not yet billed is reported separately so it can be billed without being mistaken
-- for revenue. One row per billable unit so an accountant can trace each amount to its source record:
--
--   visit  -- a completed Visit on a per-visit Job that no Invoice has claimed. Dated by its stored service
--             date (the Visit date), falling back to the completion instant in the organization timezone.
--   period -- a due, still-pending calendar reminder on a fixed-per-period Job. Dated by its due date.
--   job    -- a closed whole-price Job that no Invoice has claimed at all. Dated by its closure instant in
--             the organization timezone. An open Job is work in progress, not uninvoiced work.
--
-- The unit test and the amount per unit restate private.job_uninvoiced_work (ready-to-bill queue, job page
-- cards, batch billing) so this report cannot disagree with the screens that do the billing: a whole Job is
-- its total once, every other unit is one copy of the Job subtotal at today's Job price. Amounts are
-- estimates at current Job pricing; the frozen Invoice is the sale once it exists.

create index jobs_closed_report_idx
  on public.jobs (organization_id, closed_at, id)
  where status = 'closed';

comment on index public.jobs_closed_report_idx is
  'Serves the uninvoiced-work report: closed Jobs in closure order within one organization.';

create or replace function public.financial_uninvoiced_work_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_work_date date default null,
  cursor_unit_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  unit_kind text,
  unit_id uuid,
  work_date date,
  job_id uuid,
  job_number integer,
  job_title text,
  price_basis text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  currency_code text,
  uninvoiced_minor bigint,
  visit_id uuid,
  reminder_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  zone text;
  today date;
  window_start timestamptz;
  window_end timestamptz;
  resolved_limit integer;
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
  if (cursor_work_date is null) <> (cursor_unit_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  today := private.organization_today(target_organization_id);
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  with unit as (
    select 'visit'::text as unit_kind, visit.id as unit_id,
      coalesce(visit.visit_date, (visit.completed_at at time zone zone)::date) as work_date,
      visit.job_id, job.subtotal_minor as uninvoiced_minor, visit.id as visit_id, null::uuid as reminder_id
    from public.job_visits as visit
    join public.jobs as job
      on job.organization_id = visit.organization_id and job.id = visit.job_id
    where visit.organization_id = target_organization_id
      and visit.completed_at is not null
      and job.price_basis = 'per_visit'
      and not exists (
        select 1 from public.invoice_sources as claim
        where claim.organization_id = visit.organization_id
          and claim.visit_id = visit.id and claim.source_kind = 'visit'
      )
    union all
    select 'period', reminder.id, reminder.due_on, reminder.job_id, job.subtotal_minor, null, reminder.id
    from public.job_invoice_reminders as reminder
    join public.jobs as job
      on job.organization_id = reminder.organization_id and job.id = reminder.job_id
    where reminder.organization_id = target_organization_id
      and reminder.status = 'pending'
      and reminder.due_on <= today
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and job.price_basis = 'fixed_per_period'
    union all
    select 'job', job.id, (job.closed_at at time zone zone)::date, job.id, job.total_minor, null, null
    from public.jobs as job
    where job.organization_id = target_organization_id
      and job.status = 'closed'
      and job.closed_at >= window_start and job.closed_at < window_end
      and job.price_basis = 'job_total'
      and not exists (
        select 1 from public.invoice_sources as claim
        where claim.organization_id = job.organization_id and claim.job_id = job.id
      )
  )
  select unit.unit_kind, unit.unit_id, unit.work_date, job.id, job.job_number, job.title, job.price_basis,
    job.client_id, client.display_name, client.company_name, job.currency_code, unit.uninvoiced_minor,
    unit.visit_id, unit.reminder_id
  from unit
  join public.jobs as job
    on job.organization_id = target_organization_id and job.id = unit.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  where unit.work_date >= report_from and unit.work_date < report_to
    and (
      cursor_work_date is null
      or (sort_direction = 'asc' and (unit.work_date, unit.unit_id) > (cursor_work_date, cursor_unit_id))
      or (sort_direction = 'desc' and (unit.work_date, unit.unit_id) < (cursor_work_date, cursor_unit_id))
    )
  order by
    case when sort_direction = 'asc' then unit.work_date end asc,
    case when sort_direction = 'asc' then unit.unit_id end asc,
    case when sort_direction = 'desc' then unit.work_date end desc,
    case when sort_direction = 'desc' then unit.unit_id end desc
  limit resolved_limit;
end;
$$;

create or replace function public.financial_uninvoiced_work_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  uninvoiced_minor bigint,
  unit_count bigint,
  visit_count bigint,
  period_count bigint,
  job_count bigint,
  distinct_job_count bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  zone text;
  today date;
  window_start timestamptz;
  window_end timestamptz;
begin
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view')
     or not private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  today := private.organization_today(target_organization_id);
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  return query
  with unit as (
    select 'visit'::text as unit_kind,
      coalesce(visit.visit_date, (visit.completed_at at time zone zone)::date) as work_date,
      visit.job_id, job.subtotal_minor as uninvoiced_minor
    from public.job_visits as visit
    join public.jobs as job
      on job.organization_id = visit.organization_id and job.id = visit.job_id
    where visit.organization_id = target_organization_id
      and visit.completed_at is not null
      and job.price_basis = 'per_visit'
      and not exists (
        select 1 from public.invoice_sources as claim
        where claim.organization_id = visit.organization_id
          and claim.visit_id = visit.id and claim.source_kind = 'visit'
      )
    union all
    select 'period', reminder.due_on, reminder.job_id, job.subtotal_minor
    from public.job_invoice_reminders as reminder
    join public.jobs as job
      on job.organization_id = reminder.organization_id and job.id = reminder.job_id
    where reminder.organization_id = target_organization_id
      and reminder.status = 'pending'
      and reminder.due_on <= today
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and job.price_basis = 'fixed_per_period'
    union all
    select 'job', (job.closed_at at time zone zone)::date, job.id, job.total_minor
    from public.jobs as job
    where job.organization_id = target_organization_id
      and job.status = 'closed'
      and job.closed_at >= window_start and job.closed_at < window_end
      and job.price_basis = 'job_total'
      and not exists (
        select 1 from public.invoice_sources as claim
        where claim.organization_id = job.organization_id and claim.job_id = job.id
      )
  )
  select coalesce(sum(unit.uninvoiced_minor), 0)::bigint,
    count(*)::bigint,
    count(*) filter (where unit.unit_kind = 'visit'),
    count(*) filter (where unit.unit_kind = 'period'),
    count(*) filter (where unit.unit_kind = 'job'),
    count(distinct unit.job_id)::bigint
  from unit
  where unit.work_date >= report_from and unit.work_date < report_to;
end;
$$;

comment on function public.financial_uninvoiced_work_page(uuid, date, date, date, uuid, integer, text) is
  'Keyset-paged ledger of completed, unclaimed billable units (visit, period, closed whole-price job) at '
  'current Job pricing. Requires jobs.view and jobs.view_price; every row is explicitly organization scoped.';
comment on function public.financial_uninvoiced_work_summary(uuid, date, date) is
  'Whole-range uninvoiced-work totals over the same unit predicate as financial_uninvoiced_work_page.';

revoke all on function public.financial_uninvoiced_work_page(uuid, date, date, date, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_uninvoiced_work_page(uuid, date, date, date, uuid, integer, text)
  to authenticated;
revoke all on function public.financial_uninvoiced_work_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_uninvoiced_work_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
