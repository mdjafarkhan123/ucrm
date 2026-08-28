-- Communications Part 5C-ii: enqueue_inbound_message_forward, claim_communication_forward_event,
-- finalize_communication_forward_event, quarantine_stale_communication_forward_claims. A forward is not
-- customer email -- see 20260826090100_communications_forward_events.sql's header comment -- so this
-- test does not touch the allowance/capacity-claim fixtures the reply-command tests need.
begin;

create extension if not exists pgtap with schema extensions;
select plan(23);

select function_privs_are(
  'public', 'enqueue_inbound_message_forward',
  array['uuid', 'uuid', 'uuid', 'text', 'text[]', 'text', 'text', 'text', 'uuid[]'], 'service_role',
  array['EXECUTE'], 'only the service worker can enqueue a forward'
);
select throws_ok(
  $$set local role authenticated; select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'x', array['x@example.test'], 'x', '<p>x</p>', 'x'
  )$$,
  '42501', null, 'authenticated callers cannot call the command directly'
);
reset role;
select throws_ok(
  $$set local role anon; select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'x', array['x@example.test'], 'x', '<p>x</p>', 'x'
  )$$,
  '42501', null, 'anonymous callers cannot call the command directly'
);
reset role;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('fd100000-0000-0000-0000-000000000001', 'Forward Test', 'forward-test', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'fd000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'forward-actor@example.test', 'test', now(), now(), now()
), (
  'fd000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'forward-no-permission@example.test', 'test', now(), now(), now()
);
insert into public.organization_members (organization_id, user_id, role, status)
values
  ('fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000002', 'field', 'active');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001', 'conversations.forward', 'grant'),
  ('fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001', 'customers.view', 'grant');

insert into public.clients (id, organization_id, display_name)
values ('fd200000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001', 'Forward Client');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('fd300000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001',
  'fd200000-0000-0000-0000-000000000001', 'email', 'client@forward-test.example', true);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, spf_status
) values (
  'fd400000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001',
  'sending', 'mail.forward-test.example', 'verified', true, true, 'passing', 'passing', 'pending'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated, assigned_user_id
) values (
  'fd500000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001',
  'fd400000-0000-0000-0000-000000000001', 'hello@mail.forward-test.example', 'Forward Sender',
  'enabled', true, true, true, 'fd000000-0000-0000-0000-000000000001'
);

-- A resolved inbound message (client/contact-method/sender all set together, per
-- communication_inbound_messages_resolution_complete) with one available and one not-yet-imported
-- attachment.
insert into public.communication_inbound_messages (
  id, organization_id, client_id, client_contact_method_id, sender_id,
  sender_email, subject, text_content, provider_message_id
) values (
  'fd600000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001',
  'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001',
  'fd500000-0000-0000-0000-000000000001', 'lead@outside.example', 'Original subject', 'Original body',
  'forward-test-inbound-1'
);
-- An unresolved message: no client, so it cannot be forwarded.
insert into public.communication_inbound_messages (
  id, organization_id, sender_email, subject, text_content, provider_message_id, review_status, review_reason
) values (
  'fd600000-0000-0000-0000-000000000002', 'fd100000-0000-0000-0000-000000000001',
  'unknown@outside.example', 'Unresolved subject', 'Unresolved body', 'forward-test-inbound-2',
  'pending_review', 'unknown_sender'
);
insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size, object_key, status
) values (
  'fd700000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001',
  'fd600000-0000-0000-0000-000000000001', 'photo.jpg', 'image/jpeg', 1024,
  'fd100000-0000-0000-0000-000000000001/inbound/photo.jpg', 'available'
), (
  'fd700000-0000-0000-0000-000000000002', 'fd100000-0000-0000-0000-000000000001',
  'fd600000-0000-0000-0000-000000000001', 'scanning.jpg', 'image/jpeg', 2048, null, 'pending_scan'
);

select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000002',
    'fd600000-0000-0000-0000-000000000001', 'forward-no-perm', array['out@example.test'],
    'Fwd: Subject', '<p>Body</p>', 'Body'
  )$$,
  '42501', 'You do not have permission to forward a message.',
  'a member without conversations.forward/customers.view cannot enqueue a forward'
);

update public.organizations set lifecycle_status = 'suspended'
where id = 'fd100000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-suspended', array['out@example.test'],
    'Fwd: Subject', '<p>Body</p>', 'Body'
  )$$,
  '55000', null, 'a non-active organization cannot enqueue a forward'
);
update public.organizations set lifecycle_status = 'active'
where id = 'fd100000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000002', 'forward-unresolved', array['out@example.test'],
    'Fwd: Subject', '<p>Body</p>', 'Body'
  )$$,
  '55000', 'Resolve this message to a conversation before forwarding it.',
  'an unresolved (guarded) message cannot be forwarded'
);

select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-no-recipients', array[]::text[],
    'Fwd: Subject', '<p>Body</p>', 'Body'
  )$$,
  '23514', 'Choose between 1 and 10 recipients.', 'a forward needs at least one recipient'
);
select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-bad-email', array['not-an-email'],
    'Fwd: Subject', '<p>Body</p>', 'Body'
  )$$,
  '23514', 'Enter a valid email address for every recipient.', 'every recipient must look like an email address'
);
select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-bad-attachment', array['out@example.test'],
    'Fwd: Subject', '<p>Body</p>', 'Body', array['fd700000-0000-0000-0000-000000000002']::uuid[]
  )$$,
  '55000', 'One or more attachments are no longer available to forward.',
  'a not-yet-available attachment cannot be forwarded'
);

-- Success: a real forward with one available attachment.
select is(
  (public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-success', array['colleague@example.test', 'vendor@example.test'],
    'Fwd: Original subject', '<p>Body</p>', 'Body', array['fd700000-0000-0000-0000-000000000001']::uuid[]
  )).status,
  'queued', 'a valid forward enqueues in queued status'
);
select is(
  (select client_id from public.communication_forward_events where logical_send_key = 'forward-success'),
  'fd200000-0000-0000-0000-000000000001', 'the forward event carries the conversation''s client id'
);
select is(
  (select sender_id from public.communication_forward_events where logical_send_key = 'forward-success'),
  'fd500000-0000-0000-0000-000000000001', 'the forward event resolves the actor''s enabled manual sender'
);
select is(
  (select count(*)::integer from public.communication_forward_attachments
    where forward_event_id = (select id from public.communication_forward_events
      where logical_send_key = 'forward-success')),
  1, 'the requested available attachment is linked to the forward event'
);

-- Idempotency: replaying the same logical send key returns the same row, not a second one.
select is(
  (public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-success', array['colleague@example.test', 'vendor@example.test'],
    'Fwd: Original subject', '<p>Body</p>', 'Body', array['fd700000-0000-0000-0000-000000000001']::uuid[]
  )).id,
  (select id from public.communication_forward_events where logical_send_key = 'forward-success'),
  'replaying the same logical send key returns the original forward event'
);
select is(
  (select count(*)::integer from public.communication_forward_events where logical_send_key = 'forward-success'),
  1, 'replaying the same logical send key does not create a duplicate row'
);

-- No eligible sender.
update public.communication_email_senders set allows_manual = false
where id = 'fd500000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.enqueue_inbound_message_forward(
    'fd100000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001',
    'fd600000-0000-0000-0000-000000000001', 'forward-no-sender', array['out@example.test'],
    'Fwd: Subject', '<p>Body</p>', 'Body'
  )$$,
  '55000', 'Your assigned email sender is not ready. Ask an administrator to review it.',
  'a forward cannot be enqueued without a ready assigned manual sender'
);
update public.communication_email_senders set allows_manual = true
where id = 'fd500000-0000-0000-0000-000000000001';

-- Claim: the queued row is picked up, status flips to claimed, and a claim token is issued.
select is(
  (select forward_event_id from public.claim_communication_forward_event()),
  (select id from public.communication_forward_events where logical_send_key = 'forward-success'),
  'claim_communication_forward_event returns the queued forward event'
);
select is(
  (select status from public.communication_forward_events where logical_send_key = 'forward-success'),
  'claimed', 'claiming the forward event sets its status to claimed'
);

-- Finalize: submitting requires a provider message id.
select throws_ok(
  $$select public.finalize_communication_forward_event(
    (select id from public.communication_forward_events where logical_send_key = 'forward-success'),
    (select claim_token from public.communication_forward_events where logical_send_key = 'forward-success'),
    'submitted'
  )$$,
  '23502', 'A submitted forward requires a provider message identifier.',
  'finalizing as submitted without a provider message id is rejected'
);
select is(
  ((public.finalize_communication_forward_event(
    (select id from public.communication_forward_events where logical_send_key = 'forward-success'),
    (select claim_token from public.communication_forward_events where logical_send_key = 'forward-success'),
    'submitted', 'brevo-message-1'
  ))).status,
  'submitted', 'finalizing as submitted marks the forward event submitted'
);
select isnt(
  (select accepted_at from public.communication_forward_events where logical_send_key = 'forward-success'),
  null, 'a submitted forward event records an acceptance time'
);

-- Quarantine: a stale claimed row becomes submission_unknown.
insert into public.communication_forward_events (
  id, organization_id, client_id, source_inbound_message_id, sender_id, recipient_emails,
  logical_send_key, subject, html_content, text_content, status, claimed_at, claim_token, created_by
) values (
  'fd800000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001',
  'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001',
  'fd500000-0000-0000-0000-000000000001', array['stale@example.test'], 'forward-stale-claim',
  'Fwd: Stale', '<p>Stale</p>', 'Stale', 'claimed', now() - interval '1 hour',
  'fd900000-0000-0000-0000-000000000001', 'fd000000-0000-0000-0000-000000000001'
);
select is(
  public.quarantine_stale_communication_forward_claims(50, interval '15 minutes'),
  1, 'quarantine reclaims exactly the one stale claimed forward event'
);
select is(
  (select status from public.communication_forward_events where id = 'fd800000-0000-0000-0000-000000000001'),
  'submission_unknown', 'a quarantined forward event moves to submission_unknown'
);

select * from finish();
rollback;
