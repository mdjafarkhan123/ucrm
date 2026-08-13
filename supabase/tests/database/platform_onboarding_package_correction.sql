-- Part 5b: pre-payment package correction.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

select is(
  has_function_privilege('anon', 'public.correct_onboarding_application_package(uuid, text, uuid, text)', 'execute'),
  false,
  'anonymous callers cannot change a package'
);
select is(
  has_function_privilege('authenticated', 'public.correct_onboarding_application_package(uuid, text, uuid, text)', 'execute'),
  false,
  'contractors cannot change a package'
);
select is(
  has_function_privilege('service_role', 'public.correct_onboarding_application_package(uuid, text, uuid, text)', 'execute'),
  true,
  'the owner service role can change a package'
);

-- Reuse whichever versions are currently published on growth/elite (only one published
-- version per package is allowed, and the seed migration already publishes one of each,
-- so this test must not insert a competing one). One draft version on growth is still
-- created fresh, since draft status is not constrained the same way.
do $$
begin
  perform set_config(
    'test.orig_id',
    (select v.id::text from public.platform_package_versions v
       join public.platform_packages p on p.package_id = v.package_id
      where p.package_key = 'growth' and v.status = 'published' limit 1),
    true
  );
  perform set_config(
    'test.target_id',
    (select v.id::text from public.platform_package_versions v
       join public.platform_packages p on p.package_id = v.package_id
      where p.package_key = 'elite' and v.status = 'published' limit 1),
    true
  );
  perform set_config(
    'test.target_display_name',
    (select v.display_name from public.platform_package_versions v
       join public.platform_packages p on p.package_id = v.package_id
      where p.package_key = 'elite' and v.status = 'published' limit 1),
    true
  );
end $$;

insert into public.platform_package_versions (
  id, package_id, version_number, status, display_name, price_usd_cents
) values (
  '60000000-0000-0000-0000-000000000003',
  (select package_id from public.platform_packages where package_key = 'growth'),
  9303, 'draft', 'Package Correction Unpublished', 9900
)
on conflict (id) do nothing;

insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_version_id, package_snapshot, possible_duplicate
) values (
  '60000000-0000-0000-0000-000000000010', 'new', 'Package Correction Co', 'Alex Package',
  'alex@package-correction-test.example', '555-0300', 'Plumbing', 'Austin, USA', 'America/Chicago',
  current_setting('test.orig_id')::uuid,
  '{"display_name": "Package Correction Original", "price_usd_cents": 14900, "currency": "USD"}'::jsonb,
  false
);

select throws_ok(
  $$select public.correct_onboarding_application_package('60000000-0000-0000-0000-000000000010', 'owner@example.test', '60000000-0000-0000-0000-000000000003', 'Testing an unpublished target.')$$,
  '23514',
  null,
  'changing to an unpublished package version is refused'
);
select throws_ok(
  format($$select public.correct_onboarding_application_package('60000000-0000-0000-0000-000000000010', 'owner@example.test', %L, 'Testing a no-op change.')$$, current_setting('test.orig_id')),
  '23514',
  null,
  'changing to the already-active package version is refused'
);

select lives_ok(
  format($$select public.correct_onboarding_application_package('60000000-0000-0000-0000-000000000010', 'owner@example.test', %L, 'Prospect asked to move up to Elite before paying.')$$, current_setting('test.target_id')),
  'changing to a different published package before payment succeeds'
);
select is(
  (select package_version_id::text from public.platform_onboarding_applications where id = '60000000-0000-0000-0000-000000000010'),
  current_setting('test.target_id'),
  'the application now points at the new package version'
);
select is(
  (select package_snapshot ->> 'display_name' from public.platform_onboarding_applications where id = '60000000-0000-0000-0000-000000000010'),
  current_setting('test.target_display_name'),
  'the package snapshot was re-taken from the new version'
);
select is(
  (select count(*)::int from public.platform_onboarding_application_corrections
   where application_id = '60000000-0000-0000-0000-000000000010'),
  1,
  'the change is recorded in the corrections history table'
);
select is(
  (select reason from public.platform_onboarding_application_corrections
   where application_id = '60000000-0000-0000-0000-000000000010'),
  'Prospect asked to move up to Elite before paying.',
  'the private reason is kept'
);
select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'onboarding_application.package_corrected'
     and target_key = '60000000-0000-0000-0000-000000000010'),
  1,
  'the change leaves a matching audit event'
);

insert into public.platform_onboarding_application_payment_confirmations (
  application_id, actor_owner_email, amount_usd_cents, private_reference, package_version_id
) values (
  '60000000-0000-0000-0000-000000000010', 'owner@example.test', 24900, 'ref-package-correction-test',
  current_setting('test.target_id')::uuid
);

select throws_ok(
  format($$select public.correct_onboarding_application_package('60000000-0000-0000-0000-000000000010', 'owner@example.test', %L, 'Trying to revert after payment.')$$, current_setting('test.orig_id')),
  '23514',
  null,
  'the package can no longer be changed once payment is confirmed'
);

update public.platform_onboarding_applications
set stage = 'account_created'
where id = '60000000-0000-0000-0000-000000000010';

select throws_ok(
  format($$select public.correct_onboarding_application_package('60000000-0000-0000-0000-000000000010', 'owner@example.test', %L, 'Trying to change after account creation.')$$, current_setting('test.orig_id')),
  '23514',
  null,
  'the package can no longer be changed once the application has left review'
);

select throws_ok(
  format($$select public.correct_onboarding_application_package('60000000-0000-0000-0000-000000000099', 'owner@example.test', %L, 'Testing a missing application.')$$, current_setting('test.orig_id')),
  '23503',
  null,
  'a missing application is refused'
);

select * from finish();
rollback;
