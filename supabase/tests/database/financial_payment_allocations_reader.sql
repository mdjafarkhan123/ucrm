-- CRM launch readiness, financial reconciliation Part 2: payment-allocation ledger reader.

begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

select is(has_function_privilege('anon',
  'public.financial_payment_allocations_page(uuid,date,date,timestamptz,uuid,integer,text)', 'execute'), false,
  'signed-out callers cannot reach allocations');
select is(has_function_privilege('authenticated',
  'public.financial_payment_allocations_page(uuid,date,date,timestamptz,uuid,integer,text)', 'execute'), true,
  'signed-in members can reach the checked allocation reader');

set local role postgres;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'allocation-owner@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'allocation-limited@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'allocation-other@example.test', 'test', now(), now(), now());
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c2000000-0000-0000-0000-000000000001', 'Allocation Reader A', 'allocation-reader-a', 'active'),
  ('c2000000-0000-0000-0000-000000000002', 'Allocation Reader B', 'allocation-reader-b', 'active');
update public.organization_settings set timezone = 'Asia/Dhaka'
where organization_id = 'c2000000-0000-0000-0000-000000000001';
insert into public.organization_members (organization_id, user_id, role) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'owner'),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'field'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000003', 'owner');
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state, access_scope)
values ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002',
  'invoices.view', 'grant', 'all');
insert into public.clients (id, organization_id, display_name, company_name, client_type) values
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
   'Allocation Client', 'Allocation Co', 'company'),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000002',
   'Other Client', null, 'person');
insert into public.client_payment_events (
  id, organization_id, client_id, event_type, amount_minor, currency_code, method, payment_date, actor_user_id
) values
  ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
   'c3000000-0000-0000-0000-000000000001', 'received', 10000, 'USD', 'cash', '2026-09-01',
   'c1000000-0000-0000-0000-000000000001'),
  ('c4000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000002',
   'c3000000-0000-0000-0000-000000000002', 'received', 99000, 'USD', 'cash', '2026-09-01',
   'c1000000-0000-0000-0000-000000000003');
insert into public.invoice_payment_allocations (
  id, organization_id, invoice_id, invoice_number, client_id, entry_type, amount_minor, currency_code,
  payment_event_id, reversed_allocation_id, reason, actor_user_id, created_at
) values
  ('c5000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
   'c6000000-0000-0000-0000-000000000001', 41, 'c3000000-0000-0000-0000-000000000001',
   'applied', 6000, 'USD', 'c4000000-0000-0000-0000-000000000001', null, null,
   'c1000000-0000-0000-0000-000000000001', '2026-09-01 20:00:00+00'),
  ('c5000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001',
   'c6000000-0000-0000-0000-000000000001', 41, 'c3000000-0000-0000-0000-000000000001',
   'unapplied', 6000, 'USD', 'c4000000-0000-0000-0000-000000000001',
   'c5000000-0000-0000-0000-000000000001', 'Wrong invoice',
   'c1000000-0000-0000-0000-000000000001', '2026-09-02 01:00:00+00'),
  ('c5000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000002',
   'c6000000-0000-0000-0000-000000000002', 9, 'c3000000-0000-0000-0000-000000000002',
   'applied', 99000, 'USD', 'c4000000-0000-0000-0000-000000000002', null, null,
   'c1000000-0000-0000-0000-000000000003', '2026-09-01 20:00:00+00');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select is((select count(*)::integer from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')), 2,
  'the organization timezone controls the inclusive and exclusive calendar window');
select results_eq($$select allocation_effect_minor from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03') order by created_at$$,
  $$values (6000::bigint), (-6000::bigint)$$,
  'applications and unapplications carry opposite allocation effects');
select results_eq($$select applied_minor, unapplied_minor, net_allocated_minor, entry_count
  from public.financial_payment_allocations_summary(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  $$values (6000::bigint, 6000::bigint, 0::bigint, 2::bigint)$$,
  'whole-window allocation activity reconciles');
select is((select source_type from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03') limit 1),
  'payment', 'the source type is explicit');
select is((select reversed_allocation_id from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')
  where entry_type = 'unapplied'), 'c5000000-0000-0000-0000-000000000001'::uuid,
  'an unapplication retains its exact original allocation relationship');
select is((select allocation_id from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03', null, null, 1)),
  'c5000000-0000-0000-0000-000000000001'::uuid, 'the page is hard bounded');
select is((select allocation_id from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03',
  '2026-09-01 20:00:00+00', 'c5000000-0000-0000-0000-000000000001', 1)),
  'c5000000-0000-0000-0000-000000000002'::uuid, 'the ascending cursor resumes exactly');
select is((select allocation_id from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03', null, null, 1, 'desc')),
  'c5000000-0000-0000-0000-000000000002'::uuid, 'descending order is deterministic');
select throws_ok($$select * from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-02')$$,
  '22023', null, 'an invalid date window is refused');
select throws_ok($$select * from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03', now(), null)$$,
  '22023', null, 'a partial cursor is refused');

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select throws_ok($$select * from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  '42501', null, 'invoice visibility without amount visibility cannot expose allocations');
select throws_ok($$select * from public.financial_payment_allocations_summary(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  '42501', null, 'invoice visibility without amount visibility cannot expose totals');

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);
select is((select net_allocated_minor from public.financial_payment_allocations_summary(
  'c2000000-0000-0000-0000-000000000002', '2026-09-01', '2026-09-03')), 99000::bigint,
  'the other tenant owner sees only their allocations');
select throws_ok($$select * from public.financial_payment_allocations_page(
  'c2000000-0000-0000-0000-000000000001', '2026-09-02', '2026-09-03')$$,
  '42501', null, 'a member cannot choose another organization');

set local role postgres;
select matches((select indexdef from pg_indexes where schemaname = 'public'
  and indexname = 'invoice_payment_allocations_report_created_idx'),
  'organization_id, created_at, id', 'the report filter and keyset order have one matching index');

select * from finish();
rollback;
