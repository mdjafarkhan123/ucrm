-- Pipeline part D1: Undo for a custom-stage placement keeps the card's time in stage.
--
-- 20261002210000 left a placement's Undo as "another placement". The browser check showed what that
-- costs: a card fourteen days in Awaiting response, slipped into a follow-up stage and taken straight
-- back, read "in this stage for less than an hour". An Undo puts the card back as it was, so this one
-- restores `stage_entered_at` too, through the same per-transaction settings private.opportunity_apply_stage
-- already reads for pipeline_undo_move. A placement never touches `progress_at`, so there is nothing else
-- to put back.
--
-- The same gate as pipeline_undo_move: the placement named must still be the last thing that happened to
-- the card, made by this same person within the last two minutes. The card returns through
-- public.pipeline_place_opportunity, the one function that places cards, so a stage switched off since, or
-- an on-hold stage whose Task has gone, refuses in that function's own words.

create function public.pipeline_undo_placement(
  target_opportunity_id uuid,
  undone_to_custom_stage_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  event_row public.opportunity_stage_events;
  result jsonb;
  changed constant text := 'This move can no longer be undone because the card has changed since.';
begin
  opportunity_row := private.pipeline_lock_opportunity_for_drag(target_opportunity_id);

  select * into event_row
  from public.opportunity_stage_events as event
  where event.organization_id = opportunity_row.organization_id
    and event.opportunity_id = opportunity_row.id
  order by event.occurred_at desc
  limit 1;

  if opportunity_row.outcome <> 'open'
     or opportunity_row.custom_stage_id is distinct from undone_to_custom_stage_id
     or event_row.id is null
     or event_row.from_stage is distinct from event_row.to_stage
     or event_row.to_stage <> opportunity_row.stage
     or event_row.to_custom_stage_id is distinct from undone_to_custom_stage_id
     or event_row.from_custom_stage_id is not distinct from event_row.to_custom_stage_id
     or event_row.actor_user_id is distinct from (select auth.uid())
     or event_row.occurred_at < now() - interval '2 minutes'
     or event_row.from_stage_entered_at is null then
    raise exception '%', changed using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.undo_opportunity_id', opportunity_row.id::text, true);
  perform set_config('pipeline.undo_stage_entered_at', event_row.from_stage_entered_at::text, true);

  result := public.pipeline_place_opportunity(opportunity_row.id, event_row.from_custom_stage_id);

  perform set_config('pipeline.undo_opportunity_id', '', true);

  return jsonb_build_object(
    'stage', result->'stage',
    'custom_stage_id', result->'custom_stage_id'
  );
end;
$$;

revoke all on function public.pipeline_undo_placement(uuid, uuid) from public, anon;
grant execute on function public.pipeline_undo_placement(uuid, uuid) to authenticated, service_role;
