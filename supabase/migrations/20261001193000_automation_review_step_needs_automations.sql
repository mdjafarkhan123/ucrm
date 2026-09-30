-- Package builder P14: an automation's "Send a review request" step stops when the plan drops Automations.
--
-- Every other automation message (quote email and text, inquiry reply) already re-checks the Automations
-- feature at the moment of sending. The review step checked only Reviews, so a run already under way could
-- still send after Automations was switched off. It now records the request as not sent with a reason, the
-- same way it does when Reviews is off. Body is the 20261001160000 definition with only that check added.

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
  elsif not private.organization_has_automations_feature(enrollment.organization_id, now()) then
    skip_reason := 'not_sent';
    skip_detail := 'Automations are not part of your plan.';
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
