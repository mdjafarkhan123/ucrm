-- WC4.4 Stage A: the one way a visitor reads their own conversation back.
--
-- 4.1 shipped two write commands and 4.2 shipped their routes, but nothing has ever returned a
-- session's messages. Session restore after a reload, and the ~4s polling fallback behind Realtime,
-- both need this, so it is the first thing 4.4 builds.
--
-- Authorization is the visitor's own session secret plus the requesting origin, exactly as
-- `post_website_chat_message` checks them -- a script copied onto an unauthorized site cannot read a
-- conversation any more than it can write to one. Every refusal is the same silent answer: a caller
-- must not be able to tell a bad token from a wrong origin from a session that does not exist.
--
-- **A closed session still returns its history** (WC0.3). Ending a conversation stops new messages; it
-- does not take the transcript away from the person who wrote half of it.
--
-- Keyset, never offset. The cursor is the row value `(created_at, id)` of the oldest message the caller
-- already holds, which walks straight down `website_chat_messages_session_timeline_idx`
-- `(organization_id, session_id, created_at desc, id desc)` -- both leading columns are supplied, so the
-- scan starts at the cursor instead of counting past skipped rows on every page.
--
-- The projection is deliberately narrow. `sender_user_id` in particular must never reach a stranger's
-- browser: it identifies a real staff member, and this response is read by an anonymous visitor on a
-- third party's website. `organization_id`, `client_id` and `idempotency_key` are withheld for the same
-- reason -- none of them is anything the widget needs to render a bubble.

create function public.get_website_chat_session_messages(
  session_token_hash text,
  requesting_origin text,
  before_created_at timestamptz default null,
  before_id uuid default null,
  page_size integer default 30
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
  -- Clamped in the command, not only in the route: the command is the boundary that has to hold even
  -- if something else ever calls it.
  effective_page_size integer := least(greatest(coalesce(page_size, 30), 1), 50);
  rate_check record;
  page jsonb;
  fetched integer;
begin
  if normalized_origin = '' or nullif(btrim(coalesce(session_token_hash, '')), '') is null then
    return jsonb_build_object('status', 'refused');
  end if;

  -- A cursor is both halves or neither. Half a cursor is a caller bug, and silently treating it as
  -- "start from the top" would quietly return the wrong page forever.
  if (before_created_at is null) <> (before_id is null) then
    return jsonb_build_object('status', 'refused');
  end if;

  select * into target_session
  from public.website_chat_sessions s
  where s.session_token_hash = btrim(get_website_chat_session_messages.session_token_hash);
  if not found then
    return jsonb_build_object('status', 'refused');
  end if;

  select w.id, w.organization_id, w.disabled_at, w.suspended_at, w.published into widget
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

  -- Deliberately no `published`/`disabled_at`/`suspended_at` gate here, unlike the write commands: a
  -- contractor who disables their widget stops new conversations, but a visitor with a live tab open
  -- keeps the transcript already in front of them rather than watching it blank out mid-read.

  -- Read flood control, separate from the write limits. A visible tab polls every ~4s (15/minute); this
  -- leaves headroom for several tabs and a reconnect burst while still bounding a stuck client.
  select * into rate_check
  from public.check_rate_limit('website_chat:read:' || target_session.id::text, 60, 90);
  if not rate_check.allowed then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  -- One extra row is fetched purely to answer "is there another page?" without a second count query,
  -- then trimmed off before the response is built.
  -- `materialized` on purpose: `page_rows` is referenced twice (once trimmed, once counted), and
  -- without it Postgres is free to inline the CTE and run the index scan twice per call.
  with page_rows as materialized (
    select m.id, m.direction, m.sender_type, m.body, m.created_at
    from public.website_chat_messages m
    where m.organization_id = target_session.organization_id
      and m.session_id = target_session.id
      and (
        before_created_at is null
        or (m.created_at, m.id) < (before_created_at, before_id)
      )
    order by m.created_at desc, m.id desc
    limit effective_page_size + 1
  ),
  trimmed as (
    select * from page_rows
    order by created_at desc, id desc
    limit effective_page_size
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id', trimmed.id,
      'direction', trimmed.direction,
      'sender_type', trimmed.sender_type,
      'body', trimmed.body,
      'created_at', trimmed.created_at
    ) order by trimmed.created_at desc, trimmed.id desc), '[]'::jsonb),
    (select count(*) from page_rows)
  into page, fetched
  from trimmed;

  return jsonb_build_object(
    'status', 'ok',
    'session_id', target_session.id,
    'closed_at', target_session.closed_at,
    'messages', page,
    'has_more', fetched > effective_page_size
  );
end;
$$;

comment on function public.get_website_chat_session_messages(
  text, text, timestamptz, uuid, integer
) is 'The only read path for a Website Chat visitor''s own conversation. Authorized by the session '
  'token hash plus an allowlisted origin, keyset-paginated, and narrowed to the fields a bubble needs '
  '-- never sender_user_id. A closed session still returns its history.';

revoke all on function public.get_website_chat_session_messages(
  text, text, timestamptz, uuid, integer
) from public, anon, authenticated;
grant execute on function public.get_website_chat_session_messages(
  text, text, timestamptz, uuid, integer
) to service_role;
