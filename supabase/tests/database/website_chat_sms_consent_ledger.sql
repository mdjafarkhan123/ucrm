-- CRM launch readiness Part 4 Stage 6: Website Chat service-SMS consent reaches the SMS consent ledger only
-- when the visitor ticked the box, gave a phone number, and the identity resolved to the client owning it.

begin;

create extension if not exists pgtap with schema extensions;
select plan(9);

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('4c600000-0000-0000-0000-000000000001', 'Chat Consent Test', 'chat-consent-test', 'active');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select '4c600000-0000-0000-0000-000000000001', id, now() - interval '2 minutes', 'provisioning', 'Chat consent test'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select public.apply_organization_limit_exception(
  '4c600000-0000-0000-0000-000000000001', 'website_chat_accepted_conversations', 'unlimited', null,
  now() - interval '30 seconds', null, 'chat-consent-test', 'Unlimited chats for the consent test.',
  'owner@example.test'
);

insert into public.website_chat_allowance_periods (organization_id, starts_at, ends_at)
values ('4c600000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');

insert into public.website_chat_widgets (id, organization_id, name, published, source_label, public_token)
values ('4c600000-0000-0000-0000-000000000002', '4c600000-0000-0000-0000-000000000001', 'Consent widget', true,
  'Website Chat', '4c600000-0000-0000-0000-0000000000aa');

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values ('4c600000-0000-0000-0000-000000000001', '4c600000-0000-0000-0000-000000000002', 'https://consent.example.com');

-- Two existing clients sharing nothing, used for the ambiguous case.
insert into public.clients (id, organization_id, display_name, lifecycle_status)
values
  ('4c600000-0000-0000-0000-000000000010', '4c600000-0000-0000-0000-000000000001', 'Phone Owner', 'lead'),
  ('4c600000-0000-0000-0000-000000000011', '4c600000-0000-0000-0000-000000000001', 'Email Owner', 'lead');
insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
values
  ('4c600000-0000-0000-0000-000000000001', '4c600000-0000-0000-0000-000000000010', 'phone', '+14155550190', true),
  ('4c600000-0000-0000-0000-000000000001', '4c600000-0000-0000-0000-000000000011', 'email', 'owner@consent.test', true);

create temporary table chat_result (label text primary key, result jsonb) on commit drop;

-- 1. Ticked, with a phone and disclosure, new visitor.
insert into chat_result
select 'ticked', public.accept_website_chat_first_message(
  '4c600000-0000-0000-0000-0000000000aa', 'https://consent.example.com', 'hash-ticked', 'consent-ticked-1',
  'Ticked Visitor', '+14155550111', '', 'Need a quote', true, null, '{}'::jsonb,
  'Text me about my request. I agree to receive text messages from Chat Consent Test.');

select is(result ->> 'status', 'accepted', 'a ticked first message is accepted') from chat_result where label = 'ticked';

select is(
  (select count(*)::integer from public.communication_sms_consent_events e
   join chat_result r on r.label = 'ticked' and e.client_id = (r.result ->> 'client_id')::uuid
   where e.event_kind = 'opt_in' and e.proof_method = 'web_form'
     and e.subjects = array['service', 'work_updates']
     and e.evidence ->> 'channel' = 'website_chat'
     and e.evidence ->> 'disclosure' like 'Text me about my request.%'),
  1,
  'a ticked box records one web_form opt-in with the shown disclosure'
);

select is(
  (select public.communication_sms_consent_status(
     '4c600000-0000-0000-0000-000000000001', m.id, 'service')
   from public.client_contact_methods m join chat_result r on r.label = 'ticked'
   where m.client_id = (r.result ->> 'client_id')::uuid and m.kind = 'phone'),
  'opted_in',
  'the chat visitor''s number becomes opted in for service texts'
);

-- 2. A retry of the same message does not record a second opt-in.
select public.accept_website_chat_first_message(
  '4c600000-0000-0000-0000-0000000000aa', 'https://consent.example.com', 'hash-ticked', 'consent-ticked-1',
  'Ticked Visitor', '+14155550111', '', 'Need a quote', true, null, '{}'::jsonb,
  'Text me about my request. I agree to receive text messages from Chat Consent Test.');

select is(
  (select count(*)::integer from public.communication_sms_consent_events e
   join chat_result r on r.label = 'ticked' and e.client_id = (r.result ->> 'client_id')::uuid),
  1,
  'a replayed first message never duplicates consent'
);

-- 3. A bare "true" without a disclosure (an old pre-ticked widget) is not consent.
insert into chat_result
select 'bare_true', public.accept_website_chat_first_message(
  '4c600000-0000-0000-0000-0000000000aa', 'https://consent.example.com', 'hash-bare', 'consent-bare-1',
  'Old Widget Visitor', '+14155550122', '', 'Hello', true, null, '{}'::jsonb, null);

select is(
  (select count(*)::integer from public.communication_sms_consent_events e
   join chat_result r on r.label = 'bare_true' and e.client_id = (r.result ->> 'client_id')::uuid),
  0,
  'consent without a stored disclosure records nothing'
);
select is(
  (select s.consent_transactional_sms from public.website_chat_sessions s
   join chat_result r on r.label = 'bare_true' and s.id = (r.result ->> 'session_id')::uuid),
  false,
  'the session does not claim consent it has no evidence for'
);

-- 4. Unticked records nothing.
insert into chat_result
select 'unticked', public.accept_website_chat_first_message(
  '4c600000-0000-0000-0000-0000000000aa', 'https://consent.example.com', 'hash-unticked', 'consent-unticked-1',
  'Unticked Visitor', '+14155550133', '', 'Hello', false, null, '{}'::jsonb,
  'Text me about my request. I agree to receive text messages from Chat Consent Test.');

select is(
  (select count(*)::integer from public.communication_sms_consent_events e
   join chat_result r on r.label = 'unticked' and e.client_id = (r.result ->> 'client_id')::uuid),
  0,
  'an unticked box records nothing'
);

-- 5. Ambiguous identity (phone and email belong to different clients) attaches consent to nobody.
insert into chat_result
select 'ambiguous', public.accept_website_chat_first_message(
  '4c600000-0000-0000-0000-0000000000aa', 'https://consent.example.com', 'hash-ambiguous', 'consent-ambiguous-1',
  'Mixed Visitor', '+14155550190', 'owner@consent.test', 'Hello', true, null, '{}'::jsonb,
  'Text me about my request. I agree to receive text messages from Chat Consent Test.');

select is(result ->> 'match_status', 'needs_review', 'the mixed identity needs review') from chat_result where label = 'ambiguous';
select is(
  (select count(*)::integer from public.communication_sms_consent_events
   where organization_id = '4c600000-0000-0000-0000-000000000001'
     and client_id in ('4c600000-0000-0000-0000-000000000010', '4c600000-0000-0000-0000-000000000011')),
  0,
  'an identity that needs review attaches consent to nobody'
);

select * from finish();
rollback;
