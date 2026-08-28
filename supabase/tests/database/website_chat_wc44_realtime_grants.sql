-- WC4.4 Stage B: the visitor's private Realtime channel -- the grant, the join check, and the publish.
--
-- What has to hold: only the server can mint a grant, only an anonymous joiner can ask the join
-- question, a grant authorizes exactly one topic and stops authorizing it when it expires, a live tab's
-- topic is not rotated out from under it, a wrong origin and a wrong token are refused identically, a
-- new message publishes to that session's own topic and to no other, a session with no live grant
-- publishes nothing at all, and `sender_user_id` never reaches the wire.

begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- Privileges: the mint is the server's, the join check is the visitor's ----------------------------

select is(
  has_function_privilege('anon',
    'public.mint_website_chat_realtime_grant(text, text, text, integer)', 'execute'),
  false,
  'an anonymous caller cannot mint itself a channel grant'
);
select is(
  has_function_privilege('authenticated',
    'public.mint_website_chat_realtime_grant(text, text, text, integer)', 'execute'),
  false,
  'a signed-in member cannot mint a visitor channel grant'
);
select is(
  has_function_privilege('service_role',
    'public.mint_website_chat_realtime_grant(text, text, text, integer)', 'execute'),
  true,
  'the server service role owns the mint command'
);
select is(
  has_function_privilege('anon',
    'private.website_chat_realtime_topic_granted(text)', 'execute'),
  true,
  'the anonymous visitor can ask the one question the join needs answered'
);
select is(
  has_table_privilege('anon', 'public.website_chat_realtime_grants', 'select'),
  false,
  'the visitor never gets to read the grants table itself, only the boolean about one topic'
);

-- The policy: read only, Broadcast only, anonymous only ---------------------------------------------

select is(
  (select count(*)::integer from pg_policy
   where polrelid = 'realtime.messages'::regclass and polname = 'website_chat_visitor_channel_read'),
  1,
  'the visitor channel policy is installed on realtime.messages'
);
select is(
  (select polcmd::text from pg_policy
   where polrelid = 'realtime.messages'::regclass and polname = 'website_chat_visitor_channel_read'),
  'r',
  'the visitor may listen on their channel and may never broadcast on it'
);

set local role postgres;

-- Fixture: one organization, one widget, one allowed origin, two visitor sessions -------------------

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000044f1', 'Website Chat WC44 Realtime',
  'website-chat-wc44-realtime', 'active');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select '90000000-0000-0000-0000-0000000044f1', id, now() - interval '2 minutes', 'provisioning',
  'Website Chat WC4.4 realtime baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select public.apply_organization_limit_exception(
  '90000000-0000-0000-0000-0000000044f1', 'website_chat_accepted_conversations', 'numeric', 5,
  now() - interval '30 seconds', null, 'website-chat-wc44-realtime',
  'Room for two conversations in the WC4.4 realtime test.', 'owner@example.test'
);

insert into public.website_chat_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000044f1', now() - interval '1 minute', now() + interval '29 days');

insert into public.website_chat_widgets (id, organization_id, name, published, source_label)
values ('90000000-0000-0000-0000-0000000044f2', '90000000-0000-0000-0000-0000000044f1',
  'WC4.4 Realtime Widget', true, 'Website Chat');

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values ('90000000-0000-0000-0000-0000000044f1', '90000000-0000-0000-0000-0000000044f2',
  'https://listener.example.com');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '90000000-0000-0000-0000-0000000044f3', '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', 'wc44-realtime-staff@example.test', 'x', now(), now(), now()
);

select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000044f2'),
  'https://listener.example.com',
  'wc44-realtime-token-hash-0000000000a',
  'wc44-realtime-idempotency-000a',
  'Ada Listener',
  '+14155550501',
  null,
  'First message from the listening visitor.',
  true,
  null,
  '{}'::jsonb
);

select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000044f2'),
  'https://listener.example.com',
  'wc44-realtime-token-hash-0000000000b',
  'wc44-realtime-idempotency-000b',
  'Bo Bystander',
  '+14155550502',
  null,
  'A message from a visitor who is not listening.',
  true,
  null,
  '{}'::jsonb
);

-- Minting -------------------------------------------------------------------------------------------

create temporary table wc44_grant_a on commit drop as
select public.mint_website_chat_realtime_grant(
  'wc44-realtime-token-hash-0000000000a',
  'https://listener.example.com',
  'wc:' || repeat('a', 64),
  1800
) as payload;

select is(
  (select payload ->> 'status' from wc44_grant_a),
  'ok',
  'the session''s own token and an allowlisted origin earn a channel grant'
);
select is(
  (select payload ->> 'channel_topic' from wc44_grant_a),
  'wc:' || repeat('a', 64),
  'the grant is issued for the topic the server minted'
);
select is(
  (public.mint_website_chat_realtime_grant(
    'wc44-realtime-token-hash-0000000000a', 'https://attacker.example.com',
    'wc:' || repeat('c', 64), 1800
  ) ->> 'status'),
  'refused',
  'a correct token from an origin that is not allowlisted earns no channel'
);
select is(
  (public.mint_website_chat_realtime_grant(
    'wc44-realtime-token-hash-not-real', 'https://listener.example.com',
    'wc:' || repeat('c', 64), 1800
  ) ->> 'status'),
  'refused',
  'a wrong token is refused with the same silent answer as a wrong origin'
);
select is(
  (public.mint_website_chat_realtime_grant(
    'wc44-realtime-token-hash-0000000000a', 'https://listener.example.com',
    'not-a-channel-topic', 1800
  ) ->> 'status'),
  'refused',
  'a topic that is not the minted shape is refused rather than stored'
);

-- A second tab must not rotate the topic the first tab is already listening on.
select is(
  (public.mint_website_chat_realtime_grant(
    'wc44-realtime-token-hash-0000000000a', 'https://listener.example.com',
    'wc:' || repeat('d', 64), 1800
  ) ->> 'channel_topic'),
  'wc:' || repeat('a', 64),
  'a grant with real life left in it is handed back rather than rotated'
);

-- The join check -------------------------------------------------------------------------------------

select is(
  private.website_chat_realtime_topic_granted('wc:' || repeat('a', 64)),
  true,
  'a live grant authorizes its own topic'
);
select is(
  private.website_chat_realtime_topic_granted('wc:' || repeat('f', 64)),
  false,
  'a topic nobody was granted authorizes nothing'
);

-- Publishing -----------------------------------------------------------------------------------------

insert into public.website_chat_messages (
  organization_id, session_id, client_id, direction, sender_type, sender_user_id, body
)
select s.organization_id, s.id, s.client_id, 'outbound', 'staff',
  '90000000-0000-0000-0000-0000000044f3', 'A staff reply into a listening panel.'
from public.website_chat_sessions s
where s.session_token_hash = 'wc44-realtime-token-hash-0000000000a';

-- One, not two: the visitor's own first message was written before this session had a grant, and a
-- message published to nobody is exactly what the polling fallback is for.
select is(
  (select count(*)::integer from realtime.messages
   where topic = 'wc:' || repeat('a', 64) and event = 'website_chat_message'),
  1,
  'the staff reply reached that session''s own topic'
);
select is(
  (select bool_and(not (payload ? 'sender_user_id')) from realtime.messages
   where topic = 'wc:' || repeat('a', 64)),
  true,
  'the staff member''s identity never reaches the wire'
);

-- The other visitor has no grant at all, so nothing about their conversation is ever published.
insert into public.website_chat_messages (
  organization_id, session_id, client_id, direction, sender_type, body
)
select s.organization_id, s.id, s.client_id, 'outbound', 'staff', 'A reply nobody is listening for.'
from public.website_chat_sessions s
where s.session_token_hash = 'wc44-realtime-token-hash-0000000000b';

select is(
  (select count(*)::integer from realtime.messages
   where payload ->> 'body' = 'A reply nobody is listening for.'),
  0,
  'a session with no live grant publishes nothing'
);

-- Expiry is the whole lifetime of the authorization.
update public.website_chat_realtime_grants
set expires_at = now() - interval '1 second'
where channel_topic = 'wc:' || repeat('a', 64);

select is(
  private.website_chat_realtime_topic_granted('wc:' || repeat('a', 64)),
  false,
  'an expired grant stops authorizing its topic'
);

insert into public.website_chat_messages (
  organization_id, session_id, client_id, direction, sender_type, body
)
select s.organization_id, s.id, s.client_id, 'outbound', 'staff', 'A reply after the grant lapsed.'
from public.website_chat_sessions s
where s.session_token_hash = 'wc44-realtime-token-hash-0000000000a';

select is(
  (select count(*)::integer from realtime.messages
   where payload ->> 'body' = 'A reply after the grant lapsed.'),
  0,
  'an expired grant publishes nothing either'
);

-- A lapsed grant is replaced, not reused.
select is(
  (public.mint_website_chat_realtime_grant(
    'wc44-realtime-token-hash-0000000000a', 'https://listener.example.com',
    'wc:' || repeat('e', 64), 1800
  ) ->> 'channel_topic'),
  'wc:' || repeat('e', 64),
  'a lapsed grant rotates to the freshly minted topic'
);

-- The grant is a property of the session and dies with it. (The messages go first only because
-- their own foreign key protects a paid conversation from being deleted out from under itself.)
delete from public.website_chat_messages m
using public.website_chat_sessions s
where m.session_id = s.id and s.session_token_hash = 'wc44-realtime-token-hash-0000000000a';

delete from public.website_chat_sessions
where session_token_hash = 'wc44-realtime-token-hash-0000000000a';

select is(
  (select count(*)::integer from public.website_chat_realtime_grants
   where channel_topic = 'wc:' || repeat('e', 64)),
  0,
  'a deleted session takes its channel grant with it'
);

select * from finish();
rollback;
