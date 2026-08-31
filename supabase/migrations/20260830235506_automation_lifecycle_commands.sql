-- Contractor Settings Part 6C, slice 3a (backend): atomic recipe lifecycle commands.
--
-- docs/automation-behavior-contract.md § Recipe definition and lifecycle ("Activate freezes a new version
-- after review ... Pausing stops new enrollment ... Resume continues ... Archiving ... Archived recipes are
-- read-only ... Restore creates a new draft; it does not reactivate an old version") and § Entitlement,
-- permissions, and commands ("State-changing commands also enforce expected revision, organization ownership,
-- entitlement, permission, suspension, and an idempotency key in the atomic database command"). Also
-- § Entitlement: "An organization may save drafts above its active limits but cannot activate them."
--
-- 6C is real-but-inert: activation FREEZES an immutable version and marks the recipe live, but no events,
-- enrollments, or customer effects exist yet, so activation_cutoff_sequence stays NULL until 6D gives it
-- meaning. Every write stays SECURITY DEFINER executed by service_role after the route has already resolved
-- entitlement, permission, and authority (src/lib/server/access/automation.ts). Definitions are validated and
-- canonicalized on the server (src/lib/server/automation/definition.ts) and passed in already validated; the
-- database stores, never trusts.
--
-- draft_revision is the aggregate optimistic-lock token: every state change bumps it and every command guards
-- the caller-supplied expected_revision against it, so a stale actor gets the newer editor/time and never
-- clobbers concurrent work (mirrors save_automation_recipe_draft).

-- 1. Broaden the shared idempotency receipts to cover the lifecycle commands. ---------------------------
alter table public.automation_draft_command_receipts
  drop constraint automation_draft_command_receipts_command_check;

alter table public.automation_draft_command_receipts
  add constraint automation_draft_command_receipts_command_check
  check (command in (
    'create_draft', 'save_draft',
    'activate', 'pause', 'resume', 'archive', 'restore', 'duplicate'
  ));

comment on table public.automation_draft_command_receipts is
  'Private idempotency receipts for automation draft AND lifecycle commands. A retried submit replays its '
  'stored result. Retained at least 24h; batched indexed cleanup is owned by 6E.';

-- 2. Activate: freeze an immutable version from the reviewed draft and mark the recipe live. ------------
-- The route validates draft_definition at activation strictness (>=1 step, >=1 stop) and computes the
-- canonical JSON + hash + trigger key; they are passed in. The command re-checks the revision under the row
-- lock, so the canonical definition the route computed still describes the locked draft (a concurrent save
-- would have bumped the revision, tripping the stale return). p_active_limit is the effective active-recipes
-- ceiling (NULL = unlimited); it is enforced ONLY when the recipe is not already active, so re-activating an
-- edited recipe never trips its own limit.
create or replace function public.activate_automation_recipe_version(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_recipe_id uuid,
  p_expected_revision integer,
  p_schema_version integer,
  p_definition jsonb,
  p_definition_hash text,
  p_trigger_key text,
  p_active_limit integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  existing_receipt public.automation_draft_command_receipts%rowtype;
  recipe public.automation_recipes%rowtype;
  active_count integer;
  next_version_number integer;
  new_version_id uuid;
  next_revision integer;
  command_result jsonb;
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

  -- Stale: report the newer editor/time; never freeze content the actor did not review.
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

  -- Active-recipes ceiling: enforced only on a NEW activation (a recipe already active keeps its slot).
  if p_active_limit is not null and recipe.status <> 'active' then
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

  insert into public.automation_recipe_versions (
    recipe_id, organization_id, version_number, schema_version,
    definition, definition_hash, trigger_key, activation_cutoff_sequence, activated_by
  ) values (
    p_recipe_id, p_organization_id, next_version_number, p_schema_version,
    p_definition, p_definition_hash, p_trigger_key, null, p_actor_user_id
  ) returning id into new_version_id;

  next_revision := recipe.draft_revision + 1;

  -- The draft buffer stays in sync with the just-frozen version so a later Edit opens a draft equal to the
  -- live recipe (contract: "Editing an Active or Paused recipe creates or updates a draft based on its active
  -- version"). draft_updated_* keep describing the last human draft edit, not this activation.
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

revoke all on function public.activate_automation_recipe_version(uuid, uuid, uuid, integer, integer, jsonb, text, text, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.activate_automation_recipe_version(uuid, uuid, uuid, integer, integer, jsonb, text, text, integer, uuid)
  to service_role;

comment on function public.activate_automation_recipe_version(uuid, uuid, uuid, integer, integer, jsonb, text, text, integer, uuid) is
  'Freezes an immutable recipe version from the reviewed draft and marks the recipe active. Idempotent per '
  'organization + key; enforces the active-recipes limit on a new activation and the caller-supplied revision.';

-- 3. Lifecycle state transitions: pause, resume, archive, restore. -------------------------------------
-- One command over the CLOSED set of four state actions. Each action has a fixed allowed source status and
-- target status; the mapping is hardcoded (no data-driven state machine). Restore returns an archived recipe
-- to a fresh draft: it clears the live version pointer so a later activation freezes a new version, and never
-- reactivates the old one (contract). Frozen versions and audit are retained across archive/restore.
create or replace function public.set_automation_recipe_lifecycle_state(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_recipe_id uuid,
  p_expected_revision integer,
  p_action text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  existing_receipt public.automation_draft_command_receipts%rowtype;
  recipe public.automation_recipes%rowtype;
  target_status text;
  action_label text;
  allowed_sources text[];
  next_revision integer;
  command_result jsonb;
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

  -- Restore needs a draft to return to; the buffer is kept in sync on every activation, so it is present.
  if p_action = 'restore' and recipe.draft_definition is null then
    raise exception 'This automation has no saved draft to restore.' using errcode = 'check_violation';
  end if;

  next_revision := recipe.draft_revision + 1;

  if p_action = 'restore' then
    -- Back to a fresh draft: drop the live version pointer (versions stay in the history table) so a later
    -- activation freezes a NEW version rather than reviving the old one.
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

revoke all on function public.set_automation_recipe_lifecycle_state(uuid, uuid, uuid, integer, text, uuid)
  from public, anon, authenticated;
grant execute on function public.set_automation_recipe_lifecycle_state(uuid, uuid, uuid, integer, text, uuid)
  to service_role;

comment on function public.set_automation_recipe_lifecycle_state(uuid, uuid, uuid, integer, text, uuid) is
  'Pauses, resumes, archives, or restores a recipe over a closed set of state transitions. Idempotent per '
  'organization + key; enforces the valid source status and the caller-supplied revision. Restore returns to '
  'a fresh draft and clears the live version pointer without reactivating the old version.';

-- 4. Duplicate: copy a recipe's current definition into a brand-new independent draft. ------------------
-- Copies the source's editable draft buffer (which for an active recipe equals its live version) into a new
-- recipe born in 'draft'. The source is unchanged; expected_revision guards that the copy reflects what the
-- actor saw. A duplicate is a draft, so it does not count against the active-recipes limit.
create or replace function public.duplicate_automation_recipe(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_recipe_id uuid,
  p_expected_revision integer,
  p_name text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_name text := btrim(coalesce(p_name, ''));
  existing_receipt public.automation_draft_command_receipts%rowtype;
  source public.automation_recipes%rowtype;
  new_recipe public.automation_recipes%rowtype;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception 'An expected revision is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_name) not between 1 and 120 then
    raise exception 'A recipe name of 1 to 120 characters is required.' using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('automation-recipe:' || p_recipe_id::text));

  select * into existing_receipt
  from public.automation_draft_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into source
  from public.automation_recipes
  where id = p_recipe_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That automation does not exist.' using errcode = 'no_data_found';
  end if;
  if source.draft_revision <> p_expected_revision then
    return jsonb_build_object(
      'stale', true,
      'current_revision', source.draft_revision,
      'draft_updated_at', source.draft_updated_at,
      'draft_updated_by', source.draft_updated_by
    );
  end if;
  if source.draft_definition is null then
    raise exception 'This automation has no definition to copy.' using errcode = 'check_violation';
  end if;

  insert into public.automation_recipes (
    organization_id, name, status, source, preset_key, preset_version,
    draft_definition, draft_revision, draft_updated_by, draft_updated_at, created_by
  ) values (
    p_organization_id, clean_name, 'draft', source.source, source.preset_key, source.preset_version,
    source.draft_definition, 1, p_actor_user_id, now(), p_actor_user_id
  ) returning * into new_recipe;

  command_result := jsonb_build_object(
    'recipe_id', new_recipe.id,
    'status', 'draft',
    'draft_revision', new_recipe.draft_revision,
    'stale', false
  );

  insert into public.automation_draft_command_receipts (
    organization_id, idempotency_key, command, recipe_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'duplicate', new_recipe.id, command_result
  );

  return command_result;
end;
$$;

revoke all on function public.duplicate_automation_recipe(uuid, uuid, uuid, integer, text, uuid)
  from public, anon, authenticated;
grant execute on function public.duplicate_automation_recipe(uuid, uuid, uuid, integer, text, uuid)
  to service_role;

comment on function public.duplicate_automation_recipe(uuid, uuid, uuid, integer, text, uuid) is
  'Copies a recipe''s current definition into a new independent draft. Idempotent per organization + key; '
  'guards the source revision. The copy is a draft and does not count against the active-recipes limit.';
