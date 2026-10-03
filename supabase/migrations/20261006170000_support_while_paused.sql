-- Client onboarding D5c: Chat with Uplift stays open while a business is paused.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7 — "The paused-account screen keeps
-- Chat with Uplift", and every active team member may contact support.
-- Industry reference: Intercom and Zendesk keep the support messenger working for a customer whose account
-- is suspended; that is when they most need it.
--
-- A paused business is hidden from its own team: private.is_organization_member and
-- private.is_organization_admin require an active organization, and every other table leans on them. This
-- change leaves both alone and gives support its own pair of checks, which also accept a suspended
-- organization and one pending closure (restoration is still possible then). A closed business gets no chat.
-- Only the support functions and the support_threads read policy switch to them, so nothing else opens.

-- 1. The support checks ------------------------------------------------------------------------------------

create function private.is_support_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and organization.lifecycle_status in ('active', 'suspended', 'pending_closure')
  );
$$;

create function private.is_support_admin(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.role in ('owner', 'admin')
      and membership.status = 'active'
      and organization.lifecycle_status in ('active', 'suspended', 'pending_closure')
  );
$$;

revoke all on function private.is_support_member(uuid) from public, anon;
revoke all on function private.is_support_admin(uuid) from public, anon;
grant execute on function private.is_support_member(uuid) to authenticated;
grant execute on function private.is_support_admin(uuid) to authenticated;

-- 2. The server's organization context for support --------------------------------------------------------
-- The app's usual context reads the organization through its own row level security, so a paused member
-- gets none. Support asks this instead: the caller's one active membership, if support is open to it.

create function public.support_member_context()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
    'id', organization.id,
    'name', organization.name,
    'slug', organization.slug,
    'role', membership.role
  )
  from public.organization_members as membership
  join public.organizations as organization
    on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid())
    and membership.status = 'active'
    and organization.lifecycle_status in ('active', 'suspended', 'pending_closure')
  order by membership.created_at
  limit 1;
$$;

revoke all on function public.support_member_context() from public, anon;
grant execute on function public.support_member_context() to authenticated;

-- 3. Teammates' names in the messenger ---------------------------------------------------------------------
-- profiles' own policy goes through organization_members, which a paused team cannot read, so a teammate's
-- chat would read "Former team member". Someone permanently removed stays unnamed, as before.

create function public.support_teammate_names(target_organization_id uuid, target_user_ids uuid[])
returns table (id uuid, full_name text)
language sql
stable
security definer
set search_path to ''
as $$
  select profile.id, profile.full_name
  from public.profiles as profile
  where private.is_support_member(target_organization_id)
    and profile.id = any (target_user_ids[1:200])
    and exists (
      select 1
      from public.organization_members as membership
      where membership.organization_id = target_organization_id
        and membership.user_id = profile.id
        and membership.status <> 'removed'
    );
$$;

revoke all on function public.support_teammate_names(uuid, uuid[]) from public, anon;
grant execute on function public.support_teammate_names(uuid, uuid[]) to authenticated;

-- 4. Who sees which chat -----------------------------------------------------------------------------------

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
      and private.is_support_member(thread.organization_id)
      and (
        thread.started_by_user_id = (select auth.uid())
        or private.is_support_admin(thread.organization_id)
        or private.is_support_thread_participant(thread.id)
      )
  );
$$;

drop policy "members can view support threads they started, joined, or admin" on public.support_threads;
create policy "members can view support threads they started, joined, or admin"
  on public.support_threads
  for select
  to authenticated
  using (
    (select private.is_support_member(support_threads.organization_id))
    and (
      started_by_user_id = (select auth.uid())
      or (select private.is_support_admin(support_threads.organization_id))
      or private.is_support_thread_participant(id)
    )
  );

-- 5. Writing, topics, and people ---------------------------------------------------------------------------

create or replace function public.send_support_message(
  target_organization_id uuid,
  target_thread_id uuid,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  clean_body text := btrim(coalesce(message_body, ''));
  file_count smallint;
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if actor_id is null or not private.is_support_member(target_organization_id) then
    raise exception 'Only an active team member can message Uplift.'
      using errcode = 'insufficient_privilege';
  end if;

  file_count := private.check_support_attachments(target_organization_id, message_attachments);

  if char_length(clean_body) > 4000 then
    raise exception 'A message can have up to 4000 characters.' using errcode = 'check_violation';
  end if;

  if clean_body = '' and file_count = 0 then
    raise exception 'Write a message or attach a file first.' using errcode = 'check_violation';
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
    thread_id, organization_id, sender_kind, sender_user_id, sender_name, body, client_message_id,
    attachment_count
  )
  values (
    thread_id_value, target_organization_id, 'member', actor_id, private.support_member_name(actor_id),
    clean_body, message_client_id, file_count
  )
  on conflict (thread_id, client_message_id) do nothing
  returning * into message_row;

  if message_row.id is null then
    select * into message_row
    from public.support_messages
    where thread_id = thread_id_value and client_message_id = message_client_id;
  else
    perform private.add_support_attachments(message_row, message_attachments);
  end if;

  return private.support_message_json(message_row);
end;
$$;

create or replace function public.start_support_thread(
  target_organization_id uuid,
  thread_topic text,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  clean_body text := btrim(coalesce(message_body, ''));
  clean_topic text := coalesce(nullif(btrim(thread_topic), ''), 'other');
  file_count smallint;
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if actor_id is null or not private.is_support_member(target_organization_id) then
    raise exception 'Only an active team member can message Uplift.'
      using errcode = 'insufficient_privilege';
  end if;

  file_count := private.check_support_attachments(target_organization_id, message_attachments);

  if char_length(clean_body) > 4000 then
    raise exception 'A message can have up to 4000 characters.' using errcode = 'check_violation';
  end if;

  if clean_body = '' and file_count = 0 then
    raise exception 'Write a message or attach a file first.' using errcode = 'check_violation';
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
    thread_id, organization_id, sender_kind, sender_user_id, sender_name, body, client_message_id,
    attachment_count
  )
  values (
    thread_id_value, target_organization_id, 'member', actor_id, private.support_member_name(actor_id),
    clean_body, message_client_id, file_count
  )
  returning * into message_row;

  perform private.add_support_attachments(message_row, message_attachments);

  return private.support_message_json(message_row);
end;
$$;

create or replace function public.set_support_thread_participant(
  target_thread_id uuid,
  target_user_id uuid,
  adding boolean
)
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
      or private.is_support_admin(thread_row.organization_id)
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

create or replace function public.set_support_thread_topic(target_thread_id uuid, new_topic text)
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
      or private.is_support_admin(thread_row.organization_id)
    )
  then
    raise exception 'Only the person who started this conversation, or an owner or admin, can change its topic.'
      using errcode = 'insufficient_privilege';
  end if;

  return private.change_support_thread_topic(thread_row.id, new_topic, private.support_member_name(actor_id));
end;
$$;

create or replace function public.support_thread_people(target_thread_id uuid)
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
      or private.is_support_admin(thread_row.organization_id)
  );
end;
$$;
