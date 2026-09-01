-- Jobs, Part 7: direct one-off job creation and its visits.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_list_read_model.sql documents. Do not
-- run it through a runner that executes each statement separately: `set local role` and `set_config` do not
-- survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- 1. Shape and privileges ----------------------------------------------------------------------------------

select has_table('public', 'job_visits', 'a job''s appointments have their own table');
select has_table('public', 'job_visit_assignments', 'a visit''s people have their own table');
select has_table('public', 'job_command_receipts', 'the idempotency ledger exists');

select is(
  (select c.relrowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'job_visits'),
  true, 'visits enforce row level security'
);

select is(
  has_table_privilege('authenticated', 'public.job_visits', 'insert'),
  false, 'members cannot write visits directly; only the command may'
);
select is(
  has_table_privilege('authenticated', 'public.job_visits', 'select'),
  true, 'members read visits'
);
select is(
  has_table_privilege('authenticated', 'public.job_command_receipts', 'select'),
  false, 'the receipt ledger is not a member-readable table'
);
select is(
  has_function_privilege(
    'anon',
    'public.create_job_with_visits(uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb)',
    'execute'
  ),
  false, 'signed-out callers cannot create a job'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.create_job_with_visits(uuid, uuid, uuid, text, text, boolean, jsonb, jsonb, text, text, text, boolean, jsonb)',
    'execute'
  ),
  true, 'members reach the create command'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-create-office@example.test', 'test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-create-field@example.test', 'test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-create-other-org@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('a2000000-0000-0000-0000-000000000001', 'Create Org A', 'create-org-a', 'active'),
  ('a2000000-0000-0000-0000-000000000002', 'Create Org B', 'create-org-b', 'active');

insert into public.organization_settings (organization_id, timezone, locale, currency_code)
values ('a2000000-0000-0000-0000-000000000001', 'America/Chicago', 'en-US', 'CAD')
on conflict (organization_id) do update set currency_code = excluded.currency_code;

insert into public.organization_members (organization_id, user_id, role)
values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'office'),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'field'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name)
values
  ('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Create Client A'),
  ('a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'Create Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values
  ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', '1 Create Way', 'Testville', 'TX', '78741'),
  ('a4000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000002', '2 Create Way', 'Otherville', 'TX', '78742');

-- 3. A real create, as the office member ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);

select is(
  (public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'Repaint the front office',
    'Gate code is 4417',
    true,
    '[{"position":0,"line_kind":"priced","category":"service","name":"Interior painting","quantity":2,"unit_price_minor":15000,"unit_cost_minor":4000,"is_taxable":true}]'::jsonb,
    jsonb_build_array(
      jsonb_build_object('position', 0, 'visit_date', to_char(current_date, 'YYYY-MM-DD'), 'start_time', '09:00', 'end_time', '11:00', 'all_day', false, 'assignee_ids', jsonb_build_array('a1000000-0000-0000-0000-000000000001')),
      jsonb_build_object('position', 1, 'visit_date', null, 'all_day', false)
    ),
    'idem-create-0001',
    'hash-create-0001'
  ))->>'applied',
  'true', 'the office member creates the job'
);

-- Read the job that was just created for the rest of the assertions.
select is(
  (select count(*)::int from public.jobs
    where organization_id = 'a2000000-0000-0000-0000-000000000001' and title = 'Repaint the front office'),
  1, 'exactly one job row was written'
);

select is(
  (select currency_code from public.jobs
    where organization_id = 'a2000000-0000-0000-0000-000000000001' and title = 'Repaint the front office'),
  'CAD', 'the job takes the organization''s currency'
);

select is(
  (select billing_timing from public.jobs
    where organization_id = 'a2000000-0000-0000-0000-000000000001' and title = 'Repaint the front office'),
  'on_closure', 'invoice-on-close true stores the on_closure reminder'
);

select is(
  (select count(*)::int from public.job_visits v
    join public.jobs j on j.id = v.job_id
    where j.title = 'Repaint the front office'),
  2, 'both visits were written'
);

-- The first visit is a booked appointment, the second is backlog with no date.
select is(
  (select v.visit_date is not null and v.start_time = time '09:00'
    from public.job_visits v join public.jobs j on j.id = v.job_id
    where j.title = 'Repaint the front office' and v.position = 0),
  true, 'the first visit is a timed appointment'
);
select is(
  (select v.visit_date is null and v.start_time is null
    from public.job_visits v join public.jobs j on j.id = v.job_id
    where j.title = 'Repaint the front office' and v.position = 1),
  true, 'the second visit is unscheduled backlog'
);

select is(
  (select count(*)::int from public.job_visit_assignments a
    join public.job_visits v on v.id = a.visit_id
    join public.jobs j on j.id = v.job_id
    where j.title = 'Repaint the front office'),
  1, 'the assignee on the first visit was recorded'
);

select is(
  (select count(*)::int from public.job_line_items li
    join public.jobs j on j.id = li.job_id
    where j.title = 'Repaint the front office'),
  1, 'the scope line was written'
);

-- 2 * 150.00 = 300.00, no tax configured, so the total is the subtotal. Read through the gated reader,
-- which the office member (jobs.view_price) is entitled to.
select is(
  (
    select (public.job_money(array[j.id])->(j.id::text)->>'total_minor')::bigint
    from public.jobs j where j.title = 'Repaint the front office'
  ),
  30000::bigint, 'the job total was calculated and stored'
);

select is(
  (select count(*)::int from public.job_events e
    join public.jobs j on j.id = e.job_id
    where j.title = 'Repaint the front office' and e.event_type = 'job_created'),
  1, 'creating the job emitted one job_created event'
);

-- 4. Idempotency and conflict --------------------------------------------------------------------------------

-- The same key and the same fingerprint returns the first job and makes no second one.
select is(
  (public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'Repaint the front office',
    'Gate code is 4417',
    true,
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
    'idem-create-0001',
    'hash-create-0001'
  ))->>'applied',
  'false', 'a retry with the same key does not create a second job'
);

select is(
  (select count(*)::int from public.jobs
    where organization_id = 'a2000000-0000-0000-0000-000000000001' and title = 'Repaint the front office'),
  1, 'still exactly one job after the retry'
);

select throws_ok(
  $$ select public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'A different job under the same key',
    null, true, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
    'idem-create-0001', 'a-changed-fingerprint'
  ) $$,
  'P0409', null, 'the same key with different details is a conflict, not a silent second job'
);

-- 5. Guards --------------------------------------------------------------------------------------------------

-- A field member does not hold jobs.create.
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'Field member should not create this', null, true, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
    'idem-field-0001', 'hash-field-0001'
  ) $$,
  '42501', null, 'a member without jobs.create is refused'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);

-- Zero visits and too many visits are both refused.
select throws_ok(
  $$ select public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001', 'No visits', null, true, '[]'::jsonb,
    '[]'::jsonb, 'idem-zero-0001', 'hash-zero-0001'
  ) $$,
  '23514', null, 'a one-off job needs at least one visit'
);

select throws_ok(
  $$ select public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001', 'Too many visits', null, true, '[]'::jsonb,
    (select jsonb_agg(jsonb_build_object('position', g, 'visit_date', null)) from generate_series(0, 20) g),
    'idem-many-0001', 'hash-many-0001'
  ) $$,
  '23514', null, 'more than twenty visits is refused'
);

-- A property that belongs to a different client is refused by the job writer.
select throws_ok(
  $$ select public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000002', 'Wrong property', null, true, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
    'idem-prop-0001', 'hash-prop-0001'
  ) $$,
  '23514', null, 'a property from another client cannot receive the job'
);

-- An assignee from another organization is refused by the assignment''s composite foreign key.
select throws_ok(
  $$ select public.create_job_with_visits(
    'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001', 'Cross-tenant assignee', null, true, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null, 'assignee_ids', jsonb_build_array('a1000000-0000-0000-0000-000000000003'))),
    'idem-xtenant-0001', 'hash-xtenant-0001'
  ) $$,
  '23503', null, 'a visit cannot be assigned to someone from another organization'
);

select * from finish();
rollback;
