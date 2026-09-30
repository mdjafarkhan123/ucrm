-- Package builder P8a: changing a customer's package, scheduled changes, unused-time credit, and
-- temporary exceptions.
begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- Privileges ---------------------------------------------------------------------

select is(
  has_function_privilege('authenticated',
    'public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text, uuid, text, boolean)', 'execute'),
  false, 'contractors cannot change a package');
select is(
  has_function_privilege('service_role',
    'public.change_organization_package(uuid, uuid, text, text, date, integer, integer, text, text, text, uuid, text, boolean)', 'execute'),
  true, 'the owner service role can change a package');
select is(
  has_function_privilege('authenticated',
    'public.add_organization_package_exception(uuid, text, text, text, text, integer, timestamptz, timestamptz, text, text, text)',
    'execute'),
  false, 'contractors cannot add exceptions');

-- Fixtures: every organization keeps its dates in UTC. ------------------------------------------------

set local role postgres;

create temporary table day as select (now() at time zone 'UTC')::date as today;

-- Big: $200 a month or $2,000 a year, 20 seats, inbox and website chat. Small: $50 a month, 5 seats.
insert into public.packages (id, slug, visibility) values
  ('c8000000-0000-0000-0000-0000000000b1', 'p8-big', 'private'),
  ('c8000000-0000-0000-0000-0000000000b2', 'p8-small', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents, yearly_price_usd_cents) values
  ('e8000000-0000-0000-0000-0000000000b1', 'c8000000-0000-0000-0000-0000000000b1', 'Big', 20000, 200000),
  ('e8000000-0000-0000-0000-0000000000b2', 'c8000000-0000-0000-0000-0000000000b2', 'Small', 5000, 50000);
insert into public.package_edition_capabilities (edition_id, capability_key) values
  ('e8000000-0000-0000-0000-0000000000b1', 'communications.inbox'),
  ('e8000000-0000-0000-0000-0000000000b1', 'website_chat');
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value) values
  ('e8000000-0000-0000-0000-0000000000b1', 'employee_seats', 'numeric', 20),
  ('e8000000-0000-0000-0000-0000000000b2', 'employee_seats', 'numeric', 5);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id in ('e8000000-0000-0000-0000-0000000000b1', 'e8000000-0000-0000-0000-0000000000b2');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('98000000-0000-0000-0000-0000000008a1', 'Eight members', 'p8-eight-members', 'active'),
  ('98000000-0000-0000-0000-0000000008a2', 'Renews later', 'p8-renews-later', 'active'),
  ('98000000-0000-0000-0000-0000000008a3', 'Moves now', 'p8-moves-now', 'active'),
  ('98000000-0000-0000-0000-0000000008a4', 'Goes yearly', 'p8-goes-yearly', 'active'),
  ('98000000-0000-0000-0000-0000000008a5', 'Never paid', 'p8-never-paid', 'active'),
  ('98000000-0000-0000-0000-0000000008a6', 'Exceptions', 'p8-exceptions', 'active');

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
select o.id, 'e8000000-0000-0000-0000-0000000000b1', 'month', 20000, now() - interval '60 days', 'test_reset', 'P8 fixture'
from public.organizations o where o.slug like 'p8-%';

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid, '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'p8-member-' || n || '@example.test', 'test', now(), now(), now()
from generate_series(1, 8) n;
insert into public.organization_members (organization_id, user_id, role)
select '98000000-0000-0000-0000-0000000008a1', ('00000000-0000-0000-0000-0000000008' || lpad(n::text, 2, '0'))::uuid,
  case when n = 1 then 'owner' else 'admin' end
from generate_series(1, 8) n;

-- Three organizations with a paid, covered month that started ten days ago, and next month's charge waiting.
create temporary table paid_org as
select o.id from public.organizations o where o.slug in ('p8-renews-later', 'p8-moves-now', 'p8-goes-yearly');

select public.add_organization_billing_charge(p.id, 'owner@example.test', 'p8-first-' || p.id, (select today from day) - 10)
from paid_org p;
select public.record_organization_billing_receipt(p.id, (select today from day), 20000, 'Bank transfer', 'P8',
  'owner@example.test', 'p8-receipt-' || p.id, null,
  jsonb_build_array(jsonb_build_object('charge_id', c.id, 'amount_usd_cents', 20000)))
from paid_org p join public.organization_billing_charges c on c.organization_id = p.id;
select public.confirm_organization_billing_coverage(p.id, c.id, c.period_start, c.period_end, 'owner@example.test',
  'p8-cover-' || p.id)
from paid_org p join public.organization_billing_charges c on c.organization_id = p.id;

create temporary table first_period as
select c.organization_id, c.period_start, c.period_end from public.organization_billing_charges c
join paid_org p on p.id = c.organization_id
where c.period_start = (select today from day) - 10;

-- 1. A smaller package is refused while more seats are in use than it allows. -------------------------

select is(
  (public.owner_package_change_preview('98000000-0000-0000-0000-0000000008a1',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'now') -> 'over_limits' -> 0 ->> 'excess')::integer,
  3, 'moving eight members to a five-seat package shows three seats over');
select throws_ok(
  $$select public.change_organization_package('98000000-0000-0000-0000-0000000008a1',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'now', (select today from day), 0, 0, 'Downgrade',
    'owner@example.test', 'p8-downgrade-refused')$$,
  '23514', 'Resolve what is over the new package''s limits first.',
  'the move is refused until the extra seats are resolved');

delete from public.organization_members
where organization_id = '98000000-0000-0000-0000-0000000008a1' and role = 'admin'
  and user_id in ('00000000-0000-0000-0000-000000000806', '00000000-0000-0000-0000-000000000807',
    '00000000-0000-0000-0000-000000000808');

select is(
  public.change_organization_package('98000000-0000-0000-0000-0000000008a1',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'now', (select today from day), 0, 0, 'Downgrade',
    'owner@example.test', 'p8-downgrade-ok') ->> 'applied',
  'true', 'with three seats freed the move goes through');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a1', 'employee_seats')),
  5, 'the organization now has five seats');
select is(
  public.change_organization_package('98000000-0000-0000-0000-0000000008a1',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'now', (select today from day), 0, 0, 'Downgrade',
    'owner@example.test', 'p8-downgrade-ok') ->> 'applied',
  'false', 'repeating the same change does nothing');

-- 2. A move at the next renewal takes effect that day and reprices the waiting charge. ---------------

create temporary table renewal_plan as
select public.owner_package_change_preview('98000000-0000-0000-0000-0000000008a2',
  'e8000000-0000-0000-0000-0000000000b2', 'month', 'next_renewal') as plan;

select is(
  (select (plan ->> 'effective_date')::date from renewal_plan),
  (select period_end + 1 from first_period where organization_id = '98000000-0000-0000-0000-0000000008a2'),
  'the next renewal is the day after paid-through');
select is(
  (select jsonb_array_length(plan -> 'money' -> 'replaced_charges') from renewal_plan), 1,
  'the waiting old-price charge is listed as replaced');
select is(
  (select (plan -> 'money' -> 'next_charge' ->> 'amount_usd_cents')::integer from renewal_plan), 5000,
  'it comes back at the new price');

select is(
  public.change_organization_package('98000000-0000-0000-0000-0000000008a2',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'next_renewal',
    (select (plan ->> 'effective_date')::date from renewal_plan), 0, 0, 'Asked for the smaller package',
    'owner@example.test', 'p8-renewal') ->> 'applied',
  'true', 'the move is scheduled');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a2', 'employee_seats')),
  20, 'until the renewal the customer keeps twenty seats');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a2', 'employee_seats',
    (select (plan ->> 'effective_from')::timestamptz from renewal_plan))),
  5, 'from the renewal they have five');
select is(
  (select c.amount_usd_cents from public.organization_billing_charges c
   where c.organization_id = '98000000-0000-0000-0000-0000000008a2'
     and c.period_start = (select (plan ->> 'effective_date')::date from renewal_plan)
     and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)),
  5000, 'the next month is charged at the new price');
select is(
  (select jsonb_array_length(public.owner_organization_billing('98000000-0000-0000-0000-0000000008a2') -> 'upcoming_agreements')),
  1, 'Billing shows the scheduled change');
select is(
  (public.owner_package_change_preview('98000000-0000-0000-0000-0000000008a2',
    'e8000000-0000-0000-0000-0000000000b1', 'year', 'now') -> 'blockers' -> 0 ->> 'code'),
  'change_scheduled', 'another change waits until the scheduled one is cancelled');

select is(
  public.cancel_scheduled_package_change('98000000-0000-0000-0000-0000000008a2',
    (select a.id from public.organization_package_agreements a
     where a.idempotency_key = 'p8-renewal'), 'Changed their mind', 'owner@example.test', 'p8-renewal-cancel') ->> 'applied',
  'true', 'the scheduled change can be cancelled');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a2', 'employee_seats',
    (select (plan ->> 'effective_from')::timestamptz from renewal_plan))),
  20, 'after cancelling, the renewal keeps twenty seats');
select is(
  (select c.amount_usd_cents from public.organization_billing_charges c
   where c.organization_id = '98000000-0000-0000-0000-0000000008a2'
     and c.period_start = (select (plan ->> 'effective_date')::date from renewal_plan)
     and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)),
  20000, 'and the next month goes back to the old price');
select is(
  (select jsonb_array_length(public.owner_organization_billing('98000000-0000-0000-0000-0000000008a2') -> 'upcoming_agreements')),
  0, 'the cancelled change is no longer upcoming');
select is(
  (select count(*)::integer from jsonb_array_elements(
    public.owner_organization_billing('98000000-0000-0000-0000-0000000008a2') -> 'agreement_history') h
   where h ->> 'cancelled_at' is not null),
  1, 'but stays in the agreement history');

-- 3. A move now at the same interval credits unused days and charges the rest at the new price. ------

create temporary table now_plan as
select public.owner_package_change_preview('98000000-0000-0000-0000-0000000008a3',
  'e8000000-0000-0000-0000-0000000000b2', 'month', 'now') as plan;
create temporary table now_expect as
select
  round(20000::numeric * (f.period_end - (select today from day) + 1) / (f.period_end - f.period_start + 1))::integer as credit,
  round(5000::numeric * (f.period_end - (select today from day) + 1) / (f.period_end - f.period_start + 1))::integer as charge,
  f.period_end
from first_period f where f.organization_id = '98000000-0000-0000-0000-0000000008a3';

select is((select (plan -> 'money' ->> 'credit_usd_cents')::integer from now_plan), (select credit from now_expect),
  'the credit is the unused share of this month''s charge');
select is((select (plan -> 'money' -> 'new_charge' ->> 'amount_usd_cents')::integer from now_plan),
  (select charge from now_expect), 'the new charge is the new price for the same remaining days');
select is((select (plan -> 'money' -> 'new_charge' ->> 'period_end')::date from now_plan),
  (select period_end from now_expect), 'the renewal date stays the same');

select throws_ok(
  format($$select public.change_organization_package('98000000-0000-0000-0000-0000000008a3',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'now', %L, %s, %s, 'Downgrade now',
    'owner@example.test', 'p8-now-stale')$$, (select today from day), (select credit from now_expect) + 1,
    (select charge from now_expect)),
  'P0409', 'The change has moved on since you reviewed it. Review it again.',
  'a confirmation that no longer matches the preview is refused');

select is(
  public.change_organization_package('98000000-0000-0000-0000-0000000008a3',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'now', (select today from day),
    (select credit from now_expect), (select charge from now_expect), 'Downgrade now',
    'owner@example.test', 'p8-move-now') ->> 'applied',
  'true', 'the move now goes through');
select is(
  (select amount_usd_cents from public.organization_billing_credit_notes
   where organization_id = '98000000-0000-0000-0000-0000000008a3'),
  (select credit from now_expect), 'the credit is recorded as it was shown');
select is(
  (select c.amount_usd_cents - private.billing_charge_applied(c.id) from public.organization_billing_charges c
   where c.organization_id = '98000000-0000-0000-0000-0000000008a3' and c.kind = 'change'),
  0, 'the credit pays the smaller remaining-days charge');
select is(
  (select (public.owner_organization_billing('98000000-0000-0000-0000-0000000008a3') -> 'totals' ->> 'credit_usd_cents')::integer),
  (select credit - charge from now_expect), 'what is left of the credit stays as credit');
select is(
  (select c.amount_usd_cents from public.organization_billing_charges c
   where c.organization_id = '98000000-0000-0000-0000-0000000008a3' and c.period_start = (select period_end + 1 from now_expect)
     and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)),
  5000, 'next month is charged at the new price');
select is(
  (select paid_through_date from public.organization_commercial_state
   where organization_id = '98000000-0000-0000-0000-0000000008a3'),
  (select period_end from now_expect), 'paid-through does not move');

-- 4. Monthly to yearly now starts the year today. ----------------------------------------------------

create temporary table year_plan as
select public.owner_package_change_preview('98000000-0000-0000-0000-0000000008a4',
  'e8000000-0000-0000-0000-0000000000b1', 'year', 'now') as plan;

select is(
  public.change_organization_package('98000000-0000-0000-0000-0000000008a4',
    'e8000000-0000-0000-0000-0000000000b1', 'year', 'now', (select today from day),
    (select (plan -> 'money' ->> 'credit_usd_cents')::integer from year_plan), 200000, 'Pays for the year',
    'owner@example.test', 'p8-yearly-move') ->> 'applied',
  'true', 'moving to yearly now goes through');
select results_eq(
  $$select c.period_start, c.period_end, c.amount_usd_cents from public.organization_billing_charges c
    where c.organization_id = '98000000-0000-0000-0000-0000000008a4' and c.period_start > (select today from day) - 10
      and not exists (select 1 from public.organization_billing_voids v where v.charge_id = c.id)$$,
  $$select (select today from day), ((select today from day) + interval '1 year')::date - 1, 200000$$,
  'one yearly charge starts today and the waiting monthly charge is gone');

-- 5. With no paid period, there is no renewal date to wait for. --------------------------------------

select is(
  (public.owner_package_change_preview('98000000-0000-0000-0000-0000000008a5',
    'e8000000-0000-0000-0000-0000000000b2', 'month', 'next_renewal') -> 'blockers' -> 0 ->> 'code'),
  'no_renewal_date', 'a customer who never paid can only be moved now');

-- 6. Temporary exceptions. ---------------------------------------------------------------------------

select is(
  public.add_organization_package_exception('98000000-0000-0000-0000-0000000008a6', null, null,
    'employee_seats', 'numeric', 25, now(), now() + interval '1 day', 'Busy season', 'owner@example.test',
    'p8-extra-seats') ->> 'applied',
  'true', 'an extra-seat exception can be added');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a6', 'employee_seats')),
  25, 'the exception applies now');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a6', 'employee_seats',
    now() + interval '2 days')),
  20, 'and ends on its end date');
select throws_like(
  $$select public.add_organization_package_exception('98000000-0000-0000-0000-0000000008a6', null, null,
    'employee_seats', 'numeric', 30, now(), now() + interval '3 days', 'Overlap', 'owner@example.test', 'p8-overlap')$$,
  'An exception for this already runs until%', 'two exceptions for the same limit cannot overlap');
select throws_ok(
  $$select public.add_organization_package_exception('98000000-0000-0000-0000-0000000008a6',
    'communications.inbox', 'off', null, null, null, now(), now() + interval '1 day', 'Off', 'owner@example.test',
    'p8-inbox-off')$$,
  '23514', 'Website chat needs Shared inbox. Switch Website chat off first.',
  'a feature another feature needs cannot be switched off alone');
select throws_like(
  $$select public.add_organization_package_exception('98000000-0000-0000-0000-0000000008a6',
    'integrations.api', 'on', null, null, null, now(), now() + interval '1 day', 'On', 'owner@example.test',
    'p8-api-on')$$,
  '%is not built yet%', 'a feature that is not built cannot be switched on');
select is(
  public.end_organization_package_exception('98000000-0000-0000-0000-0000000008a6',
    (select id from public.organization_package_exceptions where idempotency_key = 'p8-extra-seats'),
    'Season over early', 'owner@example.test', 'p8-extra-seats-end') ->> 'applied',
  'true', 'an exception can be ended early');
select is(
  (select value from public.organization_allowance('98000000-0000-0000-0000-0000000008a6', 'employee_seats')),
  20, 'ending it brings back the package''s limit');

select * from finish();
rollback;
