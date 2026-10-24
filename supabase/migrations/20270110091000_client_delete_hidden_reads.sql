-- Data privacy Part 6b: lists, boards, reports and customer links that read past row security skip a customer in
-- Recently Deleted. Design: docs/data-privacy-client-delete-restore.md § Hiding, point 2.
--
-- Each function below is its current definition with every read of the customer's work tables (jobs, visits,
-- quotes, requests, assessments, opportunities, review requests, properties) narrowed to
-- `(select * from public.<table> where client_deleted_at is null)`, the same filter the member policies apply. The
-- invoice list functions narrow only `invoices` (a deleted customer's drafts); issued invoices and their jobs stay
-- visible (§ Money records). Writes are already refused by private.refuse_work_for_deleted_client.

CREATE OR REPLACE FUNCTION public.emit_due_appointment_reminders(p_limit integer DEFAULT 200)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  due record;
  emitted integer := 0;
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'The reminder batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for due in
    with recipes as (
      select recipe.id as recipe_id, recipe.organization_id, version.activated_at,
        version.definition -> 'trigger' -> 'config' as config,
        private.appointment_timezone(recipe.organization_id) as timezone
      from public.automation_recipes as recipe
      join public.automation_recipe_versions as version on version.id = recipe.current_version_id
      where recipe.status = 'active' and recipe.active_trigger_key = 'appointment.reminder_due'
    ),
    candidates as (
      select recipes.recipe_id, recipes.organization_id, recipes.activated_at,
        'job_visit'::text as subject_type, visit.id as subject_id, visit.schedule_set_at,
        private.appointment_reminder_at(recipes.config, visit.visit_date, visit.start_time, recipes.timezone)
          as remind_at,
        private.appointment_starts_at(visit.visit_date, visit.start_time, recipes.timezone) as starts_at
      from recipes
      join (select * from public.job_visits where client_deleted_at is null) as visit
        on visit.organization_id = recipes.organization_id
        and visit.visit_date between (now() at time zone recipes.timezone)::date
          and (now() at time zone recipes.timezone)::date + 8
        and visit.completed_at is null
      join (select * from public.jobs where client_deleted_at is null) as job
        on job.organization_id = visit.organization_id and job.id = visit.job_id and job.status = 'active'
      union all
      select recipes.recipe_id, recipes.organization_id, recipes.activated_at,
        'assessment'::text, assessment.id, assessment.schedule_set_at,
        private.appointment_reminder_at(
          recipes.config,
          (assessment.starts_at at time zone recipes.timezone)::date,
          case when assessment.all_day then null else (assessment.starts_at at time zone recipes.timezone)::time end,
          recipes.timezone),
        private.appointment_starts_at(
          (assessment.starts_at at time zone recipes.timezone)::date,
          case when assessment.all_day then null else (assessment.starts_at at time zone recipes.timezone)::time end,
          recipes.timezone)
      from recipes
      join (select * from public.assessments where client_deleted_at is null) as assessment
        on assessment.organization_id = recipes.organization_id
        and assessment.completed_at is null
        and assessment.starts_at > now() - interval '1 day'
        and assessment.starts_at < now() + interval '9 days'
      join (select * from public.requests where client_deleted_at is null) as request
        on request.organization_id = assessment.organization_id and request.id = assessment.request_id
        and request.status <> 'archived'
    )
    select candidates.*
    from candidates
    where candidates.remind_at <= now()
      and candidates.starts_at > now()
      and candidates.remind_at >= coalesce(candidates.schedule_set_at, '-infinity'::timestamptz)
      and candidates.remind_at >= candidates.activated_at
      and not exists (
        select 1 from private.automation_events as event
        where event.source_module = 'scheduling'
          and event.source_event_id = private.appointment_reminder_source_id(candidates.recipe_id, candidates.subject_id)
          and event.event_type = 'appointment.reminder_due'
      )
    order by candidates.remind_at
    limit p_limit
  loop
    perform private.emit_automation_event(
      due.organization_id, 'appointment.reminder_due', due.subject_type, due.subject_id,
      jsonb_build_object('recipe_id', due.recipe_id, 'remind_at', due.remind_at, 'starts_at', due.starts_at),
      due.remind_at, 'scheduling', private.appointment_reminder_source_id(due.recipe_id, due.subject_id));
    emitted := emitted + 1;
  end loop;

  return emitted;
end;
$function$;

CREATE OR REPLACE FUNCTION public.financial_expenses_page(target_organization_id uuid, report_from date, report_to date, cursor_expense_date date DEFAULT NULL::date, cursor_expense_id uuid DEFAULT NULL::uuid, page_limit integer DEFAULT 100, sort_direction text DEFAULT 'asc'::text)
 RETURNS TABLE(expense_id uuid, expense_date date, name text, description text, accounting_code text, total_minor bigint, currency_code text, job_id uuid, job_number integer, job_title text, client_id uuid, client_display_name text, client_company_name text, reimburse_to_user_name text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  join (select * from public.jobs where client_deleted_at is null) as job
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
$function$;

CREATE OR REPLACE FUNCTION public.financial_job_profitability_page(target_organization_id uuid, report_from date, report_to date, cursor_job_number integer DEFAULT NULL::integer, page_limit integer DEFAULT 100, sort_direction text DEFAULT 'asc'::text)
 RETURNS TABLE(job_id uuid, job_number integer, job_title text, job_type text, price_basis text, job_status text, closed_on date, client_id uuid, client_display_name text, client_company_name text, currency_code text, unit_count integer, revenue_minor bigint, item_cost_minor bigint, labor_cost_minor bigint, expense_cost_minor bigint, total_cost_minor bigint, profit_minor bigint, margin_basis_points integer, labor_minutes bigint, unrated_labor_count bigint, unrated_labor_minutes bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    join (select * from public.jobs where client_deleted_at is null) as job
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
  join (select * from public.jobs where client_deleted_at is null) as job
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
$function$;

CREATE OR REPLACE FUNCTION public.financial_job_profitability_summary(target_organization_id uuid, report_from date, report_to date)
 RETURNS TABLE(job_count bigint, one_off_count bigint, per_visit_count bigint, fixed_per_period_count bigint, unpriced_job_count bigint, revenue_minor bigint, item_cost_minor bigint, labor_cost_minor bigint, expense_cost_minor bigint, total_cost_minor bigint, profit_minor bigint, unpriced_cost_minor bigint, labor_minutes bigint, unrated_labor_count bigint, unrated_labor_minutes bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  join (select * from public.jobs where client_deleted_at is null) as job
    on job.organization_id = target_organization_id and job.id = figures.job_id
  cross join lateral (
    select (figures.item_cost_minor + figures.labor_cost_minor + figures.expense_cost_minor)::bigint as total_minor
  ) as cost;
end;
$function$;

CREATE OR REPLACE FUNCTION public.financial_sales_outcomes_page(target_organization_id uuid, report_from date, report_to date, cursor_outcome_at timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_opportunity_id uuid DEFAULT NULL::uuid, page_limit integer DEFAULT 100, sort_direction text DEFAULT 'asc'::text)
 RETURNS TABLE(opportunity_id uuid, outcome text, outcome_at timestamp with time zone, outcome_on date, created_on date, source_kind text, request_id uuid, quote_id uuid, quote_number integer, title text, client_id uuid, client_display_name text, client_company_name text, currency_code text, estimated_value_minor bigint, lost_reason text, outcome_event_id uuid, job_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  can_view_value boolean;
  zone text;
  organization_currency text;
  window_start timestamptz;
  window_end timestamptz;
  resolved_limit integer;
begin
  if not private.member_has_permission(target_organization_id, caller, 'pipeline.view') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_outcome_at is null) <> (cursor_opportunity_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_value := private.member_has_permission(target_organization_id, caller, 'pipeline.view_value');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC'), settings.currency_code
  into zone, organization_currency
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select opportunity.id,
    opportunity.outcome,
    opportunity.outcome_at,
    (opportunity.outcome_at at time zone zone)::date,
    (opportunity.created_at at time zone zone)::date,
    case
      when opportunity.job_id is not null then 'direct_job'
      when opportunity.quote_id is not null then 'quote'
      else 'request'
    end,
    opportunity.request_id,
    opportunity.quote_id,
    quote.quote_number,
    opportunity.title,
    opportunity.client_id,
    client.display_name,
    client.company_name,
    coalesce(quote.currency_code, organization_currency),
    case when can_view_value then round(opportunity.estimated_value * 100)::bigint end,
    outcome_event.reason,
    opportunity.current_outcome_event_id,
    opportunity.job_id
  from (select * from public.opportunities where client_deleted_at is null) as opportunity
  left join (select * from public.quotes where client_deleted_at is null) as quote
    on quote.organization_id = opportunity.organization_id and quote.id = opportunity.quote_id
  left join public.clients as client
    on client.organization_id = opportunity.organization_id and client.id = opportunity.client_id
  left join public.opportunity_outcome_events as outcome_event
    on outcome_event.organization_id = opportunity.organization_id
   and outcome_event.id = opportunity.current_outcome_event_id
   and outcome_event.event_type = 'lost'
  where opportunity.organization_id = target_organization_id
    and opportunity.outcome_kind is not null
    and opportunity.outcome_at >= window_start and opportunity.outcome_at < window_end
    and (
      cursor_outcome_at is null
      or (sort_direction = 'asc'
        and (opportunity.outcome_at, opportunity.id) > (cursor_outcome_at, cursor_opportunity_id))
      or (sort_direction = 'desc'
        and (opportunity.outcome_at, opportunity.id) < (cursor_outcome_at, cursor_opportunity_id))
    )
  order by
    case when sort_direction = 'asc' then opportunity.outcome_at end asc,
    case when sort_direction = 'asc' then opportunity.id end asc,
    case when sort_direction = 'desc' then opportunity.outcome_at end desc,
    case when sort_direction = 'desc' then opportunity.id end desc
  limit resolved_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.financial_sales_outcomes_summary(target_organization_id uuid, report_from date, report_to date)
 RETURNS TABLE(won_count bigint, lost_count bigint, won_unvalued_count bigint, lost_unvalued_count bigint, won_value_minor bigint, lost_value_minor bigint, direct_job_count bigint, direct_job_unvalued_count bigint, direct_job_value_minor bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  can_view_value boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
begin
  if not private.member_has_permission(target_organization_id, caller, 'pipeline.view') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_value := private.member_has_permission(target_organization_id, caller, 'pipeline.view_value');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  return query
  select count(*) filter (where opportunity.outcome_kind = 'won'),
    count(*) filter (where opportunity.outcome_kind = 'lost'),
    count(*) filter (where opportunity.outcome_kind = 'won' and opportunity.estimated_value is null),
    count(*) filter (where opportunity.outcome_kind = 'lost' and opportunity.estimated_value is null),
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome_kind = 'won'), 0)::bigint
    end,
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome_kind = 'lost'), 0)::bigint
    end,
    count(*) filter (where opportunity.outcome_kind = 'direct_job'),
    count(*) filter (where opportunity.outcome_kind = 'direct_job' and opportunity.estimated_value is null),
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome_kind = 'direct_job'), 0)::bigint
    end
  from (select * from public.opportunities where client_deleted_at is null) as opportunity
  where opportunity.organization_id = target_organization_id
    and opportunity.outcome_kind is not null
    and opportunity.outcome_at >= window_start and opportunity.outcome_at < window_end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.financial_time_entries_page(target_organization_id uuid, report_from date, report_to date, cursor_started_at timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_entry_id uuid DEFAULT NULL::uuid, page_limit integer DEFAULT 100, sort_direction text DEFAULT 'asc'::text)
 RETURNS TABLE(entry_id uuid, started_at timestamp with time zone, started_on date, minutes integer, user_id uuid, user_name text, job_id uuid, job_number integer, job_title text, client_id uuid, client_display_name text, client_company_name text, visit_id uuid, visit_date date, currency_code text, is_unrated boolean, cost_per_hour_minor bigint, cost_total_minor bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  can_team boolean;
  can_own boolean;
  can_view_cost boolean;
  assigned_only boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
  resolved_limit integer;
begin
  can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
  can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view')
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
  if (cursor_started_at is null) <> (cursor_entry_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');
  assigned_only := private.member_permission_scope(target_organization_id, caller, 'jobs.view') = 'assigned';

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select entry.id,
    entry.started_at,
    (entry.started_at at time zone zone)::date,
    entry.minutes,
    entry.user_id,
    profile.full_name,
    entry.job_id,
    job.job_number,
    job.title,
    job.client_id,
    client.display_name,
    client.company_name,
    entry.visit_id,
    visit.visit_date,
    job.currency_code,
    entry.cost_per_hour_minor is null,
    case when can_view_cost then entry.cost_per_hour_minor end,
    case when can_view_cost then entry.cost_total_minor end
  from public.job_time_entries as entry
  join (select * from public.jobs where client_deleted_at is null) as job
    on job.organization_id = entry.organization_id and job.id = entry.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  left join public.profiles as profile
    on profile.id = entry.user_id
  left join (select * from public.job_visits where client_deleted_at is null) as visit
    on visit.organization_id = entry.organization_id and visit.id = entry.visit_id
  where entry.organization_id = target_organization_id
    and entry.started_at >= window_start and entry.started_at < window_end
    and (can_team or entry.user_id = caller)
    and (
      not assigned_only
      or exists (
        select 1
        from public.job_visit_assignments as assignment
        where assignment.organization_id = entry.organization_id
          and assignment.user_id = caller
          and assignment.job_id = entry.job_id
      )
    )
    and (
      cursor_started_at is null
      or (sort_direction = 'asc' and (entry.started_at, entry.id) > (cursor_started_at, cursor_entry_id))
      or (sort_direction = 'desc' and (entry.started_at, entry.id) < (cursor_started_at, cursor_entry_id))
    )
  order by
    case when sort_direction = 'asc' then entry.started_at end asc,
    case when sort_direction = 'asc' then entry.id end asc,
    case when sort_direction = 'desc' then entry.started_at end desc,
    case when sort_direction = 'desc' then entry.id end desc
  limit resolved_limit;
end;
$function$;

CREATE OR REPLACE FUNCTION public.financial_uninvoiced_work_page(target_organization_id uuid, report_from date, report_to date, cursor_work_date date DEFAULT NULL::date, cursor_unit_id uuid DEFAULT NULL::uuid, page_limit integer DEFAULT 100, sort_direction text DEFAULT 'asc'::text)
 RETURNS TABLE(unit_kind text, unit_id uuid, work_date date, job_id uuid, job_number integer, job_title text, price_basis text, client_id uuid, client_display_name text, client_company_name text, currency_code text, uninvoiced_minor bigint, visit_id uuid, reminder_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    from (select * from public.job_visits where client_deleted_at is null) as visit
    join (select * from public.jobs where client_deleted_at is null) as job
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
    join (select * from public.jobs where client_deleted_at is null) as job
      on job.organization_id = reminder.organization_id and job.id = reminder.job_id
    where reminder.organization_id = target_organization_id
      and reminder.status = 'pending'
      and reminder.due_on <= today
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and job.price_basis = 'fixed_per_period'
    union all
    select 'job', job.id, (job.closed_at at time zone zone)::date, job.id, job.total_minor, null, null
    from (select * from public.jobs where client_deleted_at is null) as job
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
  join (select * from public.jobs where client_deleted_at is null) as job
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
$function$;

CREATE OR REPLACE FUNCTION public.financial_uninvoiced_work_summary(target_organization_id uuid, report_from date, report_to date)
 RETURNS TABLE(uninvoiced_minor bigint, unit_count bigint, visit_count bigint, period_count bigint, job_count bigint, distinct_job_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    from (select * from public.job_visits where client_deleted_at is null) as visit
    join (select * from public.jobs where client_deleted_at is null) as job
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
    join (select * from public.jobs where client_deleted_at is null) as job
      on job.organization_id = reminder.organization_id and job.id = reminder.job_id
    where reminder.organization_id = target_organization_id
      and reminder.status = 'pending'
      and reminder.due_on <= today
      and reminder.reminder_kind in ('monthly_last_day', 'custom_date')
      and job.price_basis = 'fixed_per_period'
    union all
    select 'job', (job.closed_at at time zone zone)::date, job.id, job.total_minor
    from (select * from public.jobs where client_deleted_at is null) as job
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
$function$;

CREATE OR REPLACE FUNCTION public.get_incomplete_assignments_for_member(target_organization_id uuid, target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  result jsonb;
begin
  if (select auth.uid()) is null or not exists (
    select 1
    from private.permitted_organizations('team.manage') as permitted(organization_id)
    where permitted.organization_id = target_organization_id
  ) then
    raise exception 'Team management is not available for this organization.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'starts_at', a.starts_at))
      from (
        select assessment.id, assessment.starts_at
        from public.assessment_assignees as assignee
        join (select * from public.assessments where client_deleted_at is null) as assessment on assessment.id = assignee.assessment_id
        where assignee.organization_id = target_organization_id
          and assignee.user_id = target_user_id
          and assessment.completed_at is null
        order by assessment.starts_at nulls last
        limit 50
      ) as a
    ), '[]'::jsonb),
    'assessments_total', (
      select count(*)
      from public.assessment_assignees as assignee
      join (select * from public.assessments where client_deleted_at is null) as assessment on assessment.id = assignee.assessment_id
      where assignee.organization_id = target_organization_id
        and assignee.user_id = target_user_id
        and assessment.completed_at is null
    ),
    'visits', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', v.id, 'visit_date', v.visit_date, 'start_time', v.start_time, 'title', v.title)
      )
      from (
        select visit.id, visit.visit_date, visit.start_time, visit.title
        from public.job_visit_assignments as assignee
        join (select * from public.job_visits where client_deleted_at is null) as visit on visit.id = assignee.visit_id
        where assignee.organization_id = target_organization_id
          and assignee.user_id = target_user_id
          and visit.completed_at is null
        order by visit.visit_date nulls last, visit.start_time nulls last
        limit 50
      ) as v
    ), '[]'::jsonb),
    'visits_total', (
      select count(*)
      from public.job_visit_assignments as assignee
      join (select * from public.job_visits where client_deleted_at is null) as visit on visit.id = assignee.visit_id
      where assignee.organization_id = target_organization_id
        and assignee.user_id = target_user_id
        and visit.completed_at is null
    ),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'due_on', t.due_on))
      from (
        select task.id, task.title, task.due_on
        from public.tasks as task
        where task.organization_id = target_organization_id
          and task.assignee_user_id = target_user_id
          and task.status = 'open'
        order by task.due_on nulls last
        limit 50
      ) as t
    ), '[]'::jsonb),
    'tasks_total', (
      select count(*)
      from public.tasks as task
      where task.organization_id = target_organization_id
        and task.assignee_user_id = target_user_id
        and task.status = 'open'
    )
  ) into result;

  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_review_request_context(p_organization_id uuid, p_actor_id uuid, p_client_id uuid, p_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  scope text;
  client_row public.clients;
  job_row public.jobs;
  sms_sender public.communication_sms_sender_identities;
  sms_registration public.communication_sms_registrations;
  sms_state text;
  sms_reason text;
  email_ready boolean;
begin
  if p_job_id is not null then
    select * into job_row from (select * from public.jobs where client_deleted_at is null) as jobs where organization_id = p_organization_id and id = p_job_id;
    if job_row.id is null then return null; end if;
  end if;
  select * into client_row from public.clients
  where organization_id = p_organization_id
    and id = coalesce(job_row.client_id, p_client_id)
    and deleted_at is null;
  if client_row.id is null then return null; end if;

  if not private.review_request_actor_may_ask(p_organization_id, p_actor_id, p_job_id) then
    return null;
  end if;
  scope := private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.request');

  -- Texting is ready when the default number could send right now (the same test the send itself runs).
  select * into sms_sender from public.communication_sms_sender_identities
  where organization_id = p_organization_id and is_default_sender and lifecycle_state = 'ready' and capable_sms;
  if sms_sender.id is null or sms_sender.registration_id is null then
    sms_reason := 'no_number';
  else
    select * into sms_registration from public.communication_sms_registrations
    where organization_id = p_organization_id and id = sms_sender.registration_id;
    select state into sms_state from public.communication_sms_outbound_state(
      p_organization_id, sms_sender.country_code, sms_sender.sender_type, sms_registration.use_case);
    if sms_state = 'outbound_paused' then sms_reason := 'paused';
    elsif sms_state is distinct from 'ready' then sms_reason := 'not_ready';
    end if;
  end if;

  email_ready := (private.review_request_email_sender(p_organization_id, 'manual')).id is not null;

  return jsonb_build_object(
    'business_name', (select name from public.organizations where id = p_organization_id),
    'client', jsonb_build_object(
      'id', client_row.id,
      'name', client_row.display_name,
      'first_name', nullif(btrim(client_row.first_name), '')
    ),
    'job', case when job_row.id is null then null else jsonb_build_object(
      'id', job_row.id,
      'job_number', job_row.job_number,
      'title', job_row.title,
      'eligible', private.review_request_job_is_eligible(p_organization_id, job_row.id)
    ) end,
    -- The client's jobs that can be asked about, most recently completed first. Only from the client page.
    'jobs', case when p_job_id is not null then '[]'::jsonb else coalesce((
      select jsonb_agg(item.body order by item.last_completed_at desc)
      from (
        select jsonb_build_object(
                 'id', job.id, 'job_number', job.job_number, 'title', job.title,
                 'last_completed_at', max(visit.completed_at)
               ) as body,
               max(visit.completed_at) as last_completed_at
        from (select * from public.jobs where client_deleted_at is null) as job
        join (select * from public.job_visits where client_deleted_at is null) as visit
          on visit.organization_id = job.organization_id and visit.job_id = job.id
         and visit.completed_at is not null
        where job.organization_id = p_organization_id
          and job.client_id = client_row.id
          and (job.status = 'closed' or job.job_type = 'recurring')
          and (scope = 'all' or exists (
            select 1 from public.job_visit_assignments as assignment
            where assignment.organization_id = job.organization_id
              and assignment.job_id = job.id and assignment.user_id = p_actor_id))
        group by job.id
        order by max(visit.completed_at) desc
        limit 25
      ) as item
    ), '[]'::jsonb) end,
    'phones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', method.id, 'value', method.value, 'label', method.label, 'is_primary', method.is_primary,
               'contact_name', nullif(btrim(concat_ws(' ', contact.first_name, contact.last_name)), ''),
               'sms_consent', public.communication_sms_consent_status(p_organization_id, method.id, 'service')
             ) order by method.is_primary desc, method.created_at, method.id)
      from public.client_contact_methods as method
      left join public.client_contacts as contact
        on contact.organization_id = method.organization_id and contact.id = method.client_contact_id
      where method.organization_id = p_organization_id and method.client_id = client_row.id
        and method.kind = 'phone'
    ), '[]'::jsonb),
    'emails', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', method.id, 'value', method.value, 'label', method.label, 'is_primary', method.is_primary,
               'contact_name', nullif(btrim(concat_ws(' ', contact.first_name, contact.last_name)), ''),
               'suppressed', (
                 select suppression.reason from public.communication_email_suppressions as suppression
                 where suppression.organization_id = p_organization_id
                   and suppression.recipient_email = method.normalized_value
                   and suppression.released_at is null
                 order by suppression.reason limit 1)
             ) order by method.is_primary desc, method.created_at, method.id)
      from public.client_contact_methods as method
      left join public.client_contacts as contact
        on contact.organization_id = method.organization_id and contact.id = method.client_contact_id
      where method.organization_id = p_organization_id and method.client_id = client_row.id
        and method.kind = 'email'
    ), '[]'::jsonb),
    'sms_ready', sms_reason is null,
    'sms_reason', sms_reason,
    'email_ready', email_ready,
    -- The newest request to this client about anything, so the panel can say "already asked on ...".
    'last_asked_at', (
      select max(request.created_at) from (select * from public.review_requests where client_deleted_at is null) as request
      where request.organization_id = p_organization_id and request.client_id = client_row.id
        and request.cancelled_at is null
        and exists (
          select 1 from public.review_request_messages as message
          where message.organization_id = request.organization_id and message.request_id = request.id
        )
    ),
    'requests', coalesce((
      select jsonb_agg(private.review_request_summary(request) order by request.created_at desc)
      from (
        select * from (select * from public.review_requests where client_deleted_at is null) as request
        where request.organization_id = p_organization_id and request.client_id = client_row.id
          and (p_job_id is null or request.job_id = p_job_id)
        order by request.created_at desc
        limit 5
      ) as request
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.invoice_list_facts(target_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  today date;
  zone text;
  window_start timestamptz;
  paid_count bigint;
  average_days numeric;
  reminder_days integer;
  reminders_on boolean;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  today := private.organization_today(target_organization_id);
  window_start := ((today - 29)::timestamp at time zone zone);

  with touched as (
    -- Invoices that took money in the window, and invoices closed by hand in it.
    select distinct allocation.invoice_id
    from public.invoice_payment_allocations as allocation
    where allocation.organization_id = target_organization_id
      and allocation.created_at >= window_start
    union
    select invoice.id
    from (select * from public.invoices where client_deleted_at is null) as invoice
    where invoice.organization_id = target_organization_id
      and invoice.marked_received_at >= window_start
  ),
  paid as (
    select
      invoice.issue_date,
      coalesce(invoice.marked_received_at, settled.settled_at) as paid_at
    from touched
    join (select * from public.invoices where client_deleted_at is null) as invoice
      on invoice.organization_id = target_organization_id and invoice.id = touched.invoice_id
    left join lateral (
      -- The last moment the running applied total crossed up to the invoice total: a payment later taken back
      -- and paid again counts from the second payment.
      select crossing.created_at as settled_at
      from (
        select
          running.created_at,
          running.applied_minor,
          lag(running.applied_minor, 1, 0::numeric) over (order by running.created_at, running.id) as before_minor
        from (
          select
            entry.id,
            entry.created_at,
            sum(case when entry.entry_type = 'applied' then entry.amount_minor else -entry.amount_minor end)
              over (order by entry.created_at, entry.id) as applied_minor
          from public.invoice_payment_allocations as entry
          where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
        ) as running
      ) as crossing
      where crossing.applied_minor >= invoice.total_minor
        and crossing.before_minor < invoice.total_minor
      order by crossing.created_at desc
      limit 1
    ) as settled on true
    where invoice.voided_at is null
      and invoice.written_off_at is null
      and invoice.replaced_at is null
      and (invoice.issued_at is not null or invoice.recognized_at is not null)
      and invoice.total_minor > 0
      and (
        invoice.marked_received_at is not null
        or (select coalesce(sum(case when entry.entry_type = 'applied' then entry.amount_minor
                                     else -entry.amount_minor end), 0)
            from public.invoice_payment_allocations as entry
            where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id)
           >= invoice.total_minor
      )
  )
  select
    count(*),
    -- A deposit taken before the invoice was issued counts as paid on the day it was issued, never earlier.
    avg(greatest((paid.paid_at at time zone zone)::date - paid.issue_date, 0))
  into paid_count, average_days
  from paid
  where paid.paid_at >= window_start;

  select
    true,
    coalesce((version.definition -> 'trigger' -> 'config' ->> 'days_after_due')::integer, 1)
  into reminders_on, reminder_days
  from public.automation_recipes as recipe
  join public.automation_recipe_versions as version on version.id = recipe.current_version_id
  where recipe.organization_id = target_organization_id
    and recipe.status = 'active'
    and recipe.active_trigger_key = 'invoice.past_due'
  order by version.activated_at, recipe.id
  limit 1;

  return jsonb_build_object(
    'paid_count', paid_count,
    'average_days_to_paid', case when paid_count > 0 then round(average_days)::integer end,
    'overdue_reminders_on', coalesce(reminders_on, false),
    'overdue_reminder_days_after_due', reminder_days
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.invoice_list_page(target_organization_id uuid, search_like text DEFAULT NULL::text, search_number bigint DEFAULT NULL::bigint, status_filter text[] DEFAULT NULL::text[], sort_key text DEFAULT 'created'::text, sort_dir text DEFAULT 'desc'::text, created_from timestamp with time zone DEFAULT NULL::timestamp with time zone, created_to timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_created timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_number bigint DEFAULT NULL::bigint, cursor_id uuid DEFAULT NULL::uuid, page_limit integer DEFAULT 25, client_id_filter uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, invoice_number integer, subject text, currency_code text, issue_date date, due_date date, issued_at timestamp with time zone, created_at timestamp with time zone, is_replaced boolean, derived_status text, client_id uuid, client_display_name text, client_company_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  today date;
  ascending boolean := lower(sort_dir) = 'asc';
  sort_column text;
  comparison text;
  seek_clause text := '';
  statement text;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  if page_limit is null or page_limit < 1 or page_limit > 50 then
    page_limit := 25;
  end if;
  today := private.organization_today(target_organization_id);

  -- Whitelisted, never interpolated from caller text: only these two columns and two directions are ever
  -- placed into the statement, and every value travels as a bound parameter.
  sort_column := case when sort_key = 'number' then 'invoice.invoice_number' else 'invoice.created_at' end;
  comparison := case when ascending then '>' else '<' end;

  if sort_key = 'number' and cursor_number is not null and cursor_id is not null then
    seek_clause := format(
      ' and (invoice.invoice_number %1$s $10 or (invoice.invoice_number = $10 and invoice.id %1$s $11))',
      comparison
    );
  elsif sort_key <> 'number' and cursor_created is not null and cursor_id is not null then
    seek_clause := format(
      ' and (invoice.created_at %1$s $9 or (invoice.created_at = $9 and invoice.id %1$s $11))',
      comparison
    );
  end if;

  statement := format($q$
    select
      invoice.id,
      invoice.invoice_number,
      invoice.subject,
      invoice.currency_code,
      invoice.issue_date,
      invoice.due_date,
      invoice.issued_at,
      invoice.created_at,
      invoice.replaced_at is not null as is_replaced,
      label.derived_status,
      invoice.client_id,
      client.display_name as client_display_name,
      client.company_name as client_company_name
    from (select * from public.invoices where client_deleted_at is null) as invoice
    left join public.clients as client
      on client.organization_id = invoice.organization_id and client.id = invoice.client_id
    left join lateral (
      select coalesce(sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end), 0)::bigint as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
    ) as allocation on true
    cross join lateral (
      select case
        when invoice.replaced_at is not null then invoice.frozen_status_label
        else private.invoice_live_status(
          invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
          invoice.marked_received_at, invoice.total_minor, allocation.applied_minor, invoice.due_date, $2)
      end as derived_status
    ) as label
    where invoice.organization_id = $1
      and ($3::text is null or invoice.subject ilike $3
           or ($4::bigint is not null and invoice.invoice_number = $4))
      and ($5::timestamptz is null or invoice.created_at >= $5)
      and ($6::timestamptz is null or invoice.created_at <= $6)
      and ($7::text[] is null or label.derived_status = any($7))
      and ($12::uuid is null or invoice.client_id = $12)
      %1$s
    order by %2$s %3$s, invoice.id %3$s
    limit $8
  $q$, seek_clause, sort_column, case when ascending then 'asc' else 'desc' end);

  return query execute statement
    using target_organization_id, today, search_like, search_number, created_from, created_to,
          status_filter, page_limit, cursor_created, cursor_number, cursor_id, client_id_filter;
end;
$function$;

CREATE OR REPLACE FUNCTION public.invoice_status_counts(target_organization_id uuid)
 RETURNS TABLE(derived_status text, total bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  today date;
begin
  if not private.member_has_permission(target_organization_id, caller, 'invoices.view') then
    raise exception 'You do not have access to these invoices.' using errcode = 'insufficient_privilege';
  end if;
  today := private.organization_today(target_organization_id);

  return query
    select label.derived_status, count(*)::bigint as total
    from (select * from public.invoices where client_deleted_at is null) as invoice
    left join lateral (
      select coalesce(sum(case when entry.entry_type = 'applied'
        then entry.amount_minor else -entry.amount_minor end), 0)::bigint as applied_minor
      from public.invoice_payment_allocations as entry
      where entry.organization_id = invoice.organization_id and entry.invoice_id = invoice.id
    ) as allocation on true
    cross join lateral (
      select case
        when invoice.replaced_at is not null then invoice.frozen_status_label
        else private.invoice_live_status(
          invoice.voided_at, invoice.written_off_at, invoice.issued_at, invoice.recognized_at,
          invoice.marked_received_at, invoice.total_minor, allocation.applied_minor, invoice.due_date, today)
      end as derived_status
    ) as label
    where invoice.organization_id = target_organization_id
    group by label.derived_status;
end;
$function$;

CREATE OR REPLACE FUNCTION public.job_report_customer_preview(target_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  report_row public.job_reports;
  effective_include_price boolean;
  business_name text;
  document jsonb;
begin
  select * into job_row from (select * from public.jobs where client_deleted_at is null) as jobs where id = target_job_id;
  if not found or not private.member_has_permission(job_row.organization_id, caller, 'jobs.view')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = target_job_id;

  effective_include_price := coalesce(report_row.include_price, false)
    and private.member_has_permission(job_row.organization_id, caller, 'jobs.view_price');

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = job_row.organization_id;

  document := private.job_report_customer_document(job_row, business_name, effective_include_price);

  return jsonb_build_object(
    'document', document,
    'preview', jsonb_build_object(
      'has_content', private.job_report_has_content(job_row.organization_id, target_job_id),
      'prices_withheld', coalesce(report_row.include_price, false) and not effective_include_price
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.job_report_state(target_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  org uuid;
  report_row public.job_reports;
  link_row public.job_report_access_links;
  business_name text;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into job_row from (select * from public.jobs where client_deleted_at is null) as job where job.id = target_job_id;
  org := job_row.organization_id;
  if org is null then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if not private.member_has_permission(org, caller, 'jobs.edit')
     or not private.can_view_job(org, target_job_id) then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = org and job_id = target_job_id;

  -- At most one link is live at a time: issuing a new one turns the old one off.
  select * into link_row
  from public.job_report_access_links as link
  where link.organization_id = org
    and link.job_id = target_job_id
    and link.revoked_at is null
    and (link.expires_at is null or link.expires_at > now())
  order by link.issued_at desc
  limit 1;

  if link_row.id is not null then
    select organization.name into business_name
    from public.organizations as organization
    where organization.id = org;
  end if;

  return jsonb_build_object(
    'report', jsonb_build_object(
      'include_service_details', coalesce(report_row.include_service_details, true),
      'include_price', coalesce(report_row.include_price, false),
      'signature_id', report_row.signature_id,
      'summary', report_row.summary,
      -- Every photo on the report, in its arranged order.
      'photo_ids', (
        select coalesce(jsonb_agg(photo.file_id
          order by section.position nulls first, photo.position,
                   case photo.pair_side when 'after' then 1 else 0 end), '[]'::jsonb)
        from public.job_report_photos as photo
        left join public.job_report_sections as section
          on section.organization_id = photo.organization_id
         and section.job_id = photo.job_id
         and section.id = photo.section_id
        where photo.organization_id = org and photo.job_id = target_job_id
      ),
      -- The same arrangement save_job_report takes. A lone pair half (its partner trashed) reads back as a
      -- single photo, so the next save stores it as one.
      'layout', jsonb_build_object(
        'top', private.job_report_layout_items(org, target_job_id, null),
        'sections', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'heading', section.heading,
              'note', section.note,
              'items', private.job_report_layout_items(org, target_job_id, section.id)
            ) order by section.position
          ), '[]'::jsonb)
          from public.job_report_sections as section
          where section.organization_id = org and section.job_id = target_job_id
        )
      ),
      'checklist', (
        select coalesce(jsonb_agg(jsonb_build_object('visit_id', sel.visit_id, 'item_id', sel.item_id)),
          '[]'::jsonb)
        from public.job_report_checklist_items as sel
        where sel.organization_id = org and sel.job_id = target_job_id
      )
    ),
    'has_content', private.job_report_has_content(org, target_job_id),
    'can_view_price', private.member_has_permission(org, caller, 'jobs.view_price'),
    -- The customer's live link, if any, and whether it still shows what a new link would. Compared as whole
    -- documents, so an edited caption or work list counts as a change the customer has not been sent.
    'live_link', case when link_row.id is null then null else jsonb_build_object(
      'issued_at', link_row.issued_at,
      'recipient_email', link_row.recipient_email,
      'up_to_date', link_row.frozen_document is not distinct from private.job_report_customer_document(
        job_row, business_name, coalesce(report_row.include_price, false))
    ) end,
    'candidates', jsonb_build_object(
      -- Every checked, un-trashed photo linked to the job itself or to any of its visits. A line photo is a
      -- picture of what was priced, not of the work, so it is not offered.
      'photos', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'file_id', candidate.id,
            'file_name', candidate.display_name,
            'mime_type', candidate.mime_type,
            'has_thumbnail', candidate.thumbnail_object_key is not null,
            'created_at', candidate.created_at,
            'caption', candidate.caption,
            'labels', (
              select coalesce(jsonb_agg(label.name order by lower(label.name), label.id), '[]'::jsonb)
              from public.file_label_assignments as assignment
              join public.file_labels as label
                on label.organization_id = assignment.organization_id and label.id = assignment.label_id
              where assignment.organization_id = org
                and assignment.file_id = candidate.id
            )
          ) order by candidate.created_at, candidate.id
        ), '[]'::jsonb)
        from public.files as candidate
        where candidate.organization_id = org
          and candidate.kind = 'image'
          and candidate.processing_state = 'available'
          and candidate.trashed_at is null
          and exists (
            select 1 from public.file_links as link
            where link.organization_id = org
              and link.file_id = candidate.id
              and link.role <> 'line_photo'
              and (
                (link.entity_type = 'job' and link.entity_id = target_job_id)
                or (link.entity_type = 'visit' and link.entity_id in (
                  select visit.id from (select * from public.job_visits where client_deleted_at is null) as visit
                  where visit.organization_id = org and visit.job_id = target_job_id
                ))
              )
          )
      ),
      -- Answered checklist questions, grouped by the visit that answered them. Only answered ones are
      -- pickable: there is nothing to show a customer for a blank question.
      'visits', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'visit_id', grp.visit_id,
            'visit_date', grp.visit_date,
            'items', grp.items
          ) order by grp.visit_date, grp.visit_id
        ), '[]'::jsonb)
        from (
          select visit.id as visit_id,
                 visit.visit_date,
                 jsonb_agg(
                   jsonb_build_object(
                     'item_id', item.id,
                     'label', item.label,
                     'item_type', item.item_type,
                     'value', answer.value
                   ) order by item.position, item.id
                 ) as items
          from public.visit_checklist_answers as answer
          join (select * from public.job_visits where client_deleted_at is null) as visit
            on visit.organization_id = answer.organization_id and visit.id = answer.visit_id
          join public.job_checklist_items as item
            on item.organization_id = answer.organization_id and item.id = answer.item_id
          where answer.organization_id = org and answer.job_id = target_job_id
          group by visit.id, visit.visit_date
        ) as grp
      ),
      -- The job's signatures, so one can be shown on the report.
      'signatures', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', sig.id,
            'signer_name', sig.signer_name,
            'signature_type', sig.signature_type,
            'collected_at', sig.collected_at
          ) order by sig.collected_at desc, sig.id desc
        ), '[]'::jsonb)
        from public.job_signatures as sig
        where sig.organization_id = org and sig.job_id = target_job_id
      )
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_review_feedback(p_organization_id uuid, p_actor_id uuid, p_status text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_cursor_submitted_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  page_size integer := least(greatest(coalesce(p_limit, 25), 1), 50);
  search_pattern text := null;
  rows_json jsonb;
  cursor_submitted_at timestamptz;
  cursor_id uuid;
  has_more boolean;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.feedback')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.feedback') is distinct from 'all' then
    return null;
  end if;

  if p_status is not null and p_status not in ('open', 'new', 'contacting', 'resolved', 'closed') then
    raise exception 'Unknown feedback status.' using errcode = 'check_violation';
  end if;
  if nullif(btrim(p_search), '') is not null then
    search_pattern := '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with picked as (
    select feedback.id, feedback.submitted_at
    from public.review_feedback as feedback
    join (select * from public.review_requests where client_deleted_at is null) as request
      on request.organization_id = feedback.organization_id and request.id = feedback.request_id
    where feedback.organization_id = p_organization_id
      and (p_status is null
           or (p_status = 'open' and feedback.status in ('new', 'contacting'))
           or feedback.status = p_status)
      and (p_cursor_submitted_at is null
           or (feedback.submitted_at, feedback.id) < (p_cursor_submitted_at, p_cursor_id))
      and (search_pattern is null or exists (
        select 1 from public.clients as client
        where client.organization_id = request.organization_id
          and client.id = request.client_id
          and client.display_name ilike search_pattern
      ))
    order by feedback.submitted_at desc, feedback.id desc
    limit page_size + 1
  ),
  numbered as (
    select picked.id, picked.submitted_at,
           row_number() over (order by picked.submitted_at desc, picked.id desc) as position
    from picked
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'id', feedback.id,
        'request_id', feedback.request_id,
        'status', feedback.status,
        'rating', feedback.rating,
        'submitted_at', feedback.submitted_at,
        'questions', feedback.questions,
        'answers', feedback.answers,
        'channel', request.channel,
        'client', case when client.id is null then null else jsonb_build_object(
          'id', client.id,
          'name', client.display_name,
          'email', (select method.value from public.client_contact_methods as method
                    where method.organization_id = client.organization_id and method.client_id = client.id
                      and method.kind = 'email'
                    order by method.is_primary desc, method.created_at limit 1),
          'phone', (select method.value from public.client_contact_methods as method
                    where method.organization_id = client.organization_id and method.client_id = client.id
                      and method.kind = 'phone'
                    order by method.is_primary desc, method.created_at limit 1)
        ) end,
        'job_id', request.job_id,
        'job_number', job.job_number,
        'job_title', job.title
      ) order by numbered.position
    ) filter (where numbered.position <= page_size), '[]'::jsonb),
    coalesce(bool_or(numbered.position > page_size), false),
    (array_agg(numbered.submitted_at order by numbered.position) filter (where numbered.position = page_size))[1],
    (array_agg(numbered.id order by numbered.position) filter (where numbered.position = page_size))[1]
  into rows_json, has_more, cursor_submitted_at, cursor_id
  from numbered
  join public.review_feedback as feedback on feedback.id = numbered.id
  join (select * from public.review_requests where client_deleted_at is null) as request
    on request.organization_id = feedback.organization_id and request.id = feedback.request_id
  left join public.clients as client
    on client.organization_id = request.organization_id and client.id = request.client_id
   and client.deleted_at is null
  left join (select * from public.jobs where client_deleted_at is null) as job
    on job.organization_id = request.organization_id and job.id = request.job_id;

  return jsonb_build_object(
    'feedback', rows_json,
    'next_cursor', case when has_more then jsonb_build_object(
      'submitted_at', cursor_submitted_at, 'id', cursor_id) else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_review_requests(p_organization_id uuid, p_actor_id uuid, p_status text DEFAULT NULL::text, p_channel text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  page_size integer := least(greatest(coalesce(p_limit, 25), 1), 50);
  search_pattern text := null;
  rows_json jsonb;
  cursor_created_at timestamptz;
  cursor_id uuid;
  has_more boolean;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.view')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.view') is distinct from 'all' then
    return null;
  end if;

  if p_status is not null and p_status not in (
    'queued', 'scheduled', 'sent', 'delivered', 'failed', 'cancelled', 'not_sent',
    'opened', 'continued_to_google', 'feedback_submitted'
  ) then
    raise exception 'Unknown review request status.' using errcode = 'check_violation';
  end if;
  if p_channel is not null and p_channel not in ('sms', 'email') then
    raise exception 'Unknown review request channel.' using errcode = 'check_violation';
  end if;
  if nullif(btrim(p_search), '') is not null then
    search_pattern := '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with picked as (
    select request.id, request.created_at
    from (select * from public.review_requests where client_deleted_at is null) as request
    where request.organization_id = p_organization_id
      and (p_channel is null or request.channel = p_channel)
      and (p_cursor_created_at is null
           or (request.created_at, request.id) < (p_cursor_created_at, p_cursor_id))
      and (p_status is null or private.review_request_status(request) = p_status)
      and (search_pattern is null or exists (
        select 1 from public.clients as client
        where client.organization_id = request.organization_id
          and client.id = request.client_id
          and client.display_name ilike search_pattern
      ))
    order by request.created_at desc, request.id desc
    limit page_size + 1
  ),
  numbered as (
    select picked.id, picked.created_at,
           row_number() over (order by picked.created_at desc, picked.id desc) as position
    from picked
  )
  select
    coalesce(jsonb_agg(
      private.review_request_summary(request) || jsonb_build_object(
        'client', case when client.id is null then null else jsonb_build_object(
          'id', client.id, 'name', client.display_name) end,
        'job_title', job.title,
        'rating', request.rating,
        'opened_at', request.first_opened_at,
        'continued_to_google_at', request.continued_to_google_at,
        'feedback_submitted_at', request.feedback_submitted_at,
        'cancelled_at', request.cancelled_at
      ) order by numbered.position
    ) filter (where numbered.position <= page_size), '[]'::jsonb),
    coalesce(bool_or(numbered.position > page_size), false),
    (array_agg(numbered.created_at order by numbered.position) filter (where numbered.position = page_size))[1],
    (array_agg(numbered.id order by numbered.position) filter (where numbered.position = page_size))[1]
  into rows_json, has_more, cursor_created_at, cursor_id
  from numbered
  join (select * from public.review_requests where client_deleted_at is null) as request on request.id = numbered.id
  left join public.clients as client
    on client.organization_id = request.organization_id and client.id = request.client_id
   and client.deleted_at is null
  left join (select * from public.jobs where client_deleted_at is null) as job
    on job.organization_id = request.organization_id and job.id = request.job_id;

  return jsonb_build_object(
    'requests', rows_json,
    'next_cursor', case when has_more then jsonb_build_object(
      'created_at', cursor_created_at, 'id', cursor_id) else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.organization_tax_default_property_count(target_organization_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  result integer;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into result
  from (select * from public.properties where client_deleted_at is null) as properties
  where organization_id = target_organization_id and tax_rate_id is null and deleted_at is null;

  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.organization_tax_rate_property_count(target_organization_id uuid, target_rate_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  result integer;
begin
  if not private.has_permission(target_organization_id, 'settings.taxes.manage') then
    raise exception 'You do not have access to manage taxes.' using errcode = 'insufficient_privilege';
  end if;

  select count(*) into result
  from (select * from public.properties where client_deleted_at is null) as properties
  where organization_id = target_organization_id and tax_rate_id = target_rate_id;

  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_board_page(target_organization_id uuid, target_stage text, page_limit integer DEFAULT 25, sort_key text DEFAULT 'attention'::text, sort_direction text DEFAULT 'desc'::text, owner_filter text DEFAULT 'all'::text, filter_owner_user_id uuid DEFAULT NULL::uuid, created_from timestamp with time zone DEFAULT NULL::timestamp with time zone, created_to timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_sort_key text DEFAULT NULL::text, cursor_phase integer DEFAULT NULL::integer, cursor_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_value numeric DEFAULT NULL::numeric, cursor_id uuid DEFAULT NULL::uuid, board_today date DEFAULT NULL::date, cursor_date date DEFAULT NULL::date, search_like text DEFAULT NULL::text, search_digits text DEFAULT NULL::text, search_number bigint DEFAULT NULL::bigint, lead_source_filter text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, stage text, stage_entered_at timestamp with time zone, outcome text, created_at timestamp with time zone, request_id uuid, request_status text, client_id uuid, client_display_name text, client_company_name text, property_id uuid, property_label text, property_address_line1 text, property_city text, property_state_region text, property_postal_code text, owner_user_id uuid, owner_full_name text, owner_avatar_url text, estimated_value numeric, expected_close_on date, next_task_due_on date, task_id uuid, task_title text, task_due_on date, quote_id uuid, quote_status text, assessment_starts_at timestamp with time zone, assessment_ends_at timestamp with time zone, custom_stage_id uuid, quote_delivery_failed_at timestamp with time zone, quote_delivery_failed_email text, quote_delivery_failure text, progress_at timestamp with time zone, client_lead_source text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  phase integer;
  select_body text;
  stage_predicate text;
  filters text := '';
  keyset text;
  ordering text;
  fetched integer;
  remaining integer;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Every card ('all', for the table), one named logical column, the seven real stages, or one of this
  -- organization's custom stages. Written
  -- out rather than assembled from a caller's list, so 'assessment' is the only grouping that exists and no
  -- other combination is reachable. Every one is a value of `board_column`, the column a card is drawn in:
  -- its custom stage when somebody placed it in one, its real stage otherwise. So a protected column never
  -- shows a card that is sitting in a custom stage, and all of them read through the same indexes.
  if target_stage = 'all' then
    -- The table view: every card the board draws, in one list. Spelled exactly as the partial predicate
    -- of the opportunities_board_all_* indexes, so the planner matches it and stops at the page.
    stage_predicate := $p$ and opportunity.board_column <> 'request_closed'$p$;
  elsif target_stage = 'assessment' then
    -- Spelled exactly as opportunities_board_assessment_group_idx spells it: the planner matches the two
    -- expressions before attempting a harder proof, and a mismatch here silently costs the index.
    stage_predicate :=
      $p$ and opportunity.board_column in
        ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed')$p$;
  elsif target_stage in (
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed',
    'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
  ) then
    stage_predicate := format(' and opportunity.board_column = %L', target_stage);
  elsif target_stage ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and exists (
          select 1
          from public.pipeline_custom_stages as custom_stage
          where custom_stage.organization_id = target_organization_id
            and custom_stage.id = target_stage::uuid
            and custom_stage.disabled_at is null
        ) then
    -- Through uuid and back, so the text compared is the one spelling `board_column` holds.
    stage_predicate := format(' and opportunity.board_column = %L', target_stage::uuid::text);
  else
    raise exception 'That is not a board column.' using errcode = 'invalid_parameter_value';
  end if;

  if sort_key not in ('attention', 'stage_entered_at', 'created_at', 'estimated_value', 'expected_close_on')
     or sort_direction not in ('asc', 'desc')
     or owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to sort or filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- "Overdue" and "due today" are questions about the contractor's calendar, which only the route knows.
  if sort_key = 'attention' and board_today is null then
    raise exception 'Sorting by Task needs today''s date.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat cards, so it is refused instead. The column a cursor belongs to is
  -- checked by the route, which is the only place that knows the logical-column vocabulary.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- One row over the asked-for page is how the caller detects there is more, so the cap is 50 plus one.
  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Asked once for the whole page. A caller without it is checked against the set of clients they are
  -- assigned to, read once per query rather than once per card.
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  -- Ordering by money is reading money. Withholding the amounts while handing over the ranking would
  -- give the column away one comparison at a time.
  if sort_key = 'estimated_value' and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.stage,
      opportunity.stage_entered_at,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.request_id,
      request.status,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      opportunity.property_id,
      case when client_visible.allowed then property.label end,
      case when client_visible.allowed then property.address_line1 end,
      case when client_visible.allowed then property.city end,
      case when client_visible.allowed then property.state_region end,
      case when client_visible.allowed then property.postal_code end,
      opportunity.owner_user_id,
      -- A teammate who never typed a name is shown by sign-in email, as the owner menu shows them; only an
      -- owner who has left the team comes back without a name. The email is looked up only for the
      -- unnamed, one primary-key read each.
      case when owner_is_teammate.yes then coalesce(
        nullif(btrim(owner_profile.full_name), ''),
        (select owner_account.email::text from auth.users as owner_account
          where owner_account.id = opportunity.owner_user_id)
      ) end,
      case when owner_is_teammate.yes then owner_profile.avatar_url end,
      case when %L::boolean then opportunity.estimated_value end,
      opportunity.expected_close_on,
      opportunity.next_task_due_on,
      open_task.id,
      open_task.title,
      open_task.due_on,
      opportunity.quote_id,
      quote.status,
      assessment.starts_at,
      assessment.ends_at,
      opportunity.custom_stage_id,
      case when last_email.failure is not null then last_email.failed_at end,
      case when last_email.failure is not null and client_visible.allowed then last_email.recipient_email end,
      last_email.failure,
      opportunity.progress_at,
      case when client_visible.allowed then client.lead_source end
    from (select * from public.opportunities where client_deleted_at is null) as opportunity
    cross join lateral (
      select
        %L::boolean
        or opportunity.client_id in (select private.current_user_assigned_client_ids()) as allowed
    ) as client_visible
    cross join lateral (
      select exists (
        select 1
        from public.organization_members as owner_membership
        where owner_membership.organization_id = opportunity.organization_id
          and owner_membership.user_id = opportunity.owner_user_id
      ) as yes
    ) as owner_is_teammate
    left join lateral (
      select task.id, task.title, task.due_on
      from public.tasks as task
      where task.organization_id = opportunity.organization_id
        and task.opportunity_id = opportunity.id
        and task.status = 'open'
      order by task.due_on nulls last, task.created_at, task.id
      limit 1
    ) as open_task on true
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join (select * from public.properties where client_deleted_at is null) as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join (select * from public.requests where client_deleted_at is null) as request
      on request.id = opportunity.request_id
     and request.organization_id = opportunity.organization_id
    left join (select * from public.quotes where client_deleted_at is null) as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.profiles as owner_profile
      on owner_profile.id = opportunity.owner_user_id
    left join (select * from public.assessments where client_deleted_at is null) as assessment
      on assessment.request_id = opportunity.request_id
     and assessment.organization_id = opportunity.organization_id
    left join lateral (
      -- The quote's most recent email, and whether it failed. Asked only for a card still waiting on the
      -- customer, so no other column pays for it. A send to two addresses shares one moment, and the
      -- failed one is picked first: one address the quote never reached is enough to say so.
      select
        email.recipient_email,
        coalesce(email.delivery_outcome_at, email.updated_at) as failed_at,
        private.quote_email_delivery_failure(email.status, email.delivery_outcome) as failure
      from public.communication_delivery_intents as email
      where opportunity.stage = 'quote_awaiting_response'
        and email.organization_id = opportunity.organization_id
        and email.quote_id = opportunity.quote_id
        and email.quote_version_id is not null
        and email.channel = 'email'
      order by email.created_at desc,
        (private.quote_email_delivery_failure(email.status, email.delivery_outcome) is not null) desc,
        email.id desc
      limit 1
    ) as last_email on true
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
  $body$, caller_sees_money, caller_sees_clients, target_organization_id) || stage_predicate;

  -- Only the clauses this request actually needs. "Or the filter is null" reads the same and costs the
  -- index scan.
  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants. The upper bound is exclusive: it is the first moment of the day after.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  -- Search and lead source, in the same words the column headings count with.
  filters := filters || private.pipeline_board_filter_clause(
    search_like, search_digits, search_number, lead_source_filter, target_organization_id);

  -- The Task order, in three phases read one after another until the page is full: 1 is a Task due today or
  -- earlier, oldest due first, so overdue comes before today; 2 is no dated Task, longest in this column
  -- first; 3 is a Task due later, soonest first. The direction does not apply: this is a work queue.
  if sort_key = 'attention' then
    phase := coalesce(cursor_phase, 1);
    if phase not in (1, 2, 3) then
      raise exception 'That page marker belongs to a different order.'
        using errcode = 'invalid_parameter_value';
    end if;

    remaining := resolved_limit;
    while phase <= 3 and remaining > 0 loop
      -- Only the phase the cursor was cut from pages past it; a later phase starts from its beginning.
      if phase = 1 then
        keyset := case when cursor_id is null or cursor_phase is distinct from 1 then '' else format(
          ' and (opportunity.next_task_due_on, opportunity.id) > (%L::date, %L::uuid)',
          cursor_date, cursor_id) end;
        return query execute select_body || filters
          || format(' and opportunity.next_task_due_on <= %L::date', board_today) || keyset
          || ' order by opportunity.next_task_due_on asc, opportunity.id asc'
          || format(' limit %s', remaining);
      elsif phase = 2 then
        keyset := case when cursor_id is null or cursor_phase is distinct from 2 then '' else format(
          ' and (opportunity.stage_entered_at, opportunity.id) > (%L::timestamptz, %L::uuid)',
          cursor_timestamp, cursor_id) end;
        return query execute select_body || filters
          || ' and opportunity.next_task_due_on is null' || keyset
          || ' order by opportunity.stage_entered_at asc, opportunity.id asc'
          || format(' limit %s', remaining);
      else
        keyset := case when cursor_id is null or cursor_phase is distinct from 3 then '' else format(
          ' and (opportunity.next_task_due_on, opportunity.id) > (%L::date, %L::uuid)',
          cursor_date, cursor_id) end;
        return query execute select_body || filters
          || format(' and opportunity.next_task_due_on > %L::date', board_today) || keyset
          || ' order by opportunity.next_task_due_on asc, opportunity.id asc'
          || format(' limit %s', remaining);
      end if;
      get diagnostics fetched = row_count;
      remaining := remaining - fetched;
      phase := phase + 1;
    end loop;
    return;
  end if;

  if sort_key in ('stage_entered_at', 'created_at') then
    -- Ties break the same way the sort runs, so the pair reads as one index range rather than as a
    -- filter over everything above it. This is also what keeps the grouped column's order globally
    -- correct: one keyset across all three assessment states, never three lists stitched together.
    if sort_direction = 'desc' then
      ordering := format(' order by opportunity.%1$I desc, opportunity.id desc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by opportunity.%1$I asc, opportunity.id asc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    end if;

    return query execute select_body || filters || keyset || ordering
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Value and expected close sort the same way, phase by phase. Phase 1 is the cards that have one, in the
  -- caller's chosen direction; phase 2 is the ones that do not, always oldest id first, which is the order
  -- they already sit in.
  phase := coalesce(cursor_phase, 1);
  if phase not in (1, 2) then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  if phase = 1 then
    if sort_direction = 'desc' then
      ordering := format(' order by opportunity.%1$I desc, opportunity.id desc', sort_key);
      keyset := case
        when cursor_id is null then ''
        when sort_key = 'estimated_value' then format(
          ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
        else format(
          ' and (opportunity.expected_close_on, opportunity.id) < (%1$L::date, %2$L::uuid)',
          cursor_date, cursor_id)
      end;
    else
      ordering := format(' order by opportunity.%1$I asc, opportunity.id asc', sort_key);
      keyset := case
        when cursor_id is null then ''
        when sort_key = 'estimated_value' then format(
          ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
        else format(
          ' and (opportunity.expected_close_on, opportunity.id) > (%1$L::date, %2$L::uuid)',
          cursor_date, cursor_id)
      end;
    end if;

    return query execute select_body || filters
      || format(' and opportunity.%I is not null', sort_key) || keyset || ordering
      || format(' limit %s', resolved_limit);
    get diagnostics fetched = row_count;

    -- The filled side is finished, so the rest of this page comes from the empty side, from its
    -- beginning. No card from that side can have been returned before this point, so there is nothing to
    -- page past.
    if fetched < resolved_limit then
      return query execute select_body || filters
        || format(' and opportunity.%I is null', sort_key)
        || ' order by opportunity.id asc'
        || format(' limit %s', resolved_limit - fetched);
    end if;
    return;
  end if;

  return query execute select_body || filters
    || format(' and opportunity.%I is null', sort_key)
    || case when cursor_id is null then ''
            else format(' and opportunity.id > %L::uuid', cursor_id) end
    || ' order by opportunity.id asc'
    || format(' limit %s', resolved_limit);
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_conversion_report(target_organization_id uuid, report_from timestamp with time zone DEFAULT NULL::timestamp with time zone, report_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_every_client boolean;
  request_totals jsonb;
  quote_totals jsonb;
  sources jsonb;
  stages jsonb;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Lead source is the client's own detail. The board blanks it on a card whose client the member may not
  -- see; a breakdown cannot be blanked row by row, so it is given only to a member who sees every client.
  caller_sees_every_client :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  -- Each piece of work created in the window, with its result read across the Request and its Quote.
  with work as (
    select
      card.request_id is not null as is_request,
      card.client_id,
      -- "Quoted" means a Quote that was not abandoned before sending.
      quote_card.id is not null
        and not (quote_card.outcome = 'open' and quote_card.stage = 'request_closed') as quoted,
      case
        when card.outcome = 'won' or quote_card.outcome = 'won' then 'won'
        when card.stage <> 'request_closed'
          or (quote_card.outcome = 'open' and quote_card.stage <> 'request_closed') then 'open'
        when card.outcome = 'lost' or quote_card.outcome = 'lost' then 'lost'
        else 'closed'
      end as result,
      case
        when card.outcome = 'won' then card.estimated_value
        when quote_card.outcome = 'won' then quote_card.estimated_value
      end as won_value
    from (select * from public.opportunities where client_deleted_at is null) as card
    left join (select * from public.quotes where client_deleted_at is null) as quote
      on quote.organization_id = card.organization_id
     and quote.request_id = card.request_id
    left join (select * from public.opportunities where client_deleted_at is null) as quote_card
      on quote_card.organization_id = quote.organization_id
     and quote_card.quote_id = quote.id
    where card.organization_id = target_organization_id
      and card.job_id is null
      and (
        card.request_id is not null
        -- A Quote with no Request behind it, unless it was abandoned before sending.
        or (card.quote_id is not null
            and not (card.outcome = 'open' and card.stage = 'request_closed')
            and not exists (
              select 1 from (select * from public.quotes where client_deleted_at is null) as own_quote
              where own_quote.organization_id = target_organization_id
                and own_quote.id = card.quote_id
                and own_quote.request_id is not null
            ))
      )
      and (report_from is null or card.created_at >= report_from)
      and (report_to is null or card.created_at < report_to)
  ),
  by_source as (
    select
      mode() within group (order by btrim(client.lead_source)) as lead_source,
      count(*) as total,
      count(*) filter (where work.result = 'won') as won,
      count(*) filter (where work.result = 'lost') as lost,
      count(*) filter (where work.result = 'closed') as closed,
      count(*) filter (where work.result = 'open') as still_open,
      sum(work.won_value) as won_value
    from work
    join public.clients as client
      on client.organization_id = target_organization_id and client.id = work.client_id
    where caller_sees_every_client
    group by lower(btrim(coalesce(client.lead_source, '')))
  )
  select
    (
      select jsonb_build_object(
        'total', count(*),
        'quoted', count(*) filter (where work.quoted),
        'won', count(*) filter (where work.result = 'won'),
        'lost', count(*) filter (where work.result = 'lost'),
        'closed', count(*) filter (where work.result = 'closed'),
        'open', count(*) filter (where work.result = 'open'),
        'open_unquoted', count(*) filter (where work.result = 'open' and not work.quoted)
      )
      from work
      where work.is_request
    ),
    (
      -- Free text, so the list is capped; the busiest sources are the ones worth reading.
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'lead_source', nullif(top.lead_source, ''),
          'total', top.total,
          'won', top.won,
          'lost', top.lost,
          'closed', top.closed,
          'open', top.still_open
        ) || case when caller_sees_money
               then jsonb_build_object('won_value', top.won_value) else '{}'::jsonb end
        order by top.total desc, top.lead_source), '[]'::jsonb)
      from (
        select * from by_source order by by_source.total desc, by_source.lead_source limit 50
      ) as top
    )
  into request_totals, sources;

  -- Per-Quote win rate: every Quote card created in the window, whether or not a Request came first.
  select jsonb_build_object(
    'total', count(*),
    'won', count(*) filter (where card.outcome = 'won'),
    'lost', count(*) filter (where card.outcome = 'lost'),
    'open', count(*) filter (where card.outcome = 'open' and card.stage <> 'request_closed'),
    'abandoned', count(*) filter (where card.outcome = 'open' and card.stage = 'request_closed')
  )
  into quote_totals
  from (select * from public.opportunities where client_deleted_at is null) as card
  where card.organization_id = target_organization_id
    and card.quote_id is not null
    and (report_from is null or card.created_at >= report_from)
    and (report_to is null or card.created_at < report_to);

  -- Time in stage. Each stage event is an arrival in a column: a custom stage when it names one, the
  -- built-in stage otherwise (ADR 0004: a row with equal stages is a custom move). The stay ends at the
  -- card's next arrival, or runs to now when the card is still there. A card that comes back to a stage
  -- adds to its own time there, so each card counts once per stage (HubSpot's cumulative time in stage).
  with arrivals as (
    select
      event.opportunity_id,
      event.to_stage,
      event.to_custom_stage_id,
      event.occurred_at,
      event.is_undo,
      lead(event.is_undo) over card_history as taken_back
    from public.opportunity_stage_events as event
    join (select * from public.opportunities where client_deleted_at is null) as card
      on card.organization_id = event.organization_id and card.id = event.opportunity_id
    where event.organization_id = target_organization_id
      and (report_from is null or card.created_at >= report_from)
      and (report_to is null or card.created_at < report_to)
    window card_history as (partition by event.opportunity_id order by event.occurred_at, event.id)
  ),
  stays as (
    select
      arrivals.opportunity_id,
      arrivals.to_stage,
      arrivals.to_custom_stage_id,
      arrivals.occurred_at,
      lead(arrivals.occurred_at) over (
        partition by arrivals.opportunity_id order by arrivals.occurred_at
      ) as left_at
    from arrivals
    -- An Undo and the move it took back never happened as far as a report is concerned.
    where not arrivals.is_undo and not coalesce(arrivals.taken_back, false)
  ),
  per_card as (
    select
      stays.to_stage,
      stays.to_custom_stage_id,
      sum(extract(epoch from (coalesce(stays.left_at, now()) - stays.occurred_at))) / 86400.0 as days,
      bool_or(stays.left_at is null) as still_there
    from stays
    where stays.to_stage <> 'request_closed'
    group by stays.opportunity_id, stays.to_stage, stays.to_custom_stage_id
  ),
  per_stage as (
    select
      case when per_card.to_custom_stage_id is null then per_card.to_stage end as stage,
      per_card.to_custom_stage_id as custom_stage_id,
      count(*) as cards,
      count(*) filter (where per_card.still_there) as still_there,
      percentile_cont(0.5) within group (order by per_card.days) as median_days,
      avg(per_card.days) as average_days
    from per_card
    group by 1, 2
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'stage', per_stage.stage,
      'custom_stage_id', per_stage.custom_stage_id,
      'name', custom.name,
      'section', custom.section,
      'after_stage', custom.after_stage,
      'position', custom.position,
      'disabled', custom.disabled_at is not null,
      'cards', per_stage.cards,
      'still_there', per_stage.still_there,
      'median_days', round(per_stage.median_days::numeric, 1),
      'average_days', round(per_stage.average_days::numeric, 1)
    )), '[]'::jsonb)
  into stages
  from per_stage
  left join public.pipeline_custom_stages as custom
    on custom.organization_id = target_organization_id and custom.id = per_stage.custom_stage_id;

  return jsonb_build_object(
    'requests', request_totals,
    'quotes', quote_totals,
    'sources', sources,
    'stages', stages,
    'can_view_sources', caller_sees_every_client,
    'can_view_value', caller_sees_money
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_custom_stage_card_count(target_organization_id uuid, target_stage_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  -- Asked by the Settings form, whose reader may hold no Pipeline permission of their own.
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  -- An index-only count through opportunities_custom_stage_idx: only placed cards are in it.
  return (
    select count(*)::integer
    from (select * from public.opportunities where client_deleted_at is null) as opportunity
    where opportunity.organization_id = target_organization_id
      and opportunity.custom_stage_id = target_stage_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_lead_sources(target_organization_id uuid)
 RETURNS TABLE(lead_source text, open_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  sees_every_client boolean;
begin
  -- The same rule the board page applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  sees_every_client :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  return query
    select
      mode() within group (order by btrim(client.lead_source)) as lead_source,
      count(*)::bigint as open_count
    from (select * from public.opportunities where client_deleted_at is null) as opportunity
    join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    -- Matches the partial board indexes: same tenant, same predicate.
    where opportunity.organization_id = target_organization_id
      and opportunity.outcome = 'open'
      and opportunity.board_column <> 'request_closed'
      and btrim(coalesce(client.lead_source, '')) <> ''
      and (sees_every_client
           or opportunity.client_id in (select private.current_user_assigned_client_ids()))
    group by lower(btrim(client.lead_source))
    order by 2 desc, 1
    limit 100;
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_outcome_page(target_organization_id uuid, outcome_type text, page_limit integer DEFAULT 25, sort_key text DEFAULT 'outcome_at'::text, sort_direction text DEFAULT 'desc'::text, outcome_from timestamp with time zone DEFAULT NULL::timestamp with time zone, outcome_to timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_sort_key text DEFAULT NULL::text, cursor_phase integer DEFAULT NULL::integer, cursor_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone, cursor_numeric numeric DEFAULT NULL::numeric, cursor_text text DEFAULT NULL::text, cursor_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, title text, outcome text, created_at timestamp with time zone, outcome_at timestamp with time zone, client_id uuid, client_display_name text, client_company_name text, estimated_value numeric, source_kind text, quote_id uuid, quote_number integer, lost_reason text, lost_note text, customer_declined boolean, customer_message text, customer_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  select_body text;
  filters text := '';
  keyset text;
  ordering text;
  sort_expr text;
  phase integer;
  fetched integer;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if outcome_type not in ('won', 'lost', 'direct_job') then
    raise exception 'That is not a Sales Outcomes type.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_key not in ('title', 'client', 'created', 'outcome_at', 'total')
     or sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a way to sort Sales Outcomes.' using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat rows.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  if sort_key = 'total' and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;
  if sort_key = 'client' and not caller_sees_clients then
    raise exception 'You do not have access to client names on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.outcome_at,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      case when %L::boolean then opportunity.estimated_value end,
      case
        when opportunity.job_id is not null then 'job'
        when opportunity.quote_id is not null then 'quote'
        else 'request'
      end,
      opportunity.quote_id,
      quote.quote_number,
      outcome_event.reason,
      outcome_event.note,
      -- The customer said no, as opposed to the team giving up on it. Their words stay beside the reason.
      opportunity.outcome = 'lost' and quote.decision is not distinct from 'declined',
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then quote.decision_note end,
      -- What they picked when they declined online. A decline staff recorded by phone has none.
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then customer_answer.customer_reason end
    from (select * from public.opportunities where client_deleted_at is null) as opportunity
    cross join lateral (
      select
        %L::boolean
        or opportunity.client_id in (select private.current_user_assigned_client_ids()) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join (select * from public.quotes where client_deleted_at is null) as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.quote_decisions as customer_answer
      on customer_answer.organization_id = quote.organization_id
     and customer_answer.quote_id = quote.id
     and customer_answer.is_current
    left join public.opportunity_outcome_events as outcome_event
      on outcome_event.id = opportunity.current_outcome_event_id
     and outcome_event.organization_id = opportunity.organization_id
     and outcome_event.event_type = 'lost'
    where opportunity.organization_id = %L
      and opportunity.outcome_kind = %L
  $body$, caller_sees_money, caller_sees_clients, target_organization_id, outcome_type);

  if outcome_from is not null then
    filters := filters || format(' and opportunity.outcome_at >= %L', outcome_from);
  end if;
  if outcome_to is not null then
    filters := filters || format(' and opportunity.outcome_at < %L', outcome_to);
  end if;

  -- Total pages in two phases, the same way the board's value sort does: a null estimate cannot sit in a
  -- keyset row comparison, so the estimated rows and the unestimated ones are two separate ordered reads
  -- rather than one NULLS LAST that a cursor could not resume.
  if sort_key = 'total' then
    phase := coalesce(cursor_phase, 1);
    if phase not in (1, 2) then
      raise exception 'That page marker belongs to a different order.'
        using errcode = 'invalid_parameter_value';
    end if;

    if phase = 1 then
      if sort_direction = 'desc' then
        ordering := ' order by opportunity.estimated_value desc, opportunity.id desc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      else
        ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      end if;

      return query execute select_body || filters
        || ' and opportunity.estimated_value is not null' || keyset || ordering
        || format(' limit %s', resolved_limit);
      get diagnostics fetched = row_count;

      if fetched < resolved_limit then
        return query execute select_body || filters
          || ' and opportunity.estimated_value is null'
          || ' order by opportunity.id asc'
          || format(' limit %s', resolved_limit - fetched);
      end if;
      return;
    end if;

    return query execute select_body || filters
      || ' and opportunity.estimated_value is null'
      || case when cursor_id is null then ''
              else format(' and opportunity.id > %L::uuid', cursor_id) end
      || ' order by opportunity.id asc'
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Every other sort is a single ordered read. Title, Created and Outcome date are never null; Client can
  -- be null only when the backing client row itself has been removed, which NULLS LAST is enough for --
  -- this is a report column, not money, and that edge is rare enough not to earn Total's two-phase split.
  sort_expr := case sort_key
    when 'title' then 'opportunity.title'
    when 'client' then 'client.display_name'
    when 'created' then 'opportunity.created_at'
    else 'opportunity.outcome_at'
  end;

  if sort_key in ('title', 'client') then
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc nulls last, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) < (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc nulls last, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) > (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    end if;
  else
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    end if;
  end if;

  return query execute select_body || filters || keyset || ordering
    || format(' limit %s', resolved_limit);
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_outcome_tiles(target_organization_id uuid, tile_from timestamp with time zone, tile_to timestamp with time zone)
 RETURNS TABLE(outcome_key text, closed_count bigint, value_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  -- Both outcome types are always returned, zero-filled, so a tile with nothing in the window still shows
  -- "Won (0)" instead of going missing.
  return query
  select
    outcome_type.outcome_key,
    coalesce(counted.closed_count, 0)::bigint,
    counted.value_total
  from unnest(array['won', 'lost']) as outcome_type(outcome_key)
  left join (
    select
      opportunity.outcome_kind as outcome_key,
      count(*) as closed_count,
      case when caller_sees_money then sum(opportunity.estimated_value) end as value_total
    from (select * from public.opportunities where client_deleted_at is null) as opportunity
    where opportunity.organization_id = target_organization_id
      -- Deals only. A Direct job is booked work that was never a card, so it is not in the board's tiles.
      and opportunity.outcome_kind in ('won', 'lost')
      and opportunity.outcome_at >= tile_from
      and opportunity.outcome_at < tile_to
    group by opportunity.outcome_kind
  ) as counted on counted.outcome_key = outcome_type.outcome_key;
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_outcomes_report(target_organization_id uuid, report_from timestamp with time zone DEFAULT NULL::timestamp with time zone, report_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  totals record;
  reasons jsonb;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  select
    count(*) filter (where o.outcome_kind = 'won') as won_count,
    count(*) filter (where o.outcome_kind = 'won' and o.estimated_value is null) as won_unvalued,
    sum(o.estimated_value) filter (where o.outcome_kind = 'won') as won_value,
    count(*) filter (where o.outcome_kind = 'lost') as lost_count,
    count(*) filter (where o.outcome_kind = 'lost' and o.estimated_value is null) as lost_unvalued,
    sum(o.estimated_value) filter (where o.outcome_kind = 'lost') as lost_value,
    count(*) filter (where o.outcome_kind = 'direct_job') as direct_count,
    count(*) filter (where o.outcome_kind = 'direct_job' and o.estimated_value is null) as direct_unvalued,
    sum(o.estimated_value) filter (where o.outcome_kind = 'direct_job') as direct_value,
    percentile_cont(0.5) within group (
      order by extract(epoch from (o.outcome_at - o.created_at)) / 86400.0
    ) filter (where o.outcome_kind = 'won') as median_days,
    avg(extract(epoch from (o.outcome_at - o.created_at)) / 86400.0)
      filter (where o.outcome_kind = 'won') as average_days
  into totals
  from (select * from public.opportunities where client_deleted_at is null) as o
  where o.organization_id = target_organization_id
    and o.outcome_kind in ('won', 'lost', 'direct_job')
    and (report_from is null or o.outcome_at >= report_from)
    and (report_to is null or o.outcome_at < report_to);

  -- Why Lost deals were lost. A customer's own decline is its own bucket (the Lost list shows it the same
  -- way); otherwise the staff reason on the current Lost event, with "no reason" kept as a bucket of its
  -- own so the breakdown always adds up to the Lost count.
  select coalesce(jsonb_agg(jsonb_build_object('reason', bucket.reason, 'count', bucket.reason_count)
    order by bucket.reason_count desc, bucket.reason nulls last), '[]'::jsonb)
  into reasons
  from (
    select
      case
        when quote.decision is not distinct from 'declined' then 'customer_declined'
        else lost_event.reason
      end as reason,
      count(*) as reason_count
    from (select * from public.opportunities where client_deleted_at is null) as o
    left join (select * from public.quotes where client_deleted_at is null) as quote
      on quote.id = o.quote_id and quote.organization_id = o.organization_id
    left join public.opportunity_outcome_events as lost_event
      on lost_event.id = o.current_outcome_event_id
     and lost_event.organization_id = o.organization_id
     and lost_event.event_type = 'lost'
    where o.organization_id = target_organization_id
      and o.outcome_kind = 'lost'
      and (report_from is null or o.outcome_at >= report_from)
      and (report_to is null or o.outcome_at < report_to)
    group by 1
  ) as bucket;

  return jsonb_build_object(
    'won', jsonb_build_object(
      'count', totals.won_count,
      'unvalued_count', totals.won_unvalued
    ) || case when caller_sees_money then jsonb_build_object('value_total', totals.won_value) else '{}'::jsonb end,
    'lost', jsonb_build_object(
      'count', totals.lost_count,
      'unvalued_count', totals.lost_unvalued
    ) || case when caller_sees_money then jsonb_build_object('value_total', totals.lost_value) else '{}'::jsonb end,
    'direct_job', jsonb_build_object(
      'count', totals.direct_count,
      'unvalued_count', totals.direct_unvalued
    ) || case when caller_sees_money then jsonb_build_object('value_total', totals.direct_value) else '{}'::jsonb end,
    'days_to_win', jsonb_build_object(
      'count', totals.won_count,
      'median', round(totals.median_days::numeric, 1),
      'average', round(totals.average_days::numeric, 1)
    ),
    'lost_reasons', reasons
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.pipeline_stage_counts(target_organization_id uuid, owner_filter text DEFAULT 'all'::text, filter_owner_user_id uuid DEFAULT NULL::uuid, created_from timestamp with time zone DEFAULT NULL::timestamp with time zone, created_to timestamp with time zone DEFAULT NULL::timestamp with time zone, search_like text DEFAULT NULL::text, search_digits text DEFAULT NULL::text, search_number bigint DEFAULT NULL::bigint, lead_source_filter text DEFAULT NULL::text)
 RETURNS TABLE(stage_key text, open_count bigint, value_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  filters text := '';
  record_filter text;
  joins text := '';
  counted text;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants, and the upper one is the first moment of the day after. The same two the
  -- columns are paging with, so the heading and the cards cannot drift apart.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  -- Search and lead source read the client, the property, and the quote, under the names the board page
  -- joins them by. Joined only when asked for.
  record_filter := private.pipeline_board_filter_clause(
    search_like, search_digits, search_number, lead_source_filter, target_organization_id);
  if record_filter <> '' then
    joins := format($joins$
    cross join lateral (
      select
        %L::boolean
        or opportunity.client_id in (select private.current_user_assigned_client_ids()) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join (select * from public.properties where client_deleted_at is null) as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join (select * from public.quotes where client_deleted_at is null) as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    $joins$, private.member_has_permission(target_organization_id, caller_id, 'customers.view'));
    filters := filters || record_filter;
  end if;

  counted := format($body$
    select
      opportunity.board_column as stage_key,
      count(*) as open_count,
      case when %L::boolean then sum(opportunity.estimated_value) end as value_total
    from (select * from public.opportunities where client_deleted_at is null) as opportunity
    %s
    -- Matches the partial board indexes exactly: same tenant, same predicate.
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
      and opportunity.board_column <> 'request_closed'
  $body$, caller_sees_money, joins, target_organization_id);

  -- Every column is listed — the seven protected stages and each custom stage that is switched on, by its
  -- id — so one that filtered down to nothing still reports zero and keeps its heading, instead of going
  -- missing from the board. A card counts under the column it is drawn in, never under both.
  return query execute format($head$
    select
      board_stage.stage_key,
      coalesce(counted.open_count, 0)::bigint,
      counted.value_total
    from (
      select unnest(array[
        'new_request',
        'assessment_unscheduled',
        'assessment_scheduled',
        'assessment_completed',
        'quote_draft',
        'quote_awaiting_response',
        'quote_changes_requested'
      ])
      union all
      select custom_stage.id::text
      from public.pipeline_custom_stages as custom_stage
      where custom_stage.organization_id = %L
        and custom_stage.disabled_at is null
    ) as board_stage(stage_key)
    left join (
  $head$, target_organization_id) || counted || filters || $tail$
      group by opportunity.board_column
    ) as counted on counted.stage_key = board_stage.stage_key
  $tail$;
end;
$function$;

CREATE OR REPLACE FUNCTION public.quote_access_link_state(target_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  quote_row public.quotes;
begin
  select * into quote_row from (select * from public.quotes where client_deleted_at is null) as quotes where id = target_quote_id;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.view'
     ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'quote_access_link_id', link.id,
          'quote_version_id', link.quote_version_id,
          'version_number', version.version_number,
          'recipient_name', recipient.display_name,
          'recipient_email', recipient.email,
          'issued_at', link.issued_at,
          'expires_at', link.expires_at,
          'first_viewed_at', link.first_viewed_at,
          'last_viewed_at', link.last_viewed_at,
          'view_count', link.view_count,
          'is_current_version', link.quote_version_id = quote_row.current_published_version_id
        )
        order by link.issued_at desc
      )
      from public.quote_access_links as link
      join public.quote_recipients as recipient on recipient.id = link.recipient_id
      join public.quote_versions as version on version.id = link.quote_version_id
      where link.organization_id = quote_row.organization_id
        and link.quote_id = quote_row.id
        and link.revoked_at is null
    ),
    '[]'::jsonb
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.quote_customer_preview(target_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  client_name text;
  client_email text;
  can_see_price boolean;
begin
  select * into quote_row from (select * from public.quotes where client_deleted_at is null) as quotes where id = target_quote_id;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.view'
     ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  select * into version_row
  from public.quote_versions
  where id = coalesce(quote_row.current_published_version_id, quote_row.draft_version_id);

  if version_row.id is null then
    return null;
  end if;

  can_see_price := private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view_price'
  );

  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = quote_row.organization_id
             and method.client_id = quote_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = quote_row.organization_id
    and client.id = quote_row.client_id;

  return jsonb_build_object(
    'document', private.quote_customer_document(
      quote_row,
      version_row,
      coalesce(nullif(trim(client_name), ''), client_email, 'Your client'),
      client_email,
      can_see_price
    ),
    'preview', jsonb_build_object(
      'version_status', version_row.status,
      'version_number', version_row.version_number,
      'is_current_published', coalesce(version_row.id = quote_row.current_published_version_id, false),
      'prices_withheld', not can_see_price
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.quote_list_activity(target_organization_id uuid, target_quote_ids uuid[])
 RETURNS TABLE(quote_id uuid, view_count integer, changes_requested_at timestamp with time zone, job_id uuid, job_number integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  can_see_jobs boolean;
begin
  if not private.member_has_permission(target_organization_id, caller, 'quotes.view') then
    raise exception 'You do not have access to these quotes.' using errcode = 'insufficient_privilege';
  end if;
  if target_quote_ids is null or cardinality(target_quote_ids) = 0 then
    return;
  end if;
  if cardinality(target_quote_ids) > 100 then
    raise exception 'Ask for at most 100 quotes at a time.' using errcode = 'check_violation';
  end if;
  -- A quote viewer who cannot open jobs is told the quote became a job, not which one.
  can_see_jobs := private.member_has_permission(target_organization_id, caller, 'jobs.view');

  return query
  select
    quote.id,
    -- Opens of what the client was last sent: the links issued for the current published version.
    coalesce((
      select sum(link.view_count)::integer
      from public.quote_access_links as link
      where link.organization_id = quote.organization_id
        and link.quote_id = quote.id
        and link.quote_version_id = quote.current_published_version_id
    ), 0),
    (
      select decision.decided_at
      from public.quote_decisions as decision
      where decision.organization_id = quote.organization_id
        and decision.quote_id = quote.id
        and decision.is_current
        and decision.outcome = 'changes_requested'
    ),
    case when can_see_jobs then job.id end,
    case when can_see_jobs then job.job_number end
  from (select * from public.quotes where client_deleted_at is null) as quote
  left join (select * from public.jobs where client_deleted_at is null) as job
    on job.organization_id = quote.organization_id and job.quote_id = quote.id
  where quote.organization_id = target_organization_id
    and quote.id = any(target_quote_ids);
end;
$function$;

CREATE OR REPLACE FUNCTION public.quote_list_overview(target_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  can_price boolean;
  today date;
  zone text;
  window_start timestamptz;
  prior_start timestamptz;
  open_money jsonb;
  open_count bigint;
  open_minor bigint;
  sent_count bigint;
  sent_minor bigint;
  converted_count bigint;
  converted_minor bigint;
  prior_sent bigint;
  prior_converted bigint;
  waiting_long bigint;
  not_opened bigint;
  follow_up_days integer[];
begin
  if not private.member_has_permission(target_organization_id, caller, 'quotes.view') then
    raise exception 'You do not have access to these quotes.' using errcode = 'insufficient_privilege';
  end if;
  can_price := private.member_has_permission(target_organization_id, caller, 'quotes.view_price');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  today := private.organization_today(target_organization_id);
  -- The past 30 days are the 30 calendar days ending today where the business is, counted from local
  -- midnight; the 30 before them are the comparison.
  window_start := ((today - 29)::timestamp at time zone zone);
  prior_start := ((today - 59)::timestamp at time zone zone);

  -- Money per open status, from the version each quote is working from (the draft while one is open, else
  -- the published one) -- the same figure the list's Total column shows, so a tile adds up to its rows.
  select
    coalesce(jsonb_object_agg(per_status.status, per_status.total_minor), '{}'::jsonb),
    coalesce(sum(per_status.quote_count), 0),
    coalesce(sum(per_status.total_minor), 0)
  into open_money, open_count, open_minor
  from (
    select quote.status, count(*) as quote_count, coalesce(sum(version.total_minor), 0)::bigint as total_minor
    from (select * from public.quotes where client_deleted_at is null) as quote
    left join public.quote_versions as version
      on version.organization_id = quote.organization_id
     and version.id = coalesce(quote.draft_version_id, quote.current_published_version_id)
    where quote.organization_id = target_organization_id
      and quote.status in ('draft', 'awaiting_response', 'changes_requested', 'approved')
    group by quote.status
  ) as per_status;

  -- Conversion: of the quotes first sent in a window, how many became a job. A cohort, so a quote sent this
  -- month and converted next month still counts for the month it was sent. Money is what the client was
  -- shown: the published version.
  select
    count(*) filter (where cohort.sent_at >= window_start),
    coalesce(sum(cohort.total_minor) filter (where cohort.sent_at >= window_start), 0),
    count(*) filter (where cohort.sent_at >= window_start and cohort.converted),
    coalesce(sum(cohort.total_minor) filter (where cohort.sent_at >= window_start and cohort.converted), 0),
    count(*) filter (where cohort.sent_at < window_start),
    count(*) filter (where cohort.sent_at < window_start and cohort.converted)
  into sent_count, sent_minor, converted_count, converted_minor, prior_sent, prior_converted
  from (
    select
      quote.sent_at,
      version.total_minor,
      exists (
        select 1 from (select * from public.jobs where client_deleted_at is null) as job
        where job.organization_id = quote.organization_id and job.quote_id = quote.id
      ) as converted
    from (select * from public.quotes where client_deleted_at is null) as quote
    left join public.quote_versions as version
      on version.organization_id = quote.organization_id
     and version.id = coalesce(quote.current_published_version_id, quote.draft_version_id)
    where quote.organization_id = target_organization_id
      and quote.sent_at is not null
      and quote.sent_at >= prior_start
      and quote.sent_at <= now()
  ) as cohort;

  -- The follow-up strip: quotes still waiting on the client.
  select
    count(*) filter (where quote.sent_at < now() - interval '7 days'),
    count(*) filter (where not exists (
      select 1 from public.quote_access_links as link
      where link.organization_id = quote.organization_id
        and link.quote_id = quote.id
        and link.quote_version_id = quote.current_published_version_id
        and link.view_count > 0
    ))
  into waiting_long, not_opened
  from (select * from public.quotes where client_deleted_at is null) as quote
  where quote.organization_id = target_organization_id
    and quote.status = 'awaiting_response';

  -- The days the active quote follow-up sends on: the running total of its waits before each email.
  -- The earliest-activated active recipe wins when there is more than one.
  select array_agg(sends.day order by sends.position) into follow_up_days
  from (
    select steps.position, steps.waited_days::integer as day, steps.step ->> 'type' as step_type
    from (
      select
        step.position,
        step.value as step,
        sum(case when step.value ->> 'type' = 'wait' then
          case step.value -> 'config' ->> 'unit'
            when 'days' then (step.value -> 'config' ->> 'amount')::numeric
            when 'hours' then (step.value -> 'config' ->> 'amount')::numeric / 24
            when 'minutes' then (step.value -> 'config' ->> 'amount')::numeric / 1440
            else 0 end
          else 0 end) over (order by step.position) as waited_days
      from (
        select version.definition
        from public.automation_recipes as recipe
        join public.automation_recipe_versions as version on version.id = recipe.current_version_id
        where recipe.organization_id = target_organization_id
          and recipe.status = 'active'
          and recipe.active_trigger_key = 'quote.delivery_succeeded'
        order by version.activated_at, recipe.id
        limit 1
      ) as active_recipe
      cross join lateral jsonb_array_elements(active_recipe.definition -> 'steps')
        with ordinality as step(value, position)
    ) as steps
    where steps.step ->> 'type' = 'action'
      and steps.step ->> 'key' in ('action.send_email', 'action.send_customer_message')
  ) as sends;

  return jsonb_build_object(
    'open_count', open_count,
    'open_minor', case when can_price then open_minor end,
    'status_minor', case when can_price then open_money end,
    'window_start', today - 29,
    'window_end', today,
    'sent_count', sent_count,
    'sent_minor', case when can_price then sent_minor end,
    'converted_count', converted_count,
    'converted_minor', case when can_price then converted_minor end,
    'rate_basis_points', case when sent_count > 0 then (converted_count * 10000 / sent_count) end,
    'prior_rate_basis_points', case when prior_sent > 0 then (prior_converted * 10000 / prior_sent) end,
    'waiting_over_7_days', waiting_long,
    'sent_not_opened', not_opened,
    'follow_up_days', case when follow_up_days is null then null else to_jsonb(follow_up_days) end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.quote_online_deposit_context(supplied_token_hash bytea)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  settings_row public.organization_settings;
  connection_row public.payment_stripe_connections;
  lifecycle text;
  satisfied boolean;
  unavailable text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  select * into quote_row from (select * from public.quotes where client_deleted_at is null) as quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  select organization.lifecycle_status into lifecycle
  from public.organizations as organization where organization.id = quote_row.organization_id;
  select * into settings_row
  from public.organization_settings where organization_id = quote_row.organization_id;
  select * into connection_row
  from public.payment_stripe_connections where organization_id = quote_row.organization_id;

  satisfied := exists (
    select 1 from public.quote_deposit_events received
    where received.organization_id = version_row.organization_id
      and received.quote_id = version_row.quote_id
      and received.quote_version_id = version_row.id
      and received.event_type = 'received'
      and not exists (
        select 1 from public.quote_deposit_events reversal
        where reversal.organization_id = received.organization_id
          and reversal.reversed_event_id = received.id
      )
  );

  unavailable := case
    when lifecycle is distinct from 'active' then 'business_unavailable'
    when connection_row.id is null then 'not_connected'
    when not settings_row.online_deposit_payments_enabled then 'turned_off'
    when quote_row.status <> 'approved' then 'not_approved'
    when version_row.deposit_type is null or version_row.deposit_required_minor <= 0 then 'no_deposit'
    when satisfied then 'already_paid'
  end;

  return jsonb_build_object(
    'organization_id', quote_row.organization_id,
    'quote_id', quote_row.id,
    'quote_version_id', version_row.id,
    'client_id', quote_row.client_id,
    'quote_number', quote_row.quote_number,
    'currency_code', version_row.currency_code,
    'available', unavailable is null,
    'unavailable_reason', unavailable,
    'deposit_required_minor', coalesce(version_row.deposit_required_minor, 0),
    'livemode', connection_row.livemode,
    'stripe_account_id', connection_row.stripe_account_id,
    'pay_by_app', jsonb_build_object(
      'venmo_username', settings_row.pay_by_app_venmo_username,
      'cash_app_cashtag', settings_row.pay_by_app_cash_app_cashtag,
      'paypal_me_username', settings_row.pay_by_app_paypal_me_username,
      'zelle_contact', settings_row.pay_by_app_zelle_contact,
      'e_transfer_email', settings_row.pay_by_app_e_transfer_email,
      'bank_transfer_instructions', settings_row.pay_by_app_bank_transfer_instructions
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.ready_to_bill_page(target_organization_id uuid, search_like text DEFAULT NULL::text, search_number bigint DEFAULT NULL::bigint, cursor_due_on date DEFAULT NULL::date, cursor_reminder_id uuid DEFAULT NULL::uuid, page_limit integer DEFAULT 25)
 RETURNS TABLE(job_id uuid, job_number integer, title text, job_type text, price_basis text, billing_timing text, currency_code text, oldest_due_on date, cursor_reminder uuid, due_reminder_count integer, unit_kind text, unit_count integer, uninvoiced_minor bigint, client_id uuid, client_display_name text, client_company_name text, property_label text, property_address_line1 text, property_city text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  caller uuid := (select auth.uid());
  today date;
begin
  if caller is null then
    raise exception 'You must be signed in to see what is ready to bill.'
      using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'invoices.create') then
    raise exception 'You do not have access to bill work here.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to job prices, so there is nothing to compare here.'
      using errcode = 'insufficient_privilege';
  end if;

  if page_limit is null or page_limit < 1 or page_limit > 50 then
    page_limit := 25;
  end if;
  today := private.organization_today(target_organization_id);

  return query
  with candidate as (
    select reminder.id as reminder_id, reminder.job_id, reminder.due_on
    from public.job_invoice_reminders as reminder
    where reminder.organization_id = target_organization_id
      and reminder.status = 'pending'
      and reminder.due_on <= today
      and (
        cursor_due_on is null or cursor_reminder_id is null
        or (reminder.due_on, reminder.id) > (cursor_due_on, cursor_reminder_id)
      )
      and not exists (
        select 1
        from public.job_invoice_reminders as earlier
        where earlier.organization_id = reminder.organization_id
          and earlier.job_id = reminder.job_id
          and earlier.status = 'pending'
          and earlier.due_on <= today
          and (earlier.due_on, earlier.id) < (reminder.due_on, reminder.id)
      )
      and (
        search_like is null
        or exists (
          select 1
          from (select * from public.jobs where client_deleted_at is null) as candidate_job
          left join public.clients as candidate_client
            on candidate_client.organization_id = candidate_job.organization_id
            and candidate_client.id = candidate_job.client_id
          where candidate_job.organization_id = reminder.organization_id
            and candidate_job.id = reminder.job_id
            and (
              candidate_job.title ilike search_like
              or candidate_client.display_name ilike search_like
              or candidate_client.company_name ilike search_like
              or (search_number is not null and candidate_job.job_number = search_number)
            )
        )
      )
    order by reminder.due_on, reminder.id
    limit page_limit
  )
  select
    job.id,
    job.job_number,
    job.title,
    job.job_type,
    job.price_basis,
    job.billing_timing,
    job.currency_code,
    candidate.due_on,
    candidate.reminder_id,
    (
      select count(*)::integer
      from public.job_invoice_reminders as counted
      where counted.organization_id = job.organization_id
        and counted.job_id = job.id
        and counted.status = 'pending'
        and counted.due_on <= today
    ),
    work.unit_kind,
    work.unit_count,
    work.uninvoiced_minor,
    job.client_id,
    client.display_name,
    client.company_name,
    property.label,
    property.address_line1,
    property.city
  from candidate
  join (select * from public.jobs where client_deleted_at is null) as job
    on job.organization_id = target_organization_id and job.id = candidate.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  left join (select * from public.properties where client_deleted_at is null) as property
    on property.organization_id = job.organization_id and property.id = job.property_id
  cross join lateral private.job_uninvoiced_work(
    job.organization_id, job.id, job.price_basis, job.subtotal_minor, job.total_minor, today
  ) as work
  order by candidate.due_on, candidate.reminder_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_quote_access_file(supplied_token_hash bytea, target_file_id uuid)
 RETURNS TABLE(object_key text, thumbnail_object_key text, mime_type text, display_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 or target_file_id is null then
    return;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null or link_row.revoked_at is not null then
    return;
  end if;

  if link_row.expires_at is not null and link_row.expires_at <= now() then
    return;
  end if;

  select * into quote_row from (select * from public.quotes where client_deleted_at is null) as quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return;
  end if;

  return query
  select file.object_key, file.thumbnail_object_key, file.mime_type, file.display_name
  from public.files as file
  where file.organization_id = version_row.organization_id
    and file.id = target_file_id
    and file.trashed_at is null
    and (
      exists (
        select 1 from public.quote_version_lines as line
        where line.organization_id = version_row.organization_id
          and line.quote_id = version_row.quote_id
          and line.quote_version_id = version_row.id
          and line.image_file_id = file.id
          and file.processing_state = 'available'
      )
      or exists (
        select 1 from public.quote_version_attachments as version_attachment
        where version_attachment.organization_id = version_row.organization_id
          and version_attachment.quote_id = version_row.quote_id
          and version_attachment.quote_version_id = version_row.id
          and version_attachment.file_id = file.id
          and version_attachment.customer_visible
      )
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_quote_access_link(supplied_token_hash bytea)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  recipient_row public.quote_recipients;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null or link_row.revoked_at is not null then
    return null;
  end if;

  if link_row.expires_at is not null and link_row.expires_at <= now() then
    return jsonb_build_object('expired', true);
  end if;

  select * into quote_row from (select * from public.quotes where client_deleted_at is null) as quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  select * into recipient_row from public.quote_recipients where id = link_row.recipient_id;

  return private.quote_customer_document(
    quote_row, version_row, recipient_row.display_name, recipient_row.email, true
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_quote_access_link_logo(supplied_token_hash bytea)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null or link_row.revoked_at is not null then
    return null;
  end if;

  if link_row.expires_at is not null and link_row.expires_at <= now() then
    return null;
  end if;

  select * into quote_row from (select * from public.quotes where client_deleted_at is null) as quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  return version_row.logo_object_key;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_request_counts(p_organization_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  since timestamptz := now() - interval '30 days';
  may_see_feedback boolean;
begin
  if not private.member_has_permission(p_organization_id, p_actor_id, 'reviews.view')
    or private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.view') is distinct from 'all' then
    return null;
  end if;

  may_see_feedback := private.member_has_permission(p_organization_id, p_actor_id, 'reviews.feedback')
    and private.member_permission_scope(p_organization_id, p_actor_id, 'reviews.feedback') = 'all';

  return (
    select jsonb_build_object(
      'asked', count(*) filter (where request.cancelled_at is null),
      'opened', count(*) filter (where request.first_opened_at is not null),
      'went_to_google', count(*) filter (where request.continued_to_google_at is not null),
      'private_feedback', count(*) filter (where request.feedback_submitted_at is not null),
      'new_feedback', case when may_see_feedback then (
        select count(*) from public.review_feedback as feedback
        where feedback.organization_id = p_organization_id and feedback.status = 'new'
      ) else null end
    )
    from (select * from public.review_requests where client_deleted_at is null) as request
    where request.organization_id = p_organization_id and request.created_at >= since
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.team_notification_links(p_organization_id uuid, p_subject_ids uuid[])
 RETURNS TABLE(subject_type text, subject_id uuid, request_id uuid, job_id uuid, client_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  select 'form_submission', s.id,
    nullif(s.result ->> 'request_id', '')::uuid,
    nullif(s.result ->> 'job_id', '')::uuid,
    nullif(s.result ->> 'client_id', '')::uuid
  from private.form_submissions as s
  where s.organization_id = p_organization_id and s.id = any (p_subject_ids)
  union all
  select 'website_chat_session', w.id, null, null, w.client_id
  from public.website_chat_sessions as w
  where w.organization_id = p_organization_id and w.id = any (p_subject_ids)
  union all
  select 'assessment', a.id, a.request_id, null, null
  from (select * from public.assessments where client_deleted_at is null) as a
  where a.organization_id = p_organization_id and a.id = any (p_subject_ids)
  union all
  select 'inbound_message', m.id, null, null, m.client_id
  from public.communication_inbound_messages as m
  where m.organization_id = p_organization_id and m.id = any (p_subject_ids);
$function$;

CREATE OR REPLACE FUNCTION public.timesheet_entries(target_organization_id uuid, target_user_id uuid, range_from date, range_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	caller uuid := (select auth.uid());
	page_size constant integer := 400;
	can_team boolean;
	can_own boolean;
	can_see_own boolean;
	can_write_own boolean;
	jobs_scope text;
	zone text;
	window_start timestamptz;
	window_end timestamptz;
	entries jsonb;
	entry_count integer;
begin
	if caller is null then
		raise exception 'You must be signed in to see Timesheets.' using errcode = 'insufficient_privilege';
	end if;
	can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
	can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');
	can_see_own := private.can_see_own_time(target_organization_id, caller);
	-- Someone limited to their own time cannot read a teammate's, and is told the same as for a stranger.
	if not (can_team or (can_see_own and target_user_id = caller)) then
		raise exception 'You do not have access to these hours.' using errcode = 'insufficient_privilege';
	end if;
	if range_from is null or range_to is null or range_to < range_from or range_to - range_from > 6 then
		raise exception 'Choose a day or a week.' using errcode = 'invalid_parameter_value';
	end if;

	-- The same rule the commands apply (private.assert_can_write_time), worked out once for the list.
	can_write_own := can_team or (can_own and target_user_id = caller);
	jobs_scope := private.member_permission_scope(target_organization_id, caller, 'jobs.view');
	zone := private.organization_timezone(target_organization_id);
	window_start := range_from::timestamp at time zone zone;
	window_end := (range_to + 1)::timestamp at time zone zone;

	-- Every hour of theirs is listed, so the totals add up. A Job or Request the reader may not open (a Field
	-- member no longer on it) is named by its number only, or as "Assessment", and is not a link.
	select
		coalesce(
			jsonb_agg(
				jsonb_build_object(
					'id', listed.entry_id,
					'kind', listed.kind,
					'is_running', listed.is_running,
					'approved', listed.approved,
					'source', listed.source,
					'started_at', listed.started_at,
					'ended_at', listed.ended_at,
					'started_on', (listed.started_at at time zone zone)::date,
					'minutes', listed.minutes,
					'notes', listed.notes,
					'overlaps', listed.overlaps,
					'long_running', listed.is_running and now() - listed.started_at > interval '12 hours',
					'over_a_day', listed.is_running and now() - listed.started_at > interval '24 hours',
					'job', case when listed.job_id is null then null else jsonb_build_object(
						'id', listed.job_id,
						'number', job.job_number,
						'visible', listed.job_visible,
						'closed', job.status <> 'active',
						'title', case when listed.job_visible then job.title end,
						'client_name', case when listed.job_visible then client.display_name end
					) end,
					'request', case when listed.request_id is null then null else jsonb_build_object(
						'id', listed.request_id,
						'visible', listed.request_visible,
						'title', case when listed.request_visible then request.title end
					) end,
					'visit_id', case when listed.job_visible then listed.visit_id end,
					'visit_date', case when listed.job_visible then visit.visit_date end,
					-- Running timers change only their start and notes, and are never deleted; a closed Job's
					-- hours are its manager's to change.
					-- Approved hours are locked for people limited to their own time (plan § Weekly approval).
					'can_edit', can_write_own and (can_team or not listed.approved) and (
						listed.job_id is null
						or (listed.job_visible and (can_team or listed.is_running or job.status = 'active'))
					),
					'can_delete', not listed.is_running and can_write_own and (can_team or not listed.approved) and (
						listed.job_id is null or (listed.job_visible and (can_team or job.status = 'active'))
					),
					'edited', exists (
						select 1
						from public.time_entry_history as history
						where history.organization_id = target_organization_id
							and history.entry_id = listed.entry_id
							and history.action = 'changed'
					)
				)
				order by listed.started_at, listed.entry_id
			),
			'[]'::jsonb
		),
		count(*)
	into entries, entry_count
	from (
		select hours.*,
			hours.job_id is not null and (
				jobs_scope = 'all'
				or (
					jobs_scope = 'assigned'
					and exists (
						select 1
						from public.job_visit_assignments as assignment
						where assignment.organization_id = target_organization_id
							and assignment.user_id = caller
							and assignment.job_id = hours.job_id
					)
				)
			) as job_visible,
			hours.request_id is not null
				and private.can_view_request(target_organization_id, hours.request_id) as request_visible
		from private.timesheet_rows(target_organization_id, window_start, window_end, target_user_id) as hours
		order by hours.started_at, hours.entry_id
		limit page_size
	) as listed
	left join (select * from public.jobs where client_deleted_at is null) as job
		on job.organization_id = target_organization_id and job.id = listed.job_id
	left join public.clients as client
		on client.organization_id = target_organization_id and client.id = job.client_id
	left join (select * from public.job_visits where client_deleted_at is null) as visit
		on visit.organization_id = target_organization_id and visit.id = listed.visit_id
	left join (select * from public.requests where client_deleted_at is null) as request
		on request.organization_id = target_organization_id and request.id = listed.request_id;

	return jsonb_build_object(
		'user_id', target_user_id,
		'from', range_from,
		'to', range_to,
		'timezone', zone,
		'server_now', now(),
		'entries', entries,
		-- A guard against a runaway week, not a page size: a real week is a few dozen entries.
		'truncated', entry_count >= page_size
	);
end;
$function$;

CREATE OR REPLACE FUNCTION public.timesheet_summary(target_organization_id uuid, anchor_date date DEFAULT NULL::date, span text DEFAULT 'week'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
	caller uuid := (select auth.uid());
	can_team boolean;
	can_own boolean;
	can_see_own boolean;
	zone text;
	today date;
	range_from date;
	range_to date;
	window_start timestamptz;
	window_end timestamptz;
	people jsonb;
begin
	if caller is null then
		raise exception 'You must be signed in to see Timesheets.' using errcode = 'insufficient_privilege';
	end if;
	can_team := private.member_has_permission(target_organization_id, caller, 'time.track_team');
	can_own := private.member_has_permission(target_organization_id, caller, 'time.track_own');
	can_see_own := private.can_see_own_time(target_organization_id, caller);
	if not (can_team or can_see_own) then
		raise exception 'You do not have access to Timesheets.' using errcode = 'insufficient_privilege';
	end if;
	if span is null or span not in ('day', 'week') then
		raise exception 'Choose a day or a week.' using errcode = 'invalid_parameter_value';
	end if;

	-- The window is the business's own day or week, so the page needs no time zone of its own to ask for
	-- "today". The week starts on Sunday, as the Schedule's does (plan § Timesheets page).
	zone := private.organization_timezone(target_organization_id);
	today := (now() at time zone zone)::date;
	range_from := coalesce(anchor_date, today);
	if span = 'week' then
		range_from := range_from - extract(dow from range_from)::integer;
	end if;
	range_to := case when span = 'week' then range_from + 6 else range_from end;
	window_start := range_from::timestamp at time zone zone;
	window_end := (range_to + 1)::timestamp at time zone zone;

	-- Who sees whom (plan § Timesheets page): someone limited to their own time sees only themselves.
	with visible as (
		select *
		from private.timesheet_rows(
			target_organization_id, window_start, window_end, case when can_team then null else caller end
		)
	),
	per_day as (
		select visible.user_id, (visible.started_at at time zone zone)::date as day, sum(visible.minutes) as minutes
		from visible
		where not visible.is_running
		group by visible.user_id, (visible.started_at at time zone zone)::date
	),
	per_person as (
		select visible.user_id,
			count(*) filter (where not visible.is_running) as entry_count,
			count(*) filter (where not visible.is_running and not visible.approved) as unapproved_count,
			coalesce(sum(visible.minutes) filter (where not visible.is_running), 0) as total_minutes,
			count(*) filter (where visible.overlaps) as overlap_count
		from visible
		group by visible.user_id
	),
	-- Everyone working here now who may time their work, and anyone else with hours in this window or a
	-- timer still running: a member who has left still appears for weeks they worked (plan § Timesheets
	-- page), and someone who cannot time their own work appears only when a manager recorded hours for them.
	roster as (
		select member.user_id, member.status, member.display_name_at_removal
		from public.organization_members as member
		where member.organization_id = target_organization_id
			and (can_team or member.user_id = caller)
			and (
				(member.status = 'active' and private.can_run_own_timer(target_organization_id, member.user_id))
				or exists (select 1 from per_person where per_person.user_id = member.user_id)
				or exists (
					select 1
					from public.running_timers as timer
					where timer.organization_id = target_organization_id and timer.user_id = member.user_id
				)
			)
	)
	select coalesce(
		jsonb_agg(
			jsonb_build_object(
				'user_id', roster.user_id,
				'name', coalesce(
					case when roster.status = 'removed' then roster.display_name_at_removal end,
					nullif(btrim(profile.full_name), ''),
					roster.display_name_at_removal,
					account.email
				),
				'avatar_url', case when roster.status <> 'removed' then profile.avatar_url end,
				'status', roster.status,
				'is_me', roster.user_id = caller,
				'days', coalesce(
					(
						select jsonb_object_agg(per_day.day::text, per_day.minutes)
						from per_day
						where per_day.user_id = roster.user_id
					),
					'{}'::jsonb
				),
				'total_minutes', coalesce(per_person.total_minutes, 0),
				'entry_count', coalesce(per_person.entry_count, 0),
				'unapproved_count', coalesce(per_person.unapproved_count, 0),
				'overlap_count', coalesce(per_person.overlap_count, 0),
				-- What they are on the clock for right now, whatever day it started.
				'running', (
					select jsonb_build_object(
						'id', timer.id,
						'kind', timer.kind,
						'job_id', timer.job_id,
						'job_number', job.job_number,
						'started_at', timer.started_at,
						'started_on', (timer.started_at at time zone zone)::date,
						'long_running', now() - timer.started_at > interval '12 hours',
						'over_a_day', now() - timer.started_at > interval '24 hours',
						-- Clocked in for the day: the day clock runs, or a visit timer will resume it.
						'clocked_in', timer.kind = 'general' or timer.resume_general
					)
					from public.running_timers as timer
					left join (select * from public.jobs where client_deleted_at is null) as job
						on job.organization_id = timer.organization_id and job.id = timer.job_id
					where timer.organization_id = target_organization_id and timer.user_id = roster.user_id
				)
			)
			order by roster.status = 'active' desc,
				lower(coalesce(
					case when roster.status = 'removed' then roster.display_name_at_removal end,
					nullif(btrim(profile.full_name), ''),
					roster.display_name_at_removal,
					account.email,
					''
				)),
				roster.user_id
		),
		'[]'::jsonb
	) into people
	from roster
	left join per_person on per_person.user_id = roster.user_id
	left join public.profiles as profile on profile.id = roster.user_id
	left join auth.users as account on account.id = roster.user_id;

	return jsonb_build_object(
		'span', span,
		'from', range_from,
		'to', range_to,
		'timezone', zone,
		'today', today,
		'server_now', now(),
		'can_view_team', can_team,
		-- Add entry: for anyone with time.track_team, for themselves with time.track_own.
		'can_add', can_team or can_own,
		-- Approve: only someone who manages the team's time.
		'can_approve', can_team,
		'people', people
	);
end;
$function$;
