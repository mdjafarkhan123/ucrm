-- A paid quote deposit reaches the invoice raised for that quote's work.
--
-- Reproduces the live gap found during online-payments Part 8: quote deposit paid, job converted, whole-job
-- bill raised — and the client asked to pay the deposit a second time. Written for `supabase test db`;
-- verified against the remote dev project by running this whole file as one transaction that is rolled back
-- at the end, the same convention the sibling invoice files document. Do not run it through a runner that
-- executes each statement separately: `set local role` and `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- 1. Fixtures --------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'deposit-bill-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('d2000000-0000-0000-0000-000000000001', 'Deposit Bill Co', 'deposit-bill-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'owner');

insert into public.clients (id, organization_id, display_name)
values ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'Deposit Bill Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', '1 Deposit Row', 'Testville');

-- The quote behind the work: $1,320 with a 25% deposit of $330, the live shape from the Part 8 run.
insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('d5000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 9401,
  'Deposit bill quote', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name
) values ('d6000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
  'd5000000-0000-0000-0000-000000000001', 1, 'USD', 'Deposit Bill Client', 'Deposit Bill Co');

insert into public.quote_deposit_events (
  id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key
) values ('d7000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
  'd5000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001',
  'received', 33000, 'stripe_card', 'deposit-bill-received');

-- The job that quote became, and a second job with no quote behind it at all.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
  quote_id, quote_version_id
) values (
  'd8000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 9402,
  'Quoted job', 'one_off', 'job_total', 'USD',
  'd5000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001'
);

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
) values (
  'd8000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 9403,
  'Unquoted job', 'one_off', 'job_total', 'USD'
);

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
) values
  ('d9000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
   'd8000000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Quoted work', 1, 120000, 0, false),
  ('d9000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
   'd8000000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Other work', 1, 50000, 0, false);

do $$ begin
  perform private.store_job_money('d8000000-0000-0000-0000-000000000001');
  perform private.store_job_money('d8000000-0000-0000-0000-000000000002');
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

-- 2. The deposit is spent on the bill for that quote's work --------------------------------------------------

select is(
  (public.create_invoice_from_work(
    'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'Quoted work',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Quoted work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 120000, 'is_taxable', false)),
    array['d4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-10-31'::date, '2026-10-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', 'd8000000-0000-0000-0000-000000000001')),
    'deposit-bill-idem-1', 'deposit-bill-hash-1'
  ))->>'deposit_applied_minor',
  '33000', 'billing the quoted job spends the deposit the client already paid'
);

select is(
  (select amount_minor from public.invoice_payment_allocations
   where organization_id = 'd2000000-0000-0000-0000-000000000001'
     and deposit_event_id = 'd7000000-0000-0000-0000-000000000001'),
  33000::bigint, 'the credit is one deposit-sourced allocation, not a payment'
);

select is(
  (select entry_type from public.invoice_payment_allocations
   where organization_id = 'd2000000-0000-0000-0000-000000000001'
     and deposit_event_id = 'd7000000-0000-0000-0000-000000000001'),
  'applied', 'the allocation is an application, so the invoice page shows Deposit applied'
);

-- The balance helpers are internal, so they are asserted from the owning role rather than as a member;
-- a member reaching them directly would be the bug, not the test.
set local role postgres;

select is(
  private.invoice_allocated_minor('d2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where organization_id = 'd2000000-0000-0000-0000-000000000001'
       and subject = 'Quoted work')),
  33000::bigint, 'the invoice counts the deposit against what it owes'
);

select is(
  private.deposit_event_available_minor('d2000000-0000-0000-0000-000000000001',
    'd7000000-0000-0000-0000-000000000001'),
  0::bigint, 'the deposit has nothing left to give once it is on a bill'
);

set local role authenticated;

select is(
  (select count(*)::integer from public.invoice_events
   where organization_id = 'd2000000-0000-0000-0000-000000000001'
     and event_type = 'invoice.payment_applied'),
  1, 'the application is on the invoice history like any other money movement'
);

-- 3. It happens once, not once per attempt --------------------------------------------------------------------

select is(
  (public.create_invoice_from_work(
    'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'Quoted work',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Quoted work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 120000, 'is_taxable', false)),
    array['d4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-10-31'::date, '2026-10-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', 'd8000000-0000-0000-0000-000000000001')),
    'deposit-bill-idem-1', 'deposit-bill-hash-1'
  ))->>'deposit_applied_minor',
  '33000', 'a doubled click replays the first answer rather than spending the deposit twice'
);

select is(
  (select count(*)::integer from public.invoice_payment_allocations
   where organization_id = 'd2000000-0000-0000-0000-000000000001'
     and deposit_event_id = 'd7000000-0000-0000-0000-000000000001'),
  1, 'the replay wrote no second credit'
);

-- 4. Work with no quote behind it gets no credit ----------------------------------------------------------------

select is(
  (public.create_invoice_from_work(
    'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'Other work',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Other work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 50000, 'is_taxable', false)),
    array['d4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-10-31'::date, '2026-10-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', 'd8000000-0000-0000-0000-000000000002')),
    'deposit-bill-idem-2', 'deposit-bill-hash-2'
  ))->>'deposit_applied_minor',
  '0', 'a job authored without a quote has no deposit to spend'
);

select is(
  (select count(*)::integer from public.invoice_payment_allocations
   where organization_id = 'd2000000-0000-0000-0000-000000000001'),
  1, 'and the unquoted bill borrowed no other quote''s deposit'
);

-- 5. A deposit larger than the bill is capped at what the bill owes ----------------------------------------------

set local role postgres;

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('d5000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 9404,
  'Overpaid quote', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name
) values ('d6000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
  'd5000000-0000-0000-0000-000000000002', 1, 'USD', 'Deposit Bill Client', 'Deposit Bill Co');

insert into public.quote_deposit_events (
  id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key
) values ('d7000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001',
  'd5000000-0000-0000-0000-000000000002', 'd6000000-0000-0000-0000-000000000002',
  'received', 90000, 'stripe_card', 'deposit-bill-received-large');

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
  quote_id, quote_version_id
) values (
  'd8000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 9405,
  'Overpaid job', 'one_off', 'job_total', 'USD',
  'd5000000-0000-0000-0000-000000000002', 'd6000000-0000-0000-0000-000000000002'
);

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
) values
  ('d9000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000001',
   'd8000000-0000-0000-0000-000000000003', 0, 'priced', 'service', 'Small job', 1, 30000, 0, false);

do $$ begin perform private.store_job_money('d8000000-0000-0000-0000-000000000003'); end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select is(
  (public.create_invoice_from_work(
    'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'Small job',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Small job', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 30000, 'is_taxable', false)),
    array['d4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-10-31'::date, '2026-10-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', 'd8000000-0000-0000-0000-000000000003')),
    'deposit-bill-idem-3', 'deposit-bill-hash-3'
  ))->>'deposit_applied_minor',
  '30000', 'a deposit bigger than the bill pays the bill off and no more'
);

set local role postgres;

select is(
  private.deposit_event_available_minor('d2000000-0000-0000-0000-000000000001',
    'd7000000-0000-0000-0000-000000000002'),
  60000::bigint, 'the rest of that deposit stays as the client''s credit for later'
);

select * from finish();
rollback;
