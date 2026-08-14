-- Part 6C: package-version changes and reasoned feature/limit exceptions.
-- These commands must leave one private event, one contractor-safe event, and one current
-- projection change in the same transaction, while remaining idempotent per organization.
begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

-- Only the owner service role can reach the command seams.
select is(has_function_privilege('anon', 'public.apply_organization_package_change(uuid, uuid, text, text, text, timestamptz)', 'execute'), false, 'anonymous callers cannot change packages');
select is(has_function_privilege('authenticated', 'public.apply_organization_package_change(uuid, uuid, text, text, text, timestamptz)', 'execute'), false, 'contractors cannot change packages');
select is(has_function_privilege('service_role', 'public.apply_organization_package_change(uuid, uuid, text, text, text, timestamptz)', 'execute'), true, 'the owner service role can change packages');
select is(has_function_privilege('service_role', 'public.apply_organization_feature_exception(uuid, text, text, timestamptz, timestamptz, text, text, text, timestamptz)', 'execute'), true, 'the owner service role can change feature exceptions');
select is(has_function_privilege('service_role', 'public.apply_organization_limit_exception(uuid, text, text, integer, timestamptz, timestamptz, text, text, text, timestamptz)', 'execute'), true, 'the owner service role can change limit exceptions');

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000000c1', '6C Package Test', '6c-package-test', 'active');

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select '90000000-0000-0000-0000-0000000000c1', id, now() - interval '2 minutes', 'provisioning', '6C test baseline assignment'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select is(
  (public.apply_organization_package_change(
    target_organization_id => '90000000-0000-0000-0000-0000000000c1',
    target_package_version_id => (
      select id from public.platform_package_versions
      where status = 'published'
        and id <> (select package_version_id from public.organization_package_assignments where organization_id = '90000000-0000-0000-0000-0000000000c1')
      order by version_number, id
      limit 1
    ),
    idempotency_key => '6c-package-change-1',
    private_reason => 'Move the pilot organization to the current published package.',
    actor_owner_email => 'owner@example.test',
    occurred_at => now() - interval '1 minute'
  ) ->> 'applied'),
  'true',
  'a package version change applies'
);
select is((select count(*)::int from public.organization_package_assignments where organization_id = '90000000-0000-0000-0000-0000000000c1'), 2, 'package changes append a new assignment');
select is((select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000c1' and event_kind = 'package_version_changed'), 1, 'package changes create one private event');
select is((select count(*)::int from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000c1' and safe_kind = 'package_changed'), 1, 'package changes create one safe event');
select is(
  (public.apply_organization_package_change(
    target_organization_id => '90000000-0000-0000-0000-0000000000c1',
    target_package_version_id => (select package_version_id from public.organization_package_assignments where organization_id = '90000000-0000-0000-0000-0000000000c1' order by effective_at desc limit 1),
    idempotency_key => '6c-package-change-1',
    private_reason => 'Replay',
    actor_owner_email => 'owner@example.test'
  ) ->> 'applied'),
  'false',
  'replaying a package command is idempotent'
);

select is(
  (public.apply_organization_feature_exception(
    '90000000-0000-0000-0000-0000000000c1',
    (select feature_key from public.features order by feature_key limit 1),
    'on', now() - interval '1 hour', now() + interval '1 day',
    '6c-feature-exception-1', 'Enable the feature for the pilot.', 'owner@example.test'
  ) ->> 'applied'),
  'true',
  'a feature exception applies'
);
select is((select reason from public.organization_feature_overrides where organization_id = '90000000-0000-0000-0000-0000000000c1'), 'Enable the feature for the pilot.', 'feature exception reason is retained');
select is((select is_legacy_import from public.organization_feature_overrides where organization_id = '90000000-0000-0000-0000-0000000000c1'), false, 'new feature exceptions are not legacy imports');
select is((select count(*)::int from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000c1' and safe_kind = 'feature_access_changed'), 1, 'feature exceptions create one safe event');
select is((public.apply_organization_feature_exception(
  '90000000-0000-0000-0000-0000000000c1', (select feature_key from public.features order by feature_key limit 1),
  'on', now() - interval '1 hour', now() + interval '1 day', '6c-feature-exception-1', 'Replay', 'owner@example.test'
) ->> 'applied'), 'false', 'feature exception replay is idempotent');

select is(
  (public.apply_organization_limit_exception(
    '90000000-0000-0000-0000-0000000000c1', 'employee_seats', 'not_included', null,
    now() - interval '1 hour', null, '6c-limit-exception-1', 'Exclude seats for the pilot.', 'owner@example.test'
  ) ->> 'applied'),
  'true',
  'a not-included limit exception applies'
);
select is((select limit_state from public.organization_limit_overrides where organization_id = '90000000-0000-0000-0000-0000000000c1'), 'not_included', 'not-included is a first-class limit state');
select is((select limit_value from public.organization_limit_overrides where organization_id = '90000000-0000-0000-0000-0000000000c1'), null::integer, 'not-included has no numeric value');
select is((select count(*)::int from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000c1' and safe_kind = 'limit_access_changed'), 1, 'limit exceptions create one safe event');

select lives_ok(
  $$select public.apply_organization_feature_exception(
    '90000000-0000-0000-0000-0000000000c1', (select feature_key from public.features order by feature_key limit 1),
    'inherit', now(), null, '6c-feature-inherit-1', 'Remove the temporary feature exception.', 'owner@example.test'
  )$$,
  'inherit removes the projection while retaining the private event'
);
select is((select count(*)::int from public.organization_feature_overrides where organization_id = '90000000-0000-0000-0000-0000000000c1'), 0, 'inherit removes the feature projection');
select is((select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000c1' and event_kind = 'feature_exception_changed'), 2, 'inherit adds a second feature history event');

select throws_ok(
  $$select public.apply_organization_limit_exception(
    '90000000-0000-0000-0000-0000000000c1', 'employee_seats', 'numeric', null,
    now(), null, '6c-limit-invalid-1', 'Missing numeric value.', 'owner@example.test'
  )$$,
  '23514', null,
  'numeric limits require a value'
);
select is((select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000c1' and event_kind = 'limit_exception_changed'), 1, 'a rejected limit command creates no history');
select is((select count(*)::int from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000c1'), 4, 'successful package, feature, limit, and inherit commands each create a safe event');

select * from finish();
rollback;
