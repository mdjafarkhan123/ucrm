-- The performance advisor flagged assigned_by (audit-only: who made the assignment) as an unindexed FK.
-- Partial, like opportunities_owner_idx, because most rows never need it looked up by assigned_by and a
-- null assigned_by (e.g. a system-made assignment) is never the answer to that lookup either.
create index communication_conversation_assignments_assigned_by_idx
  on public.communication_conversation_assignments (assigned_by)
  where assigned_by is not null;
