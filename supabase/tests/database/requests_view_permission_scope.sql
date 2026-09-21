-- Paid-launch trust, Part 2: the requests.view permission seam.
--
-- Proves only the switch exists and resolves correctly per role. No Request table, policy, or
-- can_view_request change belongs in this file -- that is Part 3. Follows the same seam jobs.view used in
-- field_assigned_scope_foundation: a permission declares scope_model = 'assigned_or_all', a role holds it
-- at a narrower access_scope, and private.member_permission_scope resolves the two together.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention the sibling files document.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

create temporary table tap_results (id serial primary key, line text);

-- 1. The permission catalog entry ----------------------------------------------------------------------

insert into tap_results (line) select is(
  (select scope_model from public.permissions where key = 'requests.view'),
  'assigned_or_all',
  'requests.view declares an assigned-or-all scope model'
);

-- 2. Role defaults ---------------------------------------------------------------------------------------

insert into tap_results (line) select is(
  (select array_agg(role order by role) from public.role_permissions
    where permission_key = 'requests.view' and access_scope = 'all'),
  array['admin', 'finance', 'office', 'owner', 'sales']::text[],
  'owner, admin, office, sales and finance default to all-scope requests.view'
);

insert into tap_results (line) select is(
  (select access_scope from public.role_permissions
    where role = 'field' and permission_key = 'requests.view'),
  'assigned',
  'field defaults to assigned-scope requests.view'
);

-- 3. Fixtures: one organization, one member per role -----------------------------------------------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000071001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-owner@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000071002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-admin@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000071003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-office@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000071004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-sales@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000071005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-finance@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000071006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('10000000-0000-0000-0000-000000071000', 'Requests Scope Test Org', 'requests-scope-test-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071001', 'owner'),
  ('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071002', 'admin'),
  ('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071003', 'office'),
  ('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071004', 'sales'),
  ('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071005', 'finance'),
  ('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071006', 'field');

-- 4. The resolver, per role ---------------------------------------------------------------------------------

insert into tap_results (line) select is(
  private.member_permission_scope('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071001', 'requests.view'),
  'all', 'owner resolves requests.view to all scope'
);
insert into tap_results (line) select is(
  private.member_permission_scope('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071002', 'requests.view'),
  'all', 'admin resolves requests.view to all scope'
);
insert into tap_results (line) select is(
  private.member_permission_scope('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071003', 'requests.view'),
  'all', 'office resolves requests.view to all scope'
);
insert into tap_results (line) select is(
  private.member_permission_scope('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071004', 'requests.view'),
  'all', 'sales resolves requests.view to all scope'
);
insert into tap_results (line) select is(
  private.member_permission_scope('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071005', 'requests.view'),
  'all', 'finance resolves requests.view to all scope'
);
insert into tap_results (line) select is(
  private.member_permission_scope('10000000-0000-0000-0000-000000071000', '00000000-0000-0000-0000-000000071006', 'requests.view'),
  'assigned', 'field resolves requests.view to assigned scope'
);

select line from tap_results order by id;

select * from finish();
rollback;
