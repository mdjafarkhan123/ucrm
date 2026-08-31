-- Contractor Settings Part 6C, slice 2 (backend): atomic draft create/save commands.
--
-- docs/automation-behavior-contract.md § Recipe definition and lifecycle ("Save updates only a draft ...
-- Draft updates use a revision supplied by the caller. A stale save returns the newer editor and time and
-- offers review or discard, never blind overwrite") and § Entitlement, permissions, and commands ("State-
-- changing commands also enforce expected revision, organization ownership, ... and an idempotency key in
-- the atomic database command").
--
-- Writes stay SECURITY DEFINER only: the recipe/version tables grant SELECT to members and every mutation
-- flows through these functions, executed by service_role after the route has already resolved entitlement,
-- permission, and suspension (src/lib/server/access/automation.ts). The functions enforce what MUST be
-- atomic: organization ownership of the target row, the caller-supplied revision (optimistic lock), and a
-- private idempotency receipt so a retried submit replays its original result instead of creating a second
-- recipe or tripping a false stale conflict. Canonical definition JSON + hash are computed server-side by
-- src/lib/server/automation/definition.ts and passed in already validated; the database stores, never trusts.

-- 1. Idempotency receipts: private, service-only, retained at least 24h (cleanup lands with 6E). ---------
create table public.automation_draft_command_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  idempotency_key uuid not null,
  command text not null check (command in ('create_draft', 'save_draft')),
  recipe_id uuid,
  -- The exact response the first application produced, replayed verbatim on a retry.
  result jsonb not null,
  created_at timestamptz not null default now(),
  constraint automation_draft_command_receipts_key_unique unique (organization_id, idempotency_key)
);

comment on table public.automation_draft_command_receipts is
  'Private idempotency receipts for automation draft commands. A retried submit replays its stored result. '
  'Retained at least 24h; batched indexed cleanup is owned by 6E.';

-- Age-ordered index for the future bounded retention sweep (6E claims oldest terminal rows in id order).
create index automation_draft_command_receipts_age_idx
  on public.automation_draft_command_receipts (created_at, id);

alter table public.automation_draft_command_receipts enable row level security;
revoke all on public.automation_draft_command_receipts from anon, authenticated;
grant select, insert on public.automation_draft_command_receipts to service_role;

-- 2. Create a brand-new recipe as a draft. -------------------------------------------------------------
-- The recipe is born in 'draft' with the working definition on the draft buffer and no frozen version.
-- Preset lineage is recorded for explanation only; the organization copy is fully independent thereafter.
create or replace function public.create_automation_recipe_draft(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_name text,
  p_source text,
  p_preset_key text,
  p_preset_version integer,
  p_definition jsonb,
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
  new_recipe public.automation_recipes%rowtype;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(clean_name) not between 1 and 120 then
    raise exception 'A recipe name of 1 to 120 characters is required.' using errcode = 'check_violation';
  end if;
  if p_source not in ('preset', 'custom') then
    raise exception 'A recipe source of preset or custom is required.' using errcode = 'check_violation';
  end if;
  if p_source = 'preset' and (p_preset_key is null or p_preset_version is null) then
    raise exception 'A preset recipe requires its preset lineage.' using errcode = 'check_violation';
  end if;
  if p_source = 'custom' and (p_preset_key is not null or p_preset_version is not null) then
    raise exception 'A custom recipe carries no preset lineage.' using errcode = 'check_violation';
  end if;
  if p_definition is null or jsonb_typeof(p_definition) <> 'object' then
    raise exception 'A recipe definition is required.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.organizations where id = p_organization_id) then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  -- Serialize identical retries so a duplicate submit cannot create two recipes.
  perform pg_advisory_xact_lock(
    hashtext('automation-draft-cmd:' || p_organization_id::text || ':' || p_idempotency_key::text)
  );

  select * into existing_receipt
  from public.automation_draft_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  insert into public.automation_recipes (
    organization_id, name, status, source, preset_key, preset_version,
    draft_definition, draft_revision, draft_updated_by, draft_updated_at, created_by
  ) values (
    p_organization_id, clean_name, 'draft', p_source,
    case when p_source = 'preset' then p_preset_key end,
    case when p_source = 'preset' then p_preset_version end,
    p_definition, 1, p_actor_user_id, now(), p_actor_user_id
  ) returning * into new_recipe;

  insert into public.automation_draft_command_receipts (
    organization_id, idempotency_key, command, recipe_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'create_draft', new_recipe.id,
    jsonb_build_object('recipe_id', new_recipe.id, 'draft_revision', new_recipe.draft_revision)
  );

  return jsonb_build_object('recipe_id', new_recipe.id, 'draft_revision', new_recipe.draft_revision);
end;
$$;

revoke all on function public.create_automation_recipe_draft(uuid, uuid, text, text, text, integer, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.create_automation_recipe_draft(uuid, uuid, text, text, text, integer, jsonb, uuid)
  to service_role;

comment on function public.create_automation_recipe_draft(uuid, uuid, text, text, text, integer, jsonb, uuid) is
  'Creates a new automation recipe as a draft. Idempotent per organization + key; advisory-locked so a '
  'retried submit replays instead of duplicating.';

-- 3. Save an existing recipe's draft with optimistic-lock revision protection. -------------------------
-- A caller supplies the revision it last read. When it still matches, the draft advances by one; when it
-- does not, no write happens and the newer editor/time are returned so the UI can offer review or discard.
create or replace function public.save_automation_recipe_draft(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_recipe_id uuid,
  p_expected_revision integer,
  p_name text,
  p_definition jsonb,
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
  recipe public.automation_recipes%rowtype;
  next_revision integer;
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
  if p_definition is null or jsonb_typeof(p_definition) <> 'object' then
    raise exception 'A recipe definition is required.' using errcode = 'check_violation';
  end if;

  -- One recipe row is the lock domain: concurrent saves serialize here, so the revision check is honest.
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

  -- Stale save: report the newer editor/time; never overwrite, merge, or blindly advance the revision.
  if recipe.draft_revision <> p_expected_revision then
    return jsonb_build_object(
      'stale', true,
      'current_revision', recipe.draft_revision,
      'draft_updated_at', recipe.draft_updated_at,
      'draft_updated_by', recipe.draft_updated_by
    );
  end if;

  next_revision := recipe.draft_revision + 1;

  update public.automation_recipes
  set name = clean_name,
      draft_definition = p_definition,
      draft_revision = next_revision,
      draft_updated_by = p_actor_user_id,
      draft_updated_at = now()
  where id = p_recipe_id and organization_id = p_organization_id;

  insert into public.automation_draft_command_receipts (
    organization_id, idempotency_key, command, recipe_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'save_draft', p_recipe_id,
    jsonb_build_object('recipe_id', p_recipe_id, 'draft_revision', next_revision, 'stale', false)
  );

  return jsonb_build_object('recipe_id', p_recipe_id, 'draft_revision', next_revision, 'stale', false);
end;
$$;

revoke all on function public.save_automation_recipe_draft(uuid, uuid, uuid, integer, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.save_automation_recipe_draft(uuid, uuid, uuid, integer, text, jsonb, uuid)
  to service_role;

comment on function public.save_automation_recipe_draft(uuid, uuid, uuid, integer, text, jsonb, uuid) is
  'Saves an existing recipe draft under optimistic-lock revision protection. Idempotent per organization + '
  'key; a stale revision returns the newer editor/time instead of overwriting.';
