-- Communications Part 5 (5E-iii continued): enqueue_manual_communication_email's new, additive
-- target_attachments parameter -- the same paperclip on the manual/New-conversation send path as the
-- reply composer already has (20260825170000_communications_outbound_attachments.sql).
begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

select function_privs_are(
  'public', 'enqueue_manual_communication_email',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'jsonb'], 'anon', array[]::text[],
  'anon cannot call the attachment-aware manual send command'
);
select function_privs_are(
  'public', 'enqueue_manual_communication_email',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'jsonb'], 'authenticated', array[]::text[],
  'authenticated cannot call the attachment-aware manual send command directly -- the API route uses the service role'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values ('eb100000-0000-0000-0000-000000000001', 'Manual Files Test', 'manual-files-test', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'eb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'manual-files-actor@example.test', 'test', now(), now(), now()
);
insert into public.organization_members (organization_id, user_id, role, status)
values ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'admin', 'active');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'conversations.send', 'grant'),
  ('eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001', 'customers.view', 'grant');

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at)
values ('eb100000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');
select public.apply_organization_limit_exception(
  'eb100000-0000-0000-0000-000000000001', 'operational_email_recipients', 'numeric', 5,
  now() - interval '1 minute', null, 'manual-files-operational-capacity', 'Manual files test capacity.',
  'owner@example.test'
);

insert into public.clients (id, organization_id, display_name)
values ('eb200000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001', 'Manual Files Client');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('eb300000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001',
  'eb200000-0000-0000-0000-000000000001', 'email', 'customer@manual-files-test.example', true);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_verified, provider_authenticated,
  ownership_status, dkim_status, spf_status
) values (
  'eb400000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001',
  'sending', 'mail.manual-files-test.example', 'verified', true, true, 'passing', 'passing', 'pending'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated, assigned_user_id
) values (
  'eb500000-0000-0000-0000-000000000001', 'eb100000-0000-0000-0000-000000000001',
  'eb400000-0000-0000-0000-000000000001', 'hello@mail.manual-files-test.example', 'Manual Files Sender',
  'enabled', true, true, true, 'eb000000-0000-0000-0000-000000000001'
);

select set_config('request.jwt.claim.sub', 'eb000000-0000-0000-0000-000000000001', true);

select is(
  (public.enqueue_manual_communication_email(
    'eb100000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
    'eb200000-0000-0000-0000-000000000001', 'eb300000-0000-0000-0000-000000000001',
    'manual-files-send', 'With a file', '<p>see attached</p>', 'see attached',
    '[{"file_name": "quote.pdf", "mime_type": "application/pdf", "byte_size": 1024,
       "object_key": "eb100000-0000-0000-0000-000000000001/outbound-email-attachments/i/quote.pdf"}]'::jsonb
  )).status,
  'queued',
  'a manual send with an attachment still queues the intent, exactly like one without'
);

select is(
  (select file_name from public.communication_outbound_attachments
    where organization_id = 'eb100000-0000-0000-0000-000000000001'),
  'quote.pdf',
  'the manual command attaches the file inside the same call, via the shared private helper'
);

select * from finish();
rollback;
