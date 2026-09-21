-- Stage 5A: the SMS status-callback projection. Proves that Twilio MessageStatus events project the right
-- delivery_outcome, that a confirmed terminal outcome is never regressed by a later non-terminal event, that
-- conflicting terminal evidence (delivered vs failed/undelivered) becomes sms_needs_checking rather than a
-- guess, that unknown/unresolved statuses are recorded harmlessly, that the dedupe key holds, and -- the
-- load-bearing isolation -- that the email drain and the SMS drain never claim each other's rows.
--
-- Run through the Supabase MCP / CLI as a single begin/rollback call. Pure SQL; rows are keyed by MessageSid.

begin;
select plan(21);

-- ---------------------------------------------------------------------------------------------------
-- Shared tenant: one org, one client, one contact method the SMS intents can reference.
-- ---------------------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug)
values ('b5000000-0000-4000-8000-000000000001', 'Stage 5A Test Org', 'stage-5a-status-test');

insert into public.clients (id, organization_id, display_name)
values ('b5000000-0000-4000-8000-000000000002',
        'b5000000-0000-4000-8000-000000000001', 'Stage 5A Test Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('b5000000-0000-4000-8000-000000000003',
        'b5000000-0000-4000-8000-000000000001',
        'b5000000-0000-4000-8000-000000000002', 'phone', '+15005550006');

-- Seed an SMS delivery intent (submitted, with a MessageSid) plus one twilio status callback for it. An
-- optional pre_outcome simulates an already-projected terminal state so protection/conflict is deterministic.
create function pg_temp.seed_sms(p_msgsid text, p_status text, p_pre_outcome text)
returns void language plpgsql as $$
declare v_intent uuid;
begin
  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, channel, logical_send_key,
    recipient_phone, provider_message_id, status, accepted_at, delivery_outcome)
  values ('b5000000-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000002',
    'b5000000-0000-4000-8000-000000000003', 'sms', 'sms:' || p_msgsid,
    '+15005550006', p_msgsid, 'submitted', now(), p_pre_outcome)
  returning id into v_intent;

  insert into public.communication_provider_callback_events (
    provider, channel, provider_event_key, delivery_intent_id, event_kind, payload, received_at)
  values ('twilio', 'sms', p_msgsid || ':' || p_status, v_intent, p_status, '{}'::jsonb, now());
end $$;

-- Add another status callback to an already-seeded message (out-of-order / late arrival).
create function pg_temp.add_cb(p_msgsid text, p_status text)
returns void language plpgsql as $$
begin
  insert into public.communication_provider_callback_events (
    provider, channel, provider_event_key, delivery_intent_id, event_kind, payload, received_at)
  values ('twilio', 'sms', p_msgsid || ':' || p_status,
    (select id from public.communication_delivery_intents where provider_message_id = p_msgsid),
    p_status, '{}'::jsonb, now() + interval '1 second');
end $$;

-- Projection cases.
select pg_temp.seed_sms('SM00000000000000000000000000000001', 'delivered', null);            -- fresh delivered
select pg_temp.seed_sms('SM00000000000000000000000000000002', 'sent', 'sms_failed');          -- terminal + late non-terminal
select pg_temp.seed_sms('SM00000000000000000000000000000003', 'undelivered', 'sms_delivered');-- conflict (success then failure)
select pg_temp.seed_sms('SM00000000000000000000000000000004', 'delivered', 'sms_failed');     -- conflict (failure then success)
select pg_temp.seed_sms('SM00000000000000000000000000000005', 'delivered', 'sms_needs_checking'); -- never regress out
select pg_temp.seed_sms('SM00000000000000000000000000000006', 'failed', 'sms_undelivered');   -- same-class, first word stands
select pg_temp.seed_sms('SM00000000000000000000000000000007', 'sent', null);                  -- pre-delivery only
select pg_temp.seed_sms('SM00000000000000000000000000000008', 'delivered', null);             -- out-of-order base
select pg_temp.add_cb('SM00000000000000000000000000000008', 'sent');                          -- late non-terminal

-- Unresolved: a status for a message we never sent (no intent).
insert into public.communication_provider_callback_events (provider, channel, provider_event_key, delivery_intent_id, event_kind, payload)
values ('twilio', 'sms', 'SM0000000000000000000000000000ffff:delivered', null, 'delivered', '{}'::jsonb);

-- Isolation fixtures: a twilio row and a brevo row, both unresolved.
insert into public.communication_provider_callback_events (provider, channel, provider_event_key, delivery_intent_id, event_kind, payload)
values ('twilio', 'sms', 'ISO-TWILIO:delivered', null, 'delivered', '{}'::jsonb);
insert into public.communication_provider_callback_events (provider, channel, provider_event_key, delivery_intent_id, event_kind, payload)
values ('brevo', 'email', 'ISO-BREVO-A:delivered', null, 'delivered', '{}'::jsonb);

-- ---------------------------------------------------------------------------------------------------
-- 1. The email drain must never claim a twilio row.
-- ---------------------------------------------------------------------------------------------------

select public.process_communication_provider_callbacks(2000);

select is(
  (select count(*)::int from public.communication_provider_callback_events
    where provider = 'twilio' and processed_at is not null),
  0, 'the email drain claims no twilio rows');

select ok(
  (select processed_at is not null from public.communication_provider_callback_events
    where provider = 'brevo' and provider_event_key = 'ISO-BREVO-A:delivered'),
  'the email drain still claims a brevo row');

-- A fresh, still-unprocessed brevo row to prove the SMS drain skips it.
insert into public.communication_provider_callback_events (provider, channel, provider_event_key, delivery_intent_id, event_kind, payload)
values ('brevo', 'email', 'ISO-BREVO-B:delivered', null, 'delivered', '{}'::jsonb);

-- ---------------------------------------------------------------------------------------------------
-- 2. The SMS drain: project outcomes; never touch brevo.
-- ---------------------------------------------------------------------------------------------------

select public.process_communication_sms_provider_callbacks(2000);

select ok(
  (select processed_at is null from public.communication_provider_callback_events
    where provider = 'brevo' and provider_event_key = 'ISO-BREVO-B:delivered'),
  'the SMS drain claims no brevo row');

select is(
  (select count(*)::int from public.communication_provider_callback_events
    where provider = 'twilio' and processed_at is null),
  0, 'the SMS drain claims every twilio row');

-- Projection outcomes.
select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000001'),
  'sms_delivered', 'a delivered status projects sms_delivered');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000002'),
  'sms_failed', 'a late non-terminal (sent) never regresses a terminal failure');

select is((select normalized_kind from public.communication_provider_callback_events
  where provider = 'twilio' and provider_event_key = 'SM00000000000000000000000000000002:sent'),
  'sms_sent', 'a sent status is recorded as sms_sent');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000003'),
  'sms_needs_checking', 'delivered then undelivered conflicts to sms_needs_checking');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000004'),
  'sms_needs_checking', 'failed then delivered conflicts to sms_needs_checking');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000005'),
  'sms_needs_checking', 'a later terminal never regresses out of sms_needs_checking');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000006'),
  'sms_undelivered', 'same-class terminals keep the first word (undelivered stands over failed)');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000007'),
  null, 'a sent-only status writes no delivery outcome');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000008'),
  'sms_delivered', 'a late sent after a delivered leaves the delivered outcome standing');

select is((select normalized_kind from public.communication_provider_callback_events
  where provider = 'twilio' and provider_event_key = 'SM0000000000000000000000000000ffff:delivered'),
  'sms_delivered', 'an unknown MessageSid is normalized and recorded');

select ok(
  (select processed_at is not null from public.communication_provider_callback_events
    where provider = 'twilio' and provider_event_key = 'SM0000000000000000000000000000ffff:delivered'),
  'an unresolved twilio status is marked processed, not left to loop');

select is(
  (select organization_id from public.communication_provider_callback_events
    where provider = 'twilio' and provider_event_key = 'SM0000000000000000000000000000ffff:delivered'),
  null, 'an unresolved twilio status stays organization-less so nothing counts it');

-- ---------------------------------------------------------------------------------------------------
-- 3. Idempotency and dedupe.
-- ---------------------------------------------------------------------------------------------------

-- A second drain changes nothing (processed_at gate).
select is(public.process_communication_sms_provider_callbacks(2000), 0,
  'a second SMS drain processes zero rows');

select is((select delivery_outcome from public.communication_delivery_intents
  where provider_message_id = 'SM00000000000000000000000000000001'),
  'sms_delivered', 'a re-drain does not disturb a settled outcome');

select throws_ok(
  $$insert into public.communication_provider_callback_events (provider, channel, provider_event_key, event_kind, payload)
    values ('twilio', 'sms', 'SM00000000000000000000000000000001:delivered', 'delivered', '{}'::jsonb)$$,
  '23505', null,
  'the shared dedupe key rejects a duplicate (provider, event) status callback');

-- The widened outcome vocabulary admits every SMS terminal value.
select lives_ok(
  $$update public.communication_delivery_intents set delivery_outcome = 'sms_needs_checking'
    where provider_message_id = 'SM00000000000000000000000000000001'$$,
  'the delivery_outcome check admits the SMS vocabulary');

-- The outcome-history trigger writes an SMS timeline event (message_events event_kind must admit sms_*).
select ok(
  exists (select 1 from public.communication_message_events
    where delivery_intent_id = (select id from public.communication_delivery_intents
      where provider_message_id = 'SM00000000000000000000000000000008')
      and event_kind = 'sms_delivered'),
  'a projected SMS outcome writes its message-timeline event');

select * from finish();
rollback;
