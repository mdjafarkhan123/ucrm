-- Package builder P5b: the contractor's own account standing drives the grace banner and the paused
-- screen. Only owners and admins learn about payment; other staff only learn that access is paused.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select is(
  has_function_privilege('anon', 'public.contractor_account_standing()', 'execute'),
  false, 'signed-out visitors cannot ask about an account');

create temporary table day as select (now() at time zone 'UTC')::date as today;
grant select on day to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select ('95b00000-0000-0000-0000-00000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', 'p5b-' || n || '@example.test', 'test', now(), now(), now()
from generate_series(1, 6) n;

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('95b10000-0000-0000-0000-000000000001', 'Grace Plumbing', 'p5b-grace', 'active'),
  ('95b10000-0000-0000-0000-000000000002', 'Paused Roofing', 'p5b-paused', 'active'),
  ('95b10000-0000-0000-0000-000000000003', 'Security Hold', 'p5b-security', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('95b10000-0000-0000-0000-000000000001', '95b00000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('95b10000-0000-0000-0000-000000000001', '95b00000-0000-0000-0000-000000000002', 'field', 'active'),
  ('95b10000-0000-0000-0000-000000000002', '95b00000-0000-0000-0000-000000000003', 'admin', 'active'),
  ('95b10000-0000-0000-0000-000000000002', '95b00000-0000-0000-0000-000000000004', 'field', 'active'),
  ('95b10000-0000-0000-0000-000000000003', '95b00000-0000-0000-0000-000000000005', 'admin', 'active');

select public.adjust_organization_paid_through(o.id, (select today from day) + o.offset_days,
  'P5b test fixture', 'owner@example.test', 'p5b-fixture-' || o.id)
from (values
  ('95b10000-0000-0000-0000-000000000001'::uuid, -3),
  ('95b10000-0000-0000-0000-000000000002'::uuid, -9),
  ('95b10000-0000-0000-0000-000000000003'::uuid, 30)
) as o(id, offset_days);
select private.enforce_package_grace();
select public.apply_organization_lifecycle_change('95b10000-0000-0000-0000-000000000003', 'suspended',
  'security', 'p5b-security', 'Suspicious sign-ins.', 'owner@example.test');

create function pg_temp.standing_as(user_id uuid) returns jsonb language plpgsql as $$
declare result jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', user_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.contractor_account_standing();
  reset role;
  return result;
end;
$$;

select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000001') - 'organization_name' - 'covered_through',
  jsonb_build_object('state', 'grace', 'can_manage', true, 'last_access_day', (select today from day) + 4),
  'an admin in the grace week learns the last day of access');
select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000002') ->> 'state',
  'active', 'a field worker in the same business sees no grace warning');
select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000003') ->> 'state',
  'paused', 'a paused business''s admin is told access is paused');
select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000003') ->> 'reason',
  'payment', 'the admin learns the pause is about payment');
select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000004') - 'organization_name',
  jsonb_build_object('state', 'paused', 'can_manage', false, 'reason', null),
  'a field worker learns only that access is paused');
select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000005') ->> 'reason',
  'other', 'a security pause is not described as a payment problem');
select is(
  pg_temp.standing_as('95b00000-0000-0000-0000-000000000006'),
  null, 'someone with no business gets no standing');

select * from finish();
rollback;
