-- Pipeline upgrade A4: on-hold stages.
--
-- Product truth: docs/sales-pipeline-behavior-contract.md, "On hold is an ordinary custom follow-up stage,
-- not an outcome. Moving a card there requires a future Task." Jafar's choice, 2026-10-01: on hold is a
-- switch on any custom stage, not one ready-made stage. Industry reference: HubSpot's per-stage rules
-- (a stage names what a deal must have before it can be moved in) and Pipedrive's per-stage settings.
--
-- 1. pipeline_custom_stages.requires_future_task is the switch.
-- 2. save_pipeline_settings saves it with the rest of the stage list.
-- 3. pipeline_place_opportunity refuses a card with no open Task due after today.
-- 4. disable_pipeline_custom_stage holds a whole stage of cards to the same rule when their destination
--    is an on-hold stage.
--
-- Nothing here touches a card's outcome: a card on hold is an Open card in a custom column.

-- 1. The switch ----------------------------------------------------------------------------------------------

alter table public.pipeline_custom_stages
  add column requires_future_task boolean not null default false;

comment on column public.pipeline_custom_stages.requires_future_task is
  'An on-hold stage: a card may only be moved in while it has an open Task due after today. Checked on the way in by public.pipeline_place_opportunity and public.disable_pipeline_custom_stage, never afterwards.';

-- 2. Saving Settings → Pipeline -----------------------------------------------------------------------------

-- Each entry of `new_stages` may now carry "requires_future_task": true. Left out, it means false.
create or replace function public.save_pipeline_settings(
  target_organization_id uuid,
  expected_revision integer,
  new_detailed_assessment_stages boolean,
  new_stages jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  settings_row public.organization_settings;
  new_revision integer;
  editor_name text;
  editor_at timestamptz;
  updated_count integer;
  inserted_count integer;
  changed text[] := '{}';
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  if new_detailed_assessment_stages is null then
    raise exception 'Choose whether to show the detailed assessment stages.'
      using errcode = 'check_violation';
  end if;

  if new_stages is null or jsonb_typeof(new_stages) <> 'array' then
    raise exception 'The list of stages is missing.' using errcode = 'check_violation';
  end if;

  -- The settings row is the lock: two people saving the pipeline at once go one after the other.
  select * into settings_row
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  if settings_row.organization_id is null then
    raise exception 'Organization settings were not found.' using errcode = 'check_violation';
  end if;

  -- Somebody else saved first. The caller is told who and when, so it can offer to reload rather than
  -- silently overwrite a change it never saw.
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

  -- Jobber's documented ceiling. The list is every enabled stage, so its length is the count.
  if jsonb_array_length(new_stages) > 25 then
    raise exception 'A pipeline can have up to 25 custom stages.' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    group by item.stage ->> 'section', lower(btrim(item.stage ->> 'name'))
    having count(*) > 1
  ) then
    raise exception 'Two stages in the same section cannot share a name.'
      using errcode = 'check_violation';
  end if;

  -- Every id has to be one of this organization's enabled stages, named once, and still in its own
  -- section. Every enabled stage has to be named. Either failing means the page was out of date.
  if exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ->> 'id' is not null
    group by item.stage ->> 'id'
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(new_stages) as item(stage)
    where item.stage ->> 'id' is not null
      and not exists (
        select 1
        from public.pipeline_custom_stages as existing
        where existing.organization_id = target_organization_id
          and existing.disabled_at is null
          and existing.id = (item.stage ->> 'id')::uuid
          and existing.section = item.stage ->> 'section'
      )
  ) or exists (
    select 1
    from public.pipeline_custom_stages as existing
    where existing.organization_id = target_organization_id
      and existing.disabled_at is null
      and not exists (
        select 1
        from jsonb_array_elements(new_stages) as item(stage)
        where (item.stage ->> 'id')::uuid = existing.id
      )
  ) then
    raise exception 'These stages changed while you were editing. Refresh the page and try again.'
      using errcode = 'check_violation';
  end if;

  -- Renames are checked once the whole list is in place, so two stages may swap names in one save.
  set constraints public.pipeline_custom_stages_name_unique deferred;

  update public.pipeline_custom_stages as existing
  set
    name = btrim(item.stage ->> 'name'),
    after_stage = item.stage ->> 'after_stage',
    position = (item.ordinal - 1)::integer,
    requires_future_task = coalesce((item.stage ->> 'requires_future_task')::boolean, false)
  from jsonb_array_elements(new_stages) with ordinality as item(stage, ordinal)
  where existing.organization_id = target_organization_id
    and existing.disabled_at is null
    and existing.id = (item.stage ->> 'id')::uuid
    and (
      existing.name, existing.after_stage, existing.position, existing.requires_future_task
    ) is distinct from (
      btrim(item.stage ->> 'name'),
      item.stage ->> 'after_stage',
      (item.ordinal - 1)::integer,
      coalesce((item.stage ->> 'requires_future_task')::boolean, false)
    );
  get diagnostics updated_count = row_count;

  insert into public.pipeline_custom_stages (
    organization_id, section, name, after_stage, position, requires_future_task, created_by
  )
  select
    target_organization_id,
    item.stage ->> 'section',
    btrim(item.stage ->> 'name'),
    item.stage ->> 'after_stage',
    (item.ordinal - 1)::integer,
    coalesce((item.stage ->> 'requires_future_task')::boolean, false),
    (select auth.uid())
  from jsonb_array_elements(new_stages) with ordinality as item(stage, ordinal)
  where item.stage ->> 'id' is null
  order by item.ordinal;
  get diagnostics inserted_count = row_count;

  set constraints public.pipeline_custom_stages_name_unique immediate;

  update public.organization_settings
  set
    pipeline_detailed_assessment_stages = new_detailed_assessment_stages,
    pipeline_revision = pipeline_revision + 1,
    pipeline_updated_by = (select auth.uid()),
    pipeline_updated_at = now()
  where organization_id = target_organization_id
  returning pipeline_revision into new_revision;

  if new_detailed_assessment_stages
     is distinct from settings_row.pipeline_detailed_assessment_stages then
    changed := array_append(changed, 'pipeline_detailed_assessment_stages');
  end if;
  if updated_count + inserted_count > 0 then
    changed := array_append(changed, 'pipeline_custom_stages');
  end if;

  if cardinality(changed) > 0 then
    insert into public.organization_settings_audit (
      organization_id, section, changed_fields, actor_user_id
    )
    values (target_organization_id, 'pipeline', changed, (select auth.uid()));
  end if;

  return jsonb_build_object(
    'status', 'saved',
    'pipeline_revision', new_revision,
    'pipeline_detailed_assessment_stages', new_detailed_assessment_stages
  );
end;
$$;

-- 3. Placing a card --------------------------------------------------------------------------------------------

create or replace function public.pipeline_place_opportunity(
  target_opportunity_id uuid,
  target_custom_stage_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  stage_row public.pipeline_custom_stages;
  card_section text;
  organization_today date;
begin
  -- Locks the card, so a real action landing at the same moment is seen either wholly before or wholly
  -- after this move.
  opportunity_row := private.pipeline_lock_opportunity_for_drag(target_opportunity_id);

  if opportunity_row.outcome <> 'open' or opportunity_row.stage = 'request_closed' then
    raise exception 'This card is no longer on the board.' using errcode = 'check_violation';
  end if;

  if target_custom_stage_id is not null then
    -- Shared lock: switching the stage off waits for this move, and this move waits for that.
    select * into stage_row
    from public.pipeline_custom_stages as custom_stage
    where custom_stage.organization_id = opportunity_row.organization_id
      and custom_stage.id = target_custom_stage_id
      and custom_stage.disabled_at is null
    for share;

    if stage_row.id is null then
      raise exception 'That stage is no longer on the board. Refresh the page and try again.'
        using errcode = 'check_violation';
    end if;

    card_section := case
      when opportunity_row.stage in (
        'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
      ) then 'quote'
      else 'request'
    end;

    if stage_row.section <> card_section then
      if card_section = 'request' then
        raise exception
          'This is a request, so it can only go into a Requests stage. Convert it to a quote first.'
          using errcode = 'check_violation';
      end if;
      raise exception 'This is a quote, so it can only go into a Quotes stage.'
        using errcode = 'check_violation';
    end if;
  end if;

  if target_custom_stage_id is not distinct from opportunity_row.custom_stage_id then
    return jsonb_build_object(
      'applied', false,
      'stage', opportunity_row.stage,
      'custom_stage_id', opportunity_row.custom_stage_id
    );
  end if;

  -- An on-hold stage only takes a card somebody has promised to come back to: an open Task due after
  -- today, by the organization's own calendar. The card is locked and every Task write takes that same
  -- lock, so the Task seen here cannot be completed or removed before this move lands. Once the card is
  -- in, the rule has done its work — a Task falling due later does not push the card out.
  if stage_row.requires_future_task then
    organization_today := private.organization_today(opportunity_row.organization_id);

    if not exists (
      select 1
      from public.tasks as task
      where task.organization_id = opportunity_row.organization_id
        and task.opportunity_id = opportunity_row.id
        and task.status = 'open'
        and task.due_on > organization_today
    ) then
      raise exception 'Cards in “%” need a follow-up task with a future due date.', stage_row.name
        using errcode = 'check_violation', hint = 'needs_future_task';
    end if;
  end if;

  update public.opportunities
  set custom_stage_id = target_custom_stage_id
  where id = opportunity_row.id;

  return jsonb_build_object(
    'applied', true,
    'stage', opportunity_row.stage,
    'custom_stage_id', target_custom_stage_id
  );
end;
$$;

-- 4. Switching a stage off ----------------------------------------------------------------------------------

create or replace function public.disable_pipeline_custom_stage(
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
  organization_today date;
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

      -- An on-hold destination keeps its rule for a whole stage of cards as it does for one: every card
      -- arriving needs its own open Task due after today, or none of them move.
      if destination_row.requires_future_task then
        organization_today := private.organization_today(target_organization_id);

        if exists (
          select 1
          from public.opportunities as opportunity
          where opportunity.organization_id = target_organization_id
            and opportunity.custom_stage_id = target_stage_id
            and not exists (
              select 1
              from public.tasks as task
              where task.organization_id = opportunity.organization_id
                and task.opportunity_id = opportunity.id
                and task.status = 'open'
                and task.due_on > organization_today
            )
        ) then
          raise exception
            'Cards in “%” need a follow-up task with a future due date, and some of these cards have none. Choose another place for them.',
            destination_row.name
            using errcode = 'check_violation';
        end if;
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
