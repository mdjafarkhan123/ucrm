-- Paid-launch trust, Part 3: a Field member sees only Requests they are assigned to assess.
--
-- Part 1 proved every Field member sees every Request in the tenant, regardless of assignment. Part 2 only
-- seeded the requests.view scope switch; nothing yet read it. This proves the correction: public.requests
-- SELECT/UPDATE and public.request_pricing_lines SELECT now key off private.can_view_request, which is
-- 'assigned' for a Field member unless their own assessment lists them as an assignee -- the same rule
-- jobs.view already enforces for Jobs, applied here to Requests.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention the sibling files document. Asserts
-- run directly with select is(...) rather than through a temporary results table, because the role switches
-- below move between postgres and authenticated and a table owned by postgres is not insertable once the
-- session becomes authenticated.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- 1. Fixtures: one organization, an assigned Field member, an unassigned one, two Requests -----------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000073001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-owner@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000073002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-field-assigned@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000073003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-scope-field-unassigned@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('10000000-0000-0000-0000-000000073000', 'Requests Assigned Scope Test Org', 'requests-assigned-scope-test-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-000000073000', '00000000-0000-0000-0000-000000073001', 'owner'),
  ('10000000-0000-0000-0000-000000073000', '00000000-0000-0000-0000-000000073002', 'field'),
  ('10000000-0000-0000-0000-000000073000', '00000000-0000-0000-0000-000000073003', 'field');

insert into public.clients (id, organization_id, display_name)
values ('20000000-0000-0000-0000-000000073000', '10000000-0000-0000-0000-000000073000', 'Requests Scope Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('30000000-0000-0000-0000-000000073000', '10000000-0000-0000-0000-000000073000', '20000000-0000-0000-0000-000000073000', '1 Assigned Scope Street', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title)
values
  ('40000000-0000-0000-0000-000000073001', '10000000-0000-0000-0000-000000073000', '20000000-0000-0000-0000-000000073000', '30000000-0000-0000-0000-000000073000', 'Request with an assigned assessment'),
  ('40000000-0000-0000-0000-000000073002', '10000000-0000-0000-0000-000000073000', '20000000-0000-0000-0000-000000073000', '30000000-0000-0000-0000-000000073000', 'Request with no assessment');

insert into public.assessments (id, organization_id, request_id)
values ('a0000000-0000-0000-0000-000000073001', '10000000-0000-0000-0000-000000073000', '40000000-0000-0000-0000-000000073001');

insert into public.assessment_assignees (organization_id, assessment_id, user_id)
values ('10000000-0000-0000-0000-000000073000', 'a0000000-0000-0000-0000-000000073001', '00000000-0000-0000-0000-000000073002');

insert into public.request_pricing_lines (organization_id, request_id, position, category, name, quantity)
values
  ('10000000-0000-0000-0000-000000073000', '40000000-0000-0000-0000-000000073001', 0, 'service', 'Assigned request line', 1),
  ('10000000-0000-0000-0000-000000073000', '40000000-0000-0000-0000-000000073002', 0, 'service', 'Unassigned request line', 1);

-- 2. The assigned Field member sees only the Request they are on ------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000073002', true);

select is(
  (select count(*)::integer from public.requests where organization_id = '10000000-0000-0000-0000-000000073000'),
  1, 'the assigned field member sees exactly one request'
);

select is(
  (select array_agg(id order by id) from public.requests where organization_id = '10000000-0000-0000-0000-000000073000'),
  array['40000000-0000-0000-0000-000000073001'::uuid], 'the assigned field member sees their own assigned request'
);

select is(
  (select count(*)::integer from public.request_pricing_lines where organization_id = '10000000-0000-0000-0000-000000073000'),
  1, 'the assigned field member sees pricing for only their assigned request'
);

select is(
  (select count(*)::integer from public.requests where id = '40000000-0000-0000-0000-000000073002'),
  0, 'the assigned field member cannot see the request they are not on'
);

-- 3. The unassigned Field member sees no Request at all ----------------------------------------------------

set local role postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000073003', true);

select is(
  (select count(*)::integer from public.requests where organization_id = '10000000-0000-0000-0000-000000073000'),
  0, 'a field member with no assigned assessment sees zero requests'
);

select is(
  (select count(*)::integer from public.request_pricing_lines where organization_id = '10000000-0000-0000-0000-000000073000'),
  0, 'a field member with no assigned assessment sees zero pricing lines'
);

-- 4. Owner keeps full visibility -----------------------------------------------------------------------------

set local role postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000073001', true);

select is(
  (select count(*)::integer from public.requests where organization_id = '10000000-0000-0000-0000-000000073000'),
  2, 'owner keeps all-scope visibility of both requests'
);

select is(
  (select count(*)::integer from public.request_pricing_lines where organization_id = '10000000-0000-0000-0000-000000073000'),
  2, 'owner keeps all-scope visibility of both requests'' pricing lines'
);

select * from finish();
rollback;
