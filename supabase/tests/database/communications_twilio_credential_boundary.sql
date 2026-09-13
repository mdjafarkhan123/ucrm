-- Communications A2 / Stage 2A: Twilio provider identities are safe and credentials remain ciphertext-only.
begin;

create extension if not exists pgtap with schema extensions;
select plan(23);

select has_table('public', 'communication_twilio_accounts',
  'Twilio subaccount identity has an explicit server-owned record');
select has_table('public', 'communication_twilio_credentials',
  'Twilio secrets have a separate encrypted credential record');
select has_index('public', 'communication_twilio_credentials',
  'communication_twilio_credentials_one_lifecycle_key',
  'credential lifecycle lookups and uniqueness use one bounded index');
select hasnt_column('public', 'communication_twilio_accounts', 'auth_token',
  'safe provider account records cannot hold a plaintext Auth Token');
select hasnt_column('public', 'communication_twilio_credentials', 'plaintext',
  'credential records expose no plaintext column');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_twilio_accounts'::regclass),
  'Twilio account records keep row-level security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_twilio_credentials'::regclass),
  'encrypted credential records keep row-level security enabled'
);
select table_privs_are('public', 'communication_twilio_accounts', 'authenticated', array[]::text[],
  'authenticated clients have no direct Twilio account privileges');
select table_privs_are('public', 'communication_twilio_credentials', 'authenticated', array[]::text[],
  'authenticated clients have no direct credential privileges');
select table_privs_are('public', 'communication_twilio_accounts', 'anon', array[]::text[],
  'anonymous clients have no direct Twilio account privileges');
select table_privs_are('public', 'communication_twilio_credentials', 'anon', array[]::text[],
  'anonymous clients have no direct credential privileges');
select table_privs_are('public', 'communication_twilio_credentials', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'only the server role owns credential persistence');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('a2100000-0000-4000-8000-000000000011', 'Twilio Boundary A', 'twilio-boundary-a', 'active'),
  ('a2100000-0000-4000-8000-000000000012', 'Twilio Boundary B', 'twilio-boundary-b', 'active');

select throws_ok(
  $$insert into public.communication_twilio_accounts (organization_id, subaccount_sid)
    values ('a2100000-0000-4000-8000-000000000011', 'not-a-twilio-sid')$$,
  '23514', null,
  'a malformed subaccount SID is rejected'
);

insert into public.communication_twilio_accounts (
  id, organization_id, subaccount_sid, messaging_service_sid
) values
  ('a2200000-0000-4000-8000-000000000011', 'a2100000-0000-4000-8000-000000000011',
   'AC11111111111111111111111111111111', 'MG11111111111111111111111111111111'),
  ('a2200000-0000-4000-8000-000000000012', 'a2100000-0000-4000-8000-000000000012',
   'AC22222222222222222222222222222222', null);

select throws_ok(
  $$insert into public.communication_twilio_accounts (organization_id, subaccount_sid)
    values ('a2100000-0000-4000-8000-000000000011', 'AC33333333333333333333333333333333')$$,
  '23505', null,
  'one organization cannot own two Twilio subaccounts'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000012', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'current', 'v1', decode(repeat('01', 12), 'hex'),
      decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex')
    )$$,
  '23503', null,
  'a credential cannot cross the organization/subaccount boundary'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'restricted_api_key', 'current', 'v1', decode(repeat('01', 12), 'hex'),
      decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex')
    )$$,
  '23514', null,
  'a Restricted API key record requires its safe key SID'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state, credential_sid,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'current', 'SK11111111111111111111111111111111', 'v1',
      decode(repeat('01', 12), 'hex'), decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex')
    )$$,
  '23514', null,
  'an Auth Token record cannot masquerade as an API key'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'current', 'v1', decode(repeat('01', 11), 'hex'),
      decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex')
    )$$,
  '23514', null,
  'AES-GCM credentials require a 96-bit nonce'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'current', 'v1', decode(repeat('01', 12), 'hex'),
      decode('746f6b656e', 'hex'), decode(repeat('02', 15), 'hex')
    )$$,
  '23514', null,
  'AES-GCM credentials require a 128-bit authentication tag'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'prior', 'v1', decode(repeat('01', 12), 'hex'),
      decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex')
    )$$,
  '23514', null,
  'a prior credential must have an explicit retirement time'
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag, retire_after
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'current', 'v1', decode(repeat('01', 12), 'hex'),
      decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex'), now() + interval '1 hour'
    )$$,
  '23514', null,
  'a current credential cannot carry a misleading retirement time'
);

insert into public.communication_twilio_credentials (
  id, organization_id, twilio_account_id, credential_purpose, lifecycle_state,
  encryption_key_id, nonce, ciphertext, authentication_tag
) values (
  'a2300000-0000-4000-8000-000000000011', 'a2100000-0000-4000-8000-000000000011',
  'a2200000-0000-4000-8000-000000000011', 'auth_token', 'current', 'v1',
  decode(repeat('01', 12), 'hex'), decode('746f6b656e', 'hex'), decode(repeat('02', 16), 'hex')
);

select throws_ok(
  $$insert into public.communication_twilio_credentials (
      organization_id, twilio_account_id, credential_purpose, lifecycle_state,
      encryption_key_id, nonce, ciphertext, authentication_tag
    ) values (
      'a2100000-0000-4000-8000-000000000011', 'a2200000-0000-4000-8000-000000000011',
      'auth_token', 'current', 'v2', decode(repeat('03', 12), 'hex'),
      decode('6e6577', 'hex'), decode(repeat('04', 16), 'hex')
    )$$,
  '23505', null,
  'one subaccount cannot have two current Auth Tokens'
);

select is(
  (select count(*)::integer from public.communication_twilio_credentials
   where organization_id = 'a2100000-0000-4000-8000-000000000011'),
  1,
  'the valid ciphertext-only credential remains stored'
);

select * from finish();
rollback;
