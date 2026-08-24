begin;

create extension if not exists pgtap with schema extensions;

select plan(86);

-- Test fixtures are rolled back at the end of this file. The fixed IDs make
-- the assertions easy to audit without depending on generated values.
--
-- This file is written for `supabase test db`, which runs it as one session. Development currently uses
-- the remote Supabase project with no local stack, so the assertions are verified there instead by
-- running them inside a single transaction that is rolled back. Do not run this file through a runner
-- that executes each statement separately: `set local role` does not survive that, and the role-dependent
-- assertions then pass or fail for the wrong reason.
insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-b@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-field@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-sales@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-000000000001', 'RLS Organization A', 'rls-organization-a', 'active'),
  ('10000000-0000-0000-0000-000000000002', 'RLS Organization B', 'rls-organization-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'admin'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'admin'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'field'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'sales');

insert into public.clients (id, organization_id, display_name)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'RLS Client A'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'RLS Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '1 RLS Street', 'Testville'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '2 RLS Street', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'RLS Request A'),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'RLS Request B'),
  -- Left without an assessment on purpose, so the cross-tenant parentage assertion below reaches the
  -- composite foreign key instead of tripping assessments_request_unique first.
  ('40000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'RLS Request B, unassessed');

insert into public.assessments (id, organization_id, request_id, starts_at, ends_at)
values
  ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', now() + interval '1 day', now() + interval '1 day 2 hours'),
  ('a0000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', null, null);

insert into public.assessment_assignees (organization_id, assessment_id, user_id)
values
  ('10000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002');

insert into public.client_contacts (id, organization_id, client_id, first_name, is_primary)
values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Ada', true),
  ('50000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Bea', true);

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'email', 'Ada@Example.TEST', true),
  ('60000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'phone', '(555) 010-2030', true);

insert into public.permissions (key, description)
values ('rls.test.read', 'RLS test permission');

set local role postgres;
select throws_ok(
  $$insert into public.organization_members (organization_id, user_id, role) values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'admin')$$,
  '23505',
  null,
  'an Auth user cannot belong to multiple organizations'
);

-- Data model invariants, checked with row level security out of the way.
select is(
  (select is_primary from public.properties where id = '30000000-0000-0000-0000-000000000001'),
  true,
  'the first property a client gets becomes its primary property'
);

select is(
  (select normalized_value from public.client_contact_methods where id = '60000000-0000-0000-0000-000000000001'),
  'ada@example.test',
  'an email contact method is normalized for search and duplicate detection'
);

select is(
  (select normalized_value from public.client_contact_methods where id = '60000000-0000-0000-0000-000000000002'),
  '5550102030',
  'a phone contact method is normalized to digits'
);

select is(
  (select count(*)::integer from public.client_communication_preferences where client_id = '20000000-0000-0000-0000-000000000001'),
  1,
  'every client is created with a communication preference row'
);

select throws_ok(
  $$insert into public.properties (organization_id, client_id, address_line1, city, is_primary, label) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '3 RLS Street', 'Testville', true, 'Extra primary')$$,
  '23505',
  null,
  'a client cannot have two primary properties'
);

-- A second property lets us prove the primary property cannot simply disappear.
insert into public.properties (id, organization_id, client_id, address_line1, city, label)
values ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '3 RLS Street', 'Testville', 'Second site');

select is(
  (select is_primary from public.properties where id = '30000000-0000-0000-0000-000000000003'),
  false,
  'a later property does not take over as primary on its own'
);

set constraints properties_enforce_primary immediate;
select throws_ok(
  $$update public.properties set deleted_at = now() where id = '30000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'removing the primary property is refused unless another property takes over'
);
set constraints properties_enforce_primary deferred;

delete from public.properties where id = '30000000-0000-0000-0000-000000000003';

update public.clients
set lifecycle_status = 'customer'
where id = '20000000-0000-0000-0000-000000000001';

select ok(
  (select converted_to_customer_at is not null from public.clients where id = '20000000-0000-0000-0000-000000000001'),
  'converting a lead records when it became a customer'
);

select throws_ok(
  $$update public.clients set lifecycle_status = 'lead' where id = '20000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'a customer cannot be changed back to a lead'
);

select throws_ok(
  $$insert into public.client_contacts (organization_id, client_id, first_name) values ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Cross tenant')$$,
  '23503',
  null,
  'a named contact cannot point at a client in another organization'
);

select throws_ok(
  $$insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'email', 'second@example.test', true)$$,
  '23505',
  null,
  'a client cannot have two primary email addresses'
);

-- Part 3: reusable notes, tags, attachments, property contacts, and activity fixtures. Still running as
-- postgres, so these prove data-model invariants with row level security out of the way.
insert into public.notes (id, organization_id, body)
values
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Org A note'),
  ('70000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Org B note');

insert into public.note_links (organization_id, note_id, entity_type, entity_id)
values ('10000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'client', '20000000-0000-0000-0000-000000000001');

select throws_ok(
  $$insert into public.note_links (organization_id, note_id, entity_type, entity_id) values ('10000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'client', '20000000-0000-0000-0000-000000000002')$$,
  '23503',
  null,
  'a note cannot be linked to a client in another organization'
);

select is(
  (select count(*)::integer from public.activity_events where entity_id = '20000000-0000-0000-0000-000000000001' and event_type = 'note_added'),
  1,
  'linking a note to a client records one note_added activity event'
);

insert into public.tags (id, organization_id, name)
values ('80000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'VIP');

select throws_ok(
  $$insert into public.tags (organization_id, name) values ('10000000-0000-0000-0000-000000000001', 'vip')$$,
  '23505',
  null,
  'a tag name is unique per organization regardless of case'
);

insert into public.tags (id, organization_id, name)
values ('80000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'VIP');

insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id)
values ('10000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', 'client', '20000000-0000-0000-0000-000000000001');

select is(
  (select count(*)::integer from public.activity_events where entity_id = '20000000-0000-0000-0000-000000000001' and event_type = 'tag_assigned'),
  1,
  'assigning a tag records one tag_assigned activity event'
);

insert into public.attachments (id, organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key)
values
  ('90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'client', '20000000-0000-0000-0000-000000000001', 'photo.jpg', 'image/jpeg', 1024, 'org-a/client-a/photo.jpg'),
  ('90000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'client', '20000000-0000-0000-0000-000000000002', 'private.pdf', 'application/pdf', 2048, 'org-b/client-b/private.pdf');

select throws_ok(
  $$insert into public.attachments (organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key) values ('10000000-0000-0000-0000-000000000001', 'client', '20000000-0000-0000-0000-000000000001', 'huge.zip', 'application/zip', 26214401, 'org-a/client-a/huge.zip')$$,
  '23514',
  null,
  'an attachment over 25 MB is refused'
);

insert into public.property_contacts (id, organization_id, property_id, first_name, is_primary)
values ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Tenant Tom', true);

select throws_ok(
  $$insert into public.property_contacts (organization_id, property_id, first_name, is_primary) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Second primary', true)$$,
  '23505',
  null,
  'a property cannot have two primary contacts'
);

insert into public.property_contact_methods (organization_id, property_id, kind, value, is_primary)
values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'email', 'Tom@Example.TEST', true);

select is(
  (select normalized_value from public.property_contact_methods where property_id = '30000000-0000-0000-0000-000000000001' and kind = 'email'),
  'tom@example.test',
  'a property contact email is normalized for search and duplicate detection'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

select is((select count(*)::integer from public.organizations), 1, 'a member sees only their active organization');
select is((select count(*)::integer from public.organization_members), 3, 'a member sees the whole team roster in their organization');
select is((select count(*)::integer from public.clients), 1, 'a member sees only clients in their organization');
select is((select count(*)::integer from public.properties), 1, 'a member sees only properties in their organization');
select is((select count(*)::integer from public.requests), 1, 'a member sees only requests in their organization');
select is((select count(*)::integer from public.client_contacts), 1, 'a member sees only named contacts in their organization');
select is((select count(*)::integer from public.client_contact_methods), 1, 'a member sees only contact methods in their organization');
select is((select count(*)::integer from public.client_communication_preferences), 1, 'a member sees only communication preferences in their organization');
select is((select count(*)::integer from public.organization_settings), 1, 'a member sees only settings in their organization');
select is((select count(*)::integer from public.profiles where id = '00000000-0000-0000-0000-000000000001'), 1, 'a user sees their own profile');
select is((select count(*)::integer from public.profiles where id = '00000000-0000-0000-0000-000000000002'), 0, 'a user cannot see another profile');
select is((select count(*)::integer from public.permissions where key = 'rls.test.read'), 1, 'authenticated users can see the global permission catalog');

select is((select count(*)::integer from public.notes), 1, 'a member sees only notes linked to entities in their organization');
select is((select count(*)::integer from public.tags), 1, 'a member sees only tags in their organization');
select is((select count(*)::integer from public.tag_assignments), 1, 'a member sees only tag assignments in their organization');
select is((select count(*)::integer from public.attachments), 1, 'a member sees only attachments in their organization');
select is((select count(*)::integer from public.property_contacts), 1, 'a member sees only property contacts in their organization');
select is((select count(*)::integer from public.activity_events), 4, 'a member sees only activity events in their organization');
select is((select count(*)::integer from public.assessments), 1, 'a member sees only assessments in their organization');
select is((select count(*)::integer from public.assessment_assignees), 1, 'a member sees only assessment assignees in their organization');

select throws_ok(
  $$insert into public.clients (organization_id, display_name) values ('10000000-0000-0000-0000-000000000002', 'Cross-tenant client')$$,
  '42501',
  null,
  'cross-tenant client insert is denied'
);

select throws_ok(
  $$insert into public.client_contact_methods (organization_id, client_id, kind, value) values ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'email', 'cross@example.test')$$,
  '42501',
  null,
  'cross-tenant contact method insert is denied'
);

-- Part 3 acceptance: an attachment cannot be uploaded to, or downloaded from, another organization's
-- Client or Property, even with a guessed id. Two different mechanisms cover this, which is why both
-- error codes below are correct and different: claiming another organization's id outright trips the
-- row level security policy (42501), while keeping your own organization_id but pointing entity_id at
-- their client trips the private.validate_linked_entity trigger (23503). Neither path leaves a row, so
-- a presigned upload URL is never issued for it.
select throws_ok(
  $$insert into public.attachments (organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key) values ('10000000-0000-0000-0000-000000000002', 'client', '20000000-0000-0000-0000-000000000002', 'stolen.jpg', 'image/jpeg', 1024, 'org-b/client-b/stolen.jpg')$$,
  '42501',
  null,
  'cross-tenant attachment insert is denied'
);

select throws_ok(
  $$insert into public.attachments (organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key) values ('10000000-0000-0000-0000-000000000001', 'client', '20000000-0000-0000-0000-000000000002', 'guessed.jpg', 'image/jpeg', 1024, 'org-a/guessed/guessed.jpg')$$,
  '23503',
  null,
  'an attachment cannot be attached to another organization client by guessing its id'
);

select is(
  (select count(*)::integer from public.attachments where id = '90000000-0000-0000-0000-000000000002'),
  0,
  'another organization attachment cannot be read by id, so its download URL can never be issued'
);

-- Part 1a acceptance: an assessment belongs to exactly one organization, and so does everyone assigned
-- to it. Claiming another organization's id trips row level security (42501); keeping your own
-- organization_id but pointing at their request, or at one of their team members, trips the composite
-- foreign keys instead (23503). Both paths have to be closed, which is why the codes differ.
select throws_ok(
  $$insert into public.assessments (organization_id, request_id) values ('10000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'cross-tenant assessment insert is denied'
);

select throws_ok(
  $$insert into public.assessments (organization_id, request_id) values ('10000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003')$$,
  '23503',
  null,
  'an assessment cannot be attached to another organization request by guessing its id'
);

select lives_ok(
  $$update public.assessments set instructions = 'Cross-tenant instructions' where id = 'a0000000-0000-0000-0000-000000000002'$$,
  'cross-tenant assessment update is denied'
);

set local role postgres;
select ok(
  (select instructions is null from public.assessments where id = 'a0000000-0000-0000-0000-000000000002'),
  'cross-tenant assessment update changes no rows'
);
set local role authenticated;

select lives_ok(
  $$delete from public.assessments where id = 'a0000000-0000-0000-0000-000000000002'$$,
  'cross-tenant assessment delete is denied'
);

set local role postgres;
select is(
  (select count(*)::integer from public.assessments where id = 'a0000000-0000-0000-0000-000000000002'),
  1,
  'cross-tenant assessment delete removes no rows'
);
set local role authenticated;

select throws_ok(
  $$insert into public.assessment_assignees (organization_id, assessment_id, user_id) values ('10000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'cross-tenant assessment assignee insert is denied'
);

select throws_ok(
  $$insert into public.assessment_assignees (organization_id, assessment_id, user_id) values ('10000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')$$,
  '23503',
  null,
  'an assessment cannot be assigned to a user from another organization'
);

select lives_ok(
  $$delete from public.assessment_assignees where assessment_id = 'a0000000-0000-0000-0000-000000000002'$$,
  'cross-tenant assessment assignee delete is denied'
);

set local role postgres;
select is(
  (select count(*)::integer from public.assessment_assignees where assessment_id = 'a0000000-0000-0000-0000-000000000002'),
  1,
  'cross-tenant assessment assignee delete removes no rows'
);
set local role authenticated;

select lives_ok(
  $$update public.clients set display_name = 'Cross-tenant update' where id = '20000000-0000-0000-0000-000000000002'$$,
  'cross-tenant client update is denied'
);

set local role postgres;
select ok((select display_name = 'RLS Client B' from public.clients where id = '20000000-0000-0000-0000-000000000002'), 'cross-tenant client update changes no rows');
set local role authenticated;

select lives_ok(
  $$update public.organization_settings set locale = 'en-GB' where organization_id = '10000000-0000-0000-0000-000000000001'$$,
  'a member can update their organization settings'
);

select lives_ok(
  $$update public.organization_settings set locale = 'fr-FR' where organization_id = '10000000-0000-0000-0000-000000000002'$$,
  'cross-tenant settings update is denied'
);

set local role postgres;
select ok((select locale = 'en-US' from public.organization_settings where organization_id = '10000000-0000-0000-0000-000000000002'), 'cross-tenant settings update changes no rows');
set local role authenticated;

select lives_ok(
  $$update public.profiles set full_name = 'Other user' where id = '00000000-0000-0000-0000-000000000002'$$,
  'updating another user profile is denied'
);

set local role postgres;
select ok((select full_name is null from public.profiles where id = '00000000-0000-0000-0000-000000000002'), 'cross-user profile update changes no rows');
set local role authenticated;

-- A field worker reaches clients only through assigned work, never through the client list.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);

select is((select count(*)::integer from public.clients), 0, 'a field worker cannot list clients');
select is(
  (select count(*)::integer from public.clients where id = '20000000-0000-0000-0000-000000000001'),
  0,
  'a field worker cannot open an unrelated client directly by id'
);
select is((select count(*)::integer from public.properties), 0, 'a field worker cannot list properties');
select is((select count(*)::integer from public.client_contacts), 0, 'a field worker cannot list named contacts');
select is((select count(*)::integer from public.client_contact_methods), 0, 'a field worker cannot list contact methods');
select is((select count(*)::integer from public.client_communication_preferences), 0, 'a field worker cannot list communication preferences');
select is((select count(*)::integer from public.requests), 1, 'a field worker still sees work records in their organization');
select is((select count(*)::integer from public.notes), 0, 'a field worker cannot see any notes');
select is((select count(*)::integer from public.tag_assignments), 0, 'a field worker cannot see any tag assignments');
select is((select count(*)::integer from public.attachments), 0, 'a field worker cannot see any attachments');
select is((select count(*)::integer from public.property_contacts), 0, 'a field worker cannot see any property contacts');
select throws_ok(
  $$insert into public.note_links (organization_id, note_id, entity_type, entity_id) values ('10000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'property', '30000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'a field worker cannot link a note to a property'
);

-- The private helpers are only reachable from policy expressions, so these two assertions inspect them
-- directly while keeping the field worker's identity in the JWT claim.
set local role postgres;
select is(
  private.has_permission('10000000-0000-0000-0000-000000000001', 'customers.view'),
  false,
  'a field worker holds no customers.view permission'
);

select is(
  private.client_is_assigned_to_current_user('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001'),
  false,
  'the assigned-work seam grants nothing until scheduling exists'
);
set local role authenticated;

select throws_ok(
  $$insert into public.clients (organization_id, display_name) values ('10000000-0000-0000-0000-000000000001', 'Field created client')$$,
  '42501',
  null,
  'a field worker cannot create a client'
);

select lives_ok(
  $$update public.clients set display_name = 'Field edit' where id = '20000000-0000-0000-0000-000000000001'$$,
  'a field worker client update is denied'
);

set local role postgres;
select ok(
  (select display_name = 'RLS Client A' from public.clients where id = '20000000-0000-0000-0000-000000000001'),
  'a field worker client update changes no rows'
);
set local role authenticated;

-- A sales member creates and edits, but never deletes or merges.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);

select lives_ok(
  $$insert into public.clients (organization_id, display_name) values ('10000000-0000-0000-0000-000000000001', 'Sales created client')$$,
  'a sales member can create a client'
);

select lives_ok(
  $$insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id) values ('10000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', 'property', '30000000-0000-0000-0000-000000000001')$$,
  'a sales member can tag a property'
);

set local role postgres;
select is(
  private.has_permission('10000000-0000-0000-0000-000000000001', 'customers.delete'),
  false,
  'a sales member cannot delete clients'
);

select is(
  private.has_permission('10000000-0000-0000-0000-000000000001', 'customers.merge'),
  false,
  'a sales member cannot merge clients'
);
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

set local role postgres;
update public.organizations
set lifecycle_status = 'suspended'
where id = '10000000-0000-0000-0000-000000000001';

set local role authenticated;
select is((select count(*)::integer from public.organizations), 0, 'a suspended organization is hidden from its former member');
select is((select count(*)::integer from public.clients), 0, 'data in a suspended organization is hidden');
select is((select count(*)::integer from public.client_contact_methods), 0, 'contact methods in a suspended organization are hidden');
select is((select count(*)::integer from public.notes), 0, 'notes in a suspended organization are hidden');

select * from finish();
rollback;
