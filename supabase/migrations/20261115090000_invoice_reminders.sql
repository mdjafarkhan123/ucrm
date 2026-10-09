-- Client reminders Part 5: overdue invoice reminders.
--
-- Product truth: docs/client-reminders-behavior-contract.md § Overdue invoice reminders and § Customer messages:
-- shared rules. Following Jobber's Invoice Follow-ups: up to two reminders after the due date, sent shortly after
-- 8 am local time, each carrying the invoice's pay link and balance.
--
-- 1. A new automation trigger, invoice.past_due (subject type invoice, source 'invoices'). Its config holds
--    { days_after_due: 1-90 }. The reminder time is 8 am local on due date + that many days.
-- 2. emit_due_invoice_reminders runs at the start of every automation worker wake, next to the visit reminders:
--    for each active recipe on the trigger it emits one event per sent, unpaid invoice whose reminder time has
--    arrived, only when that time came after both the invoice was sent and the recipe was turned on. The event's
--    source id is derived from the recipe and the invoice's root, so a corrected (replacement) bill never starts
--    the reminders again. The event happens at the reminder time, so a later "wait N days" also lands at 8 am.
-- 3. Intake enrolls a due invoice only into the recipe that found it; a client whose "Invoice reminders" switch
--    is off is recorded as declined. Advance stops when the invoice is paid, marked received, voided, written
--    off, replaced or no longer overdue, or the client was removed, switched invoice reminders off or is on Do
--    not disturb.
-- 4. A new action, action.send_invoice_email, sends through the Communications outbox. The worker mints a fresh
--    pay link for each recipient (the client's email and their billing contact, as "Send invoice" does); earlier
--    links keep working.

-- 1. Constraints ---------------------------------------------------------------------------------------------

alter table private.automation_events
  drop constraint automation_events_event_type_check,
  add constraint automation_events_event_type_check check (event_type = any (array[
    'quote.delivery_succeeded', 'website_inquiry.received', 'job.work_completed', 'appointment.reminder_due',
    'appointment.booked', 'appointment.rescheduled', 'invoice.past_due'])),
  drop constraint automation_events_subject_type_check,
  add constraint automation_events_subject_type_check check (subject_type = any (array[
    'quote', 'form_submission', 'website_chat_session', 'job', 'job_visit', 'assessment', 'invoice'])),
  drop constraint automation_events_source_module_check,
  add constraint automation_events_source_module_check check (source_module = any (array[
    'communications', 'forms', 'website_chat', 'jobs', 'scheduling', 'invoices']));

alter table private.automation_enrollments
  drop constraint automation_enrollments_subject_type_check,
  add constraint automation_enrollments_subject_type_check check (subject_type = any (array[
    'quote', 'form_submission', 'website_chat_session', 'job', 'job_visit', 'assessment', 'invoice']));

-- 2. Invoice helpers -----------------------------------------------------------------------------------------

-- 8 am local time, the given number of days after the due date.
create or replace function private.invoice_reminder_at(p_due_date date, p_days_after integer, p_timezone text)
returns timestamptz
language sql
stable
set search_path = pg_catalog
as $$
  select ((p_due_date + p_days_after) + time '08:00') at time zone p_timezone;
$$;

revoke all on function private.invoice_reminder_at(date, integer, text) from public, anon, authenticated;

-- Why an overdue reminder for this invoice must not go out now, or null to carry on. A draft, or a bill that was
-- recorded but never sent or marked sent, is never chased.
create or replace function private.automation_invoice_stop_outcome(p_organization_id uuid, p_invoice_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  invoice_row public.invoices;
  client_row public.clients;
  preference public.client_communication_preferences;
begin
  select * into invoice_row from public.invoices
  where organization_id = p_organization_id and id = p_invoice_id;
  if invoice_row.id is null then
    return 'subject_gone';
  end if;
  if invoice_row.replaced_at is not null then
    return 'invoice_replaced';
  end if;
  if invoice_row.voided_at is not null then
    return 'invoice_voided';
  end if;
  if invoice_row.written_off_at is not null then
    return 'invoice_written_off';
  end if;
  if invoice_row.issued_at is null then
    return 'invoice_not_sent';
  end if;
  if invoice_row.marked_received_at is not null
    or private.invoice_allocated_minor(p_organization_id, invoice_row.id) >= invoice_row.total_minor then
    return 'invoice_paid';
  end if;
  if invoice_row.due_date >= private.organization_today(p_organization_id) then
    return 'invoice_not_overdue';
  end if;

  select * into client_row from public.clients
  where organization_id = p_organization_id and id = invoice_row.client_id;
  if client_row.id is null or client_row.deleted_at is not null then
    return 'client_removed';
  end if;

  select * into preference from public.client_communication_preferences
  where organization_id = p_organization_id and client_id = client_row.id;
  if preference.invoice_reminders is false then
    return 'client_opted_out';
  end if;
  if preference.contact_policy = 'do_not_disturb' then
    return 'do_not_disturb';
  end if;
  return null;
end;
$$;

revoke all on function private.automation_invoice_stop_outcome(uuid, uuid) from public, anon, authenticated;

-- 3. Finding due reminders -----------------------------------------------------------------------------------

-- Keyed by the invoice's root, so the original bill and its corrections share one set of reminders.
create or replace function private.invoice_reminder_source_id(p_recipe_id uuid, p_root_invoice_id uuid)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select md5('invoice:' || p_recipe_id::text || ':' || p_root_invoice_id::text)::uuid;
$$;

revoke all on function private.invoice_reminder_source_id(uuid, uuid) from public, anon, authenticated;

-- Called by the automation worker at the start of each wake. Returns how many reminders it found due. Only due
-- dates from the recipe's activation onward are read (invoices_receivable_due_idx), so turning the automation on
-- never chases old debts.
create or replace function public.emit_due_invoice_reminders(p_limit integer default 200)
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
        (version.definition -> 'trigger' -> 'config' ->> 'days_after_due')::integer as days_after,
        private.appointment_timezone(recipe.organization_id) as timezone
      from public.automation_recipes as recipe
      join public.automation_recipe_versions as version on version.id = recipe.current_version_id
      where recipe.status = 'active' and recipe.active_trigger_key = 'invoice.past_due'
    ),
    candidates as (
      select recipes.recipe_id, recipes.organization_id, invoice.id as invoice_id, invoice.root_invoice_id,
        private.invoice_reminder_at(invoice.due_date, recipes.days_after, recipes.timezone) as remind_at,
        invoice.issued_at, recipes.activated_at
      from recipes
      join public.invoices as invoice
        on invoice.organization_id = recipes.organization_id
        and invoice.is_effective_receivable
        and invoice.due_date >= (recipes.activated_at at time zone recipes.timezone)::date - recipes.days_after - 1
        and invoice.due_date <= (now() at time zone recipes.timezone)::date - recipes.days_after
      where invoice.issued_at is not null
        and invoice.marked_received_at is null
    )
    select candidates.*
    from candidates
    where candidates.remind_at <= now()
      and candidates.remind_at >= candidates.issued_at
      and candidates.remind_at >= candidates.activated_at
      and private.automation_invoice_stop_outcome(candidates.organization_id, candidates.invoice_id) is null
      and not exists (
        select 1 from private.automation_events as event
        where event.source_module = 'invoices'
          and event.source_event_id = private.invoice_reminder_source_id(candidates.recipe_id, candidates.root_invoice_id)
          and event.event_type = 'invoice.past_due'
      )
    order by candidates.remind_at
    limit p_limit
  loop
    perform private.emit_automation_event(
      due.organization_id, 'invoice.past_due', 'invoice', due.invoice_id,
      jsonb_build_object('recipe_id', due.recipe_id, 'remind_at', due.remind_at,
        'root_invoice_id', due.root_invoice_id),
      due.remind_at, 'invoices', private.invoice_reminder_source_id(due.recipe_id, due.root_invoice_id));
    emitted := emitted + 1;
  end loop;

  return emitted;
end;
$$;

revoke all on function public.emit_due_invoice_reminders(integer) from public, anon, authenticated;
grant execute on function public.emit_due_invoice_reminders(integer) to service_role;

-- 4. Intake and advance know invoices ------------------------------------------------------------------------

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


-- 5. The email -----------------------------------------------------------------------------------------------

-- Queues one reminder to one recipient with its own pay link. The authored copy is rendered by
-- private.render_automation_template; {{invoice_link}} is left for last so the HTML gets a real link.
create or replace function private.enqueue_automation_invoice_email_to(
  p_invoice public.invoices, p_client public.clients, p_recipient public.client_contact_methods,
  p_sender_id uuid, p_logical_send_key text, p_subject text, p_body text, p_values jsonb,
  p_invoice_url text, p_invoice_token_hash bytea
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  intent public.communication_delivery_intents;
  alias public.communication_reply_aliases;
  rendered record;
  link_html text;
begin
  select * into intent from public.communication_delivery_intents
    where organization_id = p_invoice.organization_id and logical_send_key = p_logical_send_key;
  if intent.id is not null then
    return intent;
  end if;

  select * into rendered from private.render_automation_template(p_subject, p_body,
    p_values || jsonb_build_object('customer_name',
      coalesce(nullif(btrim(p_client.display_name), ''), p_recipient.normalized_value)));
  link_html := '<a href="' || private.html_escape(p_invoice_url) || '">'
    || private.html_escape(p_invoice_url) || '</a>';

  alias := public.ensure_communication_reply_alias(
    p_invoice.organization_id, p_sender_id, p_client.id, p_recipient.id);

  insert into public.invoice_access_links
    (organization_id, invoice_id, recipient_name, recipient_email, token_hash, issued_by)
    values (p_invoice.organization_id, p_invoice.id,
      left(coalesce(nullif(btrim(p_client.display_name), ''), p_recipient.normalized_value), 200),
      p_recipient.normalized_value, p_invoice_token_hash, null);

  begin
    insert into public.communication_delivery_intents
      (organization_id, client_id, client_contact_method_id, invoice_id, logical_send_key, recipient_email,
       subject, html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by)
      values (p_invoice.organization_id, p_client.id, p_recipient.id, p_invoice.id, p_logical_send_key,
       p_recipient.normalized_value,
       replace(rendered.subject, '{{invoice_link}}', p_invoice_url),
       replace(rendered.html_content, '{{invoice_link}}', link_html),
       replace(rendered.text_content, '{{invoice_link}}', p_invoice_url),
       'automated', 'essential', p_sender_id, alias.id, null)
      returning * into intent;
  exception when unique_violation then
    select * into intent from public.communication_delivery_intents
      where organization_id = p_invoice.organization_id and logical_send_key = p_logical_send_key;
    return intent;
  end;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
    values (intent.organization_id, intent.id);
  return intent;
end;
$$;

revoke all on function private.enqueue_automation_invoice_email_to(
  public.invoices, public.clients, public.client_contact_methods, uuid, text, text, text, jsonb, text, bytea
) from public, anon, authenticated;

create or replace function private.enqueue_automation_invoice_email(
  p_organization_id uuid, p_invoice_id uuid, p_logical_send_key text, p_subject text, p_body text,
  p_invoice_url text, p_invoice_token_hash bytea, p_billing_invoice_url text, p_billing_invoice_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  stop_outcome text;
  invoice_row public.invoices;
  client_row public.clients;
  recipient public.client_contact_methods;
  billing_recipient public.client_contact_methods;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  intent public.communication_delivery_intents;
  billing_intent public.communication_delivery_intents;
  business_name text;
  balance_minor bigint;
  values_json jsonb;
begin
  select * into intent from public.communication_delivery_intents
    where organization_id = p_organization_id and logical_send_key = p_logical_send_key || ':primary';
  if intent.id is not null then
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end if;

  if coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_email_content');
  end if;
  if p_invoice_url !~ '^https?://[^[:space:]]+$' or p_invoice_token_hash is null
    or octet_length(p_invoice_token_hash) <> 32 then
    raise exception 'The invoice link is not available.' using errcode = 'check_violation';
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

  -- Checked again at the moment of sending: a payment, a void or a switch turned off since means no email.
  select * into invoice_row from public.invoices
    where organization_id = p_organization_id and id = p_invoice_id for share;
  stop_outcome := private.automation_invoice_stop_outcome(p_organization_id, p_invoice_id);
  if stop_outcome is not null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', stop_outcome);
  end if;

  select * into client_row from public.clients
    where organization_id = p_organization_id and id = invoice_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = p_organization_id and client_id = client_row.id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if client_row.id is null or recipient.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'no_email_address');
  end if;
  select * into billing_recipient from public.client_contact_methods
    where organization_id = p_organization_id and client_id = client_row.id and kind = 'email'
      and is_billing_contact and id <> recipient.id for share;

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
  balance_minor := invoice_row.total_minor
    - private.invoice_allocated_minor(p_organization_id, invoice_row.id);

  values_json := jsonb_build_object(
    'business_name', coalesce(business_name, ''),
    'invoice_number', '#' || invoice_row.invoice_number::text,
    'invoice_balance', private.format_minor(balance_minor, invoice_row.currency_code),
    'invoice_due_date', to_char(invoice_row.due_date, 'FMMonth FMDD, YYYY'));

  intent := private.enqueue_automation_invoice_email_to(
    invoice_row, client_row, recipient, sender.id, p_logical_send_key || ':primary',
    p_subject, p_body, values_json, p_invoice_url, p_invoice_token_hash);

  -- The billing contact is a different address by the table's own rule, so it never gets the same email twice.
  if billing_recipient.id is not null and p_billing_invoice_url ~ '^https?://[^[:space:]]+$'
    and octet_length(p_billing_invoice_token_hash) = 32 then
    billing_intent := private.enqueue_automation_invoice_email_to(
      invoice_row, client_row, billing_recipient, sender.id, p_logical_send_key || ':billing',
      p_subject, p_body, values_json, p_billing_invoice_url, p_billing_invoice_token_hash);
  end if;

  perform private.record_invoice_event(
    invoice_row.organization_id, invoice_row.id, invoice_row.invoice_number, invoice_row.client_id,
    'invoice.reminder_sent', null, invoice_row.revision, null,
    jsonb_strip_nulls(jsonb_build_object(
      'delivery_intent_id', intent.id, 'recipient_email', recipient.normalized_value,
      'billing_delivery_intent_id', billing_intent.id,
      'billing_recipient_email', billing_recipient.normalized_value)));

  return jsonb_build_object('status', 'sent', 'reason', 'enqueued', 'intent_id', intent.id);
end;
$$;

revoke all on function private.enqueue_automation_invoice_email(uuid, uuid, text, text, text, text, bytea, text, bytea)
  from public, anon, authenticated;

-- Runs one claimed reminder email step in a single transaction, settling the work item like the visit reminder.
create or replace function public.perform_automation_invoice_email_effect(
  p_work_item_id uuid, p_claim_token uuid, p_invoice_url text, p_invoice_token_hash bytea,
  p_billing_invoice_url text default null, p_billing_invoice_token_hash bytea default null
)
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
  if step is null or (step ->> 'type') <> 'action' or (step ->> 'key') <> 'action.send_invoice_email'
    or enrollment.subject_type <> 'invoice' then
    update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  result := private.enqueue_automation_invoice_email(
    enrollment.organization_id, enrollment.subject_id,
    'automation-invoice-reminder:' || enrollment.id || ':' || item.step_index,
    step -> 'config' ->> 'subject', step -> 'config' ->> 'body',
    p_invoice_url, p_invoice_token_hash, p_billing_invoice_url, p_billing_invoice_token_hash);
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

revoke all on function public.perform_automation_invoice_email_effect(uuid, uuid, text, bytea, text, bytea)
  from public, anon, authenticated;
grant execute on function public.perform_automation_invoice_email_effect(uuid, uuid, text, bytea, text, bytea)
  to service_role;
