-- Package builder P12: review requests switch off cleanly with the package.
--
-- Manual review requests are already refused by the app when the plan leaves out `growth.reputation`
-- (the `reviews.` permissions ride on it). The two background senders did not look at the plan: an
-- automation's "Send a review request" step and the reminder sequence. Both now re-check the capability at
-- the moment of sending and record the request as not sent, with the reason the contractor sees, exactly as
-- they already do for a business that cannot send messages. The customer's link to an existing request keeps
-- working, so nobody who already answered is shown an error.
--
-- Each function body is its current definition with only the capability check added.

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
  elsif not private.organization_has_capability(enrollment.organization_id, 'growth.reputation', now()) then
    skip_reason := 'not_sent';
    skip_detail := 'Review requests are not part of your plan.';
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

create or replace function public.send_review_reminder(
  p_request_id uuid,
  p_claim_token uuid,
  p_slot smallint,
  p_wait_days integer,
  p_next_wait_days integer,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_link_url text,
  p_token_hash bytea
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  request_row public.review_requests;
  previous_intent public.communication_delivery_intents;
  previous_outbox public.communication_outbox_events;
  due_at timestamptz;
  intent public.communication_delivery_intents;
  send_at timestamptz;
begin
  select * into request_row from public.review_requests
  where id = p_request_id and reminder_claim_token = p_claim_token
  for update;
  if request_row.id is null then
    return 'claim_lost';
  end if;

  if request_row.cancelled_at is not null or request_row.stopped_at is not null then
    perform private.review_request_stop(request_row.id, 'cancelled', null);
    return 'stopped';
  end if;
  if request_row.continued_to_google_at is not null then
    perform private.review_request_stop(request_row.id, 'continued_to_google', null);
    return 'stopped';
  end if;
  if request_row.feedback_submitted_at is not null then
    perform private.review_request_stop(request_row.id, 'feedback_submitted', null);
    return 'stopped';
  end if;

  -- The slot the claim computed must still be the next one.
  if p_slot is distinct from (
    select coalesce(max(message.slot), -1) + 1 from public.review_request_messages as message
    where message.organization_id = request_row.organization_id and message.request_id = request_row.id
  ) or p_slot < 1 then
    update public.review_requests set reminder_claim_token = null, next_reminder_at = now()
    where id = request_row.id;
    return 'claim_lost';
  end if;

  if p_body_text is null then
    perform private.review_request_stop(request_row.id, 'plan_changed',
      'The reminder plan in Review settings no longer includes this reminder.');
    return 'stopped';
  end if;
  if p_wait_days is null or p_wait_days not between 1 and 60
    or (p_next_wait_days is not null and p_next_wait_days not between 1 and 60) then
    raise exception 'A reminder waits 1 to 60 days.' using errcode = 'check_violation';
  end if;

  -- The previous message must have gone out, and the wait counts from when it did.
  select intent_row.* into previous_intent
  from public.review_request_messages as message
  join public.communication_delivery_intents as intent_row on intent_row.id = message.delivery_intent_id
  where message.organization_id = request_row.organization_id and message.request_id = request_row.id
    and message.slot = p_slot - 1;
  if previous_intent.id is null
    or previous_intent.status in ('failed', 'cancelled')
    or previous_intent.delivery_outcome in ('hard_bounce', 'complaint', 'blocked', 'unsubscribed', 'sms_undelivered', 'sms_failed') then
    perform private.review_request_stop(request_row.id, 'not_delivered', previous_intent.failure_message);
    return 'stopped';
  end if;
  if previous_intent.accepted_at is null then
    select * into previous_outbox from public.communication_outbox_events where delivery_intent_id = previous_intent.id;
    update public.review_requests
    set reminder_claim_token = null, reminder_attempts = 0,
        next_reminder_at = greatest(coalesce(previous_outbox.available_at, now()), now()) + interval '30 minutes'
    where id = request_row.id;
    return 'waiting';
  end if;
  due_at := private.review_request_days_later(request_row.organization_id, previous_intent.accepted_at, p_wait_days);
  if due_at > now() then
    update public.review_requests
    set reminder_claim_token = null, reminder_attempts = 0, next_reminder_at = due_at
    where id = request_row.id;
    return 'waiting';
  end if;

  -- Still someone the business may remind about this work.
  if not exists (
    select 1 from public.clients
    where organization_id = request_row.organization_id and id = request_row.client_id and deleted_at is null
  ) then
    perform private.review_request_stop(request_row.id, 'client_removed', null);
    return 'stopped';
  end if;
  if exists (
    select 1 from public.client_communication_preferences as preference
    where preference.organization_id = request_row.organization_id and preference.client_id = request_row.client_id
      and not preference.review_requests
  ) then
    perform private.review_request_stop(request_row.id, 'client_opted_out', null);
    return 'stopped';
  end if;
  if request_row.job_id is not null
    and not private.review_request_job_is_eligible(request_row.organization_id, request_row.job_id) then
    perform private.review_request_stop(request_row.id, 'job_not_eligible', null);
    return 'stopped';
  end if;
  if not exists (
    select 1 from public.organizations where id = request_row.organization_id and lifecycle_status = 'active'
  ) then
    perform private.review_request_stop(request_row.id, 'not_sent', 'This business cannot send messages right now.');
    return 'stopped';
  end if;
  if not private.organization_has_capability(request_row.organization_id, 'growth.reputation', now()) then
    perform private.review_request_stop(request_row.id, 'not_sent', 'Review requests are not part of your plan.');
    return 'stopped';
  end if;
  if request_row.contact_method_id is null or not exists (
    select 1 from public.client_contact_methods
    where organization_id = request_row.organization_id and client_id = request_row.client_id
      and id = request_row.contact_method_id
  ) then
    perform private.review_request_stop(request_row.id, 'no_contact', null);
    return 'stopped';
  end if;

  begin
    intent := private.review_request_enqueue_message(
      request_row, p_slot, 'automated', p_subject, p_body_text, p_body_html, p_link_url, p_token_hash, null, null,
      'review_request:' || request_row.id || ':reminder:' || p_slot);
  exception
    -- The refusals the send path words for the contractor: consent or STOP, suppression, balance, a sender
    -- or number not set up, length. They end the sequence; anything else is a fault and is retried.
    when sqlstate 'P0001' or sqlstate '23514' or sqlstate '23503' or sqlstate '55000' or sqlstate 'P0402' then
      perform private.review_request_stop(request_row.id, 'not_sent', sqlerrm);
      return 'stopped';
  end;

  select outbox.available_at into send_at
  from public.communication_outbox_events as outbox where outbox.delivery_intent_id = intent.id;

  update public.review_requests
  set reminder_claim_token = null,
      reminder_attempts = 0,
      next_reminder_at = case when p_next_wait_days is null then null
        else private.review_request_days_later(request_row.organization_id, coalesce(send_at, now()), p_next_wait_days) end
  where id = request_row.id;

  return 'sent';
end;
$$;

revoke all on function public.perform_automation_review_request_effect(uuid, uuid, text, text, text, text, text, bytea, integer, text, integer) from public, anon, authenticated;
grant execute on function public.perform_automation_review_request_effect(uuid, uuid, text, text, text, text, text, bytea, integer, text, integer) to service_role;
revoke all on function public.send_review_reminder(uuid, uuid, smallint, integer, integer, text, text, text, text, bytea) from public, anon, authenticated;
grant execute on function public.send_review_reminder(uuid, uuid, smallint, integer, integer, text, text, text, text, bytea) to service_role;
