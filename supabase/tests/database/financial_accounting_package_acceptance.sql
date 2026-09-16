-- CRM launch readiness, financial reconciliation Parts 3-4 and 6: accountant-package acceptance scenarios.
-- Run as one transaction. Every fixture is rolled back.
--
-- The contract's acceptance list in one seeded period: an unpaid and a partly paid Invoice, a discounted
-- taxable/non-taxable document, an unused and an applied deposit, a refund, a reversed mistaken receipt, a
-- moved allocation, a void, a correction/rebill chain, a write-off and its restore, a Mark Received closure,
-- rated and unrated labor, an expense, a completed uninvoiced Visit, a Pipeline Won value, (Part 4) a
-- mixed batch Invoice creation whose failed item is visible and safely retryable without duplicating
-- successful work, and (Part 6) one record traced end to end: Request -> Quote -> Job -> Invoice -> recorded
-- Payment, into the same readers the accountant CSV package writes from. Every earlier scenario proves one
-- stage in isolation; this is the only one that proves the identifiers actually chain together.
--
-- Each record is traced through the same paged reader the package writes its CSV from, and every
-- summary-versus-rows agreement check the reconciliation summary publishes is recomputed here. Cost and
-- tenant boundaries are checked too: a caller without jobs.view_cost gets null costs and no expense ledger,
-- never zeros, and another tenant gets nothing at all.

begin;

create extension if not exists pgtap with schema extensions;

select plan(76);

select is(
  has_function_privilege(
    'anon', 'public.financial_expenses_page(uuid,date,date,date,uuid,integer,text)', 'execute'
  ),
  false,
  'signed-out callers cannot reach the expense ledger'
);
select is(
  has_function_privilege(
    'authenticated', 'public.financial_expenses_page(uuid,date,date,date,uuid,integer,text)', 'execute'
  ),
  true,
  'signed-in members can reach the checked expense ledger'
);

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('ac110000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'package-owner@example.test', 'test', now(), now(), now()),
  ('ac110000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'package-cost-blind@example.test', 'test', now(), now(), now()),
  ('ac110000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'package-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('ac120000-0000-0000-0000-000000000001', 'Package A', 'package-a', 'active'),
  ('ac120000-0000-0000-0000-000000000002', 'Package B', 'package-b', 'active');

update public.organization_settings set timezone = 'Asia/Dhaka'
where organization_id in ('ac120000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000002');

insert into public.organization_members (organization_id, user_id, role)
values
  ('ac120000-0000-0000-0000-000000000001', 'ac110000-0000-0000-0000-000000000001', 'owner'),
  ('ac120000-0000-0000-0000-000000000001', 'ac110000-0000-0000-0000-000000000002', 'field'),
  ('ac120000-0000-0000-0000-000000000002', 'ac110000-0000-0000-0000-000000000003', 'owner');

-- This person may read invoice money and Job prices but holds no jobs.view_cost, so the package must drop
-- the cost columns and leave the expense ledger out rather than writing zeros.
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state, access_scope)
values
  ('ac120000-0000-0000-0000-000000000001', 'ac110000-0000-0000-0000-000000000002',
   'invoices.view', 'grant', 'all'),
  ('ac120000-0000-0000-0000-000000000001', 'ac110000-0000-0000-0000-000000000002',
   'invoices.view_price', 'grant', 'all'),
  ('ac120000-0000-0000-0000-000000000001', 'ac110000-0000-0000-0000-000000000002',
   'jobs.view_price', 'grant', 'all');

insert into public.clients (id, organization_id, display_name, company_name, client_type)
values ('ac130000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
        'Package Client', 'Package Co', 'company');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('ac140000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
        'ac130000-0000-0000-0000-000000000001', '1 Ledger Road', 'Dhaka');

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('ac150000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
        'ac130000-0000-0000-0000-000000000001', 'ac140000-0000-0000-0000-000000000001', 1,
        'Package Quote', 'USD');

insert into public.quote_versions
  (id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name)
values ('ac160000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
        'ac150000-0000-0000-0000-000000000001', 1, 'USD', 'Package Client', 'Package A');

-- Invoices: unpaid, void, superseded, write-off and Mark Received ------------------------------------
insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  issue_date, due_date, due_date_source, issued_at, issue_method, document_frozen_at,
  tax_source, subtotal_minor, tax_minor, total_minor, created_by
)
values
  ('ac170000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 1001, 'Unpaid invoice', 'USD',
   '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
   '2031-02-10', '2031-03-12', 'custom', '2031-02-10 12:00:00+06', 'sent', '2031-02-10 12:00:00+06',
   'no_tax', 100000, 0, 100000, 'ac110000-0000-0000-0000-000000000001'),
  ('ac170000-0000-0000-0000-000000000003', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 1003, 'Voided invoice', 'USD',
   '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
   '2031-04-01', '2031-05-01', 'custom', '2031-04-01 12:00:00+06', 'sent', '2031-04-01 12:00:00+06',
   'no_tax', 33000, 0, 33000, 'ac110000-0000-0000-0000-000000000001'),
  ('ac170000-0000-0000-0000-000000000004', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 1004, 'Superseded invoice', 'USD',
   '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
   '2031-05-01', '2031-06-01', 'custom', '2031-05-01 12:00:00+06', 'sent', '2031-05-01 12:00:00+06',
   'no_tax', 40000, 0, 40000, 'ac110000-0000-0000-0000-000000000001'),
  ('ac170000-0000-0000-0000-000000000006', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 1006, 'Written off invoice', 'USD',
   '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
   '2031-06-01', '2031-07-01', 'custom', '2031-06-01 12:00:00+06', 'sent', '2031-06-01 12:00:00+06',
   'no_tax', 20000, 0, 20000, 'ac110000-0000-0000-0000-000000000001'),
  ('ac170000-0000-0000-0000-000000000007', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 1007, 'Mark Received invoice', 'USD',
   '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
   '2031-07-01', '2031-08-01', 'custom', '2031-07-01 12:00:00+06', 'sent', '2031-07-01 12:00:00+06',
   'no_tax', 15000, 0, 15000, 'ac110000-0000-0000-0000-000000000001');

-- A discounted document with one taxable and one non-taxable line.
insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  issue_date, due_date, due_date_source, issued_at, issue_method, document_frozen_at,
  discount_name, discount_type, discount_value, discount_minor,
  tax_source, tax_name, tax_rate_basis_points, subtotal_minor, tax_minor, total_minor, created_by
)
values ('ac170000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
  'ac130000-0000-0000-0000-000000000001', 1002, 'Partly paid invoice', 'USD',
  '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
  '2031-03-05', '2031-04-04', 'custom', '2031-03-05 12:00:00+06', 'sent', '2031-03-05 12:00:00+06',
  'Spring discount', 'fixed', 5000, 5000, 'custom', 'Package VAT', 1000, 80000, 5000, 80000,
  'ac110000-0000-0000-0000-000000000001');

insert into public.invoice_lines
  (organization_id, invoice_id, position, name, quantity, unit_price_minor, is_taxable)
values
  ('ac120000-0000-0000-0000-000000000001', 'ac170000-0000-0000-0000-000000000002', 1,
   'Taxable service', 1, 50000, true),
  ('ac120000-0000-0000-0000-000000000001', 'ac170000-0000-0000-0000-000000000002', 2,
   'Non-taxable materials', 1, 30000, false);

-- The rebill carries its predecessor's root; the predecessor is then marked replaced.
insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  issue_date, due_date, due_date_source, issued_at, issue_method, document_frozen_at,
  tax_source, subtotal_minor, tax_minor, total_minor, root_invoice_id, predecessor_invoice_id,
  replacement_kind, created_by
)
values ('ac170000-0000-0000-0000-000000000005', 'ac120000-0000-0000-0000-000000000001',
  'ac130000-0000-0000-0000-000000000001', 1005, 'Rebill invoice', 'USD',
  '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
  '2031-05-02', '2031-06-02', 'custom', '2031-05-02 12:00:00+06', 'sent', '2031-05-02 12:00:00+06',
  'no_tax', 45000, 0, 45000, 'ac170000-0000-0000-0000-000000000004',
  'ac170000-0000-0000-0000-000000000004', 'rebill', 'ac110000-0000-0000-0000-000000000001');

update public.invoices
set replaced_at = '2031-05-02 12:05:00+06',
    replaced_by_invoice_id = 'ac170000-0000-0000-0000-000000000005',
    frozen_status_label = 'awaiting_payment'
where id = 'ac170000-0000-0000-0000-000000000004';

update public.invoices
set written_off_at = '2031-06-20 12:00:00+06',
    written_off_by = 'ac110000-0000-0000-0000-000000000001',
    write_off_note = 'Bad debt'
where id = 'ac170000-0000-0000-0000-000000000006';

update public.invoices
set marked_received_at = '2031-07-15 12:00:00+06',
    marked_received_by = 'ac110000-0000-0000-0000-000000000001'
where id = 'ac170000-0000-0000-0000-000000000007';

update public.invoices
set voided_at = '2031-04-02 12:00:00+06', void_reason = 'created_in_error'
where id = 'ac170000-0000-0000-0000-000000000003';

-- A Draft recognised by full payment.
insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  issue_date, due_date, due_date_source, recognized_at, document_frozen_at,
  tax_source, subtotal_minor, tax_minor, total_minor, created_by
)
values ('ac170000-0000-0000-0000-000000000008', 'ac120000-0000-0000-0000-000000000001',
  'ac130000-0000-0000-0000-000000000001', 1008, 'Paid draft invoice', 'USD',
  '{"display_name":"Package Client","company_name":"Package Co"}'::jsonb,
  '2031-08-01', '2031-09-01', 'custom', '2031-08-02 12:00:00+06', '2031-08-02 12:00:00+06',
  'no_tax', 25000, 0, 25000, 'ac110000-0000-0000-0000-000000000001');

-- Deposits: unused, applied, reversed and refunded ----------------------------------------------------
insert into public.quote_deposit_events
  (id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, reference,
   actor_user_id, reversed_event_id, idempotency_key, created_at)
values
  ('ac190000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
   'ac150000-0000-0000-0000-000000000001', 'ac160000-0000-0000-0000-000000000001',
   'received', 40000, 'cash', 'DEP-UNUSED', 'ac110000-0000-0000-0000-000000000001', null,
   'package-dep-unused', '2031-04-05 12:00:00+06'),
  ('ac190000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
   'ac150000-0000-0000-0000-000000000001', 'ac160000-0000-0000-0000-000000000001',
   'received', 15000, 'cash', 'DEP-APPLIED', 'ac110000-0000-0000-0000-000000000001', null,
   'package-dep-applied', '2031-04-06 12:00:00+06'),
  ('ac190000-0000-0000-0000-000000000003', 'ac120000-0000-0000-0000-000000000001',
   'ac150000-0000-0000-0000-000000000001', 'ac160000-0000-0000-0000-000000000001',
   'received', 12000, 'cash', 'DEP-ORIGINAL', 'ac110000-0000-0000-0000-000000000001', null,
   'package-dep-original', '2031-04-07 12:00:00+06'),
  ('ac190000-0000-0000-0000-000000000004', 'ac120000-0000-0000-0000-000000000001',
   'ac150000-0000-0000-0000-000000000001', 'ac160000-0000-0000-0000-000000000001',
   'reversed', 12000, 'cash', 'DEP-REVERSAL', 'ac110000-0000-0000-0000-000000000001',
   'ac190000-0000-0000-0000-000000000003', 'package-dep-reversal', '2031-04-08 12:00:00+06'),
  ('ac190000-0000-0000-0000-000000000005', 'ac120000-0000-0000-0000-000000000001',
   'ac150000-0000-0000-0000-000000000001', 'ac160000-0000-0000-0000-000000000001',
   'received', 18000, 'cash', 'DEP-REFUNDED', 'ac110000-0000-0000-0000-000000000001', null,
   'package-dep-refunded', '2031-04-09 12:00:00+06');

-- Cash: receipts, a refund, a reversed mistaken receipt and a deposit refund -------------------------
insert into public.client_payment_events
  (id, organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
   reference, actor_user_id, original_event_id, original_deposit_event_id, created_at)
values
  ('ac180000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'received', 20000, 'USD', 'bank_transfer', '2031-03-10',
   'R1', 'ac110000-0000-0000-0000-000000000001', null, null, '2031-03-10 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'received', 25000, 'USD', 'cash', '2031-08-02',
   'R-DRAFT', 'ac110000-0000-0000-0000-000000000001', null, null, '2031-08-02 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000003', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'received', 50000, 'USD', 'check', '2031-09-01',
   'R2', 'ac110000-0000-0000-0000-000000000001', null, null, '2031-09-01 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000004', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'refunded', 50000, 'USD', 'bank_transfer', '2031-09-15',
   'RF2', 'ac110000-0000-0000-0000-000000000001', 'ac180000-0000-0000-0000-000000000003', null,
   '2031-09-15 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000005', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'received', 30000, 'USD', 'cash', '2031-10-01',
   'R3', 'ac110000-0000-0000-0000-000000000001', null, null, '2031-10-01 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000006', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'reversed', 30000, 'USD', null, '2031-10-02',
   'RV3', 'ac110000-0000-0000-0000-000000000001', 'ac180000-0000-0000-0000-000000000005', null,
   '2031-10-02 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000007', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'received', 10000, 'USD', 'cash', '2031-11-01',
   'R4', 'ac110000-0000-0000-0000-000000000001', null, null, '2031-11-01 12:00:00+06'),
  ('ac180000-0000-0000-0000-000000000008', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'refunded', 18000, 'USD', 'bank_transfer', '2031-04-10',
   'RF-DEP', 'ac110000-0000-0000-0000-000000000001', null, 'ac190000-0000-0000-0000-000000000005',
   '2031-04-10 12:00:00+06');

-- Allocations, including money moved from one Invoice to another --------------------------------------
insert into public.invoice_payment_allocations
  (id, organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
   payment_event_id, deposit_event_id, reversed_allocation_id, reason, actor_user_id, created_at)
values
  ('ac1a0000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
   'ac170000-0000-0000-0000-000000000002', 1002, 'ac130000-0000-0000-0000-000000000001',
   'applied', 20000, 'USD', 'ac180000-0000-0000-0000-000000000001', null, null, null,
   'ac110000-0000-0000-0000-000000000001', '2031-03-10 13:00:00+06'),
  ('ac1a0000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
   'ac170000-0000-0000-0000-000000000008', 1008, 'ac130000-0000-0000-0000-000000000001',
   'applied', 25000, 'USD', 'ac180000-0000-0000-0000-000000000002', null, null, null,
   'ac110000-0000-0000-0000-000000000001', '2031-08-02 13:00:00+06'),
  ('ac1a0000-0000-0000-0000-000000000003', 'ac120000-0000-0000-0000-000000000001',
   'ac170000-0000-0000-0000-000000000001', 1001, 'ac130000-0000-0000-0000-000000000001',
   'applied', 10000, 'USD', 'ac180000-0000-0000-0000-000000000007', null, null, null,
   'ac110000-0000-0000-0000-000000000001', '2031-11-01 13:00:00+06'),
  ('ac1a0000-0000-0000-0000-000000000004', 'ac120000-0000-0000-0000-000000000001',
   'ac170000-0000-0000-0000-000000000001', 1001, 'ac130000-0000-0000-0000-000000000001',
   'unapplied', 10000, 'USD', 'ac180000-0000-0000-0000-000000000007', null,
   'ac1a0000-0000-0000-0000-000000000003', 'Moved to another invoice',
   'ac110000-0000-0000-0000-000000000001', '2031-11-02 13:00:00+06'),
  ('ac1a0000-0000-0000-0000-000000000005', 'ac120000-0000-0000-0000-000000000001',
   'ac170000-0000-0000-0000-000000000006', 1006, 'ac130000-0000-0000-0000-000000000001',
   'applied', 10000, 'USD', 'ac180000-0000-0000-0000-000000000007', null, null, null,
   'ac110000-0000-0000-0000-000000000001', '2031-11-02 14:00:00+06'),
  ('ac1a0000-0000-0000-0000-000000000006', 'ac120000-0000-0000-0000-000000000001',
   'ac170000-0000-0000-0000-000000000001', 1001, 'ac130000-0000-0000-0000-000000000001',
   'applied', 15000, 'USD', null, 'ac190000-0000-0000-0000-000000000002', null, null,
   'ac110000-0000-0000-0000-000000000001', '2031-04-06 13:00:00+06');

-- Jobs, labor, expense and an uninvoiced completed Visit ----------------------------------------------
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, status, price_basis,
  billing_timing, currency_code, subtotal_minor, tax_source, tax_name, tax_rate_basis_points,
  tax_minor, total_minor, cost_minor, closed_at, closed_by, created_by
)
values ('ac1b0000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
  'ac130000-0000-0000-0000-000000000001', 'ac140000-0000-0000-0000-000000000001', 1001,
  'Closed whole-price job', 'one_off', 'closed', 'job_total', 'on_closure', 'USD', 60000,
  'custom', 'Package VAT', 1000, 6000, 66000, 20000, '2031-06-15 12:00:00+06',
  'ac110000-0000-0000-0000-000000000001', 'ac110000-0000-0000-0000-000000000001');

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, status, price_basis,
  billing_timing, currency_code, subtotal_minor, tax_source, tax_minor, total_minor, cost_minor, created_by
)
values ('ac1b0000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
  'ac130000-0000-0000-0000-000000000001', 'ac140000-0000-0000-0000-000000000001', 1002,
  'Per-visit job', 'recurring', 'active', 'per_visit', 'per_completed_visit', 'USD', 12000,
  'no_tax', 0, 12000, 4000, 'ac110000-0000-0000-0000-000000000001');

insert into public.job_line_items
  (organization_id, job_id, position, name, quantity, unit_price_minor, unit_cost_minor, is_taxable, is_labor)
values
  ('ac120000-0000-0000-0000-000000000001', 'ac1b0000-0000-0000-0000-000000000001', 1,
   'Job service', 1, 60000, 20000, true, false),
  ('ac120000-0000-0000-0000-000000000001', 'ac1b0000-0000-0000-0000-000000000002', 1,
   'Visit service', 1, 12000, 4000, false, false);

-- The closed Job is already billed, so it is not uninvoiced work.
insert into public.invoice_sources
  (organization_id, root_invoice_id, client_id, source_kind, job_id, claimed_by)
values ('ac120000-0000-0000-0000-000000000001', 'ac170000-0000-0000-0000-000000000001',
  'ac130000-0000-0000-0000-000000000001', 'job_total', 'ac1b0000-0000-0000-0000-000000000001',
  'ac110000-0000-0000-0000-000000000001');

insert into public.job_visits
  (id, organization_id, job_id, position, visit_date, all_day, completed_at, completed_by)
values ('ac1c0000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
  'ac1b0000-0000-0000-0000-000000000002', 1, '2031-07-20', true, '2031-07-20 15:00:00+06',
  'ac110000-0000-0000-0000-000000000001');

insert into public.job_time_entries
  (id, organization_id, job_id, visit_id, user_id, started_at, minutes, cost_per_hour_minor, created_by)
values
  ('ac1d0000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
   'ac1b0000-0000-0000-0000-000000000001', null, 'ac110000-0000-0000-0000-000000000001',
   '2031-06-10 12:00:00+06', 120, 3000, 'ac110000-0000-0000-0000-000000000001'),
  ('ac1d0000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
   'ac1b0000-0000-0000-0000-000000000001', null, 'ac110000-0000-0000-0000-000000000001',
   '2031-06-11 12:00:00+06', 60, null, 'ac110000-0000-0000-0000-000000000001');

insert into public.job_expenses
  (id, organization_id, job_id, name, accounting_code, expense_date, total_minor, created_by)
values ('ac1e0000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
  'ac1b0000-0000-0000-0000-000000000001', 'Fuel', '5100', '2031-06-12', 5000,
  'ac110000-0000-0000-0000-000000000001');

insert into public.opportunities
  (id, organization_id, client_id, property_id, title, outcome, outcome_at, estimated_value, owner_user_id)
values
  ('ac1f0000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'ac140000-0000-0000-0000-000000000001',
   'Won opportunity', 'won', '2031-09-20 12:00:00+06', 900.00, 'ac110000-0000-0000-0000-000000000001'),
  ('ac1f0000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000001',
   'ac130000-0000-0000-0000-000000000001', 'ac140000-0000-0000-0000-000000000001',
   'Lost opportunity', 'lost', '2031-09-21 12:00:00+06', 400.00, 'ac110000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000001', true);

-- Billed sales ---------------------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  6,
  'the void and the superseded Invoice leave six current sales'
);
select results_eq(
  $$select invoice_number from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    order by invoice_number$$,
  $$values (1001), (1002), (1005), (1006), (1007), (1008)$$,
  'billed sales name every current Invoice and neither correction history row'
);
select results_eq(
  $$select coalesce(sum(net_sales_minor),0)::bigint, coalesce(sum(tax_minor),0)::bigint,
      coalesce(sum(total_minor),0)::bigint
    from public.financial_invoice_sales_page(
      'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)$$,
  $$values (280000::bigint, 5000::bigint, 285000::bigint)$$,
  'net sales, tax and billed total add up across the period'
);
select results_eq(
  $$select root_invoice_id, predecessor_invoice_id from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000005'$$,
  $$values ('ac170000-0000-0000-0000-000000000004'::uuid, 'ac170000-0000-0000-0000-000000000004'::uuid)$$,
  'the rebill stays inside its predecessor''s correction chain'
);
select isnt(
  (select written_off_at from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000006'),
  null,
  'a written-off sale stays a sale and carries its write-off stamp'
);
select is(
  (select has_unsettled_legacy_closure from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000007'),
  true,
  'a Mark Received closure is flagged as unsettled, not as cash'
);
select is(
  (select recognition_basis from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000008'),
  'paid_draft',
  'a Draft recognised by full payment is reported on that basis'
);
select results_eq(
  $$select net_sales_minor, tax_minor, total_minor from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000002'$$,
  $$values (75000::bigint, 5000::bigint, 80000::bigint)$$,
  'the discounted taxable and non-taxable document splits net sales from tax'
);
select results_eq(
  $$select write_off_count, historical_status_only_closure_count
    from public.financial_invoice_sales_summary(
      'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')$$,
  $$values (1::bigint, 1::bigint)$$,
  'the write-off and the status-only closure are both reported as exceptions'
);

-- Tax ------------------------------------------------------------------------------------------------
select is(
  (select coalesce(sum(tax_minor),0)::bigint from public.financial_invoice_tax_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  5000::bigint,
  'the tax ledger totals the period''s tax on its own'
);
select results_eq(
  $$select tax_rate_basis_points, tax_name from public.financial_invoice_tax_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000002'$$,
  $$values (1000, 'Package VAT'::text)$$,
  'the taxed Invoice traces back to its frozen rate and name'
);

-- Cash -----------------------------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  8,
  'every receipt, refund and reversal keeps its own row'
);
select is(
  (select coalesce(sum(cash_effect_minor),0)::bigint from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  37000::bigint,
  'corrected cash received is the signed total of the cash ledger'
);
select results_eq(
  $$select cash_effect_minor, original_event_type from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where event_id = 'ac180000-0000-0000-0000-000000000006'$$,
  $$values (-30000::bigint, 'received'::text)$$,
  'reversing a mistaken receipt removes it from corrected cash'
);
select is(
  (select cash_effect_minor from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where event_id = 'ac180000-0000-0000-0000-000000000004'),
  -50000::bigint,
  'a refund takes cash back out on its own date'
);
select is(
  (select count(*)::integer from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where event_type in ('refunded', 'reversed')),
  3,
  'the corrections-only ledger holds exactly the refunds and reversals'
);

-- Allocations ----------------------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.financial_payment_allocations_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  6,
  'each apply and unapply is its own allocation entry'
);
select is(
  (select coalesce(sum(allocation_effect_minor),0)::bigint from public.financial_payment_allocations_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  70000::bigint,
  'net allocated is what the Invoices actually hold'
);
select results_eq(
  $$select allocation_effect_minor, reversed_allocation_id
    from public.financial_payment_allocations_page(
      'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where allocation_id in ('ac1a0000-0000-0000-0000-000000000003', 'ac1a0000-0000-0000-0000-000000000004')
    order by allocation_effect_minor$$,
  $$values (-10000::bigint, 'ac1a0000-0000-0000-0000-000000000003'::uuid), (10000::bigint, null::uuid)$$,
  'moving money reverses the first allocation and leaves cash received untouched'
);
select results_eq(
  $$select source_type, source_event_id from public.financial_payment_allocations_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where allocation_id = 'ac1a0000-0000-0000-0000-000000000006'$$,
  $$values ('quote_deposit'::text, 'ac190000-0000-0000-0000-000000000002'::uuid)$$,
  'an applied deposit names the deposit it came from'
);

-- Deposits and remaining credit ----------------------------------------------------------------------
select is(
  (select count(*)::integer from public.financial_deposit_credits_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  5,
  'deposit receipts and reversals each keep a row'
);
select is(
  (select coalesce(sum(cash_effect_minor),0)::bigint from public.financial_deposit_credits_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  73000::bigint,
  'deposit cash effect nets the reversal out'
);
select is(
  (select available_credit_minor from public.financial_deposit_credits_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where event_id = 'ac190000-0000-0000-0000-000000000001'),
  40000::bigint,
  'an unused deposit is still available as customer credit'
);
select results_eq(
  $$select allocated_minor, available_credit_minor from public.financial_deposit_credits_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where event_id = 'ac190000-0000-0000-0000-000000000002'$$,
  $$values (15000::bigint, 0::bigint)$$,
  'an applied deposit shows what it paid and no credit left'
);
select results_eq(
  $$select refunded_minor, available_credit_minor from public.financial_deposit_credits_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where event_id = 'ac190000-0000-0000-0000-000000000005'$$,
  $$values (18000::bigint, 0::bigint)$$,
  'a refunded deposit shows what went back and no credit left'
);

-- Job profitability, labor and expenses --------------------------------------------------------------
select results_eq(
  $$select revenue_minor, item_cost_minor, labor_cost_minor, expense_cost_minor, total_cost_minor,
      profit_minor
    from public.financial_job_profitability_page(
      'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, 501)
    where job_id = 'ac1b0000-0000-0000-0000-000000000001'$$,
  $$values (60000::bigint, 20000::bigint, 6000::bigint, 5000::bigint, 31000::bigint, 29000::bigint)$$,
  'the closed Job pairs its revenue with item cost, rated labor and its expense'
);
select results_eq(
  $$select unrated_labor_count, unrated_labor_minutes from public.financial_job_profitability_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, 501)
    where job_id = 'ac1b0000-0000-0000-0000-000000000001'$$,
  $$values (1::bigint, 60::bigint)$$,
  'unrated hours are disclosed rather than costed at zero'
);
select results_eq(
  $$select is_unrated, cost_total_minor from public.financial_time_entries_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where entry_id = 'ac1d0000-0000-0000-0000-000000000001'$$,
  $$values (false, 6000::bigint)$$,
  'a rated time entry carries its own labor cost'
);
select results_eq(
  $$select is_unrated, cost_total_minor from public.financial_time_entries_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where entry_id = 'ac1d0000-0000-0000-0000-000000000002'$$,
  $$values (true, null::bigint)$$,
  'an unrated time entry leaves its cost blank, never zero'
);
select results_eq(
  $$select unrated_count, unrated_minutes, cost_total_minor from public.financial_time_entries_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')$$,
  $$values (1::bigint, 60::bigint, 6000::bigint)$$,
  'the labor summary separates unrated hours from costed hours'
);
select results_eq(
  $$select expense_id, total_minor, accounting_code, job_number from public.financial_expenses_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)$$,
  $$values ('ac1e0000-0000-0000-0000-000000000001'::uuid, 5000::bigint, '5100'::text, 1001)$$,
  'the expense traces to its Job with its accounting code'
);

-- Uninvoiced work ------------------------------------------------------------------------------------
select results_eq(
  $$select unit_kind, unit_id, uninvoiced_minor from public.financial_uninvoiced_work_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)$$,
  $$values ('visit'::text, 'ac1c0000-0000-0000-0000-000000000001'::uuid, 12000::bigint)$$,
  'the completed Visit is the only work still waiting to be billed'
);
select is(
  (select count(*)::integer from public.financial_uninvoiced_work_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where job_id = 'ac1b0000-0000-0000-0000-000000000001'),
  0,
  'a closed Job an Invoice already claimed is not uninvoiced work'
);

-- Pipeline outcomes ----------------------------------------------------------------------------------
select results_eq(
  $$select won_count, lost_count, won_value_minor from public.financial_sales_outcomes_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')$$,
  $$values (1::bigint, 1::bigint, 90000::bigint)$$,
  'Won and Lost outcomes are counted with the Won estimate kept separate from revenue'
);

-- The fifteen agreement checks the reconciliation summary publishes ----------------------------------
select is(
  (select net_sales_minor from public.financial_invoice_sales_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(net_sales_minor),0)::bigint from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'invoices_sales net sales agree with their rows'
);
select is(
  (select tax_minor from public.financial_invoice_sales_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(tax_minor),0)::bigint from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'invoices_sales tax agrees with its rows'
);
select is(
  (select billed_total_minor from public.financial_invoice_sales_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(total_minor),0)::bigint from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'invoices_sales billed total agrees with its rows'
);
select is(
  (select tax_minor from public.financial_invoice_tax_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(tax_minor),0)::bigint from public.financial_invoice_tax_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'invoice_tax agrees with its rows'
);
select is(
  (select cash_effect_minor from public.financial_payment_events_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(cash_effect_minor),0)::bigint from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'payment_events cash effect agrees with its rows'
);
select is(
  (select net_allocated_minor from public.financial_payment_allocations_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(allocation_effect_minor),0)::bigint from public.financial_payment_allocations_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'payment_allocations net allocated agrees with its rows'
);
select is(
  (select cash_effect_minor from public.financial_deposit_credits_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(cash_effect_minor),0)::bigint from public.financial_deposit_credits_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'deposits_credits cash effect agrees with its rows'
);
select is(
  (select outstanding_minor from public.financial_client_aging_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-12-31')),
  (select coalesce(sum(outstanding_minor),0)::bigint from public.financial_client_aging_page(
    'ac120000-0000-0000-0000-000000000001', '2031-12-31', null, null, 501)),
  'client_balances outstanding agrees with its rows'
);
select is(
  (select available_credit_minor from public.financial_client_aging_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-12-31')),
  (select coalesce(sum(available_credit_minor),0)::bigint from public.financial_client_aging_page(
    'ac120000-0000-0000-0000-000000000001', '2031-12-31', null, null, 501)),
  'client_balances available credit agrees with its rows'
);
select is(
  (select client_balance_minor from public.financial_client_aging_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-12-31')),
  (select coalesce(sum(client_balance_minor),0)::bigint from public.financial_client_aging_page(
    'ac120000-0000-0000-0000-000000000001', '2031-12-31', null, null, 501)),
  'client_balances client balance agrees with its rows'
);
select is(
  (select revenue_minor from public.financial_job_profitability_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(revenue_minor),0)::bigint from public.financial_job_profitability_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, 501)),
  'job_profitability revenue agrees with its rows'
);
select is(
  (select total_cost_minor from public.financial_job_profitability_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(total_cost_minor),0)::bigint from public.financial_job_profitability_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, 501)),
  'job_profitability total cost agrees with its rows'
);
select is(
  (select cost_total_minor from public.financial_time_entries_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(cost_total_minor),0)::bigint from public.financial_time_entries_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'time_entries cost agrees with its rows'
);
select is(
  (select uninvoiced_minor from public.financial_uninvoiced_work_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(uninvoiced_minor),0)::bigint from public.financial_uninvoiced_work_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'uninvoiced_work agrees with its rows'
);
select is(
  (select won_value_minor from public.financial_sales_outcomes_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  (select coalesce(sum(estimated_value_minor) filter (where outcome = 'won'), 0)::bigint
    from public.financial_sales_outcomes_page(
      'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)),
  'sales_outcomes Won value agrees with its Won rows'
);

-- Restoring a written-off sale -----------------------------------------------------------------------
set local role postgres;
update public.invoices set written_off_at = null, written_off_by = null, write_off_note = null
where id = 'ac170000-0000-0000-0000-000000000006';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000001', true);

select is(
  (select written_off_at from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000006'),
  null,
  'restoring a written-off sale clears its write-off stamp and keeps the sale'
);
select is(
  (select write_off_count from public.financial_invoice_sales_summary(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')),
  0::bigint,
  'restoring a write-off removes it from the reported exceptions'
);

-- Cost visibility and tenant boundaries --------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000002', true);
select results_eq(
  $$select revenue_minor, total_cost_minor, profit_minor from public.financial_job_profitability_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01', null, 501)
    where job_id = 'ac1b0000-0000-0000-0000-000000000001'$$,
  $$values (60000::bigint, null::bigint, null::bigint)$$,
  'a caller without job cost visibility sees prices but null costs, never zeros'
);
select throws_ok(
  $$select * from public.financial_expenses_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')$$,
  '42501', null, 'a caller without job cost visibility gets no expense ledger at all'
);

select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select * from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')$$,
  '42501', null, 'another tenant cannot read this organization''s sales'
);
select throws_ok(
  $$select * from public.financial_expenses_page(
    'ac120000-0000-0000-0000-000000000001', '2031-01-01', '2032-01-01')$$,
  '42501', null, 'another tenant cannot read this organization''s expenses'
);

-- Batch Invoice creation: a failed item stays visible, and retrying does not duplicate ----------------
-- Launch Part 4's mixed-batch scenario. create_invoices_in_batch is deliberately all-or-nothing (see
-- 20260908100000_invoice_batch_creation.sql): one bad job in a batch refuses the whole batch, so the good
-- job's work is never claimed and stays exactly as billable as before. A corrected retry then bills it
-- once, and neither a replay of that retry's own key nor a fresh attempt to rebill the same job can create
-- a second invoice for the same work -- the guarantee public.invoice_sources exists to hold.
set local role postgres;

-- One organization per user is enforced (organization_members_user_id_key), so the earlier package-owner
-- cannot also own this business; a fourth, dedicated user does.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('ac110000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'package-batch-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('ac120000-0000-0000-0000-000000000003', 'Package C', 'package-c', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('ac120000-0000-0000-0000-000000000003', 'ac110000-0000-0000-0000-000000000004', 'owner');

insert into public.clients (id, organization_id, display_name, company_name, client_type)
values ('ac130000-0000-0000-0000-000000000003', 'ac120000-0000-0000-0000-000000000003',
        'Batch Client', 'Batch Co', 'company');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('ac140000-0000-0000-0000-000000000003', 'ac120000-0000-0000-0000-000000000003',
        'ac130000-0000-0000-0000-000000000003', '3 Ledger Road', 'Dhaka');

-- The good job: one priced line, unclaimed. The bad job: no priced lines at all, which is exactly what
-- private.job_batch_billing_payload refuses a batch over.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, status, price_basis,
  currency_code, created_by
)
values
  ('ac1b0000-0000-0000-0000-000000000005', 'ac120000-0000-0000-0000-000000000003',
   'ac130000-0000-0000-0000-000000000003', 'ac140000-0000-0000-0000-000000000003', 2001,
   'Good job', 'one_off', 'active', 'job_total', 'USD', 'ac110000-0000-0000-0000-000000000004'),
  ('ac1b0000-0000-0000-0000-000000000006', 'ac120000-0000-0000-0000-000000000003',
   'ac130000-0000-0000-0000-000000000003', 'ac140000-0000-0000-0000-000000000003', 2002,
   'Bad job with nothing priced', 'one_off', 'active', 'job_total', 'USD',
   'ac110000-0000-0000-0000-000000000004');

insert into public.job_line_items
  (organization_id, job_id, position, name, quantity, unit_price_minor, is_taxable)
values ('ac120000-0000-0000-0000-000000000003', 'ac1b0000-0000-0000-0000-000000000005', 1,
        'Good service', 1, 50000, true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000004', true);

-- 1. A batch covering both jobs refuses outright: the bad job has nothing to bill, so nothing is billed.
select throws_ok(
  $$select public.create_invoices_in_batch(
    'ac120000-0000-0000-0000-000000000003',
    array['ac1b0000-0000-0000-0000-000000000005','ac1b0000-0000-0000-0000-000000000006']::uuid[],
    '{}'::uuid[], 'mixed-batch-attempt-1', 'mixed-batch-hash-1')$$,
  '23514', null, 'a batch with one unbillable job refuses the whole batch'
);
select is(
  (select count(*)::int from public.invoices where organization_id = 'ac120000-0000-0000-0000-000000000003'),
  0, 'the refused batch left the good job''s work unbilled, not half-billed'
);
select is(
  (select count(*)::int from public.invoice_sources
    where organization_id = 'ac120000-0000-0000-0000-000000000003'),
  0, 'the refused batch claimed nothing, so the good job stays visible to bill'
);

-- 2. A corrected retry -- the good job alone -- bills it exactly once.
select is(
  (public.create_invoices_in_batch(
    'ac120000-0000-0000-0000-000000000003',
    array['ac1b0000-0000-0000-0000-000000000005']::uuid[],
    '{}'::uuid[], 'mixed-batch-attempt-2', 'mixed-batch-hash-2'
  )->>'invoice_count'),
  '1', 'the corrected retry bills exactly the good job'
);
select is(
  (select count(*)::int from public.invoices where organization_id = 'ac120000-0000-0000-0000-000000000003'),
  1, 'exactly one invoice now exists for this business'
);
select is(
  (select count(*)::int from public.invoice_sources
    where organization_id = 'ac120000-0000-0000-0000-000000000003'
      and job_id = 'ac1b0000-0000-0000-0000-000000000005' and source_kind = 'job_total'),
  1, 'the good job is claimed exactly once'
);

-- 3. Replaying the same retry key never queues a second invoice.
select is(
  (public.create_invoices_in_batch(
    'ac120000-0000-0000-0000-000000000003',
    array['ac1b0000-0000-0000-0000-000000000005']::uuid[],
    '{}'::uuid[], 'mixed-batch-attempt-2', 'mixed-batch-hash-2'
  )->>'applied'),
  'false', 'replaying the same idempotency key reports it as already applied'
);
select is(
  (public.create_invoices_in_batch(
    'ac120000-0000-0000-0000-000000000003',
    array['ac1b0000-0000-0000-0000-000000000005']::uuid[],
    '{}'::uuid[], 'mixed-batch-attempt-2', 'mixed-batch-hash-2'
  )->'invoices'->0->>'invoice_id'),
  (select root_invoice_id::text from public.invoice_sources
    where organization_id = 'ac120000-0000-0000-0000-000000000003'
      and job_id = 'ac1b0000-0000-0000-0000-000000000005'),
  'the replay returns the very invoice the retry already created'
);
select is(
  (select count(*)::int from public.invoices where organization_id = 'ac120000-0000-0000-0000-000000000003'),
  1, 'replaying the key still leaves exactly one invoice behind'
);

-- 4. A brand new attempt to bill the same, already-claimed job is refused, not silently duplicated.
select throws_ok(
  $$select public.create_invoices_in_batch(
    'ac120000-0000-0000-0000-000000000003',
    array['ac1b0000-0000-0000-0000-000000000005']::uuid[],
    '{}'::uuid[], 'mixed-batch-attempt-3', 'mixed-batch-hash-3')$$,
  '23505', null, 'a fresh attempt to rebill an already-claimed job is refused outright'
);
select is(
  (select count(*)::int from public.invoices where organization_id = 'ac120000-0000-0000-0000-000000000003'),
  1, 'the refused fresh attempt still leaves exactly one invoice behind'
);

-- One record traced end to end: Request -> Quote -> Job -> Invoice -> recorded Payment --------------
-- Launch Part 6. Every scenario above proves one stage in isolation (an invoice, a payment, a job) with
-- fixtures built straight at that stage. This scenario instead chains one record through every FK the real
-- product uses -- quotes.request_id, jobs.quote_id, invoice_sources.job_id, invoice_payment_allocations ->
-- client_payment_events -- and reads it back out of the same package readers, closing the "does the whole
-- journey reconcile" half of the contract's acceptance list. A dedicated fourth organization keeps its
-- amounts out of every hardcoded total asserted above.
set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('ac110000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'package-journey-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('ac120000-0000-0000-0000-000000000004', 'Package D', 'package-d', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('ac120000-0000-0000-0000-000000000004', 'ac110000-0000-0000-0000-000000000005', 'owner');

insert into public.clients (id, organization_id, display_name, company_name, client_type)
values ('ac130000-0000-0000-0000-000000000004', 'ac120000-0000-0000-0000-000000000004',
        'Journey Client', 'Journey Co', 'company');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('ac140000-0000-0000-0000-000000000004', 'ac120000-0000-0000-0000-000000000004',
        'ac130000-0000-0000-0000-000000000004', '4 Ledger Road', 'Dhaka');

-- 1. Request: the customer's original ask.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
values ('ac210000-0000-0000-0000-000000000001', 'ac120000-0000-0000-0000-000000000004',
  'ac130000-0000-0000-0000-000000000004', 'ac140000-0000-0000-0000-000000000004',
  'Traced journey request', 'converted');

-- 2. Quote: carries the request it came from and, once accepted, becomes 'converted' itself.
insert into public.quotes (id, organization_id, client_id, property_id, request_id, quote_number, title,
  status, currency_code)
values ('ac150000-0000-0000-0000-000000000002', 'ac120000-0000-0000-0000-000000000004',
  'ac130000-0000-0000-0000-000000000004', 'ac140000-0000-0000-0000-000000000004',
  'ac210000-0000-0000-0000-000000000001', 1, 'Traced journey quote', 'converted', 'USD');

-- 3. Job: carries the quote it was created from, closed and ready to bill.
insert into public.jobs (
  id, organization_id, client_id, property_id, quote_id, job_number, title, job_type, status, price_basis,
  billing_timing, currency_code, subtotal_minor, tax_source, tax_minor, total_minor, cost_minor,
  closed_at, closed_by, created_by
)
values ('ac1b0000-0000-0000-0000-000000000007', 'ac120000-0000-0000-0000-000000000004',
  'ac130000-0000-0000-0000-000000000004', 'ac140000-0000-0000-0000-000000000004',
  'ac150000-0000-0000-0000-000000000002', 1001, 'Traced journey job', 'one_off', 'closed', 'job_total',
  'on_closure', 'USD', 70000, 'no_tax', 0, 70000, 25000,
  '2031-10-20 12:00:00+06', 'ac110000-0000-0000-0000-000000000005', 'ac110000-0000-0000-0000-000000000005');

-- 4. Invoice: bills exactly this job, and invoice_sources is the claim that proves it.
insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, customer_snapshot,
  issue_date, due_date, due_date_source, issued_at, issue_method, document_frozen_at,
  tax_source, subtotal_minor, tax_minor, total_minor, created_by
)
values ('ac170000-0000-0000-0000-000000000009', 'ac120000-0000-0000-0000-000000000004',
  'ac130000-0000-0000-0000-000000000004', 1001, 'Traced journey invoice', 'USD',
  '{"display_name":"Journey Client","company_name":"Journey Co"}'::jsonb,
  '2031-10-25', '2031-11-24', 'custom', '2031-10-25 12:00:00+06', 'sent', '2031-10-25 12:00:00+06',
  'no_tax', 70000, 0, 70000, 'ac110000-0000-0000-0000-000000000005');

insert into public.invoice_sources
  (organization_id, root_invoice_id, client_id, source_kind, job_id, claimed_by)
values ('ac120000-0000-0000-0000-000000000004', 'ac170000-0000-0000-0000-000000000009',
  'ac130000-0000-0000-0000-000000000004', 'job_total', 'ac1b0000-0000-0000-0000-000000000007',
  'ac110000-0000-0000-0000-000000000005');

-- 5. Payment: received and fully applied, so the journey ends with zero owed.
insert into public.client_payment_events
  (id, organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
   reference, actor_user_id, created_at)
values ('ac180000-0000-0000-0000-000000000009', 'ac120000-0000-0000-0000-000000000004',
  'ac130000-0000-0000-0000-000000000004', 'received', 70000, 'USD', 'bank_transfer', '2031-10-26',
  'TRACE-PAY', 'ac110000-0000-0000-0000-000000000005', '2031-10-26 12:00:00+06');

insert into public.invoice_payment_allocations
  (id, organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
   payment_event_id, actor_user_id, created_at)
values ('ac1a0000-0000-0000-0000-000000000007', 'ac120000-0000-0000-0000-000000000004',
  'ac170000-0000-0000-0000-000000000009', 1001, 'ac130000-0000-0000-0000-000000000004',
  'applied', 70000, 'USD', 'ac180000-0000-0000-0000-000000000009',
  'ac110000-0000-0000-0000-000000000005', '2031-10-26 13:00:00+06');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000005', true);

select is(
  (select status from public.requests where id = 'ac210000-0000-0000-0000-000000000001'),
  'converted', 'the traced request shows it produced a quote'
);
select is(
  (select request_id from public.quotes where id = 'ac150000-0000-0000-0000-000000000002'),
  'ac210000-0000-0000-0000-000000000001'::uuid, 'the quote carries the request it came from'
);
select is(
  (select quote_id from public.jobs where id = 'ac1b0000-0000-0000-0000-000000000007'),
  'ac150000-0000-0000-0000-000000000002'::uuid, 'the job carries the quote it was created from'
);
select is(
  (select job_id from public.invoice_sources where root_invoice_id = 'ac170000-0000-0000-0000-000000000009'),
  'ac1b0000-0000-0000-0000-000000000007'::uuid, 'the invoice claims the exact job it billed, not a guess'
);
select results_eq(
  $$select net_sales_minor, total_minor from public.financial_invoice_sales_page(
    'ac120000-0000-0000-0000-000000000004', '2031-01-01', '2032-01-01', null, null, 501)
    where invoice_id = 'ac170000-0000-0000-0000-000000000009'$$,
  $$values (70000::bigint, 70000::bigint)$$,
  'the sales reader bills the traced invoice for exactly the traced job''s total'
);
select is(
  (select cash_effect_minor from public.financial_payment_events_page(
    'ac120000-0000-0000-0000-000000000004', '2031-01-01', '2032-01-01', null, null, 501)
    where event_id = 'ac180000-0000-0000-0000-000000000009'),
  70000::bigint, 'the cash reader receives exactly the traced invoice''s total'
);
-- Money columns are deliberately outside the authenticated grant on invoices (see the grant note above); the
-- postgres role reads the source rows directly the same way "Restoring a written-off sale" does above.
set local role postgres;
select is(
  (select total_minor from public.invoices where id = 'ac170000-0000-0000-0000-000000000009'),
  (select amount_minor from public.invoice_payment_allocations
    where invoice_id = 'ac170000-0000-0000-0000-000000000009' and entry_type = 'applied'),
  'the traced payment applies exactly the invoice total, leaving zero owed'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac110000-0000-0000-0000-000000000005', true);

select results_eq(
  $$select revenue_minor, total_cost_minor from public.financial_job_profitability_page(
    'ac120000-0000-0000-0000-000000000004', '2031-01-01', '2032-01-01', null, 501)
    where job_id = 'ac1b0000-0000-0000-0000-000000000007'$$,
  $$values (70000::bigint, 25000::bigint)$$,
  'the profitability reader shows the traced job''s revenue and cost, not a recomputation'
);

select * from finish();
rollback;
