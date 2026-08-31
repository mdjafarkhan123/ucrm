-- Contractor Settings Part 6C, slice 2: atomic draft create/save commands.
-- Proves the two SECURITY DEFINER command functions are service-only, that create is idempotent and never
-- duplicates, that save advances the revision, enforces the caller-supplied revision (stale returns the
-- newer editor/time without overwriting), is idempotent (a retried key beats the stale check), refuses an
-- archived recipe and an unknown recipe, and is tenant-isolated (another org cannot touch the row).
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive.
begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- 1. Structure and least-privilege --------------------------------------------------------------------
select has_function('public', 'create_automation_recipe_draft', 'the create-draft command exists');
select has_function('public', 'save_automation_recipe_draft', 'the save-draft command exists');
select has_table('public', 'automation_draft_command_receipts', 'the idempotency receipts table exists');
select is((select relrowsecurity from pg_class where oid = 'public.automation_draft_command_receipts'::regclass),
  true, 'RLS is enabled on receipts');
select is(has_table_privilege('authenticated', 'public.automation_draft_command_receipts', 'insert'), false,
  'a signed-in session may not write receipts directly');
select is(
  has_function_privilege('authenticated',
    'public.create_automation_recipe_draft(uuid,uuid,text,text,text,integer,jsonb,uuid)', 'execute'),
  false, 'a signed-in session may not execute the create command directly');
select is(
  has_function_privilege('authenticated',
    'public.save_automation_recipe_draft(uuid,uuid,uuid,integer,text,jsonb,uuid)', 'execute'),
  false, 'a signed-in session may not execute the save command directly');

-- 2. Fixtures -----------------------------------------------------------------------------------------
set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000c211', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'draft-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-00000000c212', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'draft-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-00000000c201', 'Draft Org A', 'draft-org-a', 'active'),
  ('10000000-0000-0000-0000-00000000c202', 'Draft Org B', 'draft-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211', 'admin'),
  ('10000000-0000-0000-0000-00000000c202', '00000000-0000-0000-0000-00000000c212', 'admin');

-- 3. Create ------------------------------------------------------------------------------------------
create temp table _created as
select public.create_automation_recipe_draft(
  '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
  'Quote follow-up', 'custom', null, null,
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[],"stops":[]}'::jsonb,
  'c1000000-0000-0000-0000-000000000001'
) as res;

select is((select (res->>'draft_revision')::int from _created), 1, 'create returns draft revision 1');
select is((select count(*)::int from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), 1, 'exactly one recipe row is created');
select is((select status from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), 'draft', 'the recipe is born as a draft');
select is((select source || ':' || coalesce(preset_key, 'null') from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), 'custom:null',
  'a custom recipe carries no preset lineage');
select is((select count(*)::int from public.automation_draft_command_receipts
  where organization_id = '10000000-0000-0000-0000-00000000c201'
    and idempotency_key = 'c1000000-0000-0000-0000-000000000001'), 1, 'a create receipt is written');

-- Idempotent replay: same key returns the same recipe and creates no second row.
create temp table _replay as
select public.create_automation_recipe_draft(
  '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
  'Quote follow-up', 'custom', null, null,
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[],"stops":[]}'::jsonb,
  'c1000000-0000-0000-0000-000000000001'
) as res;

select is((select (res->>'recipe_id') from _replay), (select (res->>'recipe_id') from _created),
  'a replayed create returns the original recipe id');
select is((select (res->>'idempotent_replay')::boolean from _replay), true, 'the replay is flagged idempotent');
select is((select count(*)::int from public.automation_recipes
  where organization_id = '10000000-0000-0000-0000-00000000c201'), 1, 'the replay creates no second recipe');

-- Create validation.
select throws_ok($$
  select public.create_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
    'Bad', 'custom', 'quote_follow_up', 1, '{"schema_version":1}'::jsonb, gen_random_uuid())
$$, '23514', NULL, 'a custom recipe cannot carry preset lineage');
select throws_ok($$
  select public.create_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
    'Bad', 'preset', 'quote_follow_up', null, '{"schema_version":1}'::jsonb, gen_random_uuid())
$$, '23514', NULL, 'a preset recipe needs both key and version');
select throws_ok($$
  select public.create_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
    '   ', 'custom', null, null, '{"schema_version":1}'::jsonb, gen_random_uuid())
$$, '23514', NULL, 'a blank name is rejected');

-- 4. Save with revision protection -------------------------------------------------------------------
create temp table _saved as
select public.save_automation_recipe_draft(
  '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c212',
  (select (res->>'recipe_id')::uuid from _created), 1, 'Renamed follow-up',
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[],"stops":[{"key":"stop.quote_approved"}]}'::jsonb,
  'c2000000-0000-0000-0000-000000000001'
) as res;

select is((select (res->>'draft_revision')::int from _saved), 2, 'a matching save advances to revision 2');
select is((select name from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), 'Renamed follow-up', 'the name is updated');
select is((select draft_updated_by from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), '00000000-0000-0000-0000-00000000c212',
  'the editing user is recorded');

-- Tenant isolation: another org cannot touch the row (it simply is not found).
select throws_ok(format($$
  select public.save_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c202', '00000000-0000-0000-0000-00000000c212',
    %L, 2, 'Hijack', '{"schema_version":1}'::jsonb, gen_random_uuid())
$$, (select (res->>'recipe_id')::uuid from _created)),
  'P0002', NULL, 'another organization cannot save this recipe');

-- Stale save: wrong expected revision returns the newer editor/time and does not write.
select is((select (public.save_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
    (select (res->>'recipe_id')::uuid from _created), 1, 'Should not stick',
    '{"schema_version":1}'::jsonb, gen_random_uuid()) ->> 'stale')::boolean),
  true, 'a stale save is reported, not applied');
select is((select draft_revision from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), 2, 'the stale save did not advance the revision');
select is((select name from public.automation_recipes
  where id = (select (res->>'recipe_id')::uuid from _created)), 'Renamed follow-up',
  'the stale save did not overwrite the name');

-- Idempotent replay beats the stale check: the retried key returns its original success (revision 2).
select is((select (public.save_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c212',
    (select (res->>'recipe_id')::uuid from _created), 1, 'Retry',
    '{"schema_version":1}'::jsonb, 'c2000000-0000-0000-0000-000000000001') ->> 'draft_revision')::int),
  2, 'a retried save replays its original revision instead of reporting stale');

-- Unknown recipe is not found.
select throws_ok($$
  select public.save_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
    gen_random_uuid(), 1, 'Ghost', '{"schema_version":1}'::jsonb, gen_random_uuid())
$$, 'P0002', NULL, 'saving an unknown recipe is not found');

-- Archived recipes are read-only.
update public.automation_recipes set status = 'archived'
where id = (select (res->>'recipe_id')::uuid from _created);
select throws_ok(format($$
  select public.save_automation_recipe_draft(
    '10000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c211',
    %L, 2, 'Edit archived', '{"schema_version":1}'::jsonb, gen_random_uuid())
$$, (select (res->>'recipe_id')::uuid from _created)),
  '23001', NULL, 'an archived recipe cannot be edited');

select * from finish();
rollback;
