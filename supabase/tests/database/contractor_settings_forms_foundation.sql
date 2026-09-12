-- Contractor Settings Part 4A: request/booking form identity + Draft -> Published lifecycle.
-- Proves table shape and least-privilege grants, the create/edit/publish command chain, the published-version
-- immutability trigger, stale-revision (P0409) rejection on every revision-checked command, the one-default-
-- per-outcome-group rule, permission enforcement, cross-tenant RLS isolation, and that revising a published
-- form opens a new draft seeded from the published content.
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive, so
-- do not run this through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

-- 1. Structure and least-privilege grants ------------------------------------------------------------------

select has_table('public', 'forms', 'the forms table exists');
select has_table('public', 'form_versions', 'the form_versions table exists');
select is((select relrowsecurity from pg_class where oid = 'public.forms'::regclass), true,
  'RLS is enabled on forms');
select is((select relrowsecurity from pg_class where oid = 'public.form_versions'::regclass), true,
  'RLS is enabled on form_versions');
select is(has_table_privilege('authenticated', 'public.forms', 'select'), true,
  'a signed-in session may read forms');
select is(has_table_privilege('authenticated', 'public.forms', 'insert'), false,
  'a signed-in session may not write forms directly (writes go through definer commands)');
select is(has_table_privilege('authenticated', 'public.form_versions', 'update'), false,
  'a signed-in session may not write form_versions directly');

-- 2. Fixtures -----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('f4a10000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'forms-owner@example.test', 'test', now(), now(), now()),
  ('f4a10000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'forms-field@example.test', 'test', now(), now(), now()),
  ('f4a10000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'forms-other-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f4a20000-0000-0000-0000-000000000001', 'Forms Test Co', 'forms-test-co', 'active'),
  ('f4a20000-0000-0000-0000-000000000002', 'Other Forms Co', 'forms-other-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('f4a20000-0000-0000-0000-000000000001', 'f4a10000-0000-0000-0000-000000000001', 'owner'),
  ('f4a20000-0000-0000-0000-000000000001', 'f4a10000-0000-0000-0000-000000000002', 'field'),
  ('f4a20000-0000-0000-0000-000000000002', 'f4a10000-0000-0000-0000-000000000003', 'owner');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f4a10000-0000-0000-0000-000000000001', true);

-- 3. Create a form ------------------------------------------------------------------------------------------

select is(
  public.create_form(
    'f4a20000-0000-0000-0000-000000000001', 'request', 'Kitchen Remodel Request', 'Tell us about your kitchen'
  ) ->> 'outcome',
  'request',
  'creating a form records the outcome it produces'
);

select is(
  (select status from public.form_versions
   where form_id = (select id from public.forms where organization_id = 'f4a20000-0000-0000-0000-000000000001'
     and name = 'Kitchen Remodel Request')),
  'draft',
  'a brand new form starts with a draft, not a published version'
);

-- 4B-1: a new form also starts with a usable default builder, not an empty content blob.
select is(
  (select content -> 'contact' -> 'email' ->> 'required' from public.form_versions
   where form_id = (select id from public.forms where name = 'Kitchen Remodel Request')),
  'true',
  'a new form starts with a usable default builder -- email is required out of the box'
);

select is(
  (select jsonb_array_length(content -> 'sections') from public.form_versions
   where form_id = (select id from public.forms where name = 'Kitchen Remodel Request')),
  0,
  'a new form starts with no custom sections'
);

select is(
  (select is_default from public.forms where name = 'Kitchen Remodel Request'),
  false,
  'a new form is not the default until someone says so'
);

select throws_ok(
  $$select public.create_form('f4a20000-0000-0000-0000-000000000001', 'quote', 'Bad outcome', 'Title')$$,
  '23514', null, 'an outcome outside request/assessment/job is refused'
);

-- 4. Edit the draft, then reject a stale save --------------------------------------------------------------

select is(
  public.update_form_draft(
    'f4a20000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Kitchen Remodel Request'),
    1, 'Tell us about your kitchen project', 'A bit more detail up front.',
    jsonb_build_object(
      'contact', jsonb_build_object(
        'name', jsonb_build_object('required', true),
        'email', jsonb_build_object('shown', true, 'required', true, 'marketing_consent', false),
        'phone', jsonb_build_object('shown', true, 'required', true, 'marketing_consent', false),
        'company', jsonb_build_object('shown', false, 'required', false),
        'address', jsonb_build_object('shown', true, 'required', false)
      ),
      'sections', jsonb_build_array(jsonb_build_object(
        'id', 'sec-1', 'title', 'Project details',
        'questions', jsonb_build_array(jsonb_build_object(
          'id', 'q-1', 'type', 'short_text', 'label', 'What room?', 'required', true
        ))
      )),
      'photos', jsonb_build_object('enabled', true, 'max', 5),
      'confirmation', jsonb_build_object('title', 'Got it', 'message', 'Thanks!', 'redirect_url', null)
    )
  ) ->> 'title',
  'Tell us about your kitchen project',
  'editing the draft updates the customer-facing title'
);

select is(
  (select content -> 'sections' -> 0 ->> 'title' from public.form_versions
   where form_id = (select id from public.forms where name = 'Kitchen Remodel Request')
     and status = 'draft'),
  'Project details',
  'saving the draft stores the builder content (a custom section) alongside the title'
);

select throws_ok(
  format(
    $$select public.update_form_draft('f4a20000-0000-0000-0000-000000000001', %L, 1, 'Stale edit', null, '{}'::jsonb)$$,
    (select id from public.forms where name = 'Kitchen Remodel Request')
  ),
  'P0409', null, 'a draft save that names the wrong revision is refused, not silently overwritten'
);

select throws_ok(
  format(
    $$select public.update_form_draft('f4a20000-0000-0000-0000-000000000001', %L, 2, 'Bad content', null, '[]'::jsonb)$$,
    (select id from public.forms where name = 'Kitchen Remodel Request')
  ),
  '23514', null, 'draft content that is not a json object is refused'
);

select throws_ok(
  format(
    $$select public.update_form_draft('f4a20000-0000-0000-0000-000000000001', %L, 2, 'Too big', null,
        jsonb_build_object('x', repeat('a', 70000)))$$,
    (select id from public.forms where name = 'Kitchen Remodel Request')
  ),
  '23514', null, 'draft content beyond the gross size bound is refused'
);

-- 5. Publish, then prove the frozen version is immutable -----------------------------------------------------

select is(
  public.publish_form_draft(
    'f4a20000-0000-0000-0000-000000000001', (select id from public.forms where name = 'Kitchen Remodel Request'),
    2
  ) ->> 'version_number',
  '1',
  'publishing the draft freezes version 1'
);

select is(
  (select draft_version_id is null and current_published_version_id is not null
   from public.forms where name = 'Kitchen Remodel Request'),
  true,
  'publishing clears the draft pointer and sets the published pointer'
);

select is(
  (select published_at is not null from public.form_versions
   where id = (select current_published_version_id from public.forms where name = 'Kitchen Remodel Request')),
  true,
  'the published version is stamped with when it went live'
);

set local role postgres;

select throws_ok(
  format(
    $$update public.form_versions set title = 'Rewriting history' where id = %L$$,
    (select current_published_version_id from public.forms where name = 'Kitchen Remodel Request')
  ),
  '23514', 'A published form version is immutable.', 'a published version can never be edited again, by anyone'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f4a10000-0000-0000-0000-000000000001', true);

select throws_ok(
  format(
    $$select public.publish_form_draft('f4a20000-0000-0000-0000-000000000001', %L, 1)$$,
    (select id from public.forms where name = 'Kitchen Remodel Request')
  ),
  '23514', null, 'a form with no draft in progress cannot be published again'
);

-- 6. Revising after publish opens a new draft seeded from the published content -----------------------------

select is(
  public.create_form_draft(
    'f4a20000-0000-0000-0000-000000000001', (select id from public.forms where name = 'Kitchen Remodel Request')
  ) ->> 'draft_version_number',
  '2',
  'revising a published form starts version 2, never reopens version 1'
);

select is(
  (select title from public.form_versions
   where form_id = (select id from public.forms where name = 'Kitchen Remodel Request')
     and version_number = 2),
  'Tell us about your kitchen project',
  'the new draft is seeded from the published content, not left blank'
);

select is(
  (select content -> 'sections' -> 0 ->> 'title' from public.form_versions
   where form_id = (select id from public.forms where name = 'Kitchen Remodel Request')
     and version_number = 2),
  'Project details',
  'the new draft copies the published builder content, not just the title'
);

select is(
  (select draft_version_id from public.forms where name = 'Kitchen Remodel Request') is not null,
  true,
  'the form now has a draft in progress again'
);

select throws_ok(
  format(
    $$select public.create_form_draft('f4a20000-0000-0000-0000-000000000001', %L)$$,
    (select id from public.forms where name = 'Kitchen Remodel Request')
  ),
  '23514', null, 'a form cannot have two drafts in progress at once'
);

-- 7. Identity edits and stale-revision rejection -------------------------------------------------------------

select is(
  public.update_form_identity(
    'f4a20000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Kitchen Remodel Request'), 1, 'Kitchen Remodel Requests', false
  ) ->> 'is_enabled',
  'false',
  'renaming and disabling a form saves together'
);

select throws_ok(
  format(
    $$select public.update_form_identity('f4a20000-0000-0000-0000-000000000001', %L, 1, 'Stale rename', true)$$,
    (select id from public.forms where name = 'Kitchen Remodel Requests')
  ),
  'P0409', null, 'renaming with the wrong expected revision is refused'
);

-- 8. Only one default per outcome group ------------------------------------------------------------------

select is(
  public.set_form_default(
    'f4a20000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Kitchen Remodel Requests'), 2
  ) ->> 'is_default',
  'true',
  'the first request form can become the default request form'
);

select is(
  public.create_form(
    'f4a20000-0000-0000-0000-000000000001', 'request', 'Second Request Form', 'Second form'
  ) ->> 'form_id' is not null,
  true,
  'a second request form can exist alongside the default'
);

select is(
  public.set_form_default(
    'f4a20000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Second Request Form'), 1
  ) ->> 'is_default',
  'true',
  'making a second request form the default succeeds'
);

select is(
  (select is_default from public.forms where name = 'Kitchen Remodel Requests'),
  false,
  'promoting a new default request form demotes the old one -- only one at a time'
);

select is(
  public.create_form(
    'f4a20000-0000-0000-0000-000000000001', 'assessment', 'Free Assessment', 'Book an assessment'
  ) ->> 'form_id' is not null,
  true,
  'an assessment form can be created'
);

select is(
  public.set_form_default(
    'f4a20000-0000-0000-0000-000000000001', (select id from public.forms where name = 'Free Assessment'), 1
  ) ->> 'is_default',
  'true',
  'the assessment form becomes the default booking form'
);

select is(
  public.create_form(
    'f4a20000-0000-0000-0000-000000000001', 'job', 'Instant Job Booking', 'Book a job directly'
  ) ->> 'form_id' is not null,
  true,
  'a job-outcome form can be created'
);

select is(
  public.set_form_default(
    'f4a20000-0000-0000-0000-000000000001', (select id from public.forms where name = 'Instant Job Booking'), 1
  ) ->> 'is_default',
  'true',
  'a job form can become the default, sharing the booking slot with assessment'
);

select is(
  (select is_default from public.forms where name = 'Free Assessment'),
  false,
  'assessment and job share one booking default slot -- the job form promotion demoted the assessment form'
);

select is(
  (select is_default from public.forms where name = 'Second Request Form'),
  true,
  'the request default is untouched by booking-slot changes -- request and booking are separate groups'
);

-- 9. Archive and restore -------------------------------------------------------------------------------------

select is(
  (public.archive_form(
    'f4a20000-0000-0000-0000-000000000001', (select id from public.forms where name = 'Second Request Form'), 2
  ) ->> 'archived')::boolean,
  true,
  'archiving a form succeeds'
);

select is(
  (select is_default from public.forms where name = 'Second Request Form'),
  false,
  'archiving the default request form clears its default status -- an archived form can never be the default'
);

select throws_ok(
  format(
    $$select public.update_form_identity('f4a20000-0000-0000-0000-000000000001', %L, 3, 'Edit while archived', true)$$,
    (select id from public.forms where name = 'Second Request Form')
  ),
  '23514', null, 'an archived form must be restored before it can be edited'
);

select is(
  (public.restore_form(
    'f4a20000-0000-0000-0000-000000000001', (select id from public.forms where name = 'Second Request Form'), 3
  ) ->> 'archived')::boolean,
  false,
  'restoring a form succeeds'
);

-- 10. Permission enforcement ----------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f4a10000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.create_form('f4a20000-0000-0000-0000-000000000001', 'request', 'Field Member Form', 'Title')$$,
  '42501', null, 'a field member without settings.forms.manage cannot create a form'
);

select is(
  (select count(*)::integer from public.forms where organization_id = 'f4a20000-0000-0000-0000-000000000001'),
  0,
  'a field member without settings.forms.manage cannot even see the organization''s forms'
);

-- 11. Cross-organization isolation -----------------------------------------------------------------------------

-- Captured as postgres (bypassing RLS) so the hijack attempt below targets a real, existing form id --
-- proving the block is the permission check, not just that the outsider cannot look the id up.
set local role postgres;
select set_config('test.hijack_form_id',
  (select id::text from public.forms where name = 'Kitchen Remodel Requests'), true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f4a10000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::integer from public.forms where organization_id = 'f4a20000-0000-0000-0000-000000000001'),
  0,
  'an owner of a different organization sees none of another business''s forms'
);

select throws_ok(
  format(
    $$select public.update_form_identity('f4a20000-0000-0000-0000-000000000001', %L, 2, 'Hijacked', true)$$,
    current_setting('test.hijack_form_id')::uuid
  ),
  '42501', null, 'an outsider owner cannot manage another organization''s form even by guessing its id'
);

select * from finish();
rollback;
