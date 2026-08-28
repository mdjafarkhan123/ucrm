-- Communications Part 4 item 4: inbound-message resolution and the attachment import claim/finalize queue.
begin;

create extension if not exists pgtap with schema extensions;
select plan(38);

select function_privs_are(
  'public', 'record_communication_inbound_message',
  array['text', 'text', 'uuid', 'text', 'text', 'jsonb', 'jsonb', 'text', 'text', 'text', 'text', 'jsonb'],
  'service_role', array['EXECUTE'], 'only the service worker can record an inbound message'
);
select function_privs_are(
  'public', 'claim_communication_inbound_attachment_imports', array['integer'],
  'service_role', array['EXECUTE'], 'only the service worker can claim inbound attachment imports'
);
select function_privs_are(
  'public', 'finalize_communication_inbound_attachment_import',
  array['uuid', 'uuid', 'text', 'text', 'text'],
  'service_role', array['EXECUTE'], 'only the service worker can finalize an inbound attachment import'
);
select throws_ok(
  $$set local role authenticated; select public.record_communication_inbound_message(
    'x', null, null, 'a@example.test', 'A', '[]'::jsonb, '[]'::jsonb, 'S', 'h', 't', 'reply', '[]'::jsonb
  )$$,
  '42501', null, 'authenticated callers cannot record an inbound message'
);
reset role;
select throws_ok(
  $$set local role anon; select public.claim_communication_inbound_attachment_imports()$$,
  '42501', null, 'anonymous callers cannot claim inbound attachment imports'
);
reset role;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('db100000-0000-0000-0000-000000000001', 'Ingestion Test', 'ingestion-test', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'db000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ingest-actor@example.test', 'test', now(), now(), now()
);
insert into public.organization_members (organization_id, user_id, role, status)
values ('db100000-0000-0000-0000-000000000001', 'db000000-0000-0000-0000-000000000001', 'admin', 'active');

insert into public.clients (id, organization_id, display_name)
values ('db200000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001', 'Ingestion Client');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('db300000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001',
  'db200000-0000-0000-0000-000000000001', 'email', 'customer@ingest-test.example', true);
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('db300000-0000-0000-0000-000000000002', 'db100000-0000-0000-0000-000000000001',
  'db200000-0000-0000-0000-000000000001', 'email', 'customer-secondary@ingest-test.example', false);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, spf_status
) values (
  'db400000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001',
  'sending', 'mail.ingest-test.example', 'verified', true, true, 'passing', 'passing', 'passing'
);
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, dmarc_status, spf_status, inbound_mx_status
) values (
  'db400000-0000-0000-0000-000000000002', 'db100000-0000-0000-0000-000000000001',
  'receiving', 'reply.ingest-test.example', 'verified', true, false, 'passing', 'unchecked', 'unchecked',
  'unchecked', 'passing'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values (
  'db500000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001',
  'db400000-0000-0000-0000-000000000001', 'hello@mail.ingest-test.example', 'Ingest Sender', 'enabled',
  true, true, true
);

insert into public.communication_reply_aliases (
  id, organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id, alias_local_part
) values (
  'db600000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001',
  'db400000-0000-0000-0000-000000000002', 'db500000-0000-0000-0000-000000000001',
  'db200000-0000-0000-0000-000000000001', 'db300000-0000-0000-0000-000000000001', 'convo-alias-001'
);
insert into public.communication_reply_aliases (
  id, organization_id, receiving_domain_id, sender_id, client_id, client_contact_method_id, alias_local_part,
  expires_at
) values (
  'db600000-0000-0000-0000-000000000002', 'db100000-0000-0000-0000-000000000001',
  'db400000-0000-0000-0000-000000000002', 'db500000-0000-0000-0000-000000000001',
  'db200000-0000-0000-0000-000000000001', 'db300000-0000-0000-0000-000000000002', 'convo-alias-expired',
  now() - interval '1 day'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email,
  subject, html_content, text_content, provider_message_id, status, accepted_at
) values (
  'db700000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001',
  'db200000-0000-0000-0000-000000000001', 'db300000-0000-0000-0000-000000000001',
  'ingest-original-send', 'customer@ingest-test.example', 'Original subject', '<p>x</p>', 'x',
  'outbound-msg-1', 'submitted', now()
);

-- No recipient addresses one of our own receiving domains: pure noise, not a product case.
select is(
  public.record_communication_inbound_message(
    'msg-no-domain-1', null, null, 'someone@example.test', 'Someone', '[]'::jsonb, '[]'::jsonb,
    'No domain match', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'foo@unrelated.example', 'local_part', 'foo', 'domain_name', 'unrelated.example'
    ))
  ),
  null::public.communication_inbound_messages, 'an unmatched receiving domain resolves to no message row'
);
select is(
  (select count(*)::integer from public.communication_inbound_messages
    where provider_message_id = 'msg-no-domain-1'),
  0, 'no row was inserted for an unmatched domain'
);

select is(
  (public.record_communication_inbound_message(
    'msg-unknown-1', null, null, 'stranger@example.test', 'Stranger', '[]'::jsonb, '[]'::jsonb,
    'Unknown sender test', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'nonexistent@reply.ingest-test.example', 'local_part', 'nonexistent',
      'domain_name', 'reply.ingest-test.example'
    ))
  )).review_status,
  'pending_review', 'a reply to an alias local part that does not exist enters review'
);
select is(
  (select review_reason from public.communication_inbound_messages where provider_message_id = 'msg-unknown-1'),
  'unknown_sender', 'the unknown-alias review carries the unknown_sender reason'
);

select is(
  (public.record_communication_inbound_message(
    'msg-expired-1', null, null, 'customer@ingest-test.example', 'Customer', '[]'::jsonb, '[]'::jsonb,
    'Expired alias test', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'convo-alias-expired@reply.ingest-test.example', 'local_part', 'convo-alias-expired',
      'domain_name', 'reply.ingest-test.example'
    ))
  )).review_reason,
  'expired_alias', 'a reply to an alias past its retention window enters review with the expired reason'
);

select is(
  (public.record_communication_inbound_message(
    'msg-ambiguous-1', null, null, 'not-the-customer@example.test', 'Not The Customer', '[]'::jsonb,
    '[]'::jsonb, 'Ambiguous sender test', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'convo-alias-001@reply.ingest-test.example', 'local_part', 'convo-alias-001',
      'domain_name', 'reply.ingest-test.example'
    ))
  )).review_reason,
  'ambiguous_sender',
  'a valid alias replied to by an address that is not the conversation''s customer enters review'
);

select is(
  (public.record_communication_inbound_message(
    'msg-accepted-1', 'outbound-msg-1', null, 'customer@ingest-test.example', 'Customer', '[]'::jsonb,
    '[]'::jsonb, 'Loop test subject', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'convo-alias-001@reply.ingest-test.example', 'local_part', 'convo-alias-001',
      'domain_name', 'reply.ingest-test.example'
    ))
  )).review_status,
  'accepted', 'the conversation''s own customer replying through a live alias is fully resolved'
);
select is(
  (select client_id from public.communication_inbound_messages where provider_message_id = 'msg-accepted-1'),
  'db200000-0000-0000-0000-000000000001', 'an accepted message resolves the correct client'
);
select is(
  (select client_contact_method_id from public.communication_inbound_messages
    where provider_message_id = 'msg-accepted-1'),
  'db300000-0000-0000-0000-000000000001', 'an accepted message resolves the correct contact method'
);
select is(
  (select sender_id from public.communication_inbound_messages where provider_message_id = 'msg-accepted-1'),
  'db500000-0000-0000-0000-000000000001', 'an accepted message resolves the sender that owns the alias'
);
select is(
  (select reply_alias_id from public.communication_inbound_messages where provider_message_id = 'msg-accepted-1'),
  'db600000-0000-0000-0000-000000000001', 'an accepted message records which alias correlated it'
);
select is(
  (select automation_suppressed from public.communication_inbound_messages
    where provider_message_id = 'msg-accepted-1'),
  false, 'an accepted ordinary reply does not suppress automation'
);
select is(
  (select in_reply_to_intent_id from public.communication_inbound_messages
    where provider_message_id = 'msg-accepted-1'),
  'db700000-0000-0000-0000-000000000001',
  'a known outbound provider message id in In-Reply-To resolves back to its delivery intent'
);

select is(
  public.record_communication_inbound_message(
    'msg-accepted-1', null, null, 'customer@ingest-test.example', 'Customer', '[]'::jsonb, '[]'::jsonb,
    'Duplicate', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'convo-alias-001@reply.ingest-test.example', 'local_part', 'convo-alias-001',
      'domain_name', 'reply.ingest-test.example'
    ))
  ),
  null::public.communication_inbound_messages, 'a duplicate provider message id is a no-op, not a second row'
);
select is(
  (select count(*)::integer from public.communication_inbound_messages
    where provider_message_id = 'msg-accepted-1'),
  1, 'only one row exists for the duplicated provider message id'
);

-- Loop detection: the same sender+subject pair recurring three times inside ten minutes overrides the
-- fourth occurrence's message_kind, regardless of the caller's own classification.
select public.record_communication_inbound_message(
  'msg-loop-2', null, null, 'customer@ingest-test.example', 'Customer', '[]'::jsonb, '[]'::jsonb,
  'Loop test subject', '<p>x</p>', 'x', 'reply',
  jsonb_build_array(jsonb_build_object(
    'address', 'convo-alias-001@reply.ingest-test.example', 'local_part', 'convo-alias-001',
    'domain_name', 'reply.ingest-test.example'
  ))
);
select public.record_communication_inbound_message(
  'msg-loop-3', null, null, 'customer@ingest-test.example', 'Customer', '[]'::jsonb, '[]'::jsonb,
  'Loop test subject', '<p>x</p>', 'x', 'reply',
  jsonb_build_array(jsonb_build_object(
    'address', 'convo-alias-001@reply.ingest-test.example', 'local_part', 'convo-alias-001',
    'domain_name', 'reply.ingest-test.example'
  ))
);
select is(
  (public.record_communication_inbound_message(
    'msg-loop-4', null, null, 'customer@ingest-test.example', 'Customer', '[]'::jsonb, '[]'::jsonb,
    'Loop test subject', '<p>x</p>', 'x', 'reply',
    jsonb_build_array(jsonb_build_object(
      'address', 'convo-alias-001@reply.ingest-test.example', 'local_part', 'convo-alias-001',
      'domain_name', 'reply.ingest-test.example'
    ))
  )).message_kind,
  'loop_detected', 'the same sender and subject recurring a fourth time inside the window is a loop'
);
select is(
  (select automation_suppressed from public.communication_inbound_messages where provider_message_id = 'msg-loop-4'),
  true, 'a loop-detected message suppresses automation even though it was classified as a reply'
);
select isnt(
  (select loop_detected_at from public.communication_inbound_messages where provider_message_id = 'msg-loop-4'),
  null, 'a loop-detected message records when the loop was detected'
);
select is(
  (select message_kind from public.communication_inbound_messages where provider_message_id = 'msg-loop-2'),
  'reply', 'the second occurrence of the same sender and subject is not yet a loop'
);

-- Attachment import claim/finalize queue.
create function pg_temp.ingest_accepted_message_id() returns uuid language sql stable as
  $$select id from public.communication_inbound_messages where provider_message_id = 'msg-accepted-1'$$;

insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size, provider_download_token
) values (
  'db900000-0000-0000-0000-000000000001', 'db100000-0000-0000-0000-000000000001',
  pg_temp.ingest_accepted_message_id(), 'never-claimed.pdf', 'application/pdf', 100, 'token-a'
);
insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size, provider_download_token,
  claimed_at, claim_token
) values (
  'db900000-0000-0000-0000-000000000002', 'db100000-0000-0000-0000-000000000001',
  pg_temp.ingest_accepted_message_id(), 'stale-claim.pdf', 'application/pdf', 100, 'token-b',
  now() - interval '11 minutes', gen_random_uuid()
);
insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size, provider_download_token,
  claimed_at, claim_token
) values (
  'db900000-0000-0000-0000-000000000003', 'db100000-0000-0000-0000-000000000001',
  pg_temp.ingest_accepted_message_id(), 'live-claim.pdf', 'application/pdf', 100, 'token-c',
  now() - interval '5 minutes', gen_random_uuid()
);
insert into public.communication_inbound_attachments (
  id, organization_id, inbound_message_id, file_name, mime_type, byte_size, status
) values (
  'db900000-0000-0000-0000-000000000004', 'db100000-0000-0000-0000-000000000001',
  pg_temp.ingest_accepted_message_id(), 'already-blocked.exe', 'application/octet-stream', 100, 'blocked_type'
);

create temporary table ingest_claims on commit drop as
select * from public.claim_communication_inbound_attachment_imports(10);

select is((select count(*)::integer from ingest_claims), 2,
  'the claim returns only the never-claimed and stale-claimed pending imports');
select ok((select bool_or(id = 'db900000-0000-0000-0000-000000000001') from ingest_claims),
  'the never-claimed attachment is claimed');
select ok((select bool_or(id = 'db900000-0000-0000-0000-000000000002') from ingest_claims),
  'the stale-claimed attachment is reclaimed');
select ok(not (select bool_or(id = 'db900000-0000-0000-0000-000000000003') from ingest_claims),
  'a live claim held by another worker is not reclaimed');
select ok(not (select bool_or(id = 'db900000-0000-0000-0000-000000000004') from ingest_claims),
  'an attachment that already left the pending_import queue is never claimed');

select is(
  (public.finalize_communication_inbound_attachment_import(
    'db900000-0000-0000-0000-000000000001', gen_random_uuid(), 'pending_scan', 'some/object/key', null
  )).status,
  'pending_import', 'a stale or foreign claim token is a no-op that returns the current state'
);

select is(
  (public.finalize_communication_inbound_attachment_import(
    'db900000-0000-0000-0000-000000000001',
    (select claim_token from ingest_claims where id = 'db900000-0000-0000-0000-000000000001'),
    'pending_scan', 'db100000-0000-0000-0000-000000000001/inbound-email-attachments/key', null
  )).status,
  'pending_scan', 'a matching claim token finalizes the import to pending_scan'
);
select is(
  (select object_key from public.communication_inbound_attachments
    where id = 'db900000-0000-0000-0000-000000000001'),
  'db100000-0000-0000-0000-000000000001/inbound-email-attachments/key',
  'a successful finalize records the stored object key'
);
select is(
  (select claim_token from public.communication_inbound_attachments
    where id = 'db900000-0000-0000-0000-000000000001'),
  null, 'a successful finalize clears the claim token'
);
select is(
  (select provider_download_token from public.communication_inbound_attachments
    where id = 'db900000-0000-0000-0000-000000000001'),
  null, 'a successful finalize clears the provider download token'
);

select is(
  (public.finalize_communication_inbound_attachment_import(
    'db900000-0000-0000-0000-000000000002',
    (select claim_token from ingest_claims where id = 'db900000-0000-0000-0000-000000000002'),
    'import_failed', null, 'Brevo rejected the download.'
  )).failure_reason,
  'Brevo rejected the download.', 'a failed import records its failure reason'
);

select throws_ok(
  $$select public.finalize_communication_inbound_attachment_import(
    'db900000-0000-0000-0000-000000000001', gen_random_uuid(), 'available', null, null
  )$$,
  '23514', null, 'finalize rejects a target status outside the worker''s allowed outcomes'
);
select throws_ok(
  $$select public.claim_communication_inbound_attachment_imports(0)$$,
  '23514', null, 'a batch size of zero is outside the safe claim bounds'
);
select throws_ok(
  $$select public.claim_communication_inbound_attachment_imports(101)$$,
  '23514', null, 'a batch size over one hundred is outside the safe claim bounds'
);

reset role;
select * from finish();
rollback;
