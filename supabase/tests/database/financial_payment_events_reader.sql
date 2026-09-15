-- CRM launch readiness, financial reconciliation Part 2: payment-event reader.

begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

select is(has_function_privilege('anon',
  'public.financial_payment_events_page(uuid,date,date,date,uuid,integer,text)', 'execute'), false,
  'signed-out callers cannot reach payment events');
select is(has_function_privilege('authenticated',
  'public.financial_payment_events_page(uuid,date,date,date,uuid,integer,text)', 'execute'), true,
  'signed-in members can reach the checked payment reader');

set local role postgres;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'payment-reader-owner@example.test', 'test', now(), now(), now()),
  ('b1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'payment-reader-limited@example.test', 'test', now(), now(), now()),
  ('b1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'payment-reader-outsider@example.test', 'test', now(), now(), now());
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('b2000000-0000-0000-0000-000000000001', 'Payment Reader A', 'payment-reader-a', 'active'),
  ('b2000000-0000-0000-0000-000000000002', 'Payment Reader B', 'payment-reader-b', 'active');
insert into public.organization_members (organization_id, user_id, role) values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'owner'),
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'field'),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000003', 'owner');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state, access_scope)
values ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002',
  'invoices.view', 'grant', 'all');
insert into public.clients (id, organization_id, display_name, client_type) values
  ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'Cash Customer', 'person'),
  ('b3000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', 'Other Customer', 'person');
insert into public.client_payment_events
  (id, organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
   original_event_id, actor_user_id)
values
  ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 'received', 10000, 'USD', 'cash', '2026-09-01', null,
   'b1000000-0000-0000-0000-000000000001'),
  ('b4000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 'refunded', 3000, 'USD', 'cash', '2026-09-02',
   'b4000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001'),
  ('b4000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 'reversed', 3000, 'USD', null, '2026-09-03',
   'b4000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001'),
  ('b4000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 'received', 5000, 'USD', 'check', '2026-09-04', null,
   'b1000000-0000-0000-0000-000000000001'),
  ('b4000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-000000000001',
   'b3000000-0000-0000-0000-000000000001', 'reversed', 5000, 'USD', null, '2026-09-05',
   'b4000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000001'),
  ('b4000000-0000-0000-0000-000000000006', 'b2000000-0000-0000-0000-000000000002',
   'b3000000-0000-0000-0000-000000000002', 'received', 99000, 'USD', 'cash', '2026-09-01', null,
   'b1000000-0000-0000-0000-000000000003');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);
select is((select count(*)::integer from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06')), 5,
  'the requested tenant and date window are isolated');
select results_eq($$select cash_effect_minor from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06') order by event_date, event_id$$,
  $$values (10000::bigint), (-3000::bigint), (3000::bigint), (5000::bigint), (-5000::bigint)$$,
  'receipts refunds reversed refunds and reversed receipts have correct cash signs');
select results_eq($$select received_minor, refunded_minor, reversed_receipt_minor, reversed_refund_minor,
  cash_effect_minor, event_count from public.financial_payment_events_summary(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06')$$,
  $$values (15000::bigint, 3000::bigint, 5000::bigint, 3000::bigint, 10000::bigint, 5::bigint)$$,
  'whole-window totals reconcile every correction type');
select is((select event_id from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', null, null, 1)),
  'b4000000-0000-0000-0000-000000000001'::uuid, 'the page is hard bounded');
select is((select event_id from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', '2026-09-01',
  'b4000000-0000-0000-0000-000000000001', 1)), 'b4000000-0000-0000-0000-000000000002'::uuid,
  'the ascending cursor resumes after its exact date and id');
select is((select event_id from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', null, null, 1, 'desc')),
  'b4000000-0000-0000-0000-000000000005'::uuid, 'descending order is deterministic');
select is((select cash_effect_minor from public.financial_payment_events_summary(
  'b2000000-0000-0000-0000-000000000001', '2025-01-01', '2025-02-01')), 0::bigint,
  'an empty window has a zero summary');
select throws_ok($$select * from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-01')$$, '22023', null,
  'an invalid date window is refused');
select throws_ok($$select * from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', '2026-09-01', null)$$,
  '22023', null, 'a partial cursor is refused');
select throws_ok($$select * from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', null, null, 10, 'sideways')$$,
  '22023', null, 'an unknown order is refused');

select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select throws_ok($$select * from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06')$$, '42501', null,
  'Invoice visibility without amount visibility cannot expose payment rows');
select throws_ok($$select * from public.financial_payment_events_summary(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06')$$, '42501', null,
  'Invoice visibility without amount visibility cannot expose payment totals');

select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000003', true);
select is((select cash_effect_minor from public.financial_payment_events_summary(
  'b2000000-0000-0000-0000-000000000002', '2026-09-01', '2026-09-06')), 99000::bigint,
  'the other tenant owner sees only their own cash');
select throws_ok($$select * from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06')$$, '42501', null,
  'a member cannot choose another organization');

set local role postgres;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);
select matches((select indexdef from pg_indexes where schemaname = 'public'
  and indexname = 'client_payment_events_report_date_idx'),
  'organization_id, payment_date, id', 'the report predicate and keyset order have one matching index');
select is((select count(*)::integer from public.financial_payment_events_page(
  'b2000000-0000-0000-0000-000000000001', '2026-09-01', '2026-09-06', null, null, 0)), 1,
  'the database owns a nonzero lower page bound');

select * from finish();
rollback;
