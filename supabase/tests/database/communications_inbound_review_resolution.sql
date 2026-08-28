-- Communications Part 5C-i: resolve_inbound_message_review -- link a guarded ("Needs review") inbound
-- conversation to a client, or dismiss it. Resolution always covers every pending message from that
-- sender address, because that is exactly the row /communications shows.
begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

select function_privs_are(
  'public', 'resolve_inbound_message_review',
  array['uuid', 'uuid', 'text', 'text', 'uuid'], 'service_role',
  array['EXECUTE'], 'only the service worker can resolve a guarded conversation'
);
select throws_ok(
  $$set local role authenticated; select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'stranger@outside.example', 'dismiss', null
  )$$,
  '42501', null, 'authenticated callers cannot call the command directly'
);
reset role;
select throws_ok(
  $$set local role anon; select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'stranger@outside.example', 'dismiss', null
  )$$,
  '42501', null, 'anonymous callers cannot call the command directly'
);
reset role;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('ec100000-0000-0000-0000-000000000001', 'Review Test', 'review-test', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'ec000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'review-actor@example.test', 'test', now(), now(), now()
), (
  'ec000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'review-no-permission@example.test', 'test', now(), now(), now()
), (
  'ec000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'review-no-customers@example.test', 'test', now(), now(), now()
);
insert into public.organization_members (organization_id, user_id, role, status)
values
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000002', 'field', 'active'),
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000003', 'field', 'active');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'conversations.manage_assignment', 'grant'),
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001', 'customers.view', 'grant'),
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000002',
    'conversations.manage_assignment', 'deny'),
  -- Can manage conversations but cannot see customers: allowed to dismiss, never to link.
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000003',
    'conversations.manage_assignment', 'grant'),
  ('ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000003', 'customers.view', 'deny');

insert into public.clients (id, organization_id, display_name)
values
  ('ec200000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001', 'Review Client'),
  ('ec200000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001', 'Archived Client');
update public.clients set deleted_at = now() where id = 'ec200000-0000-0000-0000-000000000002';

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('ec300000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  'ec200000-0000-0000-0000-000000000001', 'email', 'known@review-test.example', true);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, spf_status
) values (
  'ec400000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  'sending', 'mail.review-test.example', 'verified', true, true, 'passing', 'passing', 'pending'
);
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, dmarc_status, spf_status, inbound_mx_status
) values (
  'ec400000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001',
  'receiving', 'reply.review-test.example', 'verified', true, false, 'passing', 'unchecked', 'unchecked',
  'unchecked', 'passing'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated, assigned_user_id
) values (
  'ec500000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  'ec400000-0000-0000-0000-000000000001', 'default@mail.review-test.example', 'Default Sender',
  'enabled', true, true, true, 'ec000000-0000-0000-0000-000000000001'
), (
  'ec500000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001',
  'ec400000-0000-0000-0000-000000000001', 'alias-owner@mail.review-test.example', 'Alias Sender',
  'enabled', false, true, true, null
);
insert into public.communication_reply_aliases (
  id, organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id,
  alias_local_part, expires_at
) values (
  'ec600000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  'ec400000-0000-0000-0000-000000000002', 'ec500000-0000-0000-0000-000000000002',
  'ec200000-0000-0000-0000-000000000001', 'ec300000-0000-0000-0000-000000000001',
  'expired-alias-local-part', now() - interval '1 day'
);

-- Two guarded messages from one unknown sender (no alias at all), plus one held on an expired alias.
insert into public.communication_inbound_messages (
  id, organization_id, reply_alias_id, sender_email, sender_name, subject, text_content,
  provider_message_id, review_status, review_reason, automation_suppressed
) values (
  'ec700000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001', null,
  'Stranger@Outside.example', 'A. Stranger', 'Is this thing on?', 'Body one',
  'review-test-inbound-1', 'pending_review', 'unknown_sender', true
), (
  'ec700000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001', null,
  'stranger@outside.example', 'A. Stranger', 'Following up', 'Body two',
  'review-test-inbound-2', 'pending_review', 'unknown_sender', true
), (
  'ec700000-0000-0000-0000-000000000003', 'ec100000-0000-0000-0000-000000000001',
  'ec600000-0000-0000-0000-000000000001',
  'known@review-test.example', 'Review Client', 'Late reply', 'Body three',
  'review-test-inbound-3', 'pending_review', 'expired_alias', true
), (
  'ec700000-0000-0000-0000-000000000004', 'ec100000-0000-0000-0000-000000000001', null,
  'junk@outside.example', 'Junk Sender', 'Buy something', 'Body four',
  'review-test-inbound-4', 'pending_review', 'unknown_sender', true
);

select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'stranger@outside.example', 'quarantine', null
  )$$,
  '22023', 'Unknown review resolution.', 'only link and dismiss are accepted resolutions'
);
select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000002',
    'stranger@outside.example', 'dismiss', null
  )$$,
  '42501', 'You do not have permission to manage conversations.',
  'a member without conversations.manage_assignment cannot resolve a guarded conversation'
);
select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000003',
    'stranger@outside.example', 'link', 'ec200000-0000-0000-0000-000000000001'
  )$$,
  '42501', 'You do not have permission to manage conversations.',
  'linking additionally requires customer access, since it writes contact data'
);
select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'nobody@outside.example', 'dismiss', null
  )$$,
  '55000', 'This conversation no longer needs review.',
  'an address with nothing pending cannot be resolved'
);
select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'stranger@outside.example', 'link', null
  )$$,
  '22023', 'Choose a client to link this conversation to.',
  'linking without a client is rejected'
);
select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'stranger@outside.example', 'link', 'ec200000-0000-0000-0000-000000000002'
  )$$,
  '23503', 'That client is not available.', 'a deleted client cannot receive a linked conversation'
);

-- Linking covers every pending message from that sender address, matched case-insensitively.
select is(
  public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'STRANGER@outside.example', 'link', 'ec200000-0000-0000-0000-000000000001'
  ),
  2, 'linking resolves every pending message from that sender, regardless of address casing'
);
select is(
  (select count(*)::integer from public.communication_inbound_messages
    where id in ('ec700000-0000-0000-0000-000000000001', 'ec700000-0000-0000-0000-000000000002')
      and review_status = 'accepted' and client_id = 'ec200000-0000-0000-0000-000000000001'),
  2, 'both linked messages now belong to the chosen client'
);
select is(
  (select review_reason from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000001'),
  'unknown_sender', 'a linked message keeps the reason it was originally held for'
);
select is(
  (select review_resolved_by from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000001'),
  'ec000000-0000-0000-0000-000000000001'::uuid, 'the resolving member is recorded on the message'
);
select isnt(
  (select review_resolved_at from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000001'),
  null::timestamptz, 'the resolution time is recorded on the message'
);
select is(
  (select automation_suppressed from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000001'),
  true, 'linking never un-suppresses automation for a message that arrived unrecognised'
);
select is(
  (select count(*)::integer from public.client_contact_methods
    where client_id = 'ec200000-0000-0000-0000-000000000001'
      and normalized_value = 'stranger@outside.example'),
  1, 'the sender address is recorded once on the client, not once per message'
);
select is(
  (select is_primary from public.client_contact_methods
    where client_id = 'ec200000-0000-0000-0000-000000000001'
      and normalized_value = 'stranger@outside.example'),
  false, 'a linked address never displaces the client''s primary email'
);
select is(
  (select sender_id from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000001'),
  'ec500000-0000-0000-0000-000000000001'::uuid,
  'a truly unknown sender falls back to the organization default sending address'
);

-- A message held on an expired alias already knows which sending address its thread belongs to.
select is(
  public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'known@review-test.example', 'link', 'ec200000-0000-0000-0000-000000000001'
  ),
  1, 'an expired-alias message resolves on its own'
);
select is(
  (select sender_id from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000003'),
  'ec500000-0000-0000-0000-000000000002'::uuid,
  'an expired-alias message keeps the sending address its thread already used'
);
select is(
  (select client_contact_method_id from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000003'),
  'ec300000-0000-0000-0000-000000000001'::uuid,
  'an address already on the client is reused rather than stored a second time'
);

-- Dismissal keeps the record and its reason; it is not a delete.
select is(
  public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'junk@outside.example', 'dismiss', null
  ),
  1, 'dismissing resolves the pending message'
);
select is(
  (select review_status || '/' || review_reason from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000004'),
  'dismissed/unknown_sender', 'a dismissed message survives with the reason it was held for'
);
select is(
  (select client_id from public.communication_inbound_messages
    where id = 'ec700000-0000-0000-0000-000000000004'),
  null::uuid, 'dismissing never attaches the message to a client'
);
select throws_ok(
  $$select public.resolve_inbound_message_review(
    'ec100000-0000-0000-0000-000000000001', 'ec000000-0000-0000-0000-000000000001',
    'junk@outside.example', 'link', 'ec200000-0000-0000-0000-000000000001'
  )$$,
  '55000', 'This conversation no longer needs review.',
  'an already-resolved conversation cannot be resolved twice'
);

select * from finish();
rollback;
