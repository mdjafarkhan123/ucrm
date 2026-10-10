-- Client reminders Part 6: job follow-up.
--
-- Product truth: docs/client-reminders-behavior-contract.md § Job follow-up and § Customer messages: shared rules.
-- Following Jobber's Job Follow-ups: a thank-you email when a job's work is completed, sent within the business's
-- hours; the owner can add a delay.
--
-- 1. The existing trigger job.work_completed gains a second kind of recipe. A recipe whose steps include the new
--    action action.send_job_email is a thank-you: it follows the client's "Job completion follow-ups" switch and Do
--    not disturb, where a review-request recipe keeps following "Review requests".
-- 2. Intake and advance choose the switch per recipe. The job's existing re-entry key (one per one-off job, one per
--    completed-visit count of a recurring job) keeps a thank-you from going out twice.
-- 3. The email waits until the business is next open by its weekly hours; a business with no weekly hours (or
--    appointment only) sends at once.

-- 1. Helpers -------------------------------------------------------------------------------------------------

-- Whether a recipe's steps send the job thank-you email.
create or replace function private.automation_sends_job_email(p_definition jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select exists (
    select 1 from jsonb_array_elements(coalesce(p_definition -> 'steps', '[]'::jsonb)) as step
    where step ->> 'key' = 'action.send_job_email'
  );
$$;
revoke all on function private.automation_sends_job_email(jsonb) from public, anon, authenticated;

-- Why a job thank-you must not go out now, or null to carry on: the job's own state as the review ask reads it,
-- then the client's job follow-up switch and Do not disturb.
create or replace function private.automation_job_follow_up_stop_outcome(p_organization_id uuid, p_job_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  job_row public.jobs;
  client_row public.clients;
  preference public.client_communication_preferences;
begin
  select * into job_row from public.jobs where organization_id = p_organization_id and id = p_job_id;
  if job_row.id is null then
    return 'subject_gone';
  end if;
  select * into client_row from public.clients
  where organization_id = p_organization_id and id = job_row.client_id;
  if client_row.id is null or client_row.deleted_at is not null then
    return 'client_removed';
  end if;
  if job_row.job_type = 'one_off' and job_row.status <> 'closed' then
    return 'job_reopened';
  end if;
  if not private.review_request_job_is_eligible(p_organization_id, p_job_id) then
    return 'job_not_eligible';
  end if;
  select * into preference from public.client_communication_preferences
  where organization_id = p_organization_id and client_id = job_row.client_id;
  if preference.job_follow_ups is false then
    return 'client_opted_out';
  end if;
  if preference.contact_policy = 'do_not_disturb' then
    return 'do_not_disturb';
  end if;
  return null;
end;
$$;
revoke all on function private.automation_job_follow_up_stop_outcome(uuid, uuid) from public, anon, authenticated;

-- The first moment at or after p_at that the business is open by its weekly hours, in its own time zone. A
-- business with no weekly hours, or none open in the coming week, is treated as always open.
create or replace function private.organization_next_open_at(p_organization_id uuid, p_at timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  timezone text := private.appointment_timezone(p_organization_id);
  local_today date := (p_at at time zone timezone)::date;
  next_open timestamptz;
begin
  with periods as (
    select
      ((local_today + offset_days) + case when hours.is_open_24h then time '00:00' else hours.opens_at end)
        at time zone timezone as opens,
      case
        when hours.is_open_24h then ((local_today + offset_days + 1)::timestamp) at time zone timezone
        when hours.closes_at > hours.opens_at
          then ((local_today + offset_days) + hours.closes_at) at time zone timezone
        else ((local_today + offset_days + 1) + hours.closes_at) at time zone timezone
      end as closes
    from generate_series(-1, 7) as offset_days
    join public.organization_business_hours as hours
      on hours.organization_id = p_organization_id
      and hours.is_open
      and hours.weekday = extract(dow from local_today + offset_days)::integer
  )
  select case when bool_or(p_at >= opens and p_at < closes) then p_at else min(opens) filter (where opens > p_at) end
  into next_open
  from periods;

  return coalesce(next_open, p_at);
end;
$$;
revoke all on function private.organization_next_open_at(uuid, timestamptz) from public, anon, authenticated;

-- 2. Intake and advance know job thank-yous -------------------------------------------------------------------

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
  wants_job_follow_ups boolean;
  subject_present boolean;
  appointment_client_id uuid;
  invoice_client_id uuid;
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

        -- A client who switched review requests off is never asked automatically. Client reminders Part 6: a
        -- thank-you recipe follows the client's job follow-up switch instead (chosen per recipe below).
        select preference.review_requests, preference.job_follow_ups
        into wants_follow_ups, wants_job_follow_ups
        from public.jobs as job
        join public.client_communication_preferences as preference
          on preference.organization_id = job.organization_id and preference.client_id = job.client_id
        where job.organization_id = candidate.organization_id and job.id = candidate.subject_id;
        wants_follow_ups := coalesce(wants_follow_ups, true);
        wants_job_follow_ups := coalesce(wants_job_follow_ups, true);

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
      elsif candidate.subject_type = 'invoice' then
        -- Client reminders Part 5: one set of reminders per invoice (its root), ever, for each recipe.
        select invoice.client_id into invoice_client_id
        from public.invoices as invoice
        where invoice.organization_id = candidate.organization_id and invoice.id = candidate.subject_id;
        subject_present := private.automation_invoice_stop_outcome(candidate.organization_id, candidate.subject_id)
          is distinct from 'subject_gone';

        select preference.invoice_reminders into wants_follow_ups
        from public.client_communication_preferences as preference
        where preference.organization_id = candidate.organization_id
          and preference.client_id = invoice_client_id;
        wants_follow_ups := coalesce(wants_follow_ups, true);

        re_entry_key := 'invoice:' || coalesce(candidate.payload ->> 'root_invoice_id', candidate.subject_id::text);
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
        elsif not case
            when candidate.subject_type = 'job' and private.automation_sends_job_email(match_row.definition)
            then wants_job_follow_ups
            else wants_follow_ups
          end then
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
          -- Client reminders Part 5: likewise a due invoice reminder.
          elsif candidate.subject_type = 'invoice'
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
  -- client was removed or switched review requests off. Client reminders Part 6: a thank-you recipe checks the
  -- client's job follow-up switch and Do not disturb instead.
  if enrollment.subject_type = 'job' then
    stop_outcome := case
      when private.automation_sends_job_email(definition)
      then private.automation_job_follow_up_stop_outcome(enrollment.organization_id, enrollment.subject_id)
      else private.automation_job_stop_outcome(enrollment.organization_id, enrollment.subject_id)
    end;
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

  -- Client reminders Part 5: an overdue reminder stops once the invoice is paid, voided, written off, replaced
  -- or no longer overdue, or the client no longer wants invoice reminders.
  if enrollment.subject_type = 'invoice' then
    stop_outcome := private.automation_invoice_stop_outcome(enrollment.organization_id, enrollment.subject_id);
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
    -- Client reminders Part 5: an overdue invoice reminder email.
    elsif (step ->> 'key') = 'action.send_invoice_email' then
      return 'action_due_invoice_email';
    -- Client reminders Part 6: a job thank-you email.
    elsif (step ->> 'key') = 'action.send_job_email' then
      return 'action_due_job_email';
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



-- 3. The email -----------------------------------------------------------------------------------------------

-- Queues one thank-you to the client's email address. The authored copy is rendered by
-- private.render_automation_template with the job as it stands at sending time.
create or replace function private.enqueue_automation_job_email(
  p_organization_id uuid, p_job_id uuid, p_logical_send_key text, p_subject text, p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  job_row public.jobs;
  client_row public.clients;
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  alias public.communication_reply_aliases;
  intent public.communication_delivery_intents;
  stop_outcome text;
  business_name text;
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

  stop_outcome := private.automation_job_follow_up_stop_outcome(p_organization_id, p_job_id);
  if stop_outcome is not null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', stop_outcome);
  end if;

  select * into job_row from public.jobs where organization_id = p_organization_id and id = p_job_id;
  select * into client_row from public.clients
    where organization_id = p_organization_id and id = job_row.client_id and deleted_at is null for share;

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

  select * into rendered from private.render_automation_template(p_subject, p_body, jsonb_build_object(
    'customer_name', coalesce(nullif(btrim(client_row.display_name), ''), recipient.normalized_value),
    'business_name', coalesce(business_name, ''),
    'job_title', coalesce(nullif(btrim(job_row.title), ''), 'your job')));

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
revoke all on function private.enqueue_automation_job_email(uuid, uuid, text, text, text)
  from public, anon, authenticated;

-- Runs one claimed thank-you step in a single transaction, settling the work item like the visit reminder. Outside
-- business hours the step waits for the next opening, handing back the try the claim spent.
create or replace function public.perform_automation_job_email_effect(p_work_item_id uuid, p_claim_token uuid)
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
  opens_at timestamptz;
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
  if step is null or (step ->> 'type') <> 'action' or (step ->> 'key') <> 'action.send_job_email'
    or enrollment.subject_type <> 'job' then
    update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  opens_at := private.organization_next_open_at(enrollment.organization_id, now());
  if opens_at > now() then
    update private.automation_work_items
      set available_at = opens_at, due_at = opens_at, attempts = greatest(item.attempts - 1, 0),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_deferred';
  end if;

  result := private.enqueue_automation_job_email(
    enrollment.organization_id, enrollment.subject_id,
    'automation-job-follow-up:' || enrollment.id || ':' || item.step_index,
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

revoke all on function public.perform_automation_job_email_effect(uuid, uuid) from public, anon, authenticated;
grant execute on function public.perform_automation_job_email_effect(uuid, uuid) to service_role;
