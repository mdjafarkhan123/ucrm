-- Contractor Settings Part 4C: public rendering and abuse boundary, database layer.
-- Proves: public_slug is required and unique per organization (but freely repeatable across organizations),
-- create_form's slug validation, get_public_form_available_slots resolves a form by its org+form slug and
-- computes the same real slots as the shared engine while refusing an unknown pair, an unpublished form, a
-- disabled form, an archived form, a form belonging to a different organization, and a suspended organization
-- -- always with the one generic "not available" message; and submit_form_response's idempotency, its
-- booking-field-vs-outcome guard, its photo-key-prefix guard, and cross-organization isolation.
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive, so
-- do not run this through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

-- 1. Structure and least-privilege grants ------------------------------------------------------------------

select has_column('public', 'forms', 'public_slug', 'forms carries a public_slug column');
select col_not_null('public', 'forms', 'public_slug', 'public_slug is required on every form');
select is(
  (select count(*)::integer from pg_indexes
   where schemaname = 'public' and tablename = 'forms' and indexname = 'forms_organization_public_slug_idx'),
  1,
  'the public_slug uniqueness index exists, scoped per organization'
);
select has_function('private', 'compute_form_available_slots', 'the shared slot-computation helper exists');
select has_function('public', 'get_public_form_available_slots', 'the anonymous-safe slot reader exists');
select has_table('private', 'form_submissions', 'the submission staging table exists');
select has_function('public', 'submit_form_response', 'the anonymous-safe submission writer exists');
select is(
  (select relrowsecurity from pg_class where oid = 'private.form_submissions'::regclass),
  false,
  'form_submissions needs no RLS -- nothing but submit_form_response and the future 4D processor ever reads it'
);
select is(
  has_function_privilege('service_role', 'public.get_public_form_available_slots(text,text,date,date)', 'execute'),
  true, 'the service-role backend can read public availability'
);
select is(
  has_function_privilege('authenticated', 'public.get_public_form_available_slots(text,text,date,date)', 'execute'),
  false, 'a signed-in staff session has no reason to call the public-slug reader'
);
select is(
  has_function_privilege('anon', 'public.get_public_form_available_slots(text,text,date,date)', 'execute'),
  false, 'anon never talks to Postgres directly -- only the app''s service-role client does'
);
select is(
  has_function_privilege(
    'service_role',
    'public.submit_form_response(text,text,text,jsonb,jsonb,text[],uuid,timestamptz,timestamptz)', 'execute'
  ),
  true, 'the service-role backend can record a public submission'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.submit_form_response(text,text,text,jsonb,jsonb,text[],uuid,timestamptz,timestamptz)', 'execute'
  ),
  false, 'a signed-in staff session cannot submit as a public visitor'
);

-- 2. Fixtures -----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('4c0a0000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'public-forms-owner@example.test', 'test', now(), now(), now()),
  ('4c0a0000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'public-forms-other-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('4c0b0000-0000-0000-0000-000000000001', 'Public Forms Test Co', 'public-forms-test-co', 'active'),
  ('4c0b0000-0000-0000-0000-000000000002', 'Other Public Forms Co', 'other-public-forms-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('4c0b0000-0000-0000-0000-000000000001', '4c0a0000-0000-0000-0000-000000000001', 'owner'),
  ('4c0b0000-0000-0000-0000-000000000002', '4c0a0000-0000-0000-0000-000000000002', 'owner');

insert into public.catalog_items (id, organization_id, category, name, is_taxable)
values ('4c0c0000-0000-0000-0000-000000000001', '4c0b0000-0000-0000-0000-000000000001', 'service',
  'Drain Cleaning', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '4c0a0000-0000-0000-0000-000000000001', true);

-- 3. create_form's slug validation and per-organization uniqueness ------------------------------------------

select throws_ok(
  $$select public.create_form('4c0b0000-0000-0000-0000-000000000001', 'request', 'Blank Slug', '', 'Title')$$,
  '23514', null, 'an empty public slug is refused'
);

select throws_ok(
  $$select public.create_form(
    '4c0b0000-0000-0000-0000-000000000001', 'request', 'Bad Slug', 'Not A Slug!', 'Title'
  )$$,
  '23514', null, 'a slug with spaces or uppercase characters is refused'
);

select throws_ok(
  format(
    $$select public.create_form('4c0b0000-0000-0000-0000-000000000001', 'request', 'Too Long Slug', %L, 'Title')$$,
    repeat('a', 141)
  ),
  '23514', null, 'a slug over 140 characters is refused'
);

select is(
  public.create_form(
    '4c0b0000-0000-0000-0000-000000000001', 'request', 'Public Request Form', 'public-request-form',
    'Tell us about your project'
  ) ->> 'public_slug',
  'public-request-form',
  'a valid slug is stored and returned from create_form'
);

select throws_ok(
  $$select public.create_form(
    '4c0b0000-0000-0000-0000-000000000001', 'request', 'Second Form Same Slug', 'public-request-form', 'Title'
  )$$,
  '23505', null, 'a second form in the same organization cannot reuse a slug'
);

select public.publish_form_draft(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'public-request-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1
);

select set_config('request.jwt.claim.sub', '4c0a0000-0000-0000-0000-000000000002', true);

select is(
  public.create_form(
    '4c0b0000-0000-0000-0000-000000000002', 'request', 'Cross Org Duplicate Slug Form', 'public-request-form',
    'Title'
  ) ->> 'public_slug',
  'public-request-form',
  'a different organization may reuse the exact same slug string -- uniqueness is per organization, not global'
);

select is(
  (public.create_form(
    '4c0b0000-0000-0000-0000-000000000002', 'request', 'Org Two Exclusive Form', 'org-two-exclusive-form', 'Title'
  ) ->> 'form_id') is not null,
  true,
  'org two gets its own distinct-slug form, published below for the cross-organization resolution tests'
);

select public.publish_form_draft(
  '4c0b0000-0000-0000-0000-000000000002',
  (select id from public.forms where public_slug = 'org-two-exclusive-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000002'),
  1
);

select set_config('request.jwt.claim.sub', '4c0a0000-0000-0000-0000-000000000001', true);

-- 4. Remaining org-one fixtures: a bookable assessment form, and disabled/archived/draft-only forms ----------

select public.create_form(
  '4c0b0000-0000-0000-0000-000000000001', 'assessment', 'Public Assessment Form', 'public-assessment-form',
  'Book an assessment'
);
select public.update_form_booking_settings(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'public-assessment-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1, true, false, 120, 30, 60, null, 0, array['4c0c0000-0000-0000-0000-000000000001'::uuid]
);
select public.publish_form_draft(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'public-assessment-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1
);

select public.create_form(
  '4c0b0000-0000-0000-0000-000000000001', 'request', 'Disabled Form', 'disabled-form', 'Title'
);
select public.publish_form_draft(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'disabled-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1
);
select public.update_form_identity(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'disabled-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1, 'Disabled Form', false
);

select public.create_form(
  '4c0b0000-0000-0000-0000-000000000001', 'request', 'Archived Form', 'archived-form', 'Title'
);
select public.publish_form_draft(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'archived-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1
);
select public.archive_form(
  '4c0b0000-0000-0000-0000-000000000001',
  (select id from public.forms where public_slug = 'archived-form'
   and organization_id = '4c0b0000-0000-0000-0000-000000000001'),
  1
);

select public.create_form(
  '4c0b0000-0000-0000-0000-000000000001', 'request', 'Draft Only Form', 'draft-only-form', 'Title'
);

-- Business hours for the assessment form's slot test -- the same Monday 9-12 baseline the availability-engine
-- tests use, with no member availability restriction, so the owner is free the whole band.
set local role postgres;
update public.organization_settings set hours_mode = 'weekly'
where organization_id = '4c0b0000-0000-0000-0000-000000000001';
insert into public.organization_business_hours (organization_id, weekday, period_index, is_open, opens_at, closes_at)
values ('4c0b0000-0000-0000-0000-000000000001', 1, 0, true, time '09:00', time '12:00')
on conflict (organization_id, weekday, period_index) do update
  set is_open = excluded.is_open, opens_at = excluded.opens_at, closes_at = excluded.closes_at;

-- 5. get_public_form_available_slots: resolution and the one generic refusal ---------------------------------

select is(
  (select array_agg(start_time order by start_time) from public.get_public_form_available_slots(
    'public-forms-test-co', 'public-assessment-form', date '2099-01-05', date '2099-01-05'
  )),
  array[time '09:00', time '09:30', time '10:00', time '10:30', time '11:00'],
  'the public wrapper resolves the form by its org+form slug and computes real slots from the shared engine'
);

select throws_ok(
  $$select * from public.get_public_form_available_slots(
    'public-forms-test-co', 'does-not-exist', date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', 'That form is not available.', 'an unknown slug pair is refused with one generic message'
);

select throws_ok(
  $$select * from public.get_public_form_available_slots(
    'public-forms-test-co', 'org-two-exclusive-form', date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', 'That form is not available.',
  'a real, published form slug that belongs to a different organization does not resolve'
);

select throws_ok(
  $$select * from public.get_public_form_available_slots(
    'public-forms-test-co', 'draft-only-form', date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', 'That form is not available.', 'a form with no published version is not available publicly'
);

select throws_ok(
  $$select * from public.get_public_form_available_slots(
    'public-forms-test-co', 'disabled-form', date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', 'That form is not available.',
  'a disabled form is not available publicly, even though it was once published'
);

select throws_ok(
  $$select * from public.get_public_form_available_slots(
    'public-forms-test-co', 'archived-form', date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', 'That form is not available.', 'an archived form is not available publicly'
);

-- 6. submit_form_response: idempotency, guards, and cross-organization isolation ------------------------------

select is(
  (public.submit_form_response(
    'public-forms-test-co', 'public-request-form', 'idem-key-001',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'),
    jsonb_build_object('q1', 'Fix my sink')
  ) ->> 'already_received')::boolean,
  false,
  'a first submission on a request form is received fresh'
);

select is(
  (select count(*)::integer from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'public-request-form'
     and organization_id = '4c0b0000-0000-0000-0000-000000000001')),
  1,
  'the submission is staged for Part 4D'
);

select is(
  (public.submit_form_response(
    'public-forms-test-co', 'public-request-form', 'idem-key-001',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'),
    jsonb_build_object('q1', 'Fix my sink')
  ) ->> 'already_received')::boolean,
  true,
  'repeating the same idempotency key returns the original submission instead of creating a second one'
);

select is(
  (select count(*)::integer from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'public-request-form'
     and organization_id = '4c0b0000-0000-0000-0000-000000000001')),
  1,
  'the repeat did not create a second row'
);

select is(
  (public.submit_form_response(
    'public-forms-test-co', 'public-request-form', 'idem-key-002',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'),
    jsonb_build_object('q1', 'Also fix my faucet')
  ) ->> 'already_received')::boolean,
  false,
  'a genuinely new idempotency key on the same form creates a second, separate submission'
);

select is(
  (select count(*)::integer from private.form_submissions
   where form_id = (select id from public.forms where public_slug = 'public-request-form'
     and organization_id = '4c0b0000-0000-0000-0000-000000000001')),
  2,
  'two distinct visits are now staged'
);

select throws_ok(
  $$select public.submit_form_response(
    'public-forms-test-co', 'public-request-form', 'idem-key-003',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb,
    '{}'::text[], null, timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  )$$,
  '23514', 'This form does not book a time.', 'a request form refuses booking fields even if a visitor sends them'
);

select throws_ok(
  $$select public.submit_form_response(
    'public-forms-test-co', 'public-assessment-form', 'idem-key-004',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb
  )$$,
  '23514', 'Choose a time for this visit.', 'a booking form refuses a submission with no chosen time'
);

select throws_ok(
  $$select public.submit_form_response(
    'public-forms-test-co', 'public-assessment-form', 'idem-key-005',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb,
    '{}'::text[], gen_random_uuid(),
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  )$$,
  '23514', 'Choose one of the listed services.', 'a service id that is not offered on this form is refused'
);

select is(
  (public.submit_form_response(
    'public-forms-test-co', 'public-assessment-form', 'idem-key-006',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb,
    array[(
      select o.id::text || '/public-form-submissions/' || f.id::text || '/photo1.jpg'
      from public.organizations as o
      join public.forms as f on f.organization_id = o.id
      where o.slug = 'public-forms-test-co' and f.public_slug = 'public-assessment-form'
    )],
    '4c0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  ) ->> 'already_received')::boolean,
  false,
  'a booking submission with a correctly-scoped photo key and a valid chosen service is received'
);

select throws_ok(
  $$select public.submit_form_response(
    'public-forms-test-co', 'public-assessment-form', 'idem-key-007',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb,
    array['somewhere/else/photo.jpg'],
    '4c0c0000-0000-0000-0000-000000000001'::uuid,
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  )$$,
  '23514', 'That photo does not belong to this form.', 'a photo key outside this exact form''s own prefix is refused'
);

select throws_ok(
  $$select public.submit_form_response(
    'public-forms-test-co', 'public-request-form', 'idem-key-008',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb,
    (select array_agg('x' || g) from generate_series(1, 21) as g)
  )$$,
  '23514', 'Too many photos on one submission.', 'more than twenty photos on one submission is refused'
);

select throws_ok(
  $$select public.submit_form_response(
    'public-forms-test-co', 'org-two-exclusive-form', 'idem-key-009',
    jsonb_build_object('name', 'Jane Doe', 'email', 'jane@example.test'), '{}'::jsonb
  )$$,
  '23514', 'That form is not available.',
  'submitting against a real form slug that belongs to a different organization is refused'
);

-- 7. A suspended organization's own, otherwise-valid form is not available either -------------------------------

set local role postgres;
update public.organizations set lifecycle_status = 'suspended'
where id = '4c0b0000-0000-0000-0000-000000000002';

select throws_ok(
  $$select * from public.get_public_form_available_slots(
    'other-public-forms-co', 'org-two-exclusive-form', date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', 'That form is not available.',
  'a properly published, enabled form in a suspended organization is not available publicly'
);

select * from finish();
rollback;
