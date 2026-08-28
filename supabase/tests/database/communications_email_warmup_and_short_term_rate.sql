-- Communications Part 7.5a: the claim enforces a newly verified domain's warm-up ceiling and the
-- short-term per-organization sending rate, and both defer -- never cancel -- an over-limit message.

begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

-- --- Shape -----------------------------------------------------------------------------------------

select has_table('public', 'communication_email_warmup_stages', 'warm-up stage ceilings have a table');
select has_table(
  'public', 'communication_email_platform_sending_settings',
  'platform-wide sending settings have a table'
);
select has_index(
  'public', 'communication_email_warmup_stages',
  'communication_email_warmup_stages_live_platform_idx',
  'one live platform ceiling per warm-up stage is enforced by a partial unique index'
);
select has_index(
  'public', 'communication_email_platform_sending_settings',
  'communication_email_platform_sending_settings_live_idx',
  'one live platform sending-settings row is enforced by a partial unique index'
);
select function_privs_are(
  'public', 'get_communication_email_sending_capacity_overview', array[]::text[], 'service_role',
  array['EXECUTE'], 'only the owner service role can read the sending-capacity overview'
);
select function_privs_are(
  'public', 'set_communication_email_warmup_stage',
  array['text', 'integer', 'text', 'text', 'boolean'], 'authenticated',
  array[]::text[], 'a contractor session cannot change a platform warm-up ceiling'
);

select is(
  (select daily_ceiling from public.communication_email_warmup_stages
   where scope = 'platform' and stage_key = 'days_1_3' and effective_to is null),
  100, 'the days 1-3 warm-up ceiling seeds at the contract default of 100'
);
select is(
  (select short_term_max_recipients from public.communication_email_platform_sending_settings
   where effective_to is null),
  100, 'the short-term rate seeds at the contract default of 100 recipients'
);

-- Park every message already due in this database so only the fixtures below are claimable.
update public.communication_outbox_events
set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

-- --- Fixtures ------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c1000000-0000-0000-0000-000000000001', 'Warmup Org', 'warmup-org', 'active'),
  ('c1000000-0000-0000-0000-000000000002', 'Rate Org', 'rate-org', 'active');

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at) values
  ('c1000000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days'),
  ('c1000000-0000-0000-0000-000000000002', now() - interval '1 minute', now() + interval '29 days');

select public.apply_organization_limit_exception(
  'c1000000-0000-0000-0000-000000000001', 'operational_email_recipients', 'unlimited', null,
  now() - interval '1 minute', null, 'warmup-fixture-operational', 'Fixture reason.', 'owner@example.test');
select public.apply_organization_limit_exception(
  'c1000000-0000-0000-0000-000000000002', 'operational_email_recipients', 'unlimited', null,
  now() - interval '1 minute', null, 'rate-fixture-operational', 'Fixture reason.', 'owner@example.test');

insert into public.clients (id, organization_id, display_name) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'Warmup Customer'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'Rate Customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'c2000000-0000-0000-0000-000000000001', 'email', 'customer@warmup.test', true),
  ('c3000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002',
   'c2000000-0000-0000-0000-000000000002', 'email', 'customer@rate.test', true);

-- One domain still in warm-up (verified yesterday), one long past it (verified three weeks ago).
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state,
  provider_verified, provider_authenticated, ownership_status, dkim_status, spf_status, verified_at
) values
  ('c4000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'sending', 'young.warmup.test', 'verified', true, true, 'passing', 'passing', 'pending',
   now() - interval '1 day'),
  ('c4000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
   'sending', 'settled.warmup.test', 'verified', true, true, 'passing', 'passing', 'pending',
   now() - interval '21 days'),
  ('c4000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000002',
   'sending', 'sending.rate.test', 'verified', true, true, 'passing', 'passing', 'pending',
   now() - interval '30 days');

insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values
  ('c5000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'c4000000-0000-0000-0000-000000000001', 'svc@young.warmup.test', 'Young', 'enabled', true, true, true),
  ('c5000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
   'c4000000-0000-0000-0000-000000000002', 'svc@settled.warmup.test', 'Settled', 'enabled', false, true, true),
  ('c5000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000002',
   'c4000000-0000-0000-0000-000000000003', 'svc@sending.rate.test', 'Rate', 'enabled', true, true, true);

-- The young domain has already had one recipient accepted today: a settled, counted usage row.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id,
  status, accepted_at, provider_message_id
) values (
  'c6000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
  'warmup-prior', 'customer@warmup.test', 'Prior', '<p>Prior</p>', 'Prior', 'automated', 'optional',
  'c5000000-0000-0000-0000-000000000001', 'submitted', now() - interval '2 hours', 'prov-warmup-a1'
);
insert into public.communication_email_usage_events (organization_id, delivery_intent_id, recipient_count)
values ('c1000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-0000000000a1', 1);

-- --- Owner write closes the live warm-up row and inserts a successor -----------------------------

select lives_ok(
  $$select public.set_communication_email_warmup_stage(
      'days_1_3', 1, 'Tighten the fixture to one recipient.', 'owner@example.test', true)$$,
  'the owner can change a platform warm-up ceiling with confirmation'
);
select is(
  (select count(*)::int from public.communication_email_warmup_stages
   where scope = 'platform' and stage_key = 'days_1_3'),
  2, 'changing a ceiling keeps the prior row as history'
);

-- --- Warm-up: the ceiling of 1 is already used, so a second message defers to tomorrow ----------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'c6000000-0000-0000-0000-0000000000a2', 'c1000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
  'warmup-over', 'customer@warmup.test', 'Over', '<p>Over</p>', 'Over', 'automated', 'optional',
  'c5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('c1000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-0000000000a2');

select public.claim_communication_outbox_event();

select results_eq(
  $$select event.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'c6000000-0000-0000-0000-0000000000a2'$$,
  $$values ('pending'::text, 'email_warmup_ceiling_reached'::text)$$,
  'a message over the domain warm-up ceiling stays queued, it is not cancelled'
);
select ok(
  (select available_at > now() + interval '12 hours'
   from public.communication_outbox_events
   where delivery_intent_id = 'c6000000-0000-0000-0000-0000000000a2'),
  'the deferred warm-up message is scheduled for the next day'
);
select ok(
  not exists (
    select 1 from public.communication_email_capacity_reservations
    where delivery_intent_id = 'c6000000-0000-0000-0000-0000000000a2'
  ),
  'a warm-up defer does not take a recipient reservation'
);

-- --- Warm-up: a domain past day 14 is exempt and claims normally --------------------------------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'c6000000-0000-0000-0000-0000000000a3', 'c1000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
  'warmup-exempt', 'customer@warmup.test', 'Exempt', '<p>Exempt</p>', 'Exempt', 'manual', 'optional',
  'c5000000-0000-0000-0000-000000000002'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('c1000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-0000000000a3');

create temporary table claimed_exempt on commit drop as
select * from public.claim_communication_outbox_event();

select is(
  (select delivery_intent_id from claimed_exempt),
  'c6000000-0000-0000-0000-0000000000a3'::uuid,
  'a sending domain past day 14 is not held by warm-up'
);

-- --- Owner write closes the live short-term row and inserts a successor --------------------------

select throws_ok(
  $$select public.set_communication_email_short_term_rate(
      10, 1, 'No confirmation given.', 'owner@example.test', false)$$,
  '23514', null, 'an unconfirmed short-term rate change is refused'
);
select lives_ok(
  $$select public.set_communication_email_short_term_rate(
      10, 1, 'Tighten the fixture to one recipient per window.', 'owner@example.test', true)$$,
  'the owner can change the short-term rate with confirmation'
);

-- --- Short-term rate: one prior recipient in the window, ceiling 1, so the next defers -----------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id,
  status, accepted_at, provider_message_id
) values (
  'c6000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-000000000002',
  'c2000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002',
  'rate-prior', 'customer@rate.test', 'Prior', '<p>Prior</p>', 'Prior', 'automated', 'optional',
  'c5000000-0000-0000-0000-000000000003', 'submitted', now() - interval '3 minutes', 'prov-rate-b1'
);
insert into public.communication_email_usage_events (
  organization_id, delivery_intent_id, recipient_count, occurred_at
)
values (
  'c1000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-0000000000b1', 1,
  now() - interval '3 minutes'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'c6000000-0000-0000-0000-0000000000b2', 'c1000000-0000-0000-0000-000000000002',
  'c2000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002',
  'rate-over', 'customer@rate.test', 'Over', '<p>Over</p>', 'Over', 'automated', 'optional',
  'c5000000-0000-0000-0000-000000000003'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('c1000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-0000000000b2');

select public.claim_communication_outbox_event();

select results_eq(
  $$select event.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'c6000000-0000-0000-0000-0000000000b2'$$,
  $$values ('pending'::text, 'email_short_term_rate_limited'::text)$$,
  'a message over the short-term rate stays queued, it is not cancelled'
);
select ok(
  (select available_at > now()
   from public.communication_outbox_events
   where delivery_intent_id = 'c6000000-0000-0000-0000-0000000000b2'),
  'the rate-limited message is deferred with a future retry time'
);

-- --- Short-term rate: once the earlier recipient ages out of the window, the message flows -------

update public.communication_email_usage_events
set occurred_at = now() - interval '20 minutes'
where delivery_intent_id = 'c6000000-0000-0000-0000-0000000000b1';
update public.communication_outbox_events
set available_at = now() - interval '1 minute'
where delivery_intent_id = 'c6000000-0000-0000-0000-0000000000b2';

create temporary table claimed_after_window on commit drop as
select * from public.claim_communication_outbox_event();

select is(
  (select delivery_intent_id from claimed_after_window),
  'c6000000-0000-0000-0000-0000000000b2'::uuid,
  'the held message flows once the earlier recipient ages out of the rolling window'
);

select is(
  (public.get_communication_email_sending_capacity_overview() -> 'short_term' ->> 'max_recipients'),
  '1', 'the owner overview reflects the current short-term ceiling'
);

select * from finish();
rollback;
