-- A job's status follows its visits: Upcoming, Today, Late and Action required.
--
-- Found in the multi-industry connected proof (B12): a job with a visit booked for Oct 13 still read
-- "Unscheduled". The approved jobs contract derives these from the job's next incomplete visit; the database
-- only ever answered Unscheduled, Requires invoicing, Ending soon and Archived. Run the whole file as one
-- transaction that is rolled back at the end, like the sibling job files.
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- 1. The rule on its own -----------------------------------------------------------------------------------

select is(
  private.job_status_with_visits('unscheduled', date '2026-10-11', date '2026-10-13', true, true),
  'upcoming', 'an open visit after today reads as Upcoming'
);
select is(
  private.job_status_with_visits('unscheduled', date '2026-10-11', date '2026-10-11', true, true),
  'today', 'an open visit today reads as Today'
);
select is(
  private.job_status_with_visits('unscheduled', date '2026-10-11', date '2026-10-09', true, true),
  'late', 'an open visit before today reads as Late'
);
select is(
  private.job_status_with_visits('unscheduled', date '2026-10-11', null, true, true),
  'unscheduled', 'open visits that have no date still read as Unscheduled'
);
select is(
  private.job_status_with_visits('unscheduled', date '2026-10-11', null, false, true),
  'action_required', 'every visit done and nothing left to do reads as Action required'
);
select is(
  private.job_status_with_visits('unscheduled', date '2026-10-11', null, false, false),
  'unscheduled', 'a job that never had a visit is still Unscheduled, not Action required'
);
select is(
  private.job_status_with_visits('requires_invoicing', date '2026-10-11', date '2026-10-09', true, true),
  'requires_invoicing', 'a due invoice reminder still outranks a late visit'
);
select is(
  private.job_status_with_visits('ending_soon', date '2026-10-11', date '2026-10-13', true, true),
  'ending_soon', 'an agreement ending soon still outranks an upcoming visit'
);
select is(
  private.job_status_with_visits('archived', date '2026-10-11', date '2026-10-13', true, true),
  'archived', 'a closed job stays archived whatever its visits say'
);

-- 2. Through the list view and the counts -------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'job-status-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('f2000000-0000-0000-0000-000000000001', 'Job Status Co', 'job-status-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'owner');

insert into public.clients (id, organization_id, display_name)
values ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Job Status Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', '1 Status Row', 'Testville');

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
)
select ('f8000000-0000-0000-0000-00000000000' || n)::uuid, 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 9600 + n,
  'Status job ' || n, 'one_off', 'job_total', 'USD'
from generate_series(1, 6) as n;

create temp table org_today as
select calendar.today
from private.organization_calendars() as calendar
where calendar.organization_id = 'f2000000-0000-0000-0000-000000000001';

-- Job 1: no visits. Job 2: an upcoming visit. Job 3: a visit today. Job 4: a visit two days ago.
-- Job 5: its only visit is done. Job 6: an undated visit.
insert into public.job_visits (organization_id, job_id, position, visit_date, completed_at, completed_by)
select 'f2000000-0000-0000-0000-000000000001', v.job_id::uuid, 0, v.visit_date, v.completed_at, v.completed_by
from org_today, lateral (values
  ('f8000000-0000-0000-0000-000000000002', org_today.today + 2, null::timestamptz, null::uuid),
  ('f8000000-0000-0000-0000-000000000003', org_today.today, null, null),
  ('f8000000-0000-0000-0000-000000000004', org_today.today - 2, null, null),
  ('f8000000-0000-0000-0000-000000000005', org_today.today - 2, now(), 'f1000000-0000-0000-0000-000000000001'),
  ('f8000000-0000-0000-0000-000000000006', null, null, null)
) as v(job_id, visit_date, completed_at, completed_by);

select is(
  (select derived_status from public.job_list_rows where id = 'f8000000-0000-0000-0000-000000000001'),
  'unscheduled', 'list: a job with no visits is Unscheduled'
);
select is(
  (select derived_status from public.job_list_rows where id = 'f8000000-0000-0000-0000-000000000002'),
  'upcoming', 'list: a job with a visit in two days is Upcoming'
);
select is(
  (select derived_status from public.job_list_rows where id = 'f8000000-0000-0000-0000-000000000003'),
  'today', 'list: a job with a visit today is Today'
);
select is(
  (select derived_status from public.job_list_rows where id = 'f8000000-0000-0000-0000-000000000004'),
  'late', 'list: a job whose visit was two days ago is Late'
);
select is(
  (select derived_status from public.job_list_rows where id = 'f8000000-0000-0000-0000-000000000005'),
  'action_required', 'list: a job whose only visit is done is Action required'
);
select is(
  (select derived_status from public.job_list_rows where id = 'f8000000-0000-0000-0000-000000000006'),
  'unscheduled', 'list: a job whose visit has no date is Unscheduled'
);

-- The Overview card counts the same answers.
select is(
  (select jsonb_object_agg(derived_status, total) from public.job_status_counts('f2000000-0000-0000-0000-000000000001')),
  jsonb_build_object('unscheduled', 2, 'upcoming', 1, 'today', 1, 'late', 1, 'action_required', 1),
  'counts: the Overview card agrees with the list'
);

select * from finish();

rollback;
