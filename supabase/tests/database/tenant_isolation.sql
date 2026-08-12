begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- Test fixtures are rolled back at the end of this file. The fixed IDs make
-- the assertions easy to audit without depending on generated values.
insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-000000000001', 'RLS Organization A', 'rls-organization-a', 'active'),
  ('10000000-0000-0000-0000-000000000002', 'RLS Organization B', 'rls-organization-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'admin'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'admin');

insert into public.contacts (id, organization_id, display_name)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'RLS Contact A'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'RLS Contact B');

insert into public.properties (id, organization_id, contact_id, address_line1, city)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '1 RLS Street', 'Testville'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '2 RLS Street', 'Testville');

insert into public.requests (id, organization_id, contact_id, property_id, title)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'RLS Request A'),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'RLS Request B');

insert into public.permissions (key, description)
values ('rls.test.read', 'RLS test permission');

set local role postgres;
select throws_ok(
  $$insert into public.organization_members (organization_id, user_id, role) values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'admin')$$,
  '23505',
  null,
  'an Auth user cannot belong to multiple organizations'
);
set local role authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select is((select count(*)::integer from public.organizations), 1, 'a member sees only their active organization');
select is((select count(*)::integer from public.organization_members), 1, 'a member sees only their own membership');
select is((select count(*)::integer from public.contacts), 1, 'a member sees only contacts in their organization');
select is((select count(*)::integer from public.properties), 1, 'a member sees only properties in their organization');
select is((select count(*)::integer from public.requests), 1, 'a member sees only requests in their organization');
select is((select count(*)::integer from public.organization_settings), 1, 'a member sees only settings in their organization');
select is((select count(*)::integer from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 1, 'a user sees their own profile');
select is((select count(*)::integer from public.profiles where id = '00000000-0000-0000-0000-000000000002'), 0, 'a user cannot see another profile');
select is((select count(*)::integer from public.permissions where key = 'rls.test.read'), 1, 'authenticated users can see the global permission catalog');

select throws_ok(
  $$insert into public.contacts (organization_id, display_name) values ('10000000-0000-0000-0000-000000000002', 'Cross-tenant contact')$$,
  '42501',
  null,
  'cross-tenant contact insert is denied'
);

select lives_ok(
  $$update public.contacts set display_name = 'Cross-tenant update' where id = '20000000-0000-0000-0000-000000000002'$$,
  'cross-tenant contact update is denied'
);

set local role postgres;
select ok((select display_name = 'RLS Contact B' from public.contacts where id = '20000000-0000-0000-0000-000000000002'), 'cross-tenant contact update changes no rows');
set local role authenticated;

select lives_ok(
  $$update public.organization_settings set locale = 'en-GB' where organization_id = '10000000-0000-0000-0000-000000000001'$$,
  'a member can update their organization settings'
);

select lives_ok(
  $$update public.organization_settings set locale = 'fr-FR' where organization_id = '10000000-0000-0000-0000-000000000002'$$,
  'cross-tenant settings update is denied'
);

set local role postgres;
select ok((select locale = 'en-US' from public.organization_settings where organization_id = '10000000-0000-0000-0000-000000000002'), 'cross-tenant settings update changes no rows');
set local role authenticated;

select lives_ok(
  $$update public.profiles set full_name = 'Other user' where id = '00000000-0000-0000-0000-000000000002'$$,
  'updating another user profile is denied'
);

set local role postgres;
select ok((select full_name is null from public.profiles where id = '00000000-0000-0000-0000-000000000002'), 'cross-user profile update changes no rows');
set local role authenticated;

set local role postgres;
update public.organizations
set lifecycle_status = 'suspended'
where id = '10000000-0000-0000-0000-000000000001';

set local role authenticated;
select is((select count(*)::integer from public.organizations), 0, 'a suspended organization is hidden from its former member');
select is((select count(*)::integer from public.contacts), 0, 'data in a suspended organization is hidden');

select * from finish();
rollback;
