-- Google review campaign Part 4B: the automatic ask.
--
-- Product truth: docs/google-review-campaign-owner-brief.md (§ Eligibility and enrolment, § How the automation
-- is set up). Following HighLevel's Workflow "Review Request" action, asking automatically is an Automations
-- recipe: When a job's work is completed -> Send a review request. The message, its style, the first-send delay
-- and the reminders all come from Review settings, as they do for a manual request.
--
-- 1. A new automation event, job.work_completed (subject 'job', source 'jobs'). It is emitted from the job's
--    own event log inside the same transaction: when a one-off job is closed (closing already requires every
--    visit to be completed, so a close is never a cancellation here), and on each completed visit of a
--    recurring job, carrying the job's completed-visit count. It is only emitted while the business has an
--    active recipe on this trigger, so businesses that never use it pay no worker wake per visit.
-- 2. Intake: a recurring job enrolls only at every Nth completed visit, where N is the recipe trigger's
--    recurring_every_visits (off when absent). One-off jobs enroll once per job; recurring jobs once per count.
--    A client who switched review requests off is recorded as declined, like quote follow-ups.
-- 3. Advance: a job enrollment stops when the job was reopened or is no longer eligible, or the client was
--    removed or opted out; the new action returns action_due_review_request.
-- 4. The effect: automation_review_request_draft gives the worker what it needs to write the first message
--    (the app mints the link); perform_automation_review_request_effect re-checks everything under the
--    enrollment and client locks and either creates the request through the same enqueue path and reminder
--    schedule as a manual request, or records a visible "not sent" request with the reason.
-- 5. The six-month rule counts only automatic requests that actually sent a message.
-- 6. A request that never sent reads as "not_sent"; summaries carry their origin; "already asked" in the
--    manual panel ignores requests that never sent.

-- 1. Constraints ---------------------------------------------------------------------------------------------

alter table private.automation_events
  drop constraint automation_events_event_type_check,
  add constraint automation_events_event_type_check check (event_type = any (array[
    'quote.delivery_succeeded', 'website_inquiry.received', 'job.work_completed'])),
  drop constraint automation_events_subject_type_check,
  add constraint automation_events_subject_type_check check (subject_type = any (array[
    'quote', 'form_submission', 'website_chat_session', 'job'])),
  drop constraint automation_events_source_module_check,
  add constraint automation_events_source_module_check check (source_module = any (array[
    'communications', 'forms', 'website_chat', 'jobs']));

alter table private.automation_enrollments
  drop constraint automation_enrollments_subject_type_check,
  add constraint automation_enrollments_subject_type_check check (subject_type = any (array[
    'quote', 'form_submission', 'website_chat_session', 'job']));

alter table public.review_requests
  drop constraint review_requests_stop_reason_check,
  add constraint review_requests_stop_reason_check check (stop_reason is null or stop_reason in (
    'cancelled', 'continued_to_google', 'feedback_submitted', 'not_delivered', 'not_sent',
    'client_removed', 'client_opted_out', 'job_not_eligible', 'no_contact', 'plan_changed', 'error',
    'recently_asked'
  ));

-- 2. Emitting job.work_completed ------------------------------------------------------------------------------

create or replace function private.emit_job_work_completed_event()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  job_row public.jobs;
  completed_count integer;
  incomplete_count integer;
begin
  -- Only while someone is listening: one probe of automation_recipes_active_trigger_idx.
  if not exists (
    select 1 from public.automation_recipes as recipe
    where recipe.organization_id = new.organization_id
      and recipe.status = 'active'
      and recipe.active_trigger_key = 'job.work_completed'
  ) then
    return null;
  end if;

  select * into job_row from public.jobs
  where organization_id = new.organization_id and id = new.job_id;
  if job_row.id is null then
    return null;
  end if;

  -- A one-off job asks when it is closed; a recurring job asks per completed visit (every Nth, decided at
  -- intake from the recipe). Each ignores the other's event.
  if new.event_type = 'job_closed' and job_row.job_type <> 'one_off' then
    return null;
  end if;
  if new.event_type = 'visit_completed' and job_row.job_type <> 'recurring' then
    return null;
  end if;

  select count(*) filter (where visit.completed_at is not null),
         count(*) filter (where visit.completed_at is null)
  into completed_count, incomplete_count
  from public.job_visits as visit
  where visit.organization_id = new.organization_id and visit.job_id = new.job_id;

  if completed_count = 0 then
    return null;
  end if;
  if new.event_type = 'job_closed' and incomplete_count > 0 then
    return null;
  end if;

  perform private.emit_automation_event(
    new.organization_id,
    'job.work_completed',
    'job',
    new.job_id,
    jsonb_strip_nulls(jsonb_build_object(
      'job_id', new.job_id,
      'client_id', job_row.client_id,
      'job_type', job_row.job_type,
      'completed_visit_count', completed_count,
      'visit_id', new.related_visit_id
    )),
    new.created_at,
    'jobs',
    new.id
  );
  return null;
end;
$$;

revoke all on function private.emit_job_work_completed_event() from public, anon, authenticated;

comment on function private.emit_job_work_completed_event() is
  'Emits job.work_completed from the job event log: a one-off job closed with every visit completed, or a completed visit of a recurring job with its completed-visit count. Only while the organization has an active recipe on that trigger.';

create trigger job_events_emit_work_completed
  after insert on public.job_events
  for each row
  when (new.event_type in ('job_closed', 'visit_completed'))
  execute function private.emit_job_work_completed_event();

-- 3. Job subject helpers ------------------------------------------------------------------------------------

-- A recurring job's event enrolls only at every Nth completed visit; N off (absent) means never.
create or replace function private.automation_job_trigger_matches(p_definition jsonb, p_payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  every_visits integer;
  visit_count integer;
begin
  if coalesce(p_payload ->> 'job_type', '') <> 'recurring' then
    return true;
  end if;
  every_visits := nullif(p_definition -> 'trigger' -> 'config' ->> 'recurring_every_visits', '')::integer;
  visit_count := nullif(p_payload ->> 'completed_visit_count', '')::integer;
  return every_visits is not null and every_visits >= 1 and visit_count is not null and visit_count >= 1
    and visit_count % every_visits = 0;
end;
$$;

revoke all on function private.automation_job_trigger_matches(jsonb, jsonb) from public, anon, authenticated;

-- Why a job enrollment must stop now, or null to carry on.
create or replace function private.automation_job_stop_outcome(p_organization_id uuid, p_job_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  job_row public.jobs;
  client_row public.clients;
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
  if exists (
    select 1 from public.client_communication_preferences as preference
    where preference.organization_id = p_organization_id and preference.client_id = job_row.client_id
      and not preference.review_requests
  ) then
    return 'client_opted_out';
  end if;
  return null;
end;
$$;

revoke all on function private.automation_job_stop_outcome(uuid, uuid) from public, anon, authenticated;

-- The client's main contact for a channel: the primary mobile number for a text, the primary email address
-- for an email.
create or replace function private.review_request_main_contact(
  p_organization_id uuid,
  p_client_id uuid,
  p_channel text
)
returns public.client_contact_methods
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select method.*
  from public.client_contact_methods as method
  where method.organization_id = p_organization_id
    and method.client_id = p_client_id
    and method.kind = case when p_channel = 'sms' then 'phone' else 'email' end
    and method.is_primary
  limit 1;
$$;

revoke all on function private.review_request_main_contact(uuid, uuid, text) from public, anon, authenticated;

-- 4. Intake and advance know the job subject ----------------------------------------------------------------

do $$
declare
  intake_def text := pg_get_functiondef('public.intake_automation_events(integer)'::regprocedure);
  advance_def text := pg_get_functiondef('public.advance_automation_work_item(uuid, uuid)'::regprocedure);
  old_subject text := $old$        re_entry_key := 'website_chat_session:' || candidate.subject_id::text;
      else$old$;
  new_subject text := $new$        re_entry_key := 'website_chat_session:' || candidate.subject_id::text;
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
      else$new$;
  old_condition text := $old$          elsif jsonb_array_length(coalesce(match_row.definition -> 'conditions', '[]'::jsonb)) > 0 then$old$;
  new_condition text := $new$          elsif candidate.subject_type = 'job'
            and not private.automation_job_trigger_matches(match_row.definition, candidate.payload) then
            match_outcome := 'condition_failed';
          elsif jsonb_array_length(coalesce(match_row.definition -> 'conditions', '[]'::jsonb)) > 0 then$new$;
  old_stop text := $old$  step_type := step ->> 'type';

  if step_type = 'wait' then$old$;
  new_stop text := $new$  -- Google review Part 4B: a job enrollment stops when the job was reopened or is no longer eligible, or the
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

  step_type := step ->> 'type';

  if step_type = 'wait' then$new$;
  old_action text := $old$    elsif (step ->> 'key') = 'action.send_customer_message' then
      return 'action_due_customer_message';$old$;
  new_action text := $new$    elsif (step ->> 'key') = 'action.send_customer_message' then
      return 'action_due_customer_message';
    -- Google review Part 4B: a job's review request.
    elsif (step ->> 'key') = 'action.send_review_request' then
      return 'action_due_review_request';$new$;
begin
  if position(old_subject in intake_def) = 0 or position(old_condition in intake_def) = 0
    or position(old_stop in advance_def) = 0 or position(old_action in advance_def) = 0 then
    raise exception 'automation intake/advance blocks not found; the functions changed since this migration was written';
  end if;
  execute replace(replace(intake_def, old_subject, new_subject), old_condition, new_condition);
  execute replace(replace(advance_def, old_stop, new_stop), old_action, new_action);
end;
$$;

comment on function public.advance_automation_work_item(uuid, uuid) is
  'Runs one claimed transition: rechecks enrollment, expiry, recipe state, and the domain stop conditions, then completes, schedules the next step from the original send, or returns action_due_email / action_due_sms / action_due_customer_message / action_due_review_request for the worker to run and settle the matching effect. A website inquiry stops on a delivered staff reply and returns paused_customer_reply before a customer-facing step the customer has since replied to; a job stops when reopened or no longer eligible. Claim-token guarded. Service role only.';

-- 5. Request status, summary and "already asked" ------------------------------------------------------------

do $$
declare
  status_def text := pg_get_functiondef('private.review_request_status(public.review_requests)'::regprocedure);
  summary_def text := pg_get_functiondef('private.review_request_summary(public.review_requests)'::regprocedure);
  context_def text := pg_get_functiondef('public.get_review_request_context(uuid, uuid, uuid, uuid)'::regprocedure);
  old_status text := $old$    when p_request.cancelled_at is not null then 'cancelled'$old$;
  new_status text := $new$    when p_request.cancelled_at is not null then 'cancelled'
    -- An automatic request that was skipped: it never sent anything, and stop_reason says why.
    when p_request.stopped_at is not null and not exists (
      select 1 from public.review_request_messages as message
      where message.organization_id = p_request.organization_id and message.request_id = p_request.id
    ) then 'not_sent'$new$;
  old_summary text := $old$    'channel', p_request.channel,$old$;
  new_summary text := $new$    'origin', p_request.origin,
    'channel', p_request.channel,$new$;
  old_context text := $old$      where request.organization_id = p_organization_id and request.client_id = client_row.id
        and request.cancelled_at is null
    ),$old$;
  new_context text := $new$      where request.organization_id = p_organization_id and request.client_id = client_row.id
        and request.cancelled_at is null
        and exists (
          select 1 from public.review_request_messages as message
          where message.organization_id = request.organization_id and message.request_id = request.id
        )
    ),$new$;
begin
  if position(old_status in status_def) = 0 or position(old_summary in summary_def) = 0
    or position(old_context in context_def) = 0 then
    raise exception 'review request status/summary/context blocks not found; the functions changed since this migration was written';
  end if;
  execute replace(status_def, old_status, new_status);
  execute replace(summary_def, old_summary, new_summary);
  execute replace(context_def, old_context, new_context);
end;
$$;

-- 6. The effect ---------------------------------------------------------------------------------------------

-- What the worker needs to write the first message: the channel from the recipe step, the business's message
-- setup (null = UCRM's defaults, which live in the app) and the names to greet. Read-only; null when the claim
-- is no longer this caller's or the step is not a review request.
create or replace function public.automation_review_request_draft(p_work_item_id uuid, p_claim_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  step jsonb;
  channel text;
  job_row public.jobs;
  client_row public.clients;
  contact public.client_contact_methods;
  contact_name text;
  settings_row public.review_settings;
begin
  select * into item from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending';
  if item.id is null then
    return null;
  end if;
  select * into enrollment from private.automation_enrollments where id = item.enrollment_id;
  if enrollment.id is null or enrollment.subject_type <> 'job' then
    return null;
  end if;
  select version.definition -> 'steps' -> item.step_index into step
  from public.automation_recipe_versions as version where version.id = enrollment.recipe_version_id;
  if step ->> 'key' is distinct from 'action.send_review_request' then
    return null;
  end if;
  channel := coalesce(step -> 'config' ->> 'channel', 'sms');

  select * into job_row from public.jobs
  where organization_id = enrollment.organization_id and id = enrollment.subject_id;
  select * into client_row from public.clients
  where organization_id = enrollment.organization_id and id = job_row.client_id;
  contact := private.review_request_main_contact(enrollment.organization_id, job_row.client_id, channel);
  if contact.client_contact_id is not null then
    select nullif(btrim(concat_ws(' ', person.first_name, person.last_name)), '') into contact_name
    from public.client_contacts as person
    where person.organization_id = contact.organization_id and person.id = contact.client_contact_id;
  end if;
  select * into settings_row from public.review_settings where organization_id = enrollment.organization_id;

  return jsonb_build_object(
    'channel', channel,
    'business_name', (select name from public.organizations where id = enrollment.organization_id),
    -- Someone at the contact's own name is greeted by it; the client's own number by the client's.
    'customer_name', coalesce(contact_name, client_row.display_name, ''),
    'customer_first_name', coalesce(
      split_part(contact_name, ' ', 1),
      nullif(btrim(client_row.first_name), ''),
      split_part(coalesce(client_row.display_name, ''), ' ', 1)
    ),
    'message_styles', settings_row.message_styles,
    'request_plan', settings_row.request_plan
  );
end;
$$;

revoke all on function public.automation_review_request_draft(uuid, uuid) from public, anon, authenticated;
grant execute on function public.automation_review_request_draft(uuid, uuid) to service_role;

comment on function public.automation_review_request_draft(uuid, uuid) is
  'For a claimed automation review-request step: the channel, business name, customer names and the organization''s saved message styles and plan (null = app defaults). Read-only; null when the claim is lost. Service role only.';

-- Runs one claimed review-request step in a single transaction. Every re-check happens here, under the
-- enrollment lock and a per-client lock (so two jobs finishing together cannot both pass the six-month
-- rule). A request that can be sent is created and queued through the same path as a manual one and follows
-- the same reminder plan; one that cannot is recorded as not sent with its reason, for the contractor to see.
-- p_body_text is null when the app could not write a message (it then has nothing to send).
create or replace function public.perform_automation_review_request_effect(
  p_work_item_id uuid,
  p_claim_token uuid,
  p_style text,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_link_url text,
  p_token_hash bytea,
  p_first_send_delay_amount integer,
  p_first_send_delay_unit text,
  p_first_reminder_days integer
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
  channel text;
  stop_outcome text;
  job_row public.jobs;
  contact public.client_contact_methods;
  skip_reason text;
  skip_detail text;
  send_at timestamptz;
  request_row public.review_requests;
  intent public.communication_delivery_intents;
  first_send_at timestamptz;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;
  if p_style is null or p_style not in ('friendly', 'professional', 'short') then
    raise exception 'Choose a message style.' using errcode = 'check_violation';
  end if;
  if p_first_reminder_days is not null and p_first_reminder_days not between 1 and 60 then
    raise exception 'A reminder waits 1 to 60 days.' using errcode = 'check_violation';
  end if;
  if coalesce(p_first_send_delay_amount, 0) < 0
    or (p_first_send_delay_unit = 'hours' and p_first_send_delay_amount > 72)
    or (p_first_send_delay_unit = 'days' and p_first_send_delay_amount > 30)
    or (coalesce(p_first_send_delay_amount, 0) > 0 and p_first_send_delay_unit not in ('hours', 'days')) then
    raise exception 'The first message waits at most 72 hours or 30 days.' using errcode = 'check_violation';
  end if;

  select * into item from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending' for update;
  if not found then
    return 'claim_lost';
  end if;

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
  from public.automation_recipes as recipe
  join public.automation_recipe_versions as version on version.id = enrollment.recipe_version_id
  where recipe.id = enrollment.recipe_id;
  if recipe_status = 'paused' then
    update private.automation_work_items
    set available_at = now() + private.automation_retry_delay(item.attempts),
        claim_token = null, claimed_at = null
    where id = item.id;
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
  if step is null or step ->> 'type' <> 'action' or step ->> 'key' <> 'action.send_review_request'
    or enrollment.subject_type <> 'job' then
    update private.automation_work_items
    set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null
    where id = item.id;
    return 'action_cancelled';
  end if;
  channel := coalesce(step -> 'config' ->> 'channel', 'sms');

  -- Re-read at the moment of sending: the job was reopened, the client removed or opted out.
  stop_outcome := private.automation_job_stop_outcome(enrollment.organization_id, enrollment.subject_id);
  if stop_outcome is not null then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  select * into job_row from public.jobs
  where organization_id = enrollment.organization_id and id = enrollment.subject_id;

  -- One decision per client at a time, so the six-month rule holds when two jobs finish together.
  perform pg_advisory_xact_lock(hashtextextended('review_request_automatic:' || job_row.client_id::text, 0));

  contact := private.review_request_main_contact(enrollment.organization_id, job_row.client_id, channel);

  if not exists (
    select 1 from public.organizations where id = enrollment.organization_id and lifecycle_status = 'active'
  ) then
    skip_reason := 'not_sent';
    skip_detail := 'This business cannot send messages right now.';
  elsif not exists (
    select 1 from public.review_settings
    where organization_id = enrollment.organization_id and google_review_url is not null
  ) then
    skip_reason := 'not_sent';
    skip_detail := 'Add your Google review link in Review settings.';
  elsif exists (
    select 1 from public.review_requests as earlier
    where earlier.organization_id = enrollment.organization_id
      and earlier.client_id = job_row.client_id
      and earlier.origin = 'automation'
      and earlier.created_at > now() - interval '6 months'
      and exists (
        select 1 from public.review_request_messages as message
        where message.organization_id = earlier.organization_id and message.request_id = earlier.id
      )
  ) then
    skip_reason := 'recently_asked';
  elsif contact.id is null then
    skip_reason := 'no_contact';
    skip_detail := case when channel = 'sms' then 'This client has no main mobile number.'
                        else 'This client has no main email address.' end;
  elsif p_body_text is null then
    skip_reason := 'not_sent';
    skip_detail := 'The review message could not be written.';
  end if;

  if skip_reason is null then
    send_at := case
      when coalesce(p_first_send_delay_amount, 0) = 0 then null
      when p_first_send_delay_unit = 'hours' then now() + make_interval(hours => p_first_send_delay_amount)
      else private.review_request_days_later(enrollment.organization_id, now(), p_first_send_delay_amount)
    end;

    begin
      insert into public.review_requests (
        organization_id, client_id, job_id, created_by, channel, origin, style, contact_method_id
      )
      values (
        enrollment.organization_id, job_row.client_id, job_row.id, null, channel, 'automation', p_style, contact.id
      )
      returning * into request_row;

      intent := private.review_request_enqueue_message(
        request_row, 0::smallint, 'automated', p_subject, p_body_text, p_body_html, p_link_url, p_token_hash,
        send_at, null, 'review_request:automation:' || enrollment.id);
    exception
      -- The refusals the send path words for the contractor: consent or STOP, suppression, balance, a sender
      -- or number not set up, length. The request is recorded as not sent; anything else is a fault and the
      -- worker retries the step.
      when sqlstate 'P0001' or sqlstate '23514' or sqlstate '23503' or sqlstate '55000' or sqlstate 'P0402' then
        skip_reason := 'not_sent';
        skip_detail := left(sqlerrm, 500);
    end;
  end if;

  if skip_reason is not null then
    insert into public.review_requests (
      organization_id, client_id, job_id, created_by, channel, origin, style, contact_method_id,
      stopped_at, stop_reason, stop_detail
    )
    values (
      enrollment.organization_id, job_row.client_id, job_row.id, null, channel, 'automation', p_style, contact.id,
      now(), skip_reason, skip_detail
    );
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'review_request_' || skip_reason, stopped_at = now()
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', last_error_code = left('review_request_' || skip_reason, 100),
        claim_token = null, claimed_at = null
    where id = item.id;
    return 'action_cancelled';
  end if;

  -- The same first-reminder estimate as a manual request; the reminder re-counts from the actual send.
  if p_first_reminder_days is not null then
    select outbox.available_at into first_send_at
    from public.communication_outbox_events as outbox where outbox.delivery_intent_id = intent.id;
    update public.review_requests
    set next_reminder_at = private.review_request_days_later(
      enrollment.organization_id, coalesce(first_send_at, send_at, now()), p_first_reminder_days)
    where id = request_row.id;
  end if;

  update private.automation_enrollments
  set current_step_index = item.step_index + 1,
      customer_messages_sent = customer_messages_sent + 1
  where id = enrollment.id;
  update private.automation_work_items
  set state = 'done', claim_token = null, claimed_at = null where id = item.id;
  insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at)
  values (enrollment.organization_id, enrollment.id, item.step_index + 1, now(), now())
  on conflict (enrollment_id, step_index) do nothing;
  return 'action_sent';
end;
$$;

revoke all on function public.perform_automation_review_request_effect(uuid, uuid, text, text, text, text, text, bytea, integer, text, integer) from public, anon, authenticated;
grant execute on function public.perform_automation_review_request_effect(uuid, uuid, text, text, text, text, text, bytea, integer, text, integer) to service_role;

comment on function public.perform_automation_review_request_effect(uuid, uuid, text, text, text, text, text, bytea, integer, text, integer) is
  'Runs one claimed automatic review request: re-checks the enrollment, recipe, job, client, Google link, six-month rule and main contact, then creates the request and queues its first message through the review request path with the plan''s first reminder, or records a not-sent request with its reason. Claim-token guarded. Service role only.';
