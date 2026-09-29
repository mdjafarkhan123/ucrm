-- Part 5a: the explicit "Mark reviewed" transition, and duplicate acknowledge/close handling.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

select has_column('public', 'platform_onboarding_applications', 'duplicate_acknowledged_at', 'duplicate acknowledged-at column exists');
select has_column('public', 'platform_onboarding_applications', 'duplicate_acknowledged_by_owner_email', 'duplicate acknowledged-by column exists');

select is(
  has_function_privilege('anon', 'public.mark_onboarding_application_reviewed(uuid, text)', 'execute'),
  false,
  'anonymous callers cannot mark an application reviewed'
);
select is(
  has_function_privilege('authenticated', 'public.mark_onboarding_application_reviewed(uuid, text)', 'execute'),
  false,
  'contractors cannot mark an application reviewed'
);
select is(
  has_function_privilege('service_role', 'public.mark_onboarding_application_reviewed(uuid, text)', 'execute'),
  true,
  'the owner service role can mark an application reviewed'
);
select is(
  has_function_privilege('anon', 'public.acknowledge_onboarding_application_duplicate(uuid, text)', 'execute'),
  false,
  'anonymous callers cannot acknowledge a duplicate'
);
select is(
  has_function_privilege('service_role', 'public.acknowledge_onboarding_application_duplicate(uuid, text)', 'execute'),
  true,
  'the owner service role can acknowledge a duplicate'
);

-- An edition to satisfy the applications' foreign key: the private test package's published edition.
-- Its content is irrelevant here; nothing in this file asserts on it.
do $$
begin
  perform set_config(
    'test.pkg_edition_id',
    (select e.id::text from public.package_editions e
       join public.packages p on p.id = e.package_id
      where p.slug = 'test-package' and e.status = 'published'),
    true
  );
end $$;

insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_edition_id, billing_interval, package_snapshot, possible_duplicate
) values (
  '50000000-0000-0000-0000-000000000010', 'new', 'Reviewed Test Co', 'Alex Reviewed',
  'alex@reviewed-test.example', '555-0200', 'Plumbing', 'Austin, USA', 'America/Chicago',
  current_setting('test.pkg_edition_id')::uuid, 'month', '{}'::jsonb, false
);

select lives_ok(
  $$select public.mark_onboarding_application_reviewed('50000000-0000-0000-0000-000000000010', 'owner@example.test')$$,
  'a new application can be marked reviewed'
);
select is(
  (select stage from public.platform_onboarding_applications where id = '50000000-0000-0000-0000-000000000010'),
  'awaiting_payment',
  'marking reviewed moves the application from new to awaiting_payment'
);
select throws_ok(
  $$select public.mark_onboarding_application_reviewed('50000000-0000-0000-0000-000000000010', 'owner@example.test')$$,
  '23514',
  null,
  'an already-reviewed application cannot be marked reviewed again'
);
select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'onboarding_application.reviewed'
     and target_key = '50000000-0000-0000-0000-000000000010'),
  1,
  'marking reviewed leaves a matching audit event'
);

-- A possible-duplicate application for the acknowledge/close path.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_edition_id, billing_interval, package_snapshot, possible_duplicate
) values (
  '50000000-0000-0000-0000-000000000020', 'new', 'Duplicate Test Co', 'Sam Duplicate',
  'sam@duplicate-test.example', '555-0201', 'Plumbing', 'Austin, USA', 'America/Chicago',
  current_setting('test.pkg_edition_id')::uuid, 'month', '{}'::jsonb, true
);

select throws_ok(
  $$select public.acknowledge_onboarding_application_duplicate('50000000-0000-0000-0000-000000000010', 'owner@example.test')$$,
  '23514',
  null,
  'acknowledging a non-duplicate application is refused'
);
select throws_ok(
  $$select public.mark_onboarding_application_not_proceeding('50000000-0000-0000-0000-000000000020', 'owner@example.test')$$,
  '23514',
  null,
  'closing an unacknowledged duplicate without a reason is refused'
);
select lives_ok(
  $$select public.mark_onboarding_application_not_proceeding('50000000-0000-0000-0000-000000000020', 'owner@example.test', 'Confirmed same business as an existing application.')$$,
  'closing an unacknowledged duplicate with a reason succeeds'
);
select is(
  (select stage from public.platform_onboarding_applications where id = '50000000-0000-0000-0000-000000000020'),
  'not_proceeding',
  'the duplicate application is moved to not_proceeding'
);
select is(
  (select after_state ->> 'reason' from public.platform_owner_audit_events
   where event_type = 'onboarding_application.not_proceeding'
     and target_key = '50000000-0000-0000-0000-000000000020'),
  'Confirmed same business as an existing application.',
  'the closing reason is kept in the audit event'
);

-- A second possible-duplicate application for the acknowledge path.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_edition_id, billing_interval, package_snapshot, possible_duplicate
) values (
  '50000000-0000-0000-0000-000000000030', 'new', 'Duplicate Test Co Two', 'Jamie Duplicate',
  'jamie@duplicate-test.example', '555-0202', 'Plumbing', 'Austin, USA', 'America/Chicago',
  current_setting('test.pkg_edition_id')::uuid, 'month', '{}'::jsonb, true
);

select lives_ok(
  $$select public.acknowledge_onboarding_application_duplicate('50000000-0000-0000-0000-000000000030', 'owner@example.test')$$,
  'acknowledging a possible duplicate succeeds'
);
select is(
  (select duplicate_acknowledged_by_owner_email from public.platform_onboarding_applications where id = '50000000-0000-0000-0000-000000000030'),
  'owner@example.test',
  'the acknowledging owner is recorded'
);
select throws_ok(
  $$select public.acknowledge_onboarding_application_duplicate('50000000-0000-0000-0000-000000000030', 'owner@example.test')$$,
  '23514',
  null,
  'an already-acknowledged duplicate cannot be acknowledged again'
);
select lives_ok(
  $$select public.mark_onboarding_application_not_proceeding('50000000-0000-0000-0000-000000000030', 'owner@example.test')$$,
  'once acknowledged, closing the application no longer requires a reason'
);

select throws_ok(
  $$update public.platform_onboarding_applications set duplicate_acknowledged_at = now() where id = '50000000-0000-0000-0000-000000000010'$$,
  '23514',
  null,
  'a non-duplicate application cannot have its duplicate flag acknowledged directly'
);

select * from finish();
rollback;
