-- Communications Part 2: contractor sender commands are atomic, idempotent, and service-role only.
begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sender-admin@example.test', 'test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sender-inactive@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('e2000000-0000-0000-0000-000000000001', 'Sender Test', 'sender-test', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 'field', 'deactivated');

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider_domain_id,
  provider_verified, provider_authenticated, ownership_status, dkim_status, dmarc_status,
  spf_status, inbound_mx_status, verified_at
) values (
  'e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'sending', 'mail.sender-test.example', 'verified', 93001, true, true, 'passing', 'passing',
  'passing', 'pending', 'unchecked', now()
);

select function_privs_are(
  'public', 'begin_communication_email_sender_create',
  array['uuid', 'uuid', 'text', 'text', 'uuid', 'boolean', 'boolean', 'boolean', 'uuid', 'text'],
  'service_role', array['EXECUTE'], 'only service role can begin sender creation'
);
select function_privs_are(
  'public', 'finalize_communication_email_sender_create',
  array['uuid', 'uuid', 'bigint', 'uuid', 'text'],
  'service_role', array['EXECUTE'], 'only service role can finalize sender creation'
);
select function_privs_are(
  'public', 'begin_communication_email_sender_update',
  array['uuid', 'uuid', 'text', 'uuid', 'boolean', 'boolean', 'boolean', 'boolean', 'uuid', 'text'],
  'service_role', array['EXECUTE'], 'only service role can begin sender changes'
);
select function_privs_are(
  'public', 'finalize_communication_email_sender_update',
  array['uuid', 'uuid', 'uuid', 'text'],
  'service_role', array['EXECUTE'], 'only service role can finalize sender changes'
);

select is(
  (public.begin_communication_email_sender_create(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    'alex@mail.sender-test.example', 'Alex | Sender Test',
    'e1000000-0000-0000-0000-000000000001', true, true, false,
    'e1000000-0000-0000-0000-000000000001', 'sender-create-command'
  ) ->> 'replayed')::boolean,
  false,
  'the first create persists a provider claim'
);
select is(
  (public.begin_communication_email_sender_create(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    'alex@mail.sender-test.example', 'Alex | Sender Test',
    'e1000000-0000-0000-0000-000000000001', true, true, false,
    'e1000000-0000-0000-0000-000000000001', 'sender-create-command'
  ) ->> 'replayed')::boolean,
  true,
  'the same create claim replays without another sender row'
);
select is(
  (public.finalize_communication_email_sender_create(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.communication_email_senders where email_address = 'alex@mail.sender-test.example'),
    93002, 'e1000000-0000-0000-0000-000000000001', 'sender-create-command'
  )).lifecycle_state,
  'enabled',
  'provider success enables the claimed sender atomically'
);
select throws_ok(
  $$select public.begin_communication_email_sender_create(
    'e2000000-0000-0000-0000-000000000001',
    'e3000000-0000-0000-0000-000000000001',
    'inactive@mail.sender-test.example', 'Inactive',
    'e1000000-0000-0000-0000-000000000002', false, true, false,
    'e1000000-0000-0000-0000-000000000001', 'sender-inactive-command'
  )$$,
  '23514', 'The assigned sender member must be active.',
  'an inactive member cannot receive an enabled sender claim'
);

select lives_ok(
  $$select public.begin_communication_email_sender_update(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.communication_email_senders where email_address = 'alex@mail.sender-test.example'),
    'Alex Disabled', 'e1000000-0000-0000-0000-000000000001', false, false, true, false,
    'e1000000-0000-0000-0000-000000000001', 'sender-update-command'
  )$$,
  'a disable change is claimed before provider work'
);
select is(
  (public.finalize_communication_email_sender_update(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.communication_email_senders where email_address = 'alex@mail.sender-test.example'),
    'e1000000-0000-0000-0000-000000000001', 'sender-update-command'
  )).lifecycle_state,
  'disabled',
  'the claimed disable and sender settings finalize together'
);

update public.communication_email_domains
set lifecycle_state = 'unhealthy', provider_verified = false
where id = 'e3000000-0000-0000-0000-000000000001';
select throws_ok(
  $$update public.communication_email_senders
    set lifecycle_state = 'enabled'
    where email_address = 'alex@mail.sender-test.example'$$,
  '23514', 'A live sender requires a verified healthy sending domain.',
  'a domain regression blocks sender re-enablement at final write time'
);

select * from finish();
rollback;
