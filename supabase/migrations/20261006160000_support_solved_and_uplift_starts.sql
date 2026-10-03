-- Client onboarding D5a: Uplift marks a support chat Solved, writing reopens it, and Uplift may start a chat.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7 "Follow-up" (Jafar, 2026-10-03).
-- Industry reference: Intercom's and Zendesk's support inboxes — only the support team closes a
-- conversation, the customer writing again reopens it, and the team may send the first message.
--
-- 1. support_threads gains `status` (open or solved) and `opened_by` (member or uplift).
-- 2. Any message, from either side, reopens a solved chat. Quietly: the message itself shows the activity.
-- 3. Uplift marks a chat Solved or reopens it, leaving a grey line.
-- 4. Uplift starts a chat with a chosen active team member. The chat is that member's, as if they had
--    started it, so who-sees-what, the badge and live updates all treat it the same way.

-- 1. Status and who opened the chat -------------------------------------------------------------------------

alter table public.support_threads
  add column status text not null default 'open',
  add column solved_at timestamptz,
  add column opened_by text not null default 'member',
  add constraint support_threads_status_check check (
    status in ('open', 'solved') and ((status = 'solved') = (solved_at is not null))
  ),
  add constraint support_threads_opened_by_check check (opened_by in ('member', 'uplift'));

comment on column public.support_threads.status is
  'open or solved. Only Uplift marks a chat solved; any message reopens it.';
comment on column public.support_threads.opened_by is
  'Who sent the first message: the member in started_by_user_id, or Uplift writing to that member.';

-- The Support Inbox shows open chats unless filtered to Solved, newest activity first, with or without a
-- topic. The unfiltered "every status" reads keep support_threads_inbox_idx and
-- support_threads_inbox_topic_idx.
create index support_threads_inbox_status_idx
  on public.support_threads (status, last_message_at desc, id desc);

create index support_threads_inbox_topic_status_idx
  on public.support_threads (topic, status, last_message_at desc, id desc);

-- Finding the chat a retried Uplift-started first message already made.
create index support_messages_uplift_client_id_idx
  on public.support_messages (organization_id, client_message_id)
  where sender_kind = 'uplift';

-- 2. Writing reopens -----------------------------------------------------------------------------------------

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
      status = 'open',
      solved_at = null,
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

-- 3. Solved and reopened by Uplift --------------------------------------------------------------------------

-- Service role only: the route has already proved the platform owner's session. Returns false when the chat
-- already had that status, so a repeated click posts no second line.
create function public.set_support_thread_status_by_uplift(target_thread_id uuid, new_status text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  thread_row public.support_threads;
begin
  if new_status is null or new_status not in ('open', 'solved') then
    raise exception 'Choose open or solved.' using errcode = 'check_violation';
  end if;

  select * into thread_row from public.support_threads where id = target_thread_id for update;
  if thread_row.id is null then
    raise exception 'That conversation no longer exists.' using errcode = 'no_data_found';
  end if;

  if thread_row.status = new_status then
    return false;
  end if;

  update public.support_threads
  set status = new_status,
      solved_at = case when new_status = 'solved' then now() end
  where id = thread_row.id;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_name, body, client_message_id
  )
  values (
    thread_row.id,
    thread_row.organization_id,
    'system',
    'Uplift Support',
    case
      when new_status = 'solved' then 'Uplift Support marked this chat as solved.'
      else 'Uplift Support reopened this chat.'
    end,
    gen_random_uuid()
  );

  return true;
end;
$$;

revoke all on function public.set_support_thread_status_by_uplift(uuid, text)
  from public, anon, authenticated;
grant execute on function public.set_support_thread_status_by_uplift(uuid, text) to service_role;

-- 4. Uplift starts a chat ------------------------------------------------------------------------------------

-- Service role only, like public.reply_to_support_thread: the route has proved the owner session and passes
-- that login's email for the record. The chat belongs to `target_user_id`, who must be an active member of the
-- organization. The same client id returns the first message instead of making a second chat.
create function public.start_support_thread_by_uplift(
  target_organization_id uuid,
  target_user_id uuid,
  thread_topic text,
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
  clean_topic text := coalesce(nullif(btrim(thread_topic), ''), 'other');
  responder text;
  file_count smallint;
  thread_id_value uuid;
  message_row public.support_messages;
begin
  if clean_email is null then
    raise exception 'An acting owner email is required to write.' using errcode = 'check_violation';
  end if;

  if message_client_id is null then
    raise exception 'The message is missing its identifier.' using errcode = 'check_violation';
  end if;

  if char_length(clean_body) > 4000 then
    raise exception 'A message can have up to 4000 characters.' using errcode = 'check_violation';
  end if;

  if clean_topic not in ('setup', 'website', 'google_profile', 'crm', 'billing', 'other') then
    raise exception 'Choose one of the listed topics.' using errcode = 'check_violation';
  end if;

  select nullif(responder_name, '') into responder
  from public.platform_support_settings
  where id = true;

  if responder is null then
    raise exception 'Add the name clients see on your replies before sending one.'
      using errcode = 'check_violation';
  end if;

  if target_user_id is null or not exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = target_user_id
      and membership.status = 'active'
  ) then
    raise exception 'Choose someone who is on this business''s team.' using errcode = 'check_violation';
  end if;

  file_count := private.check_support_attachments(target_organization_id, message_attachments);

  if clean_body = '' and file_count = 0 then
    raise exception 'Write a message or attach a file first.' using errcode = 'check_violation';
  end if;

  -- Two attempts of the same first message, arriving together, take turns here; the second then finds the
  -- chat the first one made.
  perform pg_advisory_xact_lock(hashtextextended('support-start-uplift:' || message_client_id::text, 0));

  select * into message_row
  from public.support_messages
  where organization_id = target_organization_id
    and client_message_id = message_client_id
    and sender_kind = 'uplift';

  if message_row.id is not null then
    return private.support_message_json(message_row);
  end if;

  insert into public.support_threads (organization_id, started_by_user_id, topic, opened_by)
  values (target_organization_id, target_user_id, clean_topic, 'uplift')
  returning id into thread_id_value;

  insert into public.support_messages (
    thread_id, organization_id, sender_kind, sender_owner_email, sender_name, body, client_message_id,
    attachment_count
  )
  values (
    thread_id_value, target_organization_id, 'uplift', clean_email, responder, clean_body,
    message_client_id, file_count
  )
  returning * into message_row;

  perform private.add_support_attachments(message_row, message_attachments);

  return private.support_message_json(message_row);
end;
$$;

revoke all on function public.start_support_thread_by_uplift(uuid, uuid, text, text, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.start_support_thread_by_uplift(uuid, uuid, text, text, text, uuid, jsonb)
  to service_role;
