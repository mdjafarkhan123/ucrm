-- Messenger Part 7 (docs/messenger-implementation-plan.md § Server shape, Reply): staff reply to a Messenger
-- customer from the inbox. GoHighLevel's behaviour: the reply goes out from the Facebook Page the customer wrote
-- to, only inside Meta's 24-hour window, and the thread shows when Meta reports it delivered and read.
--
-- 1. Sent messages: the shared delivery tables accept Messenger. A Messenger send is addressed to the customer's
--    Messenger identity (their Page-scoped ID), not to a phone or email, so it has no contact method.
-- 2. Queuing a reply: checks permission, the Page, and the 24-hour window, then queues it once per send key.
-- 3. The send queue: claim (re-checking the Page and the window), finalize, and release of abandoned claims,
--    the same contract as the SMS queue without its money and consent steps (Messenger has neither).
-- 4. Meta's reports: delivered and read watermarks, and echoes. Our own echo confirms a send whose outcome was
--    unknown; an echo from somewhere else (the Page's own Facebook inbox) is added to the thread so it stays
--    complete.
-- 5. The one-minute wake also runs when replies are waiting.

-- 1. Sent messages --------------------------------------------------------------------------------------------

alter table public.communication_delivery_intents
  add column messenger_identity_id uuid,
  -- Meta's own time for a sent message (from its echo); delivered and read watermarks compare against it.
  add column provider_sent_at timestamptz,
  add constraint communication_delivery_intents_messenger_identity_fk
    foreign key (organization_id, messenger_identity_id)
    references public.communication_messenger_identities (organization_id, id) on delete restrict;

alter table public.communication_delivery_intents
  alter column client_contact_method_id drop not null,
  add constraint communication_delivery_intents_contact_method_required_check
    check ((channel = 'messenger') = (client_contact_method_id is null)),
  add constraint communication_delivery_intents_messenger_identity_check
    check ((channel = 'messenger') = (messenger_identity_id is not null)),
  drop constraint communication_delivery_intents_channel_check,
  add constraint communication_delivery_intents_channel_check
    check (channel in ('email', 'sms', 'messenger')),
  drop constraint communication_delivery_intents_channel_payload_check,
  add constraint communication_delivery_intents_channel_payload_check check (
    (channel = 'email' and recipient_email is not null and position('@' in recipient_email) > 1
      and recipient_phone is null and subject is not null
      and char_length(btrim(subject)) between 1 and 998
      and html_content is not null and char_length(btrim(html_content)) > 0
      and text_content is not null and char_length(btrim(text_content)) > 0
      and sms_sender_identity_id is null)
    or (channel = 'sms' and recipient_email is null and recipient_phone is not null
      and recipient_phone ~ '^\+[1-9][0-9]{7,14}$' and subject is null and html_content is null
      and text_content is null and sender_id is null and reply_alias_id is null)
    -- Meta's text limit is 2,000 characters.
    or (channel = 'messenger' and recipient_email is null and recipient_phone is null and subject is null
      and html_content is null and text_content is not null and char_length(text_content) <= 2000
      and sender_id is null and reply_alias_id is null and sms_sender_identity_id is null)
  ),
  drop constraint communication_delivery_intents_delivery_outcome_check,
  add constraint communication_delivery_intents_delivery_outcome_check check (delivery_outcome in (
    'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'deferred', 'blocked', 'unsubscribed',
    'sms_delivered', 'sms_undelivered', 'sms_failed', 'sms_needs_checking',
    'messenger_delivered', 'messenger_read'
  ));

-- Delivered and read reports name a customer and a time: everything sent to them up to then.
create index communication_delivery_intents_messenger_sent_idx
  on public.communication_delivery_intents (messenger_identity_id, accepted_at)
  where channel = 'messenger' and status = 'submitted';

alter table public.communication_message_events
  drop constraint communication_message_events_event_kind_check,
  add constraint communication_message_events_event_kind_check check (event_kind in (
    'queued', 'claimed', 'deferred', 'held', 'cancelled', 'sent', 'send_failed', 'submission_unknown',
    'delivered', 'soft_bounce', 'hard_bounce', 'complaint', 'provider_deferred', 'blocked', 'unsubscribed',
    'replied', 'resent', 'administrative_intervention',
    'sms_delivered', 'sms_undelivered', 'sms_failed', 'sms_needs_checking',
    'messenger_delivered', 'messenger_read'
  ));

alter table public.communication_outbox_events
  drop constraint communication_outbox_events_channel_check,
  add constraint communication_outbox_events_channel_check
    check (channel in ('email', 'sms', 'messenger'));

create index communication_outbox_events_messenger_claim_idx
  on public.communication_outbox_events (available_at, created_at, id)
  where channel = 'messenger' and status in ('pending', 'failed');

-- 2. Queuing a reply ------------------------------------------------------------------------------------------

create function public.enqueue_conversation_reply_messenger(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_client_id uuid,
  target_logical_send_key text,
  target_body text
)
returns public.communication_delivery_intents
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  identity_row public.communication_messenger_identities;
  connection_row public.communication_messenger_connections;
  existing public.communication_delivery_intents;
  intent public.communication_delivery_intents;
begin
  if target_actor_user_id is null then
    raise exception 'a send must record who sent it' using errcode = 'P0001';
  end if;
  if not private.member_has_permission(target_organization_id, target_actor_user_id, 'conversations.send')
    or not private.member_has_permission(target_organization_id, target_actor_user_id, 'customers.view') then
    raise exception 'You do not have permission to send a customer message.'
      using errcode = 'insufficient_privilege';
  end if;
  if target_logical_send_key is null or char_length(btrim(target_logical_send_key)) = 0 then
    raise exception 'a send must carry a logical send key' using errcode = 'P0001';
  end if;
  if target_body is null or char_length(btrim(target_body)) = 0 then
    raise exception 'Enter a message.' using errcode = 'check_violation';
  end if;
  if char_length(target_body) > 2000 then
    raise exception 'A Messenger message can be at most 2,000 characters.' using errcode = 'check_violation';
  end if;

  -- The same send pressed twice (a retry after a dropped connection) is the same message.
  select * into existing
  from public.communication_delivery_intents
  where organization_id = target_organization_id and logical_send_key = btrim(target_logical_send_key);
  if existing.id is not null then
    if existing.channel = 'messenger' and existing.client_id = target_client_id
      and existing.text_content = target_body then
      return existing;
    end if;
    raise exception 'This message was already queued with different details.' using errcode = 'unique_violation';
  end if;

  -- The Messenger identity this customer wrote from most recently: the reply goes back the same way.
  select identity.* into identity_row
  from public.communication_messenger_identities identity
  join public.clients client
    on client.organization_id = identity.organization_id and client.id = identity.client_id
  where identity.organization_id = target_organization_id
    and identity.client_id = target_client_id
    and client.deleted_at is null
  order by identity.last_inbound_at desc nulls last, identity.created_at desc
  limit 1
  for share of identity, client;

  if identity_row.id is null then
    raise exception 'This customer has not messaged you on Messenger.' using errcode = 'foreign_key_violation';
  end if;

  select * into connection_row
  from public.communication_messenger_connections
  where id = identity_row.connection_id;

  if connection_row.status = 'disconnected' then
    raise exception 'The Facebook Page is disconnected, so Messenger replies can''t be sent.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if connection_row.status = 'needs_reconnect' then
    raise exception 'Facebook stopped accepting messages from this Page. Reconnect it in Settings to reply.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Meta's rule: a Page may answer for 24 hours after the customer's last message.
  if identity_row.last_inbound_at is null or identity_row.last_inbound_at <= now() - interval '24 hours' then
    raise exception 'Messenger only allows replies within 24 hours of the customer''s last message.'
      using errcode = 'P0001';
  end if;

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, messenger_identity_id, channel, logical_send_key,
    text_content, status, send_kind, created_by
  ) values (
    target_organization_id, target_client_id, null, identity_row.id, 'messenger',
    btrim(target_logical_send_key), target_body, 'queued', 'manual', target_actor_user_id
  )
  returning * into intent;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id, channel)
  values (target_organization_id, intent.id, 'messenger');

  return intent;
end;
$$;

revoke all on function public.enqueue_conversation_reply_messenger(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.enqueue_conversation_reply_messenger(uuid, uuid, uuid, text, text)
  to service_role;

-- 3. The send queue -------------------------------------------------------------------------------------------

-- Ends a queued send without contacting Meta, with the reason staff will read on the message.
create function private.cancel_communication_messenger_send(
  p_outbox_event_id uuid,
  p_delivery_intent_id uuid,
  p_failure_code text,
  p_failure_message text
)
returns void
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $$
  update public.communication_delivery_intents
  set status = 'cancelled', failure_code = p_failure_code, failure_message = p_failure_message
  where id = p_delivery_intent_id;
  update public.communication_outbox_events
  set status = 'cancelled', claimed_at = null, claim_token = null, last_error = p_failure_message
  where id = p_outbox_event_id;
$$;

revoke all on function private.cancel_communication_messenger_send(uuid, uuid, text, text)
  from public, anon, authenticated;

create function public.claim_communication_messenger_outbox_event()
returns table (
  outbox_event_id uuid,
  delivery_intent_id uuid,
  organization_id uuid,
  connection_id uuid,
  page_id text,
  psid text,
  claim_token uuid,
  attempt_number integer,
  body text
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $$
declare
  candidate record;
  new_claim_token uuid;
  new_attempt integer;
begin
  for candidate in
    select event.id as event_id, event.delivery_intent_id as intent_id, event.attempt_count,
      intent.organization_id as org_id, intent.text_content,
      identity.psid as identity_psid, identity.last_inbound_at,
      connection.id as conn_id, connection.page_id as conn_page_id, connection.status as conn_status
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    join public.communication_messenger_identities identity on identity.id = intent.messenger_identity_id
    join public.communication_messenger_connections connection on connection.id = identity.connection_id
    where event.channel = 'messenger' and event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    -- The Page or the window can change while a reply waits (a retry minutes later): never send outside them.
    if candidate.conn_status <> 'active' then
      perform private.cancel_communication_messenger_send(
        candidate.event_id, candidate.intent_id,
        case when candidate.conn_status = 'disconnected'
          then 'messenger_page_disconnected' else 'messenger_page_needs_reconnect' end,
        case when candidate.conn_status = 'disconnected'
          then 'The Facebook Page was disconnected before this message was sent.'
          else 'Facebook stopped accepting messages from this Page. Reconnect it in Settings.' end);
      continue;
    end if;
    if candidate.last_inbound_at is null or candidate.last_inbound_at <= now() - interval '24 hours' then
      perform private.cancel_communication_messenger_send(
        candidate.event_id, candidate.intent_id, 'messenger_window_closed',
        'Messenger''s 24-hour reply window closed before this message was sent.');
      continue;
    end if;

    new_claim_token := gen_random_uuid();
    new_attempt := candidate.attempt_count + 1;

    update public.communication_outbox_events
    set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = new_attempt, last_error = null
    where id = candidate.event_id;
    update public.communication_delivery_intents
    set status = 'claimed', failure_code = null, failure_message = null
    where id = candidate.intent_id;

    return query select candidate.event_id, candidate.intent_id, candidate.org_id, candidate.conn_id,
      candidate.conn_page_id, candidate.identity_psid, new_claim_token, new_attempt, candidate.text_content;
    return;
  end loop;
end;
$$;

revoke all on function public.claim_communication_messenger_outbox_event() from public, anon, authenticated;
grant execute on function public.claim_communication_messenger_outbox_event() to service_role;

create function public.finalize_communication_messenger_outbox_event(
  target_outbox_event_id uuid,
  target_claim_token uuid,
  target_outcome text,
  target_provider_message_id text default null,
  target_failure_code text default null,
  target_failure_message text default null
)
returns table (outbox_status text, intent_status text, attempt_count integer, available_at timestamptz)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  claimed_event public.communication_outbox_events;
  next_available_at timestamptz;
  v_failure_code text := nullif(btrim(target_failure_code), '');
  v_failure_message text := nullif(btrim(target_failure_message), '');
begin
  if target_outcome not in ('submitted', 'retry', 'submission_unknown', 'cancelled') then
    raise exception 'The Messenger outcome is invalid.' using errcode = 'check_violation';
  end if;

  select * into claimed_event
  from public.communication_outbox_events
  where id = target_outbox_event_id
  for update;

  if not found then
    raise exception 'The Messenger outbox event does not exist.' using errcode = 'no_data_found';
  end if;
  if claimed_event.channel <> 'messenger' then
    raise exception 'This is not a Messenger outbox event.' using errcode = 'check_violation';
  end if;

  -- Already finalized by this same claim (a repeated call): report what was recorded.
  if claimed_event.status <> 'processing' then
    if claimed_event.finalized_claim_token is distinct from target_claim_token then
      raise exception 'The Messenger claim is no longer current.' using errcode = 'object_not_in_prerequisite_state';
    end if;
    return query
    select claimed_event.status, intent.status, claimed_event.attempt_count, claimed_event.available_at
    from public.communication_delivery_intents intent
    where intent.id = claimed_event.delivery_intent_id;
    return;
  end if;

  if claimed_event.claim_token is distinct from target_claim_token then
    raise exception 'The Messenger claim token is invalid.' using errcode = 'insufficient_privilege';
  end if;

  if target_outcome = 'submitted' then
    if nullif(btrim(target_provider_message_id), '') is null then
      raise exception 'A sent Messenger message requires Meta''s message ID.' using errcode = 'not_null_violation';
    end if;
    -- Our own echo can arrive first and record the same ID (metadata carries the intent ID), so it is kept.
    update public.communication_delivery_intents
    set status = 'submitted', provider_message_id = btrim(target_provider_message_id),
      accepted_at = coalesce(accepted_at, now()), failure_code = null, failure_message = null
    where id = claimed_event.delivery_intent_id;
    update public.communication_outbox_events
    set status = 'submitted', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = null
    where id = claimed_event.id;

  elsif target_outcome = 'retry' then
    -- Short steps: the 24-hour window is the hard limit, and the claim re-checks it before every try.
    next_available_at := case claimed_event.attempt_count
      when 1 then now() + interval '1 minute'
      when 2 then now() + interval '5 minutes'
      when 3 then now() + interval '30 minutes'
      else 'infinity'::timestamptz
    end;
    update public.communication_delivery_intents
    set status = 'failed', provider_message_id = null, accepted_at = null,
      failure_code = v_failure_code,
      failure_message = v_failure_message
    where id = claimed_event.delivery_intent_id;
    update public.communication_outbox_events
    set status = 'failed', available_at = next_available_at, claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      last_error = v_failure_message
    where id = claimed_event.id;

  elsif target_outcome = 'cancelled' then
    update public.communication_delivery_intents
    set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = v_failure_code,
      failure_message = v_failure_message
    where id = claimed_event.delivery_intent_id;
    update public.communication_outbox_events
    set status = 'cancelled', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      last_error = v_failure_message
    where id = claimed_event.id;

    -- Meta refused the Page's key or permission: the Settings card shows "reconnect" instead of failing quietly.
    if v_failure_code in ('token_invalid', 'permission_missing') then
      update public.communication_messenger_connections connection
      set status = 'needs_reconnect',
        needs_reconnect_reason = v_failure_code, updated_at = now()
      from public.communication_delivery_intents intent
      join public.communication_messenger_identities identity on identity.id = intent.messenger_identity_id
      where intent.id = claimed_event.delivery_intent_id
        and connection.id = identity.connection_id
        and connection.status = 'active';
    end if;

  else
    -- Our echo (which carries the intent ID) settles this later if Meta did take the message.
    update public.communication_delivery_intents
    set status = 'submission_unknown', accepted_at = null,
      failure_code = v_failure_code,
      failure_message = v_failure_message
    where id = claimed_event.delivery_intent_id and status <> 'submitted';
    update public.communication_outbox_events
    set status = 'submission_unknown', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      last_error = v_failure_message
    where id = claimed_event.id;
  end if;

  return query
  select event.status, intent.status, event.attempt_count, event.available_at
  from public.communication_outbox_events event
  join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
  where event.id = claimed_event.id;
end;
$$;

revoke all on function public.finalize_communication_messenger_outbox_event(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_messenger_outbox_event(uuid, uuid, text, text, text, text)
  to service_role;

create function public.quarantine_stale_communication_messenger_claims(
  batch_size integer default 50,
  stale_after interval default '5 minutes'
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  quarantined_count integer;
begin
  if batch_size < 1 or batch_size > 100 then
    raise exception 'The stale Messenger batch is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if stale_after < interval '1 minute' or stale_after > interval '1 day' then
    raise exception 'The stale Messenger threshold is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  -- A worker died mid-send: Meta may or may not have the message, so it is never resent blindly.
  with stale as (
    select id
    from public.communication_outbox_events
    where channel = 'messenger' and status = 'processing' and claimed_at <= now() - stale_after
    order by claimed_at, id
    limit batch_size
    for update skip locked
  ), quarantined as (
    update public.communication_outbox_events event
    set status = 'submission_unknown', finalized_claim_token = event.claim_token,
      claimed_at = null, claim_token = null,
      last_error = 'The worker stopped before Meta''s answer was recorded.'
    from stale
    where event.id = stale.id
    returning event.delivery_intent_id
  ), updated_intents as (
    update public.communication_delivery_intents intent
    set status = 'submission_unknown', failure_code = 'worker_lease_expired',
      failure_message = 'The worker stopped before Meta''s answer was recorded.'
    from quarantined
    where intent.id = quarantined.delivery_intent_id and intent.status <> 'submitted'
    returning intent.id
  )
  select count(*)::integer into quarantined_count from quarantined;

  return quarantined_count;
end;
$$;

revoke all on function public.quarantine_stale_communication_messenger_claims(integer, interval)
  from public, anon, authenticated;
grant execute on function public.quarantine_stale_communication_messenger_claims(integer, interval)
  to service_role;

-- 4. Meta's reports -------------------------------------------------------------------------------------------

-- Delivered and read are watermarks: everything the Page sent this person at or before that time. Read implies
-- delivered, and a message never steps back from read to delivered. Returns how many messages changed.
create function public.record_communication_messenger_receipt(
  target_connection_id uuid,
  target_psid text,
  target_kind text,
  target_watermark timestamptz,
  target_mids text[] default '{}'
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  identity_id uuid;
  outcome text;
  changed integer;
begin
  if target_kind not in ('delivered', 'read') then
    raise exception 'The Messenger receipt kind is invalid.' using errcode = 'check_violation';
  end if;
  outcome := 'messenger_' || target_kind;

  select id into identity_id
  from public.communication_messenger_identities
  where connection_id = target_connection_id and psid = target_psid;
  if identity_id is null then
    return 0;
  end if;

  -- Meta's echo time when we have it (same clock as the watermark), else the moment Meta accepted the send,
  -- which is a little later than Meta's own time, so a message is never marked early.
  update public.communication_delivery_intents
  set delivery_outcome = outcome, delivery_outcome_at = least(coalesce(target_watermark, now()), now())
  where messenger_identity_id = identity_id
    and channel = 'messenger'
    and status = 'submitted'
    and (
      coalesce(provider_sent_at, accepted_at) <= target_watermark
      or provider_message_id = any (coalesce(target_mids, '{}'))
    )
    and (delivery_outcome is null or (outcome = 'messenger_read' and delivery_outcome = 'messenger_delivered'));
  get diagnostics changed = row_count;
  return changed;
end;
$$;

revoke all on function public.record_communication_messenger_receipt(uuid, text, text, timestamptz, text[])
  from public, anon, authenticated;
grant execute on function public.record_communication_messenger_receipt(uuid, text, text, timestamptz, text[])
  to service_role;

-- The Page sent a message. One of ours (its metadata is our intent ID, or Meta's ID is already recorded): note
-- Meta's time and settle an unknown outcome. Anyone else's (the Page's Facebook inbox, Meta Business Suite):
-- add it to the thread as sent, so the conversation matches what the customer sees.
create function public.record_communication_messenger_echo(
  target_connection_id uuid,
  target_psid text,
  target_mid text,
  target_metadata text,
  target_text text,
  target_sent_at timestamptz,
  target_from_this_app boolean
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  identity_row public.communication_messenger_identities;
  intent_id uuid;
  sent_at timestamptz := least(coalesce(target_sent_at, now()), now());
  body text := left(coalesce(target_text, ''), 2000);
begin
  if target_mid is null or btrim(target_mid) = '' then
    return null;
  end if;

  select * into identity_row
  from public.communication_messenger_identities
  where connection_id = target_connection_id and psid = target_psid;
  if identity_row.id is null then
    -- Someone who never wrote to the Page in this CRM: nothing to attach the message to.
    return null;
  end if;

  select id into intent_id
  from public.communication_delivery_intents
  where provider_message_id = target_mid;

  if intent_id is null and target_metadata ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select id into intent_id
    from public.communication_delivery_intents
    where id = target_metadata::uuid and messenger_identity_id = identity_row.id;
  end if;

  if intent_id is not null then
    update public.communication_delivery_intents
    set provider_sent_at = coalesce(provider_sent_at, sent_at),
      provider_message_id = coalesce(provider_message_id, target_mid),
      status = case when status in ('submission_unknown', 'claimed') then 'submitted' else status end,
      accepted_at = case when status in ('submission_unknown', 'claimed') then coalesce(accepted_at, now())
        else accepted_at end,
      failure_code = case when status in ('submission_unknown', 'claimed') then null else failure_code end,
      failure_message = case when status in ('submission_unknown', 'claimed') then null else failure_message end
    where id = intent_id;
    return intent_id;
  end if;

  -- Our own send that we cannot match is left alone rather than shown twice.
  if target_from_this_app or char_length(btrim(body)) = 0 then
    return null;
  end if;

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, messenger_identity_id, channel, logical_send_key,
    text_content, status, send_kind, created_by, provider_message_id, accepted_at, provider_sent_at, created_at
  ) values (
    identity_row.organization_id, identity_row.client_id, null, identity_row.id, 'messenger',
    'messenger-echo:' || left(target_mid, 180), body, 'submitted', 'manual', null, target_mid, sent_at, sent_at,
    sent_at
  )
  on conflict (organization_id, logical_send_key) do nothing
  returning id into intent_id;

  return intent_id;
end;
$$;

revoke all on function public.record_communication_messenger_echo(uuid, text, text, text, text, timestamptz, boolean)
  from public, anon, authenticated;
grant execute on function public.record_communication_messenger_echo(uuid, text, text, text, text, timestamptz, boolean)
  to service_role;

-- 5. The one-minute wake --------------------------------------------------------------------------------------
-- Unchanged from 20261228090000_messenger_inbound_webhook.sql except that waiting replies also wake the worker.

create or replace function public.dispatch_communication_messenger_worker_wake()
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_worker_name constant text := 'communications-messenger-inbound';
  v_job_name constant text := 'communications-messenger-inbound-wake-one-minute';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  -- Nothing waiting: no request, no ledger row. Most minutes end here.
  if not exists (
    select 1 from public.communication_messenger_webhook_events
    where processed_at is null and processing_attempts < 10
  ) and not exists (
    select 1 from public.communication_outbox_events
    where channel = 'messenger'
      and ((status in ('pending', 'failed') and available_at <= now())
        or (status = 'processing' and claimed_at <= now() - interval '5 minutes'))
  ) then
    return;
  end if;

  select decrypted_secret into v_target_url
  from vault.decrypted_secrets
  where name = 'communications_messenger_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets
  where name = 'communications_worker_secret';

  if v_target_url is null or v_bearer is null then
    raise exception 'The Messenger worker cron target url or bearer secret is not configured.'
      using errcode = 'no_data_found';
  end if;

  select net.http_post(
    url := v_target_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_bearer,
      'X-Wake-Correlation-Id', v_correlation::text
    ),
    body := jsonb_build_object('wake_correlation_id', v_correlation),
    timeout_milliseconds := 50000
  ) into v_request_id;

  perform public.record_communication_worker_wake_dispatch(v_worker_name, v_job_name, v_correlation, v_request_id);

  delete from private.communication_worker_wake_ledger
  where worker_name = v_worker_name
    and dispatched_at < now() - interval '7 days';
end;
$$;
