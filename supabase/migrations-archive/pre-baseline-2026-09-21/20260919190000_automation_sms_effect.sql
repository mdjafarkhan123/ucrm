-- Communications A2 / Automation Stage 7: the SMS effect.
--
-- Mirrors 20260831030526_automation_email_effect.sql's shape for the second channel, but reuses rather than
-- duplicates the send: the build boundary is explicit that "Manual and Automation SMS use one server-side
-- eligibility and enqueue command" (docs/communications-a2-implementation-plan.md § Build boundaries), unlike
-- email, where the automation and manual sends independently duplicate similar logic. So this migration first
-- splits communication_sms_enqueue_operational (20260919110000) into a private core -- every live gate
-- (consent, destination, readiness/holds, balance, quiet hours, idempotency) and the atomic write -- and a
-- thin public wrapper that only adds the human actor's permission check. Automation gets its own thin entry
-- point, enqueue_automation_quote_sms, that owns the facts IT is responsible for (entitlement, platform
-- authority, the quote stop conditions already shared with email) and calls the SAME core, with no actor and
-- no permission check, exactly as enqueue_automation_quote_email already does for the human-authorized email
-- send vs. its own system path.
--
-- Not in this slice, by design: the SMS body may not use {{quote_link}} -- the SMS send path does not mint a
-- customer access link the way email does, so a text can only carry customer_name / business_name /
-- quote_number (src/lib/automation/email-variables.ts). Adding a texted secure link is a real follow-up, not
-- a same-migration add-on, since it means deciding how quote_recipients/quote_access_links (an email-shaped
-- table: NOT NULL, email-format-checked) represent a phone recipient. Also not in this slice: the "send a
-- test to my verified team phone" control (Jafar deferred it 2026-09-15 pending a phone-verification design).
--
-- Flow for one action step, mirroring email: advance_automation_work_item returns 'action_due_sms' (it now
-- distinguishes the two action kinds instead of assuming email for every action step); the worker calls
-- perform_automation_sms_effect, which re-checks pause/current truth and enqueues idempotently in ONE
-- transaction. Unlike email, there is no link to mint, so the worker does no pre-work before calling it.

-- ---------------------------------------------------------------------------------------------------
-- 1. Split communication_sms_enqueue_operational into a private core and a permission-checked wrapper.
-- ---------------------------------------------------------------------------------------------------
-- Identical body to the 20260919110000 definition, minus the human-actor shape/permission check (step 1's
-- actor-null check and step 2's member_has_permission check move to the public wrapper below) and the actor
-- parameter itself (renamed to p_created_by, which the automation caller passes as null). One change to the
-- gates themselves: the insufficient-balance raise gets its own errcode (P0402, this codebase's existing
-- P04xx convention for a payment/balance-required outcome -- see client_create_edit_foundation's P0002 "not
-- found", quote_professional_proposals_foundation's P0409 "conflict") instead of the shared P0001 bucket, so
-- the automation wrapper below can tell "not enough balance" (retry later) apart from a permanent business
-- rule failure (opted out, invalid number) without parsing message text.
create or replace function private.communication_sms_enqueue_operational_core(
  p_organization_id uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_sender_id uuid,
  p_subject text,
  p_body text,
  p_send_kind text,
  p_logical_send_key text,
  p_created_by uuid
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  recipient public.client_contact_methods;
  recipient_e164 text;
  sender public.communication_sms_sender_identities;
  registration public.communication_sms_registrations;
  outbound record;
  consent text;
  v_encoding text;
  v_segment_count integer;
  rate public.communication_sms_retail_rates;
  cost_minor bigint;
  currency text := 'USD';
  settled bigint;
  reserved bigint;
  promo_balance bigint;
  promo_reserved bigint;
  promo_available bigint;
  purchased_available bigint;
  promo_used bigint;
  purchased_used bigint;
  available timestamptz;
  intent public.communication_delivery_intents;
  existing public.communication_delivery_intents;
  existing_body text;
  source_key text;
begin
  -- 1. Shape.
  if p_subject is null or p_subject not in ('service', 'work_updates', 'billing_updates') then
    raise exception 'a send must name a valid operational subject' using errcode = 'P0001';
  end if;
  if p_body is null or char_length(trim(p_body)) = 0 then
    raise exception 'a send needs a message body' using errcode = 'P0001';
  end if;
  if p_send_kind is null or p_send_kind not in ('manual', 'automated') then
    raise exception 'a send must be manual or automated' using errcode = 'P0001';
  end if;
  if p_logical_send_key is null or char_length(trim(p_logical_send_key)) = 0 then
    raise exception 'a send must carry a logical send key' using errcode = 'P0001';
  end if;

  -- 2. Resolve the recipient: an active phone on this customer in this organization, normalized to E.164.
  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = p_organization_id
    and method.id = p_client_contact_method_id
    and method.client_id = p_client_id
    and method.kind = 'phone'
    and client.deleted_at is null
  for share of method, client;

  if recipient.id is null then
    raise exception 'Choose an active phone number for this customer.' using errcode = 'foreign_key_violation';
  end if;
  recipient_e164 := '+' || recipient.normalized_value;
  if recipient_e164 !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'That customer phone number is not a valid mobile number.' using errcode = 'P0001';
  end if;

  -- 3. Resolve the sending number: the chosen one, or the organization default. Must be a live, SMS-capable
  --    number tied to a registration.
  if p_sender_id is not null then
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id
      and s.id = p_sender_id
      and s.lifecycle_state = 'ready'
      and s.capable_sms
    for share of s;
  else
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = p_organization_id
      and s.is_default_sender
      and s.lifecycle_state = 'ready'
      and s.capable_sms
    for share of s;
  end if;

  if sender.id is null then
    raise exception 'No ready SMS number is available to send from.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if sender.registration_id is null or sender.country_code is null or sender.sender_type is null then
    raise exception 'This SMS number is not fully set up to send yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select r.* into registration
  from public.communication_sms_registrations r
  where r.organization_id = p_organization_id and r.id = sender.registration_id;
  if registration.id is null then
    raise exception 'This SMS number is not fully set up to send yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 4. Idempotency: a repeat of the same logical send returns the already-queued intent unchanged; the same
  --    key with a different frozen payload is a conflict. Return the replay before re-running any live gate.
  select i.* into existing
  from public.communication_delivery_intents i
  where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);

  if existing.id is not null then
    select snap.body into existing_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;

    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end if;

  -- 5. Readiness and holds in one read.
  select * into outbound
  from public.communication_sms_outbound_state(
    p_organization_id, sender.country_code, sender.sender_type, registration.use_case
  );
  if outbound.state = 'outbound_paused' then
    raise exception 'Outbound SMS is paused for this organization right now.'
      using errcode = 'object_not_in_prerequisite_state';
  elsif outbound.state <> 'ready' then
    raise exception 'This organization is not ready to send SMS yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 6. Consent for this exact number and this one subject. Unknown or opted-out refuses.
  consent := public.communication_sms_consent_status(
    p_organization_id, p_client_contact_method_id, p_subject
  );
  if consent = 'opted_out' then
    raise exception 'This customer has opted out of text messages.' using errcode = 'P0001';
  elsif consent <> 'opted_in' then
    raise exception 'There is no SMS consent on file for this customer and message type.'
      using errcode = 'P0001';
  end if;

  -- 7. Freeze the segment estimate.
  select est.encoding, est.segment_count into v_encoding, v_segment_count
  from public.communication_sms_estimate_segments(p_body) est;
  if v_segment_count > 10 then
    raise exception 'This message is too long to send as one text.' using errcode = 'P0001';
  end if;

  -- 8. Freeze the applicable retail rate and the estimated cost (rounded up so the reservation never under-holds).
  select rr.* into rate
  from public.communication_sms_effective_retail_rate(
    sender.country_code, sender.sender_type, 'segment', currency, now()
  ) rr;
  if rate.id is null then
    raise exception 'No SMS price is published for this destination yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  cost_minor := ceil(v_segment_count * rate.retail_rate_major * 100)::bigint;

  -- 9. Serialize on the organization's credit account and check spendable balance.
  insert into public.communication_sms_credit_accounts (organization_id, currency_code)
  values (p_organization_id, currency)
  on conflict (organization_id) do nothing;

  select settled_balance_minor, reserved_balance_minor into settled, reserved
  from public.communication_sms_credit_accounts
  where organization_id = p_organization_id
  for update;

  promo_balance := public.communication_sms_promotional_balance(p_organization_id);
  select coalesce(sum(reserved_promotional_minor), 0) into promo_reserved
  from public.communication_sms_credit_reservations
  where organization_id = p_organization_id and state in ('reserved', 'submission_unknown');
  promo_available := greatest(promo_balance - promo_reserved, 0);
  purchased_available := settled - reserved;

  if promo_available + purchased_available < cost_minor then
    -- Its own errcode (not the shared P0001 bucket) so a caller without a signed-in actor -- Automation -- can
    -- treat "not enough balance right now" as temporary and retry, distinct from a permanent business refusal.
    raise exception 'There is not enough SMS balance to send this message.' using errcode = 'P0402';
  end if;

  promo_used := least(cost_minor, promo_available);
  purchased_used := cost_minor - promo_used;

  -- 10. Schedule for quiet hours (now unless inside the window).
  available := public.communication_sms_quiet_hours_available_at(now());

  -- 11. Create the durable send intent.
  begin
    insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, channel, logical_send_key,
      recipient_phone, sms_sender_identity_id, send_kind, allowance_class, created_by
    ) values (
      p_organization_id, p_client_id, p_client_contact_method_id, 'sms', trim(p_logical_send_key),
      recipient_e164, sender.id, p_send_kind, 'optional', p_created_by
    )
    returning * into intent;
  exception when unique_violation then
    select i.* into existing
    from public.communication_delivery_intents i
    where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);
    select snap.body into existing_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;
    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end;

  -- 12. Freeze the message body, encoding and segment count.
  insert into public.communication_sms_message_snapshots (
    delivery_intent_id, organization_id, body, encoding, segment_count
  ) values (
    intent.id, p_organization_id, p_body, v_encoding, v_segment_count
  );

  -- 13. Reserve the estimated cost.
  source_key := 'send:' || trim(p_logical_send_key);
  update public.communication_sms_credit_accounts
  set reserved_balance_minor = reserved_balance_minor + purchased_used,
      updated_at = now()
  where organization_id = p_organization_id;

  insert into public.communication_sms_credit_reservations (
    organization_id, delivery_intent_id, source_key, amount_minor, segment_count,
    reserved_promotional_minor, reserved_purchased_minor
  ) values (
    p_organization_id, intent.id, source_key, cost_minor, v_segment_count,
    promo_used, purchased_used
  );

  -- 14. Hand the send to the outbox, scheduled for quiet hours.
  insert into public.communication_outbox_events (
    organization_id, delivery_intent_id, channel, available_at
  ) values (
    p_organization_id, intent.id, 'sms', available
  );

  return intent;
end;
$$;

comment on function private.communication_sms_enqueue_operational_core(
  uuid, uuid, uuid, uuid, text, text, text, text, uuid) is
  'The one SMS eligibility/write engine shared by every caller: consent, destination, readiness/holds, '
  'balance, segments/rate, quiet hours, idempotency, and the atomic intent/reservation/snapshot/outbox write. '
  'Takes no actor and does no permission check -- callers authorize themselves first. Service role only.';

revoke all on function private.communication_sms_enqueue_operational_core(
  uuid, uuid, uuid, uuid, text, text, text, text, uuid) from public, anon, authenticated;

-- The human-authorized entry point Conversations already calls: same signature as before, now a thin wrapper
-- that checks the actor's permission, then delegates to the shared core.
create or replace function public.communication_sms_enqueue_operational(
  p_organization_id uuid,
  p_actor uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_sender_id uuid,
  p_subject text,
  p_body text,
  p_send_kind text,
  p_logical_send_key text
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if p_actor is null then
    raise exception 'a send must record who sent it' using errcode = 'P0001';
  end if;

  -- Mirrors the email command: the authorized member may send customer messages.
  if not private.member_has_permission(p_organization_id, p_actor, 'conversations.send')
    or not private.member_has_permission(p_organization_id, p_actor, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.'
      using errcode = 'insufficient_privilege';
  end if;

  return private.communication_sms_enqueue_operational_core(
    p_organization_id, p_client_id, p_client_contact_method_id, p_sender_id,
    p_subject, p_body, p_send_kind, p_logical_send_key, p_actor);
end;
$$;

revoke all on function public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text) to service_role;

comment on function public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text) is
  'Human-authorized SMS send: checks the actor''s permission, then delegates every live gate and the atomic '
  'write to private.communication_sms_enqueue_operational_core. Service role only.';

-- ---------------------------------------------------------------------------------------------------
-- 2. Rendering: author copy + the three allow-listed variables SMS supports (no quote_link).
-- ---------------------------------------------------------------------------------------------------
create or replace function private.render_automation_sms(
  p_body text,
  p_customer_name text,
  p_business_name text,
  p_quote_number text
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select replace(replace(replace(
    coalesce(p_body, ''),
    '{{customer_name}}', coalesce(p_customer_name, '')),
    '{{business_name}}', coalesce(p_business_name, '')),
    '{{quote_number}}', coalesce(p_quote_number, ''));
$$;

comment on function private.render_automation_sms(text, text, text, text) is
  'Renders an automation SMS body from author text and the three allow-listed variables. SMS carries no '
  'markup, so unlike render_automation_email there is nothing to escape -- only a plain substitution.';

-- ---------------------------------------------------------------------------------------------------
-- 3. The system send command: Automation's equivalent of enqueue_conversation_reply_sms.
-- ---------------------------------------------------------------------------------------------------
-- Owns the facts it is responsible for (entitlement, platform authority, the quote stop conditions already
-- shared with email via private.automation_quote_stop_outcome) and resolves recipient/sender itself, then
-- delegates the actual send to the shared core. Returns a plain status like enqueue_automation_quote_email:
-- 'sent', 'skipped_permanent' (the caller should stop the enrollment), or 'skipped_temporary' (back off and
-- retry). The core raises instead of returning a status (it also serves the human path, which surfaces a
-- thrown error as an API error); the exception block below is what translates those raises into the same
-- plain status shape, by SQLSTATE: object_not_in_prerequisite_state / P0402 (balance) are temporary,
-- unique_violation / foreign_key_violation / P0001 are permanent. Anything else is a genuine infrastructure
-- failure and is left to propagate, exactly as an unexpected error from enqueue_automation_quote_email would.
create or replace function public.enqueue_automation_quote_sms(
  p_organization_id uuid,
  p_quote_id uuid,
  p_logical_send_key text,
  p_body text,
  p_sender_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  quote_row public.quotes;
  version_row public.quote_versions;
  client_row public.clients;
  recipient public.client_contact_methods;
  sender public.communication_sms_sender_identities;
  stop_outcome text;
  customer_name text;
  rendered_body text;
  intent public.communication_delivery_intents;
begin
  if coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_sms_content');
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

  -- The same quote stop check the email send uses: gone/archived, not awaiting a response, or the client
  -- turned quote follow-ups off. Channel-agnostic by design (private.automation_quote_stop_outcome).
  stop_outcome := private.automation_quote_stop_outcome(p_organization_id, p_quote_id);
  if stop_outcome is not null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', stop_outcome);
  end if;

  select * into quote_row from public.quotes
    where organization_id = p_organization_id and id = p_quote_id for share;
  if quote_row.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'quote_not_sendable');
  end if;

  select * into version_row from public.quote_versions
    where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
      and quote_id = quote_row.id and status = 'published' for share;
  select * into client_row from public.clients
    where organization_id = quote_row.organization_id and id = quote_row.client_id and deleted_at is null for share;
  if version_row.id is null or client_row.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'recipient_unavailable');
  end if;

  -- The customer's current primary SMS-capable number only. Never a silent fallback to another saved number
  -- (docs/automation-behavior-contract.md § SMS customer action) -- no primary is a permanent skip.
  select * into recipient from public.client_contact_methods
    where organization_id = quote_row.organization_id and client_id = quote_row.client_id
      and kind = 'phone' and is_primary for share;
  if recipient.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'recipient_unavailable');
  end if;

  -- Sender: an authored pin if the step named one, else the number this customer's SMS conversation has been
  -- using, else the organization default. Unattended Automation never infers a sender from a staff assignment
  -- (docs/automation-behavior-contract.md § SMS customer action).
  if p_sender_id is not null then
    select s.* into sender from public.communication_sms_sender_identities s
      where s.organization_id = quote_row.organization_id and s.id = p_sender_id
        and s.lifecycle_state = 'ready' and s.capable_sms;
  else
    select s.* into sender
    from public.communication_sms_sender_identities s
    where s.organization_id = quote_row.organization_id
      and s.lifecycle_state = 'ready' and s.capable_sms
      and s.id = (
        select di.sms_sender_identity_id
        from public.communication_delivery_intents di
        where di.organization_id = quote_row.organization_id
          and di.client_id = quote_row.client_id and di.channel = 'sms'
        order by di.created_at desc
        limit 1
      );
    if sender.id is null then
      select s.* into sender from public.communication_sms_sender_identities s
        where s.organization_id = quote_row.organization_id and s.is_default_sender
          and s.lifecycle_state = 'ready' and s.capable_sms;
    end if;
  end if;
  if sender.id is null then
    return jsonb_build_object('status', 'skipped_temporary', 'reason', 'sender_not_ready');
  end if;

  customer_name := coalesce(nullif(btrim(client_row.display_name), ''), recipient.normalized_value);
  rendered_body := private.render_automation_sms(
    p_body, customer_name, version_row.organization_name, quote_row.quote_number::text);

  begin
    intent := private.communication_sms_enqueue_operational_core(
      quote_row.organization_id, quote_row.client_id, recipient.id, sender.id,
      'service', rendered_body, 'automated', p_logical_send_key, null);
  exception
    when object_not_in_prerequisite_state or sqlstate 'P0402' then
      return jsonb_build_object('status', 'skipped_temporary', 'reason', left(sqlerrm, 200));
    when unique_violation or foreign_key_violation or sqlstate 'P0001' then
      return jsonb_build_object('status', 'skipped_permanent', 'reason', left(sqlerrm, 200));
  end;

  return jsonb_build_object('status', 'sent', 'reason', 'enqueued', 'intent_id', intent.id);
end;
$$;

comment on function public.enqueue_automation_quote_sms(uuid, uuid, text, text, uuid) is
  'System-authorized automation SMS send: re-checks entitlement, authority, and the quote stop conditions, '
  'resolves the primary customer number and the continuity/default/pinned sender, renders safe copy, and '
  'enqueues through the shared SMS core idempotently on the logical send key. Returns sent / '
  'skipped_permanent / skipped_temporary. Service role only.';

revoke all on function public.enqueue_automation_quote_sms(uuid, uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.enqueue_automation_quote_sms(uuid, uuid, text, text, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. The claimed action effect: recheck pause, enqueue, and settle in one transaction.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.perform_automation_sms_effect(
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
  logical_send_key text;
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

  -- Recheck pause immediately before the customer effect: a recipe paused since the claim holds this step.
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
  if step is null or (step ->> 'type') <> 'action' or (step ->> 'key') <> 'action.send_sms' then
    -- Not a textable action (or past the last step): nothing this adapter can do. Park for attention rather
    -- than guessing.
    update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_cancelled';
  end if;

  logical_send_key := 'automation-quote-follow-up-sms:' || enrollment.id || ':'
    || enrollment.recipe_version_id || ':' || item.step_index;

  result := public.enqueue_automation_quote_sms(
    enrollment.organization_id,
    enrollment.subject_id,
    logical_send_key,
    step -> 'config' ->> 'body',
    nullif(step -> 'config' ->> 'sender_id', '')::uuid);
  status := result ->> 'status';

  if status = 'sent' then
    update private.automation_enrollments
      set current_step_index = item.step_index + 1,
        customer_messages_sent = customer_messages_sent + 1
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

comment on function public.perform_automation_sms_effect(uuid, uuid) is
  'Runs one claimed SMS action in a single transaction: rechecks enrollment/expiry/pause, enqueues the text '
  'idempotently, and settles the work item (advance on sent, back off on temporary, stop the enrollment on '
  'permanent). Claim-token guarded. Service role only.';

revoke all on function public.perform_automation_sms_effect(uuid, uuid) from public, anon, authenticated;
grant execute on function public.perform_automation_sms_effect(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. advance now distinguishes which action kind is due instead of assuming email for every action step.
-- ---------------------------------------------------------------------------------------------------
-- Copied verbatim from 20260831103248's definition; only the action branch changes. An action step whose
-- key is neither known kind parks immediately as 'action_not_available' instead of routing to a worker
-- effect that would only re-discover the same thing.
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
  next_due timestamptz;
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

  step_type := step ->> 'type';

  if step_type = 'wait' then
    wait_unit := step -> 'config' ->> 'unit';
    wait_amount := nullif(step -> 'config' ->> 'amount', '')::integer;
    if wait_unit not in ('hours', 'days') or wait_amount is null or wait_amount < 1 then
      raise exception 'This automation step has an unusable delay.' using errcode = 'check_violation';
    end if;

    select
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'days'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0),
      coalesce(sum(case when entry.step -> 'config' ->> 'unit' = 'hours'
        then nullif(entry.step -> 'config' ->> 'amount', '')::integer else 0 end), 0)
    into waited_days, waited_hours
    from jsonb_array_elements(coalesce(definition -> 'steps', '[]'::jsonb))
      with ordinality as entry(step, position)
    where entry.position - 1 <= item.step_index and entry.step ->> 'type' = 'wait';

    select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into organization_timezone
    from public.organization_settings as settings
    where settings.organization_id = enrollment.organization_id;
    organization_timezone := coalesce(organization_timezone, 'UTC');

    next_due := ((enrollment.anchor_at at time zone organization_timezone)
      + make_interval(days => waited_days, hours => waited_hours)) at time zone organization_timezone;

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
  'action_due_sms for the worker to run and settle the matching effect. Claim-token guarded. Service role '
  'only.';

revoke all on function public.advance_automation_work_item(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_automation_work_item(uuid, uuid) to service_role;
