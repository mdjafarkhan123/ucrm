-- Client reminders Part 3: visit and assessment reminders.
--
-- Product truth: docs/client-reminders-behavior-contract.md § Visit and assessment reminders and § Customer
-- messages: shared rules. Following Jobber's Assessment and Visit Reminders, the reminder time is worked out from
-- the visit's current date and time when it falls due, not fixed at booking, so moving a visit moves its reminder
-- and a cancelled visit simply never comes due.
--
-- 1. A new automation trigger, appointment.reminder_due (subject types job_visit and assessment, source
--    'scheduling'). Its config holds the timing: { mode: 'before', amount, unit: hours|days } or
--    { mode: 'fixed_time', days_before, time }. A visit with no set time is reminded at 9 am, at least a day before.
-- 2. job_visits.schedule_set_at and assessments.schedule_set_at record when the date or time was last set, so a
--    visit booked after its reminder time had already passed gets no reminder.
-- 3. emit_due_appointment_reminders runs at the start of every automation worker wake (each minute): for each
--    active recipe on the trigger it emits one event per visit whose reminder time has arrived, while the visit is
--    still ahead, and only when that time came after both the booking and the recipe's activation. The event's
--    source id is derived from the recipe and the visit, so a visit is reminded at most once per recipe.
-- 4. Intake enrolls a due visit only into the recipe that found it; a client whose "Upcoming assessment and visit
--    reminders" switch is off is recorded as declined. Advance stops when the visit is gone, completed, its job
--    closed or request archived, its start passed, or the client was removed, switched reminders off or is on
--    Do not disturb.
-- 5. A new action, action.send_appointment_email, sends through the Communications outbox like the other
--    automation emails, with the visit's own variables.

-- 1. Constraints ---------------------------------------------------------------------------------------------

alter table private.automation_events
  drop constraint automation_events_event_type_check,
  add constraint automation_events_event_type_check check (event_type = any (array[
    'quote.delivery_succeeded', 'website_inquiry.received', 'job.work_completed', 'appointment.reminder_due'])),
  drop constraint automation_events_subject_type_check,
  add constraint automation_events_subject_type_check check (subject_type = any (array[
    'quote', 'form_submission', 'website_chat_session', 'job', 'job_visit', 'assessment'])),
  drop constraint automation_events_source_module_check,
  add constraint automation_events_source_module_check check (source_module = any (array[
    'communications', 'forms', 'website_chat', 'jobs', 'scheduling']));

alter table private.automation_enrollments
  drop constraint automation_enrollments_subject_type_check,
  add constraint automation_enrollments_subject_type_check check (subject_type = any (array[
    'quote', 'form_submission', 'website_chat_session', 'job', 'job_visit', 'assessment']));

-- 2. When a visit was booked ---------------------------------------------------------------------------------

alter table public.job_visits add column schedule_set_at timestamptz;
alter table public.assessments add column schedule_set_at timestamptz;

-- Existing bookings count from when they were created; that only matters for a recipe already active, and none is.
update public.job_visits set schedule_set_at = created_at where visit_date is not null;
update public.assessments set schedule_set_at = created_at where starts_at is not null;

create or replace function private.job_visits_track_schedule_set()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.visit_date is null then
    new.schedule_set_at := null;
  elsif tg_op = 'INSERT'
    or (old.visit_date, old.start_time, old.all_day) is distinct from (new.visit_date, new.start_time, new.all_day) then
    new.schedule_set_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.job_visits_track_schedule_set() from public, anon, authenticated;

create trigger job_visits_track_schedule_set
  before insert or update of visit_date, start_time, all_day on public.job_visits
  for each row execute function private.job_visits_track_schedule_set();

create or replace function private.assessments_track_schedule_set()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.starts_at is null then
    new.schedule_set_at := null;
  elsif tg_op = 'INSERT'
    or (old.starts_at, old.all_day) is distinct from (new.starts_at, new.all_day) then
    new.schedule_set_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.assessments_track_schedule_set() from public, anon, authenticated;

create trigger assessments_track_schedule_set
  before insert or update of starts_at, all_day on public.assessments
  for each row execute function private.assessments_track_schedule_set();

-- 3. Appointment helpers -------------------------------------------------------------------------------------

create or replace function private.appointment_timezone(p_organization_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (select nullif(btrim(settings.timezone), '') from public.organization_settings as settings
      where settings.organization_id = p_organization_id),
    'UTC');
$$;

revoke all on function private.appointment_timezone(uuid) from public, anon, authenticated;

-- When the visit starts; a visit with no set time counts from the start of its day.
create or replace function private.appointment_starts_at(p_date date, p_time time, p_timezone text)
returns timestamptz
language sql
stable
set search_path = pg_catalog
as $$
  select (p_date + coalesce(p_time, time '00:00')) at time zone p_timezone;
$$;

revoke all on function private.appointment_starts_at(date, time, text) from public, anon, authenticated;

-- When a visit on this local date and time should be reminded, from the trigger's timing config. Days land on the
-- same local time of day (a Thursday 7 am visit, 1 day before, is Wednesday 7 am); hours are real elapsed time.
create or replace function private.appointment_reminder_at(
  p_config jsonb, p_date date, p_time time, p_timezone text
)
returns timestamptz
language plpgsql
stable
set search_path = pg_catalog
as $$
declare
  amount integer;
  unit text;
  days_before integer;
begin
  if p_date is null then
    return null;
  end if;

  if p_config ->> 'mode' = 'fixed_time' then
    days_before := (p_config ->> 'days_before')::integer;
    return ((p_date - days_before) + (p_config ->> 'time')::time) at time zone p_timezone;
  end if;

  amount := (p_config ->> 'amount')::integer;
  unit := p_config ->> 'unit';

  -- No set time: 9 am, on the day the reminder falls, and never on the visit's own day.
  if p_time is null then
    days_before := greatest(1, case when unit = 'days' then amount else ceil(amount / 24.0)::integer end);
    return ((p_date - days_before) + time '09:00') at time zone p_timezone;
  end if;

  if unit = 'days' then
    return ((p_date + p_time) - make_interval(days => amount)) at time zone p_timezone;
  end if;
  return ((p_date + p_time) at time zone p_timezone) - make_interval(hours => amount);
end;
$$;

revoke all on function private.appointment_reminder_at(jsonb, date, time, text) from public, anon, authenticated;

-- One visit or assessment as the reminder sees it, in the business's local time.
create or replace function private.automation_appointment(
  p_organization_id uuid, p_subject_type text, p_subject_id uuid, p_timezone text
)
returns table (
  client_id uuid,
  property_id uuid,
  local_date date,
  local_time time,
  is_completed boolean,
  is_open boolean,
  arrival_window_minutes integer,
  arrival_window_style text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select job.client_id, job.property_id, visit.visit_date, visit.start_time, visit.completed_at is not null,
    job.status = 'active', job.arrival_window_minutes, job.arrival_window_style
  from public.job_visits as visit
  join public.jobs as job on job.organization_id = visit.organization_id and job.id = visit.job_id
  where p_subject_type = 'job_visit' and visit.organization_id = p_organization_id and visit.id = p_subject_id
  union all
  select request.client_id, request.property_id, (assessment.starts_at at time zone p_timezone)::date,
    case when assessment.all_day then null else (assessment.starts_at at time zone p_timezone)::time end,
    assessment.completed_at is not null, request.status <> 'archived', null, null
  from public.assessments as assessment
  join public.requests as request
    on request.organization_id = assessment.organization_id and request.id = assessment.request_id
  where p_subject_type = 'assessment' and assessment.organization_id = p_organization_id
    and assessment.id = p_subject_id and assessment.starts_at is not null;
$$;

revoke all on function private.automation_appointment(uuid, text, uuid, text) from public, anon, authenticated;

-- Why an appointment reminder must not go out now, or null to carry on.
create or replace function private.automation_appointment_stop_outcome(
  p_organization_id uuid, p_subject_type text, p_subject_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  timezone text := private.appointment_timezone(p_organization_id);
  appointment record;
  client_row public.clients;
  preference public.client_communication_preferences;
begin
  select * into appointment
  from private.automation_appointment(p_organization_id, p_subject_type, p_subject_id, timezone);
  if not found or appointment.local_date is null then
    return 'subject_gone';
  end if;
  if appointment.is_completed then
    return 'appointment_completed';
  end if;
  if not appointment.is_open then
    return 'appointment_cancelled';
  end if;
  if private.appointment_starts_at(appointment.local_date, appointment.local_time, timezone) <= now() then
    return 'appointment_started';
  end if;

  select * into client_row from public.clients
  where organization_id = p_organization_id and id = appointment.client_id;
  if client_row.id is null or client_row.deleted_at is not null then
    return 'client_removed';
  end if;

  select * into preference from public.client_communication_preferences
  where organization_id = p_organization_id and client_id = client_row.id;
  if preference.appointment_reminders is false then
    return 'client_opted_out';
  end if;
  if preference.contact_policy = 'do_not_disturb' then
    return 'do_not_disturb';
  end if;
  return null;
end;
$$;

revoke all on function private.automation_appointment_stop_outcome(uuid, text, uuid) from public, anon, authenticated;

-- 4. Finding due reminders -----------------------------------------------------------------------------------

create or replace function private.appointment_reminder_source_id(p_recipe_id uuid, p_subject_id uuid)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select md5(p_recipe_id::text || ':' || p_subject_id::text)::uuid;
$$;

revoke all on function private.appointment_reminder_source_id(uuid, uuid) from public, anon, authenticated;

-- Called by the automation worker at the start of each wake. Returns how many reminders it found due.
create or replace function public.emit_due_appointment_reminders(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
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
      join public.job_visits as visit
        on visit.organization_id = recipes.organization_id
        and visit.visit_date between (now() at time zone recipes.timezone)::date
          and (now() at time zone recipes.timezone)::date + 8
        and visit.completed_at is null
      join public.jobs as job
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
      join public.assessments as assessment
        on assessment.organization_id = recipes.organization_id
        and assessment.completed_at is null
        and assessment.starts_at > now() - interval '1 day'
        and assessment.starts_at < now() + interval '9 days'
      join public.requests as request
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
$$;

revoke all on function public.emit_due_appointment_reminders(integer) from public, anon, authenticated;
grant execute on function public.emit_due_appointment_reminders(integer) to service_role;

-- 5. Intake and advance know appointments --------------------------------------------------------------------

create or replace function public.intake_automation_events(p_batch_size integer default 25)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate private.automation_events%rowtype;
  match_row record;
  authority public.organization_automation_authority%rowtype;
  quote_row public.quotes%rowtype;
  is_entitled boolean;
  wants_follow_ups boolean;
  subject_present boolean;
  appointment_client_id uuid;
  duration_days integer;
  enrollment_expires_at timestamptz;
  re_entry_key text;
  match_outcome text;
  new_enrollment_id uuid;
  processed_count integer := 0;
  max_processing_attempts constant integer := 5;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The intake batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select *
    from private.automation_events
    where processed_at is null
      and available_at <= now()
    order by seq
    limit p_batch_size
    for update skip locked
  loop
    begin
      select * into authority
      from public.organization_automation_authority
      where organization_id = candidate.organization_id;

      is_entitled := private.organization_has_automations_feature(candidate.organization_id);

      quote_row := null;
      wants_follow_ups := true;
      if candidate.subject_type = 'quote' then
        select * into quote_row
        from public.quotes
        where organization_id = candidate.organization_id and id = candidate.subject_id;

        if quote_row.client_id is not null then
          select coalesce(p.quote_follow_ups, true) into wants_follow_ups
          from public.client_communication_preferences as p
          where p.organization_id = candidate.organization_id and p.client_id = quote_row.client_id;
          wants_follow_ups := coalesce(wants_follow_ups, true);
        end if;

        subject_present := quote_row.id is not null and quote_row.archived_at is null;
        re_entry_key := coalesce(candidate.payload ->> 'quote_version_id', '')
          || ':' || coalesce(candidate.payload ->> 'quote_recipient_id', '');
      elsif candidate.subject_type = 'form_submission' then
        select exists (
          select 1 from private.form_submissions as s
          where s.organization_id = candidate.organization_id and s.id = candidate.subject_id
            and s.status = 'processed'
        ) into subject_present;
        re_entry_key := 'form_submission:' || candidate.subject_id::text;
      elsif candidate.subject_type = 'website_chat_session' then
        select exists (
          select 1 from public.website_chat_sessions as s
          where s.organization_id = candidate.organization_id and s.id = candidate.subject_id
        ) into subject_present;
        re_entry_key := 'website_chat_session:' || candidate.subject_id::text;
      elsif candidate.subject_type = 'job' then
        select exists (
          select 1 from public.jobs as job
          join public.clients as client
            on client.organization_id = job.organization_id and client.id = job.client_id
          where job.organization_id = candidate.organization_id and job.id = candidate.subject_id
            and client.deleted_at is null
        ) into subject_present;

        -- A client who switched review requests off is never asked automatically.
        select preference.review_requests into wants_follow_ups
        from public.jobs as job
        join public.client_communication_preferences as preference
          on preference.organization_id = job.organization_id and preference.client_id = job.client_id
        where job.organization_id = candidate.organization_id and job.id = candidate.subject_id;
        wants_follow_ups := coalesce(wants_follow_ups, true);

        -- One ask per one-off job; one per completed-visit count of a recurring job, so completing,
        -- clearing and completing the same visit again does not ask twice.
        re_entry_key := 'job:' || candidate.subject_id::text
          || case when candidate.payload ->> 'job_type' = 'recurring'
               then ':visits:' || coalesce(candidate.payload ->> 'completed_visit_count', '')
               else '' end;
      elsif candidate.subject_type in ('job_visit', 'assessment') then
        -- Client reminders Part 3: one reminder per visit or assessment, ever, for each recipe.
        select appointment.client_id into appointment_client_id
        from private.automation_appointment(
          candidate.organization_id, candidate.subject_type, candidate.subject_id,
          private.appointment_timezone(candidate.organization_id)) as appointment;
        subject_present := private.automation_appointment_stop_outcome(
          candidate.organization_id, candidate.subject_type, candidate.subject_id
        ) is distinct from 'subject_gone';

        select preference.appointment_reminders into wants_follow_ups
        from public.client_communication_preferences as preference
        where preference.organization_id = candidate.organization_id
          and preference.client_id = appointment_client_id;
        wants_follow_ups := coalesce(wants_follow_ups, true);

        re_entry_key := candidate.subject_type || ':' || candidate.subject_id::text;
      else
        subject_present := false;
        re_entry_key := candidate.subject_type || ':' || candidate.subject_id::text;
      end if;

      select case when limits.state = 'numeric' then limits.value end
      into duration_days
      from public.effective_automation_limits(candidate.organization_id) as limits
      where limits.limit_key = 'automation_max_enrollment_duration_days';

      enrollment_expires_at := case
        when duration_days is not null and duration_days > 0
        then now() + make_interval(days => duration_days)
      end;

      for match_row in
        select
          recipe.id as recipe_id,
          recipe.current_version_id,
          version.definition,
          version.activation_cutoff_snapshot,
          version.activation_cutoff_sequence
        from public.automation_recipes as recipe
        join public.automation_recipe_versions as version
          on version.id = recipe.current_version_id
        where recipe.organization_id = candidate.organization_id
          and recipe.status = 'active'
          and recipe.active_trigger_key = candidate.event_type
        order by recipe.id
      loop
        match_outcome := null;
        new_enrollment_id := null;

        if not is_entitled then
          match_outcome := 'not_entitled';
        elsif authority.organization_id is not null
          and (authority.operational_state <> 'enabled' or authority.security_state <> 'active') then
          match_outcome := 'authority_blocked';
        elsif (
            match_row.activation_cutoff_snapshot is not null
            and pg_visible_in_snapshot(candidate.created_xid, match_row.activation_cutoff_snapshot)
          ) or (
            match_row.activation_cutoff_snapshot is null
            and candidate.seq <= coalesce(match_row.activation_cutoff_sequence, 0)
          ) then
          match_outcome := 'before_activation';
        elsif not subject_present then
          match_outcome := 'subject_gone';
        elsif not wants_follow_ups then
          match_outcome := 'follow_ups_declined';
        else
          if candidate.subject_type = 'quote' then
            match_outcome := private.automation_conditions_outcome(
              match_row.definition, candidate.organization_id, quote_row.status, candidate.payload
            );
          elsif candidate.subject_type = 'job'
            and not private.automation_job_trigger_matches(match_row.definition, candidate.payload) then
            match_outcome := 'condition_failed';
          -- A due reminder was found with one recipe's timing; only that recipe takes it.
          elsif candidate.subject_type in ('job_visit', 'assessment')
            and candidate.payload ->> 'recipe_id' is distinct from match_row.recipe_id::text then
            match_outcome := 'condition_failed';
          elsif jsonb_array_length(coalesce(match_row.definition -> 'conditions', '[]'::jsonb)) > 0 then
            match_outcome := 'condition_unavailable';
          else
            match_outcome := 'pass';
          end if;

          if match_outcome = 'pass' then
            insert into private.automation_enrollments (
              organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
              trigger_event_id, source, re_entry_key, context, expires_at, anchor_at
            ) values (
              candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
              candidate.subject_type, candidate.subject_id, candidate.id, 'event',
              re_entry_key, candidate.payload, enrollment_expires_at,
              candidate.occurred_at
            )
            on conflict do nothing
            returning id into new_enrollment_id;

            if new_enrollment_id is null then
              match_outcome := 'already_enrolled';
            else
              match_outcome := 'enrolled';
              insert into private.automation_work_items (
                organization_id, enrollment_id, step_index, due_at, available_at
              ) values (
                candidate.organization_id, new_enrollment_id, 0, now(), now()
              )
              on conflict do nothing;
            end if;
          end if;
        end if;

        insert into private.automation_event_matches (
          event_id, organization_id, recipe_id, recipe_version_id, outcome, enrollment_id
        ) values (
          candidate.id, candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
          match_outcome, new_enrollment_id
        )
        on conflict (event_id, recipe_id) do nothing;
      end loop;

      update private.automation_events
      set processed_at = now(), processing_error = null
      where id = candidate.id;
      processed_count := processed_count + 1;

    exception
      when others then
        update private.automation_events
        set processing_attempts = coalesce(processing_attempts, 0) + 1,
          processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
          available_at = now() + private.automation_retry_delay(coalesce(processing_attempts, 0) + 1),
          processed_at = case
            when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
            else processed_at
          end
        where id = candidate.id;
    end;
  end loop;

  return processed_count;
end;
$$;

create or replace function public.advance_automation_work_item(p_work_item_id uuid, p_claim_token uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  definition jsonb;
  step jsonb;
  step_type text;
  stop_outcome text;
  organization_timezone text;
  wait_amount integer;
  wait_unit text;
  waited_days integer;
  waited_hours integer;
  waited_minutes integer;
  next_due timestamptz;
  customer_reply_at timestamptz;   -- Stage 3
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;

  select * into item from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending' for update;
  if not found then return 'claim_lost'; end if;

  select * into enrollment from private.automation_enrollments where id = item.enrollment_id for update;
  if not found or enrollment.state <> 'active' then
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'enrollment_inactive';
  end if;

  if enrollment.expires_at is not null and enrollment.expires_at <= now() then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'enrollment_expired', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'enrollment_expired';
  end if;

  select recipe.status, version.definition into recipe_status, definition
  from private.automation_enrollments as e
  join public.automation_recipes as recipe on recipe.id = e.recipe_id
  join public.automation_recipe_versions as version on version.id = e.recipe_version_id
  where e.id = enrollment.id;

  if recipe_status is distinct from 'active' then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'recipe_not_active', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'recipe_not_active';
  end if;

  step := (definition -> 'steps') -> item.step_index;

  if step is null then
    update private.automation_enrollments
    set state = 'completed', completed_at = now(), current_step_index = item.step_index
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null where id = item.id;
    return 'completed';
  end if;

  if enrollment.subject_type = 'quote' then
    stop_outcome := private.automation_quote_stop_outcome(enrollment.organization_id, enrollment.subject_id);
    if stop_outcome is not null then
      update private.automation_enrollments
      set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
      update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
      return 'stop_condition_met';
    end if;
  end if;

  -- Stage 3: a website inquiry stops on a delivered staff reply at every transition, and pauses before a
  -- customer-facing step when the customer replied to what this enrollment already sent them.
  if enrollment.subject_type in ('form_submission', 'website_chat_session') then
    stop_outcome := private.automation_inquiry_stop_outcome(
      enrollment.organization_id, enrollment.subject_type, enrollment.subject_id, enrollment.anchor_at
    );
    if stop_outcome is not null then
      update private.automation_enrollments
      set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
      update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
      return 'stop_condition_met';
    end if;

    if step ->> 'type' = 'action' and step ->> 'key' in ('action.send_email', 'action.send_sms', 'action.send_customer_message') then
      customer_reply_at := private.automation_inquiry_customer_reply_at(
        enrollment.organization_id, enrollment.subject_type, enrollment.subject_id,
        enrollment.customer_reply_after
      );
      if customer_reply_at is not null then
        -- The same shape as a staff Pause, so the existing Resume restores this step at its original time.
        update private.automation_enrollments
        set state = 'paused', paused_work_due_at = item.due_at, current_step_index = item.step_index,
          customer_reply_after = customer_reply_at
        where id = enrollment.id;
        update private.automation_work_items
        set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
        return 'paused_customer_reply';
      end if;
    end if;
  end if;

  -- Google review Part 4B: a job enrollment stops when the job was reopened or is no longer eligible, or the
  -- client was removed or switched review requests off.
  if enrollment.subject_type = 'job' then
    stop_outcome := private.automation_job_stop_outcome(enrollment.organization_id, enrollment.subject_id);
    if stop_outcome is not null then
      update private.automation_enrollments
      set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
      update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
      return 'stop_condition_met';
    end if;
  end if;

  -- Client reminders Part 3: a reminder stops once its visit is gone, done, cancelled or started, or the client
  -- no longer wants reminders.
  if enrollment.subject_type in ('job_visit', 'assessment') then
    stop_outcome := private.automation_appointment_stop_outcome(
      enrollment.organization_id, enrollment.subject_type, enrollment.subject_id);
    if stop_outcome is not null then
      update private.automation_enrollments
      set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
      update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
      return 'stop_condition_met';
    end if;
  end if;

  step_type := step ->> 'type';

  if step_type = 'wait' then
    wait_unit := step -> 'config' ->> 'unit';
    wait_amount := nullif(step -> 'config' ->> 'amount', '')::integer;
    if wait_unit not in ('minutes', 'hours', 'days') or wait_amount is null or wait_amount < 1 then
      raise exception 'This automation step has an unusable delay.' using errcode = 'check_violation';
    end if;

    select
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'days'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0),
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'hours'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0),
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'minutes'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0)
    into waited_days, waited_hours, waited_minutes
    from jsonb_array_elements(coalesce(definition -> 'steps', '[]'::jsonb))
      with ordinality as entry(step, position)
    where entry.position - 1 <= item.step_index and entry.step ->> 'type' = 'wait';

    select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into organization_timezone
    from public.organization_settings as settings
    where settings.organization_id = enrollment.organization_id;
    organization_timezone := coalesce(organization_timezone, 'UTC');

    -- Days land at the same local time of day; hours and minutes are real elapsed time. Round-tripping the
    -- anchor through local time only when days are waited keeps a short wait on a fall-back night exact.
    next_due := case
        when waited_days > 0 then
          ((enrollment.anchor_at at time zone organization_timezone) + make_interval(days => waited_days))
            at time zone organization_timezone
        else enrollment.anchor_at
      end
      + make_interval(hours => waited_hours, mins => waited_minutes);

    update private.automation_enrollments
    set current_step_index = item.step_index + 1 where id = enrollment.id;

    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null where id = item.id;

    insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at)
    values (enrollment.organization_id, enrollment.id, item.step_index + 1, next_due, next_due)
    on conflict (enrollment_id, step_index) do nothing;

    return 'waiting';
  end if;

  if step_type = 'action' then
    -- 7: distinguish which action effect the worker must run instead of always assuming email. The row stays
    -- claimed under its lease meanwhile; a lease that expires before the effect settles returns the row to
    -- the queue and the idempotent send key prevents a double.
    if (step ->> 'key') = 'action.send_email' then
      return 'action_due_email';
    elsif (step ->> 'key') = 'action.send_sms' then
      return 'action_due_sms';
    -- Stage 5: a website inquiry's text-or-email message.
    elsif (step ->> 'key') = 'action.send_customer_message' then
      return 'action_due_customer_message';
    -- Google review Part 4B: a job's review request.
    elsif (step ->> 'key') = 'action.send_review_request' then
      return 'action_due_review_request';
    -- Client reminders Part 3: a visit or assessment reminder email.
    elsif (step ->> 'key') = 'action.send_appointment_email' then
      return 'action_due_appointment_email';
    else
      update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null
      where id = item.id;
      return 'action_not_available';
    end if;
  end if;

  raise exception 'This automation step has an unknown type.' using errcode = 'check_violation';
end;
$$;

-- 6. The email -----------------------------------------------------------------------------------------------

-- Fills {{token}} placeholders from p_values. The subject and text get the raw value; the HTML gets it escaped,
-- after the authored body itself was escaped, so neither authored nor customer text can become markup.
create or replace function private.render_automation_template(p_subject text, p_body text, p_values jsonb)
returns table (subject text, html_content text, text_content text)
language plpgsql
immutable
set search_path = pg_catalog, private
as $$
declare
  entry record;
  rendered_subject text := coalesce(p_subject, '');
  rendered_html text := private.html_escape(coalesce(p_body, ''));
  rendered_text text := coalesce(p_body, '');
begin
  for entry in select key, value from jsonb_each_text(coalesce(p_values, '{}'::jsonb)) loop
    rendered_subject := replace(rendered_subject, '{{' || entry.key || '}}', coalesce(entry.value, ''));
    rendered_html := replace(rendered_html, '{{' || entry.key || '}}', private.html_escape(coalesce(entry.value, '')));
    rendered_text := replace(rendered_text, '{{' || entry.key || '}}', coalesce(entry.value, ''));
  end loop;
  subject := rendered_subject;
  html_content := '<p>' || regexp_replace(rendered_html, E'\\r?\\n', '<br>', 'g') || '</p>';
  text_content := rendered_text;
  return next;
end;
$$;

revoke all on function private.render_automation_template(text, text, jsonb) from public, anon, authenticated;

-- "Thursday, October 10 at 9:00 AM", "Thursday, October 10 between 9:00 AM and 11:00 AM" (the job's arrival
-- window), or "Thursday, October 10" when no time is set.
create or replace function private.appointment_when_text(
  p_date date, p_time time, p_arrival_window_minutes integer, p_arrival_window_style text
)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  day_text text := to_char(p_date, 'FMDay, FMMonth FMDD');
  starts timestamp := p_date + p_time;
  window_start timestamp;
  window_end timestamp;
begin
  if p_time is null then
    return day_text;
  end if;
  if p_arrival_window_minutes is null then
    return day_text || ' at ' || to_char(starts, 'FMHH12:MI AM');
  end if;
  if p_arrival_window_style = 'centered' then
    window_start := starts - make_interval(mins => p_arrival_window_minutes / 2);
    window_end := starts + make_interval(mins => p_arrival_window_minutes - p_arrival_window_minutes / 2);
  else
    window_start := starts;
    window_end := starts + make_interval(mins => p_arrival_window_minutes);
  end if;
  return day_text || ' between ' || to_char(window_start, 'FMHH12:MI AM')
    || ' and ' || to_char(window_end, 'FMHH12:MI AM');
end;
$$;

revoke all on function private.appointment_when_text(date, time, integer, text) from public, anon, authenticated;

create or replace function private.enqueue_automation_appointment_email(
  p_organization_id uuid, p_subject_type text, p_subject_id uuid, p_logical_send_key text,
  p_subject text, p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  timezone text := private.appointment_timezone(p_organization_id);
  appointment record;
  client_row public.clients;
  preference public.client_communication_preferences;
  property_row public.properties;
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  alias public.communication_reply_aliases;
  intent public.communication_delivery_intents;
  business_name text;
  address_text text;
  rendered record;
begin
  select * into intent from public.communication_delivery_intents
    where organization_id = p_organization_id and logical_send_key = p_logical_send_key;
  if intent.id is not null then
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end if;

  if coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_email_content');
  end if;

  if not private.organization_has_automations_feature(p_organization_id, now()) then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'automations_not_entitled');
  end if;
  select * into authority from public.organization_automation_authority
    where organization_id = p_organization_id;
  if coalesce(authority.operational_state, 'enabled') <> 'enabled'
    or coalesce(authority.security_state, 'active') <> 'active' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'automation_suspended');
  end if;

  select * into appointment
    from private.automation_appointment(p_organization_id, p_subject_type, p_subject_id, timezone);
  if not found or appointment.local_date is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'subject_gone');
  end if;

  select * into client_row from public.clients
    where organization_id = p_organization_id and id = appointment.client_id and deleted_at is null for share;
  select * into preference from public.client_communication_preferences
    where organization_id = p_organization_id and client_id = client_row.id;
  if preference.appointment_reminders is false then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'client_opted_out');
  end if;
  if preference.contact_policy = 'do_not_disturb' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'do_not_disturb');
  end if;

  select * into recipient from public.client_contact_methods
    where organization_id = p_organization_id and client_id = client_row.id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'no_email_address');
  end if;

  select * into sender from public.communication_email_senders
    where organization_id = p_organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    return jsonb_build_object('status', 'skipped_temporary', 'reason', 'email_sender_not_ready');
  end if;

  select organization.name into business_name from public.organizations as organization
    where organization.id = p_organization_id;

  select * into property_row from public.properties
    where organization_id = p_organization_id and id = appointment.property_id;
  address_text := concat_ws(', ',
    nullif(btrim(property_row.address_line1), ''), nullif(btrim(property_row.address_line2), ''),
    nullif(btrim(property_row.city), ''),
    nullif(btrim(concat_ws(' ', nullif(btrim(property_row.state_region), ''),
      nullif(btrim(property_row.postal_code), ''))), ''));

  select * into rendered from private.render_automation_template(p_subject, p_body, jsonb_build_object(
    'customer_name', coalesce(nullif(btrim(client_row.display_name), ''), recipient.normalized_value),
    'business_name', coalesce(business_name, ''),
    'appointment_when', private.appointment_when_text(
      appointment.local_date, appointment.local_time,
      appointment.arrival_window_minutes, appointment.arrival_window_style),
    'appointment_address', coalesce(address_text, '')));

  alias := public.ensure_communication_reply_alias(p_organization_id, sender.id, client_row.id, recipient.id);

  begin
    insert into public.communication_delivery_intents
      (organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email, subject,
       html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by)
      values (p_organization_id, client_row.id, recipient.id, p_logical_send_key, recipient.normalized_value,
       rendered.subject, rendered.html_content, rendered.text_content,
       'automated', 'essential', sender.id, alias.id, null)
      returning * into intent;
  exception when unique_violation then
    select * into intent from public.communication_delivery_intents
      where organization_id = p_organization_id and logical_send_key = p_logical_send_key;
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
    values (intent.organization_id, intent.id);

  return jsonb_build_object('status', 'sent', 'reason', 'enqueued', 'intent_id', intent.id);
end;
$$;

revoke all on function private.enqueue_automation_appointment_email(uuid, text, uuid, text, text, text)
  from public, anon, authenticated;

-- Runs one claimed reminder email step in a single transaction, settling the work item like the quote email.
create or replace function public.perform_automation_appointment_email_effect(p_work_item_id uuid, p_claim_token uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  definition jsonb;
  step jsonb;
  result jsonb;
  status text;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;
  select * into item from private.automation_work_items
    where id = p_work_item_id and claim_token = p_claim_token and state = 'pending' for update;
  if not found then return 'claim_lost'; end if;
  select * into enrollment from private.automation_enrollments where id = item.enrollment_id for update;
  if not found or enrollment.state <> 'active' then
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;
  if enrollment.expires_at is not null and enrollment.expires_at <= now() then
    update private.automation_enrollments
      set state = 'stopped', stop_reason = 'enrollment_expired', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;
  select recipe.status, version.definition into recipe_status, definition
    from private.automation_enrollments e
    join public.automation_recipes recipe on recipe.id = e.recipe_id
    join public.automation_recipe_versions version on version.id = e.recipe_version_id
    where e.id = enrollment.id;
  if recipe_status = 'paused' then
    update private.automation_work_items
      set available_at = now() + private.automation_retry_delay(item.attempts),
        claim_token = null, claimed_at = null where id = item.id;
    return 'action_deferred';
  end if;
  if recipe_status is distinct from 'active' then
    update private.automation_enrollments
      set state = 'stopped', stop_reason = 'recipe_not_active', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;
  step := (definition -> 'steps') -> item.step_index;
  if step is null or (step ->> 'type') <> 'action' or (step ->> 'key') <> 'action.send_appointment_email'
    or enrollment.subject_type not in ('job_visit', 'assessment') then
    update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  result := private.enqueue_automation_appointment_email(
    enrollment.organization_id, enrollment.subject_type, enrollment.subject_id,
    'automation-appointment-reminder:' || enrollment.id || ':' || item.step_index,
    step -> 'config' ->> 'subject', step -> 'config' ->> 'body');
  status := result ->> 'status';
  if status = 'sent' then
    update private.automation_enrollments
      set current_step_index = item.step_index + 1, customer_messages_sent = customer_messages_sent + 1
      where id = enrollment.id;
    update private.automation_work_items
      set state = 'done', claim_token = null, claimed_at = null where id = item.id;
    insert into private.automation_work_items
      (organization_id, enrollment_id, step_index, due_at, available_at)
      values (enrollment.organization_id, enrollment.id, item.step_index + 1, now(), now())
      on conflict (enrollment_id, step_index) do nothing;
    return 'action_sent';
  elsif status = 'skipped_temporary' then
    update private.automation_work_items
      set available_at = now() + private.automation_retry_delay(item.attempts),
        last_error_code = left(result ->> 'reason', 100), claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_deferred';
  else
    update private.automation_enrollments
      set state = 'stopped', stop_reason = left(result ->> 'reason', 100), stopped_at = now()
      where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', last_error_code = left(result ->> 'reason', 100),
        claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;
end;
$$;

revoke all on function public.perform_automation_appointment_email_effect(uuid, uuid) from public, anon, authenticated;
grant execute on function public.perform_automation_appointment_email_effect(uuid, uuid) to service_role;
