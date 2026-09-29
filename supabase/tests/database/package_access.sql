begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

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

-- A: the private test package (every working capability). B: a small package made here with only the core
-- capabilities and three seats. C: no agreement at all.
insert into public.organizations (id, name, slug, lifecycle_status)
values ('10000000-0000-0000-0000-000000000014', 'Access Organization C', 'access-organization-c', 'active');

insert into public.packages (id, slug, visibility)
values ('10000000-0000-0000-0000-0000000000a1', 'access-starter', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents)
values ('10000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-0000000000a1', 'Access Starter', 4900);
insert into public.package_edition_capabilities (edition_id, capability_key)
select '10000000-0000-0000-0000-0000000000e1', capability_key from public.package_capabilities where kind = 'core';
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
values ('10000000-0000-0000-0000-0000000000e1', 'employee_seats', 'numeric', 3);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id = '10000000-0000-0000-0000-0000000000e1';

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
select '10000000-0000-0000-0000-000000000011', edition.id, 'month', 0, now() - interval '1 day', 'test_reset',
  'Package access test'
from public.package_editions edition
join public.packages package on package.id = edition.package_id
where package.slug = 'test-package' and edition.status = 'published';
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
values ('10000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-0000000000e1', 'month', 4900,
  now() - interval '1 day', 'test_reset', 'Package access test');

insert into public.organization_package_exceptions
  (organization_id, capability_key, capability_state, reason, starts_at, ends_at, actor_owner_email)
values
  ('10000000-0000-0000-0000-000000000011', 'core.team', 'off', 'Test fixture.', '2026-01-01T00:00:00Z',
   '2100-01-01T00:00:00Z', 'owner@example.test'),
  ('10000000-0000-0000-0000-000000000012', 'core.team', 'off', 'An exception that has already ended.',
   '2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z', 'owner@example.test');
insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email)
values
  ('10000000-0000-0000-0000-000000000011', 'employee_seats', 'numeric', 1, 'Test fixture.', '2026-01-01T00:00:00Z',
   '2100-01-01T00:00:00Z', 'owner@example.test');

select ok(not private.organization_has_capability('10000000-0000-0000-0000-000000000011', 'core.team', now()),
  'an active exception turns off a capability the edition includes');
select ok(private.organization_has_capability('10000000-0000-0000-0000-000000000011', 'marketing', now()),
  'the test package includes marketing');
select ok(private.organization_has_capability('10000000-0000-0000-0000-000000000012', 'core.team', now()),
  'an exception that has ended no longer applies');
select ok(not private.organization_has_capability('10000000-0000-0000-0000-000000000012', 'sales.pipeline', now()),
  'a capability the edition leaves out is not part of the plan');
select ok(not private.organization_has_capability('10000000-0000-0000-0000-000000000014', 'core.jobs', now()),
  'an organization with no agreement has no capability');
select is((select state from public.effective_employee_seat_limit('10000000-0000-0000-0000-000000000014')),
  'not_included', 'an organization with no agreement has no seats');

select throws_ok(
  $$update public.package_editions set monthly_price_usd_cents = 1 where id = '10000000-0000-0000-0000-0000000000e1'$$,
  '23514', null, 'a published edition''s terms cannot change'
);
select throws_ok(
  $$delete from public.package_edition_capabilities where edition_id = '10000000-0000-0000-0000-0000000000e1' and capability_key = 'core.team'$$,
  '23514', null, 'a published edition''s capabilities cannot change'
);
select throws_ok(
  $$update public.organization_package_agreements set agreed_price_usd_cents = 1 where organization_id = '10000000-0000-0000-0000-000000000012'$$,
  '23514', null, 'an agreement cannot be changed, only replaced'
);
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents)
values ('10000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-0000000000a1', 'Access Starter', 5900);
select throws_ok(
  $$insert into public.organization_package_agreements (organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason) values ('10000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-0000000000e2', 'month', 0, now(), 'test_reset', 'Draft')$$,
  '23514', null, 'an organization cannot agree to a draft edition'
);

-- A newer agreement already in effect replaces the older one.
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
values ('10000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-0000000000e1', 'month', 4900,
  now() - interval '1 hour', 'package_change', 'Moved to the smaller package');
select ok(not private.organization_has_capability('10000000-0000-0000-0000-000000000011', 'marketing', now()),
  'moving to an edition without a capability takes that capability away');
select ok(private.organization_has_capability('10000000-0000-0000-0000-000000000011', 'marketing', now() - interval '2 hours'),
  'the earlier agreement still answers for the time before the change');

-- Role and permission changes are written by the team API through the service role, not by members writing these
-- tables, so the one override this test reads is placed here the way the API would place it.
insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state)
values ('10000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000013', 'customers.edit', 'grant');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);

select is((select count(*)::integer from public.organizations), 1, 'admin sees only one organization');
select is((select count(*)::integer from public.organization_package_agreements), 2, 'members see their organization''s agreements');
select is((select count(*)::integer from public.organization_package_exceptions), 2, 'members see their organization''s exceptions');
select is((select count(*)::integer from public.package_editions where package_id = '10000000-0000-0000-0000-0000000000a1'), 1,
  'members see the published edition they agreed to, not the draft');
select is((select state from public.effective_employee_seat_limit('10000000-0000-0000-0000-000000000011')), 'numeric',
  'a member reads the seat allowance');
select is((select value from public.effective_employee_seat_limit('10000000-0000-0000-0000-000000000011')), 1,
  'an allowance exception wins over the edition');
select throws_ok(
  $$insert into public.organization_package_exceptions (organization_id, capability_key, capability_state, reason, starts_at, ends_at, actor_owner_email) values ('10000000-0000-0000-0000-000000000011', 'marketing', 'on', 'Self-service', now(), now() + interval '1 day', 'x@example.test')$$,
  '42501', null, 'a member cannot grant their organization an exception'
);

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
select is((select count(*)::integer from public.organization_package_exceptions), 1, 'a member sees only their own organization''s exceptions');
select is((select count(*)::integer from public.package_editions where package_id = (select id from public.packages where slug = 'test-package')), 0,
  'a member cannot see another organization''s private package');
select is((select count(*)::integer from public.access_audit_events), 0, 'a different organization cannot see access audit events');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000013', true);
select is((select count(*)::integer from public.organization_member_permission_overrides), 1, 'an employee sees their own permission override');
select is((select count(*)::integer from public.organization_package_exceptions), 2, 'an employee sees their organization''s exceptions');
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
