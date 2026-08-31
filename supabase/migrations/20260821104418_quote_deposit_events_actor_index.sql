-- The advisor flags actor_user_id's foreign key as uncovered, the same shape quote_decisions already fixed:
-- without this, removing a user would seq-scan every deposit event looking for rows to null out.
create index quote_deposit_events_actor_idx
  on public.quote_deposit_events(actor_user_id)
  where actor_user_id is not null;
