-- Communications Part 5: outbound email attachments (the composer's paperclip).
begin;

create extension if not exists pgtap with schema extensions;
select plan(19);

select table_privs_are(
  'public', 'communication_outbound_attachments', 'anon', array[]::text[],
  'anon has no direct access to outbound attachments'
);
select table_privs_are(
  'public', 'communication_outbound_attachments', 'authenticated', array[]::text[],
  'authenticated has no direct access to outbound attachments -- the API route uses the service role'
);
select function_privs_are(
  'public', 'list_communication_outbound_attachments', array['uuid'], 'authenticated', array[]::text[],
  'authenticated cannot list outbound attachment object keys over PostgREST'
);
select function_privs_are(
  'public', 'enqueue_conversation_reply_email',
  array['uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'jsonb'], 'anon', array[]::text[],
  'anon cannot call the attachment-aware reply command'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('ea100000-0000-0000-0000-000000000001', 'Outbound Files Test', 'outbound-files-test', 'active'),
  ('ea100000-0000-0000-0000-000000000002', 'Other Org', 'outbound-files-other', 'active');

insert into public.clients (id, organization_id, display_name)
values
  ('ea200000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-000000000001', 'Files Client'),
  ('ea200000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-000000000002', 'Other Org Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('ea300000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-000000000001',
    'ea200000-0000-0000-0000-000000000001', 'email', 'files@example.test', true),
  ('ea300000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-000000000002',
    'ea200000-0000-0000-0000-000000000002', 'email', 'other@example.test', true);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
) values
  ('ea400000-0000-0000-0000-000000000001', 'ea100000-0000-0000-0000-000000000001',
    'ea200000-0000-0000-0000-000000000001', 'ea300000-0000-0000-0000-000000000001',
    'outbound-files-1', 'files@example.test', 'With files', '<p>hi</p>', 'hi'),
  ('ea400000-0000-0000-0000-000000000002', 'ea100000-0000-0000-0000-000000000002',
    'ea200000-0000-0000-0000-000000000002', 'ea300000-0000-0000-0000-000000000002',
    'outbound-files-2', 'other@example.test', 'Other org', '<p>hi</p>', 'hi');

set local role service_role;

select lives_ok(
  $$insert into public.communication_outbound_attachments
    (organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key) values (
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      'quote.pdf', 'application/pdf', 1024,
      'ea100000-0000-0000-0000-000000000001/outbound-email-attachments/ea400000-0000-0000-0000-000000000001/a-quote.pdf'
    )$$,
  'a file can be attached to a delivery intent in the same organization'
);

select throws_ok(
  $$insert into public.communication_outbound_attachments
    (organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key) values (
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000002',
      'leak.pdf', 'application/pdf', 1024, 'x/outbound-email-attachments/y/leak.pdf'
    )$$,
  '23503', null,
  'another organization''s delivery intent cannot be attached to this organization'
);

select throws_ok(
  $$insert into public.communication_outbound_attachments
    (organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key) values (
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      'quote.pdf', 'application/pdf', 1024,
      'ea100000-0000-0000-0000-000000000001/outbound-email-attachments/ea400000-0000-0000-0000-000000000001/a-quote.pdf'
    )$$,
  '23505', null,
  'the same stored object cannot be attached to one message twice'
);

select throws_ok(
  $$insert into public.communication_outbound_attachments
    (organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key) values (
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      'empty.pdf', 'application/pdf', 0, 'ea100000-0000-0000-0000-000000000001/outbound-email-attachments/z/empty.pdf'
    )$$,
  '23514', null,
  'a zero-byte attachment is rejected -- nothing actually landed in storage'
);

reset role;

-- The command the reply enqueue calls. It is private, so only the owner role reaches it here; the point
-- of these checks is the caps and the tenant prefix guard, not who may call it.
select lives_ok(
  $$select private.attach_communication_outbound_files(
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      '[{"file_name": "plan.pdf", "mime_type": "application/pdf", "byte_size": 2048,
         "object_key": "ea100000-0000-0000-0000-000000000001/outbound-email-attachments/i/plan.pdf"}]'::jsonb
    )$$,
  'the attach command stores a file for its own organization'
);

select is(
  (select count(*)::integer from public.communication_outbound_attachments
    where delivery_intent_id = 'ea400000-0000-0000-0000-000000000001'),
  2,
  'the attach command added its file alongside the directly inserted one'
);

-- Re-sending the same logical_send_key returns the same intent and calls this command again with the
-- same files; it must not duplicate them.
select lives_ok(
  $$select private.attach_communication_outbound_files(
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      '[{"file_name": "plan.pdf", "mime_type": "application/pdf", "byte_size": 2048,
         "object_key": "ea100000-0000-0000-0000-000000000001/outbound-email-attachments/i/plan.pdf"}]'::jsonb
    )$$,
  'attaching the same stored file again is accepted'
);

select is(
  (select count(*)::integer from public.communication_outbound_attachments
    where delivery_intent_id = 'ea400000-0000-0000-0000-000000000001'),
  2,
  'attaching the same stored file again does not duplicate it'
);

select throws_ok(
  $$select private.attach_communication_outbound_files(
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      '[{"file_name": "big.pdf", "mime_type": "application/pdf", "byte_size": 20971521,
         "object_key": "ea100000-0000-0000-0000-000000000001/outbound-email-attachments/i/big.pdf"}]'::jsonb
    )$$,
  '23514', 'Attachments must total 20 MB or less.',
  'the 20 MB per-message total matches the inbound cap'
);

select throws_ok(
  $$select private.attach_communication_outbound_files(
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      (select jsonb_agg(jsonb_build_object(
        'file_name', 'f' || generation || '.pdf', 'mime_type', 'application/pdf', 'byte_size', 10,
        'object_key', 'ea100000-0000-0000-0000-000000000001/outbound-email-attachments/i/f' || generation || '.pdf'
      )) from generate_series(1, 11) as generation)
    )$$,
  '23514', 'Attach at most 10 files to one email.',
  'at most ten files may ride on one email'
);

select throws_ok(
  $$select private.attach_communication_outbound_files(
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001',
      '[{"file_name": "stolen.pdf", "mime_type": "application/pdf", "byte_size": 10,
         "object_key": "ea100000-0000-0000-0000-000000000002/outbound-email-attachments/i/stolen.pdf"}]'::jsonb
    )$$,
  '23514', 'That file does not belong to this business.',
  'a stored object belonging to another organization cannot be attached'
);

select lives_ok(
  $$select private.attach_communication_outbound_files(
      'ea100000-0000-0000-0000-000000000001', 'ea400000-0000-0000-0000-000000000001', '[]'::jsonb
    )$$,
  'a message with no files is an ordinary no-op'
);

select results_eq(
  $$select file_name from public.list_communication_outbound_attachments('ea400000-0000-0000-0000-000000000001')$$,
  $$values ('quote.pdf'::text), ('plan.pdf'::text)$$,
  'the worker reads a claimed message''s files in the order they were attached'
);

-- Nothing deletes a delivery intent today, but the organization-purge path eventually will, and an
-- orphaned attachment row would point at a storage object no message can explain.
select lives_ok(
  $$delete from public.communication_delivery_intents where id = 'ea400000-0000-0000-0000-000000000001'$$,
  'a delivery intent can be deleted while it still has attachments'
);

select is(
  (select count(*)::integer from public.communication_outbound_attachments
    where delivery_intent_id = 'ea400000-0000-0000-0000-000000000001'),
  0,
  'deleting the message takes its attachment rows with it'
);

select * from finish();
rollback;
