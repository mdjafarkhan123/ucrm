-- Jobs, Part 6: the list's read model — derived status, the tenant boundary on the list view, and the
-- overview counts.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(32);

-- 1. Shape and privileges ----------------------------------------------------------------------------------

select has_view('public', 'job_list_rows', 'the jobs list reads from a view, not from the table directly');

select is(
  (select c.relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'jobs'),
  true, 'the table behind the view still enforces row level security'
);

-- The view is security invoker, which is the whole reason it is safe: without it the view owner's rights
-- would be used and every member would read every organization's jobs.
select is(
  (select 'security_invoker=true' = any(c.reloptions) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'job_list_rows'),
  true, 'the list view runs with the reader''s own rights'
);

select is(
  has_table_privilege('anon', 'public.job_list_rows', 'select'),
  false, 'signed-out callers cannot read the jobs list'
);
select is(
  has_table_privilege('authenticated', 'public.job_list_rows', 'select'),
  true, 'members read the jobs list through the view'
);

-- The financial fence holds through the view: the view never selects a money column, so there is no
-- column for a member to read even by name.
select hasnt_column('public', 'job_list_rows', 'total_minor', 'the list view carries no job total');
select hasnt_column('public', 'job_list_rows', 'cost_minor', 'the list view carries no internal cost');
select has_column('public', 'job_list_rows', 'derived_status', 'the list view names the status a person reads');

select is(
  has_function_privilege('anon', 'public.job_status_counts(uuid)', 'execute'),
  false, 'signed-out callers cannot count an organization''s jobs'
);
select is(
  has_function_privilege('authenticated', 'public.job_status_counts(uuid)', 'execute'),
  true, 'members reach the overview counts'
);
select is(
  has_function_privilege('anon', 'private.organization_today(uuid)', 'execute'),
  false, 'signed-out callers cannot ask what day it is for an organization'
);

-- 2. The derivation rule, without a clock -------------------------------------------------------------------

select is(
  private.job_derived_status('closed', 'one_off', null, date '2026-09-01'),
  'archived', 'a closed job reads as archived'
);
select is(
  private.job_derived_status('closed', 'recurring', date '2026-09-10', date '2026-09-01'),
  'archived', 'archived beats a contract that is running out'
);
select is(
  private.job_derived_status('active', 'recurring', date '2026-09-10', date '2026-09-01'),
  'ending_soon', 'a recurring agreement ending within 30 days reads as ending soon'
);
select is(
  private.job_derived_status('active', 'recurring', date '2026-10-01', date '2026-09-01'),
  'ending_soon', 'the thirtieth day is still within 30 days'
);
select is(
  private.job_derived_status('active', 'recurring', date '2026-10-02', date '2026-09-01'),
  'unscheduled', 'a contract ending later than 30 days out is not ending soon yet'
);
select is(
  private.job_derived_status('active', 'recurring', date '2026-08-31', date '2026-09-01'),
  'unscheduled', 'a contract whose end date has already passed is not ending soon'
);
select is(
  private.job_derived_status('active', 'one_off', date '2026-09-10', date '2026-09-01'),
  'unscheduled', 'ending soon belongs to recurring agreements, not one-off work'
);
select is(
  private.job_derived_status('active', 'one_off', null, date '2026-09-01'),
  'unscheduled', 'an active job with nothing on the calendar reads as unscheduled'
);

-- 3. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-list-admin-a@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-list-admin-b@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-list-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('96000000-0000-0000-0000-000000000001', 'List Org A', 'list-org-a', 'active'),
  ('96000000-0000-0000-0000-000000000002', 'List Org B', 'list-org-b', 'active');

-- Org A keeps time in Auckland, which is a day ahead of UTC for most of the year. The derived status has to
-- read the contractor's calendar, not the server's.
insert into public.organization_settings (organization_id, timezone, locale, currency_code)
values ('96000000-0000-0000-0000-000000000001', 'Pacific/Auckland', 'en-NZ', 'NZD')
on conflict (organization_id) do update set timezone = excluded.timezone;

insert into public.organization_members (organization_id, user_id, role)
values
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 'admin'),
  ('96000000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000002', 'admin'),
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000003', 'field');

insert into public.clients (id, organization_id, display_name, company_name)
values
  ('97000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001', 'List Client A', 'A Holdings'),
  ('97000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000002', 'List Client B', null);

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values
  ('98000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001', '7 List Lane', 'Testville', 'TX', '78741'),
  ('98000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000002', '8 Other Lane', 'Otherville', 'TX', '78742');

select private.create_job(
  '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001', 'Org A open job', 'one_off', 'job_total', 'NZD',
  '95000000-0000-0000-0000-000000000001'
);

select private.create_job(
  '96000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000002',
  '98000000-0000-0000-0000-000000000002', 'Org B open job', 'one_off', 'job_total', 'USD',
  '95000000-0000-0000-0000-000000000002'
);

-- A recurring agreement in org A that runs out next week, and one that runs out next year.
insert into public.jobs (
  organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
  contract_end_date
) values (
  '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001', 500, 'Ends next week', 'recurring', 'per_visit', 'NZD',
  (private.organization_today('96000000-0000-0000-0000-000000000001') + 7)
), (
  '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001', 501, 'Ends next year', 'recurring', 'per_visit', 'NZD',
  (private.organization_today('96000000-0000-0000-0000-000000000001') + 300)
);

update public.jobs
set status = 'closed', closed_at = now()
where organization_id = '96000000-0000-0000-0000-000000000001' and job_number = 501;

select is(
  private.organization_today('96000000-0000-0000-0000-000000000001'),
  (now() at time zone 'Pacific/Auckland')::date,
  'today is read in the organization''s own timezone'
);
select is(
  private.organization_today('96000000-0000-0000-0000-000000000002'),
  (now() at time zone 'UTC')::date,
  'an organization with no settings row falls back to UTC rather than to nothing'
);

-- 4. What each reader sees ------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::int from public.job_list_rows),
  3, 'an admin sees their own organization''s jobs and no others'
);

select is(
  (select derived_status from public.job_list_rows
    where organization_id = '96000000-0000-0000-0000-000000000001' and job_number = 500),
  'ending_soon', 'a contract running out next week reads as ending soon on the list'
);

select is(
  (select derived_status from public.job_list_rows
    where organization_id = '96000000-0000-0000-0000-000000000001' and job_number = 501),
  'archived', 'a closed job reads as archived on the list'
);

select is(
  (select client_display_name from public.job_list_rows
    where organization_id = '96000000-0000-0000-0000-000000000001' and job_number = 1),
  'List Client A', 'the list carries the client name without a second query'
);

select is(
  (select property_address_line1 from public.job_list_rows
    where organization_id = '96000000-0000-0000-0000-000000000001' and job_number = 1),
  '7 List Lane', 'the list carries the property address without a second query'
);

select is(
  (select count(*)::int from public.job_status_counts('96000000-0000-0000-0000-000000000001')
    where derived_status = 'unscheduled' and total = 1),
  1, 'the overview counts the open job nobody has scheduled'
);
select is(
  (select count(*)::int from public.job_status_counts('96000000-0000-0000-0000-000000000001')
    where derived_status = 'ending_soon' and total = 1),
  1, 'the overview counts the agreement that is running out'
);

-- Counting another organization's jobs returns nothing, because the reader's own RLS on jobs decides which
-- rows the count can see.
select is(
  (select coalesce(sum(total), 0)::int from public.job_status_counts('96000000-0000-0000-0000-000000000002')),
  0, 'a member cannot count another organization''s jobs'
);

select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.job_list_rows),
  1, 'the other organization sees only its own job'
);

-- A field member holds jobs.view but not customers.view, so the job is visible and the client name it may
-- not read comes back empty rather than leaking.
select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::int from public.job_list_rows),
  3, 'a field member still sees the organization''s jobs'
);

select is(
  (select client_display_name from public.job_list_rows
    where organization_id = '96000000-0000-0000-0000-000000000001' and job_number = 1),
  null, 'a reader without customers.view gets no client name off the jobs list'
);

select * from finish();
rollback;
