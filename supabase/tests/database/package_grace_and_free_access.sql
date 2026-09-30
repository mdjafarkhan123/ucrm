-- Package builder P5a: the grace week, the automatic pause when it ends unpaid, restoring access when
-- coverage returns, and dated free access.
begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- Privileges ---------------------------------------------------------------------

select is(
  has_function_privilege('authenticated', 'public.grant_organization_free_access(uuid, date, date, text, text, text)', 'execute'),
  false, 'contractors cannot grant free access');
select is(
  has_function_privilege('service_role', 'public.end_organization_free_access(uuid, uuid, text, text, text)', 'execute'),
  true, 'the owner service role can end free access');
select is(
  has_function_privilege('authenticated', 'private.enforce_package_grace()', 'execute'),
  false, 'contractors cannot run the grace sweep');
select is(
  (select schedule from cron.job where jobname = 'package-grace-enforcement'),
  '*/15 * * * *', 'the grace sweep runs every fifteen minutes');

-- Fixtures: every organization keeps its dates in UTC, so "today" is the UTC date. ------------------

set local role postgres;

create temporary table day as select (now() at time zone 'UTC')::date as today;

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('95000000-0000-0000-0000-0000000005a1', 'Eight days late', 'p5-eight-days-late', 'active'),
  ('95000000-0000-0000-0000-0000000005a2', 'Seven days late', 'p5-seven-days-late', 'active'),
  ('95000000-0000-0000-0000-0000000005a3', 'Security pause', 'p5-security-pause', 'active'),
  ('95000000-0000-0000-0000-0000000005a4', 'Free access late payer', 'p5-free-access', 'active'),
  ('95000000-0000-0000-0000-0000000005a5', 'Paused then free', 'p5-paused-then-free', 'active'),
  ('95000000-0000-0000-0000-0000000005a6', 'Free access begins later', 'p5-free-later', 'active');

select public.adjust_organization_paid_through(o.id, (select today from day) + o.offset_days,
  'P5 test fixture', 'owner@example.test', 'p5-fixture-' || o.id)
from (values
  ('95000000-0000-0000-0000-0000000005a1'::uuid, -8),
  ('95000000-0000-0000-0000-0000000005a2'::uuid, -7),
  ('95000000-0000-0000-0000-0000000005a3'::uuid, -8),
  ('95000000-0000-0000-0000-0000000005a4'::uuid, -10),
  ('95000000-0000-0000-0000-0000000005a5'::uuid, -9),
  ('95000000-0000-0000-0000-0000000005a6'::uuid, -9)
) as o(id, offset_days);

select public.apply_organization_lifecycle_change('95000000-0000-0000-0000-0000000005a3', 'suspended',
  'security', 'p5-security-pause', 'Suspicious sign-ins under review.', 'owner@example.test');

-- Free access on the fourth organization covers today, so its grace has not even started.
select public.grant_organization_free_access('95000000-0000-0000-0000-0000000005a4',
  (select today from day), (select today from day) + 5, 'Storm season goodwill', 'owner@example.test', 'p5-free-a4');

-- The sweep --------------------------------------------------------------------------------

select is(
  private.enforce_package_grace() ->> 'paused', '3',
  'the sweep pauses exactly the organizations whose grace week ended unpaid');

select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a1'),
  'suspended', 'eight days past paid-through, access is paused');
select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a2'),
  'active', 'seven days past paid-through, the grace week still has today');
select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a4'),
  'active', 'free access covering today prevents the pause');
select results_eq(
  $$select actor_kind, suspension_category, actor_owner_email from public.organization_commercial_events
    where organization_id = '95000000-0000-0000-0000-0000000005a1' and event_kind = 'organization_suspended'$$,
  $$values ('system'::text, 'nonpayment'::text, null::text)$$,
  'the pause is recorded as a nonpayment suspension by the system');
select is(
  (select safe_payload from public.organization_safe_events
    where organization_id = '95000000-0000-0000-0000-0000000005a1' and safe_kind = 'account_suspended'),
  jsonb_build_object('access_status', 'suspended'), 'the contractor-safe notice carries only the access status');
select is(
  (select pauses_at from private.organization_access_coverage('95000000-0000-0000-0000-0000000005a2')),
  ((select today from day) + 1)::timestamp at time zone 'UTC',
  'access pauses at the end of the seventh local day after paid-through');
select is(
  private.enforce_package_grace() ->> 'paused', '0', 'a second sweep changes nothing');

-- Confirming payment and coverage restores access at once --------------------------------------

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason,
  actor_owner_email
)
select '95000000-0000-0000-0000-0000000005a1', e.id, 'month', 14900, now() - interval '90 days',
  'test_reset', 'P5 test agreement', 'owner@example.test'
from public.package_editions e
join public.packages p on p.id = e.package_id
where p.slug = 'test-package' and e.status = 'published';

create temporary table ids (name text primary key, id uuid);
insert into ids
select 'charge', (public.add_organization_billing_charge('95000000-0000-0000-0000-0000000005a1',
  'owner@example.test', 'p5-charge', (select today from day) - 7) ->> 'charge_id')::uuid;

select public.record_organization_billing_receipt('95000000-0000-0000-0000-0000000005a1', (select today from day),
  14900, 'Bank transfer', 'TX-P5', 'owner@example.test', 'p5-receipt', null,
  jsonb_build_array(jsonb_build_object('charge_id', (select id from ids where name = 'charge'), 'amount_usd_cents', 14900)));

select is(
  (public.confirm_organization_billing_coverage('95000000-0000-0000-0000-0000000005a1',
    (select id from ids where name = 'charge'),
    (select period_start from public.organization_billing_charges where id = (select id from ids where name = 'charge')),
    (select period_end from public.organization_billing_charges where id = (select id from ids where name = 'charge')),
    'owner@example.test', 'p5-confirm') ->> 'access_restored'),
  'true', 'confirming coverage reports that access was restored');
select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a1'),
  'active', 'confirming payment and coverage restores access at once');
select ok(
  exists (select 1 from public.organization_safe_events
    where organization_id = '95000000-0000-0000-0000-0000000005a1' and safe_kind = 'account_reactivated'),
  'the contractor-safe history shows access restored');

-- A security pause is not lifted by payment --------------------------------------------------------

select is(
  public.adjust_organization_paid_through('95000000-0000-0000-0000-0000000005a3', (select today from day) + 30,
    'Paid offsite', 'owner@example.test', 'p5-security-paid') ->> 'access_restored',
  'false', 'correcting paid-through does not lift a security pause');
select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a3'),
  'suspended', 'the security pause stays after payment');

-- Free access that covers today lifts a nonpayment pause -------------------------------------------

select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a5'),
  'suspended', 'the fifth organization was paused by the sweep');
select is(
  public.grant_organization_free_access('95000000-0000-0000-0000-0000000005a5', (select today from day),
    (select today from day) + 14, 'Owner in hospital', 'owner@example.test', 'p5-free-a5') ->> 'access_restored',
  'true', 'granting free access that covers today lifts the nonpayment pause');
select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a5'),
  'active', 'the organization has access again');

-- The sweep lifts its own pause when free access begins -----------------------------------------------

-- Written directly, as if granted earlier to start today, so no command lifts the pause first.
insert into public.organization_free_access_events (organization_id, action, starts_at, access_until_date, reason,
  actor_owner_email)
values ('95000000-0000-0000-0000-0000000005a6', 'grant', (select today from day), (select today from day) + 3,
  'Scheduled goodwill', 'owner@example.test');
select is(private.enforce_package_grace() ->> 'restored', '1', 'the sweep restores access once free access begins');
select is((select lifecycle_status from public.organizations where id = '95000000-0000-0000-0000-0000000005a6'),
  'active', 'the organization whose free access began has access again');

-- Free access rules ------------------------------------------------------------------------------

select throws_ok(
  $$select public.grant_organization_free_access('95000000-0000-0000-0000-0000000005a2', (select today from day),
    null, 'No end', 'owner@example.test', 'p5-free-no-end')$$,
  '23514', null, 'free access needs an end date');
select throws_ok(
  $$insert into public.organization_free_access_events (organization_id, action, starts_at, reason, actor_owner_email)
    values ('95000000-0000-0000-0000-0000000005a2', 'grant', (select today from day), 'Forever', 'owner@example.test')$$,
  '23514', null, 'the table refuses open-ended free access');
select throws_ok(
  $$select public.grant_organization_free_access('95000000-0000-0000-0000-0000000005a4', (select today from day),
    (select today from day) + 2, 'Second', 'owner@example.test', 'p5-free-second')$$,
  '23514', null, 'a second current grant is refused; the first must be extended');
select throws_ok(
  $$select public.grant_organization_free_access('95000000-0000-0000-0000-0000000005a4', (select today from day) + 3,
    (select today from day) + 9, 'Overlap', 'owner@example.test', 'p5-free-overlap')$$,
  '23514', null, 'a later grant cannot overlap the current one');
select throws_ok(
  $$select public.extend_organization_free_access('95000000-0000-0000-0000-0000000005a4',
    (select grant_id from private.organization_open_free_access('95000000-0000-0000-0000-0000000005a4', (select today from day))),
    (select today from day) + 4, 'Shorter', 'owner@example.test', 'p5-free-shorter')$$,
  '23514', null, 'an extension must end later than the current end date');

select is(
  public.extend_organization_free_access('95000000-0000-0000-0000-0000000005a4',
    (select grant_id from private.organization_open_free_access('95000000-0000-0000-0000-0000000005a4', (select today from day))),
    (select today from day) + 20, 'Longer', 'owner@example.test', 'p5-free-longer') ->> 'applied',
  'true', 'free access can be extended');
select is(
  public.extend_organization_free_access('95000000-0000-0000-0000-0000000005a4',
    (select grant_id from private.organization_open_free_access('95000000-0000-0000-0000-0000000005a4', (select today from day))),
    (select today from day) + 20, 'Longer', 'owner@example.test', 'p5-free-longer') ->> 'applied',
  'false', 'repeating the same command changes nothing');

-- Ending free access covers through today, then the grace week runs; it does not pause at once.
select public.end_organization_free_access('95000000-0000-0000-0000-0000000005a4',
  (select grant_id from private.organization_open_free_access('95000000-0000-0000-0000-0000000005a4', (select today from day))),
  'Customer paid another way', 'owner@example.test', 'p5-free-end');
select results_eq(
  $$select covered_through, free_access_today from private.organization_access_coverage('95000000-0000-0000-0000-0000000005a4')$$,
  $$select (select today from day), true$$,
  'ended free access still covers the day it was ended');
select is(private.enforce_package_grace() ->> 'paused', '0', 'ending free access early does not pause at once');

select * from finish();
rollback;
