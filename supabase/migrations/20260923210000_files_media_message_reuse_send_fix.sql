-- Files and Media, Part 6E fix: a library File picked in the composer can actually be sent.
--
-- 20260923190000 assumed the send commands already accepted any resolved attachment. They did not: both
-- private.attach_communication_outbound_files (email) and private.communication_sms_enqueue_operational_core
-- (text) refuse any object_key outside the composer's own upload prefix, so every send that reused a library
-- File failed with "That file does not belong to this business."
--
-- Both now accept a key that is either under the composer's own upload prefix (unchanged) or the object_key of
-- an available, untrashed File in the same organization. The Files row is the proof of ownership, so a key
-- from another organization, a trashed File, or a File still being checked is still refused. Nothing deletes
-- communication_outbound_attachments objects from storage, so pointing a message at a library object is safe.

create or replace function private.outbound_attachment_key_allowed(
  target_organization_id uuid,
  target_object_key text,
  upload_prefix text
) returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select target_object_key like target_organization_id::text || '/' || upload_prefix || '/%'
    or exists (
      select 1
      from public.files file
      where file.object_key = target_object_key
        and file.organization_id = target_organization_id
        and file.trashed_at is null
        and file.processing_state = 'available'
    );
$$;

revoke all on function private.outbound_attachment_key_allowed(uuid, text, text) from public, anon, authenticated;

create or replace function private.attach_communication_outbound_files(
  target_organization_id uuid,
  target_delivery_intent_id uuid,
  target_attachments jsonb
) returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
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

  if file_count > 10 then
    raise exception 'Attach at most 10 files to one email.' using errcode = 'check_violation';
  end if;
  if total_bytes > 20 * 1024 * 1024 then
    raise exception 'Attachments must total 20 MB or less.' using errcode = 'check_violation';
  end if;

  -- Defense in depth behind the API's own checks: a key issued for one organization, or a library File that
  -- is not this organization's available File, can never be committed here.
  if exists (
    select 1 from jsonb_array_elements(target_attachments) as item
    where not private.outbound_attachment_key_allowed(
      target_organization_id, item ->> 'object_key', 'outbound-email-attachments'
    )
  ) then
    raise exception 'That file does not belong to this business.' using errcode = 'check_violation';
  end if;

  insert into public.communication_outbound_attachments (
    organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key, sort_order
  )
  select
    target_organization_id,
    target_delivery_intent_id,
    item.value ->> 'file_name',
    item.value ->> 'mime_type',
    (item.value ->> 'byte_size')::bigint,
    item.value ->> 'object_key',
    (item.ordinality - 1)::integer
  from jsonb_array_elements(target_attachments) with ordinality as item(value, ordinality)
  on conflict (delivery_intent_id, object_key) do nothing;
end;
$$;

-- The text-message engine, unchanged except for its step-14 ownership check.
CREATE OR REPLACE FUNCTION "private"."communication_sms_enqueue_operational_core"("p_organization_id" "uuid", "p_client_id" "uuid", "p_client_contact_method_id" "uuid", "p_sender_id" "uuid", "p_subject" "text", "p_body" "text", "p_send_kind" "text", "p_logical_send_key" "text", "p_created_by" "uuid", "p_attachments" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "public"."communication_delivery_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'private'
    AS $_$
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
  existing_raw_body text;
  source_key text;
  v_attachment jsonb;
  v_delivery_mode text;
  v_effective_body text;
  v_attachment_id uuid;
  v_attachment_bytes bigint;
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
  if jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) > 1 then
    raise exception 'Attach at most one file to a text message.' using errcode = 'check_violation';
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

  -- 3.5. Delivery mode (Stage 6D-3): a picture goes as real MMS only when both the sender is MMS-capable and
  --      its registered country is US/Canada (Twilio's hard technical limit -- see 6D-2's own header note for
  --      why this is the only country signal this system has). Anything else with an attachment -- a
  --      non-image file, or an image the sender/destination cannot carry as MMS -- gets a secure link instead
  --      of a refusal, per the approved 6D contract. No exception is raised for ineligibility any more.
  if jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) = 1 then
    v_attachment := p_attachments -> 0;
    if (v_attachment ->> 'mime_type') in ('image/jpeg', 'image/jpg', 'image/png', 'image/gif')
       and sender.capable_mms and sender.country_code in ('US', 'CA') then
      v_delivery_mode := 'inline_media';
    else
      v_delivery_mode := 'secure_link';
    end if;
  end if;

  v_effective_body := case
    when v_delivery_mode = 'secure_link' then p_body || E'\n\n' || (v_attachment ->> 'link_url')
    else p_body
  end;

  select r.* into registration
  from public.communication_sms_registrations r
  where r.organization_id = p_organization_id and r.id = sender.registration_id;
  if registration.id is null then
    raise exception 'This SMS number is not fully set up to send yet.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- 4. Idempotency: a repeat of the same logical send returns the already-queued intent unchanged; the same
  --    key with a different frozen payload is a conflict. Compared against raw_body (what the user actually
  --    typed), never the wire body -- see this migration's header note on why the wire body can legitimately
  --    differ attempt to attempt for a secure-link send. Return the replay before re-running any live gate.
  select i.* into existing
  from public.communication_delivery_intents i
  where i.organization_id = p_organization_id and i.logical_send_key = trim(p_logical_send_key);

  if existing.id is not null then
    select snap.raw_body into existing_raw_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;

    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_raw_body = p_body then
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

  -- 7. Freeze the segment estimate against the wire body (with any secure link already appended), so the
  --     charge, the "too long to send" refusal and the frozen snapshot all agree on what is actually sent.
  select est.encoding, est.segment_count into v_encoding, v_segment_count
  from public.communication_sms_estimate_segments(v_effective_body) est;
  if v_segment_count > 10 then
    raise exception 'This message is too long to send as one text.' using errcode = 'P0001';
  end if;

  -- 8. Freeze the applicable retail rate and the estimated cost (rounded up so the reservation never
  --    under-holds). A real MMS photo bills as one flat message_unit='mms' charge, matching how Twilio itself
  --    bills a picture text -- per segment only applies to plain text.
  if v_delivery_mode = 'inline_media' then
    select rr.* into rate
    from public.communication_sms_effective_retail_rate(
      sender.country_code, sender.sender_type, 'mms', currency, now()
    ) rr;
    if rate.id is null then
      raise exception 'No picture-message price is published for this destination yet.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
    cost_minor := ceil(rate.retail_rate_major * 100)::bigint;
  else
    select rr.* into rate
    from public.communication_sms_effective_retail_rate(
      sender.country_code, sender.sender_type, 'segment', currency, now()
    ) rr;
    if rate.id is null then
      raise exception 'No SMS price is published for this destination yet.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
    cost_minor := ceil(v_segment_count * rate.retail_rate_major * 100)::bigint;
  end if;

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
    select snap.raw_body into existing_raw_body
    from public.communication_sms_message_snapshots snap
    where snap.delivery_intent_id = existing.id;
    if existing.channel = 'sms'
      and existing.recipient_phone = recipient_e164
      and existing.sms_sender_identity_id = sender.id
      and existing.send_kind = p_send_kind
      and existing_raw_body = p_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end;

  -- 12. Freeze the wire body (with any link already appended), the raw draft text, encoding and segment count.
  insert into public.communication_sms_message_snapshots (
    delivery_intent_id, organization_id, body, raw_body, encoding, segment_count
  ) values (
    intent.id, p_organization_id, v_effective_body, p_body, v_encoding, v_segment_count
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

  -- 14. Persist the attachment (if any) and, for a secure-link delivery, the access link the body already
  --     names. Re-validates size and the caller's own object-key prefix server-side (advisory checks
  --     already ran in TS) -- a real MMS photo keeps 6D-2's own 5 MB/image-only ceiling; anything going out
  --     as a link gets the same 20 MB ceiling every other outbound attachment (email) already uses.
  if v_delivery_mode is not null then
    v_attachment_bytes := (v_attachment ->> 'byte_size')::bigint;
    if not private.outbound_attachment_key_allowed(
      p_organization_id, v_attachment ->> 'object_key', 'outbound-sms-attachments'
    ) then
      raise exception 'That file does not belong to this business.' using errcode = 'check_violation';
    end if;
    if v_delivery_mode = 'inline_media' and v_attachment_bytes > 5 * 1024 * 1024 then
      raise exception 'A picture must be 5 MB or smaller to send as a text message.'
        using errcode = 'check_violation';
    end if;
    if v_delivery_mode = 'secure_link' and v_attachment_bytes > 20 * 1024 * 1024 then
      raise exception 'A file must be 20 MB or smaller to send as a text message.'
        using errcode = 'check_violation';
    end if;

    insert into public.communication_outbound_attachments (
      organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key, delivery_mode
    ) values (
      p_organization_id, intent.id, v_attachment ->> 'file_name', v_attachment ->> 'mime_type',
      v_attachment_bytes, v_attachment ->> 'object_key', v_delivery_mode
    )
    on conflict (delivery_intent_id, object_key) do update set delivery_mode = excluded.delivery_mode
    returning id into v_attachment_id;

    if v_delivery_mode = 'secure_link' then
      insert into public.communication_sms_attachment_access_links (
        organization_id, delivery_intent_id, attachment_id, token_hash
      ) values (
        p_organization_id, intent.id, v_attachment_id,
        decode(v_attachment ->> 'access_token_hash', 'hex')
      )
      on conflict (token_hash) do nothing;
    end if;
  end if;

  -- 15. Hand the send to the outbox, scheduled for quiet hours.
  insert into public.communication_outbox_events (
    organization_id, delivery_intent_id, channel, available_at
  ) values (
    p_organization_id, intent.id, 'sms', available
  );

  return intent;
end;
$_$;



