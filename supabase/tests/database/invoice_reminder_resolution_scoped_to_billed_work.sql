-- Invoices 5b: the reminders a bill clears are the ones it actually answered.
--
-- Part 5a could resolve every pending reminder on a job because the only way to bill a job was to bill all of
-- it. 5b-2 (chosen visits) and 5b-3 (one billing period) broke that: billing August also marked September
-- resolved, so an unbilled month left the queue with nothing behind it. These tests pin the rule Part 2's
-- design states -- resolve the reminders consumed by this batch -- for all three claim kinds.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention invoices_source_claims_and_chains.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that. All 17 passed on that run (the remote run collected each is() into a
-- temporary table first, because that client returns only the last statement's rows).
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- 1. Privileges ----------------------------------------------------------------------------------------------

select is(has_function_privilege('authenticated',
  'public.create_invoice_from_work(uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text)',
  'execute'), true, 'members reach the bill-this-work command');
select is(has_function_privilege('anon',
  'public.create_invoice_from_work(uuid, uuid, text, jsonb, uuid[], uuid, date, date, jsonb, text, text)',
  'execute'), false, 'signed-out callers do not');
select is(has_function_privilege('authenticated',
  'private.resolve_job_reminders_as_invoiced(uuid, uuid, uuid)', 'execute'),
  false, 'reminder resolution is internal to the command, not a member-callable function');

-- 2. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reminder-scope-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('e2000000-0000-0000-0000-000000000001', 'Reminder Scope Org', 'reminder-scope-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'owner');

insert into public.clients (id, organization_id, display_name, client_type)
values ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'Reminder Scope Client', 'person');

insert into public.properties (
  id, organization_id, client_id, address_line1, city, state_region, postal_code, country
)
values ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000001', '1 Reminder Row', 'Testville', 'TX', '78741', 'United States');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- Three jobs, one billing shape each, so no test reasons about another test's reminders.
select public.create_job_with_visits(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001', 'Period job', null, true, '[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('position', 0, 'visit_date', '2026-08-06'),
    jsonb_build_object('position', 1, 'visit_date', '2026-09-08')),
  'rem-idem-job-period', 'rem-hash-job-period');

select public.create_job_with_visits(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001', 'Visit job', null, true, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', '2026-08-05')),
  'rem-idem-job-visit', 'rem-hash-job-visit');

select public.create_job_with_visits(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001', 'Whole job', null, true, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', '2026-08-10')),
  'rem-idem-job-whole', 'rem-hash-job-whole');

-- A recurring as-needed job defaults to month-end billing, so the jobs_sync_month_end_reminder trigger seeds
-- its month-end reminder on insert. That is the only reminder kind this suite cannot write by hand without
-- also faking the policy that makes rolling it forward correct.
select public.create_job_with_visits(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001', 'Month end job', null, true, '[]'::jsonb,
  '[]'::jsonb, 'rem-idem-job-month', 'rem-hash-job-month', 'recurring', true, null);

create temporary view job as
  select title, id, revision from public.jobs
  where organization_id = 'e2000000-0000-0000-0000-000000000001';

create temporary view visit as
  select v.id, v.visit_date, j.title
  from public.job_visits as v
  join public.jobs as j on j.id = v.job_id
  where v.organization_id = 'e2000000-0000-0000-0000-000000000001';

-- Two periods on the period job: August, and the September one that must survive an August bill.
select public.add_job_invoice_reminder('e2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Period job'), '2026-08-31'::date, 'August');
select public.add_job_invoice_reminder('e2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Period job'), '2026-09-30'::date, 'September');

-- The visit job carries both a per-visit prompt and an unrelated calendar prompt, so a visit bill has
-- something correct to clear and something it must leave alone.
select public.add_job_invoice_reminder('e2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Visit job'), '2026-09-30'::date, 'Unrelated period');

-- Two calendar prompts on the whole-job job, to show a job_total bill still answers all of them.
select public.add_job_invoice_reminder('e2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Whole job'), '2026-08-31'::date, 'August');
select public.add_job_invoice_reminder('e2000000-0000-0000-0000-000000000001',
  (select id from job where title = 'Whole job'), '2026-09-30'::date, 'September');

-- A per-visit reminder, which only the visit-completion flow raises. Written directly because the point of
-- these tests is what a bill clears, not the route the prompt came in by.
set local role postgres;
insert into public.job_invoice_reminders (organization_id, job_id, reminder_kind, visit_id, due_on)
values ('e2000000-0000-0000-0000-000000000001',
  (select id from public.jobs
    where organization_id = 'e2000000-0000-0000-0000-000000000001' and title = 'Visit job'),
  'per_visit',
  (select v.id from public.job_visits as v join public.jobs as j on j.id = v.job_id
    where j.organization_id = 'e2000000-0000-0000-0000-000000000001'
      and j.title = 'Visit job' and v.visit_date = '2026-08-05'),
  '2026-08-05'::date);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

create temporary view reminder as
  select r.id, r.due_on, r.reminder_kind, r.status, r.resolution, j.title
  from public.job_invoice_reminders as r
  join public.jobs as j on j.id = r.job_id
  where r.organization_id = 'e2000000-0000-0000-0000-000000000001';

-- 3. Billing one period clears that period only ----------------------------------------------------------------

-- The bug this file exists for: before the fix, this call also resolved September.
select is(
  (public.create_invoice_from_work(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'August work',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'August', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 40000, 'is_taxable', false)),
    array['e4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-09-30'::date, '2026-09-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'reminder_period',
      'job_id', (select id from job where title = 'Period job'),
      'reminder_id', (select id from reminder where title = 'Period job' and due_on = '2026-08-31'))),
    'rem-idem-bill-august', 'rem-hash-bill-august'
  ))->>'reminders_resolved',
  '1', 'billing one period answers exactly one prompt');

select is(
  (select (status, resolution) from reminder where title = 'Period job' and due_on = '2026-08-31'),
  ('resolved'::text, 'invoiced'::text), 'the billed period is cleared as invoiced');

select is(
  (select status from reminder where title = 'Period job' and due_on = '2026-09-30'),
  'pending', 'the period nobody billed is still asking to be billed');

select is(
  (select count(*)::int from reminder where title = 'Period job' and reminder_kind = 'monthly_last_day'),
  0, 'billing a custom period does not invent a month-end arrangement');

-- The job's own history names the bill that answered the prompt, once.
select is(
  (select count(*)::int from public.job_events
    where organization_id = 'e2000000-0000-0000-0000-000000000001'
      and job_id = (select id from job where title = 'Period job')
      and event_type = 'invoice_reminder_invoiced'),
  1, 'one reminder-invoiced entry lands on the job, not one per pending reminder');

-- 4. Billing one visit clears that visit's prompt only ----------------------------------------------------------

select is(
  (public.create_invoice_from_work(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'One visit',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Visit', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 20000, 'is_taxable', false)),
    array['e4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-09-30'::date, '2026-09-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'visit',
      'job_id', (select id from job where title = 'Visit job'),
      'visit_id', (select id from visit where title = 'Visit job' and visit_date = '2026-08-05'))),
    'rem-idem-bill-visit', 'rem-hash-bill-visit'
  ))->>'reminders_resolved',
  '1', 'billing one visit answers exactly one prompt');

select is(
  (select (status, resolution) from reminder
    where title = 'Visit job' and reminder_kind = 'per_visit'),
  ('resolved'::text, 'invoiced'::text), 'the billed visit''s own prompt is cleared');

select is(
  (select status from reminder where title = 'Visit job' and due_on = '2026-09-30'),
  'pending', 'the job''s unrelated period prompt is left alone');

-- 5. Billing a whole job still answers every prompt on it --------------------------------------------------------

select is(
  (public.create_invoice_from_work(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'The whole job',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Everything', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 50000, 'is_taxable', false)),
    array['e4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-09-30'::date, '2026-09-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'job_total',
      'job_id', (select id from job where title = 'Whole job'))),
    'rem-idem-bill-whole', 'rem-hash-bill-whole'
  ))->>'reminders_resolved',
  '2', 'a whole-job bill answers every prompt the job was carrying');

select is(
  (select count(*)::int from reminder where title = 'Whole job' and status = 'pending'),
  0, 'nothing on that job is still asking to be billed');

-- 6. A month-end arrangement rolls forward only when a month-end prompt was billed --------------------------------

select is(
  (select count(*)::int from reminder
    where title = 'Month end job' and reminder_kind = 'monthly_last_day' and status = 'pending'),
  1, 'the month-end job starts with exactly one open month-end prompt');

select is(
  (public.create_invoice_from_work(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'This month',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Monthly', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 30000, 'is_taxable', false)),
    array['e4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-09-30'::date, '2026-09-01'::date,
    jsonb_build_array(jsonb_build_object(
      'kind', 'reminder_period',
      'job_id', (select id from job where title = 'Month end job'),
      'reminder_id', (select id from reminder
        where title = 'Month end job' and reminder_kind = 'monthly_last_day' and status = 'pending'))),
    'rem-idem-bill-month', 'rem-hash-bill-month'
  ))->>'reminders_resolved',
  '1', 'billing the month answers the month-end prompt');

select is(
  (select count(*)::int from reminder
    where title = 'Month end job' and reminder_kind = 'monthly_last_day' and status = 'pending'),
  1, 'and the arrangement rolls forward: exactly one open month-end prompt again');

select is(
  (select due_on from reminder
    where title = 'Month end job' and reminder_kind = 'monthly_last_day' and status = 'pending'),
  -- Read from the prompt that was just billed rather than from the clock, so the expectation is the rule
  -- (the next month's end) and not a date this file would have to keep up to date.
  (select (date_trunc('month', (billed.due_on + 1)) + interval '1 month' - interval '1 day')::date
    from reminder as billed
    where billed.title = 'Month end job'
      and billed.reminder_kind = 'monthly_last_day'
      and billed.status = 'resolved'),
  'the new prompt is next month''s end, not a repeat of the one just billed');

select * from finish();
rollback;
