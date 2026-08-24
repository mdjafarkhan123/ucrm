-- Team & access, part 3A, item 4, performance review.
--
-- Measured on 20,000 synthetic history rows in a rolled-back transaction. Two of the three plans were
-- already right: the organization history list uses (organization_id, created_at desc) with no sort step,
-- and one member's history used its own index. The third was not.
--
-- Deleting an Auth account makes Postgres check every foreign key pointing at auth.users. With no index on
-- actor_user_id or a usable one on subject_user_id, that check planned as:
--
--   Seq Scan on organization_member_access_events (actual time=1.500..3.435 rows=100)
--     Rows Removed by Filter: 19900
--
-- 3.5 ms over 20k rows, and this table only ever grows -- at ten million rows that is a multi-second scan
-- holding a pooled connection, twice, for every account 3B's orphan worker cleans up. The other two foreign
-- keys are left unindexed on purpose: member_access_event_shapes is reference data with no write grant at
-- all, and invitation rows are retained forever by the Part 3A invariants table, so neither parent has a
-- delete path that could trigger the same scan.
--
-- subject_user_id gets column order rather than a second index. The old index led with organization_id,
-- which the page query supplies but the foreign-key check does not. Leading with subject_user_id serves
-- both: the check matches on the first column, and the member history page still matches both equality
-- columns and reads created_at in order.

drop index if exists public.organization_member_access_events_subject_user_idx;

create index organization_member_access_events_subject_user_idx
  on public.organization_member_access_events (subject_user_id, organization_id, created_at desc)
  where subject_user_id is not null;

create index organization_member_access_events_actor_user_idx
  on public.organization_member_access_events (actor_user_id)
  where actor_user_id is not null;
