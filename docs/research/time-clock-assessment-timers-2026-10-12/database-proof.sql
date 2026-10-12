-- Part 8 rolled-back proof, run before the migration was applied (psql -f, from the worktree root): the
-- Field member (timers only, work narrowed to what they are assigned) times today's Assessment while clocked
-- in; the time lands once on Timesheets against its Request, never on a Job cost, and the day clock resumes.
-- Completing the Assessment stops its timer. Only today's, assigned, incomplete Assessments can be started.
-- The owner's corrections keep or clear the Request. Output in database-proof-output.txt.
\set ON_ERROR_STOP 1
\set org '18f0d717-904e-48d8-bd99-9df7e3844cda'
\set owner '1d50477c-8c55-4d33-a550-91ecf637b624'
\set crew '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb'
\set client '86705118-7fd9-414a-a61e-75f280b53bce'
\set property '91cdb687-c9cc-4bdc-901a-504d9fdf8876'
begin;
\i supabase/migrations/20261211090000_assessment_timers.sql

create temporary table proof (name text primary key, id uuid) on commit drop;
grant all on proof to authenticated;

-- Four Requests with an Assessment each: two today with the crew member on them, tomorrow's with them on
-- it, and today's without them.
with made as (
	insert into public.requests (organization_id, client_id, property_id, title, status)
	select :'org', :'client', :'property', title, 'new'
	from unnest(array['Proof roof check', 'Proof second check', 'Proof tomorrow check', 'Proof someone else check']) as title
	returning id, title
)
insert into proof (name, id)
select case title when 'Proof roof check' then 'request_today' when 'Proof second check' then 'request_second'
	when 'Proof tomorrow check' then 'request_tomorrow' else 'request_other' end, id
from made;
with made as (
	insert into public.assessments (organization_id, request_id, starts_at, ends_at)
	select :'org', proof.id,
		now() + case when proof.name = 'request_tomorrow' then interval '1 day' else interval '0' end,
		now() + case when proof.name = 'request_tomorrow' then interval '1 day 1 hour' else interval '1 hour' end
	from proof where proof.name like 'request_%'
	returning id, request_id
)
insert into proof (name, id)
select replace((select name from proof where proof.id = made.request_id), 'request_', 'assessment_'), made.id
from made;
-- Kept today in the business's zone even near midnight: the test only needs "today".
update public.assessments set starts_at = date_trunc('day', now() at time zone 'Asia/Dhaka') at time zone 'Asia/Dhaka' + interval '12 hours',
	ends_at = date_trunc('day', now() at time zone 'Asia/Dhaka') at time zone 'Asia/Dhaka' + interval '13 hours'
where id in (select id from proof where name in ('assessment_today', 'assessment_second', 'assessment_other'));
insert into public.assessment_assignees (organization_id, assessment_id, user_id)
select :'org', id, :'crew' from proof where name in ('assessment_today', 'assessment_second', 'assessment_tomorrow');

-- The crew member clocks in, then starts today's Assessment.
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;
select 'clock in' as check, public.clock_in(:'org')->>'clocked_in' as clocked_in;
reset role;
update public.running_timers set started_at = now() - interval '90 minutes' where user_id = :'crew';
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;
select 'start assessment' as check, s->>'already_running' as already_running, s->>'day_clock_paused' as day_clock_paused
from public.start_assessment_timer(:'org', (select id from proof where name = 'assessment_today')) s;
select 'start again' as check, s->>'already_running' as already_running
from public.start_assessment_timer(:'org', (select id from proof where name = 'assessment_today')) s;
select 'my timer' as check, t->'timer'->>'kind' as kind, t->'timer'->>'request_title' as request, t->>'clocked_in' as clocked_in
from public.my_running_timer(:'org') t;
do $$ begin
	perform public.start_assessment_timer('18f0d717-904e-48d8-bd99-9df7e3844cda', (select id from proof where name = 'assessment_second'));
	raise exception 'a second timer should have been refused';
exception when sqlstate 'P0409' then raise notice 'second timer refused: %', sqlerrm;
end $$;
reset role;

-- 40 minutes on site, then Stop.
update public.running_timers set started_at = now() - interval '40 minutes' where user_id = :'crew';
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;
insert into proof (name, id)
select 'entry_stopped', (s->>'entry_id')::uuid from public.stop_my_timer(:'org') s;
reset role;
select 'stopped' as check, kind, minutes, request_id = (select id from proof where name = 'request_today') as on_request
from (select 'assessment' as kind, g.minutes, g.request_id from public.general_time_entries g
	where g.id = (select id from proof where name = 'entry_stopped')) stopped;
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;
select 'day clock resumed' as check, t->'timer'->>'kind' as kind from public.my_running_timer(:'org') t;
select 'crew timesheet' as check, x->>'kind' as kind, x->>'minutes' as minutes, x->'request'->>'title' as request,
	jsonb_typeof(x->'job') = 'null' as no_job, x->>'can_edit' as can_edit
from public.timesheet_entries(:'org', :'crew', current_date - 1, current_date + 1) e, jsonb_array_elements(e->'entries') x
where x->>'id' = (select id::text from proof where name = 'entry_stopped');

-- Only today's, and only one they can see.
select 'clock out' as check, c->>'kind' as stopped_kind from public.clock_out(:'org') c;
do $$ begin
	perform public.start_assessment_timer('18f0d717-904e-48d8-bd99-9df7e3844cda', (select id from proof where name = 'assessment_tomorrow'));
	raise exception 'tomorrow should have been refused';
exception when sqlstate 'P0410' then raise notice 'tomorrow refused: %', sqlerrm;
end $$;
do $$ begin
	perform public.start_assessment_timer('18f0d717-904e-48d8-bd99-9df7e3844cda', (select id from proof where name = 'assessment_other'));
	raise exception 'an unassigned assessment should have been refused';
exception when insufficient_privilege then raise notice 'unassigned refused: %', sqlerrm;
end $$;
reset role;
select 'crew job cost untouched' as check, count(*) as job_entries_today
from public.job_time_entries where user_id = :'crew' and started_at > now() - interval '3 hours';
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;

-- Started again, then the Assessment is completed while it runs.
select 'start for completion' as check, s->>'already_running' as already_running
from public.start_assessment_timer(:'org', (select id from proof where name = 'assessment_today')) s;
reset role;
update public.running_timers set started_at = now() - interval '25 minutes' where user_id = :'crew';
select set_config('request.jwt.claims', json_build_object('sub', :'owner', 'role', 'authenticated')::text, true);
set local role authenticated;
update public.assessments set completed_at = now() where id = (select id from proof where name = 'assessment_today');
reset role;
select 'completed stops timer' as check, (select count(*) from public.running_timers where user_id = :'crew') as still_running,
	count(*) as assessment_entries, sum(minutes) as minutes
from public.general_time_entries
where user_id = :'crew' and request_id = (select id from proof where name = 'request_today');
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin
	perform public.start_assessment_timer('18f0d717-904e-48d8-bd99-9df7e3844cda', (select id from proof where name = 'assessment_today'));
	raise exception 'a completed assessment should have been refused';
exception when sqlstate 'P0410' then raise notice 'completed refused: %', sqlerrm;
end $$;
reset role;

-- The owner corrects the stopped entry: keeps the Assessment, cannot move it to another, then makes it General.
select set_config('request.jwt.claims', json_build_object('sub', :'owner', 'role', 'authenticated')::text, true);
set local role authenticated;
select 'owner keeps assessment' as check, u->>'changed' as changed
from public.update_time_entry(:'org', (select id from proof where name = 'entry_stopped'), :'crew', null, null,
	(now() at time zone 'Asia/Dhaka')::date, '09:00', '09:45', 'measured roof',
	(select id from proof where name = 'request_today')) u;
do $$ begin
	perform public.update_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda', (select id from proof where name = 'entry_stopped'),
		'7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', null, null, (now() at time zone 'Asia/Dhaka')::date, '09:00', '09:45',
		'measured roof', (select id from proof where name = 'request_other'));
	raise exception 'moving to another assessment should have been refused';
exception when invalid_parameter_value then raise notice 'other assessment refused: %', sqlerrm;
end $$;
select 'owner makes general' as check, u->>'changed' as changed
from public.update_time_entry(:'org', (select id from proof where name = 'entry_stopped'), :'crew', null, null,
	(now() at time zone 'Asia/Dhaka')::date, '09:00', '09:45', 'measured roof', null) u;
select 'history' as check, h->>'action' as action, h->'prior'->>'kind' as before, h->'prior'->>'request_title' as before_request,
	h->'new'->>'kind' as after
from public.time_entry_history(:'org', (select id from proof where name = 'entry_stopped')) t, jsonb_array_elements(t->'events') h;
reset role;
select 'now general' as check, request_id is null as general from public.general_time_entries
where id = (select id from proof where name = 'entry_stopped');
rollback;
