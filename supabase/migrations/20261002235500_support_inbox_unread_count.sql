-- Client onboarding D2: how many Support Inbox conversations are waiting unread for Uplift, for the badge on
-- /jafar's Support menu item. A thread is unread for Uplift when the member wrote last, after Uplift's mark.
-- Capped at 100: the badge shows "99+" beyond that. Service role only.
--
-- No index: the comparison is between two columns of the same row, and the table holds at most one row per
-- team member (tens of thousands at full scale), read only by the single platform owner.
create function public.support_inbox_unread_count()
returns integer
language sql
stable
set search_path to 'pg_catalog', 'public'
as $$
  select count(*)::integer
  from (
    select 1
    from public.support_threads as thread
    where thread.last_message_sender_kind = 'member'
      and thread.last_message_at > coalesce(thread.uplift_last_read_at, '-infinity'::timestamptz)
    limit 100
  ) as unread;
$$;

revoke all on function public.support_inbox_unread_count() from public, anon, authenticated;
grant execute on function public.support_inbox_unread_count() to service_role;
