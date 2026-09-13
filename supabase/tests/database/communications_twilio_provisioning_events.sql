-- Communications A2 / Stage 2B: provisioning history is server-only, append-only, and secret-free.
begin;

create extension if not exists pgtap with schema extensions;
select plan(13);

select has_table('public', 'communication_twilio_provisioning_events',
  'Twilio provisioning steps have an explicit history record');
select hasnt_column('public', 'communication_twilio_provisioning_events', 'auth_token',
  'provisioning history cannot hold a plaintext Auth Token');
select hasnt_column('public', 'communication_twilio_provisioning_events', 'secret',
  'provisioning history cannot hold an API-key secret');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.communication_twilio_provisioning_events'::regclass),
  'provisioning history keeps row-level security enabled'
);
select table_privs_are('public', 'communication_twilio_provisioning_events', 'authenticated',
  array[]::text[], 'authenticated clients have no direct history privileges');
select table_privs_are('public', 'communication_twilio_provisioning_events', 'anon',
  array[]::text[], 'anonymous clients have no direct history privileges');
select table_privs_are('public', 'communication_twilio_provisioning_events', 'service_role',
  array['SELECT', 'INSERT'],
  'the server can append and read history but never rewrite it');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('a2400000-0000-4000-8000-000000000011', 'Twilio Provisioning A', 'twilio-provisioning-a', 'active');

insert into public.communication_twilio_accounts (
  id, organization_id, subaccount_sid
) values (
  'a2500000-0000-4000-8000-000000000011', 'a2400000-0000-4000-8000-000000000011',
  'AC44444444444444444444444444444444'
);

-- A subaccount-creation failure before the account row exists is recorded with a null account link.
insert into public.communication_twilio_provisioning_events (
  organization_id, twilio_account_id, operation, step, result, detail
) values (
  'a2400000-0000-4000-8000-000000000011', null, 'provision', 'subaccount_created', 'needs_review',
  '{"reason": "orphan_subaccount_found"}'::jsonb
);

insert into public.communication_twilio_provisioning_events (
  organization_id, twilio_account_id, operation, step, result, detail
) values (
  'a2400000-0000-4000-8000-000000000011', 'a2500000-0000-4000-8000-000000000011',
  'provision', 'restricted_key_created', 'succeeded', '{"key_sid": "SK44444444444444444444444444444444"}'::jsonb
);

select throws_ok(
  $$insert into public.communication_twilio_provisioning_events (
      organization_id, operation, step, result
    ) values (
      'a2400000-0000-4000-8000-000000000011', 'not_a_known_operation', 'subaccount_created', 'succeeded'
    )$$,
  '23514', null,
  'an unknown operation is rejected'
);

select throws_ok(
  $$insert into public.communication_twilio_provisioning_events (
      organization_id, operation, step, result
    ) values (
      'a2400000-0000-4000-8000-000000000011', 'provision', 'subaccount_created', 'in_progress'
    )$$,
  '23514', null,
  'an unknown result is rejected'
);

select throws_ok(
  $$insert into public.communication_twilio_provisioning_events (
      organization_id, operation, step, result, detail
    ) values (
      'a2400000-0000-4000-8000-000000000011', 'provision', 'subaccount_created', 'succeeded',
      '"a string, not an object"'::jsonb
    )$$,
  '23514', null,
  'sanitized detail must be a JSON object'
);

select is(
  (select count(*)::integer from public.communication_twilio_provisioning_events
   where organization_id = 'a2400000-0000-4000-8000-000000000011'),
  2,
  'both recorded provisioning events remain stored'
);

select is(
  (select twilio_account_id from public.communication_twilio_provisioning_events
   where organization_id = 'a2400000-0000-4000-8000-000000000011' and step = 'subaccount_created'),
  null,
  'a pre-account failure keeps a null account link'
);

select * from finish();
rollback;
