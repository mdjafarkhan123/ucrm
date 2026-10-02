-- Client onboarding D4b: photos and documents in an Uplift Support chat, from either side.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7 — up to 5 files and 20 MB per
-- message; program files refused; photos show in the chat, other files download. Industry reference:
-- Intercom's and Slack's composers — a file uploads to storage as soon as it is picked, and the message
-- that is then sent names the uploads it carries. A message may be files alone, with no words.
--
-- 1. support_message_attachments: the files a message carries. Never edited or deleted, like the message.
-- 2. support_messages gains `attachment_count`, so a message with no words is allowed only when it carries
--    a file, and the chat lists can say "Sent a file" without reading the files.
-- 3. The three send functions take the uploaded files and store them with the message in one transaction.
--    A retry with the same message id stores nothing twice.

-- 1. Files -------------------------------------------------------------------------------------------------

create table public.support_message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.support_messages (id) on delete cascade,
  thread_id uuid not null references public.support_threads (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- The order the sender attached them in.
  position smallint not null,
  file_name text not null,
  mime_type text not null,
  byte_size bigint not null,
  -- Where the file sits in storage: always `<organization>/support-attachments/…`.
  object_key text not null,
  -- The browser made a small copy of a photo at upload, stored beside it as `<object_key>.thumb.jpg`.
  has_thumbnail boolean not null default false,
  created_at timestamptz not null default now(),
  constraint support_message_attachments_position_check check (position between 0 and 4),
  constraint support_message_attachments_file_name_check check (
    file_name = btrim(file_name) and char_length(file_name) between 1 and 255
  ),
  constraint support_message_attachments_mime_type_check check (char_length(mime_type) between 1 and 127),
  constraint support_message_attachments_byte_size_check check (byte_size between 1 and 20971520),
  -- One upload belongs to one message.
  constraint support_message_attachments_object_key_key unique (object_key),
  -- Also serves every "this message's files" read and the message foreign key.
  constraint support_message_attachments_message_position_key unique (message_id, position)
);

comment on table public.support_message_attachments is
  'Files sent in an Uplift Support Messenger chat. Never edited or deleted. Members may read the files of chats they can see, never write them: files arrive with their message through the send functions.';

create index support_message_attachments_thread_id_idx
  on public.support_message_attachments (thread_id);

create index support_message_attachments_organization_id_idx
  on public.support_message_attachments (organization_id);

alter table public.support_message_attachments enable row level security;

revoke all on table public.support_message_attachments from public, anon, authenticated;
grant select on table public.support_message_attachments to authenticated;
grant all on table public.support_message_attachments to service_role;

-- A file is visible exactly when its chat is: the policy on support_threads decides.
create policy "members can view files in support threads they can see"
  on public.support_message_attachments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.support_threads as thread
      where thread.id = support_message_attachments.thread_id
    )
  );

-- 2. A message may be files alone --------------------------------------------------------------------------

alter table public.support_messages
  add column attachment_count smallint not null default 0,
  drop constraint support_messages_body_check,
  add constraint support_messages_body_check check (
    body = btrim(body)
    and char_length(body) <= 4000
    and attachment_count between 0 and 5
    and (body <> '' or attachment_count > 0)
  );

comment on column public.support_messages.attachment_count is
  'How many files the message carries (0 to 5). Set once, when the message is stored.';

-- The chat lists show the message's words, or "Sent a file" when it has none.
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
      last_message_preview = case
        when new.body <> '' then left(regexp_replace(new.body, '\s+', ' ', 'g'), 160)
        when new.attachment_count = 1 then 'Sent a file'
        else 'Sent ' || new.attachment_count || ' files'
      end,
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

-- 3. Sending files -----------------------------------------------------------------------------------------

-- Checks the files a message names and returns how many there are. The routes measure each upload in
-- storage before calling; this is the rule a direct call cannot get around: at most 5 files, 20 MB in all,
-- every one under this organization's own support prefix, and a name whose ending matches the upload's —
-- the upload was issued for a name the program-file check had already passed, so a file cannot be renamed
-- into one it would have refused.
create function private.check_support_attachments(target_organization_id uuid, attachments jsonb)
returns smallint
language plpgsql
immutable
set search_path to ''
as $$
declare
  files jsonb := coalesce(attachments, '[]'::jsonb);
  file_count integer;
  bad_count integer;
  total_bytes bigint;
begin
  if jsonb_typeof(files) <> 'array' then
    raise exception 'The attached files could not be read.' using errcode = 'check_violation';
  end if;

  file_count := jsonb_array_length(files);
  if file_count = 0 then
    return 0;
  end if;

  if file_count > 5 then
    raise exception 'Attach at most 5 files to one message.' using errcode = 'check_violation';
  end if;

  select
    count(*) filter (
      where not coalesce(
        starts_with(file.object_key, target_organization_id::text || '/support-attachments/')
        and char_length(btrim(file.file_name)) between 1 and 255
        and char_length(file.mime_type) between 1 and 127
        and file.byte_size > 0
        and lower(substring(btrim(file.file_name) from '\.([^.]*)$'))
          is not distinct from lower(substring(file.object_key from '\.([^./]*)$')),
        false
      )
    ),
    coalesce(sum(file.byte_size), 0)
  into bad_count, total_bytes
  from jsonb_to_recordset(files) as file (
    object_key text, file_name text, mime_type text, byte_size bigint
  );

  if bad_count > 0 then
    raise exception 'One of those files could not be attached. Remove it and add it again.'
      using errcode = 'check_violation';
  end if;

  if total_bytes > 20971520 then
    raise exception 'Attachments must total 20 MB or less.' using errcode = 'check_violation';
  end if;

  return file_count::smallint;
end;
$$;

revoke all on function private.check_support_attachments(uuid, jsonb) from public;

-- Stores a new message's files, in the order they were attached.
create function private.add_support_attachments(message_row public.support_messages, attachments jsonb)
returns void
language sql
set search_path to ''
as $$
  insert into public.support_message_attachments (
    message_id, thread_id, organization_id, position, file_name, mime_type, byte_size, object_key,
    has_thumbnail
  )
  select
    message_row.id,
    message_row.thread_id,
    message_row.organization_id,
    (file.ordinality - 1)::smallint,
    btrim(file.value ->> 'file_name'),
    file.value ->> 'mime_type',
    (file.value ->> 'byte_size')::bigint,
    file.value ->> 'object_key',
    coalesce((file.value ->> 'has_thumbnail')::boolean, false)
  from jsonb_array_elements(coalesce(attachments, '[]'::jsonb)) with ordinality as file (value, ordinality);
$$;

revoke all on function private.add_support_attachments(public.support_messages, jsonb) from public;

-- The stored message as every send function returns it, now with its files.
create or replace function private.support_message_json(message_row public.support_messages)
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
    'created_at', message_row.created_at,
    'attachments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', attachment.id,
            'file_name', attachment.file_name,
            'mime_type', attachment.mime_type,
            'byte_size', attachment.byte_size,
            'has_thumbnail', attachment.has_thumbnail
          )
          order by attachment.position
        )
        from public.support_message_attachments as attachment
        where attachment.message_id = message_row.id
      ),
      '[]'::jsonb
    )
  );
$$;

drop function public.start_support_thread(uuid, text, text, uuid);

create function public.start_support_thread(
  target_organization_id uuid,
  thread_topic text,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb
) returns jsonb
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
  if actor_id is null or not private.is_organization_member(target_organization_id) then
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

revoke all on function public.start_support_thread(uuid, text, text, uuid, jsonb) from public, anon;
grant execute on function public.start_support_thread(uuid, text, text, uuid, jsonb)
  to authenticated, service_role;

drop function public.send_support_message(uuid, uuid, text, uuid);

-- A member writes in a chat of this organization they can see. The same client id returns the first message.
create function public.send_support_message(
  target_organization_id uuid,
  target_thread_id uuid,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb
) returns jsonb
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
  if actor_id is null or not private.is_organization_member(target_organization_id) then
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

revoke all on function public.send_support_message(uuid, uuid, text, uuid, jsonb) from public, anon;
grant execute on function public.send_support_message(uuid, uuid, text, uuid, jsonb)
  to authenticated, service_role;

drop function public.reply_to_support_thread(uuid, text, text, uuid);

-- Uplift replies from the Support Inbox. Service role only: the route has already proved the platform
-- owner's session, and passes that login's email for the record. The name shown comes from the saved
-- support settings, never from the request. Runs as its owner so it can reach the shared private helpers.
create function public.reply_to_support_thread(
  target_thread_id uuid,
  actor_email text,
  message_body text,
  message_client_id uuid,
  message_attachments jsonb default '[]'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  clean_body text := btrim(coalesce(message_body, ''));
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  responder text;
  file_count smallint;
  thread_row public.support_threads;
  message_row public.support_messages;
begin
  if clean_email is null then
    raise exception 'An acting owner email is required to reply.' using errcode = 'check_violation';
  end if;

  if char_length(clean_body) > 4000 then
    raise exception 'A message can have up to 4000 characters.' using errcode = 'check_violation';
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

  file_count := private.check_support_attachments(thread_row.organization_id, message_attachments);

  if clean_body = '' and file_count = 0 then
    raise exception 'Write a reply or attach a file first.' using errcode = 'check_violation';
  end if;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_owner_email, sender_name, body, client_message_id,
    attachment_count
  )
  values (
    thread_row.id, thread_row.organization_id, 'uplift', clean_email, responder, clean_body,
    message_client_id, file_count
  )
  on conflict (thread_id, client_message_id) do nothing
  returning * into message_row;

  if message_row.id is null then
    select * into message_row
    from public.support_messages
    where thread_id = thread_row.id and client_message_id = message_client_id;
  else
    perform private.add_support_attachments(message_row, message_attachments);
  end if;

  return private.support_message_json(message_row);
end;
$$;

revoke all on function public.reply_to_support_thread(uuid, text, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.reply_to_support_thread(uuid, text, text, uuid, jsonb) to service_role;
