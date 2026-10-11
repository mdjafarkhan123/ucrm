-- Rolled-back proof of the Timesheets reads. Nothing here is kept.
\set ON_ERROR_STOP 1
begin;
\i supabase/migrations/20261207090000_timesheets_views.sql

-- Raad LTD (Asia/Dhaka, UTC+6). Monday 2026-10-05.
-- Field member: the 8:00-12:00 day from the success check, timer-rounded (8:00:00 clock in, visit Start at
-- 9:00:40 records 61 minutes of General that end at 9:01, a few seconds past the visit's start).
insert into public.general_time_entries (organization_id, user_id, started_at, minutes, source)
values
	('18f0d717-904e-48d8-bd99-9df7e3844cda', '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', '2026-10-05 08:00:00+06', 61, 'timer'),
	('18f0d717-904e-48d8-bd99-9df7e3844cda', '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', '2026-10-05 11:00:40+06', 59, 'timer');
insert into public.job_time_entries (organization_id, job_id, user_id, started_at, minutes, source)
values ('18f0d717-904e-48d8-bd99-9df7e3844cda', 'fd9e7a6d-393f-46a5-bc11-1c6d6cb20e99', '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', '2026-10-05 09:00:40+06', 120, 'timer');

-- Admin: two typed entries that really overlap (13:00-14:00 and 13:30-15:00), and one on Tuesday.
insert into public.job_time_entries (organization_id, job_id, user_id, started_at, minutes, source, notes)
values
	('18f0d717-904e-48d8-bd99-9df7e3844cda', 'b6229fd7-c31a-44ed-8448-5f1d5fd18d64', 'df7d9de4-527a-4f42-88e4-6af3187470c6', '2026-10-05 13:00:00+06', 60, 'manual', 'Mowing'),
	('18f0d717-904e-48d8-bd99-9df7e3844cda', 'ed14da3e-db7a-4b48-a174-669074f56344', 'df7d9de4-527a-4f42-88e4-6af3187470c6', '2026-10-05 13:30:00+06', 90, 'manual', null),
	('18f0d717-904e-48d8-bd99-9df7e3844cda', 'b6229fd7-c31a-44ed-8448-5f1d5fd18d64', 'df7d9de4-527a-4f42-88e4-6af3187470c6', '2026-10-06 09:00:00+06', 45, 'manual', null);

-- Office member: a forgotten day clock, running since Sunday morning.
insert into public.running_timers (organization_id, user_id, kind, started_at)
values ('18f0d717-904e-48d8-bd99-9df7e3844cda', 'fd5e9676-477c-4c27-bd47-2af6b194a2cd', 'general', '2026-10-04 07:30:00+06');

set local role authenticated;

\echo '== Owner (everyone), week of Sun 4 Oct'
select set_config('request.jwt.claims', '{"sub":"1d50477c-8c55-4d33-a550-91ecf637b624","role":"authenticated"}', true);
select p->>'name' as name, p->>'total_minutes' as total, p->>'overlap_count' as overlaps, p->'running'->>'long_running' as long_running from jsonb_array_elements(public.timesheet_summary('18f0d717-904e-48d8-bd99-9df7e3844cda', '2026-10-07', 'week')->'people') as p;

\echo '== Owner opens the field member Monday'
select jsonb_pretty(public.timesheet_entries('18f0d717-904e-48d8-bd99-9df7e3844cda', '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', '2026-10-05', '2026-10-05'));

\echo '== Owner opens the admin Monday (overlaps)'
select e->>'started_at' as started, e->>'minutes' as minutes, e->>'overlaps' as overlaps, e->'job'->>'number' as job
from jsonb_array_elements(public.timesheet_entries('18f0d717-904e-48d8-bd99-9df7e3844cda', 'df7d9de4-527a-4f42-88e4-6af3187470c6', '2026-10-05', '2026-10-05')->'entries') as e;

\echo '== Field member (own only), same week'
select set_config('request.jwt.claims', '{"sub":"7d450c50-b3e5-4f97-8ee9-50e08c1f70bb","role":"authenticated"}', true);
select p->>'name' as name, p->>'total_minutes' as total, p->'days' as days, p->>'overlap_count' as overlaps
from jsonb_array_elements(public.timesheet_summary('18f0d717-904e-48d8-bd99-9df7e3844cda', '2026-10-07', 'week')->'people') as p;

\echo '== Field member opens their own Monday: job visibility'
select e->>'kind' as kind, e->'job' as job, e->>'overlaps' as overlaps
from jsonb_array_elements(public.timesheet_entries('18f0d717-904e-48d8-bd99-9df7e3844cda', '7d450c50-b3e5-4f97-8ee9-50e08c1f70bb', '2026-10-05', '2026-10-05')->'entries') as e;

\echo '== Field member tries a teammate (must refuse)'
savepoint refused;
\set ON_ERROR_STOP 0
select public.timesheet_entries('18f0d717-904e-48d8-bd99-9df7e3844cda', 'df7d9de4-527a-4f42-88e4-6af3187470c6', '2026-10-05', '2026-10-05');
rollback to savepoint refused;

\echo '== Sales member (no time permission, must refuse)'
select set_config('request.jwt.claims', '{"sub":"45228128-2e9e-419b-b60b-21670aa6ac31","role":"authenticated"}', true);
select public.timesheet_summary('18f0d717-904e-48d8-bd99-9df7e3844cda', '2026-10-07', 'week');
rollback to savepoint refused;

\echo '== A month is not a day or a week (must refuse)'
select set_config('request.jwt.claims', '{"sub":"1d50477c-8c55-4d33-a550-91ecf637b624","role":"authenticated"}', true);
select public.timesheet_summary('18f0d717-904e-48d8-bd99-9df7e3844cda', '2026-10-07', 'month');
rollback to savepoint refused;

\echo '== Anonymous cannot call the private reader'
reset role;
set local role anon;
select private.timesheet_rows('18f0d717-904e-48d8-bd99-9df7e3844cda', now(), now(), null);
rollback to savepoint refused;
rollback;
