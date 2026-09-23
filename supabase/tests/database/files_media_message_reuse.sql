-- Files and Media, Part 6E: a library File can travel on a message, and "Used in" still works for everyone.
--
--   1. A message may carry the composer's own upload or an available File of the same organization -- never
--      another organization's File, a File in Trash, a File still being checked, or an unknown key.
--   2. file_usage runs for a signed-in member even though message delivery state is server-only; before the
--      fix it failed for every File, linked to a message or not.
--   3. A message's "Used in" row names the email, its client, and opens that client's conversation, and
--      reports the File as already received by the customer.
--   4. The message lookup behind that row reveals nothing to a member who may not view the message.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('b7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'reuse-admin@example.test', 'test', now(), now(), now()),
  ('b7000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'reuse-field@example.test', 'test', now(), now(), now()),
  ('b7000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'reuse-other@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b8000000-0000-0000-0000-000000000001', 'Reuse Co A', 'reuse-co-a', 'active'),
  ('b8000000-0000-0000-0000-000000000002', 'Reuse Co B', 'reuse-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('b8000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('b8000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000002', 'field', 'active'),
  ('b8000000-0000-0000-0000-000000000002', 'b7000000-0000-0000-0000-000000000003', 'admin', 'active');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values ('b9000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'Dana Dale', 'customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('bc000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001',
        'b9000000-0000-0000-0000-000000000001', 'email', 'dana@example.test');

-- A checked photo, one in Trash, one still being checked, and another organization's checked photo.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, processing_state, uploaded_by, scanned_at, checksum_sha256, trashed_at)
values
  ('ba000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'kitchen.png',
   'image/png', 2048, 'b8000000-0000-0000-0000-000000000001/files/kitchen.png',
   'file_manager', 'available', 'b7000000-0000-0000-0000-000000000001', now(), repeat('a', 64), null),
  ('ba000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000001', 'binned.png',
   'image/png', 2048, 'b8000000-0000-0000-0000-000000000001/files/binned.png',
   'file_manager', 'available', 'b7000000-0000-0000-0000-000000000001', now(), repeat('b', 64), now()),
  ('ba000000-0000-0000-0000-000000000003', 'b8000000-0000-0000-0000-000000000001', 'checking.png',
   'image/png', 2048, 'b8000000-0000-0000-0000-000000000001/files/checking.png',
   'file_manager', 'pending', 'b7000000-0000-0000-0000-000000000001', null, null, null),
  ('ba000000-0000-0000-0000-000000000004', 'b8000000-0000-0000-0000-000000000002', 'theirs.png',
   'image/png', 2048, 'b8000000-0000-0000-0000-000000000002/files/theirs.png',
   'file_manager', 'available', 'b7000000-0000-0000-0000-000000000003', now(), repeat('c', 64), null);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key, recipient_email,
  subject, html_content, text_content, send_kind, created_by
) values (
  'bd000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001',
  'b9000000-0000-0000-0000-000000000001', 'bc000000-0000-0000-0000-000000000001', 'email', 'reuse-test-1',
  'dana@example.test', 'Your kitchen photo', '<p>Here it is.</p>', 'Here it is.', 'manual',
  'b7000000-0000-0000-0000-000000000001'
);

-- ---------------------------------------------------------------------------------------------------------
-- 1. What a message may carry
-- ---------------------------------------------------------------------------------------------------------

select ok(
  private.outbound_attachment_key_allowed('b8000000-0000-0000-0000-000000000001',
    'b8000000-0000-0000-0000-000000000001/outbound-email-attachments/x.png', 'outbound-email-attachments'),
  'the composer''s own upload is still accepted');

select ok(
  private.outbound_attachment_key_allowed('b8000000-0000-0000-0000-000000000001',
    'b8000000-0000-0000-0000-000000000001/files/kitchen.png', 'outbound-email-attachments'),
  'an available library File of the same organization is accepted');

select ok(
  not private.outbound_attachment_key_allowed('b8000000-0000-0000-0000-000000000001',
    'b8000000-0000-0000-0000-000000000002/files/theirs.png', 'outbound-email-attachments'),
  'another organization''s File is refused');

select ok(
  not private.outbound_attachment_key_allowed('b8000000-0000-0000-0000-000000000001',
    'b8000000-0000-0000-0000-000000000001/files/binned.png', 'outbound-email-attachments'),
  'a File in Trash is refused');

select ok(
  not private.outbound_attachment_key_allowed('b8000000-0000-0000-0000-000000000001',
    'b8000000-0000-0000-0000-000000000001/files/checking.png', 'outbound-email-attachments'),
  'a File still being checked is refused');

select ok(
  not private.outbound_attachment_key_allowed('b8000000-0000-0000-0000-000000000001',
    'b8000000-0000-0000-0000-000000000001/outbound-sms-attachments/x.png', 'outbound-email-attachments'),
  'the other channel''s upload prefix is refused');

select lives_ok(
  $$select private.attach_communication_outbound_files(
      'b8000000-0000-0000-0000-000000000001', 'bd000000-0000-0000-0000-000000000001',
      '[{"file_name":"kitchen.png","mime_type":"image/png","byte_size":2048,
         "object_key":"b8000000-0000-0000-0000-000000000001/files/kitchen.png"}]'::jsonb)$$,
  'an email can carry a library File');

select throws_ok(
  $$select private.attach_communication_outbound_files(
      'b8000000-0000-0000-0000-000000000001', 'bd000000-0000-0000-0000-000000000001',
      '[{"file_name":"theirs.png","mime_type":"image/png","byte_size":2048,
         "object_key":"b8000000-0000-0000-0000-000000000002/files/theirs.png"}]'::jsonb)$$,
  '23514',
  'That file does not belong to this business.',
  'an email cannot carry another organization''s File');

insert into public.file_links (organization_id, file_id, entity_type, entity_id)
values ('b8000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001', 'message',
        'bd000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------------------------------------
-- 2 and 3. "Used in" as a signed-in admin
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select * from public.file_usage('b8000000-0000-0000-0000-000000000001',
      'ba000000-0000-0000-0000-000000000003', 10, null, null)$$,
  'Used in loads for a File that was never sent in a message');

select results_eq(
  $$select entity_type, title, context, link_type, link_id, protected, customer_received
    from public.file_usage('b8000000-0000-0000-0000-000000000001',
      'ba000000-0000-0000-0000-000000000001', 10, null, null)$$,
  $$values ('message'::text, 'Your kitchen photo'::text, 'Dana Dale'::text, 'message'::text,
            'b9000000-0000-0000-0000-000000000001'::uuid, true, true)$$,
  'a message row names the email and its client, opens the conversation, and counts as received');

-- ---------------------------------------------------------------------------------------------------------
-- 4. The message lookup reveals nothing to someone who may not view the message
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.file_link_message('b8000000-0000-0000-0000-000000000001', 'message',
     'bd000000-0000-0000-0000-000000000001')),
  1,
  'the admin can look the message up');

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.file_link_message('b8000000-0000-0000-0000-000000000001', 'message',
     'bd000000-0000-0000-0000-000000000001')),
  0,
  'a field member without customer access cannot');

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::int from public.file_link_message('b8000000-0000-0000-0000-000000000001', 'message',
     'bd000000-0000-0000-0000-000000000001')),
  0,
  'another organization''s admin cannot');

select is(
  (select count(*)::int from public.file_link_message('b8000000-0000-0000-0000-000000000001', 'quote',
     'bd000000-0000-0000-0000-000000000001')),
  0,
  'a non-message link never reaches the message table');

select * from finish();

rollback;
