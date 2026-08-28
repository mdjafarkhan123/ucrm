-- The performance advisor flags review_resolved_by as an unindexed FK. Its only scan is auth.users
-- deletion cascading ON DELETE SET NULL across this table; a partial index keeps that bounded to the
-- handful of rows a guarded queue ever produces, at negligible write cost. Same call as 5B's
-- assigned_by index.
create index communication_inbound_messages_review_resolved_by_idx
  on public.communication_inbound_messages (review_resolved_by)
  where review_resolved_by is not null;
