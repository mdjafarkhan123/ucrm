-- Client onboarding D2 follow-up: the member's unread count in two steps. Measured after
-- 20261003093000: Postgres still folded the read mark back into the message scan as a per-row filter, so a
-- long thread was still walked from end to end. Reading the thread and the mark into variables first makes
-- the count a plain range on support_messages_thread_idx (thread_id, created_at desc): its work grows with
-- unread messages only, never with the thread's age.
create or replace function public.support_unread_count(target_organization_id uuid)
returns integer
language plpgsql
stable
security invoker
set search_path to 'pg_catalog', 'public'
as $$
declare
  actor_id uuid := (select auth.uid());
  thread_id_value uuid;
  mark timestamptz;
begin
  select thread.id into thread_id_value
  from public.support_threads as thread
  where thread.organization_id = target_organization_id
    and thread.started_by_user_id = actor_id;

  if thread_id_value is null then
    return 0;
  end if;

  select read_mark.last_read_at into mark
  from public.support_thread_reads as read_mark
  where read_mark.thread_id = thread_id_value and read_mark.user_id = actor_id;

  return (
    select count(*)::integer
    from (
      select 1
      from public.support_messages as message
      where message.thread_id = thread_id_value
        and message.created_at > coalesce(mark, '-infinity'::timestamptz)
        and message.sender_user_id is distinct from actor_id
      limit 100
    ) as unread
  );
end;
$$;
