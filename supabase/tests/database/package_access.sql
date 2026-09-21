begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'access-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'access-b@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'access-c@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-000000000011', 'Access Organization A', 'access-organization-a', 'active'),
  ('10000000-0000-0000-0000-000000000012', 'Access Organization B', 'access-organization-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000011', 'admin'),
  ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'field'),
  ('10000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000012', 'admin');

set local role postgres;
insert into public.organization_feature_overrides
  (organization_id, feature_key, override_state, starts_at)
values
  ('10000000-0000-0000-0000-000000000011', 'core.team', 'off', '2026-01-01T00:00:00Z'),
  ('10000000-0000-0000-0000-000000000012', 'core.team', 'on', '2026-01-01T00:00:00Z');

insert into public.organization_limit_overrides
  (organization_id, limit_key, limit_state, limit_value, is_unlimited, starts_at)
values
  ('10000000-0000-0000-0000-000000000011', 'employee_seats', 'numeric', 1, false, '2026-01-01T00:00:00Z'),
  ('10000000-0000-0000-0000-000000000012', 'employee_seats', 'unlimited', null, true, '2026-01-01T00:00:00Z');

-- Role and permission changes are written by the team API through the service role, not by members writing these
-- tables, so the one override this test reads is placed here the way the API would place it.
insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state)
values ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'customers.edit', 'grant');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);

select is((select count(*)::integer from public.organizations), 1, 'admin sees only one organization');
select is((select package_key from public.organizations limit 1), 'starter', 'new organizations start on Starter');
select is((select limit_value::integer from public.package_limits where package_key = 'starter' and limit_key = 'employee_seats'), 3, 'Starter has three employee seats');
select is((select count(*)::integer from public.package_features where package_key = 'starter' and feature_key = 'sales.pipeline'), 0, 'Starter does not include pipeline');
select is((select count(*)::integer from public.organization_feature_overrides), 1, 'members see feature overrides in their organization');
select is((select count(*)::integer from public.organization_limit_overrides), 1, 'members see limits in their organization');

select throws_ok(
  $$update public.organization_members set role = 'sales' where organization_id = '10000000-0000-0000-0000-000000000011' and user_id = '00000000-0000-0000-0000-000000000013'$$,
  '42501', null, 'even an organization admin cannot change an employee role by writing the table'
);

select throws_ok(
  $$insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state) values ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'customers.view', 'grant')$$,
  '42501', null, 'even an organization admin cannot grant an employee permission by writing the table'
);

select is((select count(*)::integer from public.organization_member_permission_overrides), 1, 'admins see employee overrides in their organization');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', true);
select is((select count(*)::integer from public.organization_feature_overrides), 1, 'a member sees only their own organization feature override');
select is((select count(*)::integer from public.access_audit_events), 0, 'a different organization cannot see access audit events');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', true);
select is((select count(*)::integer from public.organization_member_permission_overrides), 1, 'an employee sees their own permission override');
select is((select count(*)::integer from public.organization_feature_overrides), 1, 'an employee sees their organization feature override');
select is((select count(*)::integer from public.organization_limit_overrides), 1, 'an employee sees their organization limit override');
select throws_ok(
  $$insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state) values ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'invoices.view', 'grant')$$,
  '42501',
  null,
  'a non-admin cannot create employee permission overrides'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);
select throws_ok(
  $$update public.organization_members set role = 'field' where organization_id = '10000000-0000-0000-0000-000000000011' and user_id = '00000000-0000-0000-0000-000000000011'$$,
  '42501',
  null,
  'the last owner or admin cannot be demoted from the browser, because no member writes roles directly'
);
select is((select role from public.organization_members where organization_id = '10000000-0000-0000-0000-000000000011' and user_id = '00000000-0000-0000-0000-000000000011'), 'admin', 'failed last-admin demotion changes no row');

select * from finish();
rollback;
