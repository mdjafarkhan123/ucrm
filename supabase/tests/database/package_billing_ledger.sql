-- Package builder P4a: the offsite billing ledger. Charges per service period, payments applied
-- explicitly, credit, refunds, cancellations with reasons, and coverage confirmed separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

-- Privileges ---------------------------------------------------------------------

select is(
  has_function_privilege('authenticated',
    'public.record_organization_billing_receipt(uuid, date, integer, text, text, text, text, text, jsonb)', 'execute'),
  false, 'contractors cannot record package payments');
select is(
  has_function_privilege('authenticated', 'public.owner_organization_billing(uuid)', 'execute'),
  false, 'contractors cannot read the owner billing view');
select is(
  has_function_privilege('service_role',
    'public.confirm_organization_billing_coverage(uuid, uuid, date, date, text, text)', 'execute'),
  true, 'the owner service role can confirm coverage');
select is(
  has_table_privilege('authenticated', 'public.organization_billing_receipts', 'select'),
  false, 'contractors cannot read package payments');
select ok(
  to_regclass('public.organization_payment_confirmations') is null
    and to_regclass('public.organization_billing_accounts') is null,
  'the old receipt-only payment tables are gone');

-- Fixtures -------------------------------------------------------------------------

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000004a1', 'P4 Billing Test', 'p4-billing-test', 'active');

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason,
  actor_owner_email
)
select '90000000-0000-0000-0000-0000000004a1', e.id, 'month', 14900, timestamptz '2026-07-01 00:00Z',
  'test_reset', 'P4 billing test agreement', 'owner@example.test'
from public.package_editions e
join public.packages p on p.id = e.package_id
where p.slug = 'test-package' and e.status = 'published';

create temporary table ids (name text primary key, id uuid);

-- Charges --------------------------------------------------------------------------

select throws_ok(
  $$select public.add_organization_billing_charge('90000000-0000-0000-0000-0000000004a1', 'owner@example.test', 'p4-charge-no-date')$$,
  '23514', null, 'the first charge needs its start date');

insert into ids
select 'august', (public.add_organization_billing_charge(
  '90000000-0000-0000-0000-0000000004a1', 'owner@example.test', 'p4-charge-august', date '2026-08-01'
) ->> 'charge_id')::uuid;

select results_eq(
  $$select period_start, period_end, amount_usd_cents from public.organization_billing_charges
    where id = (select id from ids where name = 'august')$$,
  $$values (date '2026-08-01', date '2026-08-31', 14900)$$,
  'a monthly charge covers one month at the agreed price');

select is(
  private.billing_period_end(date '2026-01-31', date '2026-02-28', 'month'),
  date '2026-03-30',
  'a period anchored on the 31st does not drift after a short month');

-- $100 of $149 leaves $49 owed --------------------------------------------------------

insert into ids
select 'first_payment', (public.record_organization_billing_receipt(
  '90000000-0000-0000-0000-0000000004a1', date '2026-08-02', 10000, 'Bank transfer', 'TX-100',
  'owner@example.test', 'p4-receipt-100', null,
  jsonb_build_array(jsonb_build_object('charge_id', (select id from ids where name = 'august'), 'amount_usd_cents', 10000))
) ->> 'receipt_id')::uuid;

select is(
  (select c ->> 'outstanding_usd_cents' from jsonb_array_elements(
    public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'charges') c
   where c ->> 'id' = (select id::text from ids where name = 'august')),
  '4900', 'a $100 payment on a $149 period leaves $49 outstanding');
select is(
  (select c ->> 'status' from jsonb_array_elements(
    public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'charges') c
   where c ->> 'id' = (select id::text from ids where name = 'august')),
  'partly_paid', 'the period stays unpaid until its full amount is covered');
select throws_ok(
  $$select public.confirm_organization_billing_coverage('90000000-0000-0000-0000-0000000004a1',
    (select id from ids where name = 'august'), date '2026-08-01', date '2026-08-31', 'owner@example.test', 'p4-cover-too-early')$$,
  '23514', null, 'a partly paid period cannot be confirmed as covered');

-- Another $200 pays the period and leaves $151 credit -----------------------------------

insert into ids
select 'second_payment', (public.record_organization_billing_receipt(
  '90000000-0000-0000-0000-0000000004a1', date '2026-08-05', 20000, 'Wise', 'TX-200',
  'owner@example.test', 'p4-receipt-200'
) ->> 'receipt_id')::uuid;

select is(
  (public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'totals' ->> 'credit_usd_cents'),
  '20000', 'money recorded without an application waits as credit');

select public.apply_organization_billing_credit('90000000-0000-0000-0000-0000000004a1',
  (select id from ids where name = 'second_payment'), (select id from ids where name = 'august'), 4900,
  'owner@example.test', 'p4-apply-credit-49');

select results_eq(
  $$select (b -> 'totals' ->> 'outstanding_usd_cents')::int, (b -> 'totals' ->> 'credit_usd_cents')::int
    from public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') b$$,
  $$values (0, 15100)$$,
  'applying $49 pays the period and leaves $151 credit');
select is(
  (select paid_through_date from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000004a1'),
  null::date, 'paying a period does not move paid-through by itself');
select throws_ok(
  $$select public.apply_organization_billing_credit('90000000-0000-0000-0000-0000000004a1',
    (select id from ids where name = 'second_payment'), (select id from ids where name = 'august'), 100,
    'owner@example.test', 'p4-apply-over')$$,
  '23514', null, 'money cannot be applied beyond what a period owes');

-- Coverage is confirmed separately ---------------------------------------------------------

select throws_ok(
  $$select public.confirm_organization_billing_coverage('90000000-0000-0000-0000-0000000004a1',
    (select id from ids where name = 'august'), date '2026-08-01', date '2026-09-01', 'owner@example.test', 'p4-cover-wrong-dates')$$,
  'P0409', null, 'coverage is refused when the confirmed dates differ from the period');

select is(
  (public.confirm_organization_billing_coverage('90000000-0000-0000-0000-0000000004a1',
    (select id from ids where name = 'august'), date '2026-08-01', date '2026-08-31', 'owner@example.test', 'p4-cover-august')
   ->> 'paid_through_date'),
  '2026-08-31', 'confirming coverage moves paid-through to the end of the period');
select is(
  (public.confirm_organization_billing_coverage('90000000-0000-0000-0000-0000000004a1',
    (select id from ids where name = 'august'), date '2026-08-01', date '2026-08-31', 'owner@example.test', 'p4-cover-august')
   ->> 'applied'),
  'false', 'repeating the same confirmation changes nothing');
select results_eq(
  $$select period_start, period_end, amount_usd_cents from public.organization_billing_charges
    where organization_id = '90000000-0000-0000-0000-0000000004a1' order by period_start desc limit 1$$,
  $$values (date '2026-09-01', date '2026-09-30', 14900)$$,
  'confirming coverage adds the next period''s charge');
select is(
  (select count(*)::int from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000004a1' and event_kind = 'coverage_confirmed'),
  1, 'the confirmation is in the commercial history');
select throws_ok(
  $$select public.void_organization_billing_record('90000000-0000-0000-0000-0000000004a1', 'charge',
    (select id from ids where name = 'august'), 'Try to cancel', 'owner@example.test', 'p4-void-covered')$$,
  '23514', null, 'a covered period cannot be cancelled');

-- Corrections sit beside the original ---------------------------------------------------------

insert into ids
select 'corrected_payment', (public.correct_organization_billing_receipt(
  '90000000-0000-0000-0000-0000000004a1', (select id from ids where name = 'first_payment'), date '2026-08-02',
  9000, 'Bank transfer', 'TX-100', 'The bank showed $90, not $100.', 'owner@example.test', 'p4-correct-100'
) ->> 'receipt_id')::uuid;

select is(
  (select r ->> 'void_reason' from jsonb_array_elements(
    public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'receipts') r
   where r ->> 'id' = (select id::text from ids where name = 'first_payment')),
  'The bank showed $90, not $100.', 'the original payment stays visible with the correction reason');
select is(
  (select replaces_receipt_id from public.organization_billing_receipts where id = (select id from ids where name = 'corrected_payment')),
  (select id from ids where name = 'first_payment'), 'the corrected payment names the one it replaces');
select is(
  (select c ->> 'outstanding_usd_cents' from jsonb_array_elements(
    public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'charges') c
   where c ->> 'id' = (select id::text from ids where name = 'august')),
  '1000', 'the corrected payment is re-applied to the same period as far as it reaches');
select is(
  (select paid_through_date from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000004a1'),
  date '2026-08-31', 'a money correction does not change coverage');

-- Refunds come only from unapplied money ----------------------------------------------------------

select throws_ok(
  $$select public.record_organization_billing_refund('90000000-0000-0000-0000-0000000004a1',
    (select id from ids where name = 'second_payment'), date '2026-08-06', 15200, 'Wise', 'Too much', 'owner@example.test', 'p4-refund-too-much')$$,
  '23514', null, 'a refund cannot exceed the payment''s unapplied money');
select public.record_organization_billing_refund('90000000-0000-0000-0000-0000000004a1',
  (select id from ids where name = 'second_payment'), date '2026-08-06', 5000, 'Wise', 'Customer asked for $50 back',
  'owner@example.test', 'p4-refund-50');
select is(
  (public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'totals' ->> 'credit_usd_cents'),
  '10100', 'a refund reduces the credit');
select throws_ok(
  $$select public.void_organization_billing_record('90000000-0000-0000-0000-0000000004a1', 'receipt',
    (select id from ids where name = 'second_payment'), 'Try', 'owner@example.test', 'p4-void-refunded')$$,
  '23514', null, 'a refunded payment cannot be cancelled until its refund is');

-- Removing an application returns the money to credit ------------------------------------------------

select public.void_organization_billing_record('90000000-0000-0000-0000-0000000004a1', 'application',
  (select id from public.organization_billing_applications where idempotency_key = 'p4-apply-credit-49'),
  'Applied to the wrong period', 'owner@example.test', 'p4-void-application');
select results_eq(
  $$select (b -> 'totals' ->> 'credit_usd_cents')::int, (b -> 'totals' ->> 'outstanding_usd_cents')::int
    from public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') b$$,
  $$values (15000, 5900 + 14900)$$,
  'a removed application returns its money to credit and the period owes it again');

-- Cancelling the latest unpaid charge, and append-only records ------------------------------------------

select lives_ok(
  $$select public.void_organization_billing_record('90000000-0000-0000-0000-0000000004a1', 'charge',
    (select id from public.organization_billing_charges where idempotency_key = 'p4-cover-august:next'),
    'Customer is leaving', 'owner@example.test', 'p4-void-september')$$,
  'the latest unpaid charge can be cancelled with a reason');
select is(
  (select c ->> 'status' from jsonb_array_elements(
    public.owner_organization_billing('90000000-0000-0000-0000-0000000004a1') -> 'charges') c
   where c ->> 'period_start' = '2026-09-01'),
  'cancelled', 'the cancelled charge stays in the history');
select throws_ok(
  $$update public.organization_billing_receipts set amount_usd_cents = 1 where id = (select id from ids where name = 'second_payment')$$,
  '23514', null, 'payments cannot be edited');
select throws_ok(
  $$delete from public.organization_billing_charges where id = (select id from ids where name = 'august')$$,
  '23514', null, 'charges cannot be deleted');
select throws_ok(
  $$select public.record_organization_billing_receipt('90000000-0000-0000-0000-0000000004a1',
    current_date + 2, 100, 'Cash', 'future', 'owner@example.test', 'p4-receipt-future')$$,
  '23514', null, 'a payment cannot be dated in the future');

-- A reasoned paid-through correction is its own action ---------------------------------------------------

select is(
  (public.adjust_organization_paid_through('90000000-0000-0000-0000-0000000004a1', date '2026-08-15',
    'Service stopped mid-month', 'owner@example.test', 'p4-adjust-paid-through') ->> 'paid_through_date'),
  '2026-08-15', 'Jafar can correct paid-through with a reason');

select * from finish();
rollback;
