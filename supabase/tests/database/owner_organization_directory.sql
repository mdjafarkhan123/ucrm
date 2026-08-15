-- Part 6F: owner_organization_directory search, attention reasons, and pagination.
begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- Privileges -------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.owner_organization_directory(text, text, timestamptz, uuid, integer)', 'execute'),
  false, 'anonymous callers cannot read the organization directory'
);
select is(
  has_function_privilege('authenticated', 'public.owner_organization_directory(text, text, timestamptz, uuid, integer)', 'execute'),
  false, 'contractors cannot read the organization directory'
);
select is(
  has_function_privilege('service_role', 'public.owner_organization_directory(text, text, timestamptz, uuid, integer)', 'execute'),
  true, 'the owner service role can read the organization directory'
);

-- Fixtures -----------------------------------------------------------------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('90000000-1111-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-1@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-2@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000f3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-3@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000f8', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-8@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000f9', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-9@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000fa', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-10@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000fb', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6f-owner-11@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-000000000f71', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zz6fowner7a@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-000000000f72', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zz6fowner7b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000000f1', '6F Fixture Baseline', '6f-fixture-baseline', 'active'),
  ('90000000-0000-0000-0000-0000000000f2', '6F Fixture Overdue', '6f-fixture-overdue', 'active'),
  ('90000000-0000-0000-0000-0000000000f3', '6F Fixture Free Access Safe', '6f-fixture-free-access-safe', 'active'),
  ('90000000-0000-0000-0000-0000000000f4', '6F Fixture Free Access Expiring', '6f-fixture-free-access-expiring', 'active'),
  ('90000000-0000-0000-0000-0000000000f5', '6F Fixture Legacy Review', '6f-fixture-legacy-review', 'pending_setup'),
  ('90000000-0000-0000-0000-0000000000f6', '6F Fixture Admin Missing', '6f-fixture-admin-missing', 'active'),
  ('90000000-0000-0000-0000-0000000000f7', '6F Fixture Admin Unclear', '6f-fixture-admin-unclear', 'active'),
  ('90000000-0000-0000-0000-0000000000f8', '6F Fixture Setup Failed', '6f-fixture-setup-failed', 'active'),
  ('90000000-0000-0000-0000-0000000000f9', '6F Fixture Setup Resolved', '6f-fixture-setup-resolved', 'active'),
  ('90000000-0000-0000-0000-0000000000fa', '6F Fixture Exception Expiring', '6f-fixture-exception-expiring', 'active'),
  ('90000000-0000-0000-0000-0000000000fb', '6F Fixture Exception Far', '6f-fixture-exception-far', 'active'),
  ('90000000-0000-0000-0000-0000000000fc', '6F Fixture Multi Reason', '6f-fixture-multi-reason', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('90000000-0000-0000-0000-0000000000f1', '90000000-1111-0000-0000-0000000000f1', 'owner'),
  ('90000000-0000-0000-0000-0000000000f2', '90000000-1111-0000-0000-0000000000f2', 'owner'),
  ('90000000-0000-0000-0000-0000000000f3', '90000000-1111-0000-0000-0000000000f3', 'owner'),
  ('90000000-0000-0000-0000-0000000000f4', '90000000-1111-0000-0000-0000000000f3', 'owner'),
  ('90000000-0000-0000-0000-0000000000f5', '90000000-1111-0000-0000-0000000000f3', 'owner'),
  ('90000000-0000-0000-0000-0000000000f7', '90000000-1111-0000-0000-000000000f71', 'owner'),
  ('90000000-0000-0000-0000-0000000000f7', '90000000-1111-0000-0000-000000000f72', 'owner'),
  ('90000000-0000-0000-0000-0000000000f8', '90000000-1111-0000-0000-0000000000f8', 'owner'),
  ('90000000-0000-0000-0000-0000000000f9', '90000000-1111-0000-0000-0000000000f9', 'owner'),
  ('90000000-0000-0000-0000-0000000000fa', '90000000-1111-0000-0000-0000000000fa', 'owner'),
  ('90000000-0000-0000-0000-0000000000fb', '90000000-1111-0000-0000-0000000000fb', 'owner');
-- f6 and f12 deliberately have no members at all.

-- Paid-through baselines for organizations that should read as commercially eligible.
insert into public.organization_commercial_state (organization_id, paid_through_date, paid_through_source, grace_ends_at, grace_basis_timezone)
values
  ('90000000-0000-0000-0000-0000000000f1', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC'),
  ('90000000-0000-0000-0000-0000000000f6', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC'),
  ('90000000-0000-0000-0000-0000000000f7', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC'),
  ('90000000-0000-0000-0000-0000000000f8', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC'),
  ('90000000-0000-0000-0000-0000000000f9', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC'),
  ('90000000-0000-0000-0000-0000000000fa', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC'),
  ('90000000-0000-0000-0000-0000000000fb', current_date + 30, 'legacy_owner_action', now() + interval '33 days', 'UTC');

-- Free access grants: f3 is safe (expires in 10 days), f4 is expiring soon (3 days).
-- A free access event must reference a package version already assigned to the organization.
insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select org_id, version.id, now() - interval '2 minutes', 'legacy_owner_action', '6F test fixture baseline assignment'
from (values
  ('90000000-0000-0000-0000-0000000000f3'::uuid),
  ('90000000-0000-0000-0000-0000000000f4'::uuid)
) as orgs(org_id)
cross join lateral (
  select id from public.platform_package_versions where status = 'published' order by version_number, id limit 1
) as version;

insert into public.organization_free_access_events (organization_id, package_version_id, action, starts_at, access_until_date, reason)
select '90000000-0000-0000-0000-0000000000f3', version.id, 'grant', current_date - 5, current_date + 10, '6F test fixture: safe grant'
from (select id from public.platform_package_versions where status = 'published' order by version_number, id limit 1) as version;
insert into public.organization_free_access_events (organization_id, package_version_id, action, starts_at, access_until_date, reason)
select '90000000-0000-0000-0000-0000000000f4', version.id, 'grant', current_date - 5, current_date + 3, '6F test fixture: expiring grant'
from (select id from public.platform_package_versions where status = 'published' order by version_number, id limit 1) as version;

-- Package exceptions: fa expires in 5 days (soon), fb expires in 20 days (not soon).
insert into public.organization_feature_overrides (organization_id, feature_key, override_state, starts_at, expires_at, reason, actor_owner_email)
values (
  '90000000-0000-0000-0000-0000000000fa', 'core.dashboard', 'on', now() - interval '1 day', now() + interval '5 days',
  '6F test fixture: expiring feature exception', 'owner@example.test'
);
insert into public.organization_limit_overrides (organization_id, limit_key, limit_state, limit_value, starts_at, expires_at, reason, actor_owner_email)
values (
  '90000000-0000-0000-0000-0000000000fb', 'employee_seats', 'numeric', 25, now() - interval '1 day', now() + interval '20 days',
  '6F test fixture: distant limit exception', 'owner@example.test'
);

-- Unresolved vs. resolved operation attempts targeted at an organization.
insert into public.platform_operation_attempts (operation_type, target_kind, target_id, idempotency_key, status)
values
  ('setup_email_delivery', 'organization', '90000000-0000-0000-0000-0000000000f8', '6f-fixture-setup-failed-attempt', 'pending'),
  ('setup_email_delivery', 'organization', '90000000-0000-0000-0000-0000000000f9', '6f-fixture-setup-resolved-attempt', 'succeeded');

-- f12 (multi-reason): active, no paid coverage, no free access, no members at all.

reset role;

create temporary table fixture_directory as
select public.owner_organization_directory('6f-fixture', null, null, null, 50) as result;

-- Attention reasons per organization -----------------------------------------------

select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f1'),
  '[]'::jsonb, 'a paid, single-owner active organization has no attention reasons'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f2'),
  '["access_overdue"]'::jsonb, 'an active organization with no paid coverage and no free access is access_overdue'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f3'),
  '[]'::jsonb, 'an active free-access grant more than 7 days from expiry is not flagged'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f4'),
  '["expiring_soon"]'::jsonb, 'a free-access grant expiring within 7 days is expiring_soon'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f5'),
  '["legacy_review"]'::jsonb, 'a pending_setup organization is legacy_review, not access_overdue, even without paid coverage'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f6'),
  '["administrator_missing"]'::jsonb, 'an organization with no owner-role member is administrator_missing'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f7'),
  '["administrator_ownership_unclear"]'::jsonb, 'an organization with two owner-role members is administrator_ownership_unclear'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f8'),
  '["setup_or_recovery_failed"]'::jsonb, 'an unresolved operation attempt targeted at the organization is setup_or_recovery_failed'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000f9'),
  '[]'::jsonb, 'a succeeded operation attempt does not count as setup_or_recovery_failed'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000fa'),
  '["expiring_soon"]'::jsonb, 'a feature exception expiring within 7 days is expiring_soon'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000fb'),
  '[]'::jsonb, 'a limit exception expiring in 20 days is not flagged'
);
select is(
  (select org -> 'attention_reasons' from fixture_directory, jsonb_array_elements(result -> 'organizations') as org where org ->> 'id' = '90000000-0000-0000-0000-0000000000fc'),
  '["access_overdue", "administrator_missing"]'::jsonb,
  'an organization can carry more than one reason at once, in urgency order'
);

-- Search -----------------------------------------------------------------------

select is(
  (select (result -> 'totals' ->> 'matching')::int from fixture_directory),
  12, 'searching a term shared by every fixture matches exactly the 12 fixtures'
);
select is(
  (select (public.owner_organization_directory('zz6fowner7a', null, null, null, 50) -> 'totals' ->> 'matching')::int),
  1, 'search matches an owner email even when no other owner shares it'
);
select is(
  (select org ->> 'id' from jsonb_array_elements(public.owner_organization_directory('zz6fowner7a', null, null, null, 50) -> 'organizations') as org),
  '90000000-0000-0000-0000-0000000000f7', 'the owner-email search returns the organization that owner belongs to'
);
select is(
  (select (public.owner_organization_directory('zz6fowner7b', null, null, null, 50) -> 'totals' ->> 'matching')::int),
  1, 'search matches every owner on a multi-owner organization, not just the first'
);

-- Attention filter ---------------------------------------------------------------

select is(
  (select (public.owner_organization_directory('6f-fixture', 'access_overdue', null, null, 50) -> 'totals' ->> 'matching')::int),
  2, 'filtering by access_overdue returns only the organizations carrying that reason'
);
select is(
  (select (public.owner_organization_directory('6f-fixture', 'administrator_ownership_unclear', null, null, 50) -> 'totals' ->> 'matching')::int),
  1, 'filtering by administrator_ownership_unclear returns only the multi-owner organization'
);

-- Pagination ---------------------------------------------------------------------

create temporary table fixture_page_1 as
select public.owner_organization_directory('6f-fixture', null, null, null, 5) as result;
create temporary table fixture_page_2 as
select public.owner_organization_directory(
  '6f-fixture', null,
  (select (result -> 'next_cursor' ->> 'created_at')::timestamptz from fixture_page_1),
  (select (result -> 'next_cursor' ->> 'id')::uuid from fixture_page_1),
  5
) as result;
create temporary table fixture_page_3 as
select public.owner_organization_directory(
  '6f-fixture', null,
  (select (result -> 'next_cursor' ->> 'created_at')::timestamptz from fixture_page_2),
  (select (result -> 'next_cursor' ->> 'id')::uuid from fixture_page_2),
  5
) as result;

select is(
  (select jsonb_array_length(result -> 'organizations') from fixture_page_1), 5, 'the first page returns exactly page_size rows'
);
select is(
  (select jsonb_array_length(result -> 'organizations') from fixture_page_2), 5, 'the second page continues past the first page'
);
select is(
  (select jsonb_array_length(result -> 'organizations') from fixture_page_3), 2, 'the final page returns the remainder'
);
select is(
  (select result -> 'next_cursor' from fixture_page_3), 'null'::jsonb, 'the final page has no next cursor'
);
select is(
  (
    select count(distinct org ->> 'id')::int
    from (
      select org from fixture_page_1, jsonb_array_elements(result -> 'organizations') as org
      union all
      select org from fixture_page_2, jsonb_array_elements(result -> 'organizations') as org
      union all
      select org from fixture_page_3, jsonb_array_elements(result -> 'organizations') as org
    ) as all_rows
  ),
  12, 'paging through every page visits each fixture organization exactly once'
);

select * from finish();
rollback;
