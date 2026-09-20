-- Online payments Part 9b: the list of a client's unspent money.
--
-- Verified against the remote dev project by running this whole file as one transaction that is rolled back
-- at the end, the same convention invoices_payments_ledger.sql documents. Do not run it through a runner
-- that executes each statement separately: `set local role` and `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select is(has_function_privilege('anon', 'public.client_spendable_credit(uuid, uuid)', 'execute'),
  false, 'signed-out callers cannot list a client''s credit');
select is(has_function_privilege('authenticated', 'public.client_spendable_credit(uuid, uuid)', 'execute'),
  true, 'members reach the credit list');

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('f9100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'credit-owner-a@example.test', 'test', now(), now(), now()),
  ('f9100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'credit-field-a@example.test', 'test', now(), now(), now()),
  ('f9100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'credit-owner-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f9200000-0000-0000-0000-000000000001', 'Credit Org A', 'credit-org-a', 'active'),
  ('f9200000-0000-0000-0000-000000000002', 'Credit Org B', 'credit-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('f9200000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000001', 'owner'),
  ('f9200000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000002', 'field'),
  ('f9200000-0000-0000-0000-000000000002', 'f9100000-0000-0000-0000-000000000003', 'owner');

insert into public.clients (id, organization_id, display_name, client_type)
values
  ('f9300000-0000-0000-0000-000000000001', 'f9200000-0000-0000-0000-000000000001', 'Credit Client One', 'person'),
  ('f9300000-0000-0000-0000-000000000002', 'f9200000-0000-0000-0000-000000000001', 'Credit Client Two', 'person');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, country)
values
  ('f9400000-0000-0000-0000-000000000001', 'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001', '1 Credit Lane', 'Testville', 'TX', '78741', 'United States');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f9100000-0000-0000-0000-000000000001', true);

select is((select count(*)::int from public.client_spendable_credit(
  'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001')),
  0, 'a client who has given nothing has no credit to list');

-- Two receipts with no bill named: both are loose credit.
select lives_ok(
  $$ select public.record_client_payment(
    'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001',
    20000, 'cash', '2026-09-11'::date, 'First', null, null, 'credit-idem-1', 'credit-hash-1') $$,
  'a receipt with no bill named is recorded as credit');
select lives_ok(
  $$ select public.record_client_payment(
    'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001',
    5000, 'cash', '2026-09-12'::date, 'Second', null, null, 'credit-idem-2', 'credit-hash-2') $$,
  'a second one is recorded too');

select is((select array_agg(available_minor order by reference)::text from public.client_spendable_credit(
  'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001')),
  '{20000,5000}', 'both receipts are listed with everything still left on them');

-- Spend part of the first one on a bill: the list shows only what remains.
select lives_ok(
  $$ select public.create_invoice_draft(
    'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001', 'Credit job',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 100000, 'is_taxable', false)),
    array['f9400000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-09-30'::date, '2026-09-10'::date, 'credit-idem-draft', 'credit-hash-draft') $$,
  'a bill exists to spend credit on');

select lives_ok(
  $$ select public.apply_client_payment(
    'f9200000-0000-0000-0000-000000000001',
    (select id from public.invoices where organization_id = 'f9200000-0000-0000-0000-000000000001' and subject = 'Credit job'),
    (select id from public.client_payment_events where organization_id = 'f9200000-0000-0000-0000-000000000001' and reference = 'First'),
    null, 8000, null, 'credit-idem-apply', 'credit-hash-apply') $$,
  'part of the first receipt goes onto the bill');

select is((select array_agg(available_minor order by reference)::text from public.client_spendable_credit(
  'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001')),
  '{12000,5000}', 'the list now shows what is left, not what came in');

select is((select count(*)::int from public.client_spendable_credit(
  'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000002')),
  0, 'another client''s credit is not in the list');

-- Who may ask.
select set_config('request.jwt.claim.sub', 'f9100000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$ select * from public.client_spendable_credit(
    'f9200000-0000-0000-0000-000000000001', 'f9300000-0000-0000-0000-000000000001') $$,
  '42501', null, 'a member of another organization cannot read this client''s credit');

select * from finish();
rollback;
