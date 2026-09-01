-- Jobs, Part 4: identity, numbering, lifecycle, permissions, and the tenant boundary.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(57);

-- Job money left the `authenticated` grant, so every money assertion below goes through public.job_money
-- rather than through the privileges of whichever member the test is currently pretending to be.
--
-- throws_ok's three-argument form takes (query, errcode, errmsg) in this pgTAP build, not
-- (query, errcode, description). Checking an error code therefore uses the four-argument form with a null
-- message, or the description quietly becomes the message the assertion is looking for.

-- 1. Shape ------------------------------------------------------------------------------------------------

select has_table('public', 'organization_job_counters', 'the job number counter table exists');
select has_table('public', 'jobs', 'the job identity table exists');
select has_table('public', 'job_events', 'jobs own a history table');

select has_index('public', 'jobs', 'jobs_quote_lineage_idx', 'the one-job-per-quote index exists');
select has_index('public', 'jobs', 'jobs_conversion_key_idx', 'the conversion idempotency index exists');
select has_index('public', 'jobs', 'jobs_active_idx', 'the open work list index exists');

select has_column('public', 'jobs', 'is_as_needed', 'an as-needed agreement is a flag on a recurring job');
select has_column('public', 'jobs', 'revision', 'a job carries the revision a stale writer is checked against');

-- 2. Privileges -------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'private.allocate_job_number(uuid)', 'execute'),
  false, 'anonymous callers cannot allocate a job number'
);
select is(
  has_function_privilege('authenticated', 'private.allocate_job_number(uuid)', 'execute'),
  false, 'members cannot allocate a job number themselves'
);
select is(
  has_function_privilege(
    'authenticated',
    'private.create_job(uuid, uuid, uuid, text, text, text, text, uuid, boolean, text, text, uuid, uuid, text, text)',
    'execute'
  ),
  false, 'members cannot create a job row directly'
);
select is(
  has_function_privilege('anon', 'public.job_money(uuid[])', 'execute'),
  false, 'anonymous callers cannot read job money'
);
select is(
  has_function_privilege('authenticated', 'public.job_money(uuid[])', 'execute'),
  true, 'members reach job money through the gated reader'
);

select is(
  has_table_privilege('authenticated', 'public.jobs', 'insert'),
  false, 'members cannot insert a job'
);
select is(
  has_table_privilege('authenticated', 'public.jobs', 'update'),
  false, 'members cannot update a job'
);
select is(
  has_table_privilege('authenticated', 'public.jobs', 'delete'),
  false, 'members cannot delete a job'
);
select is(
  has_table_privilege('authenticated', 'public.job_events', 'insert'),
  false, 'members cannot write job history'
);
select is(
  has_table_privilege('authenticated', 'public.organization_job_counters', 'select'),
  false, 'members cannot count an organization''s jobs through the counter'
);

-- The financial fence: money columns are absent from the grant, so a member reading the table directly
-- through PostgREST gets the job and not its money.
select is(
  has_column_privilege('authenticated', 'public.jobs', 'total_minor', 'select'),
  false, 'the job total is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.jobs', 'subtotal_minor', 'select'),
  false, 'the job subtotal is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.jobs', 'cost_minor', 'select'),
  false, 'internal cost is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.jobs', 'title', 'select'),
  true, 'the parts of a job that are not money stay readable'
);

-- 3. Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-admin-a@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-admin-b@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-office-a@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('91000000-0000-0000-0000-000000000001', 'Job Org A', 'job-org-a', 'active'),
  ('91000000-0000-0000-0000-000000000002', 'Job Org B', 'job-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'admin'),
  ('91000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', 'admin'),
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000003', 'office'),
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000004', 'field');

insert into public.clients (id, organization_id, display_name)
values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'Job Client A'),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Job Client B'),
  ('92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000001', 'Job Client A2');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '4 Job Lane', 'Testville'),
  ('93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000002', '4 Other Lane', 'Otherville'),
  ('93000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000003', '5 Job Lane', 'Testville');

-- 4. Numbering --------------------------------------------------------------------------------------------

select is(
  (private.create_job(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'Org A first job', 'one_off', 'job_total', 'USD',
    '90000000-0000-0000-0000-000000000001'
  )).job_number,
  1, 'an organization numbers its jobs from one'
);

select is(
  (private.create_job(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'Org A second job', 'recurring', 'per_visit', 'USD',
    '90000000-0000-0000-0000-000000000001', true
  )).job_number,
  2, 'the next job in the same organization takes the next number'
);

select is(
  (private.create_job(
    '91000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000002',
    '93000000-0000-0000-0000-000000000002', 'Org B first job', 'one_off', 'job_total', 'USD',
    '90000000-0000-0000-0000-000000000002'
  )).job_number,
  1, 'each organization numbers its jobs from one'
);

select is(
  (select count(*)::int from public.job_events
    where event_type = 'job_created'
      and organization_id = '91000000-0000-0000-0000-000000000001'),
  2, 'creating a job writes its first history row'
);

-- 5. What a job refuses ------------------------------------------------------------------------------------

select throws_ok(
  $q$select private.create_job(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000003', 'Wrong property', 'one_off', 'job_total', 'USD',
    '90000000-0000-0000-0000-000000000001'
  )$q$,
  'That property does not belong to that client.',
  'a job cannot be booked at a property belonging to another client'
);

select throws_ok(
  $q$select private.create_job(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000002', 'Cross tenant property', 'one_off', 'job_total', 'USD',
    '90000000-0000-0000-0000-000000000001'
  )$q$,
  'That property does not belong to that client.',
  'a job cannot be booked at another organization''s property'
);

select throws_ok(
  $q$select private.create_job(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'A', 'one_off', 'job_total', 'USD',
    '90000000-0000-0000-0000-000000000001'
  )$q$,
  'A job needs a title between 2 and 160 characters.',
  'a job needs a real title'
);

select throws_ok(
  $q$insert into public.jobs (
    organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
  ) values (
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 900, 'Mismatched basis', 'one_off', 'per_visit', 'USD'
  )$q$,
  '23514'::char(5),
  null::text,
  'a one-off job cannot be priced per visit'
);

select throws_ok(
  $q$insert into public.jobs (
    organization_id, client_id, property_id, job_number, title, job_type, is_as_needed, price_basis, currency_code
  ) values (
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 901, 'As needed one off', 'one_off', true, 'job_total', 'USD'
  )$q$,
  '23514'::char(5),
  null::text,
  'a one-off job cannot be an as-needed agreement'
);

select throws_ok(
  $q$insert into public.jobs (
    organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
    contract_start_date, contract_end_date
  ) values (
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 902, 'Backwards contract', 'recurring', 'per_visit', 'USD',
    '2026-09-30', '2026-09-01'
  )$q$,
  '23514'::char(5),
  null::text,
  'a contract cannot end before it starts'
);

select throws_ok(
  $q$insert into public.jobs (
    organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
    arrival_window_minutes
  ) values (
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 903, 'Half a window', 'one_off', 'job_total', 'USD', 60
  )$q$,
  '23514'::char(5),
  null::text,
  'an arrival window needs both a length and a style'
);

select throws_ok(
  $q$insert into public.jobs (
    organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code, status
  ) values (
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 904, 'Invented state', 'one_off', 'job_total', 'USD', 'archived'
  )$q$,
  '23514'::char(5),
  null::text,
  'Archived is a label the reader computes, not a state a row may hold'
);

-- 6. What can never change ---------------------------------------------------------------------------------

select throws_ok(
  $q$update public.jobs set job_type = 'recurring', price_basis = 'per_visit'
     where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1$q$,
  'A job type cannot be changed after the job is created. Create a new job instead.',
  'job type is fixed at creation'
);

select throws_ok(
  $q$update public.jobs set is_as_needed = false
     where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 2$q$,
  'A job type cannot be changed after the job is created. Create a new job instead.',
  'an ordinary recurring job cannot quietly become an as-needed one'
);

select throws_ok(
  $q$update public.jobs set job_number = 77
     where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1$q$,
  'A job number cannot be changed.',
  'a job number is permanent'
);

select throws_ok(
  $q$update public.jobs set client_id = '92000000-0000-0000-0000-000000000003'
     where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1$q$,
  'A job cannot be moved to another client.',
  'a job cannot be moved to another client'
);

select throws_ok(
  $q$update public.jobs set quote_id = '94000000-0000-0000-0000-000000000009'
     where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1$q$,
  'Quote lineage cannot be changed.',
  'a direct job cannot later claim a quote it did not come from'
);

select throws_ok(
  $q$update public.jobs set organization_id = '91000000-0000-0000-0000-000000000002'
     where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1$q$,
  'A job cannot be moved to another organization.',
  'a job cannot be moved to another organization'
);

-- 7. The two states it does have ----------------------------------------------------------------------------

update public.jobs set status = 'closed'
where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1;

select is(
  (select (closed_at is not null) from public.jobs
    where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1),
  true, 'closing a job stamps when it closed'
);

update public.jobs set status = 'active'
where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1;

select is(
  (select (closed_at is null and reopened_at is not null) from public.jobs
    where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1),
  true, 'reopening a job clears the closing stamp and records the reopening'
);

-- 8. Row level security --------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::int from public.jobs),
  2, 'an admin sees their own organization''s jobs'
);

select is(
  (select count(*)::int from public.jobs where organization_id = '91000000-0000-0000-0000-000000000002'),
  0, 'another organization''s jobs are invisible even when asked for by id'
);

select is(
  (select count(*)::int from public.job_events),
  2, 'an admin sees their own organization''s job history'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.jobs),
  1, 'the other organization sees only its own job'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);

select is(
  (select count(*)::int from public.jobs),
  2, 'a field member can open the work they are standing in front of'
);

-- 9. The gated money reader ------------------------------------------------------------------------------------

set local role postgres;
update public.jobs
set subtotal_minor = 200000, tax_minor = 20000, total_minor = 220000, cost_minor = 80000
where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1;

-- The job id is held outside RLS on purpose. A member of the other organization cannot select this job,
-- and asking for money with an id that resolved to null would prove nothing.
create temp table job_ref as
  select id from public.jobs
  where organization_id = '91000000-0000-0000-0000-000000000001' and job_number = 1;
grant select on job_ref to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select is(
  (public.job_money(array[(select id from job_ref)])
    -> (select id::text from job_ref)
    ->> 'total_minor'),
  '220000', 'an admin reads the job total through the gated reader'
);

select is(
  (public.job_money(array[(select id from job_ref)])
    -> (select id::text from job_ref)
    ->> 'cost_minor'),
  '80000', 'an admin reads internal cost through the gated reader'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);

select is(
  (public.job_money(array[(select id from job_ref)])
    -> (select id::text from job_ref)
    ->> 'total_minor'),
  '220000', 'an office member reads prices'
);

select is(
  (public.job_money(array[(select id from job_ref)])
    -> (select id::text from job_ref)
    ->> 'cost_minor'),
  null, 'an office member is not given internal cost'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);

select is(
  (public.job_money(array[(select id from job_ref)])),
  '{}'::jsonb, 'a field member holding neither money permission gets nothing back'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $q$select public.job_money(array[(select id from job_ref)])$q$,
  'You do not have access to these jobs.',
  'money for a job you cannot see is refused rather than answered'
);

-- 10. Seeded permissions ---------------------------------------------------------------------------------------

set local role postgres;

select is(
  (select count(*)::int from public.permissions where key like 'jobs.%'),
  5, 'only the five job permissions whose behavior exists are seeded'
);

select is(
  (select count(*)::int from public.role_permissions
    where role = 'field' and permission_key = 'jobs.view'),
  1, 'the field role can see jobs'
);

select is(
  (select count(*)::int from public.role_permissions
    where role = 'field' and permission_key in ('jobs.view_price', 'jobs.view_cost')),
  0, 'the field role is given neither price nor cost'
);

select is(
  (select count(*)::int from public.role_permissions
    where role = 'office' and permission_key = 'jobs.view_cost'),
  0, 'the office role sees prices but not internal cost'
);

select * from finish();
rollback;
