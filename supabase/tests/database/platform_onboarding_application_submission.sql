-- Behaviour of the public submission entry point: the package snapshot is taken as published at
-- that moment, a repeat applicant is flagged for review but never blocked or merged, a package
-- that stopped being available is refused, and the public roles cannot call the function at all.
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- Give the elite package one published and one retired version to submit against. Any version
-- already published for it is retired first, because only one published version is allowed.
update public.platform_packages set status = 'published' where package_key = 'elite';
update public.platform_package_versions
set status = 'retired', published_at = coalesce(published_at, now()), retired_at = now()
where status = 'published'
  and package_id = (select package_id from public.platform_packages where package_key = 'elite');

insert into public.platform_package_versions (
  id, package_id, version_number, status, display_name, public_description, value_explanation,
  price_usd_cents, published_at
) values (
  '40000000-0000-0000-0000-000000000001',
  (select package_id from public.platform_packages where package_key = 'elite'),
  9001, 'published', 'Submission Test Package', 'Everything you need.', 'Worth it.', 4900, now()
);

insert into public.platform_package_versions (
  id, package_id, version_number, status, display_name, public_description, value_explanation,
  price_usd_cents, published_at, retired_at
) values (
  '40000000-0000-0000-0000-000000000002',
  (select package_id from public.platform_packages where package_key = 'elite'),
  9002, 'retired', 'Withdrawn Test Package', 'No longer offered.', 'Was worth it.', 3900, now(), now()
);

select is(
  has_function_privilege('anon', 'public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, jsonb)', 'execute'),
  false,
  'anonymous callers cannot submit applications directly'
);
select is(
  has_function_privilege('authenticated', 'public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, jsonb)', 'execute'),
  false,
  'signed-in contractors cannot submit applications directly'
);
select is(
  has_function_privilege('service_role', 'public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, jsonb)', 'execute'),
  true,
  'the server role can submit applications'
);

-- First submission.
select lives_ok(
  $$select public.submit_onboarding_application(
      '  Larkfield Test Roofing  ', 'Jordan Larkfield', '  JORDAN@larkfield-test.example ', '555-0100',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-000000000001', 'v1',
      '{"business_name":"Larkfield Test Roofing"}'::jsonb
    )$$,
  'a published package can be submitted against'
);

select is(
  (select business_name from public.platform_onboarding_applications
   where main_contact_email = 'jordan@larkfield-test.example'),
  'Larkfield Test Roofing',
  'the business name is trimmed before it is stored'
);
select is(
  (select main_contact_email from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Roofing'),
  'jordan@larkfield-test.example',
  'the contact email is trimmed and lower-cased before it is stored'
);
select is(
  (select package_snapshot ->> 'display_name' from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Roofing'),
  'Submission Test Package',
  'the package name is snapshotted as published at submission time'
);
select is(
  (select (package_snapshot ->> 'price_usd_cents')::int from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Roofing'),
  4900,
  'the price is snapshotted as published at submission time'
);
select is(
  (select possible_duplicate from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Roofing'),
  false,
  'a first-time applicant is not flagged as a possible duplicate'
);
select is(
  (select count(*)::int from public.platform_onboarding_application_submissions as submission
   join public.platform_onboarding_applications as application on application.id = submission.application_id
   where application.business_name = 'Larkfield Test Roofing'),
  1,
  'the original submission is recorded alongside the application'
);
select is(
  (select privacy_policy_version from public.platform_onboarding_application_submissions as submission
   join public.platform_onboarding_applications as application on application.id = submission.application_id
   where application.business_name = 'Larkfield Test Roofing'),
  'v1',
  'the accepted privacy policy version is kept with the submission'
);

-- Same contact applying again under a different business name.
select lives_ok(
  $$select public.submit_onboarding_application(
      'Larkfield Test Gutters', 'Jordan Larkfield', 'jordan@larkfield-test.example', '555-0100',
      '', '', 'Gutters', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-000000000001', 'v1',
      '{"business_name":"Larkfield Test Gutters"}'::jsonb
    )$$,
  'a repeat applicant is still allowed to submit'
);
select is(
  (select possible_duplicate from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Gutters'),
  true,
  'the repeat submission is flagged as a possible duplicate for review'
);
select is(
  (select count(*)::int from public.platform_onboarding_applications
   where main_contact_email = 'jordan@larkfield-test.example'),
  2,
  'both applications are kept separately and never merged'
);

select throws_ok(
  $$select public.submit_onboarding_application(
      'Retired Package Test', 'Sam Late', 'sam@late-test.example', '555-0101',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-000000000002', 'v1', '{}'::jsonb
    )$$,
  '23514',
  null,
  'a package retired while the form was open cannot be submitted against'
);
select throws_ok(
  $$select public.submit_onboarding_application(
      'Missing Package Test', 'Sam Late', 'sam@late-test.example', '555-0101',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-0000000000ff', 'v1', '{}'::jsonb
    )$$,
  '23503',
  null,
  'a package that no longer exists cannot be submitted against'
);

select * from finish();
rollback;
