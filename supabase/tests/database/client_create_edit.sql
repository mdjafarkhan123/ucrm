begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- Fixtures are rolled back at the end of this file. Fixed IDs keep the assertions readable.
--
-- Written for `supabase test db`, which runs the file as one session. Development currently uses the
-- remote Supabase project with no local stack, so these assertions are verified there instead by running
-- the file inside a single transaction that is rolled back. Do not run it through a runner that executes
-- each statement separately: `set local role` does not survive that.
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
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'write-a@example.test', 'test', now(), now(), now()),
  ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'write-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('a1000000-0000-0000-0000-000000000001', 'Write Organization A', 'write-organization-a', 'active'),
  ('a1000000-0000-0000-0000-000000000002', 'Write Organization B', 'write-organization-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'admin'),
  ('a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'admin');

insert into public.tags (id, organization_id, name)
values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'write tag one'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'write tag two');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);

-- 1. Creating a client writes everything on the form in one go ------------------------------------------

select lives_ok(
  $$select public.create_client('{
    "organization_id": "a1000000-0000-0000-0000-000000000001",
    "display_name": "Dana Rivera",
    "client_type": "person",
    "first_name": "Dana",
    "last_name": "Rivera",
    "email": "  Dana@Example.TEST ",
    "phone": "(555) 111-2222",
    "initial_note": "Called about a new roof.",
    "property": {"address_line1": "1 Write Street", "city": "Testville"},
    "preferences": {"contact_policy": "no_marketing", "marketing": true},
    "tag_ids": ["a2000000-0000-0000-0000-000000000001", "a2000000-0000-0000-0000-000000000002"]
  }'::jsonb)$$,
  'a member can create a client with contact details, an address, a note, tags, and preferences'
);

select is(
  (select normalized_value from public.client_contact_methods
    where kind = 'email' and client_id = (select id from public.clients where display_name = 'Dana Rivera')),
  'dana@example.test',
  'the email is stored normalized'
);

select is(
  (select normalized_value from public.client_contact_methods
    where kind = 'phone' and client_id = (select id from public.clients where display_name = 'Dana Rivera')),
  '5551112222',
  'the phone is stored normalized'
);

select is(
  (select count(*)::integer from public.properties
    where client_id = (select id from public.clients where display_name = 'Dana Rivera') and is_primary),
  1,
  'the address becomes the one primary property'
);

select is(
  (select count(*)::integer from public.note_links
    where entity_type = 'client'
      and entity_id = (select id from public.clients where display_name = 'Dana Rivera')),
  1,
  'the first note is linked to the new client'
);

select is(
  (select contact_policy from public.client_communication_preferences
    where client_id = (select id from public.clients where display_name = 'Dana Rivera')),
  'no_marketing',
  'the contact policy is saved'
);

select is(
  (select count(*)::integer from public.tag_assignments
    where entity_type = 'client'
      and entity_id = (select id from public.clients where display_name = 'Dana Rivera')),
  2,
  'both tags are attached'
);

-- 2. Exact duplicates are refused by the database -------------------------------------------------------

select throws_ok(
  $$select public.create_client('{
    "organization_id": "a1000000-0000-0000-0000-000000000001",
    "display_name": "Dana Duplicate",
    "email": "DANA@example.test"
  }'::jsonb)$$,
  '23505',
  null,
  'the same email in a different letter case is refused'
);

select throws_ok(
  $$select public.create_client('{
    "organization_id": "a1000000-0000-0000-0000-000000000001",
    "display_name": "Dana Duplicate Phone",
    "phone": "555-111-2222"
  }'::jsonb)$$,
  '23505',
  null,
  'the same phone written differently is refused'
);

select is(
  (select count(*)::integer from public.clients
    where organization_id = 'a1000000-0000-0000-0000-000000000001'),
  1,
  'a refused duplicate leaves no half-written client behind'
);

-- 3. Another organization is a different world -----------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);

select lives_ok(
  $$select public.create_client('{
    "organization_id": "a1000000-0000-0000-0000-000000000002",
    "display_name": "Dana Elsewhere",
    "email": "dana@example.test"
  }'::jsonb)$$,
  'the same email in another organization is not blocked'
);

select throws_ok(
  $$select public.update_client(('{"organization_id": "a1000000-0000-0000-0000-000000000002", "display_name": "Stolen"}'::jsonb)
    || jsonb_build_object('id', (select id from public.clients where display_name = 'Dana Rivera')))$$,
  'P0002',
  null,
  'a member of another organization cannot edit this client'
);

-- 4. Editing ----------------------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.update_client(('{
    "organization_id": "a1000000-0000-0000-0000-000000000001",
    "display_name": "Dana Rivera",
    "client_type": "person",
    "first_name": "Dana",
    "last_name": "Rivera",
    "email": "  Dana@Example.TEST ",
    "phone": "(555) 111-2222"
  }'::jsonb) || jsonb_build_object('id', (select id from public.clients where display_name = 'Dana Rivera')))$$,
  'a client keeps its own email and phone when it is edited'
);

select lives_ok(
  $$select public.update_client(('{
    "organization_id": "a1000000-0000-0000-0000-000000000001",
    "display_name": "Dana Rivera",
    "client_type": "person",
    "first_name": "Dana",
    "last_name": "Rivera",
    "lifecycle_status": "customer",
    "email": "dana.new@example.test",
    "phone": "",
    "property": {"address_line1": "2 Write Street", "city": "Newville"},
    "preferences": {"contact_policy": "do_not_disturb"},
    "tag_ids": ["a2000000-0000-0000-0000-000000000002"]
  }'::jsonb) || jsonb_build_object('id', (select id from public.clients where display_name = 'Dana Rivera')))$$,
  'an edit saves identity, contact, address, policy, and tags together'
);

select is(
  (select normalized_value from public.client_contact_methods
    where kind = 'email' and client_id = (select id from public.clients where display_name = 'Dana Rivera')),
  'dana.new@example.test',
  'the new email replaces the old one'
);

select is(
  (select count(*)::integer from public.client_contact_methods
    where kind = 'phone' and client_id = (select id from public.clients where display_name = 'Dana Rivera')),
  0,
  'clearing the phone removes it'
);

select is(
  (select count(*)::integer from public.properties
    where client_id = (select id from public.clients where display_name = 'Dana Rivera')
      and deleted_at is null),
  1,
  'editing the address changes the property instead of adding another'
);

select is(
  (select address_line1 from public.properties
    where client_id = (select id from public.clients where display_name = 'Dana Rivera') and is_primary),
  '2 Write Street',
  'the property carries the new address'
);

select is(
  (select contact_policy || '/' || marketing::text from public.client_communication_preferences
    where client_id = (select id from public.clients where display_name = 'Dana Rivera')),
  'do_not_disturb/true',
  'do not disturb is saved without erasing the detailed choices underneath'
);

select is(
  (select count(*)::integer from public.tag_assignments
    where entity_type = 'client'
      and entity_id = (select id from public.clients where display_name = 'Dana Rivera')),
  1,
  'removed tags are taken off and kept tags stay'
);

select throws_ok(
  $$select public.update_client(('{
    "organization_id": "a1000000-0000-0000-0000-000000000001",
    "display_name": "Dana Rivera",
    "lifecycle_status": "lead"
  }'::jsonb) || jsonb_build_object('id', (select id from public.clients where display_name = 'Dana Rivera')))$$,
  '23514',
  null,
  'a customer cannot be pushed back to being a lead'
);

select * from finish();
rollback;
