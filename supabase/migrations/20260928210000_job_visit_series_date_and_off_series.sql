-- A visit a recurring job generated now remembers the date its repeat rule gave it (`series_date`, the same
-- idea as a calendar's RECURRENCE-ID), and carries a stored `off_series` flag that says whether it has since
-- been taken off that rule: moved to another day, unscheduled, or given a different time than the rule's.
-- One trigger keeps the flag true to every path that reschedules a visit — editing it alone, dragging it on
-- the Schedule, a bulk move, or copying one visit's time forward — so no command has to remember to set it.
-- The flag is frozen once the visit is completed (a completed visit cannot be rescheduled), so it stays an
-- honest record even after the job's rule is later replaced. Rebuilding a schedule deletes and regenerates
-- every incomplete visit, which starts them back on the rule.

alter table public.job_visits
  add column series_date date,
  add column off_series boolean not null default false;

comment on column public.job_visits.series_date is
  'For a visit the repeat rule generated: the date the rule gave it. Null for manual, return and duplicated visits, and for older generated visits whose original date could not be recovered.';
comment on column public.job_visits.off_series is
  'True when a generated visit no longer follows its repeat rule: a date other than series_date, no date, or a time that differs from the rule''s. Kept by job_visits_track_series.';

create or replace function private.job_visits_track_series()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  rule public.job_recurrence_rules;
begin
  if new.source is distinct from 'generated' then
    new.series_date := null;
    new.off_series := false;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.series_date := coalesce(new.series_date, new.visit_date);
  end if;

  select * into rule
  from public.job_recurrence_rules
  where job_id = new.job_id;

  new.off_series := new.series_date is null
    or new.visit_date is distinct from new.series_date
    or (
      rule.job_id is not null
      and (
        new.all_day is distinct from rule.all_day
        or new.start_time is distinct from rule.start_time
        or new.end_time is distinct from rule.end_time
      )
    );
  return new;
end;
$$;

comment on function private.job_visits_track_series() is
  'Stamps a generated visit''s series_date on insert and recomputes off_series whenever its date or time changes, against the job''s repeat rule.';

revoke all on function private.job_visits_track_series() from public;

create trigger job_visits_track_series_insert
  before insert on public.job_visits
  for each row execute function private.job_visits_track_series();

create trigger job_visits_track_series_update
  before update of visit_date, start_time, end_time, all_day, source on public.job_visits
  for each row execute function private.job_visits_track_series();

-- Backfill. An incomplete generated visit whose date is still one of its rule's dates is taken to be that
-- date's visit; one on a date the rule never produces has lost its original date, so it is marked off series
-- with no series_date. Completed visits are history: their rule may have been replaced since, so they are
-- taken as they stand rather than measured against a rule they were never generated from. The backfill is
-- not an edit, so it leaves updated_at alone.
alter table public.job_visits disable trigger job_visits_set_updated_at;
alter table public.job_visits disable trigger job_visits_track_series_update;

update public.job_visits as visit
set series_date = visit.visit_date
where visit.source = 'generated'
  and (
    visit.completed_at is not null
    or not exists (select 1 from public.job_recurrence_rules as rule where rule.job_id = visit.job_id)
  );

with rule_dates as (
  select rule.job_id, day
  from public.job_recurrence_rules as rule
  cross join lateral private.job_recurrence_dates(
    rule.frequency, rule.interval_count, rule.weekdays, rule.monthly_mode, rule.month_day,
    rule.ordinal_week, rule.ordinal_weekday, rule.start_date, rule.end_date
  ) as day
)
update public.job_visits as visit
set series_date = case
      when exists (
        select 1 from rule_dates
        where rule_dates.job_id = visit.job_id and rule_dates.day = visit.visit_date
      ) then visit.visit_date
    end,
    off_series = not exists (
        select 1 from rule_dates
        where rule_dates.job_id = visit.job_id and rule_dates.day = visit.visit_date
      )
      or (
        rule.all_day is distinct from visit.all_day
        or rule.start_time is distinct from visit.start_time
        or rule.end_time is distinct from visit.end_time
      )
from public.job_recurrence_rules as rule
where rule.job_id = visit.job_id
  and visit.source = 'generated'
  and visit.completed_at is null;

alter table public.job_visits enable trigger job_visits_track_series_update;
alter table public.job_visits enable trigger job_visits_set_updated_at;
