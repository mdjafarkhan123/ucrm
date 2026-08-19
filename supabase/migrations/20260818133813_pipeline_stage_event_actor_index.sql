-- The actor foreign key had no covering index, so deleting an auth user would sequentially scan the
-- whole history table. History only grows, so that scan gets worse forever. Partial, because most
-- rows are written by triggers during a signed-in session and system-written rows have no actor.
create index opportunity_stage_events_actor_idx
  on public.opportunity_stage_events(actor_user_id)
  where actor_user_id is not null;
