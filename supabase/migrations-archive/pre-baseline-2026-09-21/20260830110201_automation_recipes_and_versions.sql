-- Contractor Settings Part 6C, slice 1: the recipe aggregate and its immutable activated versions.
--
-- docs/automation-behavior-contract.md § Recipe definition and lifecycle. One recipe row per automation;
-- the current editable draft lives ON the recipe (draft buffer) and is the only mutable definition. Every
-- activation FREEZES an append-only row in automation_recipe_versions; enrollments (6D) pin to a version.
--
-- No customer effects, events, or enrollments in 6C. Writes arrive in 6C-2/6C-3 through SECURITY DEFINER
-- command functions, so contractors get SELECT only here and the versions table is immutable by construction
-- (no UPDATE path plus a hard trigger). active_trigger_key is the ONLY trigger used for live matching (6D);
-- it is set at activation from the frozen version and draft edits never touch it.

-- 1. Recipes: the aggregate root and draft buffer. ----------------------------------------------------
create table public.automation_recipes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'paused', 'archived')),
  source text not null check (source in ('preset', 'custom')),
  -- Preset lineage, for explanation only; the organization copy is independent of the platform preset.
  preset_key text check (preset_key is null or char_length(trim(preset_key)) between 1 and 120),
  preset_version integer check (preset_version is null or preset_version >= 1),
  -- Live-matching trigger. Set ONLY at activation from the frozen version; draft edits (inside
  -- draft_definition) never change it, so an in-progress draft can never move an active recipe's matching.
  active_trigger_key text,
  -- The current editable draft. Null when an activated recipe has no outstanding edit. Canonical JSON is
  -- always computed server-side from validated structured fields, never taken from the browser.
  draft_definition jsonb,
  draft_revision integer not null default 1 check (draft_revision >= 1),
  draft_updated_by uuid references auth.users(id) on delete set null,
  draft_updated_at timestamptz,
  current_version_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Preset lineage is all-or-nothing; a custom recipe carries no preset columns.
  constraint automation_recipes_source_preset_check check (
    (source = 'custom' and preset_key is null and preset_version is null)
    or (source = 'preset' and preset_key is not null and preset_version is not null)
  ),
  -- Status <-> active-version invariant. A never-activated draft holds a working draft and no frozen
  -- version; active/paused always have a frozen version; archived may be either.
  constraint automation_recipes_status_version_check check (
    (status = 'draft' and current_version_id is null and draft_definition is not null)
    or (status = 'active' and current_version_id is not null)
    or (status = 'paused' and current_version_id is not null)
    or (status = 'archived')
  ),
  -- The live-matching trigger exists exactly when a frozen active version does.
  constraint automation_recipes_active_trigger_check check (
    (current_version_id is null and active_trigger_key is null)
    or (current_version_id is not null and active_trigger_key is not null)
  ),
  -- Target for the versions -> recipe composite FK (same org + recipe guarantee).
  constraint automation_recipes_id_org_key unique (id, organization_id)
);

comment on table public.automation_recipes is
  'One automation recipe per row. Mutable draft buffer here; frozen versions in '
  'automation_recipe_versions. See docs/automation-behavior-contract.md § Recipe definition and lifecycle.';

-- 2. Versions: append-only, immutable snapshots frozen at each activation. -----------------------------
create table public.automation_recipe_versions (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null,
  organization_id uuid not null,
  version_number integer not null check (version_number >= 1),
  schema_version integer not null check (schema_version >= 1),
  definition jsonb not null,
  definition_hash text not null check (char_length(definition_hash) between 1 and 128),
  trigger_key text not null,
  -- Event-sequence cutoff for automatic enrollment. Null in 6C (no engine yet); 6D sets it at activation.
  -- Never updated -- the immutability trigger below forbids it.
  activation_cutoff_sequence bigint,
  activated_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz not null default now(),
  -- Every version belongs to the SAME organization and recipe as its parent; cascades on recipe delete.
  constraint automation_recipe_versions_recipe_org_fkey
    foreign key (recipe_id, organization_id)
    references public.automation_recipes(id, organization_id) on delete cascade,
  constraint automation_recipe_versions_recipe_number_key unique (recipe_id, version_number),
  -- Target for the recipe.current_version_id composite FK.
  constraint automation_recipe_versions_id_recipe_org_key unique (id, recipe_id, organization_id)
);

comment on table public.automation_recipe_versions is
  'Immutable, append-only frozen recipe definitions, one per activation. Enrollments (6D) pin to a version. '
  'Updates are blocked by trigger; deletion is reserved for retention/organization destruction.';

-- current_version_id points only to a version of THIS recipe and organization. Nullable + MATCH SIMPLE, so
-- a recipe with no active version skips the check; a set pointer is fully validated. NO ACTION on the
-- referenced side means the active version cannot be deleted out from under an active recipe (retention
-- deletes only non-current versions).
alter table public.automation_recipes
  add constraint automation_recipes_current_version_fkey
  foreign key (current_version_id, id, organization_id)
  references public.automation_recipe_versions(id, recipe_id, organization_id);

-- 3. Indexes. -----------------------------------------------------------------------------------------
-- Home list: org + status filter, newest first, unique tie-breaker for cursor pagination (contract
-- § Query, index, and count). Its leading organization_id also covers the organizations -> recipes cascade.
create index automation_recipes_home_idx
  on public.automation_recipes(organization_id, status, updated_at desc, id desc);

-- Reverse lookup for the current_version_id composite FK (version-delete/retention checks) and detail read.
create index automation_recipes_current_version_idx
  on public.automation_recipes(current_version_id) where current_version_id is not null;

-- FK index accounting:
--   * recipes.organization_id (cascade)          -> covered by automation_recipes_home_idx (leads org).
--   * recipes.current_version_id (reverse FK)     -> automation_recipes_current_version_idx (partial).
--   * versions(recipe_id, organization_id) cascade-> covered by ..._recipe_number_key (leads recipe_id).
--   * recipes.created_by / draft_updated_by, versions.activated_by (ON DELETE SET NULL) -> intentionally
--     unindexed: user deletion is rare and rows-per-user are bounded, so a sequential set-null is acceptable.
-- The all-status home read (no status equality) is verified with EXPLAIN in 6C-1 verification; a second
-- (organization_id, updated_at desc, id desc) index is added only if that evidence requires it.

-- 4. Recipes get an updated_at touch; versions never change. -------------------------------------------
create trigger automation_recipes_set_updated_at
before update on public.automation_recipes
for each row execute function public.set_updated_at();

-- Hard immutability for activated versions: defeats even a privileged/definer UPDATE. DELETE is left to the
-- retention and organization-destruction workflows.
create function public.prevent_automation_recipe_version_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'Automation recipe versions are immutable and cannot be updated.'
    using errcode = 'restrict_violation';
end;
$$;

comment on function public.prevent_automation_recipe_version_mutation() is
  'Enforces automation_recipe_versions immutability by rejecting every UPDATE.';

create trigger automation_recipe_versions_block_update
before update on public.automation_recipe_versions
for each row execute function public.prevent_automation_recipe_version_mutation();

-- 5. RLS: read-only for members who hold automations.view; all writes go through definer commands. -----
alter table public.automation_recipes enable row level security;
alter table public.automation_recipe_versions enable row level security;

create policy "members who can view automations can read recipes"
on public.automation_recipes for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'automations.view')
);

create policy "members who can view automations can read recipe versions"
on public.automation_recipe_versions for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'automations.view')
);

revoke all on public.automation_recipes from anon, authenticated;
grant select on public.automation_recipes to authenticated;

revoke all on public.automation_recipe_versions from anon, authenticated;
grant select on public.automation_recipe_versions to authenticated;
