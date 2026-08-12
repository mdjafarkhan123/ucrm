begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

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
  (organization_id, limit_key, limit_value, is_unlimited, starts_at)
values
  ('10000000-0000-0000-0000-000000000011', 'employee_seats', 1, false, '2026-01-01T00:00:00Z'),
  ('10000000-0000-0000-0000-000000000012', 'employee_seats', null, true, '2026-01-01T00:00:00Z');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);

select is((select count(*)::integer from public.organizations), 1, 'admin sees only one organization');
select is((select package_key from public.organizations limit 1), 'starter', 'new organizations start on Starter');
select is((select limit_value::integer from public.package_limits where package_key = 'starter' and limit_key = 'employee_seats'), 3, 'Starter has three employee seats');
select is((select count(*)::integer from public.package_features where package_key = 'starter' and feature_key = 'sales.pipeline'), 0, 'Starter does not include pipeline');
select is((select count(*)::integer from public.organization_feature_overrides), 1, 'members see feature overrides in their organization');
select is((select count(*)::integer from public.organization_limit_overrides), 1, 'members see limits in their organization');

select lives_ok(
  $$update public.organization_members set role = 'sales' where organization_id = '10000000-0000-0000-0000-000000000011' and user_id = '00000000-0000-0000-0000-000000000013'$$,
  'an organization admin can change an employee role'
);

select lives_ok(
  $$insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state) values ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'customer.edit', 'grant')$$,
  'an organization admin can grant an employee permission'
);

select is((select count(*)::integer from public.organization_member_permission_overrides), 1, 'admins see employee overrides in their organization');
select is((select count(*)::integer from public.access_audit_events where event_type = 'employee_role_changed'), 1, 'role changes create an audit event');
select is((select count(*)::integer from public.access_audit_events where event_type = 'employee_permission_override_changed'), 1, 'permission changes create an audit event');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', true);
select is((select count(*)::integer from public.organization_feature_overrides), 1, 'a member sees only their own organization feature override');
select is((select count(*)::integer from public.access_audit_events), 0, 'a different organization cannot see access audit events');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', true);
select is((select count(*)::integer from public.organization_member_permission_overrides), 1, 'an employee sees their own permission override');
select is((select count(*)::integer from public.organization_feature_overrides), 1, 'an employee sees their organization feature override');
select is((select count(*)::integer from public.organization_limit_overrides), 1, 'an employee sees their organization limit override');
select throws_ok(
  $$insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state) values ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'invoice.view', 'grant')$$,
  '42501',
  null,
  'a non-admin cannot create employee permission overrides'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);
select throws_ok(
  $$update public.organization_members set role = 'field' where organization_id = '10000000-0000-0000-0000-000000000011' and user_id = '00000000-0000-0000-0000-000000000011'$$,
  '23514',
  null,
  'the last owner or admin cannot be demoted'
);
select is((select role from public.organization_members where organization_id = '10000000-0000-0000-0000-000000000011' and user_id = '00000000-0000-0000-0000-000000000011'), 'admin', 'failed last-admin demotion changes no row');

select * from finish();
rollback;
