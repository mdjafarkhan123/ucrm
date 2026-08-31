-- WC4.4 Stage B: the live transport a visitor's chat panel actually runs on.
--
-- Everything before this slice answers a question the visitor asked. This is the first path where the
-- *contractor* speaks first and the visitor's browser has to hear it without asking -- a staff reply
-- landing in a panel that is sitting open. WC0.2 approved Supabase Realtime Broadcast on a private
-- per-session channel for exactly this, with the ~4s poll kept as the degraded fallback.
--
-- The authorization question this slice had to answer, and the answer, measured on this project:
--
--   An anonymous visitor holds no account and never signs in. Supabase authorizes a private channel by
--   running RLS on `realtime.messages` at join time, against whatever credential the socket carries --
--   for this visitor, nothing but the publishable key, which identifies the project and not a person.
--   So the credential cannot be *who they are*; it has to be *what they hold*. It is the channel name
--   itself: a short-lived, high-entropy topic minted server-side per session (WC0.2's third token, the
--   "realtime channel token"), recorded here with an expiry, and checked by the policy below on every
--   join. A visitor who was never granted a topic cannot join it, and neither can one whose grant has
--   expired -- both verified against the live project before this migration was written.
--
-- Deliberately NOT here:
--   * No insert policy. A visitor may *listen* on their channel and may never *broadcast* on it --
--     everything they say goes through `post_website_chat_message`, where rate limits, the origin
--     allowlist and the session's closed state are enforced. A channel the visitor could write to
--     would route around all three.
--   * No `postgres_changes` subscription anywhere. That would put a row-filtered firehose of one
--     organization's messages behind a public credential; Broadcast sends one payload to one topic.
--   * No `sender_user_id` in any payload. The person reading it is a stranger on a third party's
--     website, exactly as in the Stage A read command.

-- 1. The grant ---------------------------------------------------------------------------------------

-- One row per session, not one per tab or per connect. Two tabs of the same conversation share the one
-- live topic, and a reconnect re-mints rather than accumulating grants, so this table stays the same
-- size as the set of recently-active conversations rather than growing with socket churn.
--
-- It is a separate table from `website_chat_sessions` on purpose: minting happens on every connect and
-- reconnect, and folding it into the session row would rewrite a wide, heavily-indexed hot row (and
-- its index entries) every time a laptop wakes from sleep.
create table public.website_chat_realtime_grants (
  session_id uuid primary key references public.website_chat_sessions(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- The topic *is* the bearer secret, so it is stored as the server minted it: unlike a session token,
  -- a hash is useless here because the publisher (the trigger below) has to name the topic in clear to
  -- send to it. The mitigation is lifetime, not obscurity at rest -- a grant is minutes old, and a
  -- stale table dump yields nothing but expired topics.
  channel_topic text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint website_chat_realtime_grants_topic_shape_check
    check (channel_topic ~ '^wc:[0-9a-f]{64}$')
);

comment on table public.website_chat_realtime_grants is
  'The short-lived private Realtime channel one Website Chat session is authorized to listen on. The '
  'topic is a server-minted bearer secret; the RLS policy on realtime.messages is the only thing that '
  'reads it at join time.';

-- The only lookup that is not by primary key: the policy resolving a joining topic. It is covered by
-- the unique constraint's index, so no second index is created for it.
--
-- This one exists for the opposite question -- "which grants are dead?" -- which is asked by nothing
-- today (a dead grant is simply overwritten by the next mint, and a deleted session takes its grant
-- with it) but is what any later sweep would need, and costs one small index on a table bounded by
-- active conversations.
create index website_chat_realtime_grants_expires_at_idx
  on public.website_chat_realtime_grants (expires_at);

create index website_chat_realtime_grants_organization_idx
  on public.website_chat_realtime_grants (organization_id);

alter table public.website_chat_realtime_grants enable row level security;

revoke all on public.website_chat_realtime_grants from anon, authenticated;
grant select, insert, update on public.website_chat_realtime_grants to service_role;

-- 2. The join check ----------------------------------------------------------------------------------

-- Runs as `anon`, inside Realtime's own authorization transaction, once per channel subscription (the
-- result is cached for the life of that connection). It is `security definer` so the visitor's role
-- never needs -- and never gets -- a select privilege on the grants table itself: the function answers
-- one boolean about one topic and exposes nothing else.
--
-- `stable`, single indexed equality, no join: this runs on the connect path of every open chat panel,
-- and Supabase's own guidance is that a slow policy here shows up as slow *connections*.
create or replace function private.website_chat_realtime_topic_granted(topic text)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.website_chat_realtime_grants g
    where g.channel_topic = $1
      and g.expires_at > now()
  );
$$;

comment on function private.website_chat_realtime_topic_granted(text) is
  'Is this Realtime topic a live Website Chat grant? The whole authorization decision for an anonymous '
  'visitor joining a private channel.';

revoke all on function private.website_chat_realtime_topic_granted(text)
  from public, anon, authenticated, service_role;
grant execute on function private.website_chat_realtime_topic_granted(text) to anon;

-- Read only, and only Broadcast. `extension` is Realtime's own record of the message type, so pinning
-- it here means this grant can never be stretched into Presence or Postgres Changes access by a client
-- that simply asks for a different feature on the same topic.
create policy website_chat_visitor_channel_read
  on realtime.messages
  for select
  to anon
  using (
    realtime.messages.extension = 'broadcast'
    and private.website_chat_realtime_topic_granted(realtime.messages.topic)
  );

-- 3. Minting -----------------------------------------------------------------------------------------

-- The topic is minted by the server, never by the caller's browser and never here: the same reasoning
-- that made the session token an HMAC of SESSION_SECRET applies unchanged -- a browser-chosen channel
-- name would let the browser decide how much entropy its own privacy gets. This command receives an
-- already-minted topic and decides only whether this session may have one.
create function public.mint_website_chat_realtime_grant(
  session_token_hash text,
  requesting_origin text,
  proposed_topic text,
  ttl_seconds integer default 1800
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
set statement_timeout = '5000'
as $$
declare
  target_session public.website_chat_sessions;
  widget record;
  normalized_origin text := lower(btrim(coalesce(requesting_origin, '')));
  origin_allowed boolean;
  -- Clamped here, not only in the route. Thirty minutes is the ceiling because a grant is the whole
  -- authorization: a topic that leaks is worth exactly as long as it lives.
  effective_ttl integer := least(greatest(coalesce(ttl_seconds, 1800), 60), 1800);
  rate_check record;
  existing public.website_chat_realtime_grants;
  granted_topic text;
  granted_expiry timestamptz;
begin
  if normalized_origin = ''
     or nullif(btrim(coalesce(session_token_hash, '')), '') is null
     or coalesce(proposed_topic, '') !~ '^wc:[0-9a-f]{64}$' then
    return jsonb_build_object('status', 'refused');
  end if;

  select * into target_session
  from public.website_chat_sessions s
  where s.session_token_hash = btrim(mint_website_chat_realtime_grant.session_token_hash);
  if not found then
    return jsonb_build_object('status', 'refused');
  end if;

  select w.id, w.organization_id into widget
  from public.website_chat_widgets w
  where w.id = target_session.widget_id;
  if not found then
    return jsonb_build_object('status', 'refused');
  end if;

  select exists (
    select 1 from public.website_chat_widget_origins o
    where o.widget_id = widget.id and o.origin = normalized_origin
  ) into origin_allowed;
  if not origin_allowed then
    return jsonb_build_object('status', 'refused');
  end if;

  -- A closed session still gets a channel, for the same reason it still reads its history: the panel
  -- in front of the visitor stays live, and the close itself is one of the events worth hearing.

  -- Reconnect storms are the shape of abuse this path has: a flapping network or a scripted client can
  -- ask for a grant in a loop. Twenty a minute leaves room for several tabs plus a genuine reconnect
  -- burst, and bounds the rest.
  select * into rate_check
  from public.check_rate_limit('website_chat:realtime_mint:' || target_session.id::text, 60, 20);
  if not rate_check.allowed then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  -- Reuse before rotation. Rotating a topic that another tab is currently subscribed to would silently
  -- deafen that tab until its own next mint, so a grant with real life left in it is handed back as-is
  -- and only a nearly-dead one is replaced.
  select * into existing
  from public.website_chat_realtime_grants g
  where g.session_id = target_session.id;

  if found and existing.expires_at > now() + interval '5 minutes' then
    granted_topic := existing.channel_topic;
    granted_expiry := existing.expires_at;
  else
    insert into public.website_chat_realtime_grants as g
      (session_id, organization_id, channel_topic, expires_at)
    values (
      target_session.id,
      target_session.organization_id,
      proposed_topic,
      now() + make_interval(secs => effective_ttl)
    )
    on conflict (session_id) do update
      set channel_topic = excluded.channel_topic,
          expires_at = excluded.expires_at,
          updated_at = now()
    returning g.channel_topic, g.expires_at into granted_topic, granted_expiry;
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'session_id', target_session.id,
    'channel_topic', granted_topic,
    'expires_at', granted_expiry
  );
end;
$$;

comment on function public.mint_website_chat_realtime_grant(text, text, text, integer) is
  'Authorizes one Website Chat session onto one short-lived private Realtime topic. Same authorization '
  'pair as every other public command -- the session secret plus an allowlisted origin -- and the same '
  'silent refusal shape.';

revoke all on function public.mint_website_chat_realtime_grant(text, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.mint_website_chat_realtime_grant(text, text, text, integer)
  to service_role;

-- 4. Publishing --------------------------------------------------------------------------------------

-- Fires inside the inserting transaction, which is what makes "publish after commit" true rather than
-- hopeful: `realtime.send` writes into `realtime.messages`, and Realtime picks it up from the WAL, so a
-- transaction that rolls back never publishes a message that does not exist. A server-side publish
-- after the API call returned could not offer that.
--
-- Both directions are published, not just staff replies. A visitor with the same conversation open in
-- two tabs is an ordinary case, and the widget dedupes by message id anyway.
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
  if live_topic is null then
    return null;
  end if;

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
      -- never roll that back and hand the conversation away free, so a failed publish is swallowed and
      -- the poll picks the message up.
      null;
  end;

  return null;
end;
$$;

comment on function public.publish_website_chat_message_to_visitor() is
  'Broadcasts a new Website Chat message to that session''s own private topic, if it currently has a '
  'live grant. Best effort: a publish failure never fails the message.';

revoke all on function public.publish_website_chat_message_to_visitor()
  from public, anon, authenticated;

create trigger website_chat_messages_publish_to_visitor
  after insert on public.website_chat_messages
  for each row
  execute function public.publish_website_chat_message_to_visitor();
