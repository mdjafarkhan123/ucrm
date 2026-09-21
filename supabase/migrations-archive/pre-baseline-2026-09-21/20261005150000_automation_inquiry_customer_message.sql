-- CRM launch readiness Part 4, Stage 5: a website inquiry's customer message picks its channel, and a public form
-- can collect service-SMS consent.
--
-- Established pattern (docs/research/website-speed-to-lead-patterns-2026-09-17.md and its addendum):
--   * HighLevel A2P separation — an optional, unchecked, non-marketing SMS checkbox whose exact wording, outcome,
--     time and source are stored. Entering a phone number never grants SMS consent.
--   * HighLevel "Messaging Error – SMS" — fall back to email only on a reported failure, never on unknown status.
--
-- Pieces:
--   1. A processed form submission whose visitor ticked the box records one web-form opt-in in the existing SMS
--      consent ledger, for that exact number on the resulting client. Nothing is recorded when it was unticked.
--   2. action.send_customer_message: text when the customer is eligible (primary number, consent on file, a ready
--      sender, balance), otherwise email. At most one text and one email per step, ever (logical send keys).
--   3. private.automation_sms_email_fallbacks: a text sent by that step is watched; a provider-reported failure
--      (Twilio failed/undelivered, or a permanent 4xx rejection) makes an email fallback due, which the automation
--      worker sends after re-checking staff reply, customer reply and enrollment state. Delivered, or any other
--      cancellation, closes the watch. Unknown or needs-checking never triggers a second message.
--   4. advance_automation_work_item routes the new action and pauses it on a customer reply like the other two.
--
-- Deliberately NOT here: the authorable catalog entry, starter preset and history UI (Stage 6), and Website Chat
-- consent in the ledger (the widget still ticks its box by default, which is not valid SMS consent evidence).

-- ---------------------------------------------------------------------------------------------------
-- 1. Web-form service-SMS consent goes into the consent ledger.
-- ---------------------------------------------------------------------------------------------------
-- The public submit route puts {given, disclosure} under contact.sms_service_consent, having normalized the phone
-- to E.164 digits when the box was ticked. The ledger only holds opt-ins; an unticked box is evidence of nothing
-- and must never override an earlier opt-in, so it stays on the submission alone.
create function private.record_form_submission_sms_consent()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  consent jsonb := new.contact -> 'sms_service_consent';
  submitted_phone text;
  target_client_id uuid;
  method_id uuid;
begin
  if consent is null or jsonb_typeof(consent) <> 'object' or (consent ->> 'given') is distinct from 'true'
    or coalesce(btrim(consent ->> 'disclosure'), '') = '' then
    return null;
  end if;

  submitted_phone := nullif(regexp_replace(coalesce(new.contact ->> 'phone', ''), '[^0-9]', '', 'g'), '');
  target_client_id := nullif(new.result ->> 'client_id', '')::uuid;
  if submitted_phone is null or target_client_id is null then
    return null;
  end if;

  -- Only the exact number the visitor typed, and only if it belongs to the client this submission became. When
  -- that number already belongs to someone else (an ambiguous match), no consent is attached to anyone.
  select method.id into method_id
  from public.client_contact_methods as method
  where method.organization_id = new.organization_id and method.client_id = target_client_id
    and method.kind = 'phone' and method.normalized_value = submitted_phone;
  if method_id is null then
    return null;
  end if;

  insert into public.communication_sms_consent_events (
    organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
    subjects, proof_method, evidence, occurred_at
  ) values (
    new.organization_id, target_client_id, method_id, 'opt_in', 'system', 'form_submission:' || new.id,
    array['service', 'work_updates'], 'web_form',
    jsonb_build_object(
      'channel', 'form',
      'form_id', new.form_id,
      'form_version_id', new.form_version_id,
      'form_submission_id', new.id,
      'disclosure', left(consent ->> 'disclosure', 1000)
    ),
    new.created_at
  )
  on conflict (organization_id, source, source_event_key) do nothing;

  return null;
end;
$$;

revoke all on function private.record_form_submission_sms_consent() from public, anon, authenticated;

create trigger form_submissions_record_sms_consent
  after update of status on private.form_submissions
  for each row
  when (new.status = 'processed' and old.status is distinct from 'processed')
  execute function private.record_form_submission_sms_consent();

-- ---------------------------------------------------------------------------------------------------
-- 2. The fallback watch.
-- ---------------------------------------------------------------------------------------------------
create table private.automation_sms_email_fallbacks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  enrollment_id uuid not null references private.automation_enrollments (id) on delete cascade,
  step_index integer not null check (step_index >= 0),
  sms_delivery_intent_id uuid not null references public.communication_delivery_intents (id) on delete cascade,
  email_delivery_intent_id uuid references public.communication_delivery_intents (id) on delete set null,
  -- watching: text sent, no final word yet. due: the provider reported a failure. sent: fallback email queued.
  -- not_needed: the text was delivered. skipped: no fallback, with a plain reason.
  state text not null default 'watching'
    check (state in ('watching', 'due', 'sent', 'not_needed', 'skipped')),
  sms_failure text,
  reason text,
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint automation_sms_email_fallbacks_step_key unique (enrollment_id, step_index),
  constraint automation_sms_email_fallbacks_sms_intent_key unique (sms_delivery_intent_id)
);

comment on table private.automation_sms_email_fallbacks is
  'One row per text a website-inquiry customer-message step sent. A provider-reported failure makes the email '
  'fallback due; delivered or any other outcome closes it. Written only by automation functions and the SMS '
  'intent outcome trigger.';

create index automation_sms_email_fallbacks_due_idx
  on private.automation_sms_email_fallbacks (available_at) where state = 'due';
create index automation_sms_email_fallbacks_email_intent_idx
  on private.automation_sms_email_fallbacks (email_delivery_intent_id) where email_delivery_intent_id is not null;
create index automation_sms_email_fallbacks_organization_idx
  on private.automation_sms_email_fallbacks (organization_id);

create trigger automation_sms_email_fallbacks_set_updated_at
  before update on private.automation_sms_email_fallbacks
  for each row execute function public.set_updated_at();

alter table private.automation_sms_email_fallbacks enable row level security;
revoke all on private.automation_sms_email_fallbacks from public, anon, authenticated;

-- The provider's final word on a watched text. Runs inside whichever transaction moves the intent (the SMS worker's
-- finalize, or the status-callback drain); it only flips one indexed row and never sends anything itself.
create function private.settle_automation_sms_email_fallback()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.delivery_outcome in ('sms_failed', 'sms_undelivered')
    and new.delivery_outcome is distinct from old.delivery_outcome then
    update private.automation_sms_email_fallbacks
    set state = 'due', sms_failure = new.delivery_outcome, available_at = now()
    where sms_delivery_intent_id = new.id and state = 'watching';
  elsif new.delivery_outcome = 'sms_delivered' and old.delivery_outcome is distinct from 'sms_delivered' then
    update private.automation_sms_email_fallbacks
    set state = 'not_needed', reason = 'sms_delivered'
    where sms_delivery_intent_id = new.id and state = 'watching';
  elsif new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    -- Twilio refused the request outright (any 4xx it did not ask us to retry): the text will never arrive.
    -- Every other cancellation (opt-out, sender gone, hold) is a deliberate stop, not a delivery failure.
    if coalesce(new.failure_code, '') ~ '^twilio_http_4[0-9]{2}$' then
      update private.automation_sms_email_fallbacks
      set state = 'due', sms_failure = new.failure_code, available_at = now()
      where sms_delivery_intent_id = new.id and state = 'watching';
    else
      update private.automation_sms_email_fallbacks
      set state = 'skipped', reason = left(coalesce(new.failure_code, 'sms_cancelled'), 100)
      where sms_delivery_intent_id = new.id and state = 'watching';
    end if;
  end if;
  return null;
end;
$$;

revoke all on function private.settle_automation_sms_email_fallback() from public, anon, authenticated;

create trigger communication_delivery_intents_settle_sms_email_fallback
  after update of status, delivery_outcome on public.communication_delivery_intents
  for each row
  when (new.channel = 'sms' and new.send_kind = 'automated')
  execute function private.settle_automation_sms_email_fallback();

-- ---------------------------------------------------------------------------------------------------
-- 3. The two sends.
-- ---------------------------------------------------------------------------------------------------
-- The email half, shared by the step and by the fallback. Same readiness rules as the quote email, without a quote
-- link. Returns sent / skipped_permanent / skipped_temporary.
create function private.enqueue_automation_inquiry_email(
  p_organization_id uuid,
  p_client_id uuid,
  p_logical_send_key text,
  p_subject text,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  client_row public.clients;
  recipient public.client_contact_methods;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  alias public.communication_reply_aliases;
  intent public.communication_delivery_intents;
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

  select * into client_row from public.clients
    where organization_id = p_organization_id and id = p_client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = p_organization_id and client_id = p_client_id and kind = 'email'
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

  -- No quote exists for an inquiry: quote variables render empty (the Stage 6 validator refuses them).
  select * into rendered from private.render_automation_email(
    p_subject, p_body,
    coalesce(nullif(btrim(client_row.display_name), ''), recipient.normalized_value),
    coalesce(business_name, ''), '', '');

  alias := public.ensure_communication_reply_alias(p_organization_id, sender.id, p_client_id, recipient.id);

  begin
    insert into public.communication_delivery_intents
      (organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email, subject,
       html_content, text_content, send_kind, allowance_class, sender_id, reply_alias_id, created_by)
      values (p_organization_id, p_client_id, recipient.id, p_logical_send_key, recipient.normalized_value,
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

comment on function private.enqueue_automation_inquiry_email(uuid, uuid, text, text, text) is
  'System-authorized automation email to a website inquiry''s client: entitlement, authority, email address and '
  'sender readiness, safe rendering, one intent per logical send key. Returns sent / skipped_permanent / '
  'skipped_temporary.';

revoke all on function private.enqueue_automation_inquiry_email(uuid, uuid, text, text, text)
  from public, anon, authenticated;

-- The channel rule. A text is tried only when the step has SMS copy, the client has a primary number and SMS
-- consent is on file for it; any refusal from the shared SMS core (no ready sender, paused, balance, invalid
-- number) falls through to email in the same call. Replays return whichever message this step already queued.
create function private.enqueue_automation_inquiry_message(
  p_organization_id uuid,
  p_client_id uuid,
  p_key_suffix text,
  p_config jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  sms_key text := 'automation-inquiry-message-sms:' || p_key_suffix;
  email_key text := 'automation-inquiry-message-email:' || p_key_suffix;
  existing public.communication_delivery_intents;
  authority public.organization_automation_authority;
  client_row public.clients;
  phone public.client_contact_methods;
  business_name text;
  sms_intent public.communication_delivery_intents;
  sms_reason text;
  result jsonb;
begin
  select * into existing from public.communication_delivery_intents
    where organization_id = p_organization_id and logical_send_key in (sms_key, email_key)
    order by created_at limit 1;
  if existing.id is not null then
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'channel', existing.channel,
      'intent_id', existing.id);
  end if;

  if p_client_id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'no_customer_record');
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

  select * into client_row from public.clients
    where organization_id = p_organization_id and id = p_client_id and deleted_at is null;
  if client_row.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'no_customer_record');
  end if;

  if coalesce(btrim(p_config ->> 'sms_body'), '') = '' then
    sms_reason := 'no_sms_copy';
  else
    select * into phone from public.client_contact_methods
      where organization_id = p_organization_id and client_id = p_client_id and kind = 'phone' and is_primary;
    if phone.id is null then
      sms_reason := 'no_mobile_number';
    elsif public.communication_sms_consent_status(p_organization_id, phone.id, 'service') <> 'opted_in' then
      sms_reason := 'no_sms_consent';
    else
      select organization.name into business_name from public.organizations as organization
        where organization.id = p_organization_id;
      begin
        sms_intent := private.communication_sms_enqueue_operational_core(
          p_organization_id, p_client_id, phone.id, null, 'service',
          private.render_automation_sms(
            p_config ->> 'sms_body',
            coalesce(nullif(btrim(client_row.display_name), ''), phone.normalized_value),
            coalesce(business_name, ''), ''),
          'automated', sms_key, null);
        return jsonb_build_object('status', 'sent', 'reason', 'enqueued', 'channel', 'sms',
          'intent_id', sms_intent.id);
      exception
        when object_not_in_prerequisite_state or foreign_key_violation or sqlstate 'P0001' or sqlstate 'P0402' then
          sms_reason := left(sqlerrm, 200);
      end;
    end if;
  end if;

  result := private.enqueue_automation_inquiry_email(
    p_organization_id, p_client_id, email_key, p_config ->> 'email_subject', p_config ->> 'email_body');
  return result || jsonb_build_object('channel', 'email', 'sms_skipped_reason', sms_reason);
end;
$$;

comment on function private.enqueue_automation_inquiry_message(uuid, uuid, text, jsonb) is
  'Website-inquiry customer message: text if the client is SMS-eligible (copy, primary number, consent, and the '
  'shared SMS core accepts it), else email. One text and one email key per step. Returns the plain status shape '
  'plus the channel used.';

revoke all on function private.enqueue_automation_inquiry_message(uuid, uuid, text, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 4. The claimed action effect.
-- ---------------------------------------------------------------------------------------------------
create function public.perform_automation_inquiry_message_effect(
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
  stop_outcome text;
  customer_reply_at timestamptz;
  subject record;
  result jsonb;
  status text;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
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
    from private.automation_enrollments e
    join public.automation_recipes recipe on recipe.id = e.recipe_id
    join public.automation_recipe_versions version on version.id = e.recipe_version_id
    where e.id = enrollment.id;
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
  if step is null or (step ->> 'type') <> 'action' or (step ->> 'key') <> 'action.send_customer_message'
    or enrollment.subject_type not in ('form_submission', 'website_chat_session') then
    update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_cancelled';
  end if;

  -- The Stage 3 rules, re-read at the moment of sending: a person answered, or the customer replied.
  stop_outcome := private.automation_inquiry_stop_outcome(
    enrollment.organization_id, enrollment.subject_type, enrollment.subject_id, enrollment.anchor_at);
  if stop_outcome is not null then
    update private.automation_enrollments
      set state = 'stopped', stop_reason = stop_outcome, stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  customer_reply_at := private.automation_inquiry_customer_reply_at(
    enrollment.organization_id, enrollment.subject_type, enrollment.subject_id, enrollment.customer_reply_after);
  if customer_reply_at is not null then
    update private.automation_enrollments
      set state = 'paused', paused_work_due_at = item.due_at, current_step_index = item.step_index,
        customer_reply_after = customer_reply_at
      where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  select * into subject from private.automation_inquiry_client_id(
    enrollment.organization_id, enrollment.subject_type, enrollment.subject_id);

  result := private.enqueue_automation_inquiry_message(
    enrollment.organization_id, subject.client_id,
    enrollment.id || ':' || enrollment.recipe_version_id || ':' || item.step_index,
    step -> 'config');
  status := result ->> 'status';

  if status = 'sent' then
    if result ->> 'channel' = 'sms' then
      insert into private.automation_sms_email_fallbacks
        (organization_id, enrollment_id, step_index, sms_delivery_intent_id)
        values (enrollment.organization_id, enrollment.id, item.step_index, (result ->> 'intent_id')::uuid)
        on conflict do nothing;
    end if;
    -- From now on a customer message counts as a reply (Stage 3). An earlier reply-pause keeps its later mark.
    update private.automation_enrollments
      set current_step_index = item.step_index + 1,
        customer_messages_sent = customer_messages_sent
          + case when result ->> 'reason' = 'enqueued' then 1 else 0 end,
        customer_reply_after = coalesce(customer_reply_after, now())
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
        last_error_code = left(result ->> 'reason', 100),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_deferred';
  else
    update private.automation_enrollments
      set state = 'stopped', stop_reason = left(result ->> 'reason', 100), stopped_at = now()
      where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', last_error_code = left(result ->> 'reason', 100),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_cancelled';
  end if;
end;
$$;

comment on function public.perform_automation_inquiry_message_effect(uuid, uuid) is
  'Runs one claimed website-inquiry customer message in a single transaction: rechecks enrollment, expiry, recipe '
  'pause, staff reply (stop) and customer reply (pause), sends by text or email, watches a text for an email '
  'fallback, and settles the work item. Claim-token guarded. Service role only.';

revoke all on function public.perform_automation_inquiry_message_effect(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.perform_automation_inquiry_message_effect(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. The fallback drain, run by the automation worker every wake.
-- ---------------------------------------------------------------------------------------------------
create function public.process_automation_sms_email_fallbacks(p_batch_size integer default 25)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate private.automation_sms_email_fallbacks%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  step jsonb;
  skip_reason text;
  subject record;
  result jsonb;
  processed_count integer := 0;
  max_attempts constant integer := 8;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The fallback batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select * from private.automation_sms_email_fallbacks
    where state = 'due' and available_at <= now()
    order by available_at
    limit p_batch_size
    for update skip locked
  loop
    begin
      skip_reason := null;
      select * into enrollment from private.automation_enrollments where id = candidate.enrollment_id;
      select recipe.status, version.definition -> 'steps' -> candidate.step_index into recipe_status, step
        from public.automation_recipes recipe
        join public.automation_recipe_versions version on version.id = enrollment.recipe_version_id
        where recipe.id = enrollment.recipe_id;

      if enrollment.state in ('stopped', 'failed') then
        skip_reason := coalesce(enrollment.stop_reason, 'enrollment_stopped');
      elsif enrollment.state = 'paused' then
        skip_reason := 'enrollment_paused';
      elsif enrollment.expires_at is not null and enrollment.expires_at <= now() then
        skip_reason := 'enrollment_expired';
      elsif recipe_status is distinct from 'active' and recipe_status is distinct from 'paused' then
        skip_reason := 'recipe_not_active';
      else
        skip_reason := private.automation_inquiry_stop_outcome(
          enrollment.organization_id, enrollment.subject_type, enrollment.subject_id, enrollment.anchor_at);
        if skip_reason is null and private.automation_inquiry_customer_reply_at(
            enrollment.organization_id, enrollment.subject_type, enrollment.subject_id,
            enrollment.customer_reply_after) is not null then
          skip_reason := 'customer_replied';
        end if;
      end if;

      if skip_reason is not null then
        update private.automation_sms_email_fallbacks
          set state = 'skipped', reason = left(skip_reason, 100), available_at = null
          where id = candidate.id;
      elsif recipe_status = 'paused' then
        update private.automation_sms_email_fallbacks
          set available_at = now() + private.automation_retry_delay(candidate.attempts + 1)
          where id = candidate.id;
      else
        select * into subject from private.automation_inquiry_client_id(
          enrollment.organization_id, enrollment.subject_type, enrollment.subject_id);
        result := private.enqueue_automation_inquiry_email(
          enrollment.organization_id, subject.client_id,
          'automation-inquiry-message-email:' || enrollment.id || ':' || enrollment.recipe_version_id || ':'
            || candidate.step_index,
          step -> 'config' ->> 'email_subject', step -> 'config' ->> 'email_body');

        if result ->> 'status' = 'sent' then
          update private.automation_sms_email_fallbacks
            set state = 'sent', email_delivery_intent_id = (result ->> 'intent_id')::uuid, reason = null,
              available_at = null
            where id = candidate.id;
          if result ->> 'reason' = 'enqueued' then
            update private.automation_enrollments
              set customer_messages_sent = customer_messages_sent + 1 where id = enrollment.id;
          end if;
        elsif result ->> 'status' = 'skipped_temporary' and candidate.attempts + 1 < max_attempts then
          update private.automation_sms_email_fallbacks
            set attempts = attempts + 1, reason = left(result ->> 'reason', 100),
              available_at = now() + private.automation_retry_delay(candidate.attempts + 1)
            where id = candidate.id;
        else
          update private.automation_sms_email_fallbacks
            set state = 'skipped', attempts = attempts + 1, reason = left(result ->> 'reason', 100),
              available_at = null
            where id = candidate.id;
        end if;
      end if;
      processed_count := processed_count + 1;
    exception
      when others then
        update private.automation_sms_email_fallbacks
          set attempts = attempts + 1, reason = left(coalesce(sqlerrm, 'unknown error'), 100),
            state = case when attempts + 1 >= max_attempts then 'skipped' else state end,
            available_at = case when attempts + 1 >= max_attempts then null
              else now() + private.automation_retry_delay(attempts + 1) end
          where id = candidate.id;
    end;
  end loop;

  return processed_count;
end;
$$;

comment on function public.process_automation_sms_email_fallbacks(integer) is
  'Bounded drain of due SMS-to-email fallbacks: skips when the enrollment stopped/paused/expired, a person '
  'answered or the customer replied, otherwise queues the step''s email once (logical send key). Temporary '
  'refusals back off up to eight attempts. Service role only.';

revoke all on function public.process_automation_sms_email_fallbacks(integer) from public, anon, authenticated;
grant execute on function public.process_automation_sms_email_fallbacks(integer) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. The transition routes the new action and pauses it on a customer reply.
-- ---------------------------------------------------------------------------------------------------
-- Replaced from 20261005120000. The only changes are the customer-message key in the reply-pause check and the
-- action_due_customer_message branch.
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
  'action_due_sms / action_due_customer_message for the worker to run and settle the matching effect. A website inquiry stops on a '
  'delivered staff reply and returns paused_customer_reply before a customer-facing step the customer has '
  'since replied to. Claim-token guarded. Service role only.';

revoke all on function public.advance_automation_work_item(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_automation_work_item(uuid, uuid) to service_role;
