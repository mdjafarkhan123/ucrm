-- Client reminders Part 4: "You're booked" and "Your visit has moved" emails.
--
-- Product truth: docs/client-reminders-behavior-contract.md § "You're booked" confirmation and § Customer messages:
-- shared rules. Following Housecall Pro's booking confirmation (sent when the visit is scheduled, with a "Notify
-- customer" box on the scheduling screen) and Jobber's one-time booking confirmation (one per job, not per visit).
--
-- 1. Two new automation triggers on Part 3's appointment subject (a job visit or an assessment):
--    appointment.booked and appointment.rescheduled. They reuse Part 3's intake, stops and
--    action.send_appointment_email.
-- 2. private.appointment_schedule_changes logs every schedule change to a visit or assessment, with who made it:
--    scheduled (a date was set), moved (a set date or time changed) or removed (a dated visit lost its date or
--    was deleted). Completed visits are ignored.
-- 3. Every scheduling screen saves first and then calls settle_appointment_notices with its "Notify customer"
--    box. That consumes the caller's own recent changes to the job or assessment and, when the box was ticked,
--    emits at most one event: booked the first time (one per job or assessment, ever), else rescheduled when a
--    visit moved or a recurring schedule was rebuilt. Adding or removing a visit alone sends nothing. An event
--    is only emitted while its automation is on, so a confirmation never counts as sent when nothing was sent.
-- 4. A "moved" email is not sent when the visit moved again before it went out; the newer move sends instead.

-- 1. Constraints ---------------------------------------------------------------------------------------------

alter table private.automation_events
  drop constraint automation_events_event_type_check,
  add constraint automation_events_event_type_check check (event_type = any (array[
    'quote.delivery_succeeded', 'website_inquiry.received', 'job.work_completed', 'appointment.reminder_due',
    'appointment.booked', 'appointment.rescheduled']));

-- 2. The schedule change log ---------------------------------------------------------------------------------

create table private.appointment_schedule_changes (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  booking_type text not null check (booking_type in ('job', 'assessment')),
  booking_id uuid not null,
  visit_id uuid not null,
  kind text not null check (kind in ('scheduled', 'moved', 'removed')),
  changed_by uuid,
  changed_at timestamptz not null default now()
);

alter table private.appointment_schedule_changes enable row level security;
revoke all on table private.appointment_schedule_changes from public, anon, authenticated;

create index appointment_schedule_changes_booking_idx
  on private.appointment_schedule_changes (organization_id, booking_type, booking_id, changed_by);
create index appointment_schedule_changes_changed_at_idx
  on private.appointment_schedule_changes (changed_at);

create or replace function private.job_visits_log_schedule_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  change_kind text;
  row_data public.job_visits;
begin
  if tg_op = 'DELETE' then
    row_data := old;
    if old.visit_date is not null and old.completed_at is null then
      change_kind := 'removed';
    end if;
  else
    row_data := new;
    if new.completed_at is not null then
      change_kind := null;
    elsif tg_op = 'INSERT' then
      if new.visit_date is not null then change_kind := 'scheduled'; end if;
    elsif old.visit_date is null and new.visit_date is not null then
      change_kind := 'scheduled';
    elsif old.visit_date is not null and new.visit_date is null then
      change_kind := 'removed';
    elsif (old.visit_date, old.start_time, old.all_day) is distinct from (new.visit_date, new.start_time, new.all_day) then
      change_kind := 'moved';
    end if;
  end if;

  if change_kind is not null then
    insert into private.appointment_schedule_changes
      (organization_id, booking_type, booking_id, visit_id, kind, changed_by)
    values (row_data.organization_id, 'job', row_data.job_id, row_data.id, change_kind, (select auth.uid()));
  end if;
  return null;
end;
$$;

revoke all on function private.job_visits_log_schedule_change() from public, anon, authenticated;

create trigger job_visits_log_schedule_change
  after insert or delete or update of visit_date, start_time, all_day on public.job_visits
  for each row execute function private.job_visits_log_schedule_change();

create or replace function private.assessments_log_schedule_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  change_kind text;
  row_data public.assessments;
begin
  if tg_op = 'DELETE' then
    row_data := old;
    if old.starts_at is not null and old.completed_at is null then
      change_kind := 'removed';
    end if;
  else
    row_data := new;
    if new.completed_at is not null then
      change_kind := null;
    elsif tg_op = 'INSERT' then
      if new.starts_at is not null then change_kind := 'scheduled'; end if;
    elsif old.starts_at is null and new.starts_at is not null then
      change_kind := 'scheduled';
    elsif old.starts_at is not null and new.starts_at is null then
      change_kind := 'removed';
    elsif (old.starts_at, old.all_day) is distinct from (new.starts_at, new.all_day) then
      change_kind := 'moved';
    end if;
  end if;

  if change_kind is not null then
    insert into private.appointment_schedule_changes
      (organization_id, booking_type, booking_id, visit_id, kind, changed_by)
    values (row_data.organization_id, 'assessment', row_data.id, row_data.id, change_kind, (select auth.uid()));
  end if;
  return null;
end;
$$;

revoke all on function private.assessments_log_schedule_change() from public, anon, authenticated;

create trigger assessments_log_schedule_change
  after insert or delete or update of starts_at, all_day on public.assessments
  for each row execute function private.assessments_log_schedule_change();

-- 3. Settling a save's changes -------------------------------------------------------------------------------

create or replace function private.appointment_trigger_is_active(p_organization_id uuid, p_trigger_key text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.automation_recipes as recipe
    where recipe.organization_id = p_organization_id and recipe.status = 'active'
      and recipe.active_trigger_key = p_trigger_key);
$$;

revoke all on function private.appointment_trigger_is_active(uuid, text) from public, anon, authenticated;

-- Called by each scheduling route right after its save, with the screen's "Notify customer" box. Returns
-- { "notice": "booked" | "rescheduled" | null }.
create or replace function public.settle_appointment_notices(
  target_organization_id uuid, target_booking_type text, target_booking_id uuid, notify_customer boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  caller uuid := (select auth.uid());
  timezone text;
  changed_visit_ids uuid[];
  has_scheduled boolean;
  has_moved boolean;
  has_removed boolean;
  target_id uuid;
  target_schedule_set_at timestamptz;
  booked_source uuid;
  payload jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in.' using errcode = 'insufficient_privilege';
  end if;
  if target_booking_type not in ('job', 'assessment') then
    raise exception 'Unknown booking.' using errcode = 'check_violation';
  end if;
  if not private.is_organization_member(target_organization_id) then
    raise exception 'You do not have access to this organization.' using errcode = 'insufficient_privilege';
  end if;

  -- Changes nobody settled (a save that failed half-way, a website booking) are dropped after a day.
  delete from private.appointment_schedule_changes
  where organization_id = target_organization_id and changed_at < now() - interval '1 day';

  with consumed as (
    delete from private.appointment_schedule_changes
    where organization_id = target_organization_id and booking_type = target_booking_type
      and booking_id = target_booking_id and changed_by = caller
    returning visit_id, kind
  )
  select
    coalesce(array_agg(distinct visit_id) filter (where kind in ('scheduled', 'moved')), '{}'),
    coalesce(bool_or(kind = 'scheduled'), false),
    coalesce(bool_or(kind = 'moved'), false),
    coalesce(bool_or(kind = 'removed'), false)
  into changed_visit_ids, has_scheduled, has_moved, has_removed
  from consumed;

  if not coalesce(notify_customer, false) or not (has_scheduled or has_moved or has_removed) then
    return jsonb_build_object('notice', null);
  end if;

  timezone := private.appointment_timezone(target_organization_id);

  -- What the email describes: the earliest upcoming visit this save touched, else the job's next visit.
  if target_booking_type = 'job' then
    select visit.id, visit.schedule_set_at into target_id, target_schedule_set_at
    from public.job_visits as visit
    join public.jobs as job
      on job.organization_id = visit.organization_id and job.id = visit.job_id and job.status = 'active'
    where visit.organization_id = target_organization_id and visit.job_id = target_booking_id
      and visit.visit_date is not null and visit.completed_at is null
      and private.appointment_starts_at(visit.visit_date, visit.start_time, timezone) > now()
    order by (visit.id = any (changed_visit_ids)) desc, visit.visit_date, visit.start_time nulls first, visit.id
    limit 1;
  else
    select assessment.id, assessment.schedule_set_at into target_id, target_schedule_set_at
    from public.assessments as assessment
    join public.requests as request
      on request.organization_id = assessment.organization_id and request.id = assessment.request_id
      and request.status <> 'archived'
    where assessment.organization_id = target_organization_id and assessment.id = target_booking_id
      and assessment.completed_at is null and assessment.starts_at > now();
  end if;

  if target_id is null then
    return jsonb_build_object('notice', null);
  end if;

  payload := jsonb_build_object(
    'booking_type', target_booking_type, 'booking_id', target_booking_id,
    'schedule_set_at', target_schedule_set_at);
  booked_source := md5('booked:' || target_booking_type || ':' || target_booking_id::text)::uuid;

  if not exists (
      select 1 from private.automation_events as event
      where event.source_module = 'scheduling' and event.source_event_id = booked_source
        and event.event_type = 'appointment.booked')
    and private.appointment_trigger_is_active(target_organization_id, 'appointment.booked') then
    perform private.emit_automation_event(
      target_organization_id, 'appointment.booked',
      case when target_booking_type = 'job' then 'job_visit' else 'assessment' end, target_id,
      payload || jsonb_build_object('notice', 'booked'), now(), 'scheduling', booked_source);
    return jsonb_build_object('notice', 'booked');
  end if;

  if (has_moved or (has_removed and has_scheduled))
    and private.appointment_trigger_is_active(target_organization_id, 'appointment.rescheduled') then
    perform private.emit_automation_event(
      target_organization_id, 'appointment.rescheduled',
      case when target_booking_type = 'job' then 'job_visit' else 'assessment' end, target_id,
      payload || jsonb_build_object('notice', 'rescheduled'), now(), 'scheduling', gen_random_uuid());
    return jsonb_build_object('notice', 'rescheduled');
  end if;

  return jsonb_build_object('notice', null);
end;
$$;

revoke all on function public.settle_appointment_notices(uuid, text, uuid, boolean) from public, anon;
grant execute on function public.settle_appointment_notices(uuid, text, uuid, boolean) to authenticated;

-- A "moved" email describes a schedule that has since changed again: the newer move sends instead.
create or replace function private.appointment_notice_superseded(
  p_organization_id uuid, p_subject_type text, p_subject_id uuid, p_context jsonb
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select p_context ->> 'notice' = 'rescheduled'
    and coalesce((
      select case when p_subject_type = 'job_visit' then
          (select visit.schedule_set_at from public.job_visits as visit
            where visit.organization_id = p_organization_id and visit.id = p_subject_id)
        else
          (select assessment.schedule_set_at from public.assessments as assessment
            where assessment.organization_id = p_organization_id and assessment.id = p_subject_id)
        end
    ) > (p_context ->> 'schedule_set_at')::timestamptz, false);
$$;

revoke all on function private.appointment_notice_superseded(uuid, text, uuid, jsonb) from public, anon, authenticated;

-- 4. Intake and advance know booking notices -----------------------------------------------------------------

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

        -- Client reminders Part 4: one confirmation per job or assessment; every settled move is its own notice.
        re_entry_key := case candidate.event_type
          when 'appointment.booked' then 'booked:' || coalesce(candidate.payload ->> 'booking_type', '')
            || ':' || coalesce(candidate.payload ->> 'booking_id', '')
          when 'appointment.rescheduled' then 'rescheduled:' || candidate.id::text
          else candidate.subject_type || ':' || candidate.subject_id::text
        end;
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
            and candidate.event_type = 'appointment.reminder_due'
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
    if stop_outcome is null and private.appointment_notice_superseded(
        enrollment.organization_id, enrollment.subject_type, enrollment.subject_id, enrollment.context) then
      stop_outcome := 'superseded';
    end if;
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
