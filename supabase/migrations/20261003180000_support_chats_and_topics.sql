-- Client onboarding D4a: a new Uplift Support chat for each question, each with a topic.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7. Industry reference: Intercom's
-- messenger — every new question is its own conversation, past ones stay listed — with a Zendesk-style
-- "type" field for the topic. Jafar's decisions (2026-10-02): picking a topic is optional and it starts as
-- Other; the chat's starter, an owner/admin, or Uplift may change it, and each change leaves a grey line.
--
-- 1. support_threads gains `topic`, and a member may now have any number of threads. Existing ones keep
--    their history and read as Other.
-- 2. public.start_support_thread opens a new chat with its first message. A retry with the same message id
--    returns the chat the first attempt made, never a second one.
-- 3. public.send_support_message now always names the chat it writes in.
-- 4. Changing a topic, by a member or by Uplift, posts a `system` line naming who did it.
-- 5. The badge counts only chats that can hold unread messages, now that chats multiply.

-- 1. Topic and several chats per member --------------------------------------------------------------------

alter table public.support_threads
  add column topic text not null default 'other',
  add constraint support_threads_topic_check check (
    topic in ('setup', 'website', 'google_profile', 'crm', 'billing', 'other')
  );

comment on column public.support_threads.topic is
  'What the chat is about: setup, website, google_profile, crm, billing or other. Changed only through the topic functions, which leave a grey line.';

comment on table public.support_threads is
  'Uplift Support Messenger chats: one per question, any number per team member. Members may read the ones they can see, never write: messages arrive through public.start_support_thread, public.send_support_message and public.reply_to_support_thread.';

drop index public.support_threads_one_per_member_idx;

-- "Your chats", newest first, and every "this member's chats in this organization" read (the badge).
create index support_threads_member_chats_idx
  on public.support_threads (organization_id, started_by_user_id, last_message_at desc, id desc);

-- The Support Inbox filtered to one topic, newest activity first.
create index support_threads_inbox_topic_idx
  on public.support_threads (topic, last_message_at desc, id desc);

-- public.support_inbox_unread_count (20261002235500) reads only chats whose latest message is the member's,
-- which this partial index holds, now that each member may have many chats.
create index support_threads_waiting_on_uplift_idx
  on public.support_threads (last_message_at desc)
  where last_message_sender_kind = 'member';

-- Finding the chat a retried first message already made. Also serves the sender foreign key, so the
-- single-column index it replaces goes.
create index support_messages_sender_client_id_idx
  on public.support_messages (sender_user_id, client_message_id)
  where sender_user_id is not null;

drop index public.support_messages_sender_user_id_idx;

-- The words a grey line uses for a topic.
create function private.support_topic_label(topic_value text)
returns text
language sql
immutable
set search_path to ''
as $$
  select case topic_value
    when 'setup' then 'Setup'
    when 'website' then 'Website'
    when 'google_profile' then 'Google Profile'
    when 'crm' then 'CRM'
    when 'billing' then 'Billing'
    else 'Other'
  end;
$$;

revoke all on function private.support_topic_label(text) from public;

-- The stored message as both send functions return it.
create function private.support_message_json(message_row public.support_messages)
returns jsonb
language sql
stable
set search_path to ''
as $$
  select jsonb_build_object(
    'id', message_row.id,
    'thread_id', message_row.thread_id,
    'sender_kind', message_row.sender_kind,
    'sender_user_id', message_row.sender_user_id,
    'sender_name', message_row.sender_name,
    'body', message_row.body,
    'created_at', message_row.created_at
  );
$$;

revoke all on function private.support_message_json(public.support_messages) from public;

-- 2. Starting a chat ---------------------------------------------------------------------------------------

create function public.start_support_thread(
  target_organization_id uuid,
  thread_topic text,
  message_body text,
  message_client_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  clean_body text := btrim(coalesce(message_body, ''));
  clean_topic text := coalesce(nullif(btrim(thread_topic), ''), 'other');
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if actor_id is null or not private.is_organization_member(target_organization_id) then
    raise exception 'Only an active team member can message Uplift.'
      using errcode = 'insufficient_privilege';
  end if;

  if char_length(clean_body) not between 1 and 4000 then
    raise exception 'A message needs between 1 and 4000 characters.' using errcode = 'check_violation';
  end if;

  if message_client_id is null then
    raise exception 'The message is missing its identifier.' using errcode = 'check_violation';
  end if;

  if clean_topic not in ('setup', 'website', 'google_profile', 'crm', 'billing', 'other') then
    raise exception 'Choose one of the listed topics.' using errcode = 'check_violation';
  end if;

  -- Two attempts of the same first message, arriving together, take turns here; the second then finds the
  -- chat the first one made.
  perform pg_advisory_xact_lock(hashtextextended('support-start:' || actor_id::text, 0));

  select * into message_row
  from public.support_messages
  where sender_user_id = actor_id
    and client_message_id = message_client_id
    and organization_id = target_organization_id;

  if message_row.id is not null then
    return private.support_message_json(message_row);
  end if;

  insert into public.support_threads (organization_id, started_by_user_id, topic)
  values (target_organization_id, actor_id, clean_topic)
  returning id into thread_id_value;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_user_id, sender_name, body, client_message_id
  )
  values (
    thread_id_value, target_organization_id, 'member', actor_id, private.support_member_name(actor_id),
    clean_body, message_client_id
  )
  returning * into message_row;

  return private.support_message_json(message_row);
end;
$$;

revoke all on function public.start_support_thread(uuid, text, text, uuid) from public, anon;
grant execute on function public.start_support_thread(uuid, text, text, uuid) to authenticated, service_role;

-- 3. Writing in a chat -------------------------------------------------------------------------------------

drop function public.send_support_message(uuid, text, uuid, uuid);

-- A member writes in a chat of this organization they can see. The same client id returns the first message.
create function public.send_support_message(
  target_organization_id uuid,
  target_thread_id uuid,
  message_body text,
  message_client_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  clean_body text := btrim(coalesce(message_body, ''));
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if actor_id is null or not private.is_organization_member(target_organization_id) then
    raise exception 'Only an active team member can message Uplift.'
      using errcode = 'insufficient_privilege';
  end if;

  if char_length(clean_body) not between 1 and 4000 then
    raise exception 'A message needs between 1 and 4000 characters.' using errcode = 'check_violation';
  end if;

  if message_client_id is null then
    raise exception 'The message is missing its identifier.' using errcode = 'check_violation';
  end if;

  select thread.id into thread_id_value
  from public.support_threads as thread
  where thread.id = target_thread_id
    and thread.organization_id = target_organization_id;

  if thread_id_value is null or not private.can_view_support_thread(thread_id_value) then
    raise exception 'That conversation is not one you can write in.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_user_id, sender_name, body, client_message_id
  )
  values (
    thread_id_value, target_organization_id, 'member', actor_id, private.support_member_name(actor_id),
    clean_body, message_client_id
  )
  on conflict (thread_id, client_message_id) do nothing
  returning * into message_row;

  if message_row.id is null then
    select * into message_row
    from public.support_messages
    where thread_id = thread_id_value and client_message_id = message_client_id;
  end if;

  return private.support_message_json(message_row);
end;
$$;

revoke all on function public.send_support_message(uuid, uuid, text, uuid) from public, anon;
grant execute on function public.send_support_message(uuid, uuid, text, uuid) to authenticated, service_role;

-- 4. Changing the topic ------------------------------------------------------------------------------------

-- The shared change. `actor_name` is who the grey line names. Returns false when the topic was already that,
-- so a repeated click posts no second line.
create function private.change_support_thread_topic(
  target_thread_id uuid,
  new_topic text,
  actor_name text
) returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  thread_row public.support_threads;
begin
  if new_topic is null
    or new_topic not in ('setup', 'website', 'google_profile', 'crm', 'billing', 'other')
  then
    raise exception 'Choose one of the listed topics.' using errcode = 'check_violation';
  end if;

  select * into thread_row from public.support_threads where id = target_thread_id for update;
  if thread_row.id is null then
    raise exception 'That conversation no longer exists.' using errcode = 'no_data_found';
  end if;

  if thread_row.topic = new_topic then
    return false;
  end if;

  update public.support_threads set topic = new_topic where id = thread_row.id;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_name, body, client_message_id
  )
  values (
    thread_row.id,
    thread_row.organization_id,
    'system',
    left(actor_name, 160),
    left(actor_name || ' changed the topic to ' || private.support_topic_label(new_topic) || '.', 4000),
    gen_random_uuid()
  );

  return true;
end;
$$;

revoke all on function private.change_support_thread_topic(uuid, text, text) from public;

create function public.set_support_thread_topic(target_thread_id uuid, new_topic text)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  thread_row public.support_threads;
begin
  select * into thread_row from public.support_threads where id = target_thread_id;

  if actor_id is null
    or thread_row.id is null
    or not private.can_view_support_thread(thread_row.id)
    or not (
      thread_row.started_by_user_id = actor_id
      or private.is_organization_admin(thread_row.organization_id)
    )
  then
    raise exception 'Only the person who started this conversation, or an owner or admin, can change its topic.'
      using errcode = 'insufficient_privilege';
  end if;

  return private.change_support_thread_topic(thread_row.id, new_topic, private.support_member_name(actor_id));
end;
$$;

-- Uplift. Service role only; the line reads "Uplift Support changed the topic to …".
create function public.set_support_thread_topic_by_uplift(target_thread_id uuid, new_topic text)
returns boolean
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select private.change_support_thread_topic(target_thread_id, new_topic, 'Uplift Support');
$$;

revoke all on function public.set_support_thread_topic(uuid, text) from public, anon;
revoke all on function public.set_support_thread_topic_by_uplift(uuid, text) from public, anon, authenticated;
grant execute on function public.set_support_thread_topic(uuid, text) to authenticated, service_role;
grant execute on function public.set_support_thread_topic_by_uplift(uuid, text) to service_role;

-- 5. Badge --------------------------------------------------------------------------------------------

-- Messages in the member's own chats and the ones they were added to, written by someone else after their
-- mark. System lines never count. Only chats whose latest message is newer than the member's mark can hold
-- unread messages (system lines never move that time, and the member's own message moves their mark), so
-- only those are counted — each a short range on support_messages_thread_idx — capped at 100 in total.
create or replace function public.support_unread_count(target_organization_id uuid)
returns integer
language plpgsql
stable
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  thread_row record;
  total integer := 0;
begin
  for thread_row in
    select thread.id, read_mark.last_read_at as mark
    from public.support_threads as thread
    left join public.support_thread_reads as read_mark
      on read_mark.thread_id = thread.id and read_mark.user_id = actor_id
    where thread.organization_id = target_organization_id
      and (
        thread.started_by_user_id = actor_id
        or thread.id in (
          select participant.thread_id
          from public.support_thread_participants as participant
          where participant.user_id = actor_id
            and participant.organization_id = target_organization_id
        )
      )
      and thread.last_message_at > coalesce(read_mark.last_read_at, '-infinity'::timestamptz)
  loop
    total := total + (
      select count(*)::integer
      from (
        select 1
        from public.support_messages as message
        where message.thread_id = thread_row.id
          and message.created_at > coalesce(thread_row.mark, '-infinity'::timestamptz)
          and message.sender_kind <> 'system'
          and message.sender_user_id is distinct from actor_id
        limit 100
      ) as unread
    );
    exit when total >= 100;
  end loop;

  return least(total, 100);
end;
$$;
