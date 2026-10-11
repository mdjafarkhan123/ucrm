-- An invoice raised from a job starts with that job's tax instead of "not configured".
--
-- Reproduces the live gap found in the multi-industry proof (B12): a quote carried 8% tax into its job, the
-- job showed $486, and the invoice raised from it started at $450 with the tax left for the contractor to
-- re-enter by hand. Run the whole file as one transaction that is rolled back at the end, the same convention
-- the sibling invoice files document; a runner that executes each statement separately loses the role and
-- `set_config` switches.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- 1. Fixtures --------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'job-tax-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('e2000000-0000-0000-0000-000000000001', 'Job Tax Co', 'job-tax-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'owner');

insert into public.clients (id, organization_id, display_name)
values ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Job Tax Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000001', '1 Tax Row', 'Testville');

-- Job 1: 8% custom tax. Job 2: 5% custom tax. Job 3: no tax decision at all.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
  tax_source, tax_name, tax_rate_basis_points
) values
  ('e8000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
   'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 9501,
   'Eight percent job', 'one_off', 'job_total', 'USD', 'custom', 'Sales tax', 800),
  ('e8000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001',
   'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 9502,
   'Five percent job', 'one_off', 'job_total', 'USD', 'custom', 'Local tax', 500),
  ('e8000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000001',
   'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 9503,
   'Untaxed job', 'one_off', 'job_total', 'USD', 'not_configured', null, 0),
  ('e8000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-000000000001',
   'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 9504,
   'Chosen-by-hand job', 'one_off', 'job_total', 'USD', 'custom', 'Sales tax', 800),
  ('e8000000-0000-0000-0000-000000000005', 'e2000000-0000-0000-0000-000000000001',
   'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 9505,
   'Second eight percent job', 'one_off', 'job_total', 'USD', 'custom', 'Sales tax', 800),
  ('e8000000-0000-0000-0000-000000000006', 'e2000000-0000-0000-0000-000000000001',
   'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 9506,
   'Second five percent job', 'one_off', 'job_total', 'USD', 'custom', 'Local tax', 500);

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
) values
  ('e9000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Roof repair', 1, 45000, 0, true),
  ('e9000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Gutter work', 1, 20000, 0, true),
  ('e9000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000003', 0, 'priced', 'service', 'Inspection', 1, 10000, 0, true),
  ('e9000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000004', 0, 'priced', 'service', 'Flashing', 1, 30000, 0, true),
  ('e9000000-0000-0000-0000-000000000005', 'e2000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000005', 0, 'priced', 'service', 'Roof repair', 1, 45000, 0, true),
  ('e9000000-0000-0000-0000-000000000006', 'e2000000-0000-0000-0000-000000000001',
   'e8000000-0000-0000-0000-000000000006', 0, 'priced', 'service', 'Gutter work', 1, 20000, 0, true);

do $$ begin
  perform private.store_job_money('e8000000-0000-0000-0000-000000000001');
  perform private.store_job_money('e8000000-0000-0000-0000-000000000002');
  perform private.store_job_money('e8000000-0000-0000-0000-000000000003');
  perform private.store_job_money('e8000000-0000-0000-0000-000000000004');
  perform private.store_job_money('e8000000-0000-0000-0000-000000000005');
  perform private.store_job_money('e8000000-0000-0000-0000-000000000006');
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 2. A job with tax gives its invoice that tax ----------------------------------------------------------------

select public.create_invoice_from_work(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Roof repair',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Roof repair', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 45000, 'is_taxable', true)),
  array['e4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-10-31'::date, '2026-10-01'::date,
  jsonb_build_array(jsonb_build_object(
    'kind', 'job_total', 'job_id', 'e8000000-0000-0000-0000-000000000001')),
  'job-tax-idem-1', 'job-tax-hash-1'
);

set local role postgres;
select is(
  (select tax_source from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Roof repair'),
  'custom', 'the invoice takes the tax the job was quoted with'
);
set local role authenticated;

set local role postgres;
select is(
  (select tax_rate_basis_points from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Roof repair'),
  800, 'at the same rate'
);
set local role authenticated;

set local role postgres;
select is(
  (select tax_minor from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Roof repair'),
  3600::bigint, 'so the invoice charges $36 of tax on $450'
);
set local role authenticated;

set local role postgres;
select is(
  (select total_minor from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Roof repair'),
  48600::bigint, 'and totals $486, the figure the client approved'
);
set local role authenticated;

-- 3. A job with no tax decision leaves the invoice for the contractor to decide ---------------------------------

select public.create_invoice_from_work(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Inspection',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Inspection', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 10000, 'is_taxable', true)),
  array['e4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-10-31'::date, '2026-10-01'::date,
  jsonb_build_array(jsonb_build_object(
    'kind', 'job_total', 'job_id', 'e8000000-0000-0000-0000-000000000003')),
  'job-tax-idem-2', 'job-tax-hash-2'
);

set local role postgres;
select is(
  (select tax_source from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Inspection'),
  'not_configured', 'no tax on the job means no tax invented on the invoice'
);
set local role authenticated;

-- 4. Two jobs with different tax: the contractor chooses, nothing is guessed ----------------------------------

select public.create_invoice_from_work(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Two jobs',
  jsonb_build_array(
    jsonb_build_object('position', 0, 'name', 'Roof repair', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 45000, 'is_taxable', true),
    jsonb_build_object('position', 1, 'name', 'Gutter work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 20000, 'is_taxable', true)),
  array['e4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-10-31'::date, '2026-10-01'::date,
  jsonb_build_array(
    jsonb_build_object('kind', 'job_total', 'job_id', 'e8000000-0000-0000-0000-000000000005'),
    jsonb_build_object('kind', 'job_total', 'job_id', 'e8000000-0000-0000-0000-000000000006')),
  'job-tax-idem-3', 'job-tax-hash-3'
);

set local role postgres;
select is(
  (select tax_source from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Two jobs'),
  'not_configured', 'jobs taxed differently leave the invoice tax for the contractor to choose'
);
set local role authenticated;

-- 5. A tax choice already made on the invoice is never overwritten ---------------------------------------------

do $$
declare
  draft jsonb;
begin
  draft := public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Chosen by hand',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Flashing', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 30000, 'is_taxable', true)),
    array['e4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-10-31'::date, '2026-10-01'::date, 'job-tax-idem-4', 'job-tax-hash-4'
  );
  perform public.set_invoice_tax(
    'e2000000-0000-0000-0000-000000000001', (draft->>'invoice_id')::uuid, (draft->>'revision')::integer,
    'no_tax'
  );
  perform public.claim_invoice_sources(
    'e2000000-0000-0000-0000-000000000001', (draft->>'invoice_id')::uuid, (draft->>'revision')::integer + 1,
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', 'e8000000-0000-0000-0000-000000000004')),
    'job-tax-idem-5', 'job-tax-hash-5'
  );
end $$;

set local role postgres;
select is(
  (select tax_source from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Chosen by hand'),
  'no_tax', 'a contractor who chose no tax keeps that choice when work is added'
);
set local role authenticated;

set local role postgres;
select is(
  (select tax_minor from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Chosen by hand'),
  0::bigint, 'and is not charged tax'
);
set local role authenticated;

set local role postgres;
select is(
  (select count(*)::integer from public.invoices
   where organization_id = 'e2000000-0000-0000-0000-000000000001'),
  4, 'each bill above is one invoice'
);
set local role authenticated;

select * from finish();

rollback;
