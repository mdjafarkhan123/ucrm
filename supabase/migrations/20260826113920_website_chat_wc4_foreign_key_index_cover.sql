-- Correction to 20260904090000, from the performance-review gate on the WC4.1 migration.
--
-- 1. website_chat_capacity_reservations carried two foreign keys to the same fact: a single-column
--    one to the allowance period, and the composite one to its capacity bucket. The bucket already
--    references the period, so the single-column key adds nothing but an uncovered foreign key --
--    every period delete would scan the reservations table. Dropping it keeps the guarantee (a
--    period delete cascades to its bucket, and the bucket is restricted by its reservations) and
--    removes the index the advisor asked for.
--
-- 2. The message timeline index led with session_id, so the (organization_id, session_id) foreign
--    key had no covering index. Leading with organization_id covers the key and still serves the
--    timeline read, which always resolves its session -- and therefore its organization -- first.
--    One index instead of two.

alter table public.website_chat_capacity_reservations
  drop constraint website_chat_capacity_reservations_allowance_period_id_fkey;

drop index public.website_chat_messages_session_timeline_idx;

create index website_chat_messages_session_timeline_idx
  on public.website_chat_messages (organization_id, session_id, created_at desc, id desc);
