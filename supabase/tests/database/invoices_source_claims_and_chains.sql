-- Invoices, Part 3c: source claims, the rules that keep one piece of work on one bill, and the
-- correction/rebill chains that let a bill be replaced without ever letting the work be billed twice.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention invoices_refunds_and_closure.sql documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and `set_config`
-- do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(60);

-- 1. Privileges ----------------------------------------------------------------------------------------------

select is(has_function_privilege('anon',
  'public.claim_invoice_sources(uuid, uuid, integer, jsonb, text, text)', 'execute'),
  false, 'signed-out callers cannot claim work');
select is(has_function_privilege('authenticated',
  'public.claim_invoice_sources(uuid, uuid, integer, jsonb, text, text)', 'execute'),
  true, 'members reach the claim command');
select is(has_function_privilege('anon',
  'public.rebill_voided_invoice(uuid, uuid, text, text)', 'execute'),
  false, 'signed-out callers cannot rebill');
select is(has_function_privilege('anon',
  'public.prepare_invoice_correction(uuid, uuid, integer, text, text)', 'execute'),
  false, 'signed-out callers cannot correct a bill');
select is(has_function_privilege('anon',
  'public.activate_invoice_replacement(uuid, uuid, integer, bigint, text, text, text)', 'execute'),
  false, 'signed-out callers cannot activate a replacement');
select is(has_function_privilege('authenticated',
  'public.activate_invoice_replacement(uuid, uuid, integer, bigint, text, text, text)', 'execute'),
  true, 'members reach the activation command');

select is(has_table_privilege('authenticated', 'public.invoice_sources', 'select'),
  true, 'members may read what a bill covers');
select is(has_table_privilege('authenticated', 'public.invoice_sources', 'insert'),
  false, 'but they cannot write a claim directly');
select is(has_table_privilege('authenticated', 'public.invoice_sources', 'delete'),
  false, 'and they cannot delete one');
select is(
  (select relrowsecurity from pg_class where oid = 'public.invoice_sources'::regclass),
  true, 'claims are behind row level security');

-- 2. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'src-owner-a@example.test', 'test', now(), now(), now()),
  ('f1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'src-owner-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f2000000-0000-0000-0000-000000000001', 'Source Org A', 'source-org-a', 'active'),
  ('f2000000-0000-0000-0000-000000000002', 'Source Org B', 'source-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'owner'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000003', 'owner');

insert into public.clients (id, organization_id, display_name, client_type)
values
  ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Source Client One', 'person'),
  ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'Source Client Two', 'person'),
  ('f3000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000002', 'Other Org Client', 'person');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, country)
values
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', '1 Source Row', 'Testville', 'TX', '78741', 'United States'),
  ('f4000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002', '2 Source Row', 'Testville', 'TX', '78741', 'United States'),
  ('f4000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000003', '3 Source Row', 'Testville', 'TX', '78741', 'United States');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

-- Five jobs, one concern each, so no test has to reason about another test's claims.
select public.create_job_with_visits(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001', 'Whole job', null, false, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', '2026-08-10')),
  'src-idem-job-whole', 'src-hash-job-whole');

select public.create_job_with_visits(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001', 'Visit job', null, false, '[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('position', 0, 'visit_date', '2026-08-05'),
    jsonb_build_object('position', 1, 'visit_date', '2026-08-12')),
  'src-idem-job-visits', 'src-hash-job-visits');

select public.create_job_with_visits(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002',
  'f4000000-0000-0000-0000-000000000002', 'Period job', null, false, '[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('position', 0, 'visit_date', '2026-08-06'),
    jsonb_build_object('position', 1, 'visit_date', '2026-08-20'),
    jsonb_build_object('position', 2, 'visit_date', '2026-09-02')),
  'src-idem-job-period', 'src-hash-job-period');

select public.create_job_with_visits(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001', 'Progress job', null, false, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', '2026-08-14')),
  'src-idem-job-progress', 'src-hash-job-progress');

-- A stage, inserted directly and pre-locked, standing in for what `create_installment_invoice` does before
-- ever calling this claim command: this file tests the claim in isolation, not the handoff that locks it.
-- Written as postgres, the same way the per-visit reminder fixture below is: the point of both is what a
-- claim does with a row that already exists, not the route that would normally create one.
set local role postgres;
insert into public.job_payment_schedule_items (
  organization_id, job_id, position, description, value_type, value, locked_amount_minor
) values (
  'f2000000-0000-0000-0000-000000000001',
  (select id from public.jobs
   where organization_id = 'f2000000-0000-0000-0000-000000000001' and title = 'Progress job'),
  0, 'Deposit', 'fixed', 50000, 50000);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

select public.create_job_with_visits(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
  'f4000000-0000-0000-0000-000000000001', 'Chain job', null, false, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', '2026-08-18')),
  'src-idem-job-chain', 'src-hash-job-chain');

create temporary view job as
  select title, id, revision from public.jobs
  where organization_id = 'f2000000-0000-0000-0000-000000000001';

create temporary view visit as
  select v.id, v.visit_date, j.title
  from public.job_visits as v
  join public.jobs as j on j.id = v.job_id
  where v.organization_id = 'f2000000-0000-0000-0000-000000000001';

-- The period job's first two visits are done; the third is not, so the period claim has something to skip.
select public.complete_job_visit('f2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Period job'),
  (select id from visit where title = 'Period job' and visit_date = '2026-08-06'));
select public.complete_job_visit('f2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Period job'),
  (select id from visit where title = 'Period job' and visit_date = '2026-08-20'));

-- Two calendar reminders, so the second one's period has a real start rather than an open beginning.
select public.add_job_invoice_reminder('f2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Period job'), '2026-08-31'::date, 'August');
select public.add_job_invoice_reminder('f2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Period job'), '2026-09-30'::date, 'September');

create temporary view reminder as
  select r.id, r.due_on, r.reminder_kind
  from public.job_invoice_reminders as r
  where r.organization_id = 'f2000000-0000-0000-0000-000000000001';

-- A per-visit reminder, which only Part 13's completion flow raises. Written directly because the point of
-- the test is the refusal, not the route in.
set local role postgres;
insert into public.job_invoice_reminders (organization_id, job_id, reminder_kind, visit_id, due_on)
values ('f2000000-0000-0000-0000-000000000001',
  (select id from public.jobs where organization_id = 'f2000000-0000-0000-0000-000000000001' and title = 'Visit job'),
  'per_visit',
  (select v.id from public.job_visits v join public.jobs j on j.id = v.job_id
    where j.title = 'Visit job' and v.visit_date = '2026-08-05'),
  '2026-08-05'::date);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

-- The bills. Every one is a plain draft until a test issues it.
select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Whole bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Whole', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 50000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-whole', 'src-hash-bill-whole');

select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Visit bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Visit', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 20000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-visit', 'src-hash-bill-visit');

select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Second visit bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Visit again', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 20000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-visit2', 'src-hash-bill-visit2');

select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002', 'Period bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'August work', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 40000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000002']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-period', 'src-hash-bill-period');

select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Progress bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Deposit stage', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 30000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-progress', 'src-hash-bill-progress');

select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Chain bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Chain work', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 100000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-chain', 'src-hash-bill-chain');

select public.create_invoice_draft(
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Correction bill',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Corrected work', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 100000, 'is_taxable', false)),
  array['f4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-01'::date, 'src-idem-bill-correct', 'src-hash-bill-correct');

create temporary view bill as
  select subject, id, revision, invoice_number, voided_at, replaced_at,
         replaced_by_invoice_id, frozen_status_label, replacement_kind, predecessor_invoice_id,
         root_invoice_id, is_effective_receivable, issued_at
  from public.invoices
  where organization_id = 'f2000000-0000-0000-0000-000000000001';

-- The original bill under each subject is the chain root; once a rebill or correction copies the subject
-- onto a successor draft, a subject alone matches two rows, so the predecessor is always looked up here.
create temporary view original as
  select * from bill where predecessor_invoice_id is null;

-- 3. One work unit, one bill --------------------------------------------------------------------------------

select is(
  (public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Whole bill'),
    (select revision from original where subject = 'Whole bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', (select id from job where title = 'Whole job'),
      'service_property_index', 0)),
    'src-idem-claim-whole', 'src-hash-claim-whole'))->>'claimed_count',
  '1', 'a whole job can be claimed by the bill that covers it');

select is(
  (select count(*)::text from public.invoice_sources
   where organization_id = 'f2000000-0000-0000-0000-000000000001'
     and source_kind = 'job_total'),
  '1', 'and it leaves exactly one claim row');

select is(
  (select root_invoice_id from public.invoice_sources
   where organization_id = 'f2000000-0000-0000-0000-000000000001' and source_kind = 'job_total'),
  (select root_invoice_id from original where subject = 'Whole bill'),
  'the claim attaches to the chain root, not to the invoice');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Visit bill'),
    (select revision from original where subject = 'Visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', (select id from job where title = 'Whole job'))),
    'src-idem-claim-whole-2', 'src-hash-claim-whole-2') $$,
  '23505', null, 'the same whole job cannot be billed on a second invoice');

select is(
  (public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Visit bill'),
    (select revision from original where subject = 'Visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Visit job'),
      'visit_id', (select id from visit where title = 'Visit job' and visit_date = '2026-08-05'))),
    'src-idem-claim-visit', 'src-hash-claim-visit'))->>'claimed_count',
  '1', 'a single visit can be billed on its own');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Visit job'),
      'visit_id', (select id from visit where title = 'Visit job' and visit_date = '2026-08-05'))),
    'src-idem-claim-visit-2', 'src-hash-claim-visit-2') $$,
  '23505', null, 'the same visit cannot be billed twice');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', (select id from job where title = 'Visit job'))),
    'src-idem-claim-mix-1', 'src-hash-claim-mix-1') $$,
  '23505', null, 'a job with a billed visit cannot then be billed as a whole');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Whole job'),
      'visit_id', (select id from visit where title = 'Whole job'))),
    'src-idem-claim-mix-2', 'src-hash-claim-mix-2') $$,
  '23505', null, 'and a visit of a wholly billed job cannot be billed separately');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Visit job'),
      'visit_id', (select id from visit where title = 'Chain job'))),
    'src-idem-claim-wrong-visit', 'src-hash-claim-wrong-visit') $$,
  'P0404', null, 'a visit that belongs to another job is refused');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Period job'),
      'visit_id', (select id from visit where title = 'Period job' and visit_date = '2026-09-02'))),
    'src-idem-claim-wrong-client', 'src-hash-claim-wrong-client') $$,
  '23514', null, 'work belonging to another client cannot go on this bill');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Visit job'),
      'visit_id', (select id from visit where title = 'Visit job' and visit_date = '2026-08-12'),
      'service_property_index', 5)),
    'src-idem-claim-bad-index', 'src-hash-claim-bad-index') $$,
  '23514', null, 'a claim cannot point at a service address the bill does not carry');

-- 4. Periods consume their visits ----------------------------------------------------------------------------

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'reminder_period', 'job_id', (select id from job where title = 'Visit job'),
      'reminder_id', (select id from reminder where reminder_kind = 'per_visit'))),
    'src-idem-claim-pervisit', 'src-hash-claim-pervisit') $$,
  '23514', null, 'a per-visit reminder is billed as its visit, not as a period');

select is(
  (public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Period bill'),
    (select revision from original where subject = 'Period bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'reminder_period', 'job_id', (select id from job where title = 'Period job'),
      'reminder_id', (select id from reminder where due_on = '2026-08-31'),
      'service_property_index', 0)),
    'src-idem-claim-period', 'src-hash-claim-period'))->>'consumed_visit_count',
  '2', 'a billing period consumes the completed visits inside it');

select is(
  (select count(*)::text from public.invoice_sources as claim
   join public.jobs as j on j.id = claim.job_id
   where claim.organization_id = 'f2000000-0000-0000-0000-000000000001'
     and j.title = 'Period job' and claim.source_kind = 'visit'),
  '2', 'so those visits now carry claims of their own');

select is(
  (select count(*)::text from public.invoice_sources as claim
   where claim.organization_id = 'f2000000-0000-0000-0000-000000000001'
     and claim.visit_id = (select id from visit where title = 'Period job' and visit_date = '2026-09-02')),
  '0', 'while a visit outside the period, and still incomplete, is left alone');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Period job'),
      'visit_id', (select id from visit where title = 'Period job' and visit_date = '2026-08-06'))),
    'src-idem-claim-consumed', 'src-hash-claim-consumed') $$,
  '23514', null, 'and a visit the period already covers cannot be billed again');

-- 5. Tenant isolation ------------------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::text from public.invoice_sources),
  '0', 'another organization sees none of these claims');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where subject = 'Second visit bill'),
    0, jsonb_build_array(jsonb_build_object('kind', 'job_total', 'job_id', gen_random_uuid())),
    'src-idem-claim-cross', 'src-hash-claim-cross') $$,
  '42501', null, 'and it cannot claim work inside another organization');

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

-- 6. Claims are facts, not fields --------------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.invoice_sources (organization_id, root_invoice_id, client_id, source_kind, job_id)
     values ('f2000000-0000-0000-0000-000000000001',
       (select id from original where subject = 'Second visit bill'),
       'f3000000-0000-0000-0000-000000000001', 'job_total',
       (select id from job where title = 'Chain job')) $$,
  '42501', null, 'a member cannot write a claim by hand');

set local role postgres;
select throws_ok(
  $$ update public.invoice_sources set source_kind = 'visit' where true $$,
  '23514', null, 'not even the owning role can edit a claim');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

-- 7. A void keeps its claim (decision D4) --------------------------------------------------------------------------

select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
  (select id from original where subject = 'Chain bill'),
  (select revision from original where subject = 'Chain bill'),
  jsonb_build_array(jsonb_build_object(
    'kind', 'job_total', 'job_id', (select id from job where title = 'Chain job'),
    'service_property_index', 0)),
  'src-idem-claim-chain', 'src-hash-claim-chain');

select public.issue_invoice('f2000000-0000-0000-0000-000000000001',
  (select id from original where subject = 'Chain bill'), (select revision from original where subject = 'Chain bill'),
  'marked_sent', 'src-idem-issue-chain', 'src-hash-issue-chain');

select public.void_invoice('f2000000-0000-0000-0000-000000000001',
  (select id from original where subject = 'Chain bill'), 'created_in_error', 'Wrong address',
  'src-idem-void-chain', 'src-hash-void-chain');

select is(
  (select count(*)::text from public.invoice_sources as claim
   join public.jobs as j on j.id = claim.job_id
   where claim.organization_id = 'f2000000-0000-0000-0000-000000000001' and j.title = 'Chain job'),
  '1', 'voiding a bill does not release the work it claimed');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', (select id from job where title = 'Chain job'))),
    'src-idem-claim-after-void', 'src-hash-claim-after-void') $$,
  '23505', null, 'so a voided bill''s work cannot be picked up by an unrelated invoice');

-- 8. Explicit rebill, exactly once -----------------------------------------------------------------------------

select throws_ok(
  $$ select public.rebill_voided_invoice('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Correction bill'),
    'src-idem-rebill-live', 'src-hash-rebill-live') $$,
  '23514', null, 'only a voided invoice can be rebilled');

select is(
  (public.rebill_voided_invoice('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Chain bill'),
    'src-idem-rebill', 'src-hash-rebill'))->>'replacement_kind',
  'rebill', 'a voided bill can be explicitly billed again');

create temporary view rebilled as
  select * from bill where predecessor_invoice_id = (select id from original where subject = 'Chain bill');

select is(
  (select root_invoice_id from rebilled),
  (select root_invoice_id from original where subject = 'Chain bill'),
  'and the replacement lives inside the original''s chain');

-- Money is not on the table grant; it comes back through public.invoice_money, which checks view_price.
select is(
  (public.invoice_money(array[(select id from rebilled)]))->(select id::text from rebilled)->>'total_minor',
  '100000', 'carrying the same amount as the bill it replaces');

select is(
  (select count(*)::text from public.invoice_lines where invoice_id = (select id from rebilled)),
  '1', 'and the same lines');

select is(
  (select count(*)::text from public.invoice_sources as claim
   join public.jobs as j on j.id = claim.job_id
   where claim.organization_id = 'f2000000-0000-0000-0000-000000000001' and j.title = 'Chain job'),
  '1', 'the chain still holds exactly one claim on that job, not two');

select throws_ok(
  $$ select public.rebill_voided_invoice('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Chain bill'),
    'src-idem-rebill-again', 'src-hash-rebill-again') $$,
  '23505', null, 'a voided bill cannot be rebilled a second time, so the chain never branches');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from rebilled), (select revision from rebilled),
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit', 'job_id', (select id from job where title = 'Visit job'),
      'visit_id', (select id from visit where title = 'Visit job' and visit_date = '2026-08-12'))),
    'src-idem-claim-successor', 'src-hash-claim-successor') $$,
  '23514', null, 'a replacement cannot smuggle new work onto an old bill''s history');

-- 9. Correcting an issued bill (decision D3) ---------------------------------------------------------------------

select public.issue_invoice('f2000000-0000-0000-0000-000000000001',
  (select id from original where subject = 'Correction bill'),
  (select revision from original where subject = 'Correction bill'),
  'marked_sent', 'src-idem-issue-correct', 'src-hash-issue-correct');

select throws_ok(
  $$ select public.prepare_invoice_correction('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Progress bill'),
    (select revision from original where subject = 'Progress bill'),
    'src-idem-correct-draft', 'src-hash-correct-draft') $$,
  '23514', null, 'a draft is edited directly rather than corrected');

select is(
  (public.prepare_invoice_correction('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Correction bill'),
    (select revision from original where subject = 'Correction bill'),
    'src-idem-correct', 'src-hash-correct'))->>'replacement_kind',
  'correction', 'an issued bill gets a replacement draft beside it');

create temporary view correction as
  select * from bill where predecessor_invoice_id = (select id from original where subject = 'Correction bill');

select is(
  (select is_effective_receivable from original where subject = 'Correction bill'),
  true, 'and the original is still what the customer owes until the replacement is activated');

select is(
  (select is_effective_receivable from correction), false,
  'while the replacement, being a draft, is owed by nobody yet');

select throws_ok(
  $$ select public.prepare_invoice_correction('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Correction bill'),
    (select revision from original where subject = 'Correction bill'),
    'src-idem-correct-again', 'src-hash-correct-again') $$,
  '23505', null, 'one invoice can have only one correction in flight');

-- 10. Activation moves the receivable in one step -------------------------------------------------------------------

select public.replace_invoice_lines('f2000000-0000-0000-0000-000000000001',
  (select id from correction), (select revision from correction),
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Corrected work', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 80000, 'is_taxable', false)));

select throws_ok(
  $$ select public.activate_invoice_replacement('f2000000-0000-0000-0000-000000000001',
    (select id from correction), (select revision from correction),
    -5000, 'marked_sent', 'src-idem-activate-stale', 'src-hash-activate-stale') $$,
  'P0409', null, 'a difference the user no longer reviewed is refused');

select is(
  (public.activate_invoice_replacement('f2000000-0000-0000-0000-000000000001',
    (select id from correction), (select revision from correction),
    -20000, 'marked_sent', 'src-idem-activate', 'src-hash-activate'))
    ->>'predecessor_frozen_status_label',
  'awaiting_payment', 'activating freezes the label the old bill carried at that moment');

select is(
  (select replaced_by_invoice_id from original where subject = 'Correction bill'),
  (select id from correction), 'the old bill points at the one that replaced it');

select is(
  (select is_effective_receivable from original where subject = 'Correction bill'),
  false, 'the replaced bill stops being what the customer owes');

select is(
  (select is_effective_receivable from correction), true,
  'and the replacement takes its place in the same step');

select is(
  (select count(*)::text from public.invoice_events
   where invoice_id = (select id from original where subject = 'Correction bill')
     and event_type = 'invoice.replaced'),
  '1', 'history records the replacement on the bill that was replaced');

select throws_ok(
  $$ select public.activate_invoice_replacement('f2000000-0000-0000-0000-000000000001',
    (select id from correction), (select revision from correction),
    -20000, 'marked_sent', 'src-idem-activate-2', 'src-hash-activate-2') $$,
  '23514', null, 'and a replacement cannot be activated twice');

select is(
  (public.activate_invoice_replacement('f2000000-0000-0000-0000-000000000001',
    (select id from correction), (select revision from correction),
    -20000, 'marked_sent', 'src-idem-activate', 'src-hash-activate'))->>'applied',
  'false', 'a retry of the original activation returns the first result instead of repeating it');

-- 11. A progress invoice is corrected, never voided --------------------------------------------------------------

create temporary view progress_stage as
  select id from public.job_payment_schedule_items
  where organization_id = 'f2000000-0000-0000-0000-000000000001'
    and job_id = (select id from job where title = 'Progress job');

select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
  (select id from original where subject = 'Progress bill'),
  (select revision from original where subject = 'Progress bill'),
  jsonb_build_array(jsonb_build_object(
    'kind', 'installment', 'job_id', (select id from job where title = 'Progress job'),
    'installment_id', (select id from progress_stage),
    'installment_number', 1, 'service_property_index', 0)),
  'src-idem-claim-progress', 'src-hash-claim-progress');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'installment', 'job_id', (select id from job where title = 'Progress job'),
      'installment_id', (select id from progress_stage),
      'installment_number', 1)),
    'src-idem-claim-progress-2', 'src-hash-claim-progress-2') $$,
  '23505', null, 'the same installment cannot be billed twice');

select throws_ok(
  $$ select public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Second visit bill'),
    (select revision from original where subject = 'Second visit bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'installment', 'job_id', (select id from job where title = 'Progress job'))),
    'src-idem-claim-progress-3', 'src-hash-claim-progress-3') $$,
  '23514', null, 'and an installment claim without its schedule position or identity is refused');

select public.issue_invoice('f2000000-0000-0000-0000-000000000001',
  (select id from original where subject = 'Progress bill'),
  (select revision from original where subject = 'Progress bill'),
  'marked_sent', 'src-idem-issue-progress', 'src-hash-issue-progress');

select throws_ok(
  $$ select public.void_invoice('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Progress bill'), 'created_in_error', null,
    'src-idem-void-progress', 'src-hash-void-progress') $$,
  '23514', null, 'a progress invoice is corrected rather than voided');

select lives_ok(
  $$ select public.prepare_invoice_correction('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Progress bill'),
    (select revision from original where subject = 'Progress bill'),
    'src-idem-correct-progress', 'src-hash-correct-progress') $$,
  'while the correction route stays open to it');

-- 12. Retry safety --------------------------------------------------------------------------------------------

select is(
  (public.claim_invoice_sources('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Whole bill'),
    (select revision from original where subject = 'Whole bill'),
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total', 'job_id', (select id from job where title = 'Whole job'),
      'service_property_index', 0)),
    'src-idem-claim-whole', 'src-hash-claim-whole'))->>'applied',
  'false', 'a repeated claim returns the first result rather than claiming twice');

select is(
  (select count(*)::text from public.invoice_sources
   where organization_id = 'f2000000-0000-0000-0000-000000000001' and source_kind = 'job_total'
     and job_id = (select id from job where title = 'Whole job')),
  '1', 'and the work is still claimed exactly once');

select is(
  (public.rebill_voided_invoice('f2000000-0000-0000-0000-000000000001',
    (select id from original where subject = 'Chain bill'),
    'src-idem-rebill', 'src-hash-rebill'))->>'applied',
  'false', 'a repeated rebill returns the first replacement rather than creating a second');

select * from finish();
rollback;
