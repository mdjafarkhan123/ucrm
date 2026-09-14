begin;

create extension if not exists pgtap with schema extensions;
select plan(22);

select has_table('public', 'communication_sms_registration_submissions',
  'attested registration submissions are first-class records');
select has_index('public', 'communication_sms_registration_submissions',
  'communication_sms_registration_submissions_history_idx',
  'submission history has an organization-scoped ordered index');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.communication_sms_registration_submissions'::regclass),
  'submission snapshots keep row-level security enabled');
select table_privs_are('public', 'communication_sms_registration_submissions', 'authenticated', array[]::text[],
  'authenticated clients cannot read registration PII directly');
select table_privs_are('public', 'communication_sms_registration_submissions', 'service_role',
  array['SELECT', 'INSERT'],
  'the server may append and read snapshots but cannot change or delete them');
select function_privs_are('public', 'communication_sms_submit_registration',
  array['uuid', 'uuid', 'text'], 'service_role', array[]::text[],
  'the legacy submit command is no longer callable by the application');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('d3a0ac70-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner@example.test', 'test', now(), now(), now()),
  ('d3a0ac70-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'other-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d3a00000-0000-4000-8000-000000000001', 'Submission Org A', 'submission-org-a', 'active'),
  ('d3a00000-0000-4000-8000-000000000002', 'Submission Org B', 'submission-org-b', 'active');

select lives_ok(
  $$select public.communication_sms_start_registration(
    'd3a00000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')$$,
  'an owner-side setup can create the registration shell');

select is(
  (public.communication_sms_save_registration_draft(
    'd3a00000-0000-4000-8000-000000000001',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    1, 1, '{"legal_business_name":"Acme Services"}'::jsonb,
    'd3a0ac70-0000-4000-8000-000000000001')).draft_revision,
  2,
  'saving answers advances the optimistic revision');
select throws_ok(
  format($$select public.communication_sms_save_registration_draft(%L, %L, 1, 1, '{}'::jsonb, %L)$$,
    'd3a00000-0000-4000-8000-000000000001',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    'd3a0ac70-0000-4000-8000-000000000001'),
  'P0001', null,
  'a stale draft save is refused');
select throws_ok(
  format($$select public.communication_sms_save_registration_draft(%L, %L, 2, 1, '{}'::jsonb, %L)$$,
    'd3a00000-0000-4000-8000-000000000002',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    'd3a0ac70-0000-4000-8000-000000000002'),
  'P0001', null,
  'another organization cannot save the draft');

select is(
  (public.communication_sms_submit_registration_answers(
    'd3a00000-0000-4000-8000-000000000001',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    2, 1, '{"legal_business_name":"Acme Services","authorized_representative":{"email":"owner@example.com"}}'::jsonb,
    'authorized-representative-v1',
    'I confirm that I am authorized to represent this business and that these details are truthful.',
    'd3a0ac70-0000-4000-8000-000000000001', 'owner@example.com')).status,
  'under_review',
  'an attested submission moves the registration under review');
select is(
  (select count(*)::int from public.communication_sms_registration_submissions
   where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
  1,
  'the first submission creates one immutable snapshot');
select is(
  (select submission_number from public.communication_sms_registration_submissions
   where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
  1,
  'the first snapshot is numbered one');
select is(
  (select attestation_version from public.communication_sms_registration_submissions
   where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
  'authorized-representative-v1',
  'the exact attestation version is retained');
select throws_ok(
  $$update public.communication_sms_registration_submissions set answers = '{}'::jsonb$$,
  '23514', null,
  'an attested answer snapshot cannot be emptied');
select throws_ok(
  format($$select public.communication_sms_submit_registration_answers(%L, %L, 3, 1, '{"changed":true}'::jsonb, 'v1', 'attested', %L, %L)$$,
    'd3a00000-0000-4000-8000-000000000001',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    'd3a0ac70-0000-4000-8000-000000000001', 'owner@example.com'),
  'P0001', null,
  'a registration already under review cannot be submitted twice');

select is(
  (public.communication_sms_record_registration_outcome(
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    'action_needed', null, null, 'Clarify the opt-in wording')).status,
  'action_needed',
  'Jafar can return the registration for correction');
select is(
  (public.communication_sms_save_registration_draft(
    'd3a00000-0000-4000-8000-000000000001',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    3, 1, '{"legal_business_name":"Acme Services","opt_in":"Website form"}'::jsonb,
    'd3a0ac70-0000-4000-8000-000000000001')).draft_revision,
  4,
  'returned answers can be corrected as a new draft revision');
select is(
  (public.communication_sms_submit_registration_answers(
    'd3a00000-0000-4000-8000-000000000001',
    (select id from public.communication_sms_registrations where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
    4, 1, '{"legal_business_name":"Acme Services","opt_in":"Website form"}'::jsonb,
    'authorized-representative-v1', 'I confirm these corrected details are truthful.',
    'd3a0ac70-0000-4000-8000-000000000001', 'owner@example.com')).status,
  'under_review',
  'corrected answers can be re-attested and resubmitted');
select is(
  (select count(*)::int from public.communication_sms_registration_submissions
   where organization_id = 'd3a00000-0000-4000-8000-000000000001'),
  2,
  'resubmission appends a second snapshot');
select is(
  (select answers->>'opt_in' from public.communication_sms_registration_submissions
   where organization_id = 'd3a00000-0000-4000-8000-000000000001' and submission_number = 2),
  'Website form',
  'the corrected snapshot contains the new answers');
select is(
  (select answers->>'legal_business_name' from public.communication_sms_registration_submissions
   where organization_id = 'd3a00000-0000-4000-8000-000000000001' and submission_number = 1),
  'Acme Services',
  'the first snapshot remains unchanged after resubmission');

select * from finish();
rollback;
