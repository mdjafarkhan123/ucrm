-- Paid-launch trust, Part 4: linked Request records and the pricing write hole follow can_view_request.
--
-- Part 3 narrowed private.can_view_request to an assigned-only rule for a Field member but left two seams
-- unproven: public.replace_request_pricing_lines authorized on plain organization membership rather than
-- can_view_request (a Field member who lost visibility could still edit pricing), and notes/tags/attachments
-- on a Request were never directly tested even though they read can_view_request through
-- private.can_view_linked_entity already.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention requests_assigned_scope_visibility.sql
-- documents. Asserts run directly with select is(...)/throws_ok(...) rather than through a temporary results
-- table, because the role switches below move between postgres and authenticated and a table owned by
-- postgres is not insertable once the session becomes authenticated.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- 1. Fixtures: one organization, an assigned Field member, an unassigned one, two Requests -----------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000074001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-linked-owner@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000074002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-linked-field-assigned@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000074003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'requests-linked-field-unassigned@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('10000000-0000-0000-0000-000000074000', 'Requests Linked Scope Test Org', 'requests-linked-scope-test-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-000000074000', '00000000-0000-0000-0000-000000074001', 'owner'),
  ('10000000-0000-0000-0000-000000074000', '00000000-0000-0000-0000-000000074002', 'field'),
  ('10000000-0000-0000-0000-000000074000', '00000000-0000-0000-0000-000000074003', 'field');

insert into public.clients (id, organization_id, display_name)
values ('20000000-0000-0000-0000-000000074000', '10000000-0000-0000-0000-000000074000', 'Requests Linked Scope Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('30000000-0000-0000-0000-000000074000', '10000000-0000-0000-0000-000000074000', '20000000-0000-0000-0000-000000074000', '1 Linked Scope Street', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title)
values ('40000000-0000-0000-0000-000000074001', '10000000-0000-0000-0000-000000074000', '20000000-0000-0000-0000-000000074000', '30000000-0000-0000-0000-000000074000', 'Linked scope request with an assigned assessment');

insert into public.assessments (id, organization_id, request_id)
values ('a0000000-0000-0000-0000-000000074001', '10000000-0000-0000-0000-000000074000', '40000000-0000-0000-0000-000000074001');

insert into public.assessment_assignees (organization_id, assessment_id, user_id)
values ('10000000-0000-0000-0000-000000074000', 'a0000000-0000-0000-0000-000000074001', '00000000-0000-0000-0000-000000074002');

insert into public.request_pricing_lines (organization_id, request_id, position, category, name, quantity)
values ('10000000-0000-0000-0000-000000074000', '40000000-0000-0000-0000-000000074001', 0, 'service', 'Linked scope request line', 1);

-- A note, a tag assignment and an attachment linked to the request, created while the owner is signed in so
-- the fixture itself does not depend on the write path being narrowed.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000074001', true);

insert into public.notes (id, organization_id, body, created_by)
values ('50000000-0000-0000-0000-000000074001', '10000000-0000-0000-0000-000000074000', 'A note on the linked scope request', '00000000-0000-0000-0000-000000074001');
insert into public.note_links (organization_id, note_id, entity_type, entity_id)
values ('10000000-0000-0000-0000-000000074000', '50000000-0000-0000-0000-000000074001', 'request', '40000000-0000-0000-0000-000000074001');

insert into public.tags (id, organization_id, name)
values ('60000000-0000-0000-0000-000000074001', '10000000-0000-0000-0000-000000074000', 'Linked scope tag');
insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id, created_by)
values ('10000000-0000-0000-0000-000000074000', '60000000-0000-0000-0000-000000074001', 'request', '40000000-0000-0000-0000-000000074001', '00000000-0000-0000-0000-000000074001');

insert into public.attachments (id, organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key, uploaded_by)
values ('70000000-0000-0000-0000-000000074001', '10000000-0000-0000-0000-000000074000', 'request', '40000000-0000-0000-0000-000000074001', 'photo.jpg', 'image/jpeg', 1024, 'requests/074/photo.jpg', '00000000-0000-0000-0000-000000074001');

-- 2. The unassigned Field member cannot reach the request's notes, tags or attachments -----------------------

set local role postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000074003', true);

select is(
  (select count(*)::integer from public.note_links where organization_id = '10000000-0000-0000-0000-000000074000'),
  0, 'a field member with no assigned assessment sees zero note links on the request'
);
select is(
  (select count(*)::integer from public.tag_assignments where organization_id = '10000000-0000-0000-0000-000000074000'),
  0, 'a field member with no assigned assessment sees zero tag assignments on the request'
);
select is(
  (select count(*)::integer from public.attachments where organization_id = '10000000-0000-0000-0000-000000074000'),
  0, 'a field member with no assigned assessment sees zero attachments on the request'
);

-- 3. The unassigned Field member cannot reprice the request through the RPC directly --------------------------

select throws_ok(
  $$ select public.replace_request_pricing_lines(
    '40000000-0000-0000-0000-000000074001', 0,
    '[{"name": "Smuggled line", "category": "service", "quantity": 1, "unit_price_minor": 500}]'::jsonb
  ) $$,
  '42501', 'You do not have access to price this request.',
  'a field member who cannot see the request cannot reprice it through the RPC'
);

-- Checked as postgres: the unassigned field member's own request_pricing_lines SELECT is scoped by the same
-- can_view_request decision, so counting through their session would prove nothing about the refused write.
set local role postgres;
select is(
  (select count(*)::integer from public.request_pricing_lines where organization_id = '10000000-0000-0000-0000-000000074000'),
  1, 'the pricing line count is unchanged after the refused write'
);

-- 4. The assigned Field member still sees the linked records and can reprice ------------------------------

set local role postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000074002', true);

select is(
  (select count(*)::integer from public.note_links where organization_id = '10000000-0000-0000-0000-000000074000'),
  1, 'the assigned field member still sees the note link on their assigned request'
);
select is(
  (select count(*)::integer from public.attachments where organization_id = '10000000-0000-0000-0000-000000074000'),
  1, 'the assigned field member still sees the attachment on their assigned request'
);
select is(
  (public.replace_request_pricing_lines(
    '40000000-0000-0000-0000-000000074001', 0,
    '[{"name": "Assigned edit", "category": "service", "quantity": 1, "unit_price_minor": 750}]'::jsonb
  ))->>'line_count',
  '1', 'the assigned field member can still reprice the request they are assigned to'
);

-- 5. Owner keeps full access to the pricing RPC regardless of scope -----------------------------------------

set local role postgres;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000074001', true);

select is(
  (public.replace_request_pricing_lines(
    '40000000-0000-0000-0000-000000074001', 1,
    '[{"name": "Owner edit", "category": "service", "quantity": 1, "unit_price_minor": 900}]'::jsonb
  ))->>'line_count',
  '1', 'the owner can reprice any request in the organization'
);

select * from finish();
rollback;
