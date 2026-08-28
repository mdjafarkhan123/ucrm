begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- Public visitor traffic never touches these tables or commands directly.
select is(
  has_function_privilege('anon',
    'public.accept_website_chat_first_message(uuid, text, text, text, text, text, text, text, boolean, text, jsonb)',
    'execute'),
  false,
  'anonymous callers cannot start a Website Chat conversation directly'
);
select is(
  has_function_privilege('authenticated',
    'public.accept_website_chat_first_message(uuid, text, text, text, text, text, text, text, boolean, text, jsonb)',
    'execute'),
  false,
  'signed-in members cannot start a Website Chat conversation directly'
);
select is(
  has_function_privilege('service_role',
    'public.accept_website_chat_first_message(uuid, text, text, text, text, text, text, text, boolean, text, jsonb)',
    'execute'),
  true,
  'the server service role owns the first-message command'
);
select is(
  has_table_privilege('anon', 'public.website_chat_sessions', 'insert'),
  false,
  'anonymous callers cannot write Website Chat sessions'
);
select is(
  has_table_privilege('authenticated', 'public.website_chat_messages', 'select'),
  false,
  'signed-in members cannot read Website Chat messages outside a command'
);
select is(
  (select bool_and(rowsecurity) from pg_tables
   where schemaname = 'public'
     and tablename in ('website_chat_sessions', 'website_chat_messages',
                       'website_chat_capacity_buckets', 'website_chat_capacity_reservations',
                       'website_chat_allowance_periods')),
  true,
  'every new Website Chat table keeps row level security on'
);

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000004c1', 'Website Chat WC4 Test', 'website-chat-wc4-test', 'active');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select '90000000-0000-0000-0000-0000000004c1', id, now() - interval '2 minutes', 'provisioning',
  'Website Chat WC4 test baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

-- One accepted conversation for the whole period, so the cap is reachable in a test.
select public.apply_organization_limit_exception(
  '90000000-0000-0000-0000-0000000004c1', 'website_chat_accepted_conversations', 'numeric', 1,
  now() - interval '30 seconds', null, 'website-chat-wc4-cap',
  'Cap of one accepted conversation for the WC4 database test.', 'owner@example.test'
);

insert into public.website_chat_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000004c1', now() - interval '1 minute', now() + interval '29 days');

insert into public.website_chat_widgets (id, organization_id, name, published, source_label)
values ('90000000-0000-0000-0000-0000000004d1', '90000000-0000-0000-0000-0000000004c1',
  'WC4 Test Widget', true, 'Website Chat');

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values ('90000000-0000-0000-0000-0000000004c1', '90000000-0000-0000-0000-0000000004d1',
  'https://tester.example.com');

-- Two different Clients, one holding the phone the visitor types, one holding the email.
insert into public.clients (id, organization_id, display_name, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000004a1', '90000000-0000-0000-0000-0000000004c1', 'Phone Client', 'lead'),
  ('90000000-0000-0000-0000-0000000004a2', '90000000-0000-0000-0000-0000000004c1', 'Email Client', 'lead');

insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
values
  ('90000000-0000-0000-0000-0000000004c1', '90000000-0000-0000-0000-0000000004a1', 'phone', '+14155550101', true),
  ('90000000-0000-0000-0000-0000000004c1', '90000000-0000-0000-0000-0000000004a2', 'email', 'conflict-y@example.test', true);

-- A second organization, with room for more than one conversation, for the new-Lead paths ---------

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000004c2', 'Website Chat WC4 Names', 'website-chat-wc4-names',
  'active');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select '90000000-0000-0000-0000-0000000004c2', id, now() - interval '2 minutes', 'provisioning',
  'Website Chat WC4 name-split baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select public.apply_organization_limit_exception(
  '90000000-0000-0000-0000-0000000004c2', 'website_chat_accepted_conversations', 'numeric', 5,
  now() - interval '30 seconds', null, 'website-chat-wc4-names',
  'Room for the name-split conversations in the WC4 database test.', 'owner@example.test'
);

insert into public.website_chat_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000004c2', now() - interval '1 minute', now() + interval '29 days');

insert into public.website_chat_widgets (id, organization_id, name, published, source_label)
values ('90000000-0000-0000-0000-0000000004d2', '90000000-0000-0000-0000-0000000004c2',
  'WC4 Name Widget', true, 'Website Chat');

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values ('90000000-0000-0000-0000-0000000004c2', '90000000-0000-0000-0000-0000000004d2',
  'https://names.example.com');

-- The visitor types one name. Everything before the first space is the given name, the whole
-- remainder is the family name, and the untouched string is what the Client is displayed under.
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000004d2'),
  'https://names.example.com',
  'wc4-session-token-hash-000000000010',
  'wc4-idempotency-key-0010',
  '  Mary Jane   Watson  ',
  '+14155550301',
  null,
  'My gutters are overflowing.',
  true,
  null,
  '{}'::jsonb
);

select is(
  (select first_name from public.clients
   where organization_id = '90000000-0000-0000-0000-0000000004c2'
     and display_name = 'Mary Jane Watson'),
  'Mary',
  'the name before the first space becomes the Client first name'
);
select is(
  (select last_name from public.clients
   where organization_id = '90000000-0000-0000-0000-0000000004c2'
     and display_name = 'Mary Jane Watson'),
  'Jane Watson',
  'everything after the first space becomes the Client last name'
);
select is(
  (select visitor_name from public.website_chat_sessions
   where session_token_hash = 'wc4-session-token-hash-000000000010'),
  'Mary Jane Watson',
  'the session keeps the whole submitted name, with its spacing normalized'
);

-- A visitor who gives one word has no surname to invent.
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000004d2'),
  'https://names.example.com',
  'wc4-session-token-hash-000000000011',
  'wc4-idempotency-key-0011',
  'Prince',
  '+14155550302',
  null,
  'Do you install skylights?',
  true,
  null,
  '{}'::jsonb
);

select is(
  (select last_name from public.clients
   where organization_id = '90000000-0000-0000-0000-0000000004c2'
     and display_name = 'Prince'),
  null::text,
  'a single word name leaves the Client last name empty rather than guessing'
);

-- One character passes every length check here but not `clients.display_name`, so it is refused
-- before it can reach the Client insert.
select is(
  (public.accept_website_chat_first_message(
    (select public_token from public.website_chat_widgets
     where id = '90000000-0000-0000-0000-0000000004d2'),
    'https://names.example.com',
    'wc4-session-token-hash-000000000012',
    'wc4-idempotency-key-0012',
    'P',
    '+14155550303',
    null,
    'Hello?',
    true,
    null,
    '{}'::jsonb
  ) ->> 'status'),
  'refused',
  'a one character name is refused rather than failing on the Client insert'
);

-- The conflicting-identifier path -----------------------------------------------------------------

create temporary table wc4_first_result on commit drop as
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000004d1'),
  'https://tester.example.com',
  'wc4-session-token-hash-000000000001',
  'wc4-idempotency-key-0001',
  'Dana',
  '+14155550101',
  'conflict-y@example.test',
  'My furnace is making a noise.',
  true,
  null,
  '{"landing_page": "https://tester.example.com/heating"}'::jsonb
) as payload;

select is(
  (select payload ->> 'status' from wc4_first_result),
  'accepted',
  'a valid first message from an allowed origin is accepted'
);
select is(
  (select payload ->> 'match_status' from wc4_first_result),
  'needs_review',
  'two identifiers pointing at different Clients park the session for review'
);
select is(
  (select payload ->> 'client_id' from wc4_first_result),
  null::text,
  'a needs review session never guesses a Client'
);
select is(
  (select count(*)::integer from public.website_chat_sessions
   where organization_id = '90000000-0000-0000-0000-0000000004c1'
     and candidate_client_id_by_phone = '90000000-0000-0000-0000-0000000004a1'
     and candidate_client_id_by_email = '90000000-0000-0000-0000-0000000004a2'),
  1,
  'both candidate Clients are stored for the staff resolution step'
);
select is(
  (select accepted_count from public.website_chat_capacity_buckets
   where organization_id = '90000000-0000-0000-0000-0000000004c1'),
  1,
  'an accepted first message claims exactly one allowance unit'
);

-- A retried POST is a no-op ------------------------------------------------------------------------

create temporary table wc4_retry_result on commit drop as
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000004d1'),
  'https://tester.example.com',
  'wc4-session-token-hash-000000000002',
  'wc4-idempotency-key-0001',
  'Dana',
  '+14155550101',
  'conflict-y@example.test',
  'My furnace is making a noise.',
  true,
  null,
  '{}'::jsonb
) as payload;

select is(
  (select retry.payload ->> 'session_id' from wc4_retry_result retry),
  (select first.payload ->> 'session_id' from wc4_first_result first),
  'a retried first message returns the original session'
);
select is(
  (select count(*)::integer from public.website_chat_sessions
   where organization_id = '90000000-0000-0000-0000-0000000004c1'),
  1,
  'a retried first message never creates a second session'
);
select is(
  (select accepted_count from public.website_chat_capacity_buckets
   where organization_id = '90000000-0000-0000-0000-0000000004c1'),
  1,
  'a retried first message never claims a second allowance unit'
);

-- The cap refuses a new conversation but never breaks an accepted one --------------------------------

select is(
  (public.accept_website_chat_first_message(
    (select public_token from public.website_chat_widgets
     where id = '90000000-0000-0000-0000-0000000004d1'),
    'https://tester.example.com',
    'wc4-session-token-hash-000000000003',
    'wc4-idempotency-key-0002',
    'Sam',
    '+14155550199',
    'sam@example.test',
    'Can someone quote a new water heater?',
    false,
    null,
    '{}'::jsonb
  ) ->> 'status'),
  'cap_reached',
  'a new conversation is refused once the period allowance is spent'
);
select is(
  (select count(*)::integer from public.website_chat_capacity_reservations
   where organization_id = '90000000-0000-0000-0000-0000000004c1'),
  1,
  'a refused conversation leaves no reservation behind'
);
select is(
  (public.post_website_chat_message(
    'wc4-session-token-hash-000000000001',
    'https://tester.example.com',
    'Any update on my furnace?',
    'wc4-message-key-0001'
  ) ->> 'status'),
  'accepted',
  'an already accepted session stays usable at the hard cap'
);

select * from finish();

rollback;
