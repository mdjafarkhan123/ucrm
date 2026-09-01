-- Jobs, Part 10a: recurring and as-needed scheduling.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_direct_creation_and_visits.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

-- 1. Shape and privileges ----------------------------------------------------------------------------------

select has_table('public', 'job_recurrence_rules', 'a recurring job''s rule has its own table');

select is(
  (select c.relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'job_recurrence_rules'),
  true, 'the rule table enforces row level security'
);

select is(
  has_table_privilege('authenticated', 'public.job_recurrence_rules', 'select'),
  true, 'members read the rule on the job page'
);
select is(
  has_table_privilege('authenticated', 'public.job_recurrence_rules', 'insert'),
  false, 'members never write the rule directly; only the commands may'
);

select is(
  has_function_privilege('anon', 'public.preview_job_recurrence(jsonb)', 'execute'),
  false, 'signed-out callers cannot ask for a preview'
);
select is(
  has_function_privilege('authenticated', 'public.preview_job_recurrence(jsonb)', 'execute'),
  true, 'members reach the preview'
);
select is(
  has_function_privilege(
    'authenticated',
    'private.job_recurrence_dates(text, integer, smallint[], text, smallint, smallint, smallint, date, date)',
    'execute'
  ),
  false, 'the date engine is internal; nobody calls it from outside'
);

-- 2. The date maths ------------------------------------------------------------------------------------------

-- Jobber's own New Job page shows "26 visits" for weekly work over six months, which is the number this has
-- to agree with.
select is(
  (select count(*)::int from private.job_recurrence_dates(
    'weekly', 1, array[1]::smallint[], null, null, null, null, '2026-09-07', '2027-03-06')),
  26, 'weekly on Mondays for six months makes 26 visits'
);

-- Every two weeks on Monday and Wednesday keeps both days inside the same week rather than alternating
-- between them, which is what a crew booked "Mondays and Wednesdays, fortnightly" actually means.
select is(
  (select array_agg(day order by day) from private.job_recurrence_dates(
    'weekly', 2, array[1,3]::smallint[], null, null, null, null, '2026-09-07', '2026-10-08') as day),
  array['2026-09-07', '2026-09-09', '2026-09-21', '2026-09-23', '2026-10-05', '2026-10-07']::date[],
  'a fortnightly pair of weekdays stays in the same week'
);

-- A rule on the 31st has no February. The month is skipped rather than quietly moved, which is what the
-- iCalendar standard does and what "the 31st" plainly means.
select is(
  (select array_agg(day order by day) from private.job_recurrence_dates(
    'monthly', 1, null, 'day_of_month', 31::smallint, null, null, '2026-01-31', '2026-06-30') as day),
  array['2026-01-31', '2026-03-31', '2026-05-31']::date[],
  'a monthly rule on the 31st skips the months that have no 31st'
);

select is(
  (select array_agg(day order by day) from private.job_recurrence_dates(
    'monthly', 1, null, 'last_day', null, null, null, '2026-01-01', '2026-04-30') as day),
  array['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']::date[],
  'the last-day rule lands on every month including February'
);

select is(
  (select array_agg(day order by day) from private.job_recurrence_dates(
    'monthly', 1, null, 'day_of_week', null, 1::smallint, 5::smallint, '2026-09-01', '2026-11-30') as day),
  array['2026-09-04', '2026-10-02', '2026-11-06']::date[],
  'the first Friday of each month'
);

-- Ordinal 5 means the last one in the month, not a literal fifth week that only exists sometimes.
select is(
  (select array_agg(day order by day) from private.job_recurrence_dates(
    'monthly', 1, null, 'day_of_week', null, 5::smallint, 5::smallint, '2026-09-01', '2026-11-30') as day),
  array['2026-09-25', '2026-10-30', '2026-11-27']::date[],
  'the last Friday of each month'
);

select is(
  (select count(*)::int from private.job_recurrence_dates(
    'daily', 1, null, null, null, null, null, '2026-09-01', '2026-09-10')),
  10, 'a daily rule lands on every day in its window'
);

select is(
  (select count(*)::int from private.job_recurrence_dates(
    'weekly', 1, array[1]::smallint[], null, null, null, null, '2026-09-07', '2026-09-06')),
  0, 'a window that ends before it starts produces nothing'
);

-- The engine stops one past the ceiling, so a caller can tell "exactly at the limit" from "over it" without
-- counting the whole series twice.
select is(
  (select count(*)::int from private.job_recurrence_dates(
    'daily', 1, null, null, null, null, null, '2020-01-01', '2029-12-31')),
  private.job_recurrence_limit() + 1, 'generation stops one row past the ceiling'
);

-- 3. Reading a rule out of the form's json ---------------------------------------------------------------------

-- "Ends after 6 months" from the 7th runs to the day before the 7th six months later, so the agreement is
-- six whole months rather than six months and a day.
select is(
  (select end_date from private.read_job_recurrence(
    '{"frequency":"weekly","weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb)),
  '2027-03-06'::date, 'a six-month duration resolves to the day before the six-month mark'
);

select is(
  (select end_date from private.read_job_recurrence(
    '{"frequency":"daily","start_date":"2026-09-07","end_mode":"on","end_date":"2026-09-30"}'::jsonb)),
  '2026-09-30'::date, 'an explicit end date is taken as given'
);

select throws_ok(
  $$ select * from private.read_job_recurrence('{"frequency":"weekly","start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb) $$,
  '23514', null, 'a weekly rule naming no day is refused in words a person can act on'
);

-- A missing `weekdays` key is not the same as an empty one, and it used to walk past this guard: jsonb_typeof
-- of a missing key is null, which made the whole condition null instead of false.
select throws_ok(
  $$ select * from private.read_job_recurrence('{"frequency":"weekly","weekdays":[],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb) $$,
  '23514', null, 'a weekly rule with an empty day list is refused the same way'
);

select throws_ok(
  $$ select * from private.read_job_recurrence('{"frequency":"monthly","start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb) $$,
  '23514', null, 'a monthly rule with no chosen shape is refused'
);

select throws_ok(
  $$ select * from private.read_job_recurrence('{"frequency":"daily","start_date":"2026-09-07","end_mode":"after","duration_count":20,"duration_unit":"year"}'::jsonb) $$,
  '23514', null, 'a schedule running more than ten years is refused'
);

-- 4. Fixtures ---------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-recur-office@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c2000000-0000-0000-0000-000000000001', 'Recur Org', 'recur-org', 'active');

insert into public.organization_settings (organization_id, timezone, locale, currency_code)
values ('c2000000-0000-0000-0000-000000000001', 'America/Chicago', 'en-US', 'USD')
on conflict (organization_id) do update set currency_code = excluded.currency_code;

insert into public.organization_members (organization_id, user_id, role)
values ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'office');

insert into public.clients (id, organization_id, display_name)
values ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Recur Client');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', '9 Recur Way', 'Testville', 'TX', '78743');

-- 5. Creating a recurring job -------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

select is(
  (public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001',
    'Weekly grounds care',
    null,
    true,
    '[{"position":0,"line_kind":"priced","category":"service","name":"Mowing","quantity":1,"unit_price_minor":12000,"unit_cost_minor":3000,"is_taxable":true}]'::jsonb,
    '[]'::jsonb,
    'idem-recur-0001',
    'hash-recur-0001',
    'recurring',
    false,
    '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month","start_time":"08:00","end_time":"10:00"}'::jsonb
  ))->>'visit_count',
  '26', 'the command generates the same 26 visits the preview counts'
);

select is(
  (select count(*)::int from public.job_visits v
    join public.jobs j on j.id = v.job_id
    where j.title = 'Weekly grounds care' and v.source = 'generated'),
  26, 'every generated visit is marked as generated, not manual'
);

select is(
  (select count(distinct (start_time, end_time))::int from public.job_visits v
    join public.jobs j on j.id = v.job_id
    where j.title = 'Weekly grounds care'),
  1, 'every generated visit carries the schedule''s own time'
);

select is(
  (select job_type from public.jobs where title = 'Weekly grounds care'),
  'recurring', 'the job is stored as recurring'
);

-- The contract window is what "Ending soon" reads, and it comes from the rule rather than the last visit.
select is(
  (select (contract_start_date, contract_end_date) from public.jobs where title = 'Weekly grounds care'),
  ('2026-09-07'::date, '2027-03-06'::date),
  'the job carries the rule''s window as its contract dates'
);

select is(
  (select (frequency, interval_count, weekdays) from public.job_recurrence_rules r
    join public.jobs j on j.id = r.job_id where j.title = 'Weekly grounds care'),
  ('weekly'::text, 1::integer, array[1]::smallint[]),
  'the rule is stored as columns, not as a string nobody can query'
);

select is(
  (select count(*)::int from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.title = 'Weekly grounds care' and e.event_type = 'visits_generated'),
  1, 'generating the visits is recorded in the job''s history'
);

-- 6. As-needed work ------------------------------------------------------------------------------------------------

select is(
  (public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001',
    'Snow removal on call',
    null,
    true,
    '[]'::jsonb,
    '[]'::jsonb,
    'idem-recur-0002',
    'hash-recur-0002',
    'recurring',
    true,
    null
  ))->>'visit_count',
  '0', 'an as-needed job is created with no visits at all'
);

select is(
  (select is_as_needed from public.jobs where title = 'Snow removal on call'),
  true, 'the job knows it is as-needed'
);

select is(
  (select count(*)::int from public.job_recurrence_rules r
    join public.jobs j on j.id = r.job_id where j.title = 'Snow removal on call'),
  0, 'an as-needed job has no rule row; "no schedule" is stored as no schedule'
);

-- 7. The shapes the command refuses ----------------------------------------------------------------------------------

select throws_ok(
  $$ select public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001', 'Bad one-off', null, true, '[]'::jsonb,
    '[{"position":0,"visit_date":"2026-09-07"}]'::jsonb, 'idem-recur-0003', 'hash-recur-0003',
    'one_off', false,
    '{"frequency":"weekly","weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb
  ) $$,
  '23514', null, 'a one-off job carrying a repeat rule is refused'
);

select throws_ok(
  $$ select public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001', 'Bad recurring', null, true, '[]'::jsonb,
    '[]'::jsonb, 'idem-recur-0004', 'hash-recur-0004', 'recurring', false, null
  ) $$,
  '23514', null, 'a recurring job with no schedule is refused'
);

select throws_ok(
  $$ select public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001', 'Bad recurring visits', null, true, '[]'::jsonb,
    '[{"position":0,"visit_date":"2026-09-07"}]'::jsonb, 'idem-recur-0005', 'hash-recur-0005',
    'recurring', false,
    '{"frequency":"weekly","weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb
  ) $$,
  '23514', null, 'a recurring job may not also list typed visits'
);

select throws_ok(
  $$ select public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001', 'Bad as-needed', null, true, '[]'::jsonb,
    '[{"position":0,"visit_date":"2026-09-07"}]'::jsonb, 'idem-recur-0006', 'hash-recur-0006',
    'recurring', true, null
  ) $$,
  '23514', null, 'an as-needed job that also lists visits is refused'
);

-- Over the ceiling nothing is written at all: the refusal comes before the job can be left half-made.
select throws_ok(
  $$ select public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001', 'Too many visits', null, true, '[]'::jsonb,
    '[]'::jsonb, 'idem-recur-0007', 'hash-recur-0007', 'recurring', false,
    '{"frequency":"daily","interval_count":1,"start_date":"2026-01-01","end_mode":"on","end_date":"2029-12-31"}'::jsonb
  ) $$,
  '23514', null, 'a schedule over the ceiling is refused rather than written'
);

-- 8. A repeat of the same create is not a second job ---------------------------------------------------------------

select is(
  (public.create_job_with_visits(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001',
    'Weekly grounds care',
    null,
    true,
    '[{"position":0,"line_kind":"priced","category":"service","name":"Mowing","quantity":1,"unit_price_minor":12000,"unit_cost_minor":3000,"is_taxable":true}]'::jsonb,
    '[]'::jsonb,
    'idem-recur-0001',
    'hash-recur-0001',
    'recurring',
    false,
    '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month","start_time":"08:00","end_time":"10:00"}'::jsonb
  ))->>'applied',
  'false', 'the same key and fingerprint replays the first job instead of generating again'
);

select is(
  (select count(*)::int from public.jobs where title = 'Weekly grounds care'),
  1, 'the replay left exactly one job'
);

select is(
  (select count(*)::int from public.job_visits v
    join public.jobs j on j.id = v.job_id where j.title = 'Weekly grounds care'),
  26, 'the replay did not generate a second set of visits'
);

-- 9. Job type stays fixed --------------------------------------------------------------------------------------------

set local role postgres;

select throws_ok(
  $$ update public.jobs set job_type = 'one_off' where title = 'Weekly grounds care' $$,
  '23514', null, 'a recurring job can never be switched to one-off'
);

-- One row out, so a runner that only shows the last non-empty result still shows the verdict.
select coalesce((select string_agg(line, E'
') from finish() as line), 'PASS: all 41 assertions') as result;
rollback;
