-- Client onboarding D5b: one email when a support reply has gone unseen for 3 minutes.
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §7 Follow-up — when an Uplift reply has
-- gone unseen for 3 minutes, the chat's starter and added teammates who have not read it get one email, and no
-- further email for that chat until they open it. Owners and admins who merely can see the chat are not
-- emailed. The same rule emails Uplift when a member's message has gone unseen in the Support Inbox.
-- Industry reference: Intercom's "unread conversation" email (sent after a short delay, once per unseen
-- stretch) and Zendesk's follow-up notification.
--
-- Shape: a due-reminder table, the standard timer-table pattern. A reply writes one row per person who should
-- see it, due 3 minutes later; opening the chat (the existing read marks) deletes that person's row. The
-- email worker's once-a-minute wake sends what is still due, through the durable outbox, and stamps the row.
-- A stamped row stays until the person opens the chat, which is what stops a second email. The table holds
-- only open reminders, so the wake's work grows with unseen replies, never with total messages.

-- 1. The reminders -----------------------------------------------------------------------------------------

create table public.support_unseen_reply_reminders (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  -- The team member to email. Null means Uplift.
  recipient_user_id uuid references auth.users (id) on delete cascade,
  -- The earliest message this person has not seen; the email lists the unseen messages from here on.
  first_unseen_at timestamptz not null,
  due_at timestamptz not null,
  -- When the email was queued. The row then stays, silencing this chat, until the person opens it.
  emailed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint support_unseen_reply_reminders_due_check check (due_at >= first_unseen_at)
);

comment on table public.support_unseen_reply_reminders is
  'One open "you have an unseen reply" reminder per person per support chat (null recipient = Uplift). Written and cleared only by triggers on support messages and read marks; sent by the email worker. Service role only.';

-- One reminder per person per chat, so later replies join the stretch already waiting.
create unique index support_unseen_reply_reminders_member_key
  on public.support_unseen_reply_reminders (thread_id, recipient_user_id)
  where recipient_user_id is not null;

create unique index support_unseen_reply_reminders_uplift_key
  on public.support_unseen_reply_reminders (thread_id)
  where recipient_user_id is null;

-- The wake's only read: reminders still waiting to be sent, oldest due first.
create index support_unseen_reply_reminders_due_idx
  on public.support_unseen_reply_reminders (due_at)
  where emailed_at is null;

create index support_unseen_reply_reminders_organization_id_idx
  on public.support_unseen_reply_reminders (organization_id);

create index support_unseen_reply_reminders_recipient_user_id_idx
  on public.support_unseen_reply_reminders (recipient_user_id)
  where recipient_user_id is not null;

alter table public.support_unseen_reply_reminders enable row level security;
revoke all on table public.support_unseen_reply_reminders from public, anon, authenticated;
grant select, insert, update, delete on table public.support_unseen_reply_reminders to service_role;

-- 2. A new message starts a reminder -----------------------------------------------------------------------

-- An Uplift reply reminds the chat's starter and every added teammate; a member's message reminds Uplift.
-- An existing reminder means that person is already in an unseen stretch, so nothing changes.
create function private.remind_of_unseen_support_message()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.sender_kind = 'uplift' then
    insert into public.support_unseen_reply_reminders
      (thread_id, organization_id, recipient_user_id, first_unseen_at, due_at)
    select new.thread_id, new.organization_id, person.user_id, new.created_at, new.created_at + interval '3 minutes'
    from (
      select thread.started_by_user_id as user_id
      from public.support_threads as thread
      where thread.id = new.thread_id and thread.started_by_user_id is not null
      union
      select participant.user_id
      from public.support_thread_participants as participant
      where participant.thread_id = new.thread_id
    ) as person
    on conflict (thread_id, recipient_user_id) where recipient_user_id is not null do nothing;
  elsif new.sender_kind = 'member' then
    insert into public.support_unseen_reply_reminders
      (thread_id, organization_id, recipient_user_id, first_unseen_at, due_at)
    values (new.thread_id, new.organization_id, null, new.created_at, new.created_at + interval '3 minutes')
    on conflict (thread_id) where recipient_user_id is null do nothing;
  end if;

  return null;
end;
$$;

create trigger support_messages_remind_of_unseen
  after insert on public.support_messages
  for each row execute function private.remind_of_unseen_support_message();

-- 3. Opening the chat clears it ----------------------------------------------------------------------------

-- A member's read mark moved (opening the chat, or writing in it). Their reminder ends; if a reply arrived
-- after the point they read to, a fresh reminder starts from that reply, so it is never silently lost.
create function private.clear_member_unseen_reply_reminder()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  next_unseen_at timestamptz;
  thread_organization_id uuid;
begin
  delete from public.support_unseen_reply_reminders
  where thread_id = new.thread_id and recipient_user_id = new.user_id;

  select thread.organization_id into thread_organization_id
  from public.support_threads as thread
  where thread.id = new.thread_id
    and (
      thread.started_by_user_id = new.user_id
      or exists (
        select 1 from public.support_thread_participants as participant
        where participant.thread_id = new.thread_id and participant.user_id = new.user_id
      )
    );
  if thread_organization_id is null then
    return null;
  end if;

  select min(message.created_at) into next_unseen_at
  from public.support_messages as message
  where message.thread_id = new.thread_id
    and message.sender_kind = 'uplift'
    and message.created_at > new.last_read_at;

  if next_unseen_at is not null then
    insert into public.support_unseen_reply_reminders
      (thread_id, organization_id, recipient_user_id, first_unseen_at, due_at)
    values (new.thread_id, thread_organization_id, new.user_id, next_unseen_at, next_unseen_at + interval '3 minutes')
    on conflict (thread_id, recipient_user_id) where recipient_user_id is not null do nothing;
  end if;

  return null;
end;
$$;

create trigger support_thread_reads_clear_unseen_reminder
  after insert or update of last_read_at on public.support_thread_reads
  for each row execute function private.clear_member_unseen_reply_reminder();

-- Uplift's read mark moved (opening the chat in the Support Inbox, or replying). Same rule for Uplift.
create function private.clear_uplift_unseen_reply_reminder()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  next_unseen_at timestamptz;
begin
  delete from public.support_unseen_reply_reminders
  where thread_id = new.id and recipient_user_id is null;

  select min(message.created_at) into next_unseen_at
  from public.support_messages as message
  where message.thread_id = new.id
    and message.sender_kind = 'member'
    and message.created_at > new.uplift_last_read_at;

  if next_unseen_at is not null then
    insert into public.support_unseen_reply_reminders
      (thread_id, organization_id, recipient_user_id, first_unseen_at, due_at)
    values (new.id, new.organization_id, null, next_unseen_at, next_unseen_at + interval '3 minutes')
    on conflict (thread_id) where recipient_user_id is null do nothing;
  end if;

  return null;
end;
$$;

create trigger support_threads_clear_unseen_reminder
  after update of uplift_last_read_at on public.support_threads
  for each row
  when (new.uplift_last_read_at is distinct from old.uplift_last_read_at and new.uplift_last_read_at is not null)
  execute function private.clear_uplift_unseen_reply_reminder();

revoke all on function private.remind_of_unseen_support_message() from public, anon, authenticated;
revoke all on function private.clear_member_unseen_reply_reminder() from public, anon, authenticated;
revoke all on function private.clear_uplift_unseen_reply_reminder() from public, anon, authenticated;

-- 4. What the email worker sends ---------------------------------------------------------------------------

-- Up to `batch_size` reminders that are due, each with everything its email needs: the recipient, the
-- business, the chat's topic, and the latest unseen messages (at most 5, newest last, with a count of the
-- rest). A reminder whose person can no longer see the chat — removed from it, left the team, a closed
-- business — or who opened it meanwhile is deleted here instead of returned. Service role only.
create function public.due_support_unseen_reply_emails(batch_size integer)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  result jsonb;
begin
  with due as (
    select reminder.*
    from public.support_unseen_reply_reminders as reminder
    where reminder.emailed_at is null and reminder.due_at <= now()
    order by reminder.due_at
    limit least(greatest(batch_size, 1), 200)
  ),
  checked as (
    select
      due.*,
      thread.topic,
      thread.started_by_user_id,
      organization.name as organization_name,
      member_user.email as member_email,
      case
        when due.recipient_user_id is null then
          coalesce(thread.uplift_last_read_at, '-infinity') < due.first_unseen_at
        else
          organization.lifecycle_status in ('active', 'suspended', 'pending_closure')
          and member_user.email is not null
          and exists (
            select 1 from public.organization_members as membership
            where membership.organization_id = due.organization_id
              and membership.user_id = due.recipient_user_id
              and membership.status = 'active'
          )
          and (
            thread.started_by_user_id = due.recipient_user_id
            or exists (
              select 1 from public.support_thread_participants as participant
              where participant.thread_id = due.thread_id and participant.user_id = due.recipient_user_id
            )
          )
          and coalesce((
            select read_mark.last_read_at from public.support_thread_reads as read_mark
            where read_mark.thread_id = due.thread_id and read_mark.user_id = due.recipient_user_id
          ), '-infinity') < due.first_unseen_at
      end as still_unseen
    from due
    join public.support_threads as thread on thread.id = due.thread_id
    join public.organizations as organization on organization.id = due.organization_id
    left join auth.users as member_user on member_user.id = due.recipient_user_id
  ),
  dropped as (
    delete from public.support_unseen_reply_reminders as reminder
    using checked
    where reminder.id = checked.id and not checked.still_unseen
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', checked.id,
    'thread_id', checked.thread_id,
    'organization_id', checked.organization_id,
    'organization_name', checked.organization_name,
    'recipient_user_id', checked.recipient_user_id,
    'recipient_email', checked.member_email,
    'recipient_name', case when checked.recipient_user_id is null then null
      else private.support_member_name(checked.recipient_user_id) end,
    'started_by_name', case when checked.started_by_user_id is null then null
      else private.support_member_name(checked.started_by_user_id) end,
    'topic', checked.topic,
    'first_unseen_at', checked.first_unseen_at,
    'unseen_count', unseen.total,
    'messages', unseen.latest
  ) order by checked.due_at), '[]'::jsonb)
  into result
  from checked
  cross join lateral (
    select
      (select count(*) from public.support_messages as message
        where message.thread_id = checked.thread_id
          and message.sender_kind = case when checked.recipient_user_id is null then 'member' else 'uplift' end
          and message.created_at >= checked.first_unseen_at) as total,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'sender_name', latest.sender_name,
          'body', latest.body,
          'attachment_count', latest.attachment_count,
          'created_at', latest.created_at
        ) order by latest.created_at, latest.id)
        from (
          select message.sender_name, message.body, message.attachment_count, message.created_at, message.id
          from public.support_messages as message
          where message.thread_id = checked.thread_id
            and message.sender_kind = case when checked.recipient_user_id is null then 'member' else 'uplift' end
            and message.created_at >= checked.first_unseen_at
          order by message.created_at desc, message.id desc
          limit 5
        ) as latest
      ), '[]'::jsonb) as latest
  ) as unseen
  where checked.still_unseen;

  return result;
end;
$$;

-- The email for this reminder is queued: stamp it, unless the person opened the chat in the meantime (the
-- row is then gone or restarted, and the stamp must not silence the new stretch).
create function public.mark_support_unseen_reply_emailed(reminder_id uuid, reminder_first_unseen_at timestamptz)
returns void
language sql
security definer
set search_path to ''
as $$
  update public.support_unseen_reply_reminders
  set emailed_at = now()
  where id = reminder_id
    and first_unseen_at = reminder_first_unseen_at
    and emailed_at is null;
$$;

revoke all on function public.due_support_unseen_reply_emails(integer) from public, anon, authenticated;
revoke all on function public.mark_support_unseen_reply_emailed(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.due_support_unseen_reply_emails(integer) to service_role;
grant execute on function public.mark_support_unseen_reply_emailed(uuid, timestamptz) to service_role;
