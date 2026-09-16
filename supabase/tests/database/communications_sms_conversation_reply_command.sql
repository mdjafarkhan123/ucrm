-- Communications Stage 6B: enqueue_conversation_reply_sms -- SMS reply from an already-open Conversations
-- thread. Recipient is resolved from the conversation's own most recent SMS activity (falling back to the
-- primary phone), the operational subject is always 'service' (a manual reply is a direct service
-- conversation), and every other gate -- consent, readiness, balance, quiet hours -- is inherited whole
-- from communication_sms_enqueue_operational, already covered by its own 37-assert suite.
begin;

create extension if not exists pgtap with schema extensions;
select plan(21);

select function_privs_are(
  'public', 'enqueue_conversation_reply_sms', array['uuid', 'uuid', 'uuid', 'text', 'text', 'jsonb'],
  'service_role', array['EXECUTE'], 'only the service worker can enqueue an SMS conversation reply'
);
select function_privs_are(
  'public', 'enqueue_conversation_reply_sms', array['uuid', 'uuid', 'uuid', 'text', 'text', 'jsonb'],
  'authenticated', array[]::text[], 'authenticated clients cannot call the command directly'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Fixtures: a fully ready SMS org (mirrors communications_sms_consent_aware_enqueue_command.sql), plus a
-- second, unresolved-phone client to prove the no-recipient refusal.
-- ---------------------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('ec000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'sms-reply-actor@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('ec100000-0000-0000-0000-000000000001', 'Reply SMS Co', 'reply-sms-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001', 'owner', 'active');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state) values
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001', 'conversations.send', 'grant'),
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001', 'customers.view', 'grant');

insert into public.clients (id, organization_id, display_name) values
  ('ec200000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001', 'Reply SMS Client'),
  ('ec200000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001', 'No Phone Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('ec300000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
   'ec200000-0000-0000-0000-000000000001', 'phone', '+15552220001', true),
  ('ec300000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001',
   'ec200000-0000-0000-0000-000000000001', 'phone', '+15552220002', false);

insert into public.communication_sms_registrations (
  id, organization_id, country_code, sender_type, use_case, status,
  attested_by, attested_at, submitted_at, provider_outcome
) values (
  'ec500000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  'US', 'long_code', 'customer_care', 'approved',
  'ec000000-0000-0000-0000-000000000001', now(), now(), 'Approved'
);

-- Country 'US' + capable_mms so this file can also exercise 6D-2's attach-a-photo path without a second
-- fixture org; none of this file's other assertions inspect country_code or capable_mms.
insert into public.communication_sms_sender_identities (
  id, organization_id, phone_number, lifecycle_state, allows_manual, allows_automated,
  country_code, sender_type, capable_sms, capable_mms, registration_id, is_default_sender
) values (
  'ec400000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  '+15559990002', 'ready', true, true, 'US', 'long_code', true, true,
  'ec500000-0000-0000-0000-000000000001', true
);

insert into public.communication_sms_org_modes (organization_id, package_max_mode, chosen_mode) values
  ('ec100000-0000-0000-0000-000000000001', 'operational', 'operational');

insert into public.communication_sms_retail_rates (
  destination, sender_type, message_unit, retail_rate_major, effective_from, set_by
) values (
  'US', 'long_code', 'segment', 0.05, now() - interval '1 day', 'ec000000-0000-0000-0000-000000000001'
),
(
  'US', 'long_code', 'mms', 0.20, now() - interval '1 day', 'ec000000-0000-0000-0000-000000000001'
);

insert into public.communication_sms_credit_accounts (organization_id, settled_balance_minor, reserved_balance_minor)
values ('ec100000-0000-0000-0000-000000000001', 100, 0);

-- Consent for 'service' on both of the first client's numbers; the second client has no consent at all.
select public.communication_sms_record_consent_proof(
  'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
  'ec200000-0000-0000-0000-000000000001', 'ec300000-0000-0000-0000-000000000001',
  'signed_agreement', array['service']::text[], now() - interval '1 hour', 'reply-consent-1');
select public.communication_sms_record_consent_proof(
  'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
  'ec200000-0000-0000-0000-000000000001', 'ec300000-0000-0000-0000-000000000002',
  'signed_agreement', array['service']::text[], now() - interval '1 hour', 'reply-consent-2');

select public.communication_sms_set_quiet_hours_policy(
  false, '21:00', '08:00', 'UTC', 'ec000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------------------------------------------
-- No prior activity: falls back to the client's primary phone.
-- ---------------------------------------------------------------------------------------------------------------
select is(
  (public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-fallback-primary', 'On our way over.'
  )).recipient_phone,
  '+15552220001',
  'with no prior conversation activity, the SMS reply falls back to the primary phone'
);
select is(
  (select subject from public.communication_delivery_intents
    where logical_send_key = 'reply-sms-fallback-primary'),
  null, 'the payload check keeps SMS intents subject-less -- the operational subject only gates consent'
);
select is(
  (select sms_sender_identity_id from public.communication_delivery_intents
    where logical_send_key = 'reply-sms-fallback-primary'),
  'ec400000-0000-0000-0000-000000000001'::uuid,
  'the reply uses the organization''s default SMS sender'
);
select is(
  (select send_kind from public.communication_delivery_intents
    where logical_send_key = 'reply-sms-fallback-primary'),
  'manual', 'an SMS conversation reply is a manual send'
);

-- Idempotency: replaying the same logical send key, before any activity moves the resolved recipient,
-- returns the same row, not a second one.
select is(
  (public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-fallback-primary', 'On our way over.'
  )).id,
  (select id from public.communication_delivery_intents where logical_send_key = 'reply-sms-fallback-primary'),
  'replaying the same logical send key returns the original intent'
);
select is(
  (select count(*)::integer from public.communication_delivery_intents
    where logical_send_key = 'reply-sms-fallback-primary'),
  1, 'replaying the same logical send key does not create a duplicate row'
);

-- A more recent inbound message on the secondary number redirects the reply to that number. Recipient
-- resolution is always fresh (unlike the frozen intent payload), so once a conversation moves on, the same
-- logical key would now resolve to a different recipient -- a real payload change, correctly refused as a
-- conflict rather than replayed. That refusal is exercised in the email sibling test; this file only proves
-- the resolution itself follows the conversation.
insert into public.communication_inbound_messages (
  organization_id, channel, client_id, client_contact_method_id, provider, provider_message_id,
  sender_phone, subject, text_content, created_at
) values (
  'ec100000-0000-0000-0000-000000000001', 'sms', 'ec200000-0000-0000-0000-000000000001',
  'ec300000-0000-0000-0000-000000000002', 'twilio', 'reply-sms-inbound-1',
  '+15552220002', '', 'Calling back on my other line', now() + interval '1 second'
);
select is(
  (public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-follows-secondary', 'Got it, texting you here.'
  )).recipient_phone,
  '+15552220002',
  'an SMS reply targets whichever number this conversation most recently used, not necessarily primary'
);

-- A client with no phone contact method at all cannot be replied to.
select throws_ok(
  $$select public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000002', 'reply-sms-no-phone', 'Hello?'
  )$$,
  '23503', 'This customer has no active phone number to reply to.',
  'a client with no phone contact method cannot receive an SMS conversation reply'
);

-- The inherited gate still applies: a member without conversations.send/customers.view is refused.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('ec000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'sms-reply-no-perm@example.test', 'test', now(), now());
insert into public.organization_members (organization_id, user_id, role, status) values
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000002', 'field', 'active');
select throws_ok(
  $$select public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000002',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-no-perm', 'Hi from an unauthorized member.'
  )$$,
  '42501', 'You do not have permission to send a customer message.',
  'a member without conversations.send/customers.view cannot enqueue an SMS reply (inherited from the operational command)'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Stage 6D-2: a photo attaches to the reply through the same transaction as the intent.
-- ---------------------------------------------------------------------------------------------------------------
select lives_ok(
  $$select public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-with-photo', 'Here is a look at the job site.',
    '[{"object_key": "ec100000-0000-0000-0000-000000000001/outbound-sms-attachments/site.jpg",
       "file_name": "site.jpg", "mime_type": "image/jpeg", "byte_size": 204800}]'::jsonb
  )$$,
  'an MMS-eligible reply with one photo attaches successfully'
);
select is(
  (select file_name from public.communication_outbound_attachments a
    join public.communication_delivery_intents i on i.id = a.delivery_intent_id
    where i.logical_send_key = 'reply-sms-with-photo'),
  'site.jpg', 'the attached photo is recorded against the new intent'
);
select throws_like(
  $$select public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-photo-wrong-org', 'Nice try.',
    '[{"object_key": "not-my-org/outbound-sms-attachments/site.jpg",
       "file_name": "site.jpg", "mime_type": "image/jpeg", "byte_size": 204800}]'::jsonb
  )$$,
  '%does not belong to this business%',
  'an object key outside this organization''s own prefix is refused'
);
select throws_like(
  $$select public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-two-photos', 'Two photos.',
    '[{"object_key": "ec100000-0000-0000-0000-000000000001/outbound-sms-attachments/a.jpg",
       "file_name": "a.jpg", "mime_type": "image/jpeg", "byte_size": 1000},
      {"object_key": "ec100000-0000-0000-0000-000000000001/outbound-sms-attachments/b.jpg",
       "file_name": "b.jpg", "mime_type": "image/jpeg", "byte_size": 1000}]'::jsonb
  )$$,
  '%Attach at most one file%',
  'a second file on the same text message is refused'
);
select is(
  (select reserved_purchased_minor from public.communication_sms_credit_reservations r
    join public.communication_delivery_intents i on i.id = r.delivery_intent_id
    where i.logical_send_key = 'reply-sms-with-photo'),
  20::bigint, 'a real MMS photo bills the flat 20-cent mms rate, not a per-segment charge'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Stage 6D-3: a non-image file (or an ineligible picture) gets a secure link baked into the body instead of
-- a refusal. The wire body carries the link; raw_body keeps the customer's own typed text untouched.
-- ---------------------------------------------------------------------------------------------------------------
select lives_ok(
  $$select public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-with-link-file', 'Here is the estimate.',
    '[{"object_key": "ec100000-0000-0000-0000-000000000001/outbound-sms-attachments/estimate.pdf",
       "file_name": "estimate.pdf", "mime_type": "application/pdf", "byte_size": 40960,
       "access_token_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
       "link_url": "https://app.example.test/m/token-one"}]'::jsonb
  )$$,
  'a non-image attachment sends successfully with a secure link instead of being refused'
);
select is(
  (select body from public.communication_sms_message_snapshots snap
    join public.communication_delivery_intents i on i.id = snap.delivery_intent_id
    where i.logical_send_key = 'reply-sms-with-link-file'),
  E'Here is the estimate.\n\nhttps://app.example.test/m/token-one',
  'the wire body has the secure link appended'
);
select is(
  (select raw_body from public.communication_sms_message_snapshots snap
    join public.communication_delivery_intents i on i.id = snap.delivery_intent_id
    where i.logical_send_key = 'reply-sms-with-link-file'),
  'Here is the estimate.',
  'raw_body keeps the customer''s own typed text, without the link'
);
select is(
  (select count(*)::integer from public.communication_sms_attachment_access_links l
    join public.communication_delivery_intents i on i.id = l.delivery_intent_id
    where i.logical_send_key = 'reply-sms-with-link-file'
      and l.token_hash = '\xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'::bytea),
  1, 'the access link is recorded against the exact token hash the caller supplied'
);

-- A retry with a genuinely fresh token (never guaranteed to repeat -- see this migration's own header note)
-- for the identical customer-typed text is still recognized as the same logical send, not a false conflict.
select is(
  (public.enqueue_conversation_reply_sms(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'ec200000-0000-0000-0000-000000000001', 'reply-sms-with-link-file', 'Here is the estimate.',
    '[{"object_key": "ec100000-0000-0000-0000-000000000001/outbound-sms-attachments/estimate.pdf",
       "file_name": "estimate.pdf", "mime_type": "application/pdf", "byte_size": 40960,
       "access_token_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
       "link_url": "https://app.example.test/m/token-two"}]'::jsonb
  )).id,
  (select id from public.communication_delivery_intents where logical_send_key = 'reply-sms-with-link-file'),
  'a retry with a different (never-reused) token for the same typed text replays the original send'
);

select * from finish();
rollback;
