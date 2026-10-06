-- Package and offer delete: a package or offer nobody ever used can be deleted; anything with customer
-- history, an application, an offer link, a public listing, or a claim is refused with a reason.
begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

-- Privileges ---------------------------------------------------------------------

select is(has_function_privilege('authenticated', 'public.delete_package(uuid, text)', 'execute'), false,
  'contractors cannot delete a package');
select is(has_function_privilege('anon', 'public.delete_package_offer(uuid, text)', 'execute'), false,
  'visitors cannot delete an offer');
select is(has_function_privilege('service_role', 'public.delete_package(uuid, text)', 'execute'), true,
  'the owner service role can delete a package');
select is(has_function_privilege('service_role', 'public.delete_package_offer(uuid, text)', 'execute'), true,
  'the owner service role can delete an offer');

-- Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

insert into public.packages (id, slug, visibility) values
  ('c1200000-0000-0000-0000-0000000000a1', 'pd-unused', 'private'),
  ('c1200000-0000-0000-0000-0000000000a2', 'pd-public', 'public'),
  ('c1200000-0000-0000-0000-0000000000a3', 'pd-customer', 'private'),
  ('c1200000-0000-0000-0000-0000000000a4', 'pd-application', 'private'),
  ('c1200000-0000-0000-0000-0000000000a5', 'pd-offer', 'private'),
  ('c1200000-0000-0000-0000-0000000000a6', 'pd-draft-only', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents, yearly_price_usd_cents) values
  ('e1200000-0000-0000-0000-0000000000a1', 'c1200000-0000-0000-0000-0000000000a1', 'Unused', 10000, null),
  ('e1200000-0000-0000-0000-0000000000a2', 'c1200000-0000-0000-0000-0000000000a2', 'Public', 10000, null),
  ('e1200000-0000-0000-0000-0000000000a3', 'c1200000-0000-0000-0000-0000000000a3', 'Customer', 10000, null),
  ('e1200000-0000-0000-0000-0000000000a4', 'c1200000-0000-0000-0000-0000000000a4', 'Application', 10000, null),
  ('e1200000-0000-0000-0000-0000000000a5', 'c1200000-0000-0000-0000-0000000000a5', 'Offered', 10000, null),
  ('e1200000-0000-0000-0000-0000000000a6', 'c1200000-0000-0000-0000-0000000000a6', 'Draft only', 10000, null);
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
select e, 'employee_seats', 'numeric', 5
from unnest(array[
  'e1200000-0000-0000-0000-0000000000a1', 'e1200000-0000-0000-0000-0000000000a2',
  'e1200000-0000-0000-0000-0000000000a3', 'e1200000-0000-0000-0000-0000000000a4',
  'e1200000-0000-0000-0000-0000000000a5']::uuid[]) e;
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id in (
  'e1200000-0000-0000-0000-0000000000a1', 'e1200000-0000-0000-0000-0000000000a2',
  'e1200000-0000-0000-0000-0000000000a3', 'e1200000-0000-0000-0000-0000000000a4',
  'e1200000-0000-0000-0000-0000000000a5');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('92000000-0000-0000-0000-0000000012a1', 'Delete customer', 'pd-customer-org', 'active');
insert into public.organization_package_agreements (
  id, organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
) values (
  'a2000000-0000-0000-0000-0000000012a1', '92000000-0000-0000-0000-0000000012a1',
  'e1200000-0000-0000-0000-0000000000a3', 'month', 10000, now() - interval '30 days', 'test_reset', 'PD fixture'
);

insert into public.platform_onboarding_applications (
  id, business_name, main_contact_name, main_contact_email, main_contact_phone, trade, city_country,
  time_zone, package_edition_id, billing_interval, package_snapshot
) values (
  '92000000-0000-0000-0000-0000000012b1', 'PD Application Co', 'Test Contact', 'pd-application@example.test',
  '+10000000000', 'plumbing', 'Testville, US', 'America/New_York',
  'e1200000-0000-0000-0000-0000000000a4', 'month', '{}'::jsonb
);

-- "Used offer" is claimed by the customer. "Unused offer" has no claim and includes the pd-offer package.
create temporary table offers as
select
  (public.save_package_offer(null, null, 'Used offer', 'automatic', null, 'percent', 50, null, true, false, 3, 'new',
    now() - interval '1 hour', null, null, array['c1200000-0000-0000-0000-0000000000a3'::uuid],
    'owner@example.test', 'pd-used-offer') ->> 'offer_id')::uuid as used_id,
  (public.save_package_offer(null, null, 'Unused offer', 'automatic', null, 'percent', 20, null, true, false, 2, 'new',
    now() - interval '1 hour', null, null, array['c1200000-0000-0000-0000-0000000000a5'::uuid],
    'owner@example.test', 'pd-unused-offer') ->> 'offer_id')::uuid as unused_id;
insert into public.package_offer_claims (offer_id, organization_id, agreement_id, method, actor_owner_email)
select used_id, '92000000-0000-0000-0000-0000000012a1', 'a2000000-0000-0000-0000-0000000012a1', 'automatic', 'owner@example.test'
from offers;

create temporary table catalog as
select p ->> 'slug' as slug, p ->> 'delete_blocker' as blocker
from jsonb_array_elements(public.owner_package_catalog()) p
where p ->> 'slug' like 'pd-%';

-- 1. The catalog says why each package can or cannot be deleted. -----------------------------------------

select is((select blocker from catalog where slug = 'pd-unused'), null,
  'a package nobody ever used shows no blocker');
select is((select blocker from catalog where slug = 'pd-draft-only'), null,
  'a package that was never published shows no blocker');
select is((select blocker from catalog where slug = 'pd-customer'),
  '1 customer is on this package, or has been. Archive it instead so their history stays.',
  'a package with a customer says so');
select is((select blocker from catalog where slug = 'pd-application'),
  'A customer application chose this package. Archive it instead so that record stays.',
  'a package chosen on an application says so');
select is((select blocker from catalog where slug = 'pd-offer'),
  'The offer “Unused offer” includes this package. Take it off that offer first.',
  'a package inside an offer names the offer');
select is((select blocker from catalog where slug = 'pd-public'),
  'This package is public on your website. Make it private or archive it first.',
  'a package on the public website must come off it first');

-- 2. Refused deletes change nothing. -----------------------------------------------------------------------

select throws_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a3', 'owner@example.test')$$,
  '23514', '1 customer is on this package, or has been. Archive it instead so their history stays.',
  'a package with a customer cannot be deleted');
select throws_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a4', 'owner@example.test')$$,
  '23514', 'A customer application chose this package. Archive it instead so that record stays.',
  'a package chosen on an application cannot be deleted');
select throws_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a5', 'owner@example.test')$$,
  '23514', 'The offer “Unused offer” includes this package. Take it off that offer first.',
  'a package inside an offer cannot be deleted');
select throws_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a2', 'owner@example.test')$$,
  '23514', 'This package is public on your website. Make it private or archive it first.',
  'a public package cannot be deleted');
select is((select count(*)::integer from public.packages where slug in ('pd-customer', 'pd-application', 'pd-offer', 'pd-public')), 4,
  'every refused package is still there');
select is((select count(*)::integer from public.package_editions
  where package_id in ('c1200000-0000-0000-0000-0000000000a3', 'c1200000-0000-0000-0000-0000000000a5')), 2,
  'refused packages keep their editions');
select is((select count(*)::integer from public.package_edition_allowances
  where edition_id = 'e1200000-0000-0000-0000-0000000000a3'), 1,
  'refused packages keep their allowances');

-- 3. An unused package is deleted completely, and the history says who did it. ----------------------------

select lives_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a1', 'owner@example.test')$$,
  'a package nobody ever used can be deleted, even when published');
select is((select count(*)::integer from public.packages where id = 'c1200000-0000-0000-0000-0000000000a1'), 0,
  'the package is gone');
select is((select count(*)::integer from public.package_editions where package_id = 'c1200000-0000-0000-0000-0000000000a1'), 0,
  'its editions are gone');
select is((select count(*)::integer from public.package_edition_allowances where edition_id = 'e1200000-0000-0000-0000-0000000000a1'), 0,
  'its allowances are gone');
select is((select before_state ->> 'name' from public.platform_owner_audit_events
  where event_type = 'package.deleted' and target_key = 'c1200000-0000-0000-0000-0000000000a1'), 'Unused',
  'the audit history records the deleted package');
select is(coalesce(current_setting('private.deleting_package_id', true), ''), '',
  'the exception for deleting a published edition is closed again');
select throws_ok($$delete from public.package_editions where id = 'e1200000-0000-0000-0000-0000000000a3'$$,
  '23514', 'A published package edition cannot be deleted.',
  'a published edition still cannot be deleted directly');
select lives_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a6', 'owner@example.test')$$,
  'a package that was never published can be deleted');
select throws_ok($$select public.delete_package('c1200000-0000-0000-0000-0000000000a1', 'owner@example.test')$$,
  'P0002', 'Package was not found.', 'deleting a package that is already gone says so');

-- 4. Offers: only one nobody claimed. ---------------------------------------------------------------------

create temporary table offer_list as
select o ->> 'name' as name, o ->> 'delete_blocker' as blocker
from jsonb_array_elements(public.owner_package_offers()) o where o ->> 'name' in ('Used offer', 'Unused offer');

select is((select blocker from offer_list where name = 'Unused offer'), null,
  'an offer nobody claimed shows no blocker');
select is((select blocker from offer_list where name = 'Used offer'),
  '1 customer has claimed this offer, so it stays on record. Archive it instead.',
  'a claimed offer says so');
select throws_ok(format($$select public.delete_package_offer(%L, 'owner@example.test')$$, (select used_id from offers)),
  '23514', '1 customer has claimed this offer, so it stays on record. Archive it instead.',
  'a claimed offer cannot be deleted');
select is((select count(*)::integer from public.package_offers where id = (select used_id from offers)), 1,
  'the claimed offer is still there');
select lives_ok(format($$select public.delete_package_offer(%L, 'owner@example.test')$$, (select unused_id from offers)),
  'an offer nobody claimed can be deleted');
select is((select count(*)::integer from public.package_offers where id = (select unused_id from offers)), 0,
  'the unused offer is gone');
select is((select count(*)::integer from public.package_offer_packages where offer_id = (select unused_id from offers)), 0,
  'its package links are gone too');
select is((select before_state ->> 'name' from public.platform_owner_audit_events
  where event_type = 'package_offer.deleted' and target_key = (select unused_id::text from offers)), 'Unused offer',
  'the audit history records the deleted offer');
select throws_ok(format($$select public.delete_package_offer(%L, 'owner@example.test')$$, (select unused_id from offers)),
  '23503', 'That offer was not found.', 'deleting an offer that is already gone says so');

-- 5. With the offer gone, the package it held can be deleted. ------------------------------------------------

select is((select o ->> 'delete_blocker' from jsonb_array_elements(public.owner_package_catalog()) o where o ->> 'slug' = 'pd-offer'), null,
  'a package is free to delete once its offer is gone');

select * from finish();
rollback;
