-- Jobs, Part 9: scheduling a job's visits after it exists — add, edit, move and delete.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_update_details_command.sql documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and `set_config`
-- do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

-- 1. Privileges --------------------------------------------------------------------------------------------

select is(has_function_privilege('anon', 'public.add_job_visits(uuid, uuid, jsonb, text, text)', 'execute'), false, 'signed-out callers cannot add visits');
select is(has_function_privilege('anon', 'public.update_job_visit(uuid, uuid, uuid, integer, date, time, time, boolean, text, text, jsonb)', 'execute'), false, 'signed-out callers cannot edit a visit');
select is(has_function_privilege('anon', 'public.move_job_visits(uuid, uuid, jsonb, integer, text, text)', 'execute'), false, 'signed-out callers cannot move visits');
select is(has_function_privilege('anon', 'public.delete_job_visit(uuid, uuid, uuid, integer)', 'execute'), false, 'signed-out callers cannot delete a visit');

select is(has_function_privilege('authenticated', 'public.add_job_visits(uuid, uuid, jsonb, text, text)', 'execute'), true, 'members reach the add-visits command');
select is(has_function_privilege('authenticated', 'public.update_job_visit(uuid, uuid, uuid, integer, date, time, time, boolean, text, text, jsonb)', 'execute'), true, 'members reach the edit-visit command');
select is(has_function_privilege('authenticated', 'public.move_job_visits(uuid, uuid, jsonb, integer, text, text)', 'execute'), true, 'members reach the move-visits command');
select is(has_function_privilege('authenticated', 'public.delete_job_visit(uuid, uuid, uuid, integer)', 'execute'), true, 'members reach the delete-visit command');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'visit-office@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'visit-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c2000000-0000-0000-0000-000000000001', 'Visit Org A', 'visit-org-a', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'office'),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'field');

insert into public.clients (id, organization_id, display_name)
values ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Visit Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', '1 Visit Way', 'Testville', 'TX', '78741');

-- The primary job, created through the real command with one unscheduled visit at position 0. A second job is
-- closed later to prove scheduling is refused on it.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

select public.create_job_with_visits(
  'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001',
  'Schedule target job', 'Original instructions', true, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
  'idem-jobA-0001', 'hash-jobA-0001'
);
select public.create_job_with_visits(
  'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001',
  'Closed target job', null, true, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
  'idem-jobB-0001', 'hash-jobB-0001'
);

-- 3. Add visits ---------------------------------------------------------------------------------------------

-- Two visits appended: a booked appointment (assigned to the field member) and an anytime day.
select is(
  (public.add_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    jsonb_build_array(
      jsonb_build_object('visit_date', '2026-10-01', 'start_time', '09:00', 'end_time', '11:00',
        'assignee_ids', jsonb_build_array('c1000000-0000-0000-0000-000000000002')),
      jsonb_build_object('visit_date', '2026-10-02', 'all_day', true)
    ),
    'idem-add-0001', 'hash-add-0001'
  ))->>'added_count',
  '2', 'the office member adds two visits and gets a count of 2'
);
select is(
  (select count(*)::int from public.job_visits
    where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')),
  3, 'the job now holds three visits, the added ones appended after the first'
);
select is(
  (select count(*)::int from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.organization_id = 'c2000000-0000-0000-0000-000000000001' and j.title = 'Schedule target job'
      and e.event_type = 'visits_added'),
  1, 'adding visits emitted one visits_added event'
);
select is(
  (select count(*)::int from public.job_visit_assignments
    where visit_id = (select id from public.job_visits
      where organization_id = 'c2000000-0000-0000-0000-000000000001'
        and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')
        and position = 1)),
  1, 'the booked visit carries its one assignment'
);

-- 4. Move visits --------------------------------------------------------------------------------------------

-- Move the whole list by a week. The unscheduled first visit has no date to shift, so only the two dated,
-- incomplete visits move.
select is(
  (public.move_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select jsonb_agg(id) from public.job_visits
      where organization_id = 'c2000000-0000-0000-0000-000000000001'
        and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')),
    7, 'idem-move-0001', 'hash-move-0001'
  ))->>'moved_count',
  '2', 'only the two dated visits move; the unscheduled one is skipped'
);
select is(
  (select visit_date::text from public.job_visits
    where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')
      and position = 1),
  '2026-10-08', 'the booked visit moved forward exactly seven days'
);
select is(
  (public.move_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select jsonb_agg(id) from public.job_visits
      where organization_id = 'c2000000-0000-0000-0000-000000000001'
        and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')),
    7, 'idem-move-0001', 'hash-move-0001'
  ))->>'applied',
  'false', 'replaying the same move key does not shift the dates a second time'
);
select throws_ok(
  $$ select public.move_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select jsonb_agg(id) from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')),
    0, 'idem-move-zero', 'hash-move-zero'
  ) $$,
  '23514', null, 'a zero-day move is refused'
);

-- 5. Edit one visit -----------------------------------------------------------------------------------------

-- Turn the unscheduled first visit into a booked appointment and give it a crew.
select is(
  (public.update_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 0),
    0, '2026-11-01', '08:00', null, false, 'Kickoff', 'Meet on site',
    jsonb_build_array('c1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002')
  ))->>'revision',
  '1', 'editing a visit bumps its revision to 1'
);
select is(
  (select start_time::text from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
    and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 0),
  '08:00:00', 'the edited visit now carries its start time'
);
select ok(
  (select metadata->'changed' from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.organization_id = 'c2000000-0000-0000-0000-000000000001' and j.title = 'Schedule target job'
      and e.event_type = 'visit_updated' limit 1) @> '["schedule"]'::jsonb,
  'the visit_updated event names the schedule as changed'
);
select is(
  (select count(*)::int from public.job_visit_assignments
    where visit_id = (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 0)),
  2, 'the assignee set was replaced with the two chosen members'
);
select throws_ok(
  $$ select public.update_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 0),
    0, '2026-11-02', null, null, false, null, null, null
  ) $$,
  'P0409', null, 'a stale visit revision is refused rather than clobbering the newer edit'
);
select throws_ok(
  $$ select public.update_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 2),
    1, null, '09:00', null, false, null, null, null
  ) $$,
  '23514', null, 'a start time without a date is refused by the table shape check'
);
select throws_ok(
  $$ select public.update_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    'c9000000-0000-0000-0000-000000000099', 0, null, null, null, false, null, null, null
  ) $$,
  'P0404', null, 'editing a visit that does not exist is a not-found'
);

-- A field member holds jobs.view but not jobs.schedule.
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.update_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 0),
    1, '2026-11-03', null, null, false, null, null, null
  ) $$,
  '42501', null, 'a member without jobs.schedule cannot edit a visit'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 6. Completed visits are protected -----------------------------------------------------------------------

set local role postgres;
update public.job_visits
set completed_at = now(), completed_by = 'c1000000-0000-0000-0000-000000000001'
where organization_id = 'c2000000-0000-0000-0000-000000000001'
  and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job')
  and position = 2;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$ select public.update_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 2),
    0, '2026-12-01', null, null, false, null, null, null
  ) $$,
  'P0410', null, 'a completed visit cannot be rescheduled'
);
select throws_ok(
  $$ select public.delete_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 2),
    0
  ) $$,
  'P0410', null, 'a completed visit cannot be removed'
);

-- 7. Delete one visit ---------------------------------------------------------------------------------------

select is(
  (public.delete_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 1),
    1
  ))->>'applied',
  'true', 'the booked visit is deleted'
);
select is(
  (select count(*)::int from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
    and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 1),
  0, 'the deleted visit is gone'
);
select is(
  (select count(*)::int from public.job_visit_assignments a
    where not exists (select 1 from public.job_visits v where v.id = a.visit_id)),
  0, 'the deleted visit took its assignments with it'
);
select is(
  (select count(*)::int from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.organization_id = 'c2000000-0000-0000-0000-000000000001' and j.title = 'Schedule target job'
      and e.event_type = 'visit_deleted'),
  1, 'deleting a visit emitted one visit_deleted event'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.delete_job_visit(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select id from public.job_visits where organization_id = 'c2000000-0000-0000-0000-000000000001'
      and job_id = (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job') and position = 0),
    1
  ) $$,
  '42501', null, 'a member without jobs.schedule cannot delete a visit'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 8. Add-visit guards -------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.add_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    (select jsonb_agg(jsonb_build_object('visit_date', null)) from generate_series(1, 21)),
    'idem-add-21', 'hash-add-21'
  ) $$,
  '23514', null, 'adding more than twenty visits at once is refused'
);
select is(
  (public.add_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    jsonb_build_array(jsonb_build_object('visit_date', '2026-10-01', 'start_time', '09:00', 'end_time', '11:00')),
    'idem-add-0001', 'hash-add-0001'
  ))->>'applied',
  'false', 'replaying the same add key does not add the visits again'
);
select throws_ok(
  $$ select public.add_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    jsonb_build_array(jsonb_build_object('visit_date', '2027-01-01')),
    'idem-add-0001', 'hash-add-DIFFERENT'
  ) $$,
  'P0409', null, 'the same add key with different visits is a conflict'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.add_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Schedule target job'),
    jsonb_build_array(jsonb_build_object('visit_date', '2027-02-01')),
    'idem-add-field', 'hash-add-field'
  ) $$,
  '42501', null, 'a member without jobs.schedule cannot add visits'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- Close the second job directly (the close command arrives in a later part) and prove scheduling is refused.
set local role postgres;
update public.jobs set status = 'closed', closed_at = now()
where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Closed target job';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$ select public.add_job_visits(
    'c2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'c2000000-0000-0000-0000-000000000001' and title = 'Closed target job'),
    jsonb_build_array(jsonb_build_object('visit_date', '2027-03-01')),
    'idem-add-closed', 'hash-add-closed'
  ) $$,
  'P0410', null, 'a closed job cannot be scheduled against'
);

select * from finish();
rollback;
