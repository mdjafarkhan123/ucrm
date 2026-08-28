-- WC4.5 Layer 1: the three staff-side commands, plus the staff Realtime topic check.
--
-- What has to hold: only the server may call any of them; the acting member's permission is re-checked
-- inside the command rather than trusted from the route; a retried staff send leaves exactly one
-- message; ending a session sets closed_at AND writes the sender_type = 'system' part in the same
-- transaction (the contract WC4.4's visitor half was built against); resolving a conflicting identity
-- moves the whole thread onto the chosen Client; and an organization's staff topic answers "no" to
-- everyone but its own permitted members.

begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

-- Only the server may ever call these commands directly -------------------------------------------

select function_privs_are(
  'public', 'post_website_chat_staff_message', array['uuid', 'uuid', 'uuid', 'text', 'text'],
  'service_role', array['EXECUTE'], 'only the service role can send a staff Website Chat message'
);
select function_privs_are(
  'public', 'end_website_chat_session', array['uuid', 'uuid', 'uuid'],
  'service_role', array['EXECUTE'], 'only the service role can end a Website Chat session'
);
select function_privs_are(
  'public', 'resolve_website_chat_session_identity', array['uuid', 'uuid', 'uuid', 'uuid'],
  'service_role', array['EXECUTE'], 'only the service role can resolve a Website Chat identity'
);
select is(
  has_function_privilege('anon',
    'public.post_website_chat_staff_message(uuid, uuid, uuid, text, text)', 'execute'),
  false,
  'anonymous callers cannot send a staff message'
);
select is(
  has_function_privilege('authenticated',
    'public.end_website_chat_session(uuid, uuid, uuid)', 'execute'),
  false,
  'signed-in members cannot end a session by calling the command themselves'
);

set local role postgres;

-- Fixture ------------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000045c1', 'Raad Staff Test', 'raad-staff-test', 'active'),
  ('90000000-0000-0000-0000-0000000045c9', 'Other Org', 'wc45-other-org', 'active');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select '90000000-0000-0000-0000-0000000045c1', id, now() - interval '2 minutes', 'provisioning',
  'Website Chat WC4.5 staff-command baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select public.apply_organization_limit_exception(
  '90000000-0000-0000-0000-0000000045c1', 'website_chat_accepted_conversations', 'numeric', 5,
  now() - interval '30 seconds', null, 'website-chat-wc45',
  'Room for the WC4.5 staff-command sessions.', 'owner@example.test'
);

insert into public.website_chat_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000045c1', now() - interval '1 minute', now() + interval '29 days');

insert into public.website_chat_widgets (id, organization_id, name, published, source_label)
values ('90000000-0000-0000-0000-0000000045d1', '90000000-0000-0000-0000-0000000045c1',
  'WC4.5 Staff Widget', true, 'Website Chat');

insert into public.website_chat_widget_origins (organization_id, widget_id, origin)
values ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045d1',
  'https://staff.example.com');

-- Four people: a full agent, someone who may see conversations but not send, someone who may send but
-- not manage identity, and a stranger who belongs to no organization at all.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  ('90000000-0000-0000-0000-0000000045e1', '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'wc45-agent@example.test', 'x', now(), now(), now()),
  ('90000000-0000-0000-0000-0000000045e2', '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'wc45-viewer@example.test', 'x', now(), now(), now()),
  ('90000000-0000-0000-0000-0000000045e3', '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'wc45-sender-only@example.test', 'x', now(), now(), now()),
  ('90000000-0000-0000-0000-0000000045e9', '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'wc45-stranger@example.test', 'x', now(), now(), now()),
  ('90000000-0000-0000-0000-0000000045e4', '00000000-0000-0000-0000-000000000000', 'authenticated',
    'authenticated', 'wc45-other-org-agent@example.test', 'x', now(), now(), now());

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', 'admin', 'active'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e2', 'field', 'active'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e3', 'field', 'active'),
  -- A fully-equipped agent at a different contractor. Without them, the tenant-isolation test below
  -- would be answered by the permission check and never reach the session lookup it means to test.
  ('90000000-0000-0000-0000-0000000045c9', '90000000-0000-0000-0000-0000000045e4', 'admin', 'active');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
    'conversations.send', 'grant'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
    'conversations.manage_assignment', 'grant'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
    'customers.view', 'grant'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
    'conversations.view_team', 'grant'),
  -- Can watch the inbox, may never speak in it.
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e2',
    'conversations.view_assigned', 'grant'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e2',
    'conversations.send', 'deny'),
  -- Can reply, may never decide who a conversation belongs to.
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e3',
    'conversations.send', 'grant'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e3',
    'conversations.manage_assignment', 'deny'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e3',
    'conversations.view_team', 'deny'),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e3',
    'conversations.view_assigned', 'deny'),
  ('90000000-0000-0000-0000-0000000045c9', '90000000-0000-0000-0000-0000000045e4',
    'conversations.send', 'grant');

-- Two clients holding one identifier each, which is what makes a conflicting session possible.
insert into public.clients (id, organization_id, display_name)
values
  ('90000000-0000-0000-0000-0000000045b1', '90000000-0000-0000-0000-0000000045c1', 'Phone Client'),
  ('90000000-0000-0000-0000-0000000045b2', '90000000-0000-0000-0000-0000000045c1', 'Email Client'),
  ('90000000-0000-0000-0000-0000000045b3', '90000000-0000-0000-0000-0000000045c1', 'Archived Client');
update public.clients set deleted_at = now() where id = '90000000-0000-0000-0000-0000000045b3';

insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
values
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045b1', 'phone',
    '+14155550501', true),
  ('90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045b2', 'email',
    'conflict@wc45.example', true);

-- Session A: an ordinary resolved session (email only, matching nobody, so a Lead Client is created).
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000045d1'),
  'https://staff.example.com',
  'wc45-session-token-hash-00000000000a',
  'wc45-idempotency-key-000a',
  'Alex Visitor',
  null,
  'alex@wc45.example',
  'Hello, are you available this week?',
  false,
  null,
  '{}'::jsonb
);

-- Session B: phone matches one Client, email matches a different one -> needs_review, client_id null.
select public.accept_website_chat_first_message(
  (select public_token from public.website_chat_widgets
   where id = '90000000-0000-0000-0000-0000000045d1'),
  'https://staff.example.com',
  'wc45-session-token-hash-00000000000b',
  'wc45-idempotency-key-000b',
  'Casey Conflict',
  '+14155550501',
  'conflict@wc45.example',
  'Which of me am I?',
  false,
  null,
  '{}'::jsonb
);

create temporary table wc45_ids on commit drop as
select
  (select id from public.website_chat_sessions
    where session_token_hash = 'wc45-session-token-hash-00000000000a') as session_a,
  (select id from public.website_chat_sessions
    where session_token_hash = 'wc45-session-token-hash-00000000000b') as session_b;

select is(
  (select s.match_status from public.website_chat_sessions s, wc45_ids where s.id = wc45_ids.session_b),
  'needs_review',
  'a phone and an email pointing at different Clients parks the session for review'
);

-- Staff reply -------------------------------------------------------------------------------------

select throws_ok(
  format($$select public.post_website_chat_staff_message(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e2', %L,
    'I should not be able to say this.', null)$$, (select session_a from wc45_ids)),
  '42501', null, 'a member without conversations.send cannot reply'
);
select throws_ok(
  format($$select public.post_website_chat_staff_message(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', %L,
    '   ', null)$$, (select session_a from wc45_ids)),
  '22023', null, 'an empty reply is refused rather than stored'
);
-- Tenant isolation proper: a real agent, with real permission, at a different contractor. The session
-- id is correct and still resolves to nothing, because the command is scoped by organization.
select throws_ok(
  format($$select public.post_website_chat_staff_message(
    '90000000-0000-0000-0000-0000000045c9', '90000000-0000-0000-0000-0000000045e4', %L,
    'Wrong organization.', null)$$, (select session_a from wc45_ids)),
  '23503', null, 'another contractor''s agent cannot reach this session even with the right id'
);

-- now() is the transaction's start time, so a bump from now() to now() would be unobservable here.
-- Ageing the session first is what makes the last_activity_at assertion below mean anything.
update public.website_chat_sessions
set last_activity_at = now() - interval '10 minutes'
where id = (select session_a from wc45_ids);

create temporary table wc45_first_reply on commit drop as
select public.post_website_chat_staff_message(
  '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
  (select session_a from wc45_ids), 'Yes, Thursday works.', 'wc45-staff-key-0001'
) as payload;

select is(
  (select payload ->> 'status' from wc45_first_reply), 'sent', 'the reply is accepted'
);
select is(
  (select payload -> 'replayed' from wc45_first_reply), 'false'::jsonb,
  'a first send is not reported as a replay'
);
select is(
  (select m.sender_type from public.website_chat_messages m, wc45_first_reply
   where m.id = (wc45_first_reply.payload ->> 'message_id')::uuid),
  'staff',
  'the reply is stored as a staff message'
);
select is(
  (select m.direction from public.website_chat_messages m, wc45_first_reply
   where m.id = (wc45_first_reply.payload ->> 'message_id')::uuid),
  'outbound',
  'a staff message is outbound'
);
select is(
  (select m.sender_user_id from public.website_chat_messages m, wc45_first_reply
   where m.id = (wc45_first_reply.payload ->> 'message_id')::uuid),
  '90000000-0000-0000-0000-0000000045e1'::uuid,
  'the reply records which member wrote it'
);
select is(
  (select m.client_id from public.website_chat_messages m, wc45_first_reply
   where m.id = (wc45_first_reply.payload ->> 'message_id')::uuid),
  (select s.client_id from public.website_chat_sessions s, wc45_ids where s.id = wc45_ids.session_a),
  'the reply carries the session''s client_id, so it lands on the contact timeline without a join'
);
select is(
  (select s.last_activity_at from public.website_chat_sessions s, wc45_ids
   where s.id = wc45_ids.session_a),
  now(),
  'replying bumps last_activity_at, keeping the session out of the inactivity sweep'
);

-- A retried send is the same send -------------------------------------------------------------------

create temporary table wc45_retried_reply on commit drop as
select public.post_website_chat_staff_message(
  '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
  (select session_a from wc45_ids), 'Yes, Thursday works.', 'wc45-staff-key-0001'
) as payload;

select is(
  (select payload -> 'replayed' from wc45_retried_reply), 'true'::jsonb,
  'the retry is reported as a replay'
);
select is(
  (select r.payload ->> 'message_id' from wc45_retried_reply r),
  (select f.payload ->> 'message_id' from wc45_first_reply f),
  'the retry returns the original message rather than a new one'
);
select is(
  (select count(*)::integer from public.website_chat_messages m, wc45_ids
   where m.session_id = wc45_ids.session_a and m.sender_type = 'staff'),
  1,
  'a retried staff send leaves exactly one message in the thread'
);

-- Ending a session ---------------------------------------------------------------------------------

select throws_ok(
  format($$select public.end_website_chat_session(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e2', %L)$$,
    (select session_a from wc45_ids)),
  '42501', null, 'a member without conversations.send cannot end a conversation'
);

create temporary table wc45_ended on commit drop as
select public.end_website_chat_session(
  '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
  (select session_a from wc45_ids)
) as payload;

select is(
  (select s.closed_reason from public.website_chat_sessions s, wc45_ids where s.id = wc45_ids.session_a),
  'staff_ended',
  'the session records that a person ended it'
);
select is(
  (select s.closed_by from public.website_chat_sessions s, wc45_ids where s.id = wc45_ids.session_a),
  '90000000-0000-0000-0000-0000000045e1'::uuid,
  'the session records which person ended it'
);
select is(
  (select s.closed_at is not null from public.website_chat_sessions s, wc45_ids
   where s.id = wc45_ids.session_a),
  true,
  'the session is closed'
);
-- The inherited WC4.4 contract, and the whole reason this is one command rather than an UPDATE.
select is(
  (select count(*)::integer from public.website_chat_messages m, wc45_ids
   where m.session_id = wc45_ids.session_a and m.sender_type = 'system'),
  1,
  'ending a session writes exactly one system part into the thread'
);
select is(
  (select m.body from public.website_chat_messages m, wc45_ids
   where m.session_id = wc45_ids.session_a and m.sender_type = 'system'),
  'Raad Staff Test ended this conversation.',
  'the system part names the contractor, because the widget renders that body verbatim'
);
select is(
  (select m.sender_user_id from public.website_chat_messages m, wc45_ids
   where m.session_id = wc45_ids.session_a and m.sender_type = 'system'),
  null::uuid,
  'the system part names no person -- the session''s closed_by does'
);
select throws_ok(
  format($$select public.end_website_chat_session(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', %L)$$,
    (select session_a from wc45_ids)),
  '55000', null, 'a session cannot be ended twice'
);
select throws_ok(
  format($$select public.post_website_chat_staff_message(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', %L,
    'One more thing.', null)$$, (select session_a from wc45_ids)),
  '55000', null, 'an ended conversation accepts no further staff message'
);
-- Ordering proof: the idempotency check runs before the closed check, so a retry whose session ended
-- in between still gets its original answer instead of an error about work it already completed.
select is(
  (public.post_website_chat_staff_message(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
    (select session_a from wc45_ids), 'Yes, Thursday works.', 'wc45-staff-key-0001'
  ) -> 'replayed'),
  'true'::jsonb,
  'a retry that arrives after the session ended still replays rather than failing'
);

-- Resolving a conflicting identity ------------------------------------------------------------------

select is(
  (select count(*)::integer from public.website_chat_messages m, wc45_ids
   where m.session_id = wc45_ids.session_b and m.client_id is null),
  1,
  'an unresolved session''s messages stay off both candidates'' timelines'
);
select throws_ok(
  format($$select public.resolve_website_chat_session_identity(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e3', %L,
    '90000000-0000-0000-0000-0000000045b1')$$, (select session_b from wc45_ids)),
  '42501', null, 'replying is not the same permission as deciding whose conversation this is'
);
select throws_ok(
  format($$select public.resolve_website_chat_session_identity(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', %L,
    '90000000-0000-0000-0000-0000000045b3')$$, (select session_b from wc45_ids)),
  '23503', null, 'an archived client cannot be chosen'
);
select throws_ok(
  format($$select public.resolve_website_chat_session_identity(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', %L,
    '90000000-0000-0000-0000-0000000045b1')$$, (select session_a from wc45_ids)),
  '55000', null, 'a session that never needed review cannot be resolved'
);

create temporary table wc45_resolved on commit drop as
select public.resolve_website_chat_session_identity(
  '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1',
  (select session_b from wc45_ids), '90000000-0000-0000-0000-0000000045b1'
) as payload;

select is(
  (select s.match_status from public.website_chat_sessions s, wc45_ids where s.id = wc45_ids.session_b),
  'resolved',
  'the conflict is settled'
);
select is(
  (select s.client_id from public.website_chat_sessions s, wc45_ids where s.id = wc45_ids.session_b),
  '90000000-0000-0000-0000-0000000045b1'::uuid,
  'the session belongs to the Client a person chose'
);
select is(
  (select payload -> 'messages_backfilled' from wc45_resolved), '1'::jsonb,
  'the command reports how much history it moved'
);
select is(
  (select count(*)::integer from public.website_chat_messages m, wc45_ids
   where m.session_id = wc45_ids.session_b
     and m.client_id = '90000000-0000-0000-0000-0000000045b1'),
  1,
  'the whole thread joins the chosen contact''s history'
);
select throws_ok(
  format($$select public.resolve_website_chat_session_identity(
    '90000000-0000-0000-0000-0000000045c1', '90000000-0000-0000-0000-0000000045e1', %L,
    '90000000-0000-0000-0000-0000000045b2')$$, (select session_b from wc45_ids)),
  '55000', null, 'a resolved session cannot be re-decided through this command'
);

-- The staff Realtime topic --------------------------------------------------------------------------

-- The payload on this topic is ids only, so the question the policy asks is deliberately the cheap one:
-- is this person a member here who may see conversations at all? What they actually see is decided by
-- the read that follows.
--
-- Exercised as the table owner rather than as `authenticated`, deliberately: no API role holds USAGE on
-- the `private` schema, and an RLS policy expression is evaluated with the owner's privileges, not the
-- querying role's. That is exactly how the shipped visitor policy already runs. Identity still comes
-- from auth.uid(), which reads the request claim below regardless of the current role.
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-0000000045e1', true);
select is(
  private.website_chat_staff_topic_permitted('wc-org:90000000-0000-0000-0000-0000000045c1'),
  true,
  'a member who can see conversations may listen on their organization''s staff topic'
);
select is(
  private.website_chat_staff_topic_permitted('wc-org:90000000-0000-0000-0000-0000000045c9'),
  false,
  'membership of one organization grants nothing on another organization''s topic'
);
select is(
  private.website_chat_staff_topic_permitted('wc-org:not-a-uuid'),
  false,
  'a malformed topic is a plain no, never an error thrown inside Realtime''s auth transaction'
);
select is(
  private.website_chat_staff_topic_permitted('wc:0000000000000000000000000000000000000000000000000000000000000000'),
  false,
  'a visitor''s session topic is not a staff topic'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-0000000045e3', true);
select is(
  private.website_chat_staff_topic_permitted('wc-org:90000000-0000-0000-0000-0000000045c1'),
  false,
  'a member who may send but may see no conversations is not given the live feed'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-0000000045e9', true);
select is(
  private.website_chat_staff_topic_permitted('wc-org:90000000-0000-0000-0000-0000000045c1'),
  false,
  'a stranger with an account but no membership is refused'
);

select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::integer from pg_catalog.pg_policies
   where schemaname = 'realtime' and tablename = 'messages'
     and policyname = 'website_chat_staff_channel_read'
     and cmd = 'SELECT' and 'authenticated' = any(roles)),
  1,
  'the staff topic is exposed to signed-in members as a read-only broadcast policy'
);

select * from finish();
rollback;
