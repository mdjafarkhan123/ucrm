-- Contractor Settings Part 4D: atomic submission outcomes.
-- Proves: submit_form_response holds the exact reserved slot synchronously for an instant-book outcome (any
-- job form, or an assessment form that does not require approval), reserves nothing for a request-only form
-- or an approval-gated assessment, and refuses a submission when a competing submission just won the only
-- free slot; and process_next_form_submission turns a held submission into exactly the right record --
-- request, request + confirmed assessment, request held needs_approval, or job + visit -- using the same
-- conservative client-matching rule Website Chat already proved (one unambiguous match connects, anything
-- ambiguous or absent creates a new lead), reuses a known client's primary property when no new address was
-- submitted, never wedges the queue on one permanently-failing row, and is idempotent to re-processing.
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive, so
-- do not run this through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(62);

-- 1. Structure and grants -------------------------------------------------------------------------------------

select has_column('private', 'form_submissions', 'assigned_user_id',
  'a submission remembers which member''s calendar was reserved for it');
select has_column('private', 'form_submissions', 'booking_reservation_id',
  'a submission remembers which reservation row it claimed');
select has_column('private', 'form_submissions', 'result',
  'a processed submission remembers what it became');
select has_function('public', 'process_next_form_submission', 'the worker''s one entry point exists');
select is(
  has_function_privilege('service_role', 'public.process_next_form_submission()', 'execute'),
  true, 'the service-role worker can process a submission'
);
select is(
  has_function_privilege('authenticated', 'public.process_next_form_submission()', 'execute'),
  false, 'a signed-in staff session never drains the submission queue directly'
);
select is(
  has_function_privilege('anon', 'public.process_next_form_submission()', 'execute'),
  false, 'anon never drains the submission queue'
);
select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'requests_status_check'),
  $$CHECK ((status = ANY (ARRAY['new'::text, 'unscheduled'::text, 'assessment_completed'::text, 'completed'::text, 'converted'::text, 'archived'::text, 'needs_approval'::text])))$$,
  'requests.status gains needs_approval alongside every stored status Jobber parity already needed'
);

-- 2. Fixtures ---------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('4d0a0000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'outcomes-owner@example.test', 'test', now(), now(), now()),
  ('4d0a0000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'outcomes-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('4d0b0000-0000-0000-0000-000000000001', 'Outcomes Test Co', 'outcomes-test-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('4d0b0000-0000-0000-0000-000000000001', '4d0a0000-0000-0000-0000-000000000001', 'owner'),
  ('4d0b0000-0000-0000-0000-000000000001', '4d0a0000-0000-0000-0000-000000000002', 'field');

-- The owner never works the field (same fixed pattern the availability-engine suite uses), so field-a is the
-- one and only candidate every booking below can resolve to -- assignment is never ambiguous in this file.
insert into public.organization_member_availability (organization_id, user_id, weekday, is_working)
select '4d0b0000-0000-0000-0000-000000000001', '4d0a0000-0000-0000-0000-000000000001', weekday, false
from generate_series(0, 6) as weekday;

update public.organization_settings set hours_mode = 'weekly'
where organization_id = '4d0b0000-0000-0000-0000-000000000001';
insert into public.organization_business_hours (organization_id, weekday, period_index, is_open, opens_at, closes_at)
values ('4d0b0000-0000-0000-0000-000000000001', 1, 0, true, time '09:00', time '12:00');

insert into public.catalog_items (id, organization_id, category, name, is_taxable)
values ('4d0c0000-0000-0000-0000-000000000001', '4d0b0000-0000-0000-0000-000000000001', 'service',
  'Drain Cleaning', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '4d0a0000-0000-0000-0000-000000000001', true);

select public.create_form(
  '4d0b0000-0000-0000-0000-000000000001', 'request', 'Outcomes Request Form', 'outcomes-request-form', 'Tell us'
);
select public.publish_form_draft(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-request-form'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1
);

select public.create_form(
  '4d0b0000-0000-0000-0000-000000000001', 'request', 'Outcomes Request Form (fails)',
  'outcomes-request-form-failure', 'Tell us'
);
select public.publish_form_draft(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-request-form-failure'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1
);

select public.create_form(
  '4d0b0000-0000-0000-0000-000000000001', 'assessment', 'Outcomes Assessment Instant',
  'outcomes-assessment-instant', 'Book us'
);
select public.update_form_booking_settings(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-assessment-instant'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1, false, false, 0, 30, 60, null, 0, array['4d0c0000-0000-0000-0000-000000000001'::uuid]
);
select public.publish_form_draft(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-assessment-instant'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1
);

select public.create_form(
  '4d0b0000-0000-0000-0000-000000000001', 'assessment', 'Outcomes Assessment Approval',
  'outcomes-assessment-approval', 'Book us'
);
select public.update_form_booking_settings(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-assessment-approval'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1, true, false, 0, 30, 60, null, 0, array['4d0c0000-0000-0000-0000-000000000001'::uuid]
);
select public.publish_form_draft(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-assessment-approval'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1
);

select public.create_form(
  '4d0b0000-0000-0000-0000-000000000001', 'job', 'Outcomes Job Form', 'outcomes-job-form', 'Book us'
);
select public.update_form_booking_settings(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-job-form'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1, false, false, 0, 30, 60, null, 0, array['4d0c0000-0000-0000-0000-000000000001'::uuid]
);
select public.publish_form_draft(
  '4d0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'outcomes-job-form'
   and organization_id = '4d0b0000-0000-0000-0000-000000000001'),
  1
);

-- Every RPC from here on plays the part of the app's own service-role client, exactly like the 4C suite --
-- run as postgres so grants are never the thing under test in this section.
set local role postgres;

-- 3. submit_form_response: instant-book reserves synchronously; approval-gated reserves nothing -------------

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-assessment-instant', 'assess-instant-1',
    jsonb_build_object('name', 'Alice A', 'email', 'alice@example.test', 'address',
      jsonb_build_object('line1', '200 Elm St', 'city', 'Austin', 'state_region', 'TX', 'postal_code', '78701')),
    '{}'::jsonb, '{}'::text[], '4d0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  ) ->> 'already_received')::boolean,
  false, 'an instant-book assessment submission is received fresh'
);
select is(
  (select assigned_user_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-instant'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-instant-1'),
  '4d0a0000-0000-0000-0000-000000000002'::uuid,
  'the only free member''s calendar is reserved synchronously at submit time'
);
select is(
  (select booking_reservation_id is not null from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-instant'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-instant-1'),
  true, 'the claimed reservation id is carried forward for the worker'
);
select is(
  (select count(*)::integer from private.form_booking_reservations
   where organization_id = '4d0b0000-0000-0000-0000-000000000001'
     and user_id = '4d0a0000-0000-0000-0000-000000000002'
     and starts_at = timestamptz '2099-01-05 09:00:00+00' and ends_at = timestamptz '2099-01-05 10:00:00+00'),
  1, 'the reservation row itself exists on the field member''s calendar'
);

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-assessment-approval', 'assess-approval-1',
    jsonb_build_object('name', 'Bob B', 'email', 'bob@example.test', 'address',
      jsonb_build_object('line1', '201 Elm St', 'city', 'Austin', 'state_region', 'TX', 'postal_code', '78701')),
    '{}'::jsonb, '{}'::text[], '4d0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  ) ->> 'already_received')::boolean,
  false, 'an approval-gated assessment submission is received fresh, over the exact same already-taken slot'
);
select is(
  (select assigned_user_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-approval'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-approval-1'),
  null, 'an approval-gated booking never touches anyone''s calendar'
);
select is(
  (select booking_reservation_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-approval'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-approval-1'),
  null, 'an approval-gated booking claims no reservation'
);

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-job-form', 'job-1',
    jsonb_build_object('name', 'Carol C', 'email', 'carol@example.test', 'address',
      jsonb_build_object('line1', '202 Elm St', 'city', 'Austin', 'state_region', 'TX', 'postal_code', '78701')),
    '{}'::jsonb, '{}'::text[], '4d0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 10:00:00+00', timestamptz '2099-01-05 11:00:00+00'
  ) ->> 'already_received')::boolean,
  false, 'a job-form submission is received fresh, right after the instant-book slot frees up again'
);
select is(
  (select assigned_user_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-job-form'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'job-1'),
  '4d0a0000-0000-0000-0000-000000000002'::uuid, 'a job form always instant-books the free member too'
);
select is(
  (select booking_reservation_id is not null from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-job-form'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'job-1'),
  true, 'the job booking''s reservation id is carried forward too'
);

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-request-form', 'req-new-1',
    jsonb_build_object('name', 'Dave D', 'email', 'dave@example.test', 'address',
      jsonb_build_object('line1', '300 Pine St', 'city', 'Round Rock', 'state_region', 'TX', 'postal_code', '78664')),
    '{}'::jsonb
  ) ->> 'already_received')::boolean,
  false, 'a request-only submission is received fresh'
);
select is(
  (select assigned_user_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-request-form'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'req-new-1'),
  null, 'a request-only submission never touches anyone''s calendar'
);
select is(
  (select booking_reservation_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-request-form'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'req-new-1'),
  null, 'a request-only submission claims no reservation'
);

-- 4. submit_form_response: a competing submission that just won the only free slot is refused ----------------

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-assessment-instant', 'contention-1',
    jsonb_build_object('name', 'Erin E', 'email', 'erin-contention@example.test'), '{}'::jsonb, '{}'::text[],
    '4d0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 11:00:00+00', timestamptz '2099-01-05 12:00:00+00'
  ) ->> 'already_received')::boolean,
  false, 'the first of two racing submissions claims the last free slot'
);
select is(
  (select assigned_user_id from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-instant'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'contention-1'),
  '4d0a0000-0000-0000-0000-000000000002'::uuid, 'the winner is assigned the only field member'
);
select throws_ok(
  $$select public.submit_form_response(
    'outcomes-test-co', 'outcomes-assessment-instant', 'contention-2',
    jsonb_build_object('name', 'Frank F', 'email', 'frank-contention@example.test'), '{}'::jsonb, '{}'::text[],
    '4d0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 11:00:00+00', timestamptz '2099-01-05 12:00:00+00'
  )$$,
  '23514', 'That time is no longer available. Please choose another.',
  'the loser of the same exact slot is told immediately, not silently double-booked'
);

-- 5. process_next_form_submission: confirmed assessment, needs_approval assessment, and job outcomes ----------

select is(public.process_next_form_submission() ->> 'status', 'processed',
  'processing the confirmed-assessment submission succeeds');
select is(
  (select status from public.requests
   where id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-instant'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-instant-1') ->> 'request_id')::uuid),
  'new', 'a confirmed assessment''s request keeps the ordinary new status'
);
select is(
  (select count(*)::integer from public.assessments
   where request_id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-instant'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-instant-1') ->> 'request_id')::uuid
     and starts_at = timestamptz '2099-01-05 09:00:00+00' and ends_at = timestamptz '2099-01-05 10:00:00+00'),
  1, 'a real assessment is booked at the exact reserved time'
);
select is(
  (select user_id from public.assessment_assignees
   where assessment_id = (select id from public.assessments
     where request_id = ((select result from private.form_submissions
       where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-instant'
         and organization_id = '4d0b0000-0000-0000-0000-000000000001')
       and idempotency_key = 'assess-instant-1') ->> 'request_id')::uuid)),
  '4d0a0000-0000-0000-0000-000000000002'::uuid, 'the assessment is assigned to the member whose calendar was reserved'
);

select is(public.process_next_form_submission() ->> 'status', 'processed',
  'processing the approval-gated submission succeeds');
select is(
  (select status from public.requests
   where id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-approval'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-approval-1') ->> 'request_id')::uuid),
  'needs_approval', 'an approval-gated booking is held for staff review, matching Jobber''s own label'
);
select is(
  (select preferred_time is not null from public.requests
   where id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-approval'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-approval-1') ->> 'request_id')::uuid),
  true, 'staff sees what time the customer actually asked for'
);
select is(
  (select count(*)::integer from public.assessments
   where request_id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-assessment-approval'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'assess-approval-1') ->> 'request_id')::uuid),
  0, 'nothing is booked on the calendar until staff actually approves it'
);

select is(public.process_next_form_submission() ->> 'status', 'processed',
  'processing the job-form submission succeeds');
select is(
  (select count(*)::integer from public.job_visits
   where job_id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-job-form'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'job-1') ->> 'job_id')::uuid
     and visit_date = date '2099-01-05' and start_time = time '10:00' and end_time = time '11:00'),
  1, 'a job form books straight into the schedule at the exact reserved time'
);
select is(
  (select user_id from public.job_visit_assignments
   where visit_id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-job-form'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'job-1') ->> 'visit_id')::uuid),
  '4d0a0000-0000-0000-0000-000000000002'::uuid, 'the visit is assigned to the member whose calendar was reserved'
);
select is(
  (select count(*)::integer from public.job_line_items
   where job_id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-job-form'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'job-1') ->> 'job_id')::uuid
     and source_catalog_item_id = '4d0c0000-0000-0000-0000-000000000001'),
  1, 'the chosen catalog service becomes a real line item on the job'
);
select is(
  (select total_minor is not null from public.jobs
   where id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-job-form'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'job-1') ->> 'job_id')::uuid),
  true, 'the job''s money is computed, not left blank'
);

-- 6. process_next_form_submission: conservative client matching and property reuse -----------------------------

select is(public.process_next_form_submission() ->> 'status', 'processed',
  'processing the new request-form submission succeeds');
select is(
  (select count(*)::integer from public.clients
   where organization_id = '4d0b0000-0000-0000-0000-000000000001' and lifecycle_status = 'lead'
     and id in (select client_id from public.client_contact_methods
       where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
         and normalized_value = 'dave@example.test')),
  1, 'a brand-new email with no match creates exactly one new lead'
);
select is(
  (select address_line1 from public.properties where client_id = (
    select client_id from public.client_contact_methods
    where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
      and normalized_value = 'dave@example.test')),
  '300 Pine St', 'the property''s street address comes from the structured address the visitor submitted'
);
select is(
  (select city from public.properties where client_id = (
    select client_id from public.client_contact_methods
    where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
      and normalized_value = 'dave@example.test')),
  'Round Rock', 'the property''s city comes from the same structured address'
);
select is(
  (select state_region from public.properties where client_id = (
    select client_id from public.client_contact_methods
    where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
      and normalized_value = 'dave@example.test')),
  'TX', 'the property''s state comes from the same structured address'
);
select is(
  (select postal_code from public.properties where client_id = (
    select client_id from public.client_contact_methods
    where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
      and normalized_value = 'dave@example.test')),
  '78664', 'the property''s postal code comes from the same structured address'
);
select is(
  (select is_primary from public.properties where client_id = (
    select client_id from public.client_contact_methods
    where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
      and normalized_value = 'dave@example.test')),
  true, 'a client''s first property becomes their primary automatically'
);

-- Drain the contention winner (Erin, contention-1) that has sat pending since section 4. The queue is strict
-- FIFO by created_at, so leaving her in front of the rows the assertions below target would make every later
-- process_next_form_submission() pick the wrong submission. A bare call (no assertion) keeps plan() unchanged.
select public.process_next_form_submission();

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-request-form', 'req-reuse-1',
    jsonb_build_object('name', 'Dave D', 'email', 'dave@example.test'), '{}'::jsonb
  ) ->> 'already_received')::boolean,
  false, 'the same customer''s second visit is received fresh'
);
select is(public.process_next_form_submission() ->> 'status', 'processed',
  'processing the returning customer''s second submission succeeds');
select is(
  (select count(*)::integer from public.client_contact_methods
   where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
     and normalized_value = 'dave@example.test'),
  1, 'the unambiguous email match connects to the same client instead of creating a second one'
);
select is(
  (select count(*)::integer from public.properties where client_id = (
    select client_id from public.client_contact_methods
    where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
      and normalized_value = 'dave@example.test')),
  1, 'the second visit with no new address reuses the existing primary property instead of creating one'
);
select is(
  (select count(*)::integer from public.requests
   where client_id = (select client_id from public.client_contact_methods
     where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
       and normalized_value = 'dave@example.test')),
  2, 'the returning customer now has two separate requests on file'
);

-- The one ambiguity the org-wide unique index actually permits: the phone belongs to one existing client
-- while the email belongs to a different one. The count>1 case ("two clients share a phone") cannot exist --
-- the index forbids it -- so this disagreement is the real "we can't tell who this is" signal. The worker
-- must not guess between them: it creates a new lead for staff to review, keeps the Request, and skips
-- copying either conflicting identifier (each already belongs to its original owner) rather than crashing and
-- dropping the inbound.
insert into public.clients (id, organization_id, display_name, lifecycle_status)
values
  ('4d0e0000-0000-0000-0000-000000000001', '4d0b0000-0000-0000-0000-000000000001', 'Ambiguous One', 'lead'),
  ('4d0e0000-0000-0000-0000-000000000002', '4d0b0000-0000-0000-0000-000000000001', 'Ambiguous Two', 'lead');
insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
values
  ('4d0b0000-0000-0000-0000-000000000001', '4d0e0000-0000-0000-0000-000000000001', 'phone', '512-555-9999', true),
  ('4d0b0000-0000-0000-0000-000000000001', '4d0e0000-0000-0000-0000-000000000002', 'email', 'ambiguous-two@example.test', true);

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-request-form', 'req-ambiguous-1',
    jsonb_build_object('name', 'Ambiguous Caller', 'phone', '(512) 555-9999', 'email', 'Ambiguous-Two@Example.test'),
    '{}'::jsonb
  ) ->> 'already_received')::boolean,
  false, 'a submission whose phone and email point at two different clients is received fresh'
);
select is(public.process_next_form_submission() ->> 'status', 'processed',
  'processing a phone-vs-email-disagreement submission succeeds instead of failing the row');
select is(
  (select client_id = any(array[
     '4d0e0000-0000-0000-0000-000000000001'::uuid, '4d0e0000-0000-0000-0000-000000000002'::uuid
   ]) from public.requests
   where id = ((select result from private.form_submissions
     where form_id = (select id from public.forms where public_slug = 'outcomes-request-form'
       and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'req-ambiguous-1') ->> 'request_id')::uuid),
  false, 'the new lead is a genuinely new client, never one of the two disagreeing candidates'
);
select is(
  (select count(distinct client_id)::integer from public.client_contact_methods
   where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'phone'
     and normalized_value = '5125559999'),
  1, 'the conflicting phone stays with its original owner -- it was not duplicated onto the new lead'
);

-- 7. process_next_form_submission never wedges the queue on one permanently-failing row --------------------

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-request-form', 'req-good-1',
    jsonb_build_object('name', 'Grace G', 'email', 'grace@example.test'), '{}'::jsonb
  ) ->> 'already_received')::boolean,
  false, 'a healthy submission behind the soon-to-fail one is received fresh'
);
select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-request-form-failure', 'req-bad-1',
    jsonb_build_object('name', 'Hank H', 'email', 'hank@example.test'), '{}'::jsonb
  ) ->> 'already_received')::boolean,
  false, 'the submission whose form is about to be disabled is received fresh too'
);

update public.forms set is_enabled = false
where public_slug = 'outcomes-request-form-failure' and organization_id = '4d0b0000-0000-0000-0000-000000000001';

select public.process_next_form_submission();
select public.process_next_form_submission();

select is(
  (select status from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-request-form-failure'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'req-bad-1'),
  'failed', 'the row whose form disappeared mid-flight is recorded failed, never left pending forever'
);
select is(
  (select processing_error is not null from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-request-form-failure'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'req-bad-1'),
  true, 'the failure reason is recorded on the row'
);
select is(
  (select status from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'outcomes-request-form'
     and organization_id = '4d0b0000-0000-0000-0000-000000000001')
     and idempotency_key = 'req-good-1'),
  'processed', 'the healthy row behind it still processed -- one bad row never wedges the queue'
);
select is(public.process_next_form_submission() ->> 'status', 'idle',
  'the queue is fully drained once every row has a final status');

-- 8. submit_form_response stays idempotent after processing, not just before it ------------------------------

select is(
  (public.submit_form_response(
    'outcomes-test-co', 'outcomes-request-form', 'req-new-1',
    jsonb_build_object('name', 'Dave D', 'email', 'dave@example.test', 'address',
      jsonb_build_object('line1', '300 Pine St', 'city', 'Round Rock', 'state_region', 'TX', 'postal_code', '78664')),
    '{}'::jsonb
  ) ->> 'already_received')::boolean,
  true, 're-submitting an already-processed idempotency key is recognized, never reprocessed'
);
select is(
  (select count(*)::integer from public.client_contact_methods
   where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
     and normalized_value = 'dave@example.test'),
  1, 'the repeat created no second client'
);
select is(
  (select count(*)::integer from public.requests
   where client_id = (select client_id from public.client_contact_methods
     where organization_id = '4d0b0000-0000-0000-0000-000000000001' and kind = 'email'
       and normalized_value = 'dave@example.test')),
  2, 'the repeat created no third request'
);

select * from finish();
rollback;
