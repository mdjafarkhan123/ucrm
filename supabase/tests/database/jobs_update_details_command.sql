-- Jobs, Part 8: the staged edit of a job's title and instructions.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_direct_creation_and_visits.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- 1. Privileges --------------------------------------------------------------------------------------------

select is(
  has_function_privilege(
    'anon', 'public.update_job_details(uuid, uuid, integer, text, text)', 'execute'
  ),
  false, 'signed-out callers cannot edit a job'
);
select is(
  has_function_privilege(
    'authenticated', 'public.update_job_details(uuid, uuid, integer, text, text)', 'execute'
  ),
  true, 'members reach the edit command'
);

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-edit-office@example.test', 'test', now(), now(), now()),
  ('b1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-edit-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('b2000000-0000-0000-0000-000000000001', 'Edit Org A', 'edit-org-a', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'office'),
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'field');

insert into public.clients (id, organization_id, display_name)
values ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'Edit Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', '1 Edit Way', 'Testville', 'TX', '78741');

-- One job to edit, created through the real command so it starts at revision 0 with its own job_created
-- event, exactly as production makes it.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);

select public.create_job_with_visits(
  'b2000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000001',
  'b4000000-0000-0000-0000-000000000001',
  'Update target job',
  'Original instructions',
  true,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
  'idem-edit-0001',
  'hash-edit-0001'
);

-- 3. A real edit, as the office member ---------------------------------------------------------------------

-- Only one job lives in this org, so this subselect is a stable handle no matter what the title becomes.
select is(
  (public.update_job_details(
    'b2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
    0,
    'Renamed job',
    'Bring the big ladder'
  ))->>'revision',
  '1', 'the office member saves the details and the revision bumps to 1'
);

select is(
  (select title from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  'Renamed job', 'the title was updated'
);
select is(
  (select instructions from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  'Bring the big ladder', 'the instructions were updated'
);
select is(
  (select revision from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
  1, 'the stored revision is now 1'
);

select is(
  (select count(*)::int from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.organization_id = 'b2000000-0000-0000-0000-000000000001' and e.event_type = 'details_updated'),
  1, 'the edit emitted one details_updated event'
);
select is(
  (select metadata->'changed' from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.organization_id = 'b2000000-0000-0000-0000-000000000001' and e.event_type = 'details_updated'),
  '["title", "instructions"]'::jsonb, 'the event names the two fields that changed'
);

-- 4. Guards ------------------------------------------------------------------------------------------------

-- The revision the caller sent is stale now that the save above bumped it to 1.
select throws_ok(
  $$ select public.update_job_details(
    'b2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
    0, 'Stale write', null
  ) $$,
  'P0409', null, 'a stale revision is refused rather than clobbering the newer save'
);

-- A job that does not exist in this organization is not found.
select throws_ok(
  $$ select public.update_job_details(
    'b2000000-0000-0000-0000-000000000001',
    'b9000000-0000-0000-0000-000000000099',
    1, 'No such job', null
  ) $$,
  'P0404', null, 'editing a missing job is a not-found'
);

-- A field member does not hold jobs.edit.
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.update_job_details(
    'b2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
    1, 'Field member cannot edit', null
  ) $$,
  '42501', null, 'a member without jobs.edit is refused'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);

-- An empty title is caught by the jobs table's own length check, surfacing as 23514.
select throws_ok(
  $$ select public.update_job_details(
    'b2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
    1, 'x', null
  ) $$,
  '23514', null, 'a title shorter than two characters is refused by the table check'
);

-- 5. A no-op save still advances the revision and records that nothing of the two fields changed -----------

select is(
  (public.update_job_details(
    'b2000000-0000-0000-0000-000000000001',
    (select id from public.jobs where organization_id = 'b2000000-0000-0000-0000-000000000001'),
    1,
    'Renamed job',
    'Bring the big ladder'
  ))->>'revision',
  '2', 'saving unchanged values still hands back the next revision'
);
-- The no-op edit adds a details_updated event whose changed list is empty. Both edits share this
-- transaction's start time, so an ordering could not tell them apart; the empty list itself is the handle.
select is(
  (select count(*)::int from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.organization_id = 'b2000000-0000-0000-0000-000000000001'
      and e.event_type = 'details_updated' and e.metadata->'changed' = '[]'::jsonb),
  1, 'a no-op save records an empty changed list'
);

select * from finish();
rollback;
