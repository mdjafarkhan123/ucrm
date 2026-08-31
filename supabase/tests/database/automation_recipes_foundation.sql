-- Contractor Settings Part 6C, slice 1: recipe + immutable version foundation.
-- Proves table shape and grants, the immutability trigger, the composite same-org/same-recipe foreign
-- keys, the source/preset and status/version/active-trigger constraints, and RLS visibility (own org with
-- automations.view, cross-tenant denial, and a member without the view permission).
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- 1. Structure and least-privilege grants -------------------------------------------------------------
select has_table('public', 'automation_recipes', 'the recipes table exists');
select has_table('public', 'automation_recipe_versions', 'the versions table exists');
select is((select relrowsecurity from pg_class where oid = 'public.automation_recipes'::regclass), true,
  'RLS is enabled on recipes');
select is((select relrowsecurity from pg_class where oid = 'public.automation_recipe_versions'::regclass), true,
  'RLS is enabled on versions');
select is(has_table_privilege('authenticated', 'public.automation_recipes', 'select'), true,
  'a signed-in session may read recipes');
select is(has_table_privilege('authenticated', 'public.automation_recipes', 'insert'), false,
  'a signed-in session may not write recipes directly (writes go through definer commands)');
select is(has_table_privilege('authenticated', 'public.automation_recipe_versions', 'insert'), false,
  'a signed-in session may not write versions directly');
select has_index('public', 'automation_recipes', 'automation_recipes_home_idx',
  'the home list index exists');

-- 2. Fixtures ------------------------------------------------------------------------------------------
set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000006c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rec-admin-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000006c2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rec-admin-b@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000006c3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rec-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-0000000006c0', 'Recipe Org A', 'recipe-org-a', 'active'),
  ('10000000-0000-0000-0000-0000000006d0', 'Recipe Org B', 'recipe-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-0000000006c0', '00000000-0000-0000-0000-0000000006c1', 'admin'),
  ('10000000-0000-0000-0000-0000000006d0', '00000000-0000-0000-0000-0000000006c2', 'admin'),
  ('10000000-0000-0000-0000-0000000006c0', '00000000-0000-0000-0000-0000000006c3', 'field');

-- Recipe A1: a valid draft, then a valid activation (insert version, point current_version_id at it).
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('a1000000-0000-0000-0000-0000000006c0', '10000000-0000-0000-0000-0000000006c0',
  'Quote follow-up', 'draft', 'custom', '{"trigger":{"key":"quote.delivery_succeeded"}}'::jsonb);

select lives_ok($$
  insert into public.automation_recipe_versions
    (id, recipe_id, organization_id, version_number, schema_version, definition, definition_hash, trigger_key)
  values ('b1000000-0000-0000-0000-0000000006c0', 'a1000000-0000-0000-0000-0000000006c0',
    '10000000-0000-0000-0000-0000000006c0', 1, 1,
    '{"trigger":{"key":"quote.delivery_succeeded"}}'::jsonb, 'hash-v1', 'quote.delivery_succeeded')
$$, 'a version can be frozen for its own recipe and organization');

select lives_ok($$
  update public.automation_recipes
  set status = 'active', current_version_id = 'b1000000-0000-0000-0000-0000000006c0',
    active_trigger_key = 'quote.delivery_succeeded'
  where id = 'a1000000-0000-0000-0000-0000000006c0'
$$, 'activation points current_version_id at the frozen version and sets the live-matching trigger');

-- 3. Immutability and referential integrity -----------------------------------------------------------
select throws_ok($$
  update public.automation_recipe_versions set schema_version = 2
  where id = 'b1000000-0000-0000-0000-0000000006c0'
$$, '23001', 'Automation recipe versions are immutable and cannot be updated.',
  'the immutability trigger blocks any update to a frozen version');

select throws_ok($$
  insert into public.automation_recipe_versions
    (recipe_id, organization_id, version_number, schema_version, definition, definition_hash, trigger_key)
  values ('a1000000-0000-0000-0000-0000000006c0', '10000000-0000-0000-0000-0000000006d0', 2, 1,
    '{}'::jsonb, 'hash-x', 'quote.delivery_succeeded')
$$, '23503', NULL, 'a version cannot claim a different organization than its recipe');

-- A2 in org A cannot adopt A1''s version as its current version (cross-recipe pointer).
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('a2000000-0000-0000-0000-0000000006c0', '10000000-0000-0000-0000-0000000006c0',
  'Second recipe', 'draft', 'custom', '{}'::jsonb);

select throws_ok($$
  update public.automation_recipes
  set status = 'active', current_version_id = 'b1000000-0000-0000-0000-0000000006c0',
    active_trigger_key = 'quote.delivery_succeeded'
  where id = 'a2000000-0000-0000-0000-0000000006c0'
$$, '23503', NULL, 'current_version_id cannot point at another recipe''s version');

-- 4. Domain constraints -------------------------------------------------------------------------------
select throws_ok($$
  insert into public.automation_recipes (organization_id, name, source, preset_key, draft_definition)
  values ('10000000-0000-0000-0000-0000000006c0', 'Bad', 'custom', 'quote_follow_up', '{}'::jsonb)
$$, '23514', NULL, 'a custom recipe cannot carry preset lineage');

select throws_ok($$
  insert into public.automation_recipes (organization_id, name, source, preset_key, draft_definition)
  values ('10000000-0000-0000-0000-0000000006c0', 'Bad', 'preset', 'quote_follow_up', '{}'::jsonb)
$$, '23514', NULL, 'a preset recipe needs both a preset key and a preset version');

select throws_ok($$
  insert into public.automation_recipes (organization_id, name, status, source, draft_definition)
  values ('10000000-0000-0000-0000-0000000006c0', 'Bad', 'active', 'custom', '{}'::jsonb)
$$, '23514', NULL, 'an active recipe must have a current version');

select throws_ok($$
  insert into public.automation_recipes (organization_id, name, status, source, draft_definition)
  values ('10000000-0000-0000-0000-0000000006c0', 'Bad', 'draft', 'custom', null)
$$, '23514', NULL, 'a draft recipe must hold a working draft definition');

-- 5. RLS visibility -----------------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000006c1', true);

select is((select count(*)::integer from public.automation_recipes
  where organization_id = '10000000-0000-0000-0000-0000000006c0'), 2,
  'an admin of Org A sees Org A recipes');
select is((select count(*)::integer from public.automation_recipes
  where organization_id = '10000000-0000-0000-0000-0000000006d0'), 0,
  'an admin of Org A sees no Org B recipes (cross-tenant denial)');
select is((select count(*)::integer from public.automation_recipe_versions
  where recipe_id = 'a1000000-0000-0000-0000-0000000006c0'), 1,
  'an admin of Org A can read its frozen version');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000006c3', true);
select is((select count(*)::integer from public.automation_recipes
  where organization_id = '10000000-0000-0000-0000-0000000006c0'), 0,
  'a member without automations.view sees no recipes even in their own org');

select * from finish();
rollback;
