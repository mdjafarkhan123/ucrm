-- Communications Part 7.5b: the claim enforces the platform-wide provider-period capacity and the
-- essential reserve. Ordinary ('optional') mail stops at capacity minus the reserve; essential mail
-- may spend the reserve but still stops at capacity. Both defer -- never cancel -- an over-limit
-- message. A maintained monthly counter, fed by an AFTER INSERT trigger on the usage events, keeps
-- the check off the growing usage table.

begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

-- --- Shape -----------------------------------------------------------------------------------------

select has_table(
  'public', 'communication_email_platform_period_usage',
  'the maintained monthly platform usage counter has a table'
);
select col_is_pk(
  'public', 'communication_email_platform_period_usage', 'period_start',
  'the counter is keyed by its month start'
);
select has_column(
  'public', 'communication_email_platform_sending_settings', 'provider_period_capacity',
  'the platform sending settings carry the provider-period capacity'
);
select has_column(
  'public', 'communication_email_platform_sending_settings', 'reserve_percent',
  'the platform sending settings carry the reserve percentage'
);
select has_trigger(
  'public', 'communication_email_usage_events',
  'communication_email_usage_events_accrue_platform_period',
  'an accepted usage event accrues into the monthly counter through a trigger'
);
select function_privs_are(
  'public', 'set_communication_email_provider_capacity',
  array['integer', 'integer', 'text', 'text', 'boolean'], 'authenticated',
  array[]::text[], 'a contractor session cannot change the provider-period capacity'
);
select is(
  (select reserve_percent from public.communication_email_platform_sending_settings
   where effective_to is null),
  10, 'the reserve percentage defaults to the contract value of 10'
);

-- Park every message already due so only the fixtures below are claimable, and clear any in-flight
-- reservations so the platform-global reserved count is defined entirely by this test.
update public.communication_outbox_events
set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');
delete from public.communication_email_capacity_reservations
where reservation_state in ('reserved', 'submission_unknown');

-- --- Owner write ---------------------------------------------------------------------------------

-- Capture the live short-term ceiling before the capacity change; the effective-dated tables cannot
-- supersede a row twice inside one transaction (same now()), so this test does exactly one set call
-- and proves the OTHER columns ride along on the successor row.
create temporary table short_term_before on commit drop as
select short_term_max_recipients
from public.communication_email_platform_sending_settings where effective_to is null;

select throws_ok(
  $$select public.set_communication_email_provider_capacity(
      1000, 10, 'No confirmation given.', 'owner@example.test', false)$$,
  '23514', null, 'an unconfirmed provider-capacity change is refused'
);
select lives_ok(
  $$select public.set_communication_email_provider_capacity(
      100, 10, 'Set a small fixture capacity.', 'owner@example.test', true)$$,
  'the owner can set the provider-period capacity with confirmation'
);
select is(
  (public.get_communication_email_sending_capacity_overview()
     -> 'provider_capacity' ->> 'capacity'),
  '100', 'the owner overview reflects the current capacity'
);
select is(
  (public.get_communication_email_sending_capacity_overview()
     -> 'provider_capacity' ->> 'reserve_recipients'),
  '10', 'the overview derives the reserved recipient count from the percentage'
);
select is(
  (select short_term_max_recipients from public.communication_email_platform_sending_settings
   where effective_to is null),
  (select short_term_max_recipients from short_term_before),
  'setting the capacity carries the short-term ceiling forward onto the successor row'
);

-- --- The trigger accrues an accepted usage event into the current month ---------------------------

delete from public.communication_email_platform_period_usage
where period_start = date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d1000000-0000-0000-0000-000000000001', 'Capacity Org', 'capacity-org', 'active');
insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at) values
  ('d1000000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');
select public.apply_organization_limit_exception(
  'd1000000-0000-0000-0000-000000000001', 'operational_email_recipients', 'unlimited', null,
  now() - interval '1 minute', null, 'capacity-fixture-operational', 'Fixture reason.', 'owner@example.test');
select public.apply_organization_limit_exception(
  'd1000000-0000-0000-0000-000000000001', 'essential_email_recipients', 'unlimited', null,
  now() - interval '1 minute', null, 'capacity-fixture-essential', 'Fixture reason.', 'owner@example.test');

insert into public.clients (id, organization_id, display_name) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'Capacity Customer');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
   'd2000000-0000-0000-0000-000000000001', 'email', 'customer@capacity.test', true);
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state,
  provider_verified, provider_authenticated, ownership_status, dkim_status, spf_status, verified_at
) values (
  'd4000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
  'sending', 'sending.capacity.test', 'verified', true, true, 'passing', 'passing', 'pending',
  now() - interval '30 days'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values (
  'd5000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
  'd4000000-0000-0000-0000-000000000001', 'svc@sending.capacity.test', 'Capacity', 'enabled',
  true, true, true
);

-- A submitted intent plus its usage event: the trigger should create the month counter at 1.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id,
  status, accepted_at, provider_message_id
) values (
  'd6000000-0000-0000-0000-0000000000a1', 'd1000000-0000-0000-0000-000000000001',
  'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001',
  'capacity-prior', 'customer@capacity.test', 'Prior', '<p>Prior</p>', 'Prior', 'automated', 'optional',
  'd5000000-0000-0000-0000-000000000001', 'submitted', now() - interval '2 hours', 'prov-capacity-a1'
);
insert into public.communication_email_usage_events (organization_id, delivery_intent_id, recipient_count)
values ('d1000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-0000000000a1', 1);

select is(
  (select accepted_recipients from public.communication_email_platform_period_usage
   where period_start = date_trunc('month', now() at time zone 'UTC') at time zone 'UTC'),
  1::bigint, 'the trigger creates the month counter and records the accepted recipient'
);

-- --- Claim: optional mail stops at capacity minus the reserve ------------------------------------

-- Capacity 100, reserve 10 -> optional stops at 90. Sit the counter exactly on that line.
update public.communication_email_platform_period_usage
set accepted_recipients = 90
where period_start = date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'd6000000-0000-0000-0000-0000000000a2', 'd1000000-0000-0000-0000-000000000001',
  'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001',
  'capacity-optional-over', 'customer@capacity.test', 'Over', '<p>Over</p>', 'Over', 'automated',
  'optional', 'd5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('d1000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-0000000000a2');

select public.claim_communication_outbox_event();

select results_eq(
  $$select event.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'd6000000-0000-0000-0000-0000000000a2'$$,
  $$values ('pending'::text, 'email_platform_capacity_reserved'::text)$$,
  'optional mail at the reserved line stays queued, it is not cancelled'
);
select ok(
  not exists (
    select 1 from public.communication_email_capacity_reservations
    where delivery_intent_id = 'd6000000-0000-0000-0000-0000000000a2'
  ),
  'a platform-capacity defer does not take a recipient reservation'
);

-- --- Claim: essential mail may spend the reserve ------------------------------------------------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'd6000000-0000-0000-0000-0000000000a3', 'd1000000-0000-0000-0000-000000000001',
  'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001',
  'capacity-essential-ok', 'customer@capacity.test', 'Essential', '<p>Essential</p>', 'Essential',
  'automated', 'essential', 'd5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('d1000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-0000000000a3');

create temporary table claimed_essential on commit drop as
select * from public.claim_communication_outbox_event();

select is(
  (select delivery_intent_id from claimed_essential),
  'd6000000-0000-0000-0000-0000000000a3'::uuid,
  'essential mail claims into the reserve while optional mail is held'
);

-- --- Claim: essential mail still stops at the full capacity --------------------------------------

update public.communication_email_platform_period_usage
set accepted_recipients = 100
where period_start = date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
delete from public.communication_email_capacity_reservations
where reservation_state in ('reserved', 'submission_unknown');

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'd6000000-0000-0000-0000-0000000000a4', 'd1000000-0000-0000-0000-000000000001',
  'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001',
  'capacity-essential-over', 'customer@capacity.test', 'Over', '<p>Over</p>', 'Over', 'automated',
  'essential', 'd5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('d1000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-0000000000a4');

select public.claim_communication_outbox_event();

select results_eq(
  $$select event.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'd6000000-0000-0000-0000-0000000000a4'$$,
  $$values ('pending'::text, 'email_platform_capacity_reached'::text)$$,
  'essential mail at the full capacity stays queued too'
);

-- --- Claim: no capacity set means the check is a no-op ------------------------------------------

-- The effective-dated table cannot be superseded twice in one transaction (same now()), so clear the
-- capacity with direct DML rather than a second owner command.
update public.communication_email_platform_sending_settings
set provider_period_capacity = null where effective_to is null;
update public.communication_outbox_events
set available_at = now() - interval '1 minute'
where delivery_intent_id = 'd6000000-0000-0000-0000-0000000000a4';

create temporary table claimed_uncapped on commit drop as
select * from public.claim_communication_outbox_event();

select is(
  (select delivery_intent_id from claimed_uncapped),
  'd6000000-0000-0000-0000-0000000000a4'::uuid,
  'with no capacity configured the platform check does not hold anything'
);

select * from finish();
rollback;
