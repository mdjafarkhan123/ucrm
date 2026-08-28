-- WC4.4 Stage A: the visitor's own read path, `get_website_chat_session_messages`.
--
-- What has to hold: a session reads its own messages and nobody else's, a wrong origin and a wrong
-- token are refused identically, a half cursor is refused rather than silently paging from the top,
-- a closed session still returns its history (WC0.3), keyset paging neither duplicates nor skips a
-- row, and `sender_user_id` never leaves the database.

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- Only the server may ever call this command directly.
select is(
  has_function_privilege('anon',
    'public.get_website_chat_session_messages(text, text, timestamptz, uuid, integer)', 'execute'),
  false,
  'anonymous callers cannot read a Website Chat conversation directly'
);
select is(
  has_function_privilege('authenticated',
    'public.get_website_chat_session_messages(text, text, timestamptz, uuid, integer)', 'execute'),
  false,
  'signed-in members cannot read a Website Chat conversation through the public command'
);
select is(
  has_function_privilege('service_role',
    'public.get_website_chat_session_messages(text, text, timestamptz, uuid, integer)', 'execute'),
  true,
  'the server service role owns the session read command'
);

set local role postgres;

-- Fixture: one organization, one widget, one allowed origin, two separate visitor sessions ---------

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000044c1', 'Website Chat WC44 Read', 'website-chat-wc44-read',
  'active');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select '90000000-0000-0000-0000-0000000044c1', id, now() - interval '2 minutes', 'provisioning',
  'Website Chat WC4.4 read-path baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select public.apply_organization_limit_exception(
  '90000000-0000-0000-0000-0000000044c1', 'website_chat_accepted_conversations', 'numeric', 5,
  now() - interval '30 seconds', null, 'website-chat-wc44-read',
  'Room for two conversations in the WC4.4 read test.', 'owner@example.test'
);

insert into public.website_chat_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000044c1', now() - interval '1 minute', now() + interval '29 days');

insert into public.website_chat_widgets (id, organization_id, name, published, source_label)
values ('90000000-0000-0000-0000-0000000044d1', '90000000-0000-0000-0000-0000000044c1',
  'WC4.4 Read Widget', true, 'Website Chat');

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values ('90000000-0000-0000-0000-0000000044c1', '90000000-0000-0000-0000-0000000044d1',
  'https://reader.example.com');

-- A real staff member, so the withheld `sender_user_id` is actually populated in the data.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '90000000-0000-0000-0000-0000000044e1', '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', 'wc44-staff@example.test', 'x', now(), now(), now()
);

-- Session A: the session under test.
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000044d1'),
  'https://reader.example.com',
  'wc44-session-token-hash-00000000000a',
  'wc44-idempotency-key-000a',
  'Alex Reader',
  '+14155550401',
  null,
  'Message 1 from the visitor.',
  true,
  null,
  '{}'::jsonb
);

-- Session B: a different visitor on the same widget, whose messages must never be readable above.
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000044d1'),
  'https://reader.example.com',
  'wc44-session-token-hash-00000000000b',
  'wc44-idempotency-key-000b',
  'Bee Other',
  '+14155550402',
  null,
  'A message that belongs to somebody else.',
  true,
  null,
  '{}'::jsonb
);

-- Four more visitor messages on session A, so paging has something to page.
select public.post_website_chat_message(
  'wc44-session-token-hash-00000000000a', 'https://reader.example.com',
  'Message ' || n::text || ' from the visitor.', 'wc44-message-key-000' || n::text
)
from generate_series(2, 5) as n;

-- One staff reply, carrying the identity that must never reach a visitor's browser.
insert into public.website_chat_messages (
  organization_id, session_id, client_id, direction, sender_type, sender_user_id, body
)
select s.organization_id, s.id, s.client_id, 'outbound', 'staff',
  '90000000-0000-0000-0000-0000000044e1', 'Message 6, from staff.'
from public.website_chat_sessions s
where s.session_token_hash = 'wc44-session-token-hash-00000000000a';

-- Isolation, projection, and the two refusals ------------------------------------------------------

create temporary table wc44_full_page on commit drop as
select public.get_website_chat_session_messages(
  'wc44-session-token-hash-00000000000a', 'https://reader.example.com', null, null, 30
) as payload;

select is(
  (select payload ->> 'status' from wc44_full_page),
  'ok',
  'the session''s own token and an allowlisted origin read the conversation'
);
select is(
  (select jsonb_array_length(payload -> 'messages') from wc44_full_page),
  6,
  'the read returns exactly this session''s six messages'
);
select is(
  (select bool_and(m ->> 'body' not like '%belongs to somebody else%')
   from wc44_full_page, jsonb_array_elements(payload -> 'messages') as m),
  true,
  'another visitor''s session is never mixed into this one'
);
select is(
  (select bool_and(not (m ? 'sender_user_id'))
   from wc44_full_page, jsonb_array_elements(payload -> 'messages') as m),
  true,
  'the staff member''s identity never appears in a visitor-facing payload'
);
select is(
  (public.get_website_chat_session_messages(
    'wc44-session-token-hash-00000000000a', 'https://attacker.example.com', null, null, 30
  ) ->> 'status'),
  'refused',
  'a correct token from an origin that is not allowlisted is refused'
);
select is(
  (public.get_website_chat_session_messages(
    'wc44-session-token-hash-not-a-real-token', 'https://reader.example.com', null, null, 30
  ) ->> 'status'),
  'refused',
  'a wrong token is refused with the same silent answer as a wrong origin'
);
select is(
  (public.get_website_chat_session_messages(
    'wc44-session-token-hash-00000000000a', 'https://reader.example.com', now(), null, 30
  ) ->> 'status'),
  'refused',
  'half a cursor is refused rather than quietly paging from the newest message'
);

-- Keyset paging: no duplicate, no gap ---------------------------------------------------------------

create temporary table wc44_page_one on commit drop as
select public.get_website_chat_session_messages(
  'wc44-session-token-hash-00000000000a', 'https://reader.example.com', null, null, 2
) as payload;

create temporary table wc44_page_two on commit drop as
select public.get_website_chat_session_messages(
  'wc44-session-token-hash-00000000000a',
  'https://reader.example.com',
  (select (payload -> 'messages' -> 1 ->> 'created_at')::timestamptz from wc44_page_one),
  (select (payload -> 'messages' -> 1 ->> 'id')::uuid from wc44_page_one),
  2
) as payload;

select is(
  (select payload -> 'has_more' from wc44_page_one),
  'true'::jsonb,
  'a partial page reports that more history exists'
);
select is(
  (select count(distinct m ->> 'id')::integer
   from (select payload from wc44_page_one union all select payload from wc44_page_two) pages,
        jsonb_array_elements(pages.payload -> 'messages') as m),
  4,
  'two keyset pages return four distinct messages -- no row is served twice'
);
select is(
  (select array_agg(m ->> 'body' order by (m ->> 'created_at')::timestamptz desc, (m ->> 'id')::uuid desc)
   from (select payload from wc44_page_one union all select payload from wc44_page_two) pages,
        jsonb_array_elements(pages.payload -> 'messages') as m),
  (select array_agg(x.body order by x.created_at desc, x.id desc)
   from (
     select m.id, m.body, m.created_at
     from public.website_chat_messages m
     join public.website_chat_sessions s on s.id = m.session_id
     where s.session_token_hash = 'wc44-session-token-hash-00000000000a'
     order by m.created_at desc, m.id desc
     limit 4
   ) x),
  'the two pages are exactly the four newest messages in order -- no gap between pages'
);

-- A closed conversation is still the visitor's to read ----------------------------------------------

update public.website_chat_sessions
set closed_at = now(), closed_reason = 'staff_ended'
where session_token_hash = 'wc44-session-token-hash-00000000000a';

select is(
  (select jsonb_array_length(
    public.get_website_chat_session_messages(
      'wc44-session-token-hash-00000000000a', 'https://reader.example.com', null, null, 30
    ) -> 'messages')),
  6,
  'a closed session still returns its full history'
);

select * from finish();

rollback;
