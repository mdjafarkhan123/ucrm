-- Communications Part 5E: enqueue_conversation_reply_email -- reply from an already-open Conversations
-- thread. Recipient is never browser-chosen; it is resolved here from the conversation's own most
-- recent activity, and the send always draws on the protected 'essential' allowance.
begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

select function_privs_are(
  'public', 'enqueue_conversation_reply_email',
  array['uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text'], 'service_role',
  array['EXECUTE'], 'only the service worker can enqueue a conversation reply'
);
select throws_ok(
  $$set local role authenticated; select public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'x', 'x', '<p>x</p>', 'x'
  )$$,
  '42501', null, 'authenticated callers cannot call the command directly'
);
reset role;
select throws_ok(
  $$set local role anon; select public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'x', 'x', '<p>x</p>', 'x'
  )$$,
  '42501', null, 'anonymous callers cannot call the command directly'
);
reset role;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('eb100000-0000-0000-0000-000000000001', 'Reply Test', 'reply-test', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'eb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reply-actor@example.test', 'test', now(), now(), now()
), (
  'eb000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reply-no-permission@example.test', 'test', now(), now(), now()
);
insert into public.organization_members (organization_id, user_id, role, status)
values
  ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000002', 'field', 'active');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'conversations.send', 'grant'),
  ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'customers.view', 'grant');

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at)
values ('eb100000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');
select public.apply_organization_limit_exception(
  'eb100000-0000-0000-0000-000000000001', 'operational_email_recipients', 'numeric', 5,
  now() - interval '1 minute', null, 'reply-operational-capacity', 'Reply test capacity.', 'owner@example.test'
);
select public.apply_organization_limit_exception(
  'eb100000-0000-0000-0000-000000000001', 'essential_email_recipients', 'numeric', 5,
  now() - interval '1 minute', null, 'reply-essential-capacity', 'Reply test capacity.', 'owner@example.test'
);

insert into public.clients (id, organization_id, display_name)
values ('eb200000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001', 'Reply Client');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('eb300000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'email', 'primary@reply-test.example', true),
  ('eb300000-0000-0000-0000-000000000002', 'eb100000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'email', 'secondary@reply-test.example', false);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, spf_status
) values (
  'eb400000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001',
  'sending', 'mail.reply-test.example', 'verified', true, true, 'passing', 'passing', 'pending'
);
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, dmarc_status, spf_status, inbound_mx_status
) values (
  'eb400000-0000-0000-0000-000000000002', 'eb100000-0000-0000-0000-000000000001',
  'receiving', 'reply.reply-test.example', 'verified', true, false, 'passing', 'unchecked', 'unchecked',
  'unchecked', 'passing'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated, assigned_user_id
) values (
  'eb500000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001',
  'eb400000-0000-0000-0000-000000000001', 'hello@mail.reply-test.example', 'Reply Sender',
  'enabled', true, true, true, 'eb000000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$select public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000002',
    'eb200000-0000-0000-0000-000000000001', 'reply-no-perm', 'Subject', '<p>Body</p>', 'Body'
  )$$,
  '42501', 'You do not have permission to send a customer message.',
  'a member without conversations.send/customers.view cannot enqueue a reply'
);

update public.organizations set lifecycle_status = 'suspended'
where id = 'eb100000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'reply-suspended', 'Subject', '<p>Body</p>', 'Body'
  )$$,
  '55000', null, 'a non-active organization cannot enqueue a reply'
);
update public.organizations set lifecycle_status = 'active'
where id = 'eb100000-0000-0000-0000-000000000001';

-- No prior activity on this conversation: falls back to the client's primary email address.
select is(
  (public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'reply-fallback-primary', 'Subject', '<p>Body</p>', 'Body'
  )).recipient_email,
  'primary@reply-test.example',
  'with no prior conversation activity, the reply falls back to the primary email address'
);
select is(
  (select allowance_class from public.communication_delivery_intents
    where logical_send_key = 'reply-fallback-primary'),
  'essential', 'a conversation reply always draws on the protected essential allowance'
);
select is(
  (select send_kind from public.communication_delivery_intents
    where logical_send_key = 'reply-fallback-primary'),
  'manual', 'a conversation reply is a manual send'
);
select isnt(
  (select reply_alias_id from public.communication_delivery_intents
    where logical_send_key = 'reply-fallback-primary'),
  null, 'a conversation reply attaches a reply alias, same as the client-detail manual send'
);

-- A more recent inbound message on the secondary address redirects the reply to that address.
-- created_at is set explicitly ahead of the prior intent's: every statement in this pgTAP transaction
-- shares one now() (transaction start), so relying on the implicit default would tie instead of order.
insert into public.communication_inbound_messages (
  organization_id, client_id, client_contact_method_id, sender_id, reply_alias_id,
  sender_email, subject, text_content, provider_message_id, created_at
) values (
  'eb100000-0000-0000-0000-000000000001', 'eb200000-0000-0000-0000-000000000001',
  'eb300000-0000-0000-0000-000000000002', 'eb500000-0000-0000-0000-000000000001',
  (select reply_alias_id from public.communication_delivery_intents
    where logical_send_key = 'reply-fallback-primary'),
  'secondary@reply-test.example', 'A reply from the secondary address', 'Body', 'reply-test-inbound-1',
  now() + interval '1 second'
);
select is(
  (public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'reply-follows-secondary', 'Subject', '<p>Body</p>', 'Body'
  )).recipient_email,
  'secondary@reply-test.example',
  'a reply targets whichever address the conversation most recently used, not necessarily primary'
);
select is(
  (select count(*)::integer from public.communication_reply_aliases
    where organization_id = 'eb100000-0000-0000-0000-000000000001'
      and client_contact_method_id = 'eb300000-0000-0000-0000-000000000002'),
  1, 'replying to the secondary address mints its own alias, distinct from the primary address''s alias'
);

-- A subsequent outbound send to the primary address is newer again, so the next reply follows it back.
insert into public.communication_delivery_intents (
  organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
  subject, html_content, text_content, send_kind, allowance_class, sender_id, created_at
) values (
  'eb100000-0000-0000-0000-000000000001', 'eb200000-0000-0000-0000-000000000001',
  'eb300000-0000-0000-0000-000000000001', 'reply-manual-primary-touch', 'primary@reply-test.example',
  'Manual to primary', '<p>Manual</p>', 'Manual', 'manual', 'optional',
  'eb500000-0000-0000-0000-000000000001', now() + interval '2 seconds'
);
select is(
  (public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'reply-follows-primary-again', 'Subject', '<p>Body</p>', 'Body'
  )).recipient_email,
  'primary@reply-test.example',
  'the most recent activity of either direction decides the reply address, not just inbound'
);

-- Idempotency: replaying the same logical send key returns the same row, not a second one.
select is(
  (public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'reply-fallback-primary', 'Subject', '<p>Body</p>', 'Body'
  )).id,
  (select id from public.communication_delivery_intents where logical_send_key = 'reply-fallback-primary'),
  'replaying the same logical send key returns the original intent'
);
select is(
  (select count(*)::integer from public.communication_delivery_intents
    where logical_send_key = 'reply-fallback-primary'),
  1, 'replaying the same logical send key does not create a duplicate row'
);

-- No eligible sender: the acting member has no enabled manual sender assigned to them.
update public.communication_email_senders set allows_manual = false
where id = 'eb500000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'reply-no-sender', 'Subject', '<p>Body</p>', 'Body'
  )$$,
  '55000', 'Your assigned email sender is not ready. Ask an administrator to review it.',
  'a reply cannot be enqueued without a ready assigned manual sender'
);
update public.communication_email_senders set allows_manual = true
where id = 'eb500000-0000-0000-0000-000000000001';

-- A client with no email contact method at all cannot be replied to.
insert into public.clients (id, organization_id, display_name)
values ('eb200000-0000-0000-0000-000000000002', 'eb100000-0000-0000-0000-000000000001', 'No Email Client');
select throws_ok(
  $$select public.enqueue_conversation_reply_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000002', 'reply-no-email', 'Subject', '<p>Body</p>', 'Body'
  )$$,
  '23503', 'This customer has no active email address to reply to.',
  'a client with no email contact method cannot receive a conversation reply'
);

select * from finish();
rollback;
