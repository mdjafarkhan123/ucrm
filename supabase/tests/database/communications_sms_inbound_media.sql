-- Communications Stage 6D-1: inbound MMS media -- the provider column and byte-size-on-finalize.
begin;

create extension if not exists pgtap with schema extensions;
select plan(9);

select function_privs_are(
  'public', 'finalize_communication_inbound_attachment_import',
  array['uuid', 'uuid', 'text', 'text', 'text', 'bigint'],
  'service_role', array['EXECUTE'],
  'only the service worker can finalize an inbound attachment import with its real byte size'
);
select function_privs_are(
  'public', 'finalize_communication_inbound_attachment_import',
  array['uuid', 'uuid', 'text', 'text', 'text', 'bigint'],
  'authenticated', array[]::text[],
  'authenticated cannot finalize an inbound attachment import'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values ('ec100000-0000-0000-0000-000000000001', 'Inbound Media Test', 'inbound-media-test', 'active');

insert into public.communication_inbound_messages (
  id, organization_id, sender_email, subject, text_content
) values (
  'ec200000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
  'customer@example.test', 'Photo attached', 'see attached'
);

set local role service_role;

select lives_ok(
  $$insert into public.communication_inbound_attachments
    (id, organization_id, inbound_message_id, file_name, mime_type, byte_size, status)
    values (
      'ec300000-0000-0000-0000-000000000001', 'ec100000-0000-0000-0000-000000000001',
      'ec200000-0000-0000-0000-000000000001', 'estimate.pdf', 'application/pdf', 1024, 'pending_import'
    )$$,
  'an attachment with no provider still inserts'
);
select is(
  (select provider from public.communication_inbound_attachments
    where id = 'ec300000-0000-0000-0000-000000000001'),
  'ses', 'the default provider is ses, the only email provider'
);

select lives_ok(
  $$insert into public.communication_inbound_attachments
    (id, organization_id, inbound_message_id, file_name, mime_type, byte_size, status, provider,
     provider_download_token)
    values (
      'ec300000-0000-0000-0000-000000000002', 'ec100000-0000-0000-0000-000000000001',
      'ec200000-0000-0000-0000-000000000001', 'mms-1.jpg', 'image/jpeg', 0, 'pending_import', 'twilio',
      'https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1'
    )$$,
  'a twilio MMS attachment records byte_size 0 until download -- the real size is unknown upfront'
);

select throws_ok(
  $$insert into public.communication_inbound_attachments
    (organization_id, inbound_message_id, file_name, mime_type, byte_size, status, provider)
    values (
      'ec100000-0000-0000-0000-000000000001', 'ec200000-0000-0000-0000-000000000001',
      'x.jpg', 'image/jpeg', 0, 'pending_import', 'other_provider'
    )$$,
  '23514', null, 'a provider outside ses/twilio is rejected'
);

create temporary table media_claims on commit drop as
select * from public.claim_communication_inbound_attachment_imports(10);

select is((select count(*)::integer from media_claims), 2, 'both attachments are claimed');

select is(
  (public.finalize_communication_inbound_attachment_import(
    'ec300000-0000-0000-0000-000000000002',
    (select claim_token from media_claims where id = 'ec300000-0000-0000-0000-000000000002'),
    'pending_scan', 'ec100000-0000-0000-0000-000000000001/inbound-sms-attachments/key', null, 204800
  )).byte_size,
  204800::bigint, 'finalize records the real downloaded byte size for an MMS attachment'
);

select is(
  (public.finalize_communication_inbound_attachment_import(
    'ec300000-0000-0000-0000-000000000001',
    (select claim_token from media_claims where id = 'ec300000-0000-0000-0000-000000000001'),
    'pending_scan', 'ec100000-0000-0000-0000-000000000001/inbound-email-attachments/key', null
  )).byte_size,
  1024::bigint, 'omitting target_byte_size leaves an email attachment''s already-known size unchanged'
);

reset role;
select * from finish();
rollback;
