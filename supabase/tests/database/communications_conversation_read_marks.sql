-- Communications Part 4 item 5: per-user conversation read marks.
begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

select table_privs_are(
  'public', 'communication_conversation_read_marks', 'anon', array[]::text[],
  'anon has no direct access to conversation read marks'
);
select table_privs_are(
  'public', 'communication_conversation_read_marks', 'authenticated', array[]::text[],
  'authenticated has no direct access to conversation read marks -- the API route uses the service role'
);
select table_privs_are(
  'public', 'communication_conversation_read_marks', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'the service role has full table access (Supabase''s default grant), unlike anon/authenticated'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('dc100000-0000-0000-0000-000000000001', 'Read Marks Test', 'read-marks-test', 'active'),
  ('dc100000-0000-0000-0000-000000000002', 'Other Org', 'read-marks-other-org', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  'dc000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'read-marks-actor@example.test', 'test', now(), now(), now()
);

insert into public.clients (id, organization_id, display_name)
values
  ('dc200000-0000-0000-0000-000000000001', 'dc100000-0000-0000-0000-000000000001', 'Read Marks Client'),
  ('dc200000-0000-0000-0000-000000000002', 'dc100000-0000-0000-0000-000000000002', 'Other Org Client');

set local role service_role;

select lives_ok(
  $$insert into public.communication_conversation_read_marks
    (organization_id, user_id, client_id, last_read_at) values (
      'dc100000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
      'dc200000-0000-0000-0000-000000000001', now()
    )$$,
  'the service role can record a read mark for a client in the same organization'
);

select throws_ok(
  $$insert into public.communication_conversation_read_marks
    (organization_id, user_id, client_id, last_read_at) values (
      'dc100000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
      'dc200000-0000-0000-0000-000000000002', now()
    )$$,
  '23503', null,
  'a client from another organization cannot be pinned to this organization''s read mark'
);

select throws_ok(
  $$insert into public.communication_conversation_read_marks
    (organization_id, user_id, client_id, last_read_at) values (
      'dc100000-0000-0000-0000-000000000001', 'dc000000-0000-0000-0000-000000000001',
      'dc200000-0000-0000-0000-000000000001', now()
    )$$,
  '23505', null,
  'one user has at most one read mark per client conversation'
);

-- now() is transaction-stable, so within this single test transaction an update cannot be shown to
-- advance updated_at past created_at -- assert the shared trigger is wired instead of its timing effect,
-- which is already covered where public.set_updated_at() itself was introduced.
select ok(
  exists(
    select 1 from pg_trigger
    where tgrelid = 'public.communication_conversation_read_marks'::regclass
    and tgname = 'communication_conversation_read_marks_set_updated_at'
  ),
  'the shared set_updated_at trigger is wired on this table'
);

delete from public.clients where id = 'dc200000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.communication_conversation_read_marks
    where client_id = 'dc200000-0000-0000-0000-000000000001'),
  0,
  'deleting the client cascades to remove its read marks'
);

reset role;
select * from finish();
rollback;
