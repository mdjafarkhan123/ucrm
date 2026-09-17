-- CRM launch readiness Part 4, Stage 3: a website inquiry's follow-up reacts to real conversation.
--
-- Established pattern (docs/research/website-speed-to-lead-patterns-2026-09-17.md, "Cancel when a human
-- replies"): HighLevel keeps two separate signals and warns against confusing them.
--   * User Replied — a staff message that was actually delivered. Workflow/automation messages never count.
--     Here it STOPS the enrollment: a person has taken over, so the pending follow-up would talk over them.
--   * Stop on Response — the contact replying to a message FROM THAT WORKFLOW. Here it PAUSES the enrollment
--     before its next customer-facing step, keeping the exact due time so staff can Resume, Skip next or Stop
--     (the existing 6D controls). Internal steps (waits) are not paused.
-- Before the enrollment has sent anything to the customer, a second visitor message is not a reply: a chat
-- visitor adding detail must not silence the speed-to-lead follow-up nobody has answered yet.
--
-- Quote enrollments are unchanged. Deliberately NOT here: the team alert on a reply-pause (Stage 4 builds
-- staff alerts) and setting customer_reply_after when an inquiry's customer message is accepted (Stage 5 owns
-- that effect and must set it, and must call both checks below before accepting a send).

-- ---------------------------------------------------------------------------------------------------
-- 1. Where "a later customer reply" starts counting.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_enrollments
  add column customer_reply_after timestamptz;

comment on column private.automation_enrollments.customer_reply_after is
  'Customer messages created after this moment count as a reply that pauses customer-facing steps. Null until '
  'the enrollment first reaches the customer. A reply-pause moves it to that reply, so Resume is not undone by '
  'the same reply.';

-- ---------------------------------------------------------------------------------------------------
-- 2. The inquiry's client, read from current truth (a chat's identity can resolve after it started).
-- ---------------------------------------------------------------------------------------------------
create function private.automation_inquiry_client_id(
  p_organization_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  out subject_found boolean,
  out client_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
begin
  subject_found := false;
  if p_subject_type = 'form_submission' then
    select true, nullif(s.result ->> 'client_id', '')::uuid into subject_found, client_id
    from private.form_submissions as s
    where s.organization_id = p_organization_id and s.id = p_subject_id;
  elsif p_subject_type = 'website_chat_session' then
    select true, s.client_id into subject_found, client_id
    from public.website_chat_sessions as s
    where s.organization_id = p_organization_id and s.id = p_subject_id;
  end if;
  subject_found := coalesce(subject_found, false);
end;
$$;

revoke all on function private.automation_inquiry_client_id(uuid, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 3. Stop: the inquiry is gone, or a staff member's reply was delivered after the inquiry arrived.
-- ---------------------------------------------------------------------------------------------------
create function private.automation_inquiry_stop_outcome(
  p_organization_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_since timestamptz
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  subject record;
begin
  select * into subject from private.automation_inquiry_client_id(p_organization_id, p_subject_type, p_subject_id);
  if not subject.subject_found then
    return 'inquiry_not_found';
  end if;

  -- A staff chat message is stored only once it is in the visitor's thread, so a stored one is delivered.
  if p_subject_type = 'website_chat_session' and exists (
    select 1 from public.website_chat_messages as m
    where m.session_id = p_subject_id and m.organization_id = p_organization_id
      and m.sender_type = 'staff' and m.delivery_state = 'sent' and m.created_at >= p_since
  ) then
    return 'staff_replied';
  end if;

  if subject.client_id is not null and (
    exists (
      select 1 from public.website_chat_messages as m
      where m.organization_id = p_organization_id and m.client_id = subject.client_id
        and m.sender_type = 'staff' and m.delivery_state = 'sent' and m.created_at >= p_since
    )
    -- A staff-sent email or text counts only once the provider confirmed delivery; accepted or unknown is not
    -- proof a person was reached. Automated sends (send_kind 'automated') never count.
    or exists (
      select 1 from public.communication_delivery_intents as i
      where i.organization_id = p_organization_id and i.client_id = subject.client_id
        and i.created_at >= p_since and i.send_kind = 'manual'
        and i.delivery_outcome in ('delivered', 'sms_delivered')
    )
  ) then
    return 'staff_replied';
  end if;

  return null;
end;
$$;

comment on function private.automation_inquiry_stop_outcome(uuid, text, uuid, timestamptz) is
  'Null while a website-inquiry enrollment may continue, else why it stops: inquiry_not_found, or '
  'staff_replied (a delivered staff chat message, email or text to that inquiry since p_since). Used by the '
  'worker transition and, from Stage 5, by the customer-message send.';

revoke all on function private.automation_inquiry_stop_outcome(uuid, text, uuid, timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 4. Pause: the latest customer reply after p_after, or null.
-- ---------------------------------------------------------------------------------------------------
create function private.automation_inquiry_customer_reply_at(
  p_organization_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_after timestamptz
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  subject record;
  latest timestamptz;
  candidate timestamptz;
begin
  -- Nothing has been sent to the customer yet, so nothing can be a reply to it.
  if p_after is null then
    return null;
  end if;

  select * into subject from private.automation_inquiry_client_id(p_organization_id, p_subject_type, p_subject_id);
  if not subject.subject_found then
    return null;
  end if;

  if p_subject_type = 'website_chat_session' then
    select max(m.created_at) into latest
    from public.website_chat_messages as m
    where m.session_id = p_subject_id and m.organization_id = p_organization_id
      and m.sender_type = 'visitor' and m.created_at > p_after;
  end if;

  if subject.client_id is not null then
    select max(m.created_at) into candidate
    from public.website_chat_messages as m
    where m.organization_id = p_organization_id and m.client_id = subject.client_id
      and m.sender_type = 'visitor' and m.created_at > p_after;
    latest := greatest(latest, candidate);

    -- Only a real, accepted reply: not an out-of-office, bounce notice, detected loop, or unresolved sender.
    select max(m.created_at) into candidate
    from public.communication_inbound_messages as m
    where m.organization_id = p_organization_id and m.client_id = subject.client_id
      and m.created_at > p_after and m.message_kind = 'reply' and m.review_status = 'accepted'
      and not m.automation_suppressed;
    latest := greatest(latest, candidate);
  end if;

  return latest;
end;
$$;

comment on function private.automation_inquiry_customer_reply_at(uuid, text, uuid, timestamptz) is
  'The newest customer chat, email or text reply to a website inquiry created after p_after, or null. Null '
  'p_after (nothing sent to the customer yet) is always null.';

revoke all on function private.automation_inquiry_customer_reply_at(uuid, text, uuid, timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 5. The transition applies both rules to inquiry enrollments.
-- ---------------------------------------------------------------------------------------------------
-- Replaced from 20261005110000. The only changes are marked "Stage 3".
create or replace function public.advance_automation_work_item(
  p_work_item_id uuid,
  p_claim_token uuid
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

    if step ->> 'type' = 'action' and step ->> 'key' in ('action.send_email', 'action.send_sms') then
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

comment on function public.advance_automation_work_item(uuid, uuid) is
  'Runs one claimed transition: rechecks enrollment, expiry, recipe state, and the domain stop conditions, '
  'then completes, schedules the next step from the original send, or returns action_due_email / '
  'action_due_sms for the worker to run and settle the matching effect. A website inquiry stops on a '
  'delivered staff reply and returns paused_customer_reply before a customer-facing step the customer has '
  'since replied to. Claim-token guarded. Service role only.';

revoke all on function public.advance_automation_work_item(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_automation_work_item(uuid, uuid) to service_role;
