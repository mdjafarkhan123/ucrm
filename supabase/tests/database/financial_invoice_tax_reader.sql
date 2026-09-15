-- CRM launch readiness, financial reconciliation Part 2: frozen Invoice tax reader.
begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

select is(has_function_privilege(
  'anon', 'public.financial_invoice_tax_page(uuid,date,date,date,uuid,integer,text)', 'execute'
), false, 'signed-out callers cannot reach the tax ledger');
select is(has_function_privilege(
  'authenticated', 'public.financial_invoice_tax_page(uuid,date,date,date,uuid,integer,text)', 'execute'
), true, 'signed-in members can reach the checked tax ledger');
select is(has_function_privilege(
  'anon', 'public.financial_invoice_tax_summary(uuid,date,date)', 'execute'
), false, 'signed-out callers cannot reach the tax summary');

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tax-owner@example.test', 'test', now(), now(), now()),
  ('b1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tax-limited@example.test', 'test', now(), now(), now()),
  ('b1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'tax-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('b2000000-0000-0000-0000-000000000001', 'Tax Reader A', 'tax-reader-a', 'active'),
  ('b2000000-0000-0000-0000-000000000002', 'Tax Reader B', 'tax-reader-b', 'active');
insert into public.organization_members (organization_id, user_id, role) values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'owner'),
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'field'),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000003', 'owner');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state, access_scope)
values ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002',
  'invoices.view', 'grant', 'all');

insert into public.clients (id, organization_id, display_name, company_name, client_type) values
  ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
   'Frozen Tax Client', 'Frozen Tax Co', 'company'),
  ('b3000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002',
   'Other Tax Client', null, 'person');

insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  document_frozen_at, due_date_source, issue_date, due_date, issued_at, issue_method, recognized_at,
  voided_at, void_reason, root_invoice_id, tax_source, tax_name, tax_rate_basis_points,
  subtotal_minor, discount_minor, tax_minor, total_minor
)
values
  ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 1, 'Taxed issue', 'USD',
   '{"display_name":"Frozen Tax Client","company_name":"Frozen Tax Co"}', now(), 'custom',
   '2026-09-01', '2026-09-15', now(), 'marked_sent', null, null, null,
   'b4000000-0000-0000-0000-000000000001', 'custom', 'Sales tax', 1000, 10000, 0, 1000, 11000),
  ('b4000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 2, 'No-tax issue', 'USD',
   '{"display_name":"Frozen Tax Client","company_name":"Frozen Tax Co"}', now(), 'custom',
   '2026-09-02', '2026-09-16', now(), 'marked_sent', null, null, null,
   'b4000000-0000-0000-0000-000000000002', 'no_tax', null, 0, 20000, 0, 0, 20000),
  ('b4000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 3, 'Paid draft tax', 'USD',
   '{"display_name":"Frozen Tax Client","company_name":"Frozen Tax Co"}', now(), 'custom',
   '2026-09-03', '2026-09-17', null, null, now(), null, null,
   'b4000000-0000-0000-0000-000000000003', 'custom', 'Sales tax', 500, 30000, 0, 1500, 31500),
  ('b4000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 4, 'Voided tax', 'USD',
   '{"display_name":"Frozen Tax Client"}', now(), 'custom', '2026-09-04', '2026-09-18',
   now(), 'marked_sent', null, now(), 'created_in_error',
   'b4000000-0000-0000-0000-000000000004', 'custom', 'Sales tax', 1000, 40000, 0, 4000, 44000),
  ('b4000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 5, 'Unrecognized draft tax', 'USD',
   '{"display_name":"Frozen Tax Client"}', null, 'custom', '2026-09-05', '2026-09-19',
   null, null, null, null, null,
   'b4000000-0000-0000-0000-000000000005', 'custom', 'Sales tax', 1000, 50000, 0, 5000, 55000),
  ('b4000000-0000-0000-0000-000000000006', 'b2000000-0000-0000-0000-000000000002',
   'b3000000-0000-0000-0000-000000000002', 1, 'Other tenant tax', 'USD',
   '{"display_name":"Other Tax Client"}', now(), 'custom', '2026-09-01', '2026-09-15',
   now(), 'marked_sent', null, null, null,
   'b4000000-0000-0000-0000-000000000006', 'custom', 'Other tax', 1000, 90000, 0, 9000, 99000);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);

select is((select count(*)::integer from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05'
)), 3, 'only effective current invoices in this tenant and date window are returned');
select is((select string_agg(subject, ', ' order by tax_date, invoice_id)
  from public.financial_invoice_tax_page(
    'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05'
  )), 'Taxed issue, No-tax issue, Paid draft tax', 'tax rows have deterministic business-date order');
select results_eq($$ select net_sales_minor, tax_minor, billed_total_minor, invoice_count, taxed_invoice_count
  from public.financial_invoice_tax_summary(
    'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05'
  ) $$, $$ values (60000::bigint, 2500::bigint, 62500::bigint, 3::bigint, 2::bigint) $$,
  'summary reconciles frozen net sales, tax, totals and row counts');
select results_eq($$ select tax_source, tax_name, tax_rate_basis_points, tax_minor
  from public.financial_invoice_tax_page(
    'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-02'
  ) $$, $$ values ('custom'::text, 'Sales tax'::text, 1000, 1000::bigint) $$,
  'the ledger exposes the Invoice frozen tax identity and amount');
select is((select client_display_name from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-02'
)), 'Frozen Tax Client', 'customer identity comes from the frozen Invoice snapshot');
select is((select recognition_basis from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-03', '2026-09-04'
)), 'paid_draft', 'a fully paid Draft is disclosed without pretending it was issued');
select is((select count(*)::integer from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-04'
)), 2, 'the start is inclusive and end is exclusive');
select is((select subject from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05',
  '2026-09-01', 'b4000000-0000-0000-0000-000000000001', 1, 'asc'
)), 'No-tax issue', 'the keyset cursor resumes after the exact tax date and Invoice id');
select is((select string_agg(subject, ', ' order by row_number) from (
  select subject, row_number() over () from public.financial_invoice_tax_page(
    'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05', null, null, 10, 'desc'
  )
) ordered), 'Paid draft tax, No-tax issue, Taxed issue', 'descending order is deterministic');
select throws_ok($$ select * from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-05', '2026-09-05'
) $$, '22023', null, 'an invalid date window is refused');
select throws_ok($$ select * from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05', '2026-09-01', null
) $$, '22023', null, 'a partial page marker is refused');

select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select throws_ok($$ select * from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05'
) $$, '42501', null, 'Invoice visibility without price visibility cannot expose tax rows');
select throws_ok($$ select * from public.financial_invoice_tax_summary(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05'
) $$, '42501', null, 'Invoice visibility without price visibility cannot expose tax totals');

select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000003', true);
select results_eq($$ select tax_minor from public.financial_invoice_tax_summary(
  'b2000000-0000-0000-0000-000000000002', '2026-09-01', '2026-09-05'
) $$, $$ values (9000::bigint) $$, 'the other tenant owner sees only their own tax');
select throws_ok($$ select * from public.financial_invoice_tax_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-05'
) $$, '42501', null, 'another tenant cannot read this tax ledger');

select * from finish();
rollback;
