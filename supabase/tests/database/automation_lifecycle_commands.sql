-- Contractor Settings Part 6C, slice 3a: atomic recipe lifecycle commands.
-- Proves the three SECURITY DEFINER commands are service-only; that activate freezes an immutable version,
-- syncs the draft buffer, enforces the active-recipes limit only on a NEW activation, is idempotent, honours
-- the caller revision (stale never freezes), refuses archived/unknown recipes; that the closed pause/resume/
-- archive/restore state machine advances the revision, rejects invalid transitions, is idempotent (a retried
-- key beats the state check), reports stale, is tenant-isolated; and that duplicate copies into a fresh draft
-- without touching the source or the active count.
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive.
-- Definitions are opaque jsonb to these commands (the ROUTE validates against the catalog), so the fixtures
-- use a minimal well-formed shape.
begin;

create extension if not exists pgtap with schema extensions;

select plan(52);

-- 1. Structure and least-privilege --------------------------------------------------------------------
select has_function('public', 'activate_automation_recipe_version', 'the activate command exists');
select has_function('public', 'set_automation_recipe_lifecycle_state', 'the lifecycle-state command exists');
select has_function('public', 'duplicate_automation_recipe', 'the duplicate command exists');
select is(
  has_function_privilege('authenticated',
    'public.activate_automation_recipe_version(uuid,uuid,uuid,integer,integer,jsonb,text,text,integer,uuid)', 'execute'),
  false, 'a signed-in session may not execute activate directly');
select is(
  has_function_privilege('authenticated',
    'public.set_automation_recipe_lifecycle_state(uuid,uuid,uuid,integer,text,uuid)', 'execute'),
  false, 'a signed-in session may not execute the lifecycle command directly');
select is(
  has_function_privilege('authenticated',
    'public.duplicate_automation_recipe(uuid,uuid,uuid,integer,text,uuid)', 'execute'),
  false, 'a signed-in session may not execute duplicate directly');

-- 2. Fixtures -----------------------------------------------------------------------------------------
set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000d211', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'life-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-00000000d212', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'life-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-00000000d201', 'Life Org A', 'life-org-a', 'active'),
  ('10000000-0000-0000-0000-00000000d202', 'Life Org B', 'life-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211', 'admin'),
  ('10000000-0000-0000-0000-00000000d202', '00000000-0000-0000-0000-00000000d212', 'admin');

-- Recipes are inserted directly (create is proven elsewhere); each starts as a draft at revision 1. a4 is a
-- preset recipe, so its lineage is set inline (the source/lineage CHECK is enforced at insert time).
insert into public.automation_recipes (id, organization_id, name, status, source, preset_key, preset_version, draft_definition, draft_revision, created_by)
values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000d201', 'Activate me', 'draft', 'custom', null, null,
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb, 1, '00000000-0000-0000-0000-00000000d211'),
  ('20000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-00000000d201', 'Limit me', 'draft', 'custom', null, null,
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb, 1, '00000000-0000-0000-0000-00000000d211'),
  ('20000000-0000-0000-0000-0000000000a3', '10000000-0000-0000-0000-00000000d201', 'Cycle me', 'draft', 'custom', null, null,
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb, 1, '00000000-0000-0000-0000-00000000d211'),
  ('20000000-0000-0000-0000-0000000000a4', '10000000-0000-0000-0000-00000000d201', 'Copy source', 'draft', 'preset', 'quote_follow_up', 1,
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb, 1, '00000000-0000-0000-0000-00000000d211'),
  ('20000000-0000-0000-0000-0000000000a5', '10000000-0000-0000-0000-00000000d201', 'Archived one', 'archived', 'custom', null, null,
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb, 1, '00000000-0000-0000-0000-00000000d211');

-- 3. Activate: freeze a version --------------------------------------------------------------------
create temp table _act1 as
select public.activate_automation_recipe_version(
  '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
  '20000000-0000-0000-0000-0000000000a1', 1, 1,
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb,
  'hash-a1-v1', 'quote.delivery_succeeded', null, 'd1000000-0000-0000-0000-000000000001'
) as res;

select is((select res->>'status' from _act1), 'active', 'activate returns active status');
select is((select (res->>'version_number')::int from _act1), 1, 'the first frozen version is number 1');
select is((select (res->>'draft_revision')::int from _act1), 2, 'activation advances the aggregate revision');
select is((select status from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a1'),
  'active', 'the recipe row is now active');
select isnt((select current_version_id from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a1'),
  null, 'the recipe points at a frozen version');
select is((select active_trigger_key from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a1'),
  'quote.delivery_succeeded', 'the live-matching trigger is stamped from the frozen version');
select is((select count(*)::int from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a1'),
  1, 'exactly one version is frozen');
select is((select definition_hash from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a1'),
  'hash-a1-v1', 'the frozen version stores its server-computed hash');
select is((select activation_cutoff_sequence from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a1'),
  null, 'the event-sequence cutoff stays empty until 6D');
select is((select count(*)::int from public.automation_draft_command_receipts
  where idempotency_key = 'd1000000-0000-0000-0000-000000000001'), 1, 'an activation receipt is written');

-- Idempotent replay: same key returns the original result and freezes no second version.
select is((select (public.activate_automation_recipe_version(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a1', 1, 1,
    '{"schema_version":1}'::jsonb, 'ignored', 'quote.delivery_succeeded', null,
    'd1000000-0000-0000-0000-000000000001') ->> 'idempotent_replay')::boolean),
  true, 'a replayed activation is flagged idempotent');
select is((select count(*)::int from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a1'),
  1, 'the replay freezes no second version');

-- Stale activation: wrong revision returns stale and freezes nothing (recipe is now at revision 2).
select is((select (public.activate_automation_recipe_version(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a1', 1, 1,
    '{"schema_version":1}'::jsonb, 'hash', 'quote.delivery_succeeded', null, gen_random_uuid()) ->> 'stale')::boolean),
  true, 'a stale activation is reported, not applied');
select is((select count(*)::int from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a1'),
  1, 'the stale activation froze no version');

-- Active-recipes limit: org A already has one active recipe (a1); activating a2 under a limit of 1 is refused.
select throws_ok($$
  select public.activate_automation_recipe_version(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a2', 1, 1,
    '{"schema_version":1}'::jsonb, 'hash', 'quote.delivery_succeeded', 1, gen_random_uuid())
$$, '23001', NULL, 'activating past the active-recipes limit is refused');

-- Re-activating an already-active recipe does NOT trip its own limit (it keeps its slot); a second version freezes.
select is((select (public.activate_automation_recipe_version(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a1', 2, 1,
    '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb,
    'hash-a1-v2', 'quote.delivery_succeeded', 1, 'd1000000-0000-0000-0000-000000000002') ->> 'version_number')::int),
  2, 're-activating an active recipe freezes version 2 without tripping the limit');
select is((select count(*)::int from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a1'),
  2, 'the recipe now has two frozen versions');

-- Archived recipes are read-only; unknown recipes are not found.
select throws_ok($$
  select public.activate_automation_recipe_version(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a5', 1, 1,
    '{"schema_version":1}'::jsonb, 'hash', 'quote.delivery_succeeded', null, gen_random_uuid())
$$, '23001', NULL, 'an archived recipe cannot be activated');
select throws_ok($$
  select public.activate_automation_recipe_version(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    gen_random_uuid(), 1, 1, '{"schema_version":1}'::jsonb, 'hash', 'quote.delivery_succeeded', null, gen_random_uuid())
$$, 'P0002', NULL, 'activating an unknown recipe is not found');

-- 4. Lifecycle state machine (pause / resume / archive / restore) on a3 ------------------------------
-- Activate a3 first so it has a live version to pause.
select public.activate_automation_recipe_version(
  '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
  '20000000-0000-0000-0000-0000000000a3', 1, 1,
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb,
  'hash-a3-v1', 'quote.delivery_succeeded', null, 'd3000000-0000-0000-0000-000000000001'
);  -- a3 is now active at revision 2

select is((select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 2, 'pause', 'd3000000-0000-0000-0000-000000000002') ->> 'status'),
  'paused', 'an active recipe pauses');
select is((select status from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a3'),
  'paused', 'the recipe row is paused');
select is((select draft_revision from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a3'),
  3, 'pausing advances the aggregate revision');

-- Idempotent replay beats the state check: the retried pause key replays even though the recipe is now paused.
select is((select (public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 2, 'pause', 'd3000000-0000-0000-0000-000000000002') ->> 'idempotent_replay')::boolean),
  true, 'a retried pause replays instead of erroring on the new state');

select is((select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 3, 'resume', 'd3000000-0000-0000-0000-000000000003') ->> 'status'),
  'active', 'a paused recipe resumes');
select is((select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 4, 'archive', 'd3000000-0000-0000-0000-000000000004') ->> 'status'),
  'archived', 'a recipe archives');

-- Restore returns to a fresh draft and clears the live version pointer (versions are retained).
select is((select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 5, 'restore', 'd3000000-0000-0000-0000-000000000005') ->> 'status'),
  'draft', 'an archived recipe restores to a draft');
select is((select current_version_id from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a3'),
  null, 'restore clears the live version pointer');
select is((select active_trigger_key from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a3'),
  null, 'restore clears the live-matching trigger');
select is((select count(*)::int from public.automation_recipe_versions where recipe_id = '20000000-0000-0000-0000-0000000000a3'),
  1, 'restore retains the frozen version history');
select is((select draft_revision from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a3'),
  6, 'restore advances the aggregate revision');

-- Stale transition: wrong revision reports stale (checked before the state rule).
select is((select (public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 999, 'pause', gen_random_uuid()) ->> 'stale')::boolean),
  true, 'a stale lifecycle action is reported, not applied');

-- Invalid transition: a draft cannot be paused (revision matches, so the state rule fires).
select throws_ok($$
  select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 6, 'pause', gen_random_uuid())
$$, '23001', NULL, 'a draft cannot be paused');

-- Tenant isolation and unknown recipe.
select throws_ok($$
  select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d202', '00000000-0000-0000-0000-00000000d212',
    '20000000-0000-0000-0000-0000000000a3', 6, 'pause', gen_random_uuid())
$$, 'P0002', NULL, 'another organization cannot touch this recipe');
select throws_ok($$
  select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    gen_random_uuid(), 1, 'pause', gen_random_uuid())
$$, 'P0002', NULL, 'a lifecycle action on an unknown recipe is not found');
select throws_ok($$
  select public.set_automation_recipe_lifecycle_state(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a3', 6, 'explode', gen_random_uuid())
$$, '23514', NULL, 'an unknown lifecycle action is rejected');

-- 5. Duplicate: copy into a fresh independent draft (source a4) ---------------------------------------
create temp table _dup as
select public.duplicate_automation_recipe(
  '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
  '20000000-0000-0000-0000-0000000000a4', 1, 'Copy of source', 'd4000000-0000-0000-0000-000000000001'
) as res;

select is((select res->>'status' from _dup), 'draft', 'a duplicate is born a draft');
select is((select (res->>'draft_revision')::int from _dup), 1, 'a duplicate starts at revision 1');
select isnt((select (res->>'recipe_id')::uuid from _dup), '20000000-0000-0000-0000-0000000000a4',
  'the duplicate is a new recipe, not the source');
select is((select name from public.automation_recipes where id = (select (res->>'recipe_id')::uuid from _dup)),
  'Copy of source', 'the duplicate takes the requested name');
select is((select source || ':' || coalesce(preset_key,'null') from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _dup)), 'preset:quote_follow_up',
  'the duplicate copies the source preset lineage');
select is((select draft_definition from public.automation_recipes where id = (select (res->>'recipe_id')::uuid from _dup)),
  (select draft_definition from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a4'),
  'the duplicate copies the source definition');
select is((select current_version_id from public.automation_recipes where id = (select (res->>'recipe_id')::uuid from _dup)),
  null, 'the duplicate has no frozen version');
select is((select draft_revision from public.automation_recipes where id = '20000000-0000-0000-0000-0000000000a4'),
  1, 'the source is left untouched');

-- Stale source revision is reported; a retried key replays the original duplicate.
select is((select (public.duplicate_automation_recipe(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a4', 999, 'Nope', gen_random_uuid()) ->> 'stale')::boolean),
  true, 'a stale duplicate is reported, not applied');
select is((select (public.duplicate_automation_recipe(
    '10000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d211',
    '20000000-0000-0000-0000-0000000000a4', 1, 'Copy of source', 'd4000000-0000-0000-0000-000000000001') ->> 'recipe_id')),
  (select res->>'recipe_id' from _dup), 'a retried duplicate replays the original new recipe id');
select is((select count(*)::int from public.automation_recipes
  where organization_id = '10000000-0000-0000-0000-00000000d201' and name = 'Copy of source'), 1,
  'the retried duplicate creates no second copy');

select * from finish();
rollback;
