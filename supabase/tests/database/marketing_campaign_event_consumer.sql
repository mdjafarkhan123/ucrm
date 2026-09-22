-- Marketing M4 stage 4: project_marketing_campaign_recipient_events.
--
-- Run this whole file as one transaction that is rolled back at the end, the same convention
-- marketing_campaign_dispatcher.sql documents. Do not run it through a runner that executes each statement
-- separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- Nobody outside server code reaches the projector. ---------------------------------------------------------
select is(
  has_function_privilege('anon', 'public.project_marketing_campaign_recipient_events(integer)', 'execute'),
  false, 'signed-out callers cannot project marketing events');
select is(
  has_function_privilege('authenticated', 'public.project_marketing_campaign_recipient_events(integer)', 'execute'),
  false, 'members cannot project marketing events directly');

set local role postgres;

-- Fixtures --------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status, created_at)
values ('fe200000-0000-0000-0000-000000000001', 'Event Org A', 'event-org-a', 'active', now() - interval '40 days');

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values
  ('fe300000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', 'Delivered', 'person', 'customer'),
  ('fe300000-0000-0000-0000-000000000002', 'fe200000-0000-0000-0000-000000000001', 'Hard Bounce', 'person', 'customer'),
  ('fe300000-0000-0000-0000-000000000003', 'fe200000-0000-0000-0000-000000000001', 'Complaint', 'person', 'customer'),
  ('fe300000-0000-0000-0000-000000000004', 'fe200000-0000-0000-0000-000000000001', 'Soft Bounce', 'person', 'customer'),
  ('fe300000-0000-0000-0000-000000000005', 'fe200000-0000-0000-0000-000000000001', 'Already Bounced', 'person', 'customer'),
  ('fe300000-0000-0000-0000-000000000006', 'fe200000-0000-0000-0000-000000000001', 'Already Unsubscribed', 'person', 'customer'),
  ('fe300000-0000-0000-0000-000000000007', 'fe200000-0000-0000-0000-000000000001', 'Rejected', 'person', 'customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('fe400000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000001', 'email', 'delivered@example.test', true),
  ('fe400000-0000-0000-0000-000000000002', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000002', 'email', 'hardbounce@example.test', true),
  ('fe400000-0000-0000-0000-000000000003', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000003', 'email', 'complaint@example.test', true),
  ('fe400000-0000-0000-0000-000000000004', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000004', 'email', 'softbounce@example.test', true),
  ('fe400000-0000-0000-0000-000000000005', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000005', 'email', 'sticky@example.test', true),
  ('fe400000-0000-0000-0000-000000000006', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000006', 'email', 'unsub@example.test', true),
  ('fe400000-0000-0000-0000-000000000007', 'fe200000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000007', 'email', 'rejected@example.test', true);

insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fe600000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', 'Event Test Campaign',
  'promote_service', 'completed', '{}'::jsonb, now(), 'event-key-one', 7, 7, 0
);

-- Every recipient already reached 'submitted' the way stage 3's finalize leaves one, except the two already
-- carrying a terminal status a later event must never downgrade.
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name,
  status, provider_message_id, submitted_at
) values
  ('fe700000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000001', 'fe400000-0000-0000-0000-000000000001', 'delivered@example.test', 'Delivered',
    'submitted', 'ses-msg-delivered', now()),
  ('fe700000-0000-0000-0000-000000000002', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000002', 'fe400000-0000-0000-0000-000000000002', 'hardbounce@example.test', 'Hard Bounce',
    'submitted', 'ses-msg-hardbounce', now()),
  ('fe700000-0000-0000-0000-000000000003', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000003', 'fe400000-0000-0000-0000-000000000003', 'complaint@example.test', 'Complaint',
    'submitted', 'ses-msg-complaint', now()),
  ('fe700000-0000-0000-0000-000000000004', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000004', 'fe400000-0000-0000-0000-000000000004', 'softbounce@example.test', 'Soft Bounce',
    'submitted', 'ses-msg-softbounce', now()),
  ('fe700000-0000-0000-0000-000000000005', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000005', 'fe400000-0000-0000-0000-000000000005', 'sticky@example.test', 'Already Bounced',
    'bounced', 'ses-msg-sticky', now()),
  ('fe700000-0000-0000-0000-000000000006', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000006', 'fe400000-0000-0000-0000-000000000006', 'unsub@example.test', 'Already Unsubscribed',
    'unsubscribed', 'ses-msg-unsub', now()),
  ('fe700000-0000-0000-0000-000000000007', 'fe200000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001',
    'fe300000-0000-0000-0000-000000000007', 'fe400000-0000-0000-0000-000000000007', 'rejected@example.test', 'Rejected',
    'submitted', 'ses-msg-reject', now());

-- A duplicate provider_event_key can never be recorded twice -- this is the dedupe an at-least-once SQS
-- redelivery relies on. --------------------------------------------------------------------------------------
insert into public.marketing_campaign_recipient_events (provider_event_key, provider_message_id, event_kind, payload)
values ('ses:ses-msg-delivered:Delivery', 'ses-msg-delivered', 'Delivery',
  '{"eventType":"Delivery","mail":{"messageId":"ses-msg-delivered"},"delivery":{}}'::jsonb);

select throws_ok(
  $$insert into public.marketing_campaign_recipient_events (provider_event_key, provider_message_id, event_kind, payload)
    values ('ses:ses-msg-delivered:Delivery', 'ses-msg-delivered', 'Delivery',
      '{"eventType":"Delivery","mail":{"messageId":"ses-msg-delivered"},"delivery":{}}'::jsonb)$$,
  '23505', null, 'the same SQS event redelivered a second time cannot be recorded twice');

-- One event per remaining recipient, plus one naming a message id nothing in this database ever sent. --------
insert into public.marketing_campaign_recipient_events (provider_event_key, provider_message_id, event_kind, payload)
values
  ('ses:ses-msg-hardbounce:Bounce', 'ses-msg-hardbounce', 'Bounce',
    '{"eventType":"Bounce","mail":{"messageId":"ses-msg-hardbounce"},"bounce":{"bounceType":"Permanent"}}'::jsonb),
  ('ses:ses-msg-complaint:Complaint', 'ses-msg-complaint', 'Complaint',
    '{"eventType":"Complaint","mail":{"messageId":"ses-msg-complaint"},"complaint":{}}'::jsonb),
  ('ses:ses-msg-softbounce:Bounce', 'ses-msg-softbounce', 'Bounce',
    '{"eventType":"Bounce","mail":{"messageId":"ses-msg-softbounce"},"bounce":{"bounceType":"Transient"}}'::jsonb),
  ('ses:ses-msg-sticky:Delivery', 'ses-msg-sticky', 'Delivery',
    '{"eventType":"Delivery","mail":{"messageId":"ses-msg-sticky"},"delivery":{}}'::jsonb),
  ('ses:ses-msg-unsub:Delivery', 'ses-msg-unsub', 'Delivery',
    '{"eventType":"Delivery","mail":{"messageId":"ses-msg-unsub"},"delivery":{}}'::jsonb),
  ('ses:ses-msg-reject:Reject', 'ses-msg-reject', 'Reject',
    '{"eventType":"Reject","mail":{"messageId":"ses-msg-reject"}}'::jsonb),
  ('ses:ses-msg-nobody:Delivery', 'ses-msg-nobody', 'Delivery',
    '{"eventType":"Delivery","mail":{"messageId":"ses-msg-nobody"},"delivery":{}}'::jsonb);

select is(public.project_marketing_campaign_recipient_events(200), 7,
  'the projector processes every event with a matching recipient in one bounded pass');

select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000001'),
  'delivered', 'a Delivery event marks a submitted recipient delivered');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000002'),
  'bounced', 'a permanent Bounce event marks the recipient bounced');
select is(
  (select failure_code from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000002'),
  'ses_hard_bounce', 'the hard bounce carries its own failure code');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000003'),
  'complained', 'a Complaint event marks the recipient complained');
select is(
  (select failure_code from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000003'),
  'ses_complaint', 'the complaint carries its own failure code');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000004'),
  'submitted', 'a transient bounce leaves status alone -- SES retries it on its own');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000005'),
  'bounced', 'a later Delivery event can never downgrade an already-bounced recipient');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000006'),
  'unsubscribed', 'a later Delivery event can never overwrite a customer''s own unsubscribe');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000007'),
  'failed', 'a Reject event marks the recipient failed');
select is(
  (select failure_code from public.marketing_campaign_recipients where id = 'fe700000-0000-0000-0000-000000000007'),
  'ses_reject', 'the reject carries its own failure code');

select results_eq(
  $$select reason from public.communication_email_suppressions where organization_id = 'fe200000-0000-0000-0000-000000000001' and recipient_email = 'hardbounce@example.test'$$,
  $$values ('hard_bounce'::text)$$,
  'a hard bounce suppresses the recipient''s email address');
select results_eq(
  $$select reason from public.communication_email_suppressions where organization_id = 'fe200000-0000-0000-0000-000000000001' and recipient_email = 'complaint@example.test'$$,
  $$values ('complaint'::text)$$,
  'a complaint suppresses the recipient''s email address');
select is_empty(
  $$select * from public.communication_email_suppressions where recipient_email = 'softbounce@example.test'$$,
  'a transient bounce never suppresses the address');

-- An event naming an unknown message id is left unprocessed to retry, then gives up rather than spinning
-- forever. -------------------------------------------------------------------------------------------------
select is(
  (select processing_attempts from public.marketing_campaign_recipient_events where provider_event_key = 'ses:ses-msg-nobody:Delivery'),
  1, 'an unmatched event counts its first attempt');
select is(
  (select processed_at from public.marketing_campaign_recipient_events where provider_event_key = 'ses:ses-msg-nobody:Delivery'),
  null, 'an unmatched event is not marked processed while attempts remain');

select public.project_marketing_campaign_recipient_events(200);
select public.project_marketing_campaign_recipient_events(200);
select public.project_marketing_campaign_recipient_events(200);
select public.project_marketing_campaign_recipient_events(200);

select isnt(
  (select processed_at from public.marketing_campaign_recipient_events where provider_event_key = 'ses:ses-msg-nobody:Delivery'),
  null, 'an event naming a message id nothing here ever sent eventually gives up rather than retrying forever');
select isnt(
  (select processing_error from public.marketing_campaign_recipient_events where provider_event_key = 'ses:ses-msg-nobody:Delivery'),
  null, 'the giveup records why');

select * from finish();
rollback;
