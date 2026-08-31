-- WC4.5 Layer 1, performance gate. Two fixes, both found by measuring rather than by reading.
--
-- 1. The identity backfill was scoped by session_id alone. `website_chat_messages_session_timeline_idx`
--    leads with organization_id, so session_id alone cannot drive it and the update fell back to a
--    sequential scan of the whole messages table.
--
--    Measured on 50,010 messages across 5,001 sessions -- the realistic shape, a handful of messages per
--    conversation rather than one enormous one:
--
--      session_id alone                  Seq Scan, 2,305 buffers, 50,001 rows discarded to update 10
--      organization_id + session_id      Index Scan on website_chat_messages_session_timeline_idx,
--                                        Index Cond on BOTH leading columns, 87 buffers
--
--    26x fewer buffers, and the important part is not the ratio: the first plan grows with the whole
--    table and the second grows with the one conversation. At a few million messages the first is a
--    seconds-long table scan holding a pooled connection every time somebody resolves an identity.
--
--    The command already holds target_organization_id -- it authorized against it -- so this costs
--    nothing but the extra predicate.
--
-- 2. `closed_by` shipped without an index. Nothing queries by it, but it is a foreign key to
--    auth.users with ON DELETE SET NULL, so deleting a user forces a sequential scan of
--    website_chat_sessions to find rows to null out. That is the same reason
--    website_chat_messages_sender_user_idx exists, and it is partial for the same reason: only a
--    staff-ended session carries a value at all.

create index website_chat_sessions_closed_by_idx
  on public.website_chat_sessions (closed_by)
  where closed_by is not null;

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
  --
  -- organization_id is in the predicate for the index, not for safety -- the session was already
  -- authorized above. It is the leading column of website_chat_messages_session_timeline_idx, and
  -- without it this update reads the entire table. See this migration's header for the numbers.
  update public.website_chat_messages
  set client_id = chosen_client_id
  where organization_id = target_organization_id
    and session_id = target_session.id
    and client_id is null;

  get diagnostics backfilled_count = row_count;

  return jsonb_build_object(
    'status', 'resolved',
    'session_id', target_session.id,
    'client_id', chosen_client_id,
    'messages_backfilled', backfilled_count
  );
end;
$$;

revoke all on function public.resolve_website_chat_session_identity(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_website_chat_session_identity(uuid, uuid, uuid, uuid)
  to service_role;
