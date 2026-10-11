-- Rolled-back performance proof of the Timesheets reads (performance-review § Verify). Nothing here is kept.
-- Workload: Raad LTD (Asia/Dhaka) with 15 people who time their work, 26 weeks of ordinary history (6 entries
-- a person a day) and a very busy week of Sun 4 - Sat 10 Oct 2026 (12 entries a person a day, ~1,260).
-- Run: psql "$SUPABASE_DB_URL" -X -f docs/research/time-clock-timesheets-2026-10-11/performance-proof.sql
\set ON_ERROR_STOP 1
\set org '\'18f0d717-904e-48d8-bd99-9df7e3844cda\''
begin;

-- Ten more field members, so 15 people can time their work (the six existing who may, less sales, + 10).
create temporary table crew on commit drop as
select gen_random_uuid() as user_id, n from generate_series(1, 10) as n;
insert into auth.users (id, email, aud, role)
select user_id, 'timesheet-perf-' || n || '@example.invalid', 'authenticated', 'authenticated' from crew;
update public.profiles set full_name = 'Perf Crew ' || lpad(crew.n::text, 2, '0')
from crew where profiles.id = crew.user_id;
insert into public.organization_members (organization_id, user_id, role, status)
select :org, user_id, 'field', 'active' from crew;

create temporary table people on commit drop as
select member.user_id, row_number() over (order by member.user_id) as n
from public.organization_members as member
where member.organization_id = :org and member.status = 'active'
	and private.can_run_own_timer(:org, member.user_id);
grant select on people to authenticated;
\echo '== People who time their work'
select count(*) from people;

create temporary table org_jobs on commit drop as
select id, row_number() over (order by id) as n from public.jobs where organization_id = :org;

-- Ordinary history: 26 weeks before the busy week, 4 Job + 2 General entries a person a day, 50 min each.
insert into public.job_time_entries (organization_id, job_id, user_id, started_at, minutes, source)
select :org, (select id from org_jobs where org_jobs.n = 1 + (people.n + slot) % (select count(*) from org_jobs)),
	people.user_id, day + make_interval(hours => 8 + slot), 50, 'timer'
from people, generate_series(date '2026-04-05', date '2026-10-03', interval '1 day') as day,
	generate_series(0, 3) as slot;
insert into public.general_time_entries (organization_id, user_id, started_at, minutes, source)
select :org, people.user_id, day + make_interval(hours => 13 + slot), 50, 'timer'
from people, generate_series(date '2026-04-05', date '2026-10-03', interval '1 day') as day,
	generate_series(0, 1) as slot;

-- The busy week: 8 Job + 4 General entries a person a day, 40 min apart, 35 min each. Every fifth person
-- has one typed entry a day that overlaps their next one.
insert into public.job_time_entries (organization_id, job_id, user_id, started_at, minutes, source)
select :org, (select id from org_jobs where org_jobs.n = 1 + (people.n + slot) % (select count(*) from org_jobs)),
	people.user_id, (day::timestamp + make_interval(hours => 7, mins => 40 * slot)) at time zone 'Asia/Dhaka',
	case when people.n % 5 = 0 and slot = 2 then 60 else 35 end, 'timer'
from people, generate_series(date '2026-10-04', date '2026-10-10', interval '1 day') as day,
	generate_series(0, 7) as slot;
insert into public.general_time_entries (organization_id, user_id, started_at, minutes, source)
select :org, people.user_id, (day::timestamp + make_interval(hours => 13, mins => 20 + 40 * slot)) at time zone 'Asia/Dhaka',
	35, 'timer'
from people, generate_series(date '2026-10-04', date '2026-10-10', interval '1 day') as day,
	generate_series(0, 3) as slot;

-- Three timers running now, one forgotten since Sunday.
insert into public.running_timers (organization_id, user_id, kind, started_at)
select :org, user_id, 'general', case when n = 1 then timestamptz '2026-10-04 07:30+06' else now() - interval '1 hour' end
from people where n <= 3
on conflict do nothing;

analyze public.job_time_entries;
analyze public.general_time_entries;
analyze public.running_timers;

\echo '== Rows for this business: job, general'
select (select count(*) from public.job_time_entries where organization_id = :org),
	(select count(*) from public.general_time_entries where organization_id = :org);

-- The inner window scan, as the summary runs it for everyone (only_user_id null). Run as the owner role
-- of the database, since private.timesheet_rows is a definer function whose plan EXPLAIN cannot see into.
\echo '== Window scan: Job hours, everyone, busy week +/- 1 day'
explain (analyze, buffers, costs off, summary off)
select entry.user_id, entry.started_at, entry.minutes
from public.job_time_entries as entry
where entry.organization_id = :org
	and entry.started_at >= timestamptz '2026-10-04 00:00+06' - interval '1 day'
	and entry.started_at < timestamptz '2026-10-11 00:00+06' + interval '1 day';

\echo '== Window scan: General hours, one person, busy week +/- 1 day'
explain (analyze, buffers, costs off, summary off)
select entry.user_id, entry.started_at, entry.minutes
from public.general_time_entries as entry
where entry.organization_id = :org
	and entry.user_id = (select user_id from people where n = 4)
	and entry.started_at >= timestamptz '2026-10-04 00:00+06' - interval '1 day'
	and entry.started_at < timestamptz '2026-10-11 00:00+06' + interval '1 day';

\echo '== The whole overlap pass, everyone, busy week'
explain (analyze, buffers, costs off)
select count(*), count(*) filter (where "overlaps")
from private.timesheet_rows(:org, timestamptz '2026-10-04 00:00+06', timestamptz '2026-10-11 00:00+06', null);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"1d50477c-8c55-4d33-a550-91ecf637b624","role":"authenticated"}', true);

\echo '== Owner: week summary, three runs (Execution Time is the server time)'
explain (analyze, costs off, timing off) select public.timesheet_summary(:org, '2026-10-07', 'week');
explain (analyze, costs off, timing off) select public.timesheet_summary(:org, '2026-10-07', 'week');
explain (analyze, costs off, timing off) select public.timesheet_summary(:org, '2026-10-07', 'week');

\echo '== Owner: day summary'
explain (analyze, costs off, timing off) select public.timesheet_summary(:org, '2026-10-07', 'day');

\echo '== Owner: one person''s busy week of entries, three runs'
explain (analyze, costs off, timing off)
select public.timesheet_entries(:org, (select user_id from people where n = 5), '2026-10-04', '2026-10-10');
explain (analyze, costs off, timing off)
select public.timesheet_entries(:org, (select user_id from people where n = 5), '2026-10-04', '2026-10-10');
explain (analyze, costs off, timing off)
select public.timesheet_entries(:org, (select user_id from people where n = 5), '2026-10-04', '2026-10-10');

\echo '== Response sizes in bytes (JSON as sent, before compression): summary week, summary day, entries week'
select octet_length(public.timesheet_summary(:org, '2026-10-07', 'week')::text) as summary_week,
	octet_length(public.timesheet_summary(:org, '2026-10-07', 'day')::text) as summary_day,
	octet_length(public.timesheet_entries(:org, (select user_id from people where n = 5), '2026-10-04', '2026-10-10')::text) as entries_week;

\echo '== Shape check: people, overlapping people, long timers, entries in one week'
select jsonb_array_length(s->'people') as people,
	(select count(*) from jsonb_array_elements(s->'people') p where (p->>'overlap_count')::int > 0) as overlapping,
	(select count(*) from jsonb_array_elements(s->'people') p where (p->'running'->>'long_running')::boolean) as long_timers,
	(select sum((p->>'entry_count')::int) from jsonb_array_elements(s->'people') p) as entries
from (select public.timesheet_summary(:org, '2026-10-07', 'week') as s) as summary;

rollback;
