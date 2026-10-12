-- Part 6 rolled-back proof, run before the migration was applied (psql -f): the Field member (Login.md) can
-- run timers and see their own hours, and every typed-hours command refuses them. Output in live-journey.md.
\set ON_ERROR_STOP 1
begin;
\i /home/jafar/Ucrm-wt/time-clock-p6/supabase/migrations/20261209090000_timers_only_permission.sql
select role, permission_key from public.role_permissions where permission_key like 'time.%' order by 1,2;
select 'run timer' as check, private.can_run_own_timer('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb');
select 'see own' as check, private.can_see_own_time('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb');
select 'write general own' as check, private.can_write_general_time('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb');
-- act as the Field member
select set_config('request.jwt.claims', '{"sub":"7d450c50-b3e5-4f97-8ee9-50e08c1f70bb","role":"authenticated"}', true);
set local role authenticated;
select 'summary' as check, s->>'can_add' as can_add, s->>'can_view_team' as team, jsonb_array_length(s->'people') as people from public.timesheet_summary('18f0d717-904e-48d8-bd99-9df7e3844cda', null, 'week') s;
select 'entries' as check, jsonb_array_length(e->'entries') n, (select bool_or((x->>'can_edit')::boolean or (x->>'can_delete')::boolean) from jsonb_array_elements(e->'entries') x) any_writable
  from public.timesheet_entries('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', current_date - 30, current_date - 24) e;
select 'rls own job hours' as check, count(*) from public.job_time_entries;
select 'clock in' as check, public.clock_in('18f0d717-904e-48d8-bd99-9df7e3844cda')->>'kind';
savepoint before_add;
do $$ begin
  perform public.add_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', null, null, current_date - 1, '09:00', '10:00', 'typed');
  raise exception 'add_time_entry should have been refused';
exception when insufficient_privilege then raise notice 'add_time_entry refused: %', sqlerrm;
end $$;
do $$ begin
  perform public.update_running_timer('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', current_date, '00:01', 'x');
  raise exception 'update_running_timer should have been refused';
exception when insufficient_privilege then raise notice 'update_running_timer refused: %', sqlerrm;
end $$;
do $$ begin
  perform public.stop_timer_at('18f0d717-904e-48d8-bd99-9df7e3844cda','7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', current_date, '00:01');
  raise exception 'stop_timer_at should have been refused';
exception when insufficient_privilege then raise notice 'stop_timer_at refused: %', sqlerrm;
end $$;
select 'clock out' as check, public.clock_out('18f0d717-904e-48d8-bd99-9df7e3844cda') is not null;
rollback;

-- Second run: Job Labor, history and delete (psql -v entry=<own entry id> -v job=<Job #20 id>).
\set ON_ERROR_STOP 1
begin;
\i /home/jafar/Ucrm-wt/time-clock-p6/supabase/migrations/20261209090000_timers_only_permission.sql
select set_config('request.jwt.claims', '{"sub":"7d450c50-b3e5-4f97-8ee9-50e08c1f70bb","role":"authenticated"}', true);
set local role authenticated;
select 'labor' as check, l->>'can_add' can_add, jsonb_array_length(l->'entries') n, (select bool_or((x->>'can_edit')::boolean) from jsonb_array_elements(l->'entries') x) any_edit
  from public.job_labor('18f0d717-904e-48d8-bd99-9df7e3844cda', :'job') l;
select 'history' as check, jsonb_array_length(h->'events') from public.time_entry_history('18f0d717-904e-48d8-bd99-9df7e3844cda', :'entry') h;
do $$ begin
  perform public.delete_time_entry('18f0d717-904e-48d8-bd99-9df7e3844cda', 'fe1ae731-90e3-4b6d-95da-49924ea9a39a'::uuid);
  raise exception 'delete should have been refused';
exception when insufficient_privilege then raise notice 'delete_time_entry refused: %', sqlerrm;
end $$;
rollback;
