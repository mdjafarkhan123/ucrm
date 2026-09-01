-- Jobs, Part 10b: editing a recurring job's schedule, and the database's own protection of completed visits.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_direct_creation_and_visits.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

-- 1. Privileges ---------------------------------------------------------------------------------------------

select is(
  has_function_privilege(
    'authenticated', 'public.reschedule_job_visits(uuid, uuid, integer, jsonb, text, text)', 'execute'
  ),
  true, 'members reach the reschedule command'
);
select is(
  has_function_privilege(
    'anon', 'public.reschedule_job_visits(uuid, uuid, integer, jsonb, text, text)', 'execute'
  ),
  false, 'signed-out callers cannot reschedule a job'
);
select is(
  has_function_privilege(
    'authenticated', 'public.apply_visit_to_future(uuid, uuid, uuid, boolean, boolean, text, text)', 'execute'
  ),
  true, 'members reach the apply-to-future command'
);
select is(
  has_function_privilege(
    'anon', 'public.apply_visit_to_future(uuid, uuid, uuid, boolean, boolean, text, text)', 'execute'
  ),
  false, 'signed-out callers cannot push a visit forward'
);

select has_trigger(
  'public', 'job_visits', 'job_visits_protect_completed_update',
  'the update guard is attached to the visits table itself'
);
select has_trigger(
  'public', 'job_visits', 'job_visits_protect_completed_delete',
  'the delete guard is attached to the visits table itself'
);

-- 2. Fixtures -----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-edit-office@example.test', 'test', now(), now(), now()),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-edit-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('d2000000-0000-0000-0000-000000000001', 'Edit Org', 'edit-org', 'active');

insert into public.organization_settings (organization_id, timezone, locale, currency_code)
values ('d2000000-0000-0000-0000-000000000001', 'America/Chicago', 'en-US', 'USD')
on conflict (organization_id) do update set currency_code = excluded.currency_code;

insert into public.organization_members (organization_id, user_id, role)
values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'office'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'field');

insert into public.clients (id, organization_id, display_name)
values ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'Edit Client');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', '11 Edit Way', 'Testville', 'TX', '78744');

-- Six Mondays from 2026-08-03. Two of them are then completed, and three of the rest sit in the past, which
-- is the case that decides whether we follow Jobber: it clears *all* incomplete visits, not only upcoming
-- ones.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$ select public.create_job_with_visits(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001',
    'Weekly hedge care', null, true, '[]'::jsonb, '[]'::jsonb,
    'idem-edit-0001', 'hash-edit-0001', 'recurring', false,
    '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-08-03",
      "end_mode":"after","duration_count":6,"duration_unit":"week","start_time":"09:00",
      "end_time":"11:00","all_day":false}'::jsonb
  ) $$,
  'a weekly recurring job is created with its six visits'
);

set local role postgres;
update public.job_visits
set completed_at = now(), completed_by = 'd1000000-0000-0000-0000-000000000001'
where job_id = (select id from public.jobs where title = 'Weekly hedge care')
  and visit_date in (date '2026-08-03', date '2026-08-10');

-- 3. The database protects completed visits, whoever is holding the pen ---------------------------------------

-- These run as the table owner, outside RLS and outside every command, because that is the whole point: the
-- protection has to be the table's own, not a screen's good manners.
select throws_ok(
  $$ update public.job_visits set visit_date = date '2026-12-01'
     where job_id = (select id from public.jobs where title = 'Weekly hedge care')
       and completed_at is not null $$,
  'P0410', null, 'a completed visit cannot be moved to another day'
);

select throws_ok(
  $$ update public.job_visits set start_time = time '15:00'
     where job_id = (select id from public.jobs where title = 'Weekly hedge care')
       and completed_at is not null $$,
  'P0410', null, 'a completed visit cannot have its time changed'
);

select throws_ok(
  $$ delete from public.job_visits
     where job_id = (select id from public.jobs where title = 'Weekly hedge care')
       and completed_at is not null $$,
  'P0410', null, 'a completed visit cannot be deleted on its own'
);

select lives_ok(
  $$ update public.job_visits set instructions = 'left the key under the mat'
     where job_id = (select id from public.jobs where title = 'Weekly hedge care')
       and completed_at is not null $$,
  'a completed visit can still gain a note; only its schedule is frozen'
);

select lives_ok(
  $$ update public.job_visits
     set completed_at = now(), completed_by = 'd1000000-0000-0000-0000-000000000001'
     where job_id = (select id from public.jobs where title = 'Weekly hedge care')
       and visit_date = date '2026-08-17' $$,
  'marking a visit complete is not a reschedule and stays allowed'
);

set local role postgres;
update public.job_visits set completed_at = null, completed_by = null
where job_id = (select id from public.jobs where title = 'Weekly hedge care')
  and visit_date = date '2026-08-17';

-- 4. Rescheduling ---------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$ select public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    0,
    '{"frequency":"weekly","interval_count":1,"weekdays":[2],"start_date":"2026-09-08",
      "end_mode":"after","duration_count":4,"duration_unit":"week","all_day":true}'::jsonb,
    'idem-edit-denied-01', 'hash-edit-denied-01'
  ) $$,
  '42501', null, 'a field member without jobs.schedule cannot rewrite the schedule'
);

select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$ select public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    99,
    '{"frequency":"weekly","interval_count":1,"weekdays":[2],"start_date":"2026-09-08",
      "end_mode":"after","duration_count":4,"duration_unit":"week","all_day":true}'::jsonb,
    'idem-edit-stale-001', 'hash-edit-stale-001'
  ) $$,
  'P0409', null, 'a stale revision is refused rather than silently overwriting'
);

select throws_ok(
  $$ select public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    0, null, 'idem-edit-norule-01', 'hash-edit-norule-01'
  ) $$,
  '23514', null, 'a repeating job is never left without a rule'
);

-- Tuesdays and Fridays for two weeks from 2026-09-08.
select is(
  (public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    0,
    '{"frequency":"weekly","interval_count":1,"weekdays":[2,5],"start_date":"2026-09-08",
      "end_mode":"after","duration_count":2,"duration_unit":"week","start_time":"14:00",
      "end_time":"16:00","all_day":false}'::jsonb,
    'idem-edit-resched-01', 'hash-edit-resched-01'
  ))->>'removed_count',
  '4', 'all four incomplete visits go, including the three already in the past'
);

select is(
  (select count(*)::int from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and completed_at is not null),
  2, 'both completed visits survive the rebuild'
);

select is(
  (select array_agg(visit_date order by visit_date)::text from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and completed_at is null),
  '{2026-09-08,2026-09-11,2026-09-15,2026-09-18}',
  'the new visits are the Tuesdays and Fridays the new rule names'
);

select is(
  (select array_agg(distinct start_time)::text from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and completed_at is null),
  '{14:00:00}', 'the new visits carry the new rule''s time of day'
);

select is(
  (select array_agg(distinct start_time)::text from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and completed_at is not null),
  '{09:00:00}', 'the completed visits keep the time they were actually worked'
);

select is(
  (select count(*)::int from public.job_recurrence_rules
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')),
  1, 'the job still has exactly one rule, replaced rather than added to'
);

select is(
  (select weekdays::text from public.job_recurrence_rules
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')),
  '{2,5}', 'the stored rule is the new one'
);

select is(
  (select count(*)::int from public.job_events
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and event_type = 'schedule_replaced'),
  1, 'the rebuild leaves one history row'
);

-- A retry of the same request, carrying the revision it read before the first attempt. It must return the
-- first result rather than rebuilding again, and must not be mistaken for a stale editor.
select is(
  (public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    0,
    '{"frequency":"weekly","interval_count":1,"weekdays":[2,5],"start_date":"2026-09-08",
      "end_mode":"after","duration_count":2,"duration_unit":"week","start_time":"14:00",
      "end_time":"16:00","all_day":false}'::jsonb,
    'idem-edit-resched-01', 'hash-edit-resched-01'
  ))->>'applied',
  'false', 'a replayed reschedule reports that it did not apply again'
);

select is(
  (select count(*)::int from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')),
  6, 'the replay did not build a second set of visits'
);

-- 5. Which jobs may be rescheduled at all ---------------------------------------------------------------------

select lives_ok(
  $$ select public.create_job_with_visits(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001',
    'Single fence repair', null, true, '[]'::jsonb,
    '[{"position":0,"visit_date":"2026-09-09","all_day":true}]'::jsonb,
    'idem-edit-oneoff-1', 'hash-edit-oneoff-1', 'one_off', false, null
  ) $$,
  'a one-off job is created for the refusal below'
);

select throws_ok(
  $$ select public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Single fence repair'),
    0,
    '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-09-07",
      "end_mode":"after","duration_count":2,"duration_unit":"week","all_day":true}'::jsonb,
    'idem-edit-oneoff-2', 'hash-edit-oneoff-2'
  ) $$,
  '23514', null, 'a one-off job has no repeating schedule to edit'
);

select lives_ok(
  $$ select public.create_job_with_visits(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001',
    'On call gutters', null, true, '[]'::jsonb, '[]'::jsonb,
    'idem-edit-asneed-1', 'hash-edit-asneed-1', 'recurring', true, null
  ) $$,
  'an as-needed job is created for the refusal below'
);

-- Giving an as-needed job a real schedule is a deferred product decision, not a quiet by-product of this
-- editor: the job''s own trigger makes `is_as_needed` immutable.
select throws_ok(
  $$ select public.reschedule_job_visits(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'On call gutters'),
    0,
    '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-09-07",
      "end_mode":"after","duration_count":2,"duration_unit":"week","all_day":true}'::jsonb,
    'idem-edit-asneed-2', 'hash-edit-asneed-2'
  ) $$,
  '23514', null, 'an as-needed job is not given a repeating schedule here'
);

-- 6. Pushing one visit's time and crew forward -------------------------------------------------------------------

set local role postgres;
update public.job_visits set start_time = time '07:30', end_time = time '08:30'
where job_id = (select id from public.jobs where title = 'Weekly hedge care')
  and visit_date = date '2026-09-11';
insert into public.job_visit_assignments (organization_id, visit_id, user_id)
select 'd2000000-0000-0000-0000-000000000001', id, 'd1000000-0000-0000-0000-000000000002'
from public.job_visits
where job_id = (select id from public.jobs where title = 'Weekly hedge care')
  and visit_date = date '2026-09-11';
-- The last visit of the run is completed, so it can prove it stays untouched even though it is later than
-- the visit being pushed forward.
update public.job_visits set completed_at = now(), completed_by = 'd1000000-0000-0000-0000-000000000001'
where job_id = (select id from public.jobs where title = 'Weekly hedge care')
  and visit_date = date '2026-09-18';

set local role authenticated;

select throws_ok(
  $$ select public.apply_visit_to_future(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    (select id from public.job_visits
      where job_id = (select id from public.jobs where title = 'Weekly hedge care')
        and visit_date = date '2026-09-11'),
    false, false, 'idem-edit-fwd-none1', 'hash-edit-fwd-none1'
  ) $$,
  '23514', null, 'applying nothing forward is refused rather than doing nothing quietly'
);

select is(
  (public.apply_visit_to_future(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where title = 'Weekly hedge care'),
    (select id from public.job_visits
      where job_id = (select id from public.jobs where title = 'Weekly hedge care')
        and visit_date = date '2026-09-11'),
    true, true, 'idem-edit-fwd-0001', 'hash-edit-fwd-0001'
  ))->>'updated_count',
  '1', 'only the one later incomplete visit is updated; the completed one is not counted'
);

select is(
  (select start_time::text from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and visit_date = date '2026-09-15'),
  '07:30:00', 'the later visit takes the new time of day'
);

select is(
  (select count(*)::int from public.job_visit_assignments a
    join public.job_visits v on v.id = a.visit_id
    where v.job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and v.visit_date = date '2026-09-15'),
  1, 'the later visit takes the crew as well'
);

select is(
  (select start_time::text from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and visit_date = date '2026-09-18'),
  '14:00:00', 'the completed visit later in the run keeps its own time'
);

select is(
  (select start_time::text from public.job_visits
    where job_id = (select id from public.jobs where title = 'Weekly hedge care')
      and visit_date = date '2026-09-08'),
  '14:00:00', 'a visit earlier than the source is left alone'
);

-- One row out, so a runner that only shows the last non-empty result still shows the verdict.
select coalesce((select string_agg(line, E'\n') from finish() as line), 'PASS: all 35 assertions') as result;
rollback;
