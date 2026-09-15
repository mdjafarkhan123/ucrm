-- Communications A2 / Stage 9A: the Twilio Trust Hub submission ledger is server-only, and neither table can
-- hold a raw provider response body or a secret.
begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

select has_table('public', 'communication_sms_trust_hub_resources',
  'each Twilio Trust Hub object created for a registration has a current-state record');
select has_table('public', 'communication_sms_trust_hub_events',
  'the Trust Hub submission saga has an explicit step history');
select hasnt_column('public', 'communication_sms_trust_hub_resources', 'raw_response',
  'the resource ledger cannot hold a raw provider response body');
select hasnt_column('public', 'communication_sms_trust_hub_events', 'auth_token',
  'submission history cannot hold a plaintext Auth Token');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_trust_hub_resources'::regclass),
  'the resource ledger keeps row-level security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_trust_hub_events'::regclass),
  'submission history keeps row-level security enabled'
);

select table_privs_are('public', 'communication_sms_trust_hub_resources', 'authenticated',
  array[]::text[], 'authenticated clients have no direct resource-ledger privileges');
select table_privs_are('public', 'communication_sms_trust_hub_resources', 'anon',
  array[]::text[], 'anonymous clients have no direct resource-ledger privileges');
select table_privs_are('public', 'communication_sms_trust_hub_resources', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE'],
  'the saga can create and update resource state but never delete it, and never through a client role');
select table_privs_are('public', 'communication_sms_trust_hub_events', 'service_role',
  array['SELECT', 'INSERT'],
  'the saga can append and read history but never rewrite it');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('a2600000-0000-4000-8000-000000000011', 'Trust Hub Ledger Org', 'trust-hub-ledger-org', 'active');

insert into public.communication_sms_registrations (
  id, organization_id, country_code, sender_type, use_case, status
) values (
  'a2700000-0000-4000-8000-000000000011', 'a2600000-0000-4000-8000-000000000011',
  'US', 'long_code', 'Customer service messaging', 'waiting_for_info'
);

insert into public.communication_sms_trust_hub_resources (
  organization_id, registration_id, resource_role, status
) values (
  'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011',
  'customer_profile', 'pending'
);

-- A resubmission updates the same role's row instead of creating a second one.
update public.communication_sms_trust_hub_resources
set provider_sid = 'BU11111111111111111111111111111111',
    provider_status = 'draft',
    status = 'created'
where registration_id = 'a2700000-0000-4000-8000-000000000011' and resource_role = 'customer_profile';

select throws_ok(
  $$insert into public.communication_sms_trust_hub_resources (
      organization_id, registration_id, resource_role
    ) values (
      'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011', 'customer_profile'
    )$$,
  '23505', null,
  'a second row for the same registration and resource role is rejected'
);

select throws_ok(
  $$insert into public.communication_sms_trust_hub_resources (
      organization_id, registration_id, resource_role
    ) values (
      'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011', 'not_a_known_role'
    )$$,
  '23514', null,
  'an unknown resource role is rejected'
);

insert into public.communication_sms_trust_hub_events (
  organization_id, registration_id, resource_role, operation, step, result, detail
) values (
  'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011', 'customer_profile',
  'submit_registration', 'create_customer_profile', 'succeeded',
  '{"provider_sid": "BU11111111111111111111111111111111"}'::jsonb
);

select throws_ok(
  $$insert into public.communication_sms_trust_hub_events (
      organization_id, registration_id, operation, step, result
    ) values (
      'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011',
      'not_a_known_operation', 'create_customer_profile', 'succeeded'
    )$$,
  '23514', null,
  'an unknown operation is rejected'
);

select throws_ok(
  $$insert into public.communication_sms_trust_hub_events (
      organization_id, registration_id, operation, step, result
    ) values (
      'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011',
      'submit_registration', 'create_customer_profile', 'in_progress'
    )$$,
  '23514', null,
  'an unknown result is rejected'
);

select throws_ok(
  $$insert into public.communication_sms_trust_hub_events (
      organization_id, registration_id, operation, step, result, detail
    ) values (
      'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011',
      'submit_registration', 'create_customer_profile', 'succeeded', '"a string, not an object"'::jsonb
    )$$,
  '23514', null,
  'sanitized detail must be a JSON object'
);

select is(
  (select status from public.communication_sms_trust_hub_resources
   where registration_id = 'a2700000-0000-4000-8000-000000000011' and resource_role = 'customer_profile'),
  'created',
  'the resubmission update landed on the single existing row'
);

select is(
  (select count(*)::integer from public.communication_sms_trust_hub_resources
   where registration_id = 'a2700000-0000-4000-8000-000000000011'),
  1,
  'only one resource row exists per registration and role'
);

-- The 8th resource role (Standard A2P Trust Product's mandatory messaging-profile EndUser, added
-- 2026-09-15 after the ISV onboarding guide showed the original 7 roles were one short) is accepted.
insert into public.communication_sms_trust_hub_resources (
  organization_id, registration_id, resource_role, status
) values (
  'a2600000-0000-4000-8000-000000000011', 'a2700000-0000-4000-8000-000000000011',
  'end_user_a2p_messaging_profile', 'pending'
);
select is(
  (select status from public.communication_sms_trust_hub_resources
   where registration_id = 'a2700000-0000-4000-8000-000000000011'
     and resource_role = 'end_user_a2p_messaging_profile'),
  'pending',
  'the A2P messaging-profile EndUser role is a valid resource row'
);

-- Deleting the registration removes its ledger rows; nothing orphaned is left for another registration to see.
delete from public.communication_sms_registrations where id = 'a2700000-0000-4000-8000-000000000011';

select is(
  (select count(*)::integer from public.communication_sms_trust_hub_resources
   where registration_id = 'a2700000-0000-4000-8000-000000000011'),
  0,
  'resource rows are removed when their registration is removed'
);
select is(
  (select count(*)::integer from public.communication_sms_trust_hub_events
   where registration_id = 'a2700000-0000-4000-8000-000000000011'),
  0,
  'event rows are removed when their registration is removed'
);

select * from finish();
rollback;
