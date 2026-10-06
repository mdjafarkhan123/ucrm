-- Organization directory filters: lifecycle, package, billing, renewal window, joined range, team size, and
-- several attention reasons at once.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

set local role postgres;

insert into public.packages (id, slug, visibility) values
  ('c1400000-0000-4000-8000-0000000000a1', 'fl-starter', 'private'),
  ('c1400000-0000-4000-8000-0000000000a2', 'fl-pro', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents, yearly_price_usd_cents) values
  ('e1400000-0000-4000-8000-0000000000a1', 'c1400000-0000-4000-8000-0000000000a1', 'FL Starter', 5000, 50000),
  ('e1400000-0000-4000-8000-0000000000a2', 'c1400000-0000-4000-8000-0000000000a2', 'FL Pro', 10000, 100000);
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value) values
  ('e1400000-0000-4000-8000-0000000000a1', 'employee_seats', 'numeric', 3),
  ('e1400000-0000-4000-8000-0000000000a2', 'employee_seats', 'numeric', 9);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id in ('e1400000-0000-4000-8000-0000000000a1', 'e1400000-0000-4000-8000-0000000000a2');

-- fl-a: solo, starter monthly, renews in 3 days, joined 3 days ago
-- fl-b: three people, starter yearly, 2 days past its renewal (in grace), joined 40 days ago
-- fl-c: seven people, pro monthly, suspended, renews in 20 days, joined 100 days ago
-- fl-d: solo, no package, closing, joined yesterday
insert into public.organizations (id, name, slug, lifecycle_status, created_at) values
  ('94000000-0000-4000-8000-0000000014a1', 'FL A', 'fl-a', 'active', now() - interval '3 days'),
  ('94000000-0000-4000-8000-0000000014a2', 'FL B', 'fl-b', 'active', now() - interval '40 days'),
  ('94000000-0000-4000-8000-0000000014a3', 'FL C', 'fl-c', 'suspended', now() - interval '100 days'),
  ('94000000-0000-4000-8000-0000000014a4', 'FL D', 'fl-d', 'pending_closure', now() - interval '1 day');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select
  ('95000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'fl-user-' || n || '@example.test', 'test', now(), now(), now()
from generate_series(1, 12) n;

insert into public.organization_members (organization_id, user_id, role) values
  ('94000000-0000-4000-8000-0000000014a1', '95000000-0000-4000-8000-000000000001', 'owner'),
  ('94000000-0000-4000-8000-0000000014a2', '95000000-0000-4000-8000-000000000002', 'owner'),
  ('94000000-0000-4000-8000-0000000014a2', '95000000-0000-4000-8000-000000000003', 'office'),
  ('94000000-0000-4000-8000-0000000014a2', '95000000-0000-4000-8000-000000000004', 'office'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000005', 'owner'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000006', 'office'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000007', 'office'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000008', 'office'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000009', 'office'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000010', 'office'),
  ('94000000-0000-4000-8000-0000000014a3', '95000000-0000-4000-8000-000000000011', 'office'),
  ('94000000-0000-4000-8000-0000000014a4', '95000000-0000-4000-8000-000000000012', 'owner');

insert into public.organization_commercial_state (organization_id, paid_through_date, paid_through_source, grace_ends_at, grace_basis_timezone) values
  ('94000000-0000-4000-8000-0000000014a1', current_date + 3, 'legacy_owner_action', now() + interval '6 days', 'UTC'),
  ('94000000-0000-4000-8000-0000000014a2', current_date - 2, 'legacy_owner_action', now() + interval '1 day', 'UTC'),
  ('94000000-0000-4000-8000-0000000014a3', current_date + 20, 'legacy_owner_action', now() + interval '23 days', 'UTC');

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
) values
  ('94000000-0000-4000-8000-0000000014a1', 'e1400000-0000-4000-8000-0000000000a1', 'month', 5000, now() - interval '30 days', 'test_reset', 'FL'),
  ('94000000-0000-4000-8000-0000000014a2', 'e1400000-0000-4000-8000-0000000000a1', 'year', 50000, now() - interval '30 days', 'test_reset', 'FL'),
  ('94000000-0000-4000-8000-0000000014a3', 'e1400000-0000-4000-8000-0000000000a2', 'month', 10000, now() - interval '30 days', 'test_reset', 'FL');

reset role;

-- Every call below searches for the fixtures only, so other rows in the database cannot change the counts.
create or replace function pg_temp.slugs(result jsonb) returns text language sql as $$
  select coalesce(string_agg(o ->> 'slug', ',' order by o ->> 'slug'), '')
  from jsonb_array_elements(result -> 'organizations') o
$$;

select is(
  (select (public.owner_organization_directory('fl-', null, null, null, 50, array['suspended']) -> 'totals' ->> 'matching')::int),
  1, 'lifecycle: one status');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, array['active', 'pending_closure'])),
  'fl-a,fl-b,fl-d', 'lifecycle: several statuses at once');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, array['c1400000-0000-4000-8000-0000000000a1']::uuid[])),
  'fl-a,fl-b', 'package: one package');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, array['c1400000-0000-4000-8000-0000000000a2']::uuid[], true)),
  'fl-c,fl-d', 'package: a package or no package');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, true)),
  'fl-d', 'package: no package only');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, 'year')),
  'fl-b', 'billing: yearly');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, 'month')),
  'fl-a,fl-c', 'billing: monthly leaves out organizations with no package');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, '7')),
  'fl-a', 'renews within 7 days');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, '30')),
  'fl-a,fl-c', 'renews within 30 days');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, 'overdue')),
  'fl-b', 'renewal already passed');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, null, now() - interval '7 days')),
  'fl-a,fl-d', 'joined since a date');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, null, now() - interval '60 days', now() - interval '30 days')),
  'fl-b', 'joined inside a range');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, null, null, null, 'solo')),
  'fl-a,fl-d', 'team size: just one person');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, null, null, null, 'small')),
  'fl-b', 'team size: two to five');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, null, false, null, null, null, null, 'large')),
  'fl-c', 'team size: six or more');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', array['renewal_due', 'payment_overdue'])),
  'fl-a,fl-b', 'attention: an organization with any of the chosen reasons matches');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', array['renewal_due'])),
  'fl-a', 'attention: one reason');
select is(
  pg_temp.slugs(public.owner_organization_directory('fl-', null, null, null, 50, null, array['c1400000-0000-4000-8000-0000000000a1']::uuid[], false, 'month', '7')),
  'fl-a', 'filters combine: all of them must hold');

create temporary table fixture_facets as
select public.owner_organization_directory('fl-', null, null, null, 50, array['suspended']) -> 'totals' as totals;

select is(
  (select (p ->> 'count')::int from fixture_facets, jsonb_array_elements(totals -> 'packages') p
   where p ->> 'package_id' = 'c1400000-0000-4000-8000-0000000000a1'),
  2, 'package counts ignore the filters in use, so the chip keeps showing every option');
select ok(
  (select (totals ->> 'pending_closure')::int >= 1 and (totals ->> 'no_package')::int >= 1 from fixture_facets),
  'totals carry lifecycle and no-package counts');

select * from finish();
rollback;
