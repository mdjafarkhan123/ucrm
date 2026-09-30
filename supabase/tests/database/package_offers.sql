-- Package builder P11a: introductory offers. Offers on public cards, claims at activation and package
-- change, discounted charges for exactly the offer's periods, claim deadlines, caps, and kept offers.
begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

-- Privileges ---------------------------------------------------------------------

select is(has_function_privilege('anon', 'public.public_package_offers()', 'execute'), true,
  'visitors can read the offers shown on public packages');
select is(has_function_privilege('authenticated',
  'public.save_package_offer(uuid, integer, text, text, text, text, integer, integer, boolean, boolean, integer, text, timestamptz, timestamptz, integer, uuid[], text, text)',
  'execute'), false, 'contractors cannot build offers');
select is(has_function_privilege('anon', 'public.owner_package_offers()', 'execute'), false,
  'visitors cannot read the offer builder');

-- Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

create temporary table day as select (now() at time zone 'UTC')::date as today;

-- Pro: $149 a month or $1,490 a year. Max: $300 a month.
insert into public.packages (id, slug, visibility) values
  ('c1100000-0000-0000-0000-0000000000a1', 'p11-pro', 'public'),
  ('c1100000-0000-0000-0000-0000000000a2', 'p11-max', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents, yearly_price_usd_cents) values
  ('e1100000-0000-0000-0000-0000000000a1', 'c1100000-0000-0000-0000-0000000000a1', 'Pro', 14900, 149000),
  ('e1100000-0000-0000-0000-0000000000a2', 'c1100000-0000-0000-0000-0000000000a2', 'Max', 30000, null);
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value) values
  ('e1100000-0000-0000-0000-0000000000a1', 'employee_seats', 'numeric', 10),
  ('e1100000-0000-0000-0000-0000000000a2', 'employee_seats', 'numeric', 20);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id in ('e1100000-0000-0000-0000-0000000000a1', 'e1100000-0000-0000-0000-0000000000a2');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select ('00000000-0000-0000-0000-0000000011' || lpad(n::text, 2, '0'))::uuid, '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'p11-owner-' || n || '@example.test', 'test', now(), now(), now()
from generate_series(1, 3) n;

-- "50% off for 3 months" for new customers on Pro, monthly or yearly, at most two customers.
create temporary table launch as
select (public.save_package_offer(null, null, 'Launch offer', 'automatic', null, 'percent', 50, null, true, true, 3, 'new',
  now() - interval '1 hour', now() + interval '7 days', 2, array['c1100000-0000-0000-0000-0000000000a1'::uuid],
  'owner@example.test', 'p11-launch-offer') ->> 'offer_id')::uuid as id;

-- $20 off for 2 months, by code, for existing customers on Pro or Max.
select public.save_package_offer(null, null, 'Switch deal', 'code', 'switch20', 'fixed', null, 2000, true, false, 2,
  'existing', now() - interval '1 hour', null, null,
  array['c1100000-0000-0000-0000-0000000000a1'::uuid, 'c1100000-0000-0000-0000-0000000000a2'::uuid],
  'owner@example.test', 'p11-switch-offer');

-- 1. The public card shows the intro price and the later price. ----------------------------------------

create temporary table shown as
select o from jsonb_array_elements(public.public_package_offers()) o where o ->> 'package_slug' = 'p11-pro';

select is((select (o ->> 'intro_price_usd_cents')::integer from shown where o ->> 'billing_interval' = 'month'), 7450,
  'Pro monthly shows $74.50');
select is((select (o ->> 'periods')::integer from shown where o ->> 'billing_interval' = 'month'), 3,
  'for 3 months');
select is((select (o ->> 'normal_price_usd_cents')::integer from shown where o ->> 'billing_interval' = 'month'), 14900,
  'then $149');
select is((select (o ->> 'intro_price_usd_cents')::integer from shown where o ->> 'billing_interval' = 'year'), 74500,
  'Pro yearly shows half off the first year');
select is((select count(*)::integer from shown), 2, 'a code offer is never shown publicly');

-- 2. An application keeps the offer it showed; activation claims it and bills $74.50. ------------------

create temporary table app as
select n, public.submit_onboarding_application('P11 Customer ' || n, 'Pat ' || n, 'p11-' || n || '@example.test',
  '555-011' || n, null, null, 'Plumbing', 'Denver, USA', 'UTC', null, 'e1100000-0000-0000-0000-0000000000a1', 'month',
  'v1', '{}'::jsonb) as id
from generate_series(1, 3) n;

select is((select (a.package_snapshot ->> 'first_payment_usd_cents')::integer
  from public.platform_onboarding_applications a where a.id = (select id from app where n = 1)), 7450,
  'the application records a first payment of $74.50');
select throws_ok(
  format($$select public.confirm_onboarding_application_payment(%L, 'owner@example.test', %L, 7000, 'Bank', 'ref')$$,
    (select id from app where n = 1), (select today from day)),
  '23514', null, 'a payment below the intro price is refused');

select public.confirm_onboarding_application_payment(a.id, 'owner@example.test', (select today from day), 7450, 'Bank',
  'p11-ref-' || a.n)
from app a;

select is((public.owner_onboarding_activation_preview((select id from app where n = 1)) ->> 'first_charge_usd_cents')::integer,
  7450, 'activation previews a first charge of $74.50');

create temporary table org as
select n, ('91100000-0000-0000-0000-00000000000' || n)::uuid as id from generate_series(1, 3) n;

select public.provision_organization_from_application(
  (select id from app where n = o.n), o.id, 'P11 Customer ' || o.n, 'p11-customer-' || o.n,
  ('00000000-0000-0000-0000-0000000011' || lpad(o.n::text, 2, '0'))::uuid, 'owner@example.test',
  (select today from day), private.billing_period_end((select today from day), (select today from day), 'month'),
  null, null, 7450)
from org o where o.n in (1, 2);

select is(
  (select c.amount_usd_cents from public.organization_billing_charges c
    where c.organization_id = (select id from org where n = 1) and c.period_start = (select today from day)),
  7450, 'the first charge is $74.50');
select is(
  (select paid_through_date from public.organization_commercial_state where organization_id = (select id from org where n = 1)),
  private.billing_period_end((select today from day), (select today from day), 'month'), 'and it is paid and covered');
select is(
  (select count(*)::integer from public.package_offer_claims where offer_id = (select id from launch)), 2,
  'both activations claimed the offer');

-- 4. The cap stops the next claim. ---------------------------------------------------------------------

select is((select count(*)::integer from jsonb_array_elements(public.public_package_offers()) o
  where o ->> 'id' = (select id from launch)::text), 0, 'a full offer is no longer shown to new customers');
select is(
  (public.owner_onboarding_activation_preview((select id from app where n = 3)) -> 'offer' -> 'problems' -> 0 ->> 'code'),
  'full', 'the third activation is told the places are gone');
select throws_like(
  format($$select public.provision_organization_from_application(%L, %L, 'P11 Customer 3', 'p11-customer-3',
    '00000000-0000-0000-0000-000000001103', 'owner@example.test', %L, %L)$$,
    (select id from app where n = 3), (select id from org where n = 3), (select today from day),
    private.billing_period_end((select today from day), (select today from day), 'month')),
  '%Honor it or activate at the normal price.%', 'activation waits for Jafar to decide');

select public.provision_organization_from_application(
  (select id from app where n = 3), (select id from org where n = 3), 'P11 Customer 3', 'p11-customer-3',
  '00000000-0000-0000-0000-000000001103', 'owner@example.test', (select today from day),
  private.billing_period_end((select today from day), (select today from day), 'month'), 'honor', null, 7450);
select is(
  (select honored from public.package_offer_claims where organization_id = (select id from org where n = 3)), true,
  'Jafar can honor the offer the customer was shown, and the claim says so');

-- 5. Discount terms are fixed once claimed; the deadline stops new claims only. ------------------------

select throws_like(
  format($$select public.save_package_offer(%L, 1, 'Launch offer', 'automatic', null, 'percent', 40, null, true, true, 3,
    'new', now() - interval '1 hour', now() + interval '7 days', 5, array['c1100000-0000-0000-0000-0000000000a1'::uuid],
    'owner@example.test', 'p11-launch-edit')$$, (select id from launch)),
  '%can no longer change%', 'a claimed offer''s discount cannot change');
select is(
  public.save_package_offer((select id from launch), 1, 'Launch offer', 'automatic', null, 'percent', 50, null, true, true, 3,
    'new', now() - interval '1 hour', now() - interval '1 second', 10, array['c1100000-0000-0000-0000-0000000000a1'::uuid],
    'owner@example.test', 'p11-launch-close') ->> 'revision',
  '2', 'the deadline and cap can still change');
select throws_like(
  format($$select public.save_package_offer(%L, 1, 'Launch offer', 'automatic', null, 'percent', 50, null, true, true, 3,
    'new', now() - interval '1 hour', null, null, array['c1100000-0000-0000-0000-0000000000a1'::uuid],
    'owner@example.test', 'p11-launch-stale')$$, (select id from launch)),
  '%changed somewhere else%', 'a stale edit is refused');
select is((select count(*)::integer from jsonb_array_elements(public.public_package_offers()) o
  where o ->> 'id' = (select id from launch)::text), 0, 'after the deadline new customers do not see the offer');
create temporary table late_app as
select public.submit_onboarding_application('P11 Late', 'Lee', 'p11-late@example.test', '5550119', null, null,
  'Plumbing', 'Denver, USA', 'UTC', null, 'e1100000-0000-0000-0000-0000000000a1', 'month', 'v1', '{}'::jsonb) as id;
select is(
  (select jsonb_typeof(a.package_snapshot -> 'offer') from public.platform_onboarding_applications a
    where a.id = (select id from late_app)),
  'null', 'an application after the deadline carries no offer');
-- 5b. After the deadline the customer still gets two more months at $74.50, then $149. ----------------

do $$
begin
  -- Activation already added month 2; months 3 and 4 are billed after the deadline.
  for k in 3..4 loop
    perform public.add_organization_billing_charge('91100000-0000-0000-0000-000000000001', 'owner@example.test',
      'p11-period-' || k, (select max(c.period_end) + 1 from public.organization_billing_charges c
        where c.organization_id = '91100000-0000-0000-0000-000000000001'));
  end loop;
end $$;

select is(
  (select array_agg(c.amount_usd_cents order by c.period_start) from public.organization_billing_charges c
    where c.organization_id = (select id from org where n = 1)),
  array[7450, 7450, 7450, 14900], 'three charges at $74.50, then $149');

-- 6. An existing customer takes a code offer at the next renewal. ------------------------------------

select is(
  (public.owner_package_change_preview((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
    'next_renewal', null, 'SWITCH20') -> 'blockers') , '[]'::jsonb, 'the code is accepted in any case');
create temporary table code_plan as
select public.owner_package_change_preview((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
  'next_renewal', null, 'switch20') as plan;
select is((select (plan -> 'offer' -> 'proposed' ->> 'intro_price_usd_cents')::integer from code_plan), 28000,
  'Max for $280 with $20 off');
select is((select (plan -> 'offer' -> 'proposed' ->> 'starts_on')::date from code_plan),
  (select (plan ->> 'effective_date')::date from code_plan), 'the offer starts with the change');
select is((select plan -> 'offer' ->> 'can_keep' from code_plan), 'true',
  'the Launch offer could be kept instead, since it runs past the renewal');
select is(
  (public.owner_package_change_preview((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
    'next_renewal', null, 'switch20', true) -> 'blockers' -> 0 ->> 'code'),
  'offer_choice', 'a new offer and a kept one cannot both apply');

select public.change_organization_package((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
  'next_renewal', (select (plan ->> 'effective_date')::date from code_plan), 0, 0, 'Upgrade with the switch deal',
  'owner@example.test', 'p11-code-change', null, 'switch20');
select is(
  (select c.method from public.package_offer_claims c join public.package_offers o on o.id = c.offer_id
    where c.organization_id = (select id from org where n = 2) and o.code = 'SWITCH20'),
  'code', 'the code claim is recorded');

-- 7. Cancelling the scheduled change releases the claim. -------------------------------------------------

select public.cancel_scheduled_package_change((select id from org where n = 2),
  (select a.id from public.organization_package_agreements a
    where a.organization_id = (select id from org where n = 2) and a.idempotency_key = 'p11-code-change'),
  'Changed their mind', 'owner@example.test', 'p11-code-cancel');
select isnt(
  (select c.released_at from public.package_offer_claims c join public.package_offers o on o.id = c.offer_id
    where c.organization_id = (select id from org where n = 2) and o.code = 'SWITCH20'),
  null, 'the cancelled change''s claim is released but kept in history');
select is(
  (public.owner_package_change_preview((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
    'next_renewal', null, 'switch20') -> 'blockers'),
  '[]'::jsonb, 'and the customer may claim it again');

-- 8. A kept offer ends on its original date with the new price. ----------------------------------------

select is(
  (public.owner_package_change_preview((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a1', 'year',
    'now', null, null, true) -> 'blockers' -> 0 ->> 'code'),
  'offer_interval', 'an offer cannot be kept when moving from monthly to yearly');

create temporary table keep_plan as
select public.owner_package_change_preview((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
  'now', null, null, true) as plan;
select is((select plan -> 'blockers' from keep_plan), '[]'::jsonb, 'keeping the offer on an upgrade is allowed');
select is((select (plan -> 'offer' -> 'proposed' ->> 'ends_before')::date from keep_plan),
  (select (a.offer_terms ->> 'ends_before')::date from public.organization_package_agreements a
    where a.organization_id = (select id from org where n = 2) and a.source = 'activation'),
  'the kept offer ends on its original date');
select is((select (plan -> 'offer' -> 'proposed' ->> 'intro_price_usd_cents')::integer from keep_plan), 15000,
  'at 50% of the new $300 price');

select public.change_organization_package((select id from org where n = 2), 'e1100000-0000-0000-0000-0000000000a2', 'month',
  'now', (select today from day), (select (plan -> 'money' ->> 'credit_usd_cents')::integer from keep_plan),
  (select (plan -> 'money' -> 'new_charge' ->> 'amount_usd_cents')::integer from keep_plan), 'Upgrade keeping the offer',
  'owner@example.test', 'p11-keep-change', null, null, true);
select is(
  (select a.offer_terms ->> 'claim_id' from public.organization_package_agreements a where a.idempotency_key = 'p11-keep-change'),
  (select c.id::text from public.package_offer_claims c
    where c.organization_id = (select id from org where n = 2) and c.offer_id = (select id from launch)),
  'the kept offer is the same claim');
select is(
  (select c.amount_usd_cents from public.organization_billing_charges c
    where c.idempotency_key = 'p11-keep-change:charge'),
  15000, 'the rest of this month (all of it, activated today) is charged at the kept $150 intro price');

-- 9. Archiving stops claims. -------------------------------------------------

select public.set_package_offer_archived(o.id, true, 'owner@example.test') from public.package_offers o where o.code = 'SWITCH20';
select is(
  (public.owner_package_change_preview((select id from org where n = 1), 'e1100000-0000-0000-0000-0000000000a2', 'month',
    'next_renewal', null, 'switch20') -> 'blockers' -> 0 ->> 'code'),
  'archived', 'an archived offer cannot be claimed');

select * from finish();
rollback;
