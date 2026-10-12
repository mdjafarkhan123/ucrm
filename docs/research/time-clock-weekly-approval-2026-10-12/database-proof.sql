-- Part 7 rolled-back proof, run before the migration was applied (psql -f, from the worktree root): a
-- manager approves up to a day; the crew member can no longer change those entries, on Timesheets or the
-- Job's Labor section; the manager still can, the entry stays approved, and the history records both.
-- The Field member is given "Record and change their own hours" inside this transaction only, so the lock
-- (not the timers-only rung) is what refuses them. Output in database-proof-output.txt.
\set ON_ERROR_STOP 1
\set org '18f0d717-904e-48d8-bd99-9df7e3844cda'
\set owner '1d50477c-8c55-4d33-a550-91ecf637b624'
\set crew '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb'
\set job '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e'
begin;
\i supabase/migrations/20261210090000_weekly_approval.sql

insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key, override_state, access_scope)
values (:'org', :'crew', 'time.track_own', 'grant', 'all');

create temporary table proof (name text primary key, id uuid, day date) on commit drop;
grant all on proof to authenticated;
insert into proof (name, day)
select 'today', (now() at time zone private.organization_timezone(:'org'))::date;

-- The manager records three entries for the crew member: two the day before yesterday, one yesterday.
select set_config('request.jwt.claims', json_build_object('sub', :'owner', 'role', 'authenticated')::text, true);
set local role authenticated;
insert into proof (name, id)
select 'general', (public.add_time_entry(:'org', :'crew', null, null, (select day from proof where name = 'today') - 2, '07:00', '08:00', 'shop')->>'id')::uuid;
insert into proof (name, id)
select 'job', (public.add_time_entry(:'org', :'crew', :'job', null, (select day from proof where name = 'today') - 2, '09:00', '11:00', 'on site')->>'id')::uuid;
insert into proof (name, id)
select 'after', (public.add_time_entry(:'org', :'crew', null, null, (select day from proof where name = 'today') - 1, '07:00', '07:30', 'yesterday')->>'id')::uuid;
select 'clock crew in' as check, public.clock_in_member(:'org', :'crew') is not null as ok;

select 'preview up to today' as check, p->'running' as running
from public.timesheet_approval(:'org', (select day from proof where name = 'today')) p;
select 'preview crew' as check, person->>'entry_count' as entries, person->>'minutes' as minutes, person->>'first_day' as first_day
from public.timesheet_approval(:'org', (select day from proof where name = 'today') - 2) p,
	jsonb_array_elements(p->'people') person
where person->>'user_id' = :'crew';
do $$ begin
	perform public.timesheet_approval('18f0d717-904e-48d8-bd99-9df7e3844cda', current_date + 30);
	raise exception 'a future cut-off should have been refused';
exception when invalid_parameter_value then raise notice 'future cut-off refused: %', sqlerrm;
end $$;

select 'approve' as check, a->>'approved_count' as approved, a->>'approved_minutes' as minutes, a->>'people_count' as people, a->'running' as running
from public.approve_time_entries(:'org', (select day from proof where name = 'today') - 2, array[:'crew']::uuid[]) a;
select 'approve again' as check, a->>'approved_count' as approved
from public.approve_time_entries(:'org', (select day from proof where name = 'today') - 2, array[:'crew']::uuid[]) a;
reset role;
select 'approved rows' as check, name, coalesce(j.approved_at, g.approved_at) is not null as approved
from proof
left join public.job_time_entries j on j.id = proof.id
left join public.general_time_entries g on g.id = proof.id
where name in ('general', 'job', 'after') order by name;

-- The crew member, with "their own hours", against approved and unapproved entries.
select set_config('request.jwt.claims', json_build_object('sub', :'crew', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin
	perform public.timesheet_approval('18f0d717-904e-48d8-bd99-9df7e3844cda', current_date - 1);
	raise exception 'crew preview should have been refused';
exception when insufficient_privilege then raise notice 'crew preview refused: %', sqlerrm;
end $$;
do $$ begin
	perform public.approve_time_entries('18f0d717-904e-48d8-bd99-9df7e3844cda', current_date - 1, array['7d450c50-b3e5-4f97-8ee9-50e08c1f70bb']::uuid[]);
	raise exception 'crew approve should have been refused';
exception when insufficient_privilege then raise notice 'crew approve refused: %', sqlerrm;
end $$;
select 'crew entries' as check, x->>'notes' as notes, x->>'approved' as approved, x->>'can_edit' as can_edit, x->>'can_delete' as can_delete
from proof, public.timesheet_entries(:'org', :'crew', proof.day - 2, proof.day) e, jsonb_array_elements(e->'entries') x
where proof.name = 'today' and not (x->>'is_running')::boolean
	and x->>'id' in (select id::text from proof where name in ('general', 'job', 'after'))
order by x->>'started_at';
select 'crew labor' as check, x->>'notes' as notes, x->>'approved' as approved, x->>'can_edit' as can_edit
from public.job_labor(:'org', :'job') l, jsonb_array_elements(l->'entries') x
where x->>'id' = (select id::text from proof where name = 'job');
do $$ declare entry uuid := (select id from proof where name = 'general'); day date := (select day from proof where name = 'today');
begin
	perform public.update_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda', entry, '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', null, null, day - 2, '07:00', '08:30', 'padded');
	raise exception 'changing approved hours should have been refused';
exception when sqlstate 'P0410' then raise notice 'crew edit of approved General refused: %', sqlerrm;
end $$;
do $$ declare entry uuid := (select id from proof where name = 'general');
begin
	perform public.delete_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda', entry);
	raise exception 'deleting approved hours should have been refused';
exception when sqlstate 'P0410' then raise notice 'crew delete of approved General refused: %', sqlerrm;
end $$;
do $$ declare entry uuid := (select id from proof where name = 'job');
begin
	perform public.update_job_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda', '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e', entry, now() - interval '3 days', 180);
	raise exception 'changing approved Job hours should have been refused';
exception when sqlstate 'P0410' then raise notice 'crew edit of approved Job hours in Labor refused: %', sqlerrm;
end $$;
do $$ declare entry uuid := (select id from proof where name = 'job');
begin
	perform public.delete_job_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda', '698bbe09-ce9f-4b92-87b2-57dfcd4f9b1e', entry);
	raise exception 'deleting approved Job hours should have been refused';
exception when sqlstate 'P0410' then raise notice 'crew delete of approved Job hours in Labor refused: %', sqlerrm;
end $$;
select 'crew edits unapproved' as check, (public.update_time_entry(:'org', id, :'crew', null, null, (select day from proof where name = 'today') - 1, '07:00', '07:45', 'yesterday, fixed')->>'changed') as changed
from proof where name = 'after';

-- The manager can still change approved hours; they stay approved, also when moved onto a Job.
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'owner', 'role', 'authenticated')::text, true);
set local role authenticated;
select 'manager edits approved' as check, (public.update_time_entry(:'org', id, :'crew', :'job', null, (select day from proof where name = 'today') - 2, '07:00', '08:15', 'shop, moved to job')->>'changed') as changed
from proof where name = 'general';
reset role;
select 'still approved after move' as check, entry.approved_at is not null as approved, entry.approved_by = :'owner'::uuid as by_owner
from public.job_time_entries entry where entry.id = (select id from proof where name = 'general');
set local role authenticated;
select 'history' as check, event->>'action' as action, event->>'actor_name' as by
from public.time_entry_history(:'org', (select id from proof where name = 'general')) h, jsonb_array_elements(h->'events') event;
select 'summary' as check, person->>'entry_count' as entries, person->>'unapproved_count' as unapproved, s->>'can_approve' as can_approve
from proof, public.timesheet_summary(:'org', proof.day, 'week') s, jsonb_array_elements(s->'people') person
where proof.name = 'today' and person->>'user_id' = :'crew';
rollback;
