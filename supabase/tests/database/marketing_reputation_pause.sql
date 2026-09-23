-- Marketing M4 stage 6: the Marketing-only reputation pause.
--
-- Marketing complaints and hard bounces engage a pause that holds Marketing only, never operational email;
-- a held organization cannot starve other organizations' campaigns; only Jafar resumes it.
--
-- Run this whole file as one transaction that is rolled back at the end.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- Nobody outside server code reaches the evaluator or the resume command. ------------------------------------
select is(
  has_function_privilege('authenticated', 'public.evaluate_marketing_email_reputation(uuid, timestamptz)', 'execute'),
  false, 'members cannot run the Marketing reputation evaluator');
select is(
  has_function_privilege('authenticated',
    'public.resume_marketing_email_reputation_pause(uuid, text, text, boolean)', 'execute'),
  false, 'members cannot resume a Marketing reputation pause');
select is(
  has_function_privilege('anon', 'public.resume_marketing_email_reputation_pause(uuid, text, text, boolean)', 'execute'),
  false, 'signed-out callers cannot resume a Marketing reputation pause');

set local role postgres;

-- Park anything already queued so the claim assertions see only these fixtures.
update public.communication_outbox_events set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');
update public.marketing_campaigns set status = 'completed' where status in ('sending', 'scheduled');

-- Fixtures: org A draws complaints; org B is healthy and launched later. -----------------------------------
insert into public.organizations (id, name, slug, lifecycle_status, created_at) values
  ('fb200000-0000-0000-0000-00000000000a', 'Reputation Org A', 'reputation-org-a', 'active', now() - interval '40 days'),
  ('fb200000-0000-0000-0000-00000000000b', 'Reputation Org B', 'reputation-org-b', 'active', now() - interval '40 days');

-- Org A: 60 customers, so its waiting queue alone is longer than the claim's 50-candidate window.
insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
select ('fb300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fb200000-0000-0000-0000-00000000000a',
  'A Customer ' || n, 'person', 'customer'
from generate_series(1, 60) n;

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
select ('fb400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fb200000-0000-0000-0000-00000000000a',
  ('fb300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'email', 'a' || n || '@example.test', true
from generate_series(1, 60) n;

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values ('fb310000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-00000000000b', 'B Customer', 'person', 'customer');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('fb410000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-00000000000b',
  'fb310000-0000-0000-0000-000000000001', 'email', 'b1@example.test', true);
insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values ('fb200000-0000-0000-0000-00000000000b', 'fb310000-0000-0000-0000-000000000001',
  'fb410000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'reputation-b-one', now());

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider, provider_verified,
  provider_authenticated, ownership_status, dkim_status, spf_status, verified_at, warmup_started_at
) values
  ('fb500000-0000-0000-0000-00000000000a', 'fb200000-0000-0000-0000-00000000000a', 'marketing_sending',
    'news.reputation-org-a.test', 'verified', 'ses', true, true, 'passing', 'passing', 'passing',
    now() - interval '30 days', now() - interval '30 days'),
  ('fb500000-0000-0000-0000-00000000000b', 'fb200000-0000-0000-0000-00000000000b', 'marketing_sending',
    'news.reputation-org-b.test', 'verified', 'ses', true, true, 'passing', 'passing', 'passing',
    now() - interval '30 days', now() - interval '30 days');

-- Org A's first campaign already went out to ten customers; three of them complain.
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fb600000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-00000000000a', 'A Sent Campaign',
  'promote_service', 'completed', '{}'::jsonb, now() - interval '3 hours', 'reputation-a-sent', 10, 10, 0
);
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name,
  status, provider_message_id, submitted_at
)
select ('fb700000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fb200000-0000-0000-0000-00000000000a',
  'fb600000-0000-0000-0000-000000000001',
  ('fb300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('fb400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'a' || n || '@example.test', 'A Customer ' || n, 'submitted', 'ses-rep-a-' || n, now() - interval '2 hours'
from generate_series(1, 10) n;

-- A queued optional operational email for org A (a follow-up), to prove the Marketing pause never holds it.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, allowance_class
) values (
  'fb800000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-00000000000a',
  'fb300000-0000-0000-0000-000000000060', 'fb400000-0000-0000-0000-000000000060',
  'reputation-a-followup', 'a60@example.test', 'Follow-up', '<p>hi</p>', 'hi', 'optional'
);

-- Two complaints: below the three-event minimum, so no pause yet. ----------------------------------------
insert into public.marketing_campaign_recipient_events (provider_event_key, provider_message_id, event_kind, payload)
select 'ses:ses-rep-a-' || n || ':Complaint', 'ses-rep-a-' || n, 'Complaint',
  jsonb_build_object('eventType', 'Complaint', 'mail', jsonb_build_object('messageId', 'ses-rep-a-' || n))
from generate_series(1, 2) n;

select is(public.project_marketing_campaign_recipient_events(200), 2, 'the first two complaints project');
select ok(
  not exists (select 1 from public.communication_email_sending_pauses
    where organization_id = 'fb200000-0000-0000-0000-00000000000a' and released_at is null),
  'two complaints from a small send stay under the minimum event count and do not pause');

-- The third complaint crosses the threshold. -------------------------------------------------------------
insert into public.marketing_campaign_recipient_events (provider_event_key, provider_message_id, event_kind, payload)
values ('ses:ses-rep-a-3:Complaint', 'ses-rep-a-3', 'Complaint',
  '{"eventType":"Complaint","mail":{"messageId":"ses-rep-a-3"}}'::jsonb);

select is(public.project_marketing_campaign_recipient_events(200), 1, 'the third complaint projects');
select is(
  (select source || '/' || applies_to || '/' || engaged_by_owner_email
   from public.communication_email_sending_pauses
   where organization_id = 'fb200000-0000-0000-0000-00000000000a' and released_at is null),
  'auto_marketing_reputation/marketing/system',
  'the third complaint engages exactly one Marketing-only automatic pause');
select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'communications.marketing_reputation_pause_engaged'
     and target_key = 'fb200000-0000-0000-0000-00000000000a'),
  1, 'engaging the pause writes one owner audit event');
select ok(
  not exists (select 1 from public.communication_email_reputation_state
    where organization_id = 'fb200000-0000-0000-0000-00000000000a'),
  'the operational reputation state is untouched');

select lives_ok(
  $$select public.evaluate_marketing_email_reputation('fb200000-0000-0000-0000-00000000000a', now())$$,
  're-evaluating while already paused is safe');
select is(
  (select count(*)::int from public.communication_email_sending_pauses
   where organization_id = 'fb200000-0000-0000-0000-00000000000a' and released_at is null),
  1, 're-evaluating adds no second pause');

-- The Marketing pause never holds operational email. -----------------------------------------------------
insert into public.communication_outbox_events (id, organization_id, delivery_intent_id, available_at)
values ('fb900000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-00000000000a',
  'fb800000-0000-0000-0000-000000000001', now() - interval '1 minute');
select public.claim_communication_outbox_event();
select ok(
  (select coalesce(failure_code, '') from public.communication_delivery_intents
   where id = 'fb800000-0000-0000-0000-000000000001')
    not in ('sending_paused_reputation', 'sending_paused_organization'),
  'optional operational email passes the pause check while only Marketing is paused');

-- A paused organization's long queue cannot starve a later organization's campaign. ------------------------
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values
  ('fb600000-0000-0000-0000-000000000002', 'fb200000-0000-0000-0000-00000000000a', 'A Held Campaign',
    'promote_service', 'sending', '{}'::jsonb, now() - interval '1 hour', 'reputation-a-held', 60, 60, 0),
  ('fb600000-0000-0000-0000-000000000003', 'fb200000-0000-0000-0000-00000000000b', 'B Campaign',
    'promote_service', 'sending', '{}'::jsonb, now(), 'reputation-b', 1, 1, 0);

insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
)
select ('fb710000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fb200000-0000-0000-0000-00000000000a',
  'fb600000-0000-0000-0000-000000000002',
  ('fb300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('fb400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'a' || n || '@example.test', 'A Customer ' || n, 'waiting'
from generate_series(1, 60) n;

insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
) values ('fb720000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-00000000000b',
  'fb600000-0000-0000-0000-000000000003', 'fb310000-0000-0000-0000-000000000001',
  'fb410000-0000-0000-0000-000000000001', 'b1@example.test', 'B Customer', 'waiting');

select is(
  (select recipient_email from public.claim_marketing_campaign_recipient()),
  'b1@example.test',
  'the healthy organization''s recipient is claimed past the paused organization''s 60 waiting recipients');
select is(
  (select count(*)::int from public.marketing_campaign_recipients
   where campaign_id = 'fb600000-0000-0000-0000-000000000002' and status = 'waiting'),
  60, 'the paused organization''s recipients stay waiting, not excluded');

-- Only Jafar resumes, and only knowingly while still over the limit. ------------------------------------
select throws_ok(
  $$select public.resume_marketing_email_reputation_pause(
      'fb200000-0000-0000-0000-00000000000a', 'Reviewed the list', 'jafar@example.com', false)$$,
  '23514', null, 'resuming while still over the limit requires confirming remediation');
select is(
  (public.resume_marketing_email_reputation_pause(
    'fb200000-0000-0000-0000-00000000000a', 'Contractor cleaned the list', 'JAFAR@example.com', true)
   ->> 'released')::boolean,
  true, 'a confirmed resume releases the Marketing pause');
select is(
  (select released_by_owner_email from public.communication_email_sending_pauses
   where organization_id = 'fb200000-0000-0000-0000-00000000000a' and source = 'auto_marketing_reputation'),
  'jafar@example.com', 'the release records who resumed it');

select * from finish();
rollback;
