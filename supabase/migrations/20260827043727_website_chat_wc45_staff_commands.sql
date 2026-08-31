-- Communications Website Chat, Part WC4.5, Layer 1: the three commands the staff side needs.
--
-- Everything shipped so far is the visitor's half. A staff member can watch a Website Chat session
-- arrive and can read it, but the database has no way for them to answer it, to end it, or to say
-- which Client a conflicting-identity session actually belongs to. Those are the three writes below,
-- plus the one publish change that lets an open /communications page hear a new message arrive.
--
-- Two contracts are inherited rather than invented here:
--
-- 1. Ending a session is an entry in the thread, not a side-channel event (WC4.4, following Intercom's
--    `part_type: close`). So `end_website_chat_session` sets `closed_at` AND inserts the
--    `sender_type = 'system'` part in ONE transaction. The visitor's widget was built and verified
--    against exactly that shape: it renders the system line and re-reads, because the read owns
--    `closed_at`. A second event type or a heartbeat would be a regression, not an improvement.
--
-- 2. Live delivery to staff pushes ids only. The payload names the session and the message; the page
--    invalidates its query and the existing permission-filtered read fetches the content. That is the
--    "invalidate, don't trust" pattern Intercom and Stream both use, and it is what keeps a
--    conversation an assigned-only viewer must not see from arriving in their browser anyway.
--
-- Authorization follows the shipped staff-command precedent (`resolve_inbound_message_review`,
-- `send_operational_email`): the permission is re-checked inside the command against the acting user,
-- not trusted from the route. View scoping (Team vs My Inbox) stays in the read path where it already
-- lives, exactly as it does for guarded email.

-- 1. Who ended it -------------------------------------------------------------------------------------

-- `closed_at`/`closed_reason` record that a session ended and why, but not by whom, and WC4.5's
-- approved closed state reads "This conversation ended - who - when". The system part cannot carry it:
-- the website_chat_messages_sender_user_check constraint deliberately allows sender_user_id only on a
-- 'staff' row, so a 'system' row can never name a person.
alter table public.website_chat_sessions
  add column closed_by uuid references auth.users(id) on delete set null;

comment on column public.website_chat_sessions.closed_by is
  'The staff member who ended this session, when a person did. Null for inactivity_timeout, '
  'widget_disabled, and visitor_ended.';

-- 2. Staff reply --------------------------------------------------------------------------------------

create or replace function public.post_website_chat_staff_message(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_session_id uuid,
  message_body text,
  new_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
set statement_timeout = '5000'
as $$
declare
  target_session public.website_chat_sessions;
  clean_body text;
  clean_idempotency_key text;
  existing_message_id uuid;
  new_message_id uuid;
begin
  if not private.member_has_permission(
    target_organization_id, target_actor_user_id, 'conversations.send'
  ) then
    raise exception 'You do not have permission to send messages.'
      using errcode = 'insufficient_privilege';
  end if;

  clean_body := nullif(btrim(coalesce(message_body, '')), '');
  if clean_body is null then
    raise exception 'Write a message first.' using errcode = 'invalid_parameter_value';
  end if;
  clean_idempotency_key := nullif(btrim(coalesce(new_idempotency_key, '')), '');

  -- Locked so a reply and an end arriving together cannot interleave into a message written after the
  -- close, which the visitor would never be told about.
  select * into target_session
  from public.website_chat_sessions s
  where s.organization_id = target_organization_id and s.id = target_session_id
  for update;
  if not found then
    raise exception 'That conversation is not available.' using errcode = 'foreign_key_violation';
  end if;

  -- A retried send is the same send, and it is checked before the closed test so a retry whose session
  -- ended in between still replays its original message instead of failing on work already done.
  if clean_idempotency_key is not null then
    select m.id into existing_message_id
    from public.website_chat_messages m
    where m.session_id = target_session.id and m.idempotency_key = clean_idempotency_key;
    if found then
      return jsonb_build_object(
        'status', 'sent', 'replayed', true,
        'session_id', target_session.id, 'message_id', existing_message_id
      );
    end if;
  end if;

  if target_session.closed_at is not null then
    raise exception 'This conversation has ended.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  insert into public.website_chat_messages (
    organization_id, session_id, client_id, direction, sender_type, sender_user_id, body,
    idempotency_key
  ) values (
    target_session.organization_id, target_session.id, target_session.client_id,
    'outbound', 'staff', target_actor_user_id, clean_body, clean_idempotency_key
  ) returning id into new_message_id;

  update public.website_chat_sessions
  set last_activity_at = now()
  where id = target_session.id;

  return jsonb_build_object(
    'status', 'sent', 'replayed', false,
    'session_id', target_session.id, 'message_id', new_message_id
  );
end;
$$;

comment on function public.post_website_chat_staff_message(uuid, uuid, uuid, text, text) is
  'A staff reply into a live Website Chat session. Re-checks conversations.send, refuses a closed '
  'session, and replays a retried send rather than duplicating it. The existing after-insert trigger '
  'delivers it to the visitor.';

revoke all on function public.post_website_chat_staff_message(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.post_website_chat_staff_message(uuid, uuid, uuid, text, text)
  to service_role;

-- 3. Ending the session -------------------------------------------------------------------------------

-- The whole point of this command is that both halves happen together. A `closed_at` without the
-- system part leaves the visitor typing into a dead thread (the exact defect found and fixed during
-- WC4.4's live verification); a system part without `closed_at` leaves a thread that says it ended and
-- still accepts messages.
create or replace function public.end_website_chat_session(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
set statement_timeout = '5000'
as $$
declare
  target_session public.website_chat_sessions;
  organization_name text;
  closed_moment timestamptz := now();
begin
  if not private.member_has_permission(
    target_organization_id, target_actor_user_id, 'conversations.send'
  ) then
    raise exception 'You do not have permission to manage this conversation.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into target_session
  from public.website_chat_sessions s
  where s.organization_id = target_organization_id and s.id = target_session_id
  for update;
  if not found then
    raise exception 'That conversation is not available.' using errcode = 'foreign_key_violation';
  end if;

  if target_session.closed_at is not null then
    raise exception 'This conversation has already ended.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select o.name into organization_name
  from public.organizations o
  where o.id = target_organization_id;

  update public.website_chat_sessions
  set closed_at = closed_moment,
      closed_reason = 'staff_ended',
      closed_by = target_actor_user_id,
      last_activity_at = closed_moment
  where id = target_session.id;

  -- Narration, not a party in the conversation: the widget already renders a 'system' row as a note,
  -- and the unfiltered publish trigger already carries it. The body is stored verbatim, because that
  -- is exactly what the widget shows.
  insert into public.website_chat_messages (
    organization_id, session_id, client_id, direction, sender_type, body
  ) values (
    target_session.organization_id, target_session.id, target_session.client_id,
    'outbound', 'system', organization_name || ' ended this conversation.'
  );

  return jsonb_build_object(
    'status', 'closed', 'session_id', target_session.id, 'closed_at', closed_moment
  );
end;
$$;

comment on function public.end_website_chat_session(uuid, uuid, uuid) is
  'Ends a Website Chat session: closed_at, closed_reason, closed_by AND the sender_type = ''system'' '
  'part in one transaction. WC4.4''s inherited contract -- the visitor learns a session ended only '
  'from that part arriving in the thread.';

revoke all on function public.end_website_chat_session(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.end_website_chat_session(uuid, uuid, uuid) to service_role;

-- 4. Resolving a needs-review identity ----------------------------------------------------------------

-- A session lands at match_status = 'needs_review' when the visitor's phone matched one Client and
-- their email matched a different one. UCRM never guesses; a person chooses. There is deliberately no
-- dismiss path (approved 2026-08-27): unlike a guarded inbound email, the session already holds real
-- messages and has already consumed an allowance unit, so it always belongs to somebody.
create or replace function public.resolve_website_chat_session_identity(
  target_organization_id uuid,
  target_actor_user_id uuid,
  target_session_id uuid,
  target_client_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
set statement_timeout = '5000'
as $$
declare
  target_session public.website_chat_sessions;
  chosen_client_id uuid;
  backfilled_count integer;
begin
  -- Choosing which contact a conversation belongs to is the same administrative act as linking a
  -- guarded inbound sender, and it reads and writes contact identity, so it carries the same pair of
  -- permissions resolve_inbound_message_review requires.
  if not private.member_has_permission(
    target_organization_id, target_actor_user_id, 'conversations.manage_assignment'
  ) then
    raise exception 'You do not have permission to manage conversations.'
      using errcode = 'insufficient_privilege';
  end if;

  if not private.member_has_permission(
    target_organization_id, target_actor_user_id, 'customers.view'
  ) then
    raise exception 'You do not have permission to manage conversations.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into target_session
  from public.website_chat_sessions s
  where s.organization_id = target_organization_id and s.id = target_session_id
  for update;
  if not found then
    raise exception 'That conversation is not available.' using errcode = 'foreign_key_violation';
  end if;

  if target_session.match_status <> 'needs_review' then
    raise exception 'This conversation no longer needs review.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select c.id into chosen_client_id
  from public.clients c
  where c.organization_id = target_organization_id
    and c.id = target_client_id
    and c.deleted_at is null
  for share of c;

  if chosen_client_id is null then
    raise exception 'That client is not available.' using errcode = 'foreign_key_violation';
  end if;

  update public.website_chat_sessions
  set match_status = 'resolved',
      client_id = chosen_client_id
  where id = target_session.id;

  -- Every message in a needs_review session carries client_id = null by design (WC4.1), which is what
  -- keeps it out of both candidates' timelines while the conflict stands. Resolving is the moment the
  -- whole thread joins one contact's history, so the denormalized column is backfilled here rather
  -- than left for the read to join around.
  update public.website_chat_messages
  set client_id = chosen_client_id
  where session_id = target_session.id and client_id is null;

  get diagnostics backfilled_count = row_count;

  return jsonb_build_object(
    'status', 'resolved',
    'session_id', target_session.id,
    'client_id', chosen_client_id,
    'messages_backfilled', backfilled_count
  );
end;
$$;

comment on function public.resolve_website_chat_session_identity(uuid, uuid, uuid, uuid) is
  'Assigns a conflicting-identity Website Chat session to the Client a person chose, and backfills '
  'client_id onto that session''s messages so the whole thread joins that contact''s history.';

revoke all on function public.resolve_website_chat_session_identity(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_website_chat_session_identity(uuid, uuid, uuid, uuid)
  to service_role;

-- 5. Live delivery to staff ---------------------------------------------------------------------------

-- The visitor's half of this trigger is unchanged and stays first: it is the path that was measured at
-- 0.31 ms and live-verified in WC4.4, and nothing below is allowed to make a message insert fail.
--
-- The staff half is a second, deliberately different publish. The visitor's topic is a bearer secret
-- minted per session, because a visitor has no account to authorize. Staff do have accounts, so their
-- topic needs no secret at all -- it is simply the organization id, and the RLS policy below asks the
-- ordinary membership question about the person joining it.
--
-- The payload carries ids only. A staff socket is one per member, not one per conversation, so a
-- content payload would hand every listening member every message in the organization and route around
-- the assigned-only view scoping the read path enforces. Ids are safe to over-deliver: the page reacts
-- by re-reading, and the read is what decides whether that member may see anything at all.
create or replace function private.website_chat_staff_topic_permitted(topic text)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog, public, private
as $$
declare
  claimed_organization_id uuid;
begin
  -- Validated by shape before casting: an invalid uuid must be a plain "no", never an error thrown
  -- inside Realtime's authorization transaction.
  if topic !~ '^wc-org:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;

  claimed_organization_id := substring(topic from 8)::uuid;

  return private.is_organization_member(claimed_organization_id)
    and (
      private.has_permission(claimed_organization_id, 'conversations.view_team')
      or private.has_permission(claimed_organization_id, 'conversations.view_assigned')
    );
end;
$$;

comment on function private.website_chat_staff_topic_permitted(text) is
  'May the signed-in caller listen on this organization''s Website Chat staff topic? Membership plus '
  'either conversations view permission; the payload is ids only, so the read still decides what they '
  'actually see.';

revoke all on function private.website_chat_staff_topic_permitted(text)
  from public, anon, authenticated, service_role;
grant execute on function private.website_chat_staff_topic_permitted(text) to authenticated;

-- Read only and Broadcast only, matching the visitor policy: staff listen, and everything they say
-- goes through post_website_chat_staff_message where the permission is re-checked.
create policy website_chat_staff_channel_read
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and private.website_chat_staff_topic_permitted(realtime.messages.topic)
  );

create or replace function public.publish_website_chat_message_to_visitor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  live_topic text;
begin
  select g.channel_topic into live_topic
  from public.website_chat_realtime_grants g
  where g.session_id = new.session_id
    and g.expires_at > now();

  -- Nobody is listening: the visitor has no tab open, or their grant lapsed. The message is already
  -- durable, and session restore or the polling fallback will deliver it. Publishing is best effort by
  -- design; delivery is the database's.
  if live_topic is not null then
    begin
      perform realtime.send(
        jsonb_build_object(
          'id', new.id,
          'direction', new.direction,
          'sender_type', new.sender_type,
          'body', new.body,
          'created_at', new.created_at
        ),
        'website_chat_message',
        live_topic,
        true
      );
    exception
      when others then
        -- The first message of a session is where an allowance unit is claimed. A Realtime outage must
        -- never roll that back and hand the conversation away free, so a failed publish is swallowed
        -- and the poll picks the message up.
        null;
    end;
  end if;

  -- Ids only, and no body: see the note above this function. Unconditional, because unlike the
  -- visitor's grant there is no per-session state to look up -- an organization with nobody watching
  -- simply has no subscriber on the topic.
  begin
    perform realtime.send(
      jsonb_build_object(
        'session_id', new.session_id,
        'message_id', new.id,
        'client_id', new.client_id
      ),
      'website_chat_activity',
      'wc-org:' || new.organization_id::text,
      true
    );
  exception
    when others then
      null;
  end;

  return null;
end;
$$;

comment on function public.publish_website_chat_message_to_visitor() is
  'Broadcasts a new Website Chat message twice: the full payload to that session''s own private '
  'visitor topic when it has a live grant, and ids only to the organization''s staff topic so an open '
  'Conversations page re-reads. Best effort on both: a publish failure never fails the message.';

revoke all on function public.publish_website_chat_message_to_visitor()
  from public, anon, authenticated;
