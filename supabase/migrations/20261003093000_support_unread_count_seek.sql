-- Client onboarding D2 follow-up: the member's unread count seeks straight to the messages after their read
-- mark. The first version joined the mark in, so Postgres walked the whole thread and filtered; a member's
-- one thread lives for years, so that walk would grow forever. Reading the mark first lets the count use
-- support_messages_thread_idx (thread_id, created_at desc) as a range: work grows with unread messages only.
create or replace function public.support_unread_count(target_organization_id uuid)
returns integer
language sql
stable
security invoker
set search_path to 'pg_catalog', 'public'
as $$
  select count(*)::integer
  from (
    select 1
    from public.support_threads as thread
    cross join lateral (
      select coalesce(
        (
          select read_mark.last_read_at
          from public.support_thread_reads as read_mark
          where read_mark.thread_id = thread.id and read_mark.user_id = (select auth.uid())
        ),
        '-infinity'::timestamptz
      ) as last_read_at
    ) as mark
    join public.support_messages as message
      on message.thread_id = thread.id and message.created_at > mark.last_read_at
    where thread.organization_id = target_organization_id
      and thread.started_by_user_id = (select auth.uid())
      and message.sender_user_id is distinct from (select auth.uid())
    limit 100
  ) as unread;
$$;
