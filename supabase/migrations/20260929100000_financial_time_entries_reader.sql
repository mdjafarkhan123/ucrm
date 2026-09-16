-- CRM launch readiness, financial reconciliation Part 2: time entries reader.
--
-- One row per recorded time entry whose start instant falls inside the report range, so an accountant can
-- trace every labor minute and every unit of rated labor cost on the Job profitability report back to the
-- hour it came from. Labor is dated by started_at against the range's timezone-resolved instants, exactly as
-- financial_job_profitability_rows dates it, so the two reports cannot disagree about which hours belong to
-- a month. Unrated hours (no rate on file when recorded) are flagged per row and totalled separately; they
-- stay out of the cost total rather than being valued at zero.
--
-- Who sees which rows is the time-entry table's own select policy, restated here because these functions
-- are definer and the policy no longer stands between the reader and the rows. Three gates, all resolved
-- once for the caller, never per row:
--
--   jobs.view         -- required to read anything; an 'assigned'-scope member (the Field role) only
--                        reaches entries on Jobs they are assigned to, through the same
--                        job_visit_assignments probe private.is_assigned_to_job makes.
--   time.track_team   -- everyone's hours. Without it, time.track_own reaches the caller's own hours only,
--                        and neither means no rows and no report.
--   jobs.view_cost    -- the rate and the money. Without it those columns are null, never zero; the route
--                        drops them entirely. Minutes and identity never depend on it.
--
-- The scope predicate is spelled out in both functions rather than shared through a helper: a helper
-- carrying `set search_path` cannot be inlined, which would force the page to materialize the whole range
-- before the keyset and limit could apply. Exports must not widen that scope, so the summary counts exactly
-- the rows the page would show this caller: a crew member's total is their own total. Every read is
-- explicitly organization scoped.

-- 1. The paged ledger ------------------------------------------------------------------------------------

-- Keyset on (started_at, id): id is unique, so the pair is a complete marker. The whole-organization range
-- walks job_time_entries_started_idx (below); a crew member's own-hours range walks the existing member index.
create or replace function public.financial_time_entries_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_started_at timestamptz default null,
  cursor_entry_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  entry_id uuid,
  started_at timestamptz,
  started_on date,
  minutes integer,
  user_id uuid,
  user_name text,
  job_id uuid,
  job_number integer,
  job_title text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  visit_id uuid,
  visit_date date,
  currency_code text,
  is_unrated boolean,
  cost_per_hour_minor bigint,
  cost_total_minor bigint
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
  join public.jobs as job
    on job.organization_id = entry.organization_id and job.id = entry.job_id
  left join public.clients as client
    on client.organization_id = job.organization_id and client.id = job.client_id
  left join public.profiles as profile
    on profile.id = entry.user_id
  left join public.job_visits as visit
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
$$;

-- 2. The whole-range totals ------------------------------------------------------------------------------

create or replace function public.financial_time_entries_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  entry_count bigint,
  member_count bigint,
  job_count bigint,
  minutes bigint,
  rated_minutes bigint,
  unrated_count bigint,
  unrated_minutes bigint,
  cost_total_minor bigint
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
  can_view_cost boolean;
  assigned_only boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
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

  can_view_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');
  assigned_only := private.member_permission_scope(target_organization_id, caller, 'jobs.view') = 'assigned';

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  return query
  select count(*)::bigint,
    count(distinct entry.user_id)::bigint,
    count(distinct entry.job_id)::bigint,
    coalesce(sum(entry.minutes), 0)::bigint,
    coalesce(sum(entry.minutes) filter (where entry.cost_per_hour_minor is not null), 0)::bigint,
    count(*) filter (where entry.cost_per_hour_minor is null),
    coalesce(sum(entry.minutes) filter (where entry.cost_per_hour_minor is null), 0)::bigint,
    case when can_view_cost then coalesce(sum(entry.cost_total_minor), 0)::bigint end
  from public.job_time_entries as entry
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
    );
end;
$$;

comment on function public.financial_time_entries_page(uuid, date, date, timestamptz, uuid, integer, text) is
  'Keyset-paged time entries ledger for a report range, dated by started_at in the organization timezone as '
  'Job profitability dates labor. Requires jobs.view plus time.track_team (everyone''s hours) or '
  'time.track_own (own hours only); an assigned-scope member sees only assigned Jobs. Rate and cost are null '
  'without jobs.view_cost. Every row is explicitly organization scoped.';
comment on function public.financial_time_entries_summary(uuid, date, date) is
  'Whole-range entry, member and Job counts, minutes, unrated disclosure and rated cost over exactly the '
  'rows financial_time_entries_page would show this caller. Never wider than the caller''s own/team scope.';

revoke all on function public.financial_time_entries_page(uuid, date, date, timestamptz, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_time_entries_page(uuid, date, date, timestamptz, uuid, integer, text)
  to authenticated;
revoke all on function public.financial_time_entries_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_time_entries_summary(uuid, date, date) to authenticated;

-- 3. The range index ---------------------------------------------------------------------------------------

-- The two existing indexes prefix on job_id and user_id; a team-scope range over the whole organization had
-- nothing to walk but the table. This is the keyset order itself, so a page is one ordered range scan.
create index if not exists job_time_entries_started_idx
  on public.job_time_entries(organization_id, started_at, id);

notify pgrst, 'reload schema';
