-- Client onboarding D3: who sees which Uplift Support conversation.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7. Industry reference: the Zendesk help
-- centre's three request lists — "My requests", "Requests I'm CC'd on", "Organization requests". Here:
--   - every member sees the conversation they started;
--   - a member added to someone else's conversation sees it and may write in it;
--   - owners and administrators see, and may write in, every conversation in their organization.
-- Jafar's decisions (2026-10-01): owners/admins reply in their own name; Uplift, the conversation's starter and
-- owners/admins may add or remove teammates, and each change leaves a grey line in the conversation; the red
-- badge counts only your own conversation and ones you were added to, never every team conversation.
--
-- 1. support_thread_participants: who was added to a conversation, beyond the person who started it.
-- 2. One rule, private.can_view_support_thread, decides visibility; the thread's row policy says the same.
-- 3. A member may post into any conversation they can see (send_support_message gains a thread argument).
-- 4. Adding or removing a teammate, by a member or by Uplift, posts a `system` line naming who did it.
--    System lines never move the conversation's "latest message", so they neither reorder the Support Inbox,
--    change who is waiting on whom, nor light anyone's badge.
-- 5. The badge counts own and added conversations. Live pings reach the starter, everyone added, and the
--    organization's owners/admins (who see the team list) — a handful of people per message.

-- 1. Participants ------------------------------------------------------------------------------------------

create table public.support_thread_participants (
  thread_id uuid not null references public.support_threads (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

comment on table public.support_thread_participants is
  'Team members added to someone else''s Uplift Support conversation. Written only by the add/remove functions; whoever can see the conversation can see this list.';

-- "Which conversations was I added to?" — the badge and the member's Team chats list.
create index support_thread_participants_user_idx
  on public.support_thread_participants (user_id, organization_id);

create index support_thread_participants_organization_id_idx
  on public.support_thread_participants (organization_id);

create function private.is_support_thread_participant(target_thread_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.support_thread_participants as participant
    where participant.thread_id = target_thread_id
      and participant.user_id = (select auth.uid())
  );
$$;

-- 2. Visibility --------------------------------------------------------------------------------------------

create or replace function private.can_view_support_thread(target_thread_id uuid)
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
      and private.is_organization_member(thread.organization_id)
      and (
        thread.started_by_user_id = (select auth.uid())
        or private.is_organization_admin(thread.organization_id)
        or private.is_support_thread_participant(thread.id)
      )
  );
$$;

drop policy "members can view their own support thread" on public.support_threads;

create policy "members can view support threads they started, joined, or administer"
  on public.support_threads
  for select
  to authenticated
  using (
    (select private.is_organization_member(organization_id))
    and (
      started_by_user_id = (select auth.uid())
      or (select private.is_organization_admin(organization_id))
      or private.is_support_thread_participant(id)
    )
  );

alter table public.support_thread_participants enable row level security;

revoke all on table public.support_thread_participants from public, anon, authenticated;
grant select on table public.support_thread_participants to authenticated;
grant all on table public.support_thread_participants to service_role;

create policy "members can view who is in the support threads they can see"
  on public.support_thread_participants
  for select
  to authenticated
  using (private.can_view_support_thread(thread_id));

revoke all on function private.is_support_thread_participant(uuid) from public;
grant execute on function private.is_support_thread_participant(uuid) to authenticated;

-- System lines leave the thread's latest message alone (see 4 above).
create or replace function private.touch_support_thread_on_message()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if new.sender_kind = 'system' then
    return null;
  end if;

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

-- 3. Posting into a chosen conversation --------------------------------------------------------------------

-- The display name of a member, as messages and system lines show it.
create function private.support_member_name(target_user_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select left(
    coalesce(
      nullif(btrim(profile.full_name), ''),
      nullif(btrim(account.email), ''),
      'Team member'
    ),
    160
  )
  from (select 1) as one
  left join public.profiles as profile on profile.id = target_user_id
  left join auth.users as account on account.id = target_user_id;
$$;

revoke all on function private.support_member_name(uuid) from public;

drop function public.send_support_message(uuid, text, uuid);

-- Without a thread, the member writes in their own conversation, created by its first message. With one, they
-- write in any conversation of this organization they can see. The same client id returns the first message.
create function public.send_support_message(
  target_organization_id uuid,
  message_body text,
  message_client_id uuid,
  target_thread_id uuid default null
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

  if target_thread_id is null then
    insert into public.support_threads (organization_id, started_by_user_id)
    values (target_organization_id, actor_id)
    on conflict (organization_id, started_by_user_id) do update
      set updated_at = now()
    returning id into thread_id_value;
  else
    select thread.id into thread_id_value
    from public.support_threads as thread
    where thread.id = target_thread_id
      and thread.organization_id = target_organization_id;

    if thread_id_value is null or not private.can_view_support_thread(thread_id_value) then
      raise exception 'That conversation is not one you can write in.'
        using errcode = 'insufficient_privilege';
    end if;
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

  return jsonb_build_object(
    'id', message_row.id,
    'thread_id', message_row.thread_id,
    'sender_kind', message_row.sender_kind,
    'sender_user_id', message_row.sender_user_id,
    'sender_name', message_row.sender_name,
    'body', message_row.body,
    'created_at', message_row.created_at
  );
end;
$$;

revoke all on function public.send_support_message(uuid, text, uuid, uuid) from public, anon;
grant execute on function public.send_support_message(uuid, text, uuid, uuid) to authenticated, service_role;

-- 4. Adding and removing teammates -------------------------------------------------------------------------

-- Who is in a conversation and who could still be added. The caller has already been allowed to see it.
-- `addable` lists the organization's other active members, capped as the team screens are.
create function private.support_thread_people_core(target_thread_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with thread as (
    select id, organization_id, started_by_user_id
    from public.support_threads
    where id = target_thread_id
  ),
  people as (
    select thread.started_by_user_id as user_id, true as started, thread.organization_id
    from thread
    where thread.started_by_user_id is not null
    union all
    select participant.user_id, false, participant.organization_id
    from public.support_thread_participants as participant
    join thread on thread.id = participant.thread_id
  )
  select jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'user_id', person.user_id,
          'name', private.support_member_name(person.user_id),
          'started', person.started,
          -- Someone who has since left the team still shows, so the record reads truthfully.
          'active', exists (
            select 1 from public.organization_members as membership
            where membership.organization_id = person.organization_id
              and membership.user_id = person.user_id
              and membership.status = 'active'
          )
        )
        order by person.started desc, private.support_member_name(person.user_id)
      )
      from people as person
    ), '[]'::jsonb),
    'addable', coalesce((
      select jsonb_agg(
        jsonb_build_object('user_id', candidate.user_id, 'name', candidate.name)
        order by candidate.name
      )
      from (
        select membership.user_id, private.support_member_name(membership.user_id) as name
        from public.organization_members as membership
        join thread on thread.organization_id = membership.organization_id
        where membership.status = 'active'
          and not exists (select 1 from people where people.user_id = membership.user_id)
        limit 200
      ) as candidate
    ), '[]'::jsonb)
  )
  from thread;
$$;

revoke all on function private.support_thread_people_core(uuid) from public;

-- A member's view of the people list, with whether they may change it.
create function public.support_thread_people(target_thread_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  thread_row public.support_threads;
begin
  if not private.can_view_support_thread(target_thread_id) then
    raise exception 'That conversation could not be found.' using errcode = 'no_data_found';
  end if;

  select * into thread_row from public.support_threads where id = target_thread_id;

  return private.support_thread_people_core(target_thread_id) || jsonb_build_object(
    'can_manage',
    thread_row.started_by_user_id = (select auth.uid())
      or private.is_organization_admin(thread_row.organization_id)
  );
end;
$$;

-- Uplift's view. Service role only: the route has proved the owner session.
create function public.support_thread_people_for_uplift(target_thread_id uuid)
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select private.support_thread_people_core(target_thread_id) || jsonb_build_object('can_manage', true);
$$;

-- The shared change. `actor_name` is who the grey line names. Returns false when nothing changed (already
-- added, or already removed), so a repeated click posts no second line.
create function private.change_support_thread_participant(
  target_thread_id uuid,
  target_user_id uuid,
  adding boolean,
  actor_name text
) returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  thread_row public.support_threads;
  changed integer;
  member_name text := private.support_member_name(target_user_id);
begin
  select * into thread_row from public.support_threads where id = target_thread_id for update;
  if thread_row.id is null then
    raise exception 'That conversation no longer exists.' using errcode = 'no_data_found';
  end if;

  if target_user_id = thread_row.started_by_user_id then
    raise exception 'The person who started this conversation is always in it.'
      using errcode = 'check_violation';
  end if;

  if adding then
    if not exists (
      select 1 from public.organization_members as membership
      where membership.organization_id = thread_row.organization_id
        and membership.user_id = target_user_id
        and membership.status = 'active'
    ) then
      raise exception 'Only an active member of this team can be added.' using errcode = 'check_violation';
    end if;

    insert into public.support_thread_participants (thread_id, user_id, organization_id)
    values (thread_row.id, target_user_id, thread_row.organization_id)
    on conflict (thread_id, user_id) do nothing;
  else
    delete from public.support_thread_participants
    where thread_id = thread_row.id and user_id = target_user_id;
  end if;

  get diagnostics changed = row_count;
  if changed = 0 then
    return false;
  end if;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_name, body, client_message_id
  )
  values (
    thread_row.id,
    thread_row.organization_id,
    'system',
    left(actor_name, 160),
    left(
      actor_name || case when adding then ' added ' else ' removed ' end || member_name
        || case when adding then ' to this conversation.' else ' from this conversation.' end,
      4000
    ),
    gen_random_uuid()
  );

  -- Someone removed no longer hears the conversation's pings, so tell their open messenger once.
  if not adding then
    perform private.send_support_ping(
      'support-user:' || target_user_id::text,
      'support_activity',
      jsonb_build_object('thread_id', thread_row.id)
    );
  end if;

  return true;
end;
$$;

revoke all on function private.change_support_thread_participant(uuid, uuid, boolean, text) from public;

create function public.set_support_thread_participant(
  target_thread_id uuid,
  target_user_id uuid,
  adding boolean
) returns boolean
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
    raise exception 'Only the person who started this conversation, or an owner or admin, can change who is in it.'
      using errcode = 'insufficient_privilege';
  end if;

  if adding is null or target_user_id is null then
    raise exception 'Choose a teammate.' using errcode = 'check_violation';
  end if;

  return private.change_support_thread_participant(
    thread_row.id, target_user_id, adding, private.support_member_name(actor_id)
  );
end;
$$;

-- Uplift. Service role only; the line reads "Uplift Support added …".
create function public.set_support_thread_participant_by_uplift(
  target_thread_id uuid,
  target_user_id uuid,
  adding boolean
) returns boolean
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  if adding is null or target_user_id is null then
    raise exception 'Choose a teammate.' using errcode = 'check_violation';
  end if;

  return private.change_support_thread_participant(target_thread_id, target_user_id, adding, 'Uplift Support');
end;
$$;

revoke all on function public.support_thread_people(uuid) from public, anon;
revoke all on function public.support_thread_people_for_uplift(uuid) from public, anon, authenticated;
revoke all on function public.set_support_thread_participant(uuid, uuid, boolean) from public, anon;
revoke all on function public.set_support_thread_participant_by_uplift(uuid, uuid, boolean)
  from public, anon, authenticated;

grant execute on function public.support_thread_people(uuid) to authenticated, service_role;
grant execute on function public.support_thread_people_for_uplift(uuid) to service_role;
grant execute on function public.set_support_thread_participant(uuid, uuid, boolean) to authenticated, service_role;
grant execute on function public.set_support_thread_participant_by_uplift(uuid, uuid, boolean) to service_role;

-- 5. Badge and live pings ----------------------------------------------------------------------------------

-- Messages in the member's own conversation and the ones they were added to, written by someone else after
-- their mark. System lines never count. Each conversation is its own short range on
-- support_messages_thread_idx (see 20261003094000), capped at 100 in total for the "99+" badge.
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

-- Everyone who sees the conversation in a list: its starter, everyone added, and the organization's active
-- owners/admins. Uplift's live sessions as before.
create or replace function private.publish_support_message_activity()
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
  for member_id in
    select thread.started_by_user_id
    from public.support_threads as thread
    where thread.id = new.thread_id and thread.started_by_user_id is not null
    union
    select participant.user_id
    from public.support_thread_participants as participant
    where participant.thread_id = new.thread_id
    union
    select membership.user_id
    from public.organization_members as membership
    where membership.organization_id = new.organization_id
      and membership.role in ('owner', 'admin')
      and membership.status = 'active'
  loop
    perform private.send_support_ping('support-user:' || member_id::text, 'support_activity', payload);
  end loop;

  for owner_topic in select * from private.live_support_owner_topics() loop
    perform private.send_support_ping(owner_topic, 'support_activity', payload);
  end loop;

  return null;
end;
$$;
