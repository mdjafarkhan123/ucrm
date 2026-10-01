-- Client onboarding D1: the Uplift Support Messenger — a contractor's team member writes to Uplift, and
-- Uplift answers from the /jafar Support Inbox.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7. Industry reference: the Intercom /
-- Help Scout messenger model — one persistent conversation per person, kept in its own store, never mixed
-- with the product's customer inbox.
--
-- 1. support_threads: one conversation per team member in D1. Carries the latest message's time, preview
--    and sender, so the Support Inbox is one indexed read rather than a join over every message.
-- 2. support_messages: what was said. Never edited or deleted. The sender is a member, Uplift, the system,
--    or (later) an AI — the last two are a seam for §7's future identities; nothing writes them yet.
-- 3. platform_support_settings: the name shown on Uplift's replies and the honest hours / reply-time line.
--
-- A member reads only their own thread here. Owners and administrators seeing every thread in their
-- organization arrives with D3, by widening the one policy on support_threads.
-- Nobody writes these tables directly: a member sends through public.send_support_message, Uplift replies
-- through public.reply_to_support_thread (service role only).

-- 1. Threads -----------------------------------------------------------------------------------------------

create table public.support_threads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- The team member whose conversation this is. Kept when they later leave, so Uplift's record survives.
  started_by_user_id uuid references auth.users (id) on delete set null,
  last_message_at timestamptz not null default now(),
  last_message_preview text not null default '',
  last_message_sender_kind text not null default 'member',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_threads_last_message_sender_kind_check check (
    last_message_sender_kind in ('member', 'uplift', 'system', 'ai')
  ),
  constraint support_threads_last_message_preview_check check (char_length(last_message_preview) <= 160)
);

comment on table public.support_threads is
  'Uplift Support Messenger conversations, one per team member. Members may read their own, never write: messages arrive through public.send_support_message and public.reply_to_support_thread.';

-- One conversation per member. Also serves every "this organization's threads" read.
create unique index support_threads_one_per_member_idx
  on public.support_threads (organization_id, started_by_user_id);

create index support_threads_started_by_user_id_idx
  on public.support_threads (started_by_user_id) where started_by_user_id is not null;

-- The Support Inbox: every organization's threads, newest activity first.
create index support_threads_inbox_idx
  on public.support_threads (last_message_at desc, id desc);

create trigger support_threads_set_updated_at
  before update on public.support_threads
  for each row execute function public.set_updated_at();

-- 2. Messages ----------------------------------------------------------------------------------------------

create table public.support_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  sender_kind text not null,
  -- The team member who wrote it. Null for Uplift, and after that member's account is removed.
  sender_user_id uuid references auth.users (id) on delete set null,
  -- Which platform owner login replied. Kept for Uplift's own record; never sent to the contractor.
  sender_owner_email text,
  -- The name shown beside the message, as it was when the message was sent.
  sender_name text not null,
  body text not null,
  -- Chosen by the sender's browser, so a retry after a dropped connection never posts the message twice.
  client_message_id uuid not null,
  created_at timestamptz not null default now(),
  constraint support_messages_sender_kind_check check (
    sender_kind in ('member', 'uplift', 'system', 'ai')
  ),
  constraint support_messages_sender_identity_check check (
    (sender_kind = 'member' or sender_user_id is null)
    and ((sender_kind = 'uplift') = (sender_owner_email is not null))
  ),
  constraint support_messages_sender_name_check check (
    sender_name = btrim(sender_name) and char_length(sender_name) between 1 and 160
  ),
  constraint support_messages_body_check check (
    body = btrim(body) and char_length(body) between 1 and 4000
  ),
  constraint support_messages_client_message_id_key unique (thread_id, client_message_id)
);

comment on table public.support_messages is
  'Messages in an Uplift Support Messenger thread. Never edited or deleted. Members may read their own thread''s messages, never write them directly.';

-- Reading a thread: its latest messages first, with a stable order for messages sent in the same instant.
create index support_messages_thread_idx
  on public.support_messages (thread_id, created_at desc, id desc);

create index support_messages_organization_id_idx
  on public.support_messages (organization_id);

create index support_messages_sender_user_id_idx
  on public.support_messages (sender_user_id) where sender_user_id is not null;

-- Every message, whoever sent it, moves its thread to the top of the Support Inbox in the same transaction.
create function private.touch_support_thread_on_message()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
begin
  update public.support_threads
  set last_message_at = new.created_at,
      last_message_preview = left(regexp_replace(new.body, '\s+', ' ', 'g'), 160),
      last_message_sender_kind = new.sender_kind
  where id = new.thread_id;
  return null;
end;
$$;

revoke all on function private.touch_support_thread_on_message() from public;

create trigger support_messages_touch_thread
  after insert on public.support_messages
  for each row execute function private.touch_support_thread_on_message();

-- 3. How Uplift appears ------------------------------------------------------------------------------------

create table public.platform_support_settings (
  id boolean primary key default true,
  -- The person's name shown after "Uplift Support" on a reply. A reply cannot be sent until it is set.
  responder_name text not null default '',
  -- Uplift's own words for its support hours and usual reply time. Shown to contractors exactly as written;
  -- empty means the messenger promises nothing about timing.
  availability_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_support_settings_id_check check (id),
  constraint platform_support_settings_responder_name_check check (
    responder_name = btrim(responder_name) and char_length(responder_name) <= 80
  ),
  constraint platform_support_settings_availability_note_check check (
    availability_note = btrim(availability_note) and char_length(availability_note) <= 160
  )
);

comment on table public.platform_support_settings is
  'One row: the responder name and the hours / reply-time line the Uplift Support Messenger shows. Signed-in contractors may read it; only the platform owner (service role) writes it.';

create trigger platform_support_settings_set_updated_at
  before update on public.platform_support_settings
  for each row execute function public.set_updated_at();

insert into public.platform_support_settings (id) values (true);

-- Access ---------------------------------------------------------------------------------------------------

alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;
alter table public.platform_support_settings enable row level security;

revoke all on table public.support_threads from public, anon, authenticated;
revoke all on table public.support_messages from public, anon, authenticated;
revoke all on table public.platform_support_settings from public, anon, authenticated;

grant select on table public.support_threads to authenticated;
grant select on table public.support_messages to authenticated;
grant select on table public.platform_support_settings to authenticated;

grant all on table public.support_threads to service_role;
grant all on table public.support_messages to service_role;
grant all on table public.platform_support_settings to service_role;

create policy "members can view their own support thread"
  on public.support_threads
  for select
  to authenticated
  using (
    started_by_user_id = (select auth.uid())
    and (select private.is_organization_member(organization_id))
  );

-- A message is visible exactly when its thread is: the thread policy above decides, so D3 widens one place.
create policy "members can view messages in their support threads"
  on public.support_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.support_threads as thread
      where thread.id = support_messages.thread_id
    )
  );

create policy "signed-in users can view how Uplift support appears"
  on public.platform_support_settings
  for select
  to authenticated
  using (true);

-- Commands -------------------------------------------------------------------------------------------------

-- A team member writes to Uplift. Their thread is created by the first message, so an unopened messenger
-- leaves nothing behind. Returns the stored message; the same client_message_id returns the first one again.
create function public.send_support_message(
  target_organization_id uuid,
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
  actor_name text;
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

  select coalesce(
    nullif(btrim(profile.full_name), ''),
    nullif(btrim((select auth.jwt() ->> 'email')), ''),
    'Team member'
  )
  into actor_name
  from (select 1) as one
  left join public.profiles as profile on profile.id = actor_id;

  insert into public.support_threads (organization_id, started_by_user_id)
  values (target_organization_id, actor_id)
  on conflict (organization_id, started_by_user_id) do update
    set updated_at = now()
  returning id into thread_id_value;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_user_id, sender_name, body, client_message_id
  )
  values (
    thread_id_value, target_organization_id, 'member', actor_id, left(actor_name, 160), clean_body,
    message_client_id
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
    'sender_name', message_row.sender_name,
    'body', message_row.body,
    'created_at', message_row.created_at
  );
end;
$$;

-- Uplift replies from the Support Inbox. Service role only: the route has already proved the platform
-- owner's session, and passes that login's email for the record. The name shown comes from the saved
-- support settings, never from the request.
create function public.reply_to_support_thread(
  target_thread_id uuid,
  actor_email text,
  message_body text,
  message_client_id uuid
) returns jsonb
language plpgsql
set search_path to 'pg_catalog', 'public'
as $$
declare
  clean_body text := btrim(coalesce(message_body, ''));
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  responder text;
  thread_row public.support_threads;
  message_row public.support_messages;
begin
  if clean_email is null then
    raise exception 'An acting owner email is required to reply.' using errcode = 'check_violation';
  end if;

  if char_length(clean_body) not between 1 and 4000 then
    raise exception 'A message needs between 1 and 4000 characters.' using errcode = 'check_violation';
  end if;

  if message_client_id is null then
    raise exception 'The message is missing its identifier.' using errcode = 'check_violation';
  end if;

  select nullif(responder_name, '') into responder
  from public.platform_support_settings
  where id = true;

  if responder is null then
    raise exception 'Add the name clients see on your replies before sending one.'
      using errcode = 'check_violation';
  end if;

  select * into thread_row from public.support_threads where id = target_thread_id;
  if thread_row.id is null then
    raise exception 'That conversation no longer exists.' using errcode = 'no_data_found';
  end if;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_owner_email, sender_name, body, client_message_id
  )
  values (
    thread_row.id, thread_row.organization_id, 'uplift', clean_email, responder, clean_body,
    message_client_id
  )
  on conflict (thread_id, client_message_id) do nothing
  returning * into message_row;

  if message_row.id is null then
    select * into message_row
    from public.support_messages
    where thread_id = thread_row.id and client_message_id = message_client_id;
  end if;

  return jsonb_build_object(
    'id', message_row.id,
    'thread_id', message_row.thread_id,
    'sender_kind', message_row.sender_kind,
    'sender_name', message_row.sender_name,
    'body', message_row.body,
    'created_at', message_row.created_at
  );
end;
$$;

revoke all on function public.send_support_message(uuid, text, uuid) from public, anon;
revoke all on function public.reply_to_support_thread(uuid, text, text, uuid)
  from public, anon, authenticated;

grant execute on function public.send_support_message(uuid, text, uuid) to authenticated, service_role;
grant execute on function public.reply_to_support_thread(uuid, text, text, uuid) to service_role;
