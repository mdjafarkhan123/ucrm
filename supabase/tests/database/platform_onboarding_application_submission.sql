-- Behaviour of the public submission entry point: the package edition's terms are snapshotted as
-- published at that moment, a repeat applicant is flagged for review but never blocked or merged, an
-- edition that stopped being available (superseded, private, or without a price for the chosen billing
-- interval) is refused, and the public roles cannot call the function at all.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- A public package with a published edition (monthly price only), a public package whose only edition
-- was superseded while the form was open, and a private package.
insert into public.packages (id, slug, visibility) values
  ('40000000-0000-0000-0000-0000000000a1', 'submission-test', 'public'),
  ('40000000-0000-0000-0000-0000000000a2', 'submission-withdrawn', 'public'),
  ('40000000-0000-0000-0000-0000000000a3', 'submission-private', 'private');
insert into public.package_editions (id, package_id, name, promise, monthly_price_usd_cents) values
  ('40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-0000000000a1', 'Submission Test Package',
    'Everything you need.', 4900),
  ('40000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-0000000000a2', 'Withdrawn Test Package',
    'No longer offered.', 3900),
  ('40000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-0000000000a3', 'Private Test Package',
    'For one customer.', 2900);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id in ('40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000003');
update public.package_editions set status = 'superseded', superseded_at = now()
where id = '40000000-0000-0000-0000-000000000002';

select is(
  has_function_privilege('anon', 'public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)', 'execute'),
  false,
  'anonymous callers cannot submit applications directly'
);
select is(
  has_function_privilege('authenticated', 'public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)', 'execute'),
  false,
  'signed-in contractors cannot submit applications directly'
);
select is(
  has_function_privilege('service_role', 'public.submit_onboarding_application(text, text, text, text, text, text, text, text, text, text, uuid, text, text, jsonb)', 'execute'),
  true,
  'the server role can submit applications'
);

-- First submission.
select lives_ok(
  $$select public.submit_onboarding_application(
      '  Larkfield Test Roofing  ', 'Jordan Larkfield', '  JORDAN@larkfield-test.example ', '555-0100',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-000000000001', 'month', 'v1',
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
  (select package_edition_id from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Roofing'),
  '40000000-0000-0000-0000-000000000001'::uuid,
  'the application points at the edition that was chosen'
);
select is(
  (select package_snapshot ->> 'billing_period' from public.platform_onboarding_applications
   where business_name = 'Larkfield Test Roofing'),
  'month',
  'the chosen billing interval is snapshotted with the price'
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
      '40000000-0000-0000-0000-000000000001', 'month', 'v1',
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
      '40000000-0000-0000-0000-000000000002', 'month', 'v1', '{}'::jsonb
    )$$,
  '23514',
  null,
  'an edition superseded while the form was open cannot be submitted against'
);
select throws_ok(
  $$select public.submit_onboarding_application(
      'Missing Package Test', 'Sam Late', 'sam@late-test.example', '555-0101',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-0000000000ff', 'month', 'v1', '{}'::jsonb
    )$$,
  '23503',
  null,
  'a package that no longer exists cannot be submitted against'
);

select throws_ok(
  $$select public.submit_onboarding_application(
      'Private Package Test', 'Sam Late', 'sam@late-test.example', '555-0101',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-000000000003', 'month', 'v1', '{}'::jsonb
    )$$,
  '23514',
  null,
  'a private package cannot be chosen on the public form'
);
select throws_ok(
  $$select public.submit_onboarding_application(
      'Yearly Package Test', 'Sam Late', 'sam@late-test.example', '555-0101',
      '', '', 'Roofing', 'Austin, USA', 'America/Chicago', '',
      '40000000-0000-0000-0000-000000000001', 'year', 'v1', '{}'::jsonb
    )$$,
  '23514',
  null,
  'yearly billing cannot be chosen for an edition with no yearly price'
);

select * from finish();
rollback;
