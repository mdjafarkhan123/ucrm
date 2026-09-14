-- CRM launch readiness, financial reconciliation Part 2: billed-sales reader.
-- Run as one transaction. Every fixture is rolled back.

begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

select is(
  has_function_privilege(
    'anon', 'public.financial_invoice_sales_page(uuid,date,date,date,uuid,integer,text)', 'execute'
  ),
  false,
  'signed-out callers cannot reach the financial sales reader'
);
select is(
  has_function_privilege(
    'authenticated', 'public.financial_invoice_sales_page(uuid,date,date,date,uuid,integer,text)', 'execute'
  ),
  true,
  'signed-in members can reach the checked reader'
);
select is(
  has_function_privilege(
    'anon', 'public.financial_invoice_sales_summary(uuid,date,date)', 'execute'
  ),
  false,
  'signed-out callers cannot reach the financial sales summary'
);
select is(
  has_function_privilege(
    'authenticated', 'public.financial_invoice_sales_summary(uuid,date,date)', 'execute'
  ),
  true,
  'signed-in members can reach the checked summary'
);

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sales-reader-owner@example.test', 'test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sales-reader-limited@example.test', 'test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sales-reader-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('a2000000-0000-0000-0000-000000000001', 'Sales Reader A', 'sales-reader-a', 'active'),
  ('a2000000-0000-0000-0000-000000000002', 'Sales Reader B', 'sales-reader-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'owner'),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'field'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000003', 'owner');

-- This person may see an Invoice exists but may not see its money.
insert into public.organization_member_permission_overrides (
  organization_id, user_id, permission_key, override_state, access_scope
)
values (
  'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002',
  'invoices.view', 'grant', 'all'
);

insert into public.clients (id, organization_id, display_name, company_name, client_type)
values
  ('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
   'Frozen Customer', 'Frozen Company', 'company'),
  ('a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002',
   'Other Customer', null, 'person');

insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  document_frozen_at, due_date_source, issue_date, due_date, issued_at, issue_method, recognized_at,
  marked_received_at, written_off_at, voided_at, void_reason,
  tax_source, tax_name, tax_rate_basis_points, subtotal_minor, tax_minor, total_minor
)
values
  ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 1, 'Issued sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   '2026-09-01 12:00:00+00', 'custom', '2026-09-01', '2026-09-15', '2026-09-01 12:00:00+00',
   'marked_sent', null, null, null, null, null, 'custom', 'Tax', 1000, 10000, 1000, 11000),
  ('a4000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 2, 'Paid draft sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   '2026-09-02 12:00:00+00', 'custom', '2026-09-02', '2026-09-16', null,
   null, '2026-09-02 12:00:00+00', null, null, null, null, 'no_tax', null, 0, 20000, 0, 20000),
  ('a4000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 3, 'Written-off sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   '2026-09-03 12:00:00+00', 'custom', '2026-09-03', '2026-09-17', '2026-09-03 12:00:00+00',
   'marked_sent', null, null, '2026-09-10 12:00:00+00', null, null, 'custom', 'Tax', 1000,
   30000, 3000, 33000),
  ('a4000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 4, 'Legacy closure sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   '2026-09-04 12:00:00+00', 'custom', '2026-09-04', '2026-09-18', '2026-09-04 12:00:00+00',
   'marked_sent', null, '2026-09-11 12:00:00+00', null, null, null, 'custom', 'Tax', 1000,
   40000, 4000, 44000),
  ('a4000000-0000-0000-0000-000000000005', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 5, 'Voided sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   '2026-09-05 12:00:00+00', 'custom', '2026-09-05', '2026-09-19', '2026-09-05 12:00:00+00',
   'marked_sent', null, null, null, '2026-09-12 12:00:00+00', 'created_in_error', 'no_tax', null, 0,
   50000, 0, 50000),
  ('a4000000-0000-0000-0000-000000000006', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 6, 'Unrecognized draft', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   null, 'custom', '2026-09-05', '2026-09-19', null, null, null, null, null, null, null,
   'no_tax', null, 0, 60000, 0, 60000),
  ('a4000000-0000-0000-0000-000000000007', 'a2000000-0000-0000-0000-000000000001',
   'a3000000-0000-0000-0000-000000000001', 7, 'End-boundary sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000001","display_name":"Frozen Customer","company_name":"Frozen Company"}',
   '2026-09-06 12:00:00+00', 'custom', '2026-09-06', '2026-09-20', '2026-09-06 12:00:00+00',
   'marked_sent', null, null, null, null, null, 'no_tax', null, 0, 70000, 0, 70000),
  ('a4000000-0000-0000-0000-000000000008', 'a2000000-0000-0000-0000-000000000002',
   'a3000000-0000-0000-0000-000000000002', 1, 'Other tenant sale', 'USD',
   '{"client_id":"a3000000-0000-0000-0000-000000000002","display_name":"Other Customer","company_name":null}',
   '2026-09-01 12:00:00+00', 'custom', '2026-09-01', '2026-09-15', '2026-09-01 12:00:00+00',
   'marked_sent', null, null, null, null, null, 'no_tax', null, 0, 99000, 0, 99000);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
  )),
  4,
  'only current sales in this tenant and date window are returned'
);
select is(
  (select string_agg(subject, ', ' order by sale_date, invoice_id) from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
  )),
  'Issued sale, Paid draft sale, Written-off sale, Legacy closure sale',
  'ascending order is deterministic'
);
select results_eq(
  $$ select sum(net_sales_minor), sum(tax_minor), sum(total_minor)
     from public.financial_invoice_sales_page(
       'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
     ) $$,
  $$ values (100000::numeric, 8000::numeric, 108000::numeric) $$,
  'net sales, tax and billed total reconcile from the same frozen Invoice rows'
);
select is(
  (select recognition_basis from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03'
  )),
  'paid_draft',
  'a Draft recognized by full payment is a sale without pretending it was issued'
);
select isnt(
  (select written_off_at from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-03', '2026-09-04'
  )),
  null,
  'a write-off remains part of billed sales and is disclosed'
);
select is(
  (select has_unsettled_legacy_closure from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-04', '2026-09-05'
  )),
  true,
  'a historical status-only closure is called out as a reconciliation exception'
);
select is(
  (select count(*)::integer from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-04'
  )),
  2,
  'the start date is inclusive and the end date is exclusive'
);
select is(
  (select min(subject) from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06',
    '2026-09-02', 'a4000000-0000-0000-0000-000000000002'
  )),
  'Legacy closure sale',
  'an ascending cursor resumes after its exact date and id'
);
select is(
  (select string_agg(subject, ', ' order by row_number) from (
    select subject, row_number() over () as row_number
    from public.financial_invoice_sales_page(
      'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06',
      null, null, 10, 'desc'
    )
  ) as ordered),
  'Legacy closure sale, Written-off sale, Paid draft sale, Issued sale',
  'descending order is deterministic too'
);
select is(
  (select count(*)::integer from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', null, null, 0
  )),
  1,
  'the database owns a nonzero page bound even for malformed limits'
);
select is(
  (select client_display_name from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-02'
  )),
  'Frozen Customer',
  'the report uses the Invoice customer snapshot rather than mutable live contact data'
);

select results_eq(
  $$ select net_sales_minor, tax_minor, billed_total_minor
     from public.financial_invoice_sales_summary(
       'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
     ) $$,
  $$ values (100000::bigint, 8000::bigint, 108000::bigint) $$,
  'whole-range summary money agrees with the current-sale rows rather than one page'
);
select results_eq(
  $$ select write_off_count, historical_status_only_closure_count
     from public.financial_invoice_sales_summary(
       'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
     ) $$,
  $$ values (1::bigint, 1::bigint) $$,
  'whole-range summary discloses write-offs and historical status-only closures separately'
);
select results_eq(
  $$ select net_sales_minor, tax_minor, billed_total_minor, write_off_count,
            historical_status_only_closure_count
     from public.financial_invoice_sales_summary(
       'a2000000-0000-0000-0000-000000000001', '2025-01-01', '2025-02-01'
     ) $$,
  $$ values (0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint) $$,
  'an empty period returns one zero-valued summary'
);
select results_eq(
  $$ select billed_total_minor
     from public.financial_invoice_sales_summary(
       'a2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-04'
     ) $$,
  $$ values (53000::bigint) $$,
  'summary uses an inclusive start and exclusive end date'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-06', '2026-09-06'
  ) $$,
  '22023', null, 'an empty or backwards date window is refused'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', '2026-09-02', null
  ) $$,
  '22023', null, 'a partial cursor is refused instead of paging ambiguously'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', null, null, 10, 'sideways'
  ) $$,
  '22023', null, 'an unknown report order is refused'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_summary(
    'a2000000-0000-0000-0000-000000000001', '2026-09-06', '2026-09-06'
  ) $$,
  '22023', null, 'the summary refuses an empty or backwards date window'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select * from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
  ) $$,
  '42501', null, 'Invoice visibility without price visibility cannot expose financial rows'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_summary(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
  ) $$,
  '42501', null, 'Invoice visibility without price visibility cannot expose financial totals'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000003', true);
select results_eq(
  $$ select billed_total_minor
     from public.financial_invoice_sales_summary(
       'a2000000-0000-0000-0000-000000000002', '2026-09-01', '2026-09-06'
     ) $$,
  $$ values (99000::bigint) $$,
  'the other tenant owner sees only their own summary'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_page(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
  ) $$,
  '42501', null, 'another tenant cannot read this organization report'
);
select throws_ok(
  $$ select * from public.financial_invoice_sales_summary(
    'a2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06'
  ) $$,
  '42501', null, 'another tenant cannot read this organization summary'
);

select * from finish();
rollback;
