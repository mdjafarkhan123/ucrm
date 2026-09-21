-- Communications Stage 6D-2: outbound picture sending (the composer's "attach a photo" for SMS).
--
-- Reuses the existing channel-agnostic communication_outbound_attachments table built for email outbound
-- attachments (20260825114614) -- no fork, no new table. That table already keys purely off
-- delivery_intent_id, so an MMS picture is just another row in it with its own <org>/outbound-sms-
-- attachments/ prefix (isolated from email's <org>/outbound-email-attachments/ the same way every other
-- upload kind is isolated).
--
-- Twilio's own CreateMessage docs (fetched live, not memory) cap MediaUrl at 10 files per message and 5 MB
-- combined for jpeg/jpg/png/gif (other accepted types are capped at 500 KB instead -- moot here since only
-- those four image types are accepted at the API/Zod layer). v1 caps a text message to exactly one photo
-- (Jafar-approved scope for 6D-2: "attach a photo", singular) -- a generous ceiling to raise later needs no
-- schema change, only a widened cap in this function and the Zod schema.
--
-- Eligibility ("resolve real-MMS vs secure-link before Twilio is ever called", the approved 6D contract):
-- Twilio's hard technical limit is that MMS only works when both the sender's and the recipient's numbers
-- are US/Canada. This system does not yet track a customer's number country independently of the sender's
-- (communication_sms_effective_retail_rate already keys "destination" off the sender's own registered
-- country -- confirmed in the existing 20260919110000/20260919190000 enqueue commands, not invented here),
-- so eligibility checks the sender's own capable_mms flag (2C-3) and country_code. The secure-link fallback
-- for an ineligible send is explicitly 6D-3's job (its own new MMS retail-rate row + the access-links
-- pattern); until then, an ineligible attempt is refused with a plain-English reason rather than silently
-- downgraded -- matching 6C's own precedent of explaining an unavailable attachment in plain language
-- instead of guessing a behavior nobody approved yet.
--
-- Money: this stage does not yet charge an MMS surcharge (6D-3 owns the new message_unit rate row); a
-- picture send is reserved/settled at the same per-segment SMS rate as a plain text today. Everything stays
-- dark regardless (Stage 9's hard constraint: no real business registered anywhere yet).

-- ---------------------------------------------------------------------------------------------------------------
-- 1. The MMS-specific attach command, sibling of private.attach_communication_outbound_files.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function private.attach_communication_outbound_sms_media(
  target_organization_id uuid,
  target_delivery_intent_id uuid,
  target_attachments jsonb
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  total_bytes bigint;
  file_count integer;
begin
  if target_attachments is null or jsonb_array_length(target_attachments) = 0 then
    return;
  end if;

  select count(*), coalesce(sum((item ->> 'byte_size')::bigint), 0)
  into file_count, total_bytes
  from jsonb_array_elements(target_attachments) as item;

  if file_count > 1 then
    raise exception 'Attach at most one photo to a text message.' using errcode = 'check_violation';
  end if;
  -- Twilio's own combined message+media ceiling for jpeg/jpg/png/gif (accepted-mime-types docs).
  if total_bytes > 5 * 1024 * 1024 then
    raise exception 'A picture must be 5 MB or smaller to send as a text message.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from jsonb_array_elements(target_attachments) as item
    where item ->> 'mime_type' not in ('image/jpeg', 'image/jpg', 'image/png', 'image/gif')
  ) then
    raise exception 'Only JPEG, PNG or GIF pictures can be sent as a text message.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from jsonb_array_elements(target_attachments) as item
    where item ->> 'object_key' not like target_organization_id::text || '/outbound-sms-attachments/%'
  ) then
    raise exception 'That file does not belong to this business.' using errcode = 'check_violation';
  end if;

  insert into public.communication_outbound_attachments (
    organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key
  )
  select
    target_organization_id,
    target_delivery_intent_id,
    item ->> 'file_name',
    item ->> 'mime_type',
    (item ->> 'byte_size')::bigint,
    item ->> 'object_key'
  from jsonb_array_elements(target_attachments) as item
  on conflict (delivery_intent_id, object_key) do nothing;
end;
$function$;

revoke all on function private.attach_communication_outbound_sms_media(uuid, uuid, jsonb)
  from public, anon, authenticated;

comment on function private.attach_communication_outbound_sms_media(uuid, uuid, jsonb) is
  'Sibling of attach_communication_outbound_files for MMS: at most one image (jpeg/jpg/png/gif), 5 MB total '
  '(Twilio''s own combined message+media ceiling for those types), same per-org object-key prefix guard, '
  'writing into the shared channel-agnostic communication_outbound_attachments table.';

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Eligibility gate inside the shared operational core, so every caller (manual Conversations reply today,
--    Automation SMS later) gets the same check for free against the same locked sender row -- no second
--    sender lookup racing the one the core already holds `for share of s`.
-- ---------------------------------------------------------------------------------------------------------------
drop function if exists private.communication_sms_enqueue_operational_core(
  uuid, uuid, uuid, uuid, text, text, text, text, uuid);

create function private.communication_sms_enqueue_operational_core(
  p_organization_id uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_sender_id uuid,
  p_subject text,
  p_body text,
  p_send_kind text,
  p_logical_send_key text,
  p_created_by uuid,
  p_has_media boolean default false
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

  -- 3.5. MMS eligibility: Twilio's own hard technical limit is both ends US/Canada; this system prices and
  --      registers per the sender's own country (see this migration's header note), so that is also the
  --      only country signal available to check here. No secure-link fallback exists yet (6D-3) -- refuse
  --      plainly rather than guess an unapproved downgrade behavior.
  if p_has_media and (not sender.capable_mms or sender.country_code not in ('US', 'CA')) then
    raise exception 'Picture messaging is not available for this number yet.'
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
  where organization_id = p_organization_id and state in ('reserved', 'submission_unknown', 'settled');
  promo_available := greatest(promo_balance - promo_reserved, 0);
  purchased_available := settled - reserved;

  if promo_available + purchased_available < cost_minor then
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
  uuid, uuid, uuid, uuid, text, text, text, text, uuid, boolean) is
  'The one SMS eligibility/write engine shared by every caller: consent, destination, readiness/holds, '
  'balance, segments/rate, quiet hours, idempotency, MMS eligibility (p_has_media) and the atomic '
  'intent/reservation/snapshot/outbox write. Takes no actor and does no permission check -- callers '
  'authorize themselves first. Service role only.';

revoke all on function private.communication_sms_enqueue_operational_core(
  uuid, uuid, uuid, uuid, text, text, text, text, uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. The public, permission-checked wrapper: same widen, same drop+recreate discipline (arg list genuinely
--    changed, matching 6D-1's own finalize_communication_inbound_attachment_import precedent).
-- ---------------------------------------------------------------------------------------------------------------
drop function if exists public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text);

create function public.communication_sms_enqueue_operational(
  p_organization_id uuid,
  p_actor uuid,
  p_client_id uuid,
  p_client_contact_method_id uuid,
  p_sender_id uuid,
  p_subject text,
  p_body text,
  p_send_kind text,
  p_logical_send_key text,
  p_has_media boolean default false
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if p_actor is null then
    raise exception 'a send must record who sent it' using errcode = 'P0001';
  end if;

  if not private.member_has_permission(p_organization_id, p_actor, 'conversations.send')
    or not private.member_has_permission(p_organization_id, p_actor, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.'
      using errcode = 'insufficient_privilege';
  end if;

  return private.communication_sms_enqueue_operational_core(
    p_organization_id, p_client_id, p_client_contact_method_id, p_sender_id,
    p_subject, p_body, p_send_kind, p_logical_send_key, p_actor, p_has_media);
end;
$$;

revoke all on function public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text, boolean) to service_role;

comment on function public.communication_sms_enqueue_operational(
  uuid, uuid, uuid, uuid, uuid, text, text, text, text, boolean) is
  'Human-authorized SMS send: checks the actor''s permission, then delegates every live gate (including MMS '
  'eligibility) and the atomic write to private.communication_sms_enqueue_operational_core. Service role only.';

-- ---------------------------------------------------------------------------------------------------------------
-- 4. enqueue_conversation_reply_sms gains an attachments parameter, mirroring enqueue_conversation_reply_
--    email exactly: attach after the intent exists, before the outbox row, in the same transaction.
-- ---------------------------------------------------------------------------------------------------------------
drop function if exists public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text);

create function public.enqueue_conversation_reply_sms(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_logical_send_key text,
  target_body text,
  target_attachments jsonb default '[]'::jsonb
) returns public.communication_delivery_intents
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  recipient public.client_contact_methods;
  latest_contact_method_id uuid;
  intent public.communication_delivery_intents;
begin
  select client_contact_method_id into latest_contact_method_id
  from (
    select client_contact_method_id, created_at
    from public.communication_delivery_intents
    where organization_id = target_organization_id and client_id = target_client_id and channel = 'sms'
    union all
    select client_contact_method_id, created_at
    from public.communication_inbound_messages
    where organization_id = target_organization_id and client_id = target_client_id and channel = 'sms'
  ) activity
  order by created_at desc
  limit 1;

  select method.* into recipient
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.client_id = target_client_id
    and method.kind = 'phone'
    and client.deleted_at is null
    and (latest_contact_method_id is null or method.id = latest_contact_method_id)
  order by method.is_primary desc, method.created_at, method.id
  limit 1
  for share of method, client;

  if recipient.id is null then
    raise exception 'This customer has no active phone number to reply to.' using errcode = 'foreign_key_violation';
  end if;

  intent := public.communication_sms_enqueue_operational(
    target_organization_id, target_actor_user_id, target_client_id, recipient.id,
    null, 'service', target_body, 'manual', target_logical_send_key,
    coalesce(jsonb_array_length(target_attachments) > 0, false)
  );

  perform private.attach_communication_outbound_sms_media(
    intent.organization_id, intent.id, target_attachments
  );

  return intent;
end;
$$;

revoke all on function public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text, jsonb)
  to service_role;

comment on function public.enqueue_conversation_reply_sms(uuid, uuid, uuid, text, text, jsonb) is
  'Resolves the SMS reply recipient from this conversation''s own most recent activity (falling back to the '
  'primary phone), delegates the send (including MMS eligibility when target_attachments is non-empty) to '
  'communication_sms_enqueue_operational with subject ''service'' and the organization''s default sender, '
  'then attaches at most one photo via attach_communication_outbound_sms_media in the same transaction.';
