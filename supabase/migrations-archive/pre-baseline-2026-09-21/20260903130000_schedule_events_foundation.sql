-- Schedule Part 6a-2: Schedule-owned lightweight Events.
--
-- Events are the first calendar object Schedule OWNS. Visits belong to Jobs and Assessments to Requests --
-- Schedule only shows and dispatches those. An Event is a non-client calendar block (a team meeting, a
-- training morning, a holiday) that Schedule creates, edits and deletes for itself.
--
-- Deliberately lightweight, matching the approved behavior contract and the live Jobber tour (2026-09-03):
--   * a single-day block, timed OR anytime, for the whole team;
--   * a required title and an optional description;
--   * NO assignment, privacy, client/property, address, recurrence or completion -- those are later scope.
-- Multi-day is out: Jobber renders a multi-day event as a heavy day-spanning block, and single-day covers
-- every case this part promises. So event_date is NOT NULL -- an Event is always on a day and never enters
-- the Unscheduled backlog, which is the contract's "Events never enter the backlog" guarantee made structural.
--
-- Time is modelled exactly like a job_visit -- a plain date plus optional clock times -- not like an
-- assessment's UTC instants. Schedule owns this table, so it chooses the simpler day-anchored shape the grid
-- already thinks in, and the window read filters by a plain date range with no timezone padding.
--
-- Permission: create/edit/delete are gated on jobs.schedule (the existing calendar-change authority) in the
-- API layer, exactly as visit moves are. RLS here enforces tenant membership -- the same division assessments
-- use. Any member holding the calendar-change authority may edit or delete any event; that is UCRM's chosen
-- role-based policy, not a creator-only lock.

create table public.schedule_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  description text,
  -- A single-day block. A date with no start_time is the anytime shape; a date with a start_time is timed.
  event_date date not null,
  start_time time,
  end_time time,
  -- Jobber's "Anytime": the day is promised for the whole team, the hour is not.
  all_day boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_events_title_length check (char_length(trim(title)) between 1 and 160),
  constraint schedule_events_description_length
    check (description is null or char_length(description) <= 2000),
  -- An end without a start is meaningless, and an end that is not after the start is a typo, not an event.
  constraint schedule_events_time_order check (
    end_time is null or (start_time is not null and end_time > start_time)
  ),
  -- Anytime is a day with no clock time, so it carries neither a start nor an end.
  constraint schedule_events_all_day_no_time check (
    not all_day or (start_time is null and end_time is null)
  )
);

comment on table public.schedule_events is
  'A Schedule-owned lightweight calendar block (team meeting, holiday, training). Single-day, timed or '
  'anytime, whole-team. No client, assignment, recurrence or completion. Members read it; only a holder of '
  'the jobs.schedule authority writes it.';

-- The Schedule's bounded date-window read walks the organization by date, the same access path job_visits
-- uses, so a window's events are found without scanning the tenant.
create index schedule_events_calendar_idx
  on public.schedule_events(organization_id, event_date);

create trigger schedule_events_set_updated_at
before update on public.schedule_events
for each row execute function public.set_updated_at();

alter table public.schedule_events enable row level security;

create policy "members can view schedule events"
on public.schedule_events for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can create schedule events"
on public.schedule_events for insert to authenticated
with check (private.is_organization_member(organization_id));

create policy "members can update schedule events"
on public.schedule_events for update to authenticated
using (private.is_organization_member(organization_id))
with check (private.is_organization_member(organization_id));

create policy "members can delete schedule events"
on public.schedule_events for delete to authenticated
using (private.is_organization_member(organization_id));

grant select, insert, update, delete on public.schedule_events to authenticated;
