-- A1 (R1): the return path. Proves that a Brevo callback opens the right suppression, that the outbox
-- claim refuses the right classes, that a terminal outcome is never un-set by a later stray event, and
-- that one poison callback cannot wedge the batch.
--
-- Run through the Supabase MCP as a single begin/rollback call. Pure SQL (no psql meta-commands); every
-- row is identified by its unique recipient address.

begin;
select plan(17);

-- ---------------------------------------------------------------------------------------------------
-- Shared tenant. One org, one client, one contact method the processor intents can reference.
-- ---------------------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug)
values ('a1000000-0000-4000-8000-000000000001', 'R1 Test Org', 'r1-return-path-test');

insert into public.clients (id, organization_id, display_name)
values ('a1000000-0000-4000-8000-000000000002',
        'a1000000-0000-4000-8000-000000000001', 'R1 Test Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, normalized_value)
values ('a1000000-0000-4000-8000-000000000003',
        'a1000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000002', 'email', 'shared@r1.test', 'shared@r1.test');

-- Seed a delivery intent + one provider callback for it.
create function pg_temp.seed_proc(p_email text, p_event text, p_pre_outcome text)
returns void language plpgsql as $$
declare v_intent uuid;
begin
  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
    subject, html_content, text_content, delivery_outcome)
  values ('a1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000003', 'proc:' || p_email || ':' || p_event, p_email,
    's', '<p>h</p>', 't', p_pre_outcome)
  returning id into v_intent;

  insert into public.communication_provider_callback_events (
    provider_event_key, delivery_intent_id, event_kind, payload, received_at)
  values (p_email || ':' || p_event || ':' || gen_random_uuid()::text, v_intent, p_event, '{}'::jsonb, now());
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Processor: a callback opens the right suppression and records the outcome.
-- ---------------------------------------------------------------------------------------------------

select pg_temp.seed_proc('unsub@r1.test', 'unsubscribed', null);
select pg_temp.seed_proc('complaint@r1.test', 'complaint', null);
select pg_temp.seed_proc('bounce@r1.test', 'hard_bounce', null);
-- A message already terminally hard-bounced, then a stray 'delivered' arrives late.
select pg_temp.seed_proc('terminal@r1.test', 'delivered', 'hard_bounce');

select public.process_communication_provider_callbacks(2000);

select ok(
  exists (select 1 from public.communication_email_suppressions
    where organization_id = 'a1000000-0000-4000-8000-000000000001'
      and recipient_email = 'unsub@r1.test' and reason = 'unsubscribe' and released_at is null),
  'an unsubscribed callback opens a suppression with reason unsubscribe');

select is(
  (select delivery_outcome from public.communication_delivery_intents where recipient_email = 'unsub@r1.test'),
  'unsubscribed', 'an unsubscribed callback records the delivery outcome');

select ok(
  exists (select 1 from public.communication_email_suppressions
    where organization_id = 'a1000000-0000-4000-8000-000000000001'
      and recipient_email = 'complaint@r1.test' and reason = 'complaint' and released_at is null),
  'a complaint callback opens a complaint suppression');

select is(
  (select delivery_outcome from public.communication_delivery_intents where recipient_email = 'complaint@r1.test'),
  'complaint', 'a complaint callback records the delivery outcome');

select ok(
  exists (select 1 from public.communication_email_suppressions
    where organization_id = 'a1000000-0000-4000-8000-000000000001'
      and recipient_email = 'bounce@r1.test' and reason = 'hard_bounce' and released_at is null),
  'a hard-bounce callback opens a hard_bounce suppression');

select is(
  (select delivery_outcome from public.communication_delivery_intents where recipient_email = 'terminal@r1.test'),
  'hard_bounce', 'a late delivered event never un-sets a terminal hard_bounce outcome');

select ok(
  exists (select 1 from public.communication_email_reputation_state
    where organization_id = 'a1000000-0000-4000-8000-000000000001' and evaluation_requested_at is not null),
  'an adverse event requests a reputation re-evaluation');

-- ---------------------------------------------------------------------------------------------------
-- Poison isolation: one callback that fails on insert must not stop a good one in the same batch.
-- A rollback-scoped trigger makes exactly one suppression insert throw.
-- ---------------------------------------------------------------------------------------------------

create function pg_temp.poison() returns trigger language plpgsql as $$
begin
  if new.recipient_email = 'poison@r1.test' then
    raise exception 'poison callback';
  end if;
  return new;
end $$;

create trigger zzz_r1_poison before insert on public.communication_email_suppressions
  for each row execute function pg_temp.poison();

select pg_temp.seed_proc('good@r1.test', 'hard_bounce', null);
select pg_temp.seed_proc('poison@r1.test', 'hard_bounce', null);

select public.process_communication_provider_callbacks(2000);

select ok(
  exists (select 1 from public.communication_email_suppressions
    where recipient_email = 'good@r1.test' and reason = 'hard_bounce' and released_at is null),
  'the good callback in a poisoned batch still opens its suppression');

select ok(
  not exists (select 1 from public.communication_email_suppressions
    where recipient_email = 'poison@r1.test'),
  'the poison callback opened no suppression (its subtransaction rolled back)');

select is(
  (select cb.processing_attempts
   from public.communication_provider_callback_events cb
   join public.communication_delivery_intents i on i.id = cb.delivery_intent_id
   where i.recipient_email = 'poison@r1.test'),
  1, 'the poison callback recorded one failed attempt');

select ok(
  (select cb.processed_at is null and cb.processing_error is not null
   from public.communication_provider_callback_events cb
   join public.communication_delivery_intents i on i.id = cb.delivery_intent_id
   where i.recipient_email = 'poison@r1.test'),
  'the poison callback is left unprocessed with its error, to retry (not yet parked)');

drop trigger zzz_r1_poison on public.communication_email_suppressions;

-- ---------------------------------------------------------------------------------------------------
-- Outbox claim enforcement matrix. A blocked class cancels with failure_code recipient_suppressed; an
-- eligible one passes the suppression gate and fails later for a different reason.
-- ---------------------------------------------------------------------------------------------------

create function pg_temp.seed_claim(p_email text, p_reason text, p_class text)
returns void language plpgsql as $$
declare v_method uuid; v_intent uuid;
begin
  insert into public.client_contact_methods (organization_id, client_id, kind, value, normalized_value)
  values ('a1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002',
    'email', p_email, p_email)
  returning id into v_method;

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
    subject, html_content, text_content, allowance_class, status, send_kind, expires_at)
  values ('a1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002',
    v_method, 'claim:' || p_email, p_email, 's', '<p>h</p>', 't', p_class, 'queued', 'automated',
    now() + interval '1 day')
  returning id into v_intent;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id, status, available_at)
  values ('a1000000-0000-4000-8000-000000000001', v_intent, 'pending', timestamptz '2000-01-01');

  insert into public.communication_email_suppressions (organization_id, recipient_email, reason, source)
  values ('a1000000-0000-4000-8000-000000000001', p_email, p_reason, 'manual');
end $$;

select pg_temp.seed_claim('c-hb-opt@r1.test', 'hard_bounce', 'optional');
select pg_temp.seed_claim('c-hb-ess@r1.test', 'hard_bounce', 'essential');
select pg_temp.seed_claim('c-cp-ess@r1.test', 'complaint', 'essential');
select pg_temp.seed_claim('c-un-opt@r1.test', 'unsubscribe', 'optional');
select pg_temp.seed_claim('c-un-ess@r1.test', 'unsubscribe', 'essential');

-- One pass handles every seeded candidate; none has a configured sender, so none is returned.
select public.claim_communication_outbox_event();

select is((select failure_code from public.communication_delivery_intents where recipient_email = 'c-hb-opt@r1.test'),
  'recipient_suppressed', 'hard bounce blocks optional mail');
select is((select failure_code from public.communication_delivery_intents where recipient_email = 'c-hb-ess@r1.test'),
  'recipient_suppressed', 'hard bounce blocks essential mail too');
select is((select failure_code from public.communication_delivery_intents where recipient_email = 'c-cp-ess@r1.test'),
  'recipient_suppressed', 'a complaint blocks essential mail (corrected scope: all non-security)');
select is((select failure_code from public.communication_delivery_intents where recipient_email = 'c-un-opt@r1.test'),
  'recipient_suppressed', 'an unsubscribe blocks optional mail');
select isnt((select failure_code from public.communication_delivery_intents where recipient_email = 'c-un-ess@r1.test'),
  'recipient_suppressed', 'an unsubscribe leaves essential mail locally eligible');

-- The removal flow refuses an unsubscribe suppression instead of hitting a raw constraint violation.
select throws_ok(
  $$ select public.request_communication_email_suppression_removal(
       'a1000000-0000-4000-8000-000000000001',
       (select id from public.communication_email_suppressions
          where recipient_email = 'c-un-opt@r1.test' and reason = 'unsubscribe'),
       null, 'admin@r1.test', 'please restore', 'reverified', true) $$,
  'Unsubscribed addresses are restored through renewed consent, not a removal request.',
  'the contractor removal flow refuses an unsubscribe suppression with a clear message');

select finish();
rollback;
