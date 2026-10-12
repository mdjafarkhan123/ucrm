-- Rolled-back proof of Time clock Part 5 (corrections, history, manager actions). Nothing here is kept.
-- Raad LTD (Asia/Dhaka, UTC+6). Owner 1d50477c, field member 7d450c50 (time.track_own), admin df7d9de4.
\set ON_ERROR_STOP 1
\set org '18f0d717-904e-48d8-bd99-9df7e3844cda'
\set owner '1d50477c-8c55-4d33-a550-91ecf637b624'
\set field '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb'
\set admin 'df7d9de4-527a-4f42-88e4-6af3187470c6'
\set field_job '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e'
begin;
\i supabase/migrations/20261208090000_timesheet_corrections.sql

-- Nobody has a timer running for this proof, whatever the live data holds.
delete from public.running_timers where organization_id = :'org' and user_id in (:'field', :'admin');

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'field', 'role', 'authenticated')::text, true);

\echo '== Field member adds General 22:00-02:00 on Mon 5 Oct (overnight: 240 minutes)'
select public.add_time_entry(:'org', :'field', null, null, '2026-10-05', '22:00', '02:00', ' Yard ') ->> 'id' as general_id \gset
reset role;
select started_at, minutes, notes, source from public.general_time_entries where id = :'general_id';
set local role authenticated;

\echo '== ...moves it to their Job, 8:00-12:00 (same id, now Job hours with a costing row)'
select public.update_time_entry(:'org', :'general_id', :'field', :'field_job', null, '2026-10-05', '08:00', '12:00', 'Yard');
reset role;
select id = :'general_id' as same_id, started_at, minutes, notes, cost_per_hour_minor from public.job_time_entries where id = :'general_id';
select count(*) as general_left from public.general_time_entries where id = :'general_id';
set local role authenticated;

\echo '== ...cannot move it to the admin (refused)'
savepoint refused;
\set ON_ERROR_STOP 0
select public.update_time_entry(:'org', :'general_id', :'admin', :'field_job', null, '2026-10-05', '08:00', '12:00', 'Yard');
rollback to savepoint refused;
\echo '== ...cannot write a 25-hour or zero-length entry (refused)'
select public.add_time_entry(:'org', :'field', null, null, '2026-10-05', '08:00', '08:00', null);
rollback to savepoint refused;
\set ON_ERROR_STOP 1

\echo '== Owner moves the entry to the admin: re-priced at the admin rate, costing trail updated'
select set_config('request.jwt.claims', json_build_object('sub', :'owner', 'role', 'authenticated')::text, true);
select public.update_time_entry(:'org', :'general_id', :'admin', :'field_job', null, '2026-10-05', '08:00', '12:30', 'Yard');
reset role;
select user_id = :'admin' as now_admin, minutes, cost_per_hour_minor,
	(select cost_per_hour_minor from public.organization_member_cost_profiles where organization_id = :'org' and user_id = :'admin') as admin_rate
from public.job_time_entries where id = :'general_id';
select event_type, prior_values->>'user_id' = :'field' as was_field, new_values->>'user_id' = :'admin' as now_admin
from public.job_costing_events where subject_id = :'general_id' order by created_at, event_type;
set local role authenticated;

\echo '== History of that entry, as the owner reads it'
select e->>'action' as action, e->>'actor_name' as actor, e->'prior'->>'kind' as prior_kind, e->'prior'->>'user_name' as prior_person,
	e->'new'->>'kind' as new_kind, e->'new'->>'user_name' as new_person, e->'new'->>'minutes' as new_minutes, e->'new'->>'job_number' as job
from jsonb_array_elements(public.time_entry_history(:'org', :'general_id')->'events') as e;

\echo '== The field member cannot read it now it is the admin''s (refused)'
select set_config('request.jwt.claims', json_build_object('sub', :'field', 'role', 'authenticated')::text, true);
savepoint refused2;
\set ON_ERROR_STOP 0
select public.time_entry_history(:'org', :'general_id');
rollback to savepoint refused2;
\echo '== ...nor delete it (refused)'
select public.delete_time_entry(:'org', :'general_id');
rollback to savepoint refused2;
\echo '== ...nor clock the admin in (refused)'
select public.clock_in_member(:'org', :'admin');
rollback to savepoint refused2;
\set ON_ERROR_STOP 1

\echo '== Running timer: field member clocks in, moves the start and adds a note'
select public.clock_in(:'org');
select public.update_running_timer(:'org', :'field', (now() at time zone 'Asia/Dhaka')::date, ((now() at time zone 'Asia/Dhaka') - interval '2 hours')::time, 'Shop');
reset role;
select id as timer_id, kind, notes, round(extract(epoch from now() - started_at) / 60) as minutes_running from public.running_timers where organization_id = :'org' and user_id = :'field' \gset
select :'timer_id' is not null as has_id, :'minutes_running' as minutes_running;
set local role authenticated;
\echo '== ...it cannot be deleted or changed like an entry while it runs (refused)'
savepoint refused3;
\set ON_ERROR_STOP 0
select public.delete_time_entry(:'org', :'timer_id');
rollback to savepoint refused3;
select public.update_time_entry(:'org', :'timer_id', :'field', null, null, '2026-10-05', '08:00', '09:00', null);
rollback to savepoint refused3;
\echo '== ...and cannot start in the future (refused)'
select public.update_running_timer(:'org', :'field', (now() at time zone 'Asia/Dhaka')::date + 1, '08:00', null);
rollback to savepoint refused3;
\set ON_ERROR_STOP 1
\echo '== ...clock out: the entry keeps the timer id, its notes and its history'
select public.clock_out(:'org');
reset role;
select id = :'timer_id' as same_id, minutes, notes, source from public.general_time_entries where id = :'timer_id';
set local role authenticated;
select e->>'action' as action, e->'prior'->>'started_at' as prior_start, e->'new'->>'started_at' as new_start, e->'new'->>'minutes' as minutes
from jsonb_array_elements(public.time_entry_history(:'org', :'timer_id')->'events') as e;
\echo '== ...and deletes their own General entry'
select public.delete_time_entry(:'org', :'timer_id');
reset role;
select count(*) as remaining from public.general_time_entries where id = :'timer_id';
select action from public.time_entry_history where entry_id = :'timer_id' order by created_at, id;

\echo '== Overnight success check: a visit timer left running since 7:30 two days ago (over 24 hours)'
insert into public.running_timers (organization_id, user_id, kind, job_id, started_at, started_by, resume_general)
values (:'org', :'field', 'visit', :'field_job', ((now() at time zone 'Asia/Dhaka')::date - 2 + time '07:30') at time zone 'Asia/Dhaka', :'field', true)
returning id as overnight_id \gset
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'field', 'role', 'authenticated')::text, true);
\echo '== ...the crew member''s own Stop is refused'
savepoint refused_own;
\set ON_ERROR_STOP 0
select public.stop_my_timer(:'org');
rollback to savepoint refused_own;
\set ON_ERROR_STOP 1
reset role;
select now() - started_at > interval '24 hours' as over_a_day from private.timesheet_rows(:'org', now() - interval '3 days', now() + interval '1 day', :'field') where is_running;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', :'owner', 'role', 'authenticated')::text, true);
select p->>'name' as name, p->'running'->>'long_running' as long_running, p->'running'->>'clocked_in' as clocked_in
from jsonb_array_elements(public.timesheet_summary(:'org', null, 'week')->'people') as p where p->>'user_id' = :'field';
\echo '== ...an end more than a day after the start is refused'
savepoint refused4;
\set ON_ERROR_STOP 0
select public.stop_timer_at(:'org', :'field', (now() at time zone 'Asia/Dhaka')::date - 1, '08:00');
rollback to savepoint refused4;
\set ON_ERROR_STOP 1
\echo '== ...the manager stops it at 5:30 pm the day it started: 10 hours, nothing resumes'
select public.stop_timer_at(:'org', :'field', (now() at time zone 'Asia/Dhaka')::date - 2, '17:30');
reset role;
select id = :'overnight_id' as same_id, minutes, source from public.job_time_entries where id = :'overnight_id';
select count(*) as still_running from public.running_timers where organization_id = :'org' and user_id = :'field';
set local role authenticated;
select e->>'action' as action, e->>'actor_name' as who, e->'new'->>'minutes' as minutes
from jsonb_array_elements(public.time_entry_history(:'org', :'overnight_id')->'events') as e;

\echo '== Manager clocks the field member in'
select public.clock_in_member(:'org', :'field');
reset role;
select kind, started_by = :'owner' as by_owner from public.running_timers where organization_id = :'org' and user_id = :'field';
set local role authenticated;

\echo '== Labor section correction still works and lands in the history'
select public.update_job_time_entry(:'org', :'field_job', :'overnight_id', now() - interval '30 hours', 600, null, 'Gutter work', null);
select e->>'action' as action, e->'prior'->>'notes' as prior_notes, e->'new'->>'notes' as new_notes
from jsonb_array_elements(public.time_entry_history(:'org', :'overnight_id')->'events') as e;

\echo '== Entries list says what the field member may change'
select set_config('request.jwt.claims', json_build_object('sub', :'field', 'role', 'authenticated')::text, true);
select e->>'kind' as kind, e->>'is_running' as running, e->>'can_edit' as can_edit, e->>'can_delete' as can_delete, e->>'edited' as edited
from jsonb_array_elements(public.timesheet_entries(:'org', :'field', (now() at time zone 'Asia/Dhaka')::date - 2, (now() at time zone 'Asia/Dhaka')::date)->'entries') as e;

\echo '== Anonymous cannot call the commands'
reset role;
set local role anon;
savepoint refused5;
\set ON_ERROR_STOP 0
select public.add_time_entry(:'org', :'field', null, null, '2026-10-05', '08:00', '09:00', null);
rollback to savepoint refused5;
rollback;
