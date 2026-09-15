-- CRM launch readiness, financial reconciliation Part 2: deposit and available-credit reader.

begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

select is(has_function_privilege('anon',
  'public.financial_deposit_credits_page(uuid,date,date,timestamptz,uuid,integer,text)', 'execute'), false,
  'signed-out callers cannot reach deposits');
select is(has_function_privilege('authenticated',
  'public.financial_deposit_credits_page(uuid,date,date,timestamptz,uuid,integer,text)', 'execute'), true,
  'signed-in members can reach the checked deposit reader');

set local role postgres;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('d1100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'deposit-reader-owner@example.test', 'test', now(), now(), now()),
  ('d1100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'deposit-reader-limited@example.test', 'test', now(), now(), now()),
  ('d1100000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'deposit-reader-other@example.test', 'test', now(), now(), now());
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d1200000-0000-0000-0000-000000000001', 'Deposit Reader A', 'deposit-reader-a', 'active'),
  ('d1200000-0000-0000-0000-000000000002', 'Deposit Reader B', 'deposit-reader-b', 'active');
update public.organization_settings set timezone = 'Asia/Dhaka'
where organization_id = 'd1200000-0000-0000-0000-000000000001';
insert into public.organization_members (organization_id, user_id, role) values
  ('d1200000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000001', 'owner'),
  ('d1200000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000002', 'field'),
  ('d1200000-0000-0000-0000-000000000002', 'd1100000-0000-0000-0000-000000000003', 'owner');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state, access_scope)
values
  ('d1200000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000002',
   'invoices.view', 'grant', 'all'),
  ('d1200000-0000-0000-0000-000000000002', 'd1100000-0000-0000-0000-000000000003',
   'invoices.view', 'grant', 'all'),
  ('d1200000-0000-0000-0000-000000000002', 'd1100000-0000-0000-0000-000000000003',
   'invoices.view_price', 'grant', 'all');
insert into public.clients (id, organization_id, display_name, company_name, client_type) values
  ('d1300000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001',
   'Deposit Client', 'Deposit Co', 'company'),
  ('d1300000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000002',
   'Other Deposit Client', null, 'person');
insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('d1400000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001',
   'd1300000-0000-0000-0000-000000000001', '1 Credit Way', 'Dhaka'),
  ('d1400000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000002',
   'd1300000-0000-0000-0000-000000000002', '2 Credit Way', 'Dhaka');
insert into public.quotes
  (id, organization_id, client_id, property_id, quote_number, title, currency_code) values
  ('d1500000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001',
   'd1300000-0000-0000-0000-000000000001', 'd1400000-0000-0000-0000-000000000001', 41, 'Deposit A', 'USD'),
  ('d1500000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000002',
   'd1300000-0000-0000-0000-000000000002', 'd1400000-0000-0000-0000-000000000002', 9, 'Deposit B', 'USD');
insert into public.quote_versions
  (id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name) values
  ('d1600000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000001', 1, 'USD', 'Deposit Client', 'Deposit Reader A'),
  ('d1600000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000002',
   'd1500000-0000-0000-0000-000000000002', 1, 'USD', 'Other Deposit Client', 'Deposit Reader B');
insert into public.quote_deposit_events
  (id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, reversed_event_id,
   idempotency_key, actor_user_id, created_at) values
  ('d1700000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000001', 'd1600000-0000-0000-0000-000000000001',
   'received', 10000, 'cash', null, 'deposit-read-1', 'd1100000-0000-0000-0000-000000000001',
   '2026-09-01 20:00:00+00'),
  ('d1700000-0000-0000-0000-000000000002', 'd1200000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000001', 'd1600000-0000-0000-0000-000000000001',
   'received', 5000, 'check', null, 'deposit-read-2', 'd1100000-0000-0000-0000-000000000001',
   '2026-09-02 01:00:00+00'),
  ('d1700000-0000-0000-0000-000000000003', 'd1200000-0000-0000-0000-000000000001',
   'd1500000-0000-0000-0000-000000000001', 'd1600000-0000-0000-0000-000000000001',
   'reversed', 5000, 'check', 'd1700000-0000-0000-0000-000000000002', 'deposit-reverse-2',
   'd1100000-0000-0000-0000-000000000001', '2026-09-02 02:00:00+00'),
  ('d1700000-0000-0000-0000-000000000004', 'd1200000-0000-0000-0000-000000000002',
   'd1500000-0000-0000-0000-000000000002', 'd1600000-0000-0000-0000-000000000002',
   'received', 99000, 'cash', null, 'deposit-other-1', 'd1100000-0000-0000-0000-000000000003',
   '2026-09-01 20:00:00+00');
insert into public.client_payment_events
  (id, organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date,
   original_deposit_event_id, actor_user_id) values
  ('d1800000-0000-0000-0000-000000000001', 'd1200000-0000-0000-0000-000000000001',
   'd1300000-0000-0000-0000-000000000001', 'refunded', 3000, 'USD', 'cash', '2026-09-03',
   'd1700000-0000-0000-0000-000000000001', 'd1100000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select is((select count(*)::integer from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')), 3,
  'the organization timezone controls the activity window');
select results_eq($$select cash_effect_minor from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03') order by created_at$$,
  $$values (10000::bigint), (5000::bigint), (-5000::bigint)$$,
  'deposit receipts and reversals carry opposite cash effects');
select results_eq($$select refunded_minor, allocated_minor, available_credit_minor
  from public.financial_deposit_credits_page(
    'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')
  where event_id = 'd1700000-0000-0000-0000-000000000001'$$,
  $$values (3000::bigint, 0::bigint, 7000::bigint)$$,
  'a live receipt shows its refund and exact remaining credit');
select is((select available_credit_minor from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')
  where event_id = 'd1700000-0000-0000-0000-000000000002'), 0::bigint,
  'a reversed deposit has no available credit');
select results_eq($$select received_minor, reversed_minor, cash_effect_minor, refunded_minor,
  allocated_minor, available_credit_minor, event_count from public.financial_deposit_credits_summary(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  $$values (15000::bigint, 5000::bigint, 10000::bigint, 3000::bigint, 0::bigint, 7000::bigint, 3::bigint)$$,
  'whole-window cash and current credit totals reconcile');
select is((select event_id from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03', null, null, 1)),
  'd1700000-0000-0000-0000-000000000001'::uuid, 'the page is hard bounded');
select is((select event_id from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03',
  '2026-09-01 20:00:00+00', 'd1700000-0000-0000-0000-000000000001', 1)),
  'd1700000-0000-0000-0000-000000000002'::uuid, 'the ascending cursor resumes exactly');
select is((select event_id from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03', null, null, 1, 'desc')),
  'd1700000-0000-0000-0000-000000000003'::uuid, 'descending order is deterministic');
select throws_ok($$select * from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-02')$$,
  '22023', null, 'an invalid date window is refused');
select throws_ok($$select * from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03', now(), null)$$,
  '22023', null, 'a partial cursor is refused');

select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000002', true);
select throws_ok($$select * from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  '42501', null, 'Invoice visibility without amount visibility cannot expose deposits');
select throws_ok($$select * from public.financial_deposit_credits_summary(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  '42501', null, 'Invoice visibility without amount visibility cannot expose deposit totals');
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select is((select quote_number from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03') limit 1), 41,
  'deposit rows retain their traceable source Quote');
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000003', true);
select throws_ok($$select * from public.financial_deposit_credits_page(
  'd1200000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  '42501', null, 'a member cannot choose another organization');

set local role postgres;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select matches((select indexdef from pg_indexes where schemaname = 'public'
  and indexname = 'quote_deposit_events_report_created_idx'),
  'organization_id, created_at, id', 'the report filter and keyset order have one matching index');
select is((select cash_effect_minor from public.financial_deposit_credits_summary(
  'd1200000-0000-0000-0000-000000000001', '2025-01-01', '2025-02-01')), 0::bigint,
  'an empty window returns zero totals');

select * from finish();
rollback;
