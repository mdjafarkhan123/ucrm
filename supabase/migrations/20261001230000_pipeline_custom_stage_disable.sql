-- Pipeline upgrade A3: switching a custom follow-up stage off.
--
-- Product truth: docs/sales-pipeline-behavior-contract.md, "Disable is the normal removal action".
-- Design: docs/adr/0004-pipeline-custom-stages-anchor-to-protected-stages.md. Industry reference: HubSpot
-- and Pipedrive both refuse to remove a stage that holds deals until the person says which stage those
-- deals go to, and move them all in the same step.
--
-- 1. pipeline_custom_stage_card_count tells Settings how many cards a stage holds, so it knows whether to
--    ask where they go.
-- 2. disable_pipeline_custom_stage moves every card out and switches the stage off in one transaction. The
--    row stays, with `disabled_at` set, so every earlier move in opportunity_stage_events still reads the
--    name the stage had.

-- 1. How many cards a stage holds ---------------------------------------------------------------------------

create function public.pipeline_custom_stage_card_count(
  target_organization_id uuid,
  target_stage_id uuid
) returns integer
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  -- Asked by the Settings form, whose reader may hold no Pipeline permission of their own.
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  -- An index-only count through opportunities_custom_stage_idx: only placed cards are in it.
  return (
    select count(*)::integer
    from public.opportunities as opportunity
    where opportunity.organization_id = target_organization_id
      and opportunity.custom_stage_id = target_stage_id
  );
end;
$$;

revoke all on function public.pipeline_custom_stage_card_count(uuid, uuid) from public, anon;
grant execute on function public.pipeline_custom_stage_card_count(uuid, uuid)
  to authenticated, service_role;

-- 2. Switching a stage off ----------------------------------------------------------------------------------

-- Where the stage's cards go is said in one of two ways: `move_cards_to_stage_id` names another custom
-- stage of the same section, or `move_cards_to_built_in` sends each card back to the built-in stage its
-- real work has it in. Saying neither is fine for an empty stage; for one holding cards the command changes
-- nothing and answers 'needs_destination' with the count, so nobody's cards are ever moved without them
-- having been asked.
create function public.disable_pipeline_custom_stage(
  target_organization_id uuid,
  target_stage_id uuid,
  expected_revision integer,
  move_cards_to_stage_id uuid default null,
  move_cards_to_built_in boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  settings_row public.organization_settings;
  stage_row public.pipeline_custom_stages;
  destination_row public.pipeline_custom_stages;
  editor_name text;
  editor_at timestamptz;
  card_count integer;
  new_revision integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if move_cards_to_stage_id is not null and coalesce(move_cards_to_built_in, false) then
    raise exception 'Choose one place for the cards to go.' using errcode = 'check_violation';
  end if;

  -- The settings row is the lock every Pipeline settings command takes first, so this and a Save of the
  -- stage list go one after the other.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  -- pipeline_place_opportunity holds this row `for share` while it puts a card in the stage, so no card
  -- can arrive between the move below and the stage going off.
  select * into stage_row
  from public.pipeline_custom_stages as custom_stage
  where custom_stage.organization_id = target_organization_id
    and custom_stage.id = target_stage_id
  for update;

  if stage_row.id is null then
    raise exception 'That stage could not be found. Refresh the page and try again.'
      using errcode = 'check_violation';
  end if;

  -- Already off: a repeated request, which is answered as done rather than as somebody else's change.
  if stage_row.disabled_at is not null then
    return jsonb_build_object(
      'status', 'disabled',
      'pipeline_revision', settings_row.pipeline_revision,
      'moved_count', 0
    );
  end if;

  if expected_revision is distinct from settings_row.pipeline_revision then
    select profile.full_name, settings_row.pipeline_updated_at into editor_name, editor_at
    from public.profiles as profile
    where profile.id = settings_row.pipeline_updated_by;

    return jsonb_build_object(
      'status', 'stale',
      'editor_name', editor_name,
      'edited_at', coalesce(editor_at, settings_row.updated_at)
    );
  end if;

  -- Every card in the stage, locked in id order so two commands that each take many cards cannot wait on
  -- each other in a circle. A card somebody is moving right now is waited for, then counted as it ends up.
  select count(*)::integer into card_count
  from (
    select opportunity.id
    from public.opportunities as opportunity
    where opportunity.organization_id = target_organization_id
      and opportunity.custom_stage_id = target_stage_id
    order by opportunity.id
    for update
  ) as held;

  if card_count > 0 then
    if move_cards_to_stage_id is null and not coalesce(move_cards_to_built_in, false) then
      return jsonb_build_object('status', 'needs_destination', 'card_count', card_count);
    end if;

    if move_cards_to_stage_id is not null then
      select * into destination_row
      from public.pipeline_custom_stages as custom_stage
      where custom_stage.organization_id = target_organization_id
        and custom_stage.id = move_cards_to_stage_id
        and custom_stage.id <> target_stage_id
        and custom_stage.disabled_at is null
      for share;

      if destination_row.id is null then
        raise exception 'The stage you chose is no longer on the board. Choose another place for these cards.'
          using errcode = 'check_violation';
      end if;

      if destination_row.section <> stage_row.section then
        raise exception 'Cards can only move to a stage in the same section.'
          using errcode = 'check_violation';
      end if;
    end if;

    -- One statement for all of them. The stage trigger restarts each card's time in its column, and the
    -- history trigger writes one move per card, under the person who switched the stage off.
    update public.opportunities as opportunity
    set custom_stage_id = move_cards_to_stage_id
    where opportunity.organization_id = target_organization_id
      and opportunity.custom_stage_id = target_stage_id;
  end if;

  update public.pipeline_custom_stages
  set disabled_at = now()
  where id = stage_row.id;

  update public.organization_settings
  set
    pipeline_revision = pipeline_revision + 1,
    pipeline_updated_by = (select auth.uid()),
    pipeline_updated_at = now()
  where organization_id = target_organization_id
  returning pipeline_revision into new_revision;

  insert into public.organization_settings_audit (
    organization_id, section, changed_fields, actor_user_id
  )
  values (
    target_organization_id, 'pipeline', array['pipeline_custom_stages'], (select auth.uid())
  );

  return jsonb_build_object(
    'status', 'disabled',
    'pipeline_revision', new_revision,
    'moved_count', card_count
  );
end;
$$;

revoke all on function public.disable_pipeline_custom_stage(uuid, uuid, integer, uuid, boolean)
  from public, anon;
grant execute on function public.disable_pipeline_custom_stage(uuid, uuid, integer, uuid, boolean)
  to authenticated, service_role;

comment on table public.pipeline_custom_stages is
  'Custom follow-up stages on the Sales Pipeline board. Members may read this table, never write it: changes arrive through public.save_pipeline_settings, and a stage is switched off by public.disable_pipeline_custom_stage, which keeps the row as the stage''s historical name.';
