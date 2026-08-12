begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'package-compat@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status, package_key)
values ('10000000-0000-0000-0000-000000000021', 'Versioned Package Compatibility', 'versioned-package-compatibility', 'active', 'growth');

insert into public.organization_members (organization_id, user_id, role)
values ('10000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000021', 'admin');

set local role postgres;

select is((select count(*)::integer from public.platform_packages where status = 'published'), 3, 'the three approved package identities are published');
select is((select count(*)::integer from public.platform_package_versions where status = 'published'), 3, 'each approved package has a published immutable version');
select is((select count(*)::integer from public.platform_packages where status = 'published' and currency = 'USD' and billing_period = 'monthly'), 3, 'published package identities use the approved billing configuration');
select is((select price_usd_cents from public.platform_package_versions where version_number = 1 and package_id = (select package_id from public.platform_packages where package_key = 'growth')), 14900, 'the published Growth version retains its approved monthly price');
select is((select count(*)::integer from public.platform_package_version_features as feature join public.platform_package_versions as version on version.id = feature.package_version_id join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and feature.feature_key = 'sales.pipeline'), 1, 'published version features preserve the legacy controlled capability matrix');
select is((select count(*)::integer from public.platform_package_version_limits as limit_row join public.platform_package_versions as version on version.id = limit_row.package_version_id join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and limit_row.limit_key = 'employee_seats' and limit_row.limit_state = 'numeric' and limit_row.limit_value = 10), 1, 'published version limits preserve the controlled employee-seat limit');

select lives_ok($$insert into public.organization_package_assignments (organization_id, package_version_id, assignment_source, reason) select '10000000-0000-0000-0000-000000000021', version.id, 'package_change', 'Compatibility test assignment' from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 1$$, 'an organization can receive a published package version');
select is((select count(*)::integer from public.organization_package_assignments where organization_id = '10000000-0000-0000-0000-000000000021'), 1, 'the versioned assignment is recorded as history');

select throws_ok($$insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason) select '10000000-0000-0000-0000-000000000021', package_version_id, now() + interval '1 day', 'package_change', 'Future assignment must fail' from public.organization_package_assignments where organization_id = '10000000-0000-0000-0000-000000000021'$$, '23514', null, 'future package assignments are rejected');

insert into public.platform_package_versions (package_id, version_number, status, display_name)
select package_id, 99, 'draft', 'Draft compatibility version' from public.platform_packages where package_key = 'starter';

select throws_ok($$insert into public.organization_package_assignments (organization_id, package_version_id, assignment_source, reason) select '10000000-0000-0000-0000-000000000021', id, 'package_change', 'Draft assignment must fail' from public.platform_package_versions where version_number = 99$$, '23514', null, 'draft package versions cannot be assigned');
select throws_ok($$update public.organization_package_assignments set reason = 'History must not change' where organization_id = '10000000-0000-0000-0000-000000000021'$$, '23514', null, 'package assignment history is immutable');
select throws_ok($$delete from public.organization_package_assignments where organization_id = '10000000-0000-0000-0000-000000000021'$$, '23514', null, 'package assignment history cannot be deleted');
select is((select package_key from public.organizations where id = '10000000-0000-0000-0000-000000000021'), 'growth', 'versioned assignment does not rewrite the legacy package column');
select throws_ok($tag$update public.platform_package_versions set price_usd_cents = 1 where package_id = (select package_id from public.platform_packages where package_key = 'growth') and version_number = 1$tag$, '23514', null, 'published package prices are immutable');
select throws_ok($tag$delete from public.platform_package_version_features where package_version_id = (select id from public.platform_package_versions where package_id = (select package_id from public.platform_packages where package_key = 'growth') and version_number = 1) and feature_key = 'sales.pipeline'$tag$, '23514', null, 'published package features are immutable');
select throws_ok($tag$delete from public.platform_package_version_limits where package_version_id = (select id from public.platform_package_versions where package_id = (select package_id from public.platform_packages where package_key = 'growth') and version_number = 1) and limit_key = 'employee_seats'$tag$, '23514', null, 'published package limits are immutable');

set local role service_role;
select lives_ok($$select public.manage_platform_package_version(
  'create_draft', 'growth', null, 'Growth Draft', 'Draft Growth description',
  'Draft Growth value', 19900, array['sales.pipeline']::text[], 'numeric', 12,
  'owner@example.test'
)$$, 'the owner can create a package draft');
select is((select count(*)::integer from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2 and version.status = 'draft'), 1, 'the new package draft is stored as version two');
select is((select version.display_name from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2), 'Growth Draft', 'the draft stores its initial display name');
select is((select count(*)::integer from public.platform_package_version_features where package_version_id = (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2) and feature_key = 'sales.pipeline'), 1, 'draft feature mappings are replaced with the requested capabilities');
select is((select limit_value from public.platform_package_version_limits where package_version_id = (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2) and limit_key = 'employee_seats'), 12, 'draft limit mappings store the requested employee-seat value');
select lives_ok($$select public.manage_platform_package_version(
  'update_draft', 'growth',
  (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2),
  'Growth Updated', 'Updated Growth description', 'Updated Growth value', 20900,
  array['communications.inbox']::text[], 'numeric', 15, 'owner@example.test'
)$$, 'the owner can update a draft package version');
select is((select version.display_name from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2), 'Growth Updated', 'draft edits update package metadata');
select is((select count(*)::integer from public.platform_package_version_features where package_version_id = (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2) and feature_key = 'communications.inbox'), 1, 'draft edits replace the feature mappings');
select is((select limit_value from public.platform_package_version_limits where package_version_id = (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2) and limit_key = 'employee_seats'), 15, 'draft edits replace the limit mappings');
select lives_ok($$select public.manage_platform_package_version(
  'publish', 'growth',
  (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2),
  null, null, null, null, null, null, null, 'owner@example.test'
)$$, 'the owner can publish a complete draft package version');
select is((select version.status from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2), 'published', 'publishing promotes the draft version');
select is((select version.status from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 1), 'retired', 'publishing retires the previous published version');
select is((select price_usd_cents from public.platform_packages where package_key = 'growth'), 20900, 'publishing updates the package public metadata');
select is((select count(*)::integer from public.platform_owner_audit_events where target_type = 'platform_package_version' and event_type like 'package.%'), 3, 'package draft changes create private owner audit events');
select throws_ok($$select public.manage_platform_package_version('update_draft', 'growth', (select version.id from public.platform_package_versions as version join public.platform_packages as package on package.package_id = version.package_id where package.package_key = 'growth' and version.version_number = 2), 'Should Fail', 'Should Fail', null, 1, array[]::text[], null, null, 'owner@example.test')$$, '23514', null, 'published versions cannot be edited through the owner operation');
select is(has_table_privilege('anon', 'public.platform_owner_audit_events', 'select'), false, 'anonymous sessions cannot read owner package audit events');
select is(has_table_privilege('authenticated', 'public.platform_owner_audit_events', 'select'), false, 'contractor sessions cannot read owner package audit events');
select is(has_table_privilege('service_role', 'public.platform_owner_audit_events', 'select'), true, 'the service role can read owner package audit events');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000021', true);
select is(has_table_privilege('authenticated', 'public.organization_package_assignments', 'select'), false, 'contractor sessions cannot read owner-only package assignment history');
select throws_ok($$insert into public.organization_package_assignments (organization_id, package_version_id, assignment_source, reason) select '10000000-0000-0000-0000-000000000021', id, 'package_change', 'Contractor write must fail' from public.platform_package_versions where version_number = 1$$, '42501', null, 'contractor sessions cannot create package assignments');
select is((select package_key from public.organizations where id = '10000000-0000-0000-0000-000000000021'), 'growth', 'legacy package access data remains available to contractor sessions');
select is((select count(*)::integer from public.package_features where package_key = 'growth' and feature_key = 'sales.pipeline'), 1, 'legacy feature access remains available during compatibility');
select is((select count(*)::integer from public.package_limits where package_key = 'growth' and limit_key = 'employee_seats'), 1, 'legacy limit access remains available during compatibility');
select is((select count(*)::integer from public.platform_package_versions where status = 'published'), 3, 'authenticated reads retain all published package versions');
select is((select count(*)::integer from public.platform_package_versions where status = 'draft'), 0, 'authenticated reads cannot see draft package versions');

select * from finish();
rollback;
