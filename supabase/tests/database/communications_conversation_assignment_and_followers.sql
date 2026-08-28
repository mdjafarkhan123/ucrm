-- Communications Part 5B: conversation ownership and followers.
begin;

create extension if not exists pgtap with schema extensions;
select plan(21);

select table_privs_are(
  'public', 'communication_conversation_assignments', 'anon', array[]::text[],
  'anon has no direct access to conversation assignments'
);
select table_privs_are(
  'public', 'communication_conversation_assignments', 'authenticated', array[]::text[],
  'authenticated has no direct access to conversation assignments -- the API route uses the service role'
);
select table_privs_are(
  'public', 'communication_conversation_assignments', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'the service role has full table access (Supabase''s default grant), unlike anon/authenticated'
);
select table_privs_are(
  'public', 'communication_conversation_followers', 'anon', array[]::text[],
  'anon has no direct access to conversation followers'
);
select table_privs_are(
  'public', 'communication_conversation_followers', 'authenticated', array[]::text[],
  'authenticated has no direct access to conversation followers -- the API route uses the service role'
);
select table_privs_are(
  'public', 'communication_conversation_followers', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'the service role has full table access (Supabase''s default grant, independent of the narrower column grants this migration wrote), unlike anon/authenticated'
);

select ok(
  exists(select 1 from public.role_permissions
    where role = 'owner' and permission_key = 'conversations.manage_assignment'),
  'owner is granted conversations.manage_assignment by default'
);
select ok(
  exists(select 1 from public.role_permissions
    where role = 'admin' and permission_key = 'conversations.manage_assignment'),
  'admin is granted conversations.manage_assignment by default'
);
select ok(
  not exists(select 1 from public.role_permissions
    where role = 'sales' and permission_key = 'conversations.manage_assignment'),
  'sales is not granted conversations.manage_assignment by default -- an explicit override is required'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('dd100000-0000-0000-0000-000000000001', 'Assignment Test', 'assignment-test', 'active'),
  ('dd100000-0000-0000-0000-000000000002', 'Other Org', 'assignment-other-org', 'active');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('dd000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'assignment-owner@example.test', 'test', now(), now(), now()),
  ('dd000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'assignment-sales@example.test', 'test', now(), now(), now()),
  ('dd000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'assignment-follower@example.test', 'test', now(), now(), now()),
  ('dd000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'assignment-other-org-member@example.test', 'test', now(), now(), now());

-- Owner and admin have view_team by default, so both are eligible assignees; sales has neither view
-- permission by default, so is not eligible. Following needs only view access, which the second
-- (admin) member already has -- there is no separate follow permission to test.
insert into public.organization_members (organization_id, user_id, role, status)
values
  ('dd100000-0000-0000-0000-000000000001', 'dd000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('dd100000-0000-0000-0000-000000000001', 'dd000000-0000-0000-0000-000000000002', 'sales', 'active'),
  ('dd100000-0000-0000-0000-000000000001', 'dd000000-0000-0000-0000-000000000003', 'admin', 'active'),
  ('dd100000-0000-0000-0000-000000000002', 'dd000000-0000-0000-0000-000000000004', 'owner', 'active');

insert into public.clients (id, organization_id, display_name)
values
  ('dd200000-0000-0000-0000-000000000001', 'dd100000-0000-0000-0000-000000000001', 'Assignment Client'),
  ('dd200000-0000-0000-0000-000000000002', 'dd100000-0000-0000-0000-000000000002', 'Other Org Client');

set local role service_role;

select lives_ok(
  $$insert into public.communication_conversation_assignments
    (organization_id, client_id, assigned_to, assigned_by) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001',
      'dd000000-0000-0000-0000-000000000001', 'dd000000-0000-0000-0000-000000000001'
    )$$,
  'an eligible member (owner role, has conversations.view_team) can be assigned a conversation'
);

select throws_ok(
  $$insert into public.communication_conversation_assignments
    (organization_id, client_id, assigned_to) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000002',
      'dd000000-0000-0000-0000-000000000002'
    )$$,
  '23514', 'That person cannot be assigned conversations.',
  'a member with neither conversations.view_team nor view_assigned cannot be assigned a conversation'
);

select throws_ok(
  $$update public.communication_conversation_assignments
    set assigned_to = 'dd000000-0000-0000-0000-000000000002'
    where client_id = 'dd200000-0000-0000-0000-000000000001'$$,
  '23514', 'That person cannot be assigned conversations.',
  'reassigning to an ineligible member is rejected the same way as the initial assignment'
);

select throws_ok(
  $$insert into public.communication_conversation_assignments
    (organization_id, client_id, assigned_to) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001',
      'dd000000-0000-0000-0000-000000000003'
    )$$,
  '23505', null,
  'a conversation has at most one assignment row -- reassigning is an update, not a second insert'
);

select throws_ok(
  $$insert into public.communication_conversation_assignments
    (organization_id, client_id, assigned_to) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000002',
      'dd000000-0000-0000-0000-000000000001'
    )$$,
  '23503', null,
  'a client from another organization cannot be pinned to this organization''s assignment'
);

-- The eligibility trigger runs before the FK is checked, and member_has_permission requires a matching
-- (organization_id, user_id) membership row, so a non-member of this organization fails eligibility
-- first -- the same tenant isolation the FK would otherwise provide, just surfaced as a different error.
select throws_ok(
  $$insert into public.communication_conversation_assignments
    (organization_id, client_id, assigned_to) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001',
      'dd000000-0000-0000-0000-000000000004'
    )$$,
  '23514', 'That person cannot be assigned conversations.',
  'a member of another organization cannot be assigned a conversation in this one'
);

select ok(
  exists(
    select 1 from pg_trigger
    where tgrelid = 'public.communication_conversation_assignments'::regclass
    and tgname = 'communication_conversation_assignments_set_updated_at'
  ),
  'the shared set_updated_at trigger is wired on the assignments table'
);

select lives_ok(
  $$insert into public.communication_conversation_followers
    (organization_id, client_id, user_id) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001',
      'dd000000-0000-0000-0000-000000000001'
    )$$,
  'a member can follow a conversation'
);
select lives_ok(
  $$insert into public.communication_conversation_followers
    (organization_id, client_id, user_id) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001',
      'dd000000-0000-0000-0000-000000000003'
    )$$,
  'a second, different member can also follow the same conversation -- following has no view-permission gate at the database level'
);
select throws_ok(
  $$insert into public.communication_conversation_followers
    (organization_id, client_id, user_id) values (
      'dd100000-0000-0000-0000-000000000001', 'dd200000-0000-0000-0000-000000000001',
      'dd000000-0000-0000-0000-000000000001'
    )$$,
  '23505', null,
  'the same member cannot follow the same conversation twice'
);

delete from public.organization_members
where organization_id = 'dd100000-0000-0000-0000-000000000001'
  and user_id = 'dd000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.communication_conversation_assignments
    where assigned_to = 'dd000000-0000-0000-0000-000000000001'),
  0,
  'the assigned member leaving the organization removes the assignment row -- falls back to Unassigned'
);
select is(
  (select count(*)::integer from public.communication_conversation_followers
    where user_id = 'dd000000-0000-0000-0000-000000000001'),
  0,
  'the following member leaving the organization removes their follower row'
);

reset role;
select * from finish();
rollback;
