-- Contractor Settings, Part 4B-2b: the availability/slot-computation engine.
--
-- 4B-2a gave assessment/job forms their booking rules (min notice, slot interval, visit duration, arrival
-- window, buffer, approval default) and the business its own location/service-area radius. This part answers
-- the question those rules exist to serve: "given this form and this date range, what times can a customer
-- actually pick?" -- and lays the primitive Part 4D's submission command needs to grab one of those times
-- without two customers ever landing on the same appointment. No screens yet (4B-2c) and nothing public reads
-- any of this yet (4C) -- this is the engine underneath both.
--
-- Two building blocks, deliberately kept separate:
--
--   1. A read: public.get_form_available_slots walks a bounded date window and returns the slots that are
--      genuinely open -- open per business hours, open per at least one real team member's own availability,
--      and clear of everything already on the calendar (assessments, job visits, whole-team schedule events),
--      with the form's buffer time padded around every one of them.
--
--   2. A write-time guard: private.form_booking_reservations is a new table whose only job is to make one
--      person double-booked from public submissions impossible, using the standard Postgres pattern for this
--      -- an EXCLUDE constraint over a time range (see PostgreSQL docs, "Exclusion Constraints") -- rather
--      than a check-then-insert race a bug or a retry could slip through. It is NOT a second copy of what's
--      booked; assessments/job_visits remain the source of truth for that. It exists purely so Part 4D's
--      submission command can attempt to claim {this person, this exact window} as one atomic step and get a
--      clean "someone just took that" instead of a race. Deliberately separate from the real calendar tables:
--      your own staff scheduling intentionally ALLOWS double-booking on purpose today (see
--      src/lib/schedule/conflicts.ts) -- this guard must never reach into that and start blocking it.
--
-- Launch-scope decision, same status as 4B-2a's radius/buffer departures: there is no "which staff can be
-- booked on this form" list yet, so every active member of the organization is a candidate resource. This
-- matches how staff assignment already works everywhere else in the app (TeamPicker has no role filter).
-- Recorded here so a later session knows it was a scope choice, not an oversight.

-- ---------------------------------------------------------------------------------------------------------
-- 1. The double-booking-safe reservation primitive
-- ---------------------------------------------------------------------------------------------------------

create extension if not exists btree_gist;

-- Lives in `private`, like the automation engine's internal tables -- nobody needs to read this directly, so
-- there is no RLS policy to get right; the schema itself is never granted to anon/authenticated.
create table private.form_booking_reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  form_id uuid not null,
  user_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_range tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  created_at timestamptz not null default now(),
  constraint form_booking_reservations_time_order check (ends_at > starts_at),
  constraint form_booking_reservations_form_fk foreign key (organization_id, form_id)
    references public.forms(organization_id, id) on delete cascade,
  constraint form_booking_reservations_member_fk foreign key (organization_id, user_id)
    references public.organization_members(organization_id, user_id) on delete cascade,
  -- The guarantee this whole part exists for: no two rows for the same person in the same organization may
  -- cover overlapping instants. A second insert that would overlap is refused by Postgres itself, not by
  -- application logic that a race could outrun.
  exclude using gist (
    organization_id with =,
    user_id with =,
    time_range with &&
  )
);

comment on table private.form_booking_reservations is
  'Write-time double-booking guard for public form submissions only. One row per person per booked window. '
  'Not the source of truth for what is booked -- assessments/job_visits are -- and never touched by internal '
  'staff scheduling, which intentionally allows double-booking. Part 4D owns inserting the real assessment/'
  'job_visit alongside a claimed row here in the same transaction; this part only lays the primitive.';

-- The one way anything ever writes here. Part 4D's submission command calls this from inside its own
-- transaction; a null return means someone else just claimed that exact person and window, which 4D should
-- read as "pick another slot", not as an error to surface raw.
create or replace function public.claim_form_booking_reservation(
  target_organization_id uuid,
  target_form_id uuid,
  target_user_id uuid,
  new_starts_at timestamptz,
  new_ends_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reservation_id uuid;
begin
  if new_starts_at is null or new_ends_at is null or new_ends_at <= new_starts_at then
    raise exception 'A reservation must end after it starts.' using errcode = 'check_violation';
  end if;

  begin
    insert into private.form_booking_reservations (
      organization_id, form_id, user_id, starts_at, ends_at
    ) values (
      target_organization_id, target_form_id, target_user_id, new_starts_at, new_ends_at
    )
    returning id into reservation_id;
  exception
    when exclusion_violation then
      return null;
  end;

  return reservation_id;
end;
$$;

comment on function public.claim_form_booking_reservation(uuid, uuid, uuid, timestamptz, timestamptz) is
  'Atomically claims {person, window}. Returns the new reservation id, or null if someone already holds an '
  'overlapping window for that person -- never raises for the ordinary "lost the race" case.';

-- Granted to service_role only, exactly like 4B-2a's geocoding claim/finalize functions were granted ahead of
-- their worker existing: nothing should be able to call this until Part 4D builds the real submission path
-- and decides how it authenticates.
revoke all on function public.claim_form_booking_reservation(uuid, uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.claim_form_booking_reservation(uuid, uuid, uuid, timestamptz, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 2. Helpers the slot-finding read is built from
-- ---------------------------------------------------------------------------------------------------------

-- The open windows for one calendar day, as naive local timestamps -- everything here (business hours,
-- job_visits, schedule_events, member availability) is already stored in the organization's own local wall
-- clock with no timezone attached, so slot math stays in that same local time throughout and only converts to
-- a real instant (timestamptz) at the very end, for the one field (assessments.starts_at) that needs it.
create or replace function private.form_booking_day_bands(
  target_organization_id uuid,
  target_hours_mode text,
  target_day date,
  target_weekday smallint
)
returns tsrange[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  bands tsrange[] := '{}';
  hours_row record;
  band_start timestamp;
  band_end timestamp;
begin
  -- "By appointment" means the business made a deliberate choice not to keep fixed hours -- the open window
  -- is the whole day, and member availability alone decides what is actually offered.
  if target_hours_mode = 'appointment_only' then
    return array[tsrange(target_day::timestamp, (target_day + 1)::timestamp, '[)')];
  end if;

  if target_hours_mode <> 'weekly' then
    return bands;
  end if;

  for hours_row in
    select *
    from public.organization_business_hours as hours
    where hours.organization_id = target_organization_id
      and hours.weekday = target_weekday
      and hours.is_open
    order by hours.period_index
  loop
    if hours_row.is_open_24h then
      band_start := target_day::timestamp;
      band_end := (target_day + 1)::timestamp;
    else
      band_start := target_day + hours_row.opens_at;
      -- A closing time at or before the opening time is the schema's way of saying the period runs past
      -- midnight (organization_business_hours_shape allows this on purpose -- see 20260822001257).
      band_end := case
        when hours_row.closes_at > hours_row.opens_at then target_day + hours_row.closes_at
        else (target_day + 1) + hours_row.closes_at
      end;
    end if;
    bands := bands || tsrange(band_start, band_end, '[)');
  end loop;

  return bands;
end;
$$;

comment on function private.form_booking_day_bands(uuid, text, date, smallint) is
  'The open local-time window(s) for one weekday under the organization''s confirmed hours mode. Business '
  'hours periods are pre-validated non-overlapping and ordered at save time, so they are trusted as given.';

revoke all on function private.form_booking_day_bands(uuid, text, date, smallint)
  from public, anon, authenticated;

-- Whether one person's own availability covers a candidate local-time window. Mirrors the same "unset means
-- nobody has said, not nine-to-five" and "an exception wins over the weekly row" rules the Schedule and the
-- Availability settings screen already use (organization_member_availability, 20260913140000).
create or replace function private.form_booking_member_is_available(
  target_organization_id uuid,
  target_user_id uuid,
  candidate_start timestamp,
  candidate_end timestamp
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  slot_day date := candidate_start::date;
  exception_row public.organization_member_availability_exceptions;
  weekly_row public.organization_member_availability;
begin
  -- Availability is only ever modelled as a same-day band -- there is no overnight shift concept, unlike
  -- business hours. A slot that crosses midnight (only reachable from an overnight business-hours period)
  -- cannot be honestly checked against a same-day pattern, so nobody is considered available for it.
  if candidate_end::date <> slot_day then
    return false;
  end if;

  select * into exception_row
  from public.organization_member_availability_exceptions as exception_table
  where exception_table.organization_id = target_organization_id
    and exception_table.user_id = target_user_id
    and exception_table.exception_date = slot_day;

  if found then
    if not exception_row.is_working then
      return false;
    end if;
    return candidate_start >= (slot_day + exception_row.starts_at)
      and candidate_end <= (slot_day + exception_row.ends_at);
  end if;

  select * into weekly_row
  from public.organization_member_availability as weekly_table
  where weekly_table.organization_id = target_organization_id
    and weekly_table.user_id = target_user_id
    and weekly_table.weekday = extract(dow from slot_day)::smallint;

  -- No row at all means nobody has set a pattern for this person, which the rest of the product already
  -- treats as "nothing to warn about" rather than a default nine-to-five -- so it places no restriction here.
  if not found then
    return true;
  end if;

  if not weekly_row.is_working then
    return false;
  end if;

  return candidate_start >= (slot_day + weekly_row.starts_at)
    and candidate_end <= (slot_day + weekly_row.ends_at);
end;
$$;

revoke all on function private.form_booking_member_is_available(uuid, uuid, timestamp, timestamp)
  from public, anon, authenticated;

-- A timed whole-team calendar block (a meeting, training) removes its own padded window from every member at
-- once. An anytime one is handled a level up, by skipping the whole day -- see get_form_available_slots.
create or replace function private.form_booking_slot_blocked_by_team_event(
  target_organization_id uuid,
  candidate_start timestamp,
  candidate_end timestamp,
  buffer_minutes integer
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.schedule_events as event
    where event.organization_id = target_organization_id
      and event.start_time is not null
      and (event.event_date + event.start_time) - make_interval(mins => buffer_minutes) < candidate_end
      and (event.event_date + coalesce(event.end_time, event.start_time))
        + make_interval(mins => buffer_minutes) > candidate_start
  );
$$;

revoke all on function private.form_booking_slot_blocked_by_team_event(uuid, timestamp, timestamp, integer)
  from public, anon, authenticated;

-- The first active member who is genuinely free for a candidate window: available by their own pattern, and
-- clear of every existing assessment/job-visit assignment once the form's buffer is padded around each one.
-- Returns that person's id (useful to Part 4D later) so the caller only has to check it is not null.
create or replace function private.form_booking_free_member_for_slot(
  target_organization_id uuid,
  candidate_start timestamp,
  candidate_end timestamp,
  buffer_minutes integer,
  target_timezone text
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  slot_buffer interval := make_interval(mins => buffer_minutes);
  padded_start timestamp := candidate_start - slot_buffer;
  padded_end timestamp := candidate_end + slot_buffer;
  member_id uuid;
begin
  for member_id in
    select membership.user_id
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.status = 'active'
    order by membership.user_id
  loop
    if not private.form_booking_member_is_available(
      target_organization_id, member_id, candidate_start, candidate_end
    ) then
      continue;
    end if;

    if exists (
      select 1
      from public.assessment_assignees as assignee
      join public.assessments as assessment on assessment.id = assignee.assessment_id
      where assignee.organization_id = target_organization_id
        and assignee.user_id = member_id
        and assessment.completed_at is null
        and assessment.starts_at is not null
        and (assessment.starts_at at time zone target_timezone) < padded_end
        and (assessment.ends_at at time zone target_timezone) > padded_start
    ) then
      continue;
    end if;

    if exists (
      select 1
      from public.job_visit_assignments as assignment
      join public.job_visits as visit on visit.id = assignment.visit_id
      where assignment.organization_id = target_organization_id
        and assignment.user_id = member_id
        and visit.completed_at is null
        and visit.start_time is not null
        and (visit.visit_date + visit.start_time) < padded_end
        and (visit.visit_date + coalesce(visit.end_time, visit.start_time)) > padded_start
    ) then
      continue;
    end if;

    return member_id;
  end loop;

  return null;
end;
$$;

revoke all on function private.form_booking_free_member_for_slot(uuid, timestamp, timestamp, integer, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 3. The read: given a form and a date window, which slots are actually open
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.get_form_available_slots(
  target_organization_id uuid,
  target_form_id uuid,
  range_start date,
  range_end date
)
returns table (
  slot_date date,
  start_time time,
  end_time time,
  starts_at timestamptz,
  ends_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  rules public.form_booking_rules;
  org_timezone text;
  hours_mode text;
  earliest_allowed timestamp;
  visit_duration interval;
  slot_interval interval;
  current_day date;
  current_weekday smallint;
  day_bands tsrange[];
  band tsrange;
  band_start timestamp;
  band_end timestamp;
  candidate_start timestamp;
  candidate_end timestamp;
  free_member uuid;
  max_range_days constant integer := 60;
  max_rows constant integer := 2000;
  returned_rows integer := 0;
begin
  if not private.has_permission(target_organization_id, 'settings.forms.manage') then
    raise exception 'You do not have access to view booking availability.'
      using errcode = 'insufficient_privilege';
  end if;

  if range_start is null or range_end is null or range_end < range_start then
    raise exception 'Give a valid date range.' using errcode = 'check_violation';
  end if;
  if range_end - range_start > max_range_days then
    raise exception 'Ask for at most % days at a time.', max_range_days using errcode = 'check_violation';
  end if;

  select * into rules
  from public.form_booking_rules
  where form_id = target_form_id and organization_id = target_organization_id;

  if rules.form_id is null then
    raise exception 'This form has no booking rules.' using errcode = 'check_violation';
  end if;

  select settings.timezone, settings.hours_mode into org_timezone, hours_mode
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;

  -- 'not_configured' is honestly "nobody has said" -- the same rule the rest of Settings uses -- not a
  -- licence to guess business hours, so nothing is offered until the business confirms weekly hours or
  -- says it works strictly by appointment.
  if hours_mode is null or hours_mode = 'not_configured' then
    return;
  end if;

  earliest_allowed := (now() + make_interval(mins => rules.min_notice_minutes)) at time zone org_timezone;
  visit_duration := make_interval(mins => rules.visit_duration_minutes);
  slot_interval := make_interval(mins => rules.slot_interval_minutes);

  current_day := range_start;
  while current_day <= range_end loop
    -- An anytime team event promises the whole day to the team (see schedule_events, 20260903130000), so the
    -- day offers nothing at all rather than being picked apart around it.
    if exists (
      select 1 from public.schedule_events as event
      where event.organization_id = target_organization_id
        and event.event_date = current_day
        and event.start_time is null
    ) then
      current_day := current_day + 1;
      continue;
    end if;

    current_weekday := extract(dow from current_day)::smallint;
    day_bands := private.form_booking_day_bands(
      target_organization_id, hours_mode, current_day, current_weekday
    );

    foreach band in array day_bands loop
      band_start := lower(band);
      band_end := upper(band);
      candidate_start := band_start;

      while candidate_start + visit_duration <= band_end loop
        candidate_end := candidate_start + visit_duration;

        if candidate_start >= earliest_allowed
          and not private.form_booking_slot_blocked_by_team_event(
            target_organization_id, candidate_start, candidate_end, rules.buffer_minutes
          )
        then
          free_member := private.form_booking_free_member_for_slot(
            target_organization_id, candidate_start, candidate_end, rules.buffer_minutes, org_timezone
          );

          if free_member is not null then
            slot_date := candidate_start::date;
            start_time := candidate_start::time;
            end_time := candidate_end::time;
            starts_at := candidate_start at time zone org_timezone;
            ends_at := candidate_end at time zone org_timezone;
            return next;

            returned_rows := returned_rows + 1;
            if returned_rows >= max_rows then
              return;
            end if;
          end if;
        end if;

        candidate_start := candidate_start + slot_interval;
      end loop;
    end loop;

    current_day := current_day + 1;
  end loop;

  return;
end;
$$;

comment on function public.get_form_available_slots(uuid, uuid, date, date) is
  'Every bookable slot for one form across a date window (capped at 60 days), honoring business hours, each '
  'member''s own availability, the form''s min notice/slot interval/visit duration/buffer, and everything '
  'already on the calendar. Staff-only for now (settings.forms.manage) -- Part 4C adds the public-safe path.';

revoke all on function public.get_form_available_slots(uuid, uuid, date, date) from public;
revoke execute on function public.get_form_available_slots(uuid, uuid, date, date) from anon;
grant execute on function public.get_form_available_slots(uuid, uuid, date, date) to authenticated;
