-- Communications Part 7.6a: every step a message takes lands in one history, written by triggers on
-- the tables that already decide each fact. A repeated identical deferral collapses onto the last
-- row instead of adding another. Jafar can retry or cancel a stuck message, and neither action skips
-- a claim-time check -- retry only re-opens the message for the claim to judge again.

begin;

create extension if not exists pgtap with schema extensions;
select plan(33);

-- --- Shape -----------------------------------------------------------------------------------------

select has_table(
  'public', 'communication_message_events', 'the message history has a table'
);
select has_column(
  'public', 'communication_message_events', 'repeat_count',
  'a collapsed deferral streak carries how many times it repeated'
);
select has_column(
  'public', 'communication_message_events', 'seq',
  'the history has a monotonic tiebreaker, not a random uuid'
);
select table_privs_are(
  'public', 'communication_message_events', 'authenticated', array[]::text[],
  'a contractor session cannot read or write the history directly'
);
select has_trigger(
  'public', 'communication_outbox_events', 'communication_outbox_events_history_queued',
  'queueing a message writes its first history event'
);
select has_trigger(
  'public', 'communication_outbox_events', 'communication_outbox_events_history_progress',
  'every later outbox decision writes a history event'
);
select has_trigger(
  'public', 'communication_delivery_intents', 'communication_delivery_intents_history_outcome',
  'a provider delivery outcome writes a history event'
);
select has_trigger(
  'public', 'communication_inbound_messages', 'communication_inbound_messages_history_reply',
  'a reply writes a history event on the message it answers'
);
select function_privs_are(
  'public', 'retry_communication_message', array['uuid', 'text', 'text'], 'authenticated',
  array[]::text[], 'a contractor session cannot run the owner retry command'
);
select function_privs_are(
  'public', 'cancel_communication_message', array['uuid', 'text', 'text'], 'authenticated',
  array[]::text[], 'a contractor session cannot run the owner cancel command'
);

-- Park everything already due so the claim below can only pick up this test's fixture.
update public.communication_outbox_events
set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

-- --- Fixture ---------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e1000000-0000-0000-0000-000000000001', 'History Org', 'history-org', 'active');
insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at) values
  ('e1000000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');
select public.apply_organization_limit_exception(
  'e1000000-0000-0000-0000-000000000001', 'operational_email_recipients', 'unlimited', null,
  now() - interval '1 minute', null, 'history-fixture-operational', 'Fixture reason.',
  'owner@example.test');
select public.apply_organization_limit_exception(
  'e1000000-0000-0000-0000-000000000001', 'essential_email_recipients', 'unlimited', null,
  now() - interval '1 minute', null, 'history-fixture-essential', 'Fixture reason.',
  'owner@example.test');

insert into public.clients (id, organization_id, display_name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'History Customer');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'email', 'customer@history.test', true);
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state,
  provider_verified, provider_authenticated, ownership_status, dkim_status, spf_status, verified_at
) values (
  'e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'sending', 'sending.history.test', 'verified', true, true, 'passing', 'passing', 'pending',
  now() - interval '90 days'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values (
  'e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001', 'svc@sending.history.test', 'History', 'enabled',
  true, true, true
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'e6000000-0000-0000-0000-0000000000a1', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'history-main', 'customer@history.test', 'Main', '<p>Main</p>', 'Main', 'automated', 'optional',
  'e5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a1');

select results_eq(
  $$select event_kind, actor_kind from public.communication_message_events
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1'$$,
  $$values ('queued'::text, 'system'::text)$$,
  'queueing a message opens its history'
);

-- --- Deferrals collapse while the reason stays the same --------------------------------------------

-- Exactly what a claim-time defer does: name the reason on the intent, push the outbox into the
-- future. Repeated three times with one reason, then once with a different one.
update public.communication_delivery_intents
set failure_code = 'sending_paused_organization', failure_message = 'Paused.'
where id = 'e6000000-0000-0000-0000-0000000000a1';
update public.communication_outbox_events
set available_at = now() + interval '5 minutes', last_error = 'Paused.'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1';
update public.communication_outbox_events
set available_at = now() + interval '10 minutes', last_error = 'Paused.'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1';
update public.communication_outbox_events
set available_at = now() + interval '15 minutes', last_error = 'Paused.'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1';

select results_eq(
  $$select event_kind, reason_code, repeat_count
    from public.communication_message_events
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' and event_kind = 'deferred'$$,
  $$values ('deferred'::text, 'sending_paused_organization'::text, 3)$$,
  'three identical deferrals collapse into one row that counted them'
);
select is(
  (select retry_at from public.communication_message_events
   where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' and event_kind = 'deferred'),
  now() + interval '15 minutes',
  'the collapsed row carries the latest retry time, not the first'
);

update public.communication_delivery_intents
set failure_code = 'email_allowance_exhausted', failure_message = 'Allowance exhausted.'
where id = 'e6000000-0000-0000-0000-0000000000a1';
update public.communication_outbox_events
set available_at = now() + interval '30 minutes', last_error = 'Allowance exhausted.'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1';

select is(
  (select count(*) from public.communication_message_events
   where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' and event_kind = 'deferred'),
  2::bigint,
  'a new reason starts a new row, so the sequence of reasons survives'
);

-- --- The history cannot be rewritten ---------------------------------------------------------------

select throws_ok(
  $$update public.communication_message_events set reason_code = 'tampered'
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1'$$,
  '23514', null, 'a history row cannot be edited outside the deferral collapse'
);

-- --- Claim, and what the provider says afterwards ---------------------------------------------------

update public.communication_outbox_events
set available_at = now() - interval '1 minute'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1';
select public.claim_communication_outbox_event();

select is(
  (select event_kind from public.communication_message_events
   where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' order by seq desc limit 1),
  'claimed', 'a successful claim is recorded'
);

update public.communication_delivery_intents
set delivery_outcome = 'hard_bounce', delivery_outcome_at = now(),
  delivery_outcome_detail = 'Mailbox does not exist.'
where id = 'e6000000-0000-0000-0000-0000000000a1';

select results_eq(
  $$select event_kind, actor_kind, reason_message
    from public.communication_message_events
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' order by seq desc limit 1$$,
  $$values ('hard_bounce'::text, 'provider'::text, 'Mailbox does not exist.'::text)$$,
  'a provider outcome is recorded against the provider, not the contractor'
);

-- --- A reply lands on the message it answers --------------------------------------------------------

insert into public.communication_inbound_messages (
  id, organization_id, client_id, client_contact_method_id, sender_id, in_reply_to_intent_id,
  provider, provider_message_id, sender_email, subject, text_content, message_kind
) values (
  'e7000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'e5000000-0000-0000-0000-000000000001',
  'e6000000-0000-0000-0000-0000000000a1', 'brevo', 'prov-inbound-1', 'customer@history.test',
  'Re: Main', 'Thanks.', 'reply'
);

select results_eq(
  $$select event_kind, actor_kind, actor_email
    from public.communication_message_events
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' order by seq desc limit 1$$,
  $$values ('replied'::text, 'recipient'::text, 'customer@history.test'::text)$$,
  'the reply is recorded on the message it answers'
);

-- --- A resend links both directions ------------------------------------------------------------------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id,
  resent_from_intent_id
) values (
  'e6000000-0000-0000-0000-0000000000a2', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'history-resend', 'customer@history.test', 'Main', '<p>Main</p>', 'Main', 'automated', 'optional',
  'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a1'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id, available_at)
values ('e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a2',
  'infinity'::timestamptz);

select results_eq(
  $$select event_kind, related_intent_id
    from public.communication_message_events
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' order by seq desc limit 1$$,
  $$values ('resent'::text, 'e6000000-0000-0000-0000-0000000000a2'::uuid)$$,
  'the original message records that it was sent again, and points at the replacement'
);

-- --- Reading the story ---------------------------------------------------------------------------------

select is(
  (public.get_communication_message_history(
     'e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a1')
   -> 'message' ->> 'recipient_email'),
  'customer@history.test', 'the history read returns the message it belongs to'
);
select is(
  (public.get_communication_message_history(
     'e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a1')
   -> 'events' -> 0 ->> 'event_kind'),
  'queued', 'the timeline starts at the beginning'
);
select ok(
  public.get_communication_message_history(
    'e1000000-0000-0000-0000-000000000002', 'e6000000-0000-0000-0000-0000000000a1') is null,
  'another organization cannot read this message history'
);

-- --- Jafar recovery: retry ------------------------------------------------------------------------------

-- Put the message in the state a stuck manual send reaches: held for review.
update public.communication_delivery_intents
set status = 'failed', failure_code = 'manual_sender_review_required',
  failure_message = 'The original sender is no longer eligible.'
where id = 'e6000000-0000-0000-0000-0000000000a1';
update public.communication_outbox_events
set status = 'failed', claimed_at = null, claim_token = null, available_at = 'infinity'::timestamptz,
  last_error = 'The original sender is no longer eligible.'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1';

select is(
  (select event_kind from public.communication_message_events
   where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' order by seq desc limit 1),
  'held', 'a message parked for human review is recorded as held, not failed'
);

select throws_ok(
  $$select public.retry_communication_message(
      'e6000000-0000-0000-0000-0000000000a1', 'no', 'owner@example.test')$$,
  '23514', null, 'a retry without a real reason is refused'
);

select is(
  (public.retry_communication_message(
     'e6000000-0000-0000-0000-0000000000a1', 'Sender was reassigned.', 'owner@example.test')
   ->> 'changed'),
  'true', 'the owner can re-open a held message'
);
select results_eq(
  $$select event.status, intent.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1'$$,
  $$values ('pending'::text, 'queued'::text, null::text)$$,
  'a retry hands the message back to the claim with a clean slate, it does not send it'
);
select results_eq(
  $$select event_kind, actor_kind, reason_code
    from public.communication_message_events
    where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1' order by seq desc limit 1$$,
  $$values ('administrative_intervention'::text, 'platform_owner'::text, 'platform_owner_retry'::text)$$,
  'the intervention is on the record with who did it'
);
select is(
  (select count(*) from public.platform_owner_audit_events
   where event_type = 'communications.message_retried'
     and target_key = 'e6000000-0000-0000-0000-0000000000a1'),
  1::bigint, 'the retry also writes the owner audit event'
);
select is(
  (public.retry_communication_message(
     'e6000000-0000-0000-0000-0000000000a1', 'Same request again.', 'owner@example.test')
   ->> 'changed'),
  'false', 'retrying a message that is already waiting its turn changes nothing'
);

-- --- Jafar recovery: cancel -------------------------------------------------------------------------------

insert into public.communication_email_capacity_reservations (
  organization_id, delivery_intent_id, allowance_period_id, allowance_class, reservation_state
) select 'e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a1', id,
  'optional', 'reserved'
from public.communication_email_allowance_periods
where organization_id = 'e1000000-0000-0000-0000-000000000001'
on conflict on constraint communication_email_capacity_reservations_delivery_intent_key
do update set reservation_state = 'reserved', settled_at = null;

select is(
  (public.cancel_communication_message(
     'e6000000-0000-0000-0000-0000000000a1', 'Customer asked us to stop.', 'owner@example.test')
   ->> 'changed'),
  'true', 'the owner can stop a message that has not gone out'
);
select is(
  (select reservation_state from public.communication_email_capacity_reservations
   where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a1'),
  'released', 'cancelling gives the held allowance back to the organization'
);
select throws_ok(
  $$select public.cancel_communication_message(
      'e6000000-0000-0000-0000-0000000000a2', 'x', 'owner@example.test')$$,
  '23514', null, 'a cancel without a real reason is refused'
);

-- --- Jafar recovery queue -----------------------------------------------------------------------------------

update public.communication_delivery_intents
set status = 'failed', failure_code = 'send_rejected', failure_message = 'Provider rejected it.'
where id = 'e6000000-0000-0000-0000-0000000000a2';
update public.communication_outbox_events
set status = 'failed', last_error = 'Provider rejected it.'
where delivery_intent_id = 'e6000000-0000-0000-0000-0000000000a2';

select is(
  (select count(*) from jsonb_array_elements(
     public.get_communication_message_recovery_queue() -> 'messages') element
   where element ->> 'delivery_intent_id' = 'e6000000-0000-0000-0000-0000000000a2'),
  1::bigint, 'a message that stopped moving shows up in the owner recovery queue'
);

select * from finish();
rollback;
