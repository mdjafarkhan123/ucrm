-- Organization directory: each row names the package the organization is on today.
begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

set local role postgres;

insert into public.packages (id, slug, visibility) values
  ('c1300000-0000-4000-8000-0000000000a1', 'od-starter', 'private'),
  ('c1300000-0000-4000-8000-0000000000a2', 'od-pro', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents, yearly_price_usd_cents) values
  ('e1300000-0000-4000-8000-0000000000a1', 'c1300000-0000-4000-8000-0000000000a1', 'OD Starter', 5000, null),
  ('e1300000-0000-4000-8000-0000000000a2', 'c1300000-0000-4000-8000-0000000000a2', 'OD Pro', 10000, 100000);
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value) values
  ('e1300000-0000-4000-8000-0000000000a1', 'employee_seats', 'numeric', 3),
  ('e1300000-0000-4000-8000-0000000000a2', 'employee_seats', 'numeric', 9);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id in ('e1300000-0000-4000-8000-0000000000a1', 'e1300000-0000-4000-8000-0000000000a2');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('93000000-0000-4000-8000-0000000013a1', 'OD On starter', 'od-on-starter', 'active'),
  ('93000000-0000-4000-8000-0000000013a2', 'OD Moved up', 'od-moved-up', 'active'),
  ('93000000-0000-4000-8000-0000000013a3', 'OD Moves later', 'od-moves-later', 'active'),
  ('93000000-0000-4000-8000-0000000013a4', 'OD Cancelled only', 'od-cancelled-only', 'active'),
  ('93000000-0000-4000-8000-0000000013a5', 'OD No package', 'od-no-package', 'active');

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
) values
  ('93000000-0000-4000-8000-0000000013a1', 'e1300000-0000-4000-8000-0000000000a1', 'month', 5000, now() - interval '30 days', 'test_reset', 'OD'),
  ('93000000-0000-4000-8000-0000000013a2', 'e1300000-0000-4000-8000-0000000000a1', 'month', 5000, now() - interval '60 days', 'test_reset', 'OD'),
  ('93000000-0000-4000-8000-0000000013a2', 'e1300000-0000-4000-8000-0000000000a2', 'year', 100000, now() - interval '10 days', 'test_reset', 'OD'),
  ('93000000-0000-4000-8000-0000000013a3', 'e1300000-0000-4000-8000-0000000000a1', 'month', 5000, now() - interval '30 days', 'test_reset', 'OD'),
  ('93000000-0000-4000-8000-0000000013a3', 'e1300000-0000-4000-8000-0000000000a2', 'month', 10000, now() + interval '20 days', 'test_reset', 'OD');

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason,
  cancelled_at, cancel_reason, cancelled_by_email, cancel_idempotency_key
) values (
  '93000000-0000-4000-8000-0000000013a4', 'e1300000-0000-4000-8000-0000000000a2', 'month', 10000,
  now() - interval '30 days', 'test_reset', 'OD', now() - interval '5 days', 'OD', 'owner@example.test', 'od-cancel'
);

create temporary table directory as
select o as row
from jsonb_array_elements(public.owner_organization_directory(null, null, null, null, 100) -> 'organizations') o
where o ->> 'slug' like 'od-%';

select is((select row -> 'package' ->> 'name' from directory where row ->> 'slug' = 'od-on-starter'), 'OD Starter',
  'an organization shows the package it is on');
select is((select row -> 'package' ->> 'billing_interval' from directory where row ->> 'slug' = 'od-on-starter'), 'month',
  'and how it pays');
select is((select row -> 'package' ->> 'name' from directory where row ->> 'slug' = 'od-moved-up'), 'OD Pro',
  'after a change, the newer package shows, not the older one');
select is((select row -> 'package' ->> 'name' from directory where row ->> 'slug' = 'od-moves-later'), 'OD Starter',
  'a change that has not started yet does not show early');
select is((select jsonb_typeof(row -> 'package') from directory where row ->> 'slug' = 'od-cancelled-only'), 'null',
  'a cancelled agreement is not a package the organization is on');
select is((select jsonb_typeof(row -> 'package') from directory where row ->> 'slug' = 'od-no-package'), 'null',
  'an organization with no package shows none');

select * from finish();
rollback;
