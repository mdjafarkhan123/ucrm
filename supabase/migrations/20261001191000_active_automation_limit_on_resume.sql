-- Package builder P14: the active-automations limit holds however a recipe becomes active.
--
-- Resuming a paused automation used to skip the limit, so a business could pause one, switch on another,
-- and resume the first to run more than its package allows. Resume now checks the limit from the single
-- authority (public.effective_automation_limits). Both activation and resume first take one lock per
-- organization, so two automations switched on at the same moment are counted one after the other.

CREATE OR REPLACE FUNCTION "public"."activate_automation_recipe_version"("p_organization_id" "uuid", "p_actor_user_id" "uuid", "p_recipe_id" "uuid", "p_expected_revision" integer, "p_schema_version" integer, "p_definition" "jsonb", "p_definition_hash" "text", "p_trigger_key" "text", "p_active_limit" integer, "p_idempotency_key" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  existing_receipt public.automation_draft_command_receipts%rowtype;
  recipe public.automation_recipes%rowtype;
  active_count integer;
  next_version_number integer;
  new_version_id uuid;
  next_revision integer;
  command_result jsonb;
  cutoff_sequence bigint;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'An expected revision is required.' using errcode = 'check_violation';
  end if;
  if p_definition is null or jsonb_typeof(p_definition) <> 'object' then
    raise exception 'A recipe definition is required.' using errcode = 'check_violation';
  end if;
  if p_trigger_key is null or char_length(btrim(p_trigger_key)) = 0 then
    raise exception 'A trigger is required to activate.' using errcode = 'check_violation';
  end if;
  if p_definition_hash is null or char_length(btrim(p_definition_hash)) = 0 then
    raise exception 'A definition hash is required.' using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('automation-recipe:' || p_recipe_id::text));

  select * into existing_receipt
  from public.automation_draft_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into recipe
  from public.automation_recipes
  where id = p_recipe_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That automation does not exist.' using errcode = 'no_data_found';
  end if;
  if recipe.status = 'archived' then
    raise exception 'An archived automation is read-only.' using errcode = 'restrict_violation';
  end if;
  if recipe.status not in ('draft', 'active', 'paused') then
    raise exception 'This automation cannot be activated right now.' using errcode = 'restrict_violation';
  end if;

  if recipe.draft_revision <> p_expected_revision then
    return jsonb_build_object(
      'stale', true,
      'current_revision', recipe.draft_revision,
      'draft_updated_at', recipe.draft_updated_at,
      'draft_updated_by', recipe.draft_updated_by
    );
  end if;
  if recipe.draft_definition is null then
    raise exception 'This automation has no draft to activate.' using errcode = 'check_violation';
  end if;

  if p_active_limit is not null and recipe.status <> 'active' then
    perform pg_advisory_xact_lock(hashtext('automation-active-limit:' || p_organization_id::text));
    select count(*) into active_count
    from public.automation_recipes
    where organization_id = p_organization_id and status = 'active';
    if active_count >= p_active_limit then
      raise exception
        'Activating this automation would pass your plan limit of % active automations. Pause or archive another one first.',
        p_active_limit
        using errcode = 'restrict_violation';
    end if;
  end if;

  select coalesce(max(version_number), 0) + 1 into next_version_number
  from public.automation_recipe_versions
  where recipe_id = p_recipe_id;

  select coalesce(max(seq), 0) into cutoff_sequence from private.automation_events;

  insert into public.automation_recipe_versions (
    recipe_id, organization_id, version_number, schema_version,
    definition, definition_hash, trigger_key, activation_cutoff_sequence,
    activation_cutoff_snapshot, activated_by
  ) values (
    p_recipe_id, p_organization_id, next_version_number, p_schema_version,
    p_definition, p_definition_hash, p_trigger_key, cutoff_sequence,
    pg_current_snapshot(), p_actor_user_id
  ) returning id into new_version_id;

  next_revision := recipe.draft_revision + 1;

  update public.automation_recipes
  set status = 'active',
      current_version_id = new_version_id,
      active_trigger_key = p_trigger_key,
      draft_definition = p_definition,
      draft_revision = next_revision
  where id = p_recipe_id and organization_id = p_organization_id;

  command_result := jsonb_build_object(
    'recipe_id', p_recipe_id,
    'status', 'active',
    'version_id', new_version_id,
    'version_number', next_version_number,
    'draft_revision', next_revision,
    'stale', false
  );

  insert into public.automation_draft_command_receipts (
    organization_id, idempotency_key, command, recipe_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'activate', p_recipe_id, command_result
  );

  return command_result;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."set_automation_recipe_lifecycle_state"("p_organization_id" "uuid", "p_actor_user_id" "uuid", "p_recipe_id" "uuid", "p_expected_revision" integer, "p_action" "text", "p_idempotency_key" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  existing_receipt public.automation_draft_command_receipts%rowtype;
  recipe public.automation_recipes%rowtype;
  target_status text;
  action_label text;
  allowed_sources text[];
  next_revision integer;
  command_result jsonb;
  active_limit record;
  active_count integer;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'An expected revision is required.' using errcode = 'check_violation';
  end if;

  case p_action
    when 'pause' then
      target_status := 'paused'; action_label := 'paused'; allowed_sources := array['active'];
    when 'resume' then
      target_status := 'active'; action_label := 'resumed'; allowed_sources := array['paused'];
    when 'archive' then
      target_status := 'archived'; action_label := 'archived'; allowed_sources := array['draft', 'active', 'paused'];
    when 'restore' then
      target_status := 'draft'; action_label := 'restored'; allowed_sources := array['archived'];
    else raise exception 'Unknown lifecycle action.' using errcode = 'check_violation';
  end case;

  perform pg_advisory_xact_lock(hashtext('automation-recipe:' || p_recipe_id::text));

  select * into existing_receipt
  from public.automation_draft_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into recipe
  from public.automation_recipes
  where id = p_recipe_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That automation does not exist.' using errcode = 'no_data_found';
  end if;

  if recipe.draft_revision <> p_expected_revision then
    return jsonb_build_object(
      'stale', true,
      'current_revision', recipe.draft_revision,
      'draft_updated_at', recipe.draft_updated_at,
      'draft_updated_by', recipe.draft_updated_by
    );
  end if;

  if not (recipe.status = any(allowed_sources)) then
    raise exception 'This automation cannot be % from its current state.', action_label
      using errcode = 'restrict_violation';
  end if;

  if p_action = 'restore' and recipe.draft_definition is null then
    raise exception 'This automation has no saved draft to restore.' using errcode = 'check_violation';
  end if;

  if p_action = 'resume' then
    select limits.value, limits.is_unlimited, limits.state into active_limit
    from public.effective_automation_limits(p_organization_id) as limits
    where limits.limit_key = 'automation_active_recipes';
    if active_limit.state = 'not_included' then
      raise exception 'Automations are not part of your plan.' using errcode = 'restrict_violation';
    end if;
    if not active_limit.is_unlimited and active_limit.value is not null then
      perform pg_advisory_xact_lock(hashtext('automation-active-limit:' || p_organization_id::text));
      select count(*) into active_count
      from public.automation_recipes
      where organization_id = p_organization_id and status = 'active';
      if active_count >= active_limit.value then
        raise exception
          'Resuming this automation would pass your plan limit of % active automations. Pause or archive another one first.',
          active_limit.value
          using errcode = 'restrict_violation';
      end if;
    end if;
  end if;

  next_revision := recipe.draft_revision + 1;

  if p_action = 'restore' then
    update public.automation_recipes
    set status = 'draft',
        current_version_id = null,
        active_trigger_key = null,
        draft_revision = next_revision
    where id = p_recipe_id and organization_id = p_organization_id;
  else
    update public.automation_recipes
    set status = target_status,
        draft_revision = next_revision
    where id = p_recipe_id and organization_id = p_organization_id;
  end if;

  command_result := jsonb_build_object(
    'recipe_id', p_recipe_id,
    'status', target_status,
    'draft_revision', next_revision,
    'stale', false
  );

  insert into public.automation_draft_command_receipts (
    organization_id, idempotency_key, command, recipe_id, result
  ) values (
    p_organization_id, p_idempotency_key, p_action, p_recipe_id, command_result
  );

  return command_result;
end;
$$;
