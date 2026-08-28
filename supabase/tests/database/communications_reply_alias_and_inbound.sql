-- Communications Part 4 (foundation slice): reply-alias correlation, its wiring into outbound send,
-- and the inbound message/attachment schema's own constraints.
begin;

create extension if not exists pgtap with schema extensions;
select plan(32);

select has_table('public', 'communication_reply_aliases', 'reply alias table exists');
select has_table('public', 'communication_inbound_messages', 'inbound message table exists');
select has_table('public', 'communication_inbound_attachments', 'inbound attachment table exists');
select has_column(
  'public', 'communication_delivery_intents', 'reply_alias_id',
  'an outbound send records which conversation alias it used'
);

select function_privs_are(
  'public', 'ensure_communication_reply_alias', array['uuid', 'uuid', 'uuid', 'uuid'], 'service_role',
  array['EXECUTE'], 'only the service worker can mint or reuse a reply alias'
);
select throws_ok(
  $$set local role authenticated; select public.ensure_communication_reply_alias(
    'da100000-0000-0000-0000-000000000001', 'da500000-0000-0000-0000-000000000001',
    'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001'
  )$$,
  '42501', null, 'authenticated callers cannot mint a reply alias'
);
reset role;
select throws_ok(
  $$set local role anon; select public.ensure_communication_reply_alias(
    'da100000-0000-0000-0000-000000000001', 'da500000-0000-0000-0000-000000000001',
    'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001'
  )$$,
  '42501', null, 'anonymous callers cannot mint a reply alias'
);
reset role;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('da100000-0000-0000-0000-000000000001', 'Alias Test', 'alias-test', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'da000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'alias-actor@example.test', 'test', now(), now(), now()
);
insert into public.organization_members (organization_id, user_id, role, status)
values ('da100000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'admin', 'active');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('da100000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'conversations.send', 'grant'),
  ('da100000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'customers.view', 'grant'),
  ('da100000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001', 'quotes.send', 'grant');

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at)
values ('da100000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');
select public.apply_organization_limit_exception(
  'da100000-0000-0000-0000-000000000001', 'operational_email_recipients', 'numeric', 5,
  now() - interval '1 minute', null, 'alias-operational-capacity', 'Alias test capacity.', 'owner@example.test'
);
select public.apply_organization_limit_exception(
  'da100000-0000-0000-0000-000000000001', 'essential_email_recipients', 'numeric', 5,
  now() - interval '1 minute', null, 'alias-essential-capacity', 'Alias test capacity.', 'owner@example.test'
);

insert into public.clients (id, organization_id, display_name)
values ('da200000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001', 'Alias Client');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('da300000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'da200000-0000-0000-0000-000000000001', 'email', 'customer@alias-test.example', true);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, spf_status
) values (
  'da400000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'sending', 'mail.alias-test.example', 'verified', true, true, 'passing', 'passing', 'pending'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated, assigned_user_id
) values (
  'da500000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'da400000-0000-0000-0000-000000000001', 'hello@mail.alias-test.example', 'Alias Sender',
  'enabled', true, true, true, 'da000000-0000-0000-0000-000000000001'
);

-- No receiving domain has been provisioned yet -- outbound send must proceed without a Reply-To rather
-- than fail, exactly like every other eligibility gap in this send path.
select is(
  public.ensure_communication_reply_alias(
    'da100000-0000-0000-0000-000000000001', 'da500000-0000-0000-0000-000000000001',
    'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001'
  ),
  null::public.communication_reply_aliases,
  'no verified receiving domain means no reply alias is minted'
);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, dmarc_status, spf_status, inbound_mx_status
) values (
  'da400000-0000-0000-0000-000000000002', 'da100000-0000-0000-0000-000000000001',
  'receiving', 'reply.alias-test.example', 'verified', true, false, 'passing', 'unchecked', 'unchecked',
  'unchecked', 'passing'
);

select is(
  (length((public.ensure_communication_reply_alias(
    'da100000-0000-0000-0000-000000000001', 'da500000-0000-0000-0000-000000000001',
    'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001'
  )).alias_local_part)),
  32, 'a verified receiving domain lets ensure_communication_reply_alias mint an opaque local part'
);

select is(
  (public.ensure_communication_reply_alias(
    'da100000-0000-0000-0000-000000000001', 'da500000-0000-0000-0000-000000000001',
    'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001'
  )).id,
  (select id from public.communication_reply_aliases
    where organization_id = 'da100000-0000-0000-0000-000000000001'
      and sender_id = 'da500000-0000-0000-0000-000000000001'
      and client_id = 'da200000-0000-0000-0000-000000000001'
      and client_contact_method_id = 'da300000-0000-0000-0000-000000000001'),
  'calling ensure_communication_reply_alias again for the same conversation reuses the same alias'
);

select is(
  (select count(*)::integer from public.communication_reply_aliases
    where organization_id = 'da100000-0000-0000-0000-000000000001'),
  1, 'only one alias row exists per (sender, client, contact method) conversation'
);

select throws_ok(
  $$insert into public.communication_reply_aliases (
    organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id, alias_local_part
  ) values (
    'da100000-0000-0000-0000-000000000001', 'da400000-0000-0000-0000-000000000001',
    'da500000-0000-0000-0000-000000000001', 'da200000-0000-0000-0000-000000000001',
    'da300000-0000-0000-0000-000000000001', 'deadbeefdeadbeefdeadbeefdeadbeef'
  )$$,
  '23503', null, 'a reply alias cannot point at a sending-purpose domain'
);

update public.communication_email_domains set lifecycle_state = 'pending_dns'
where id = 'da400000-0000-0000-0000-000000000002';
select throws_ok(
  $$insert into public.communication_reply_aliases (
    organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id, alias_local_part
  ) values (
    'da100000-0000-0000-0000-000000000001', 'da400000-0000-0000-0000-000000000002',
    'da500000-0000-0000-0000-000000000001', 'da200000-0000-0000-0000-000000000001',
    'da300000-0000-0000-0000-000000000001', 'aaaabbbbaaaabbbbaaaabbbbaaaabbbb'
  )$$,
  '23503', null, 'a reply alias cannot point at an unverified receiving domain'
);
update public.communication_email_domains set lifecycle_state = 'verified'
where id = 'da400000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub', 'da000000-0000-0000-0000-000000000001', true);

select is(
  (public.enqueue_manual_communication_email(
    'da100000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001',
    'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001',
    'alias-manual-send', 'Manual subject', '<p>Manual body</p>', 'Manual body'
  )).reply_alias_id,
  (select id from public.communication_reply_aliases
    where organization_id = 'da100000-0000-0000-0000-000000000001'),
  'a manual send attaches the conversation''s existing reply alias'
);

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('da700000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'da200000-0000-0000-0000-000000000001', '1 Alias Street', 'Alias City');
select public.create_quote(
  'da200000-0000-0000-0000-000000000001', 'da700000-0000-0000-0000-000000000001', 'Alias Quote Test', null
);
create function pg_temp.alias_quote_id() returns uuid language sql stable as
  'select id from public.quotes where title = ''Alias Quote Test''';
create function pg_temp.alias_quote_revision() returns integer language sql stable as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Alias Quote Test'')';
select public.replace_quote_version_lines(
  pg_temp.alias_quote_id(), pg_temp.alias_quote_revision(),
  jsonb_build_array(jsonb_build_object(
    'name', 'Alias line', 'category', 'service', 'quantity', 1,
    'unit_price_minor', 5000, 'unit_cost_minor', 2000, 'is_taxable', false
  ))
);
select public.set_quote_draft_tax(pg_temp.alias_quote_id(), pg_temp.alias_quote_revision(), 'no_tax');
select public.publish_quote(pg_temp.alias_quote_id(), pg_temp.alias_quote_revision());

select is(
  (public.enqueue_quote_communication_email(
    'da100000-0000-0000-0000-000000000001', 'da000000-0000-0000-0000-000000000001',
    pg_temp.alias_quote_id(), 'alias-quote-send',
    'https://app.example.test/q/alias-token', decode(repeat('bb', 32), 'hex')
  )).reply_alias_id,
  (select id from public.communication_reply_aliases
    where organization_id = 'da100000-0000-0000-0000-000000000001'),
  'the same client/sender conversation reuses one alias whether the send is manual or quote-automated'
);

select set_config('request.jwt.claim.sub', '', true);

-- Both enqueue functions already insert their own outbox_events row internally; no extra insert needed.
create temporary table alias_claims on commit drop as
select * from public.claim_communication_outbox_event();
select public.claim_communication_outbox_event();

select is(
  (select reply_to_email from alias_claims where delivery_intent_id = (
    select id from public.communication_delivery_intents where logical_send_key = 'alias-manual-send'
  )),
  (select alias_local_part || '@' || 'reply.alias-test.example'
    from public.communication_reply_aliases
    where organization_id = 'da100000-0000-0000-0000-000000000001'),
  'the claim returns the conversation alias address as Reply-To'
);
select is(
  (select reply_to_name from alias_claims where delivery_intent_id = (
    select id from public.communication_delivery_intents where logical_send_key = 'alias-manual-send'
  )),
  'Alias Sender', 'the claim uses the sender''s display name as the Reply-To name'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
  subject, html_content, text_content, send_kind, sender_id, reply_alias_id
) values (
  'da600000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001',
  'alias-no-alias-send', 'customer@alias-test.example', 'No alias', '<p>No alias</p>', 'No alias',
  'manual', 'da500000-0000-0000-0000-000000000001', null
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('da100000-0000-0000-0000-000000000001', 'da600000-0000-0000-0000-000000000001');
select is(
  (select reply_to_email from public.claim_communication_outbox_event()
    where delivery_intent_id = 'da600000-0000-0000-0000-000000000001'),
  null, 'a send with no reply alias claims with a null Reply-To rather than failing'
);

-- Inbound message schema constraints.
select throws_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, sender_email, subject, text_content, review_status, review_reason
  ) values (
    'da100000-0000-0000-0000-000000000001', 'stranger@example.test', 'Hi', 'Hi',
    'accepted', 'unknown_sender'
  )$$,
  '23514', null, 'an accepted inbound message cannot also carry a review reason'
);
select throws_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, sender_email, subject, text_content, review_status, review_reason
  ) values (
    'da100000-0000-0000-0000-000000000001', 'stranger@example.test', 'Hi', 'Hi',
    'pending_review', null
  )$$,
  '23514', null, 'a pending_review inbound message must carry a review reason'
);
select throws_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, client_id, sender_email, subject, text_content
  ) values (
    'da100000-0000-0000-0000-000000000001', 'da200000-0000-0000-0000-000000000001',
    'stranger@example.test', 'Hi', 'Hi'
  )$$,
  '23514', null, 'a partially resolved conversation (client without contact method and sender) is rejected'
);

insert into public.communication_inbound_messages (
  id, organization_id, sender_email, subject, text_content, review_status, review_reason,
  provider_message_id
) values (
  'da800000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'stranger@example.test', 'Unknown sender', 'Body', 'pending_review', 'unknown_sender', 'msg-unknown-1'
);
select is(
  (select review_status from public.communication_inbound_messages
    where id = 'da800000-0000-0000-0000-000000000001'),
  'pending_review', 'a fully unresolved inbound message with a reason is accepted'
);

insert into public.communication_inbound_messages (
  id, organization_id, client_id, client_contact_method_id, sender_id, reply_alias_id,
  sender_email, subject, text_content, provider_message_id
) values (
  'da800000-0000-0000-0000-000000000002', 'da100000-0000-0000-0000-000000000001',
  'da200000-0000-0000-0000-000000000001', 'da300000-0000-0000-0000-000000000001',
  'da500000-0000-0000-0000-000000000001',
  (select id from public.communication_reply_aliases where organization_id = 'da100000-0000-0000-0000-000000000001'),
  'customer@alias-test.example', 'Resolved reply', 'Body', 'msg-resolved-1'
);
select is(
  (select review_status from public.communication_inbound_messages
    where id = 'da800000-0000-0000-0000-000000000002'),
  'accepted', 'a fully resolved inbound message needs no review reason'
);

select throws_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, sender_email, subject, text_content, provider_message_id
  ) values (
    'da100000-0000-0000-0000-000000000001', 'stranger@example.test', 'Duplicate', 'Body', 'msg-resolved-1'
  )$$,
  '23505', null, 'the same provider message id cannot create a second inbound message row'
);

insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size
) values (
  'da900000-0000-0000-0000-000000000001', 'da100000-0000-0000-0000-000000000001',
  'da800000-0000-0000-0000-000000000002', 'photo.jpg', 'image/jpeg', 12345
);
select is(
  (select attachment_count from public.communication_inbound_messages
    where id = 'da800000-0000-0000-0000-000000000002'),
  1, 'the first attachment insert bumps the message attachment count to one'
);
insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size
) values (
  'da900000-0000-0000-0000-000000000002', 'da100000-0000-0000-0000-000000000001',
  'da800000-0000-0000-0000-000000000002', 'invoice.pdf', 'application/pdf', 54321
);
select is(
  (select attachment_count from public.communication_inbound_messages
    where id = 'da800000-0000-0000-0000-000000000002'),
  2, 'a second attachment insert bumps the message attachment count to two'
);

reset role;
select table_privs_are(
  'public', 'communication_reply_aliases', 'anon', array[]::text[],
  'anon has no direct access to reply aliases'
);
select table_privs_are(
  'public', 'communication_reply_aliases', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'the service role has full table access (Supabase''s default grant), unlike anon/authenticated'
);
select table_privs_are(
  'public', 'communication_inbound_messages', 'anon', array[]::text[],
  'anon has no direct access to inbound messages'
);
select table_privs_are(
  'public', 'communication_inbound_messages', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'the service role has full table access (Supabase''s default grant), unlike anon/authenticated'
);
select table_privs_are(
  'public', 'communication_inbound_attachments', 'anon', array[]::text[],
  'anon has no direct access to inbound attachments'
);
select table_privs_are(
  'public', 'communication_inbound_attachments', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'the service role has full table access (Supabase''s default grant), unlike anon/authenticated'
);

select * from finish();
rollback;
