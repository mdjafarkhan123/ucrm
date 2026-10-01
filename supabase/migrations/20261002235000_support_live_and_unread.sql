-- Client onboarding D2: the Uplift Support Messenger goes live and shows what is unread.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7. Industry reference: Intercom /
-- Help Scout / Zendesk — a reply is pushed over a live connection the moment it is written, each person has a
-- "read up to here" mark per conversation, and a badge counts what arrived after it.
--
-- 1. support_thread_reads: each member's "read up to here" mark on a thread. A row per person rather than a
--    column on the thread, so D3's owners and added teammates each keep their own.
-- 2. support_threads.uplift_last_read_at: Uplift's single mark. Uplift answers as one team inbox.
-- 3. Sending a message counts as reading everything before it, for whoever sent it.
-- 4. Live delivery uses Supabase Realtime Broadcast from the database, the pattern Website Chat already uses
--    here: the database sends a small ids-only "something changed" ping on a private channel, and the
--    browser re-reads through the normal permission-checked API. A ping never carries a message body.
--    - A member listens on `support-user:<their user id>`; the channel rule lets only that person join.
--    - The /jafar login is not a Supabase sign-in, so each live owner session is given a secret, short-lived
--      channel name (`support-owner:<64 hex>`) by the server, exactly like Website Chat visitor grants. The
--      grant dies with the owner session (logout, rotation, or expiry).

-- 1. Member read marks -------------------------------------------------------------------------------------

create table public.support_thread_reads (
  thread_id uuid not null references public.support_threads (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Everything in the thread created at or before this time has been seen by this person.
  last_read_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

comment on table public.support_thread_reads is
  'Each team member''s "read up to here" mark on an Uplift Support thread. Written only by public.mark_support_thread_read and by sending a message.';

create index support_thread_reads_user_id_idx on public.support_thread_reads (user_id);

create trigger support_thread_reads_set_updated_at
  before update on public.support_thread_reads
  for each row execute function public.set_updated_at();

-- 2. Uplift's read mark ------------------------------------------------------------------------------------

alter table public.support_threads add column uplift_last_read_at timestamptz;

comment on column public.support_threads.uplift_last_read_at is
  'Everything in the thread created at or before this time has been seen by Uplift. Null means never opened. The thread is unread for Uplift when the member wrote last, after this mark.';

-- Who may see a thread. The thread's row level security says the same; D3 widens both together.
create function private.can_view_support_thread(target_thread_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.support_threads as thread
    where thread.id = target_thread_id
      and thread.started_by_user_id = (select auth.uid())
      and private.is_organization_member(thread.organization_id)
  );
$$;

revoke all on function private.can_view_support_thread(uuid) from public;
grant execute on function private.can_view_support_thread(uuid) to authenticated;

-- 3. Sending counts as reading -----------------------------------------------------------------------------

create or replace function private.touch_support_thread_on_message()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  update public.support_threads
  set last_message_at = new.created_at,
      last_message_preview = left(regexp_replace(new.body, '\s+', ' ', 'g'), 160),
      last_message_sender_kind = new.sender_kind,
      uplift_last_read_at = case
        when new.sender_kind = 'uplift'
          then greatest(coalesce(uplift_last_read_at, new.created_at), new.created_at)
        else uplift_last_read_at
      end
  where id = new.thread_id;

  if new.sender_kind = 'member' and new.sender_user_id is not null then
    insert into public.support_thread_reads (thread_id, user_id, last_read_at)
    values (new.thread_id, new.sender_user_id, new.created_at)
    on conflict (thread_id, user_id) do update
      set last_read_at = greatest(public.support_thread_reads.last_read_at, excluded.last_read_at);
  end if;

  return null;
end;
$$;

-- 4. Reading -----------------------------------------------------------------------------------------------

-- A member has seen their thread up to `read_through` (the newest message their screen showed). A mark never
-- moves backwards and never runs ahead of the present, so a stale or forged time cannot hide a later reply.
create function public.mark_support_thread_read(target_thread_id uuid, read_through timestamptz)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  mark timestamptz := least(read_through, now());
begin
  if actor_id is null or read_through is null or not private.can_view_support_thread(target_thread_id) then
    raise exception 'That conversation is not yours to mark as read.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.support_thread_reads (thread_id, user_id, last_read_at)
  values (target_thread_id, actor_id, mark)
  on conflict (thread_id, user_id) do update
    set last_read_at = excluded.last_read_at
    where public.support_thread_reads.last_read_at < excluded.last_read_at;
end;
$$;

-- Uplift has seen a thread up to `read_through`. Service role only: the route has proved the owner session.
create function public.mark_support_thread_read_by_uplift(target_thread_id uuid, read_through timestamptz)
returns void
language sql
set search_path to 'pg_catalog', 'public'
as $$
  update public.support_threads
  set uplift_last_read_at = least(read_through, now())
  where id = target_thread_id
    and read_through is not null
    and (uplift_last_read_at is null or uplift_last_read_at < least(read_through, now()));
$$;

-- How many messages in the signed-in member's own thread arrived after their mark, written by someone else.
-- Capped at 100: the badge shows "99+" beyond that, and the count stays a short bounded index range.
create function public.support_unread_count(target_organization_id uuid)
returns integer
language sql
stable
security invoker
set search_path to 'pg_catalog', 'public'
as $$
  select count(*)::integer
  from (
    select 1
    from public.support_threads as thread
    join public.support_messages as message on message.thread_id = thread.id
    left join public.support_thread_reads as read_mark
      on read_mark.thread_id = thread.id and read_mark.user_id = (select auth.uid())
    where thread.organization_id = target_organization_id
      and thread.started_by_user_id = (select auth.uid())
      and message.created_at > coalesce(read_mark.last_read_at, '-infinity'::timestamptz)
      and message.sender_user_id is distinct from (select auth.uid())
    limit 100
  ) as unread;
$$;

-- 5. Owner live grants -------------------------------------------------------------------------------------

create table public.platform_support_realtime_grants (
  owner_session_id uuid primary key references public.platform_owner_sessions (id) on delete cascade,
  channel_topic text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint platform_support_realtime_grants_topic_shape_check check (
    channel_topic ~ '^support-owner:[0-9a-f]{64}$'
  )
);

comment on table public.platform_support_realtime_grants is
  'The secret private Realtime channel one live /jafar session listens on for Support Inbox activity. Issued by public.issue_support_realtime_grant; valid only while its owner session is.';

create index platform_support_realtime_grants_expires_at_idx
  on public.platform_support_realtime_grants (expires_at);

-- The current owner session's channel, issued once and reused until the session ends. Service role only.
create function public.issue_support_realtime_grant(target_owner_session_id uuid)
returns text
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  session_expires_at timestamptz;
  topic text;
begin
  select session.expires_at into session_expires_at
  from public.platform_owner_sessions as session
  where session.id = target_owner_session_id
    and session.revoked_at is null
    and session.expires_at > now();

  if session_expires_at is null then
    raise exception 'That owner session is no longer active.' using errcode = 'insufficient_privilege';
  end if;

  delete from public.platform_support_realtime_grants where expires_at <= now();

  insert into public.platform_support_realtime_grants (owner_session_id, channel_topic, expires_at)
  values (
    target_owner_session_id,
    'support-owner:' || encode(extensions.gen_random_bytes(32), 'hex'),
    session_expires_at
  )
  on conflict (owner_session_id) do update
    set expires_at = excluded.expires_at
  returning channel_topic into topic;

  return topic;
end;
$$;

-- The live owner channels a ping should reach. Joined to the session registry, so logout stops them at once.
create function private.live_support_owner_topics()
returns setof text
language sql
stable
security definer
set search_path to ''
as $$
  select grant_row.channel_topic
  from public.platform_support_realtime_grants as grant_row
  join public.platform_owner_sessions as session on session.id = grant_row.owner_session_id
  where grant_row.expires_at > now()
    and session.revoked_at is null
    and session.expires_at > now();
$$;

create function private.support_owner_topic_granted(topic text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (select 1 from private.live_support_owner_topics() as live where live = topic);
$$;

-- 6. Live pings --------------------------------------------------------------------------------------------

-- Ids only. A failed ping must never undo the message or read mark that caused it: the browser's 30-second
-- fallback check and its catch-up on reconnect cover a missed one.
create function private.send_support_ping(topic text, event_name text, payload jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform realtime.send(payload, event_name, topic, true);
exception
  when others then
    null;
end;
$$;

create function private.publish_support_message_activity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  member_id uuid;
  owner_topic text;
  payload jsonb := jsonb_build_object(
    'thread_id', new.thread_id, 'message_id', new.id, 'sender_kind', new.sender_kind
  );
begin
  select thread.started_by_user_id into member_id
  from public.support_threads as thread
  where thread.id = new.thread_id;

  if member_id is not null then
    perform private.send_support_ping('support-user:' || member_id::text, 'support_activity', payload);
  end if;

  for owner_topic in select * from private.live_support_owner_topics() loop
    perform private.send_support_ping(owner_topic, 'support_activity', payload);
  end loop;

  return null;
end;
$$;

create trigger support_messages_publish_activity
  after insert on public.support_messages
  for each row execute function private.publish_support_message_activity();

-- A read mark moving clears the badge in the person's other open tabs too.
create function private.publish_support_member_read()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform private.send_support_ping(
    'support-user:' || new.user_id::text,
    'support_read',
    jsonb_build_object('thread_id', new.thread_id)
  );
  return null;
end;
$$;

create trigger support_thread_reads_publish_read
  after insert or update of last_read_at on public.support_thread_reads
  for each row execute function private.publish_support_member_read();

create function private.publish_support_uplift_read()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  owner_topic text;
begin
  for owner_topic in select * from private.live_support_owner_topics() loop
    perform private.send_support_ping(
      owner_topic, 'support_read', jsonb_build_object('thread_id', new.id)
    );
  end loop;
  return null;
end;
$$;

-- Only a direct read mark. A reply also moves the mark, but its message already pinged.
create trigger support_threads_publish_uplift_read
  after update of uplift_last_read_at on public.support_threads
  for each row
  when (
    old.uplift_last_read_at is distinct from new.uplift_last_read_at
    and old.last_message_at = new.last_message_at
  )
  execute function private.publish_support_uplift_read();

-- Access ---------------------------------------------------------------------------------------------------

alter table public.support_thread_reads enable row level security;
alter table public.platform_support_realtime_grants enable row level security;

revoke all on table public.support_thread_reads from public, anon, authenticated;
revoke all on table public.platform_support_realtime_grants from public, anon, authenticated;

grant select on table public.support_thread_reads to authenticated;
grant all on table public.support_thread_reads to service_role;
grant all on table public.platform_support_realtime_grants to service_role;

create policy "members can view their own support read marks"
  on public.support_thread_reads
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on function private.live_support_owner_topics() from public;
revoke all on function private.support_owner_topic_granted(text) from public;
revoke all on function private.send_support_ping(text, text, jsonb) from public;
revoke all on function private.publish_support_message_activity() from public;
revoke all on function private.publish_support_member_read() from public;
revoke all on function private.publish_support_uplift_read() from public;
grant execute on function private.support_owner_topic_granted(text) to anon, authenticated;

revoke all on function public.mark_support_thread_read(uuid, timestamptz) from public, anon;
revoke all on function public.mark_support_thread_read_by_uplift(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.support_unread_count(uuid) from public, anon;
revoke all on function public.issue_support_realtime_grant(uuid) from public, anon, authenticated;

grant execute on function public.mark_support_thread_read(uuid, timestamptz) to authenticated, service_role;
grant execute on function public.mark_support_thread_read_by_uplift(uuid, timestamptz) to service_role;
grant execute on function public.support_unread_count(uuid) to authenticated, service_role;
grant execute on function public.issue_support_realtime_grant(uuid) to service_role;

-- Channel rules. A member may join only their own channel. A /jafar browser may join a live owner channel
-- whether or not the same browser also holds a contractor sign-in, so that rule covers both roles.
drop policy if exists support_member_channel_read on realtime.messages;
create policy support_member_channel_read
  on realtime.messages
  for select
  to authenticated
  using (extension = 'broadcast' and topic = 'support-user:' || (select auth.uid())::text);

drop policy if exists support_owner_channel_read on realtime.messages;
create policy support_owner_channel_read
  on realtime.messages
  for select
  to anon, authenticated
  using (
    extension = 'broadcast'
    and topic like 'support-owner:%'
    and private.support_owner_topic_granted(topic)
  );
