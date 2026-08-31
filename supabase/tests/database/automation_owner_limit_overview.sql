-- Contractor Settings Part 6B, slice 3b: owner Automation limit-overview read model.
-- Proves get_organization_automation_limits assembles, for all seven keys in one call: the package default,
-- the effective value/source taken from the authoritative resolver, and the reasoned/effective-dated
-- exception (author, reason, window, active flag). Also proves the privilege matrix (owner-only), the
-- not_included fallback with no assignment, and that a scheduled/expired exception is shown but does not
-- become the effective value.
--
-- Single-session, single-transaction run (Supabase MCP execute_sql or `supabase test db`). Do not run
-- through a per-statement runner: `set local role` would not survive.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- 1. Privilege matrix ---------------------------------------------------------------------------------
select is(has_function_privilege('anon', 'public.get_organization_automation_limits(uuid, timestamptz)', 'execute'), false,
  'anonymous callers cannot read the owner automation limit overview');
select is(has_function_privilege('authenticated', 'public.get_organization_automation_limits(uuid, timestamptz)', 'execute'), false,
  'contractors cannot read the owner automation limit overview');
select is(has_function_privilege('service_role', 'public.get_organization_automation_limits(uuid, timestamptz)', 'execute'), true,
  'the owner service role can read the automation limit overview');

-- 2. Fixtures -----------------------------------------------------------------------------------------
set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-0000000006c0', 'Automation Overview Org C', 'automation-overview-org-c', 'active'),
  ('10000000-0000-0000-0000-0000000006d0', 'Automation Overview Org D', 'automation-overview-org-d', 'active');

-- A published version carrying all seven automation limits, assigned to Org C. An assignment must
-- reference a published version, so the seed elite published version is retired first (rolled back with
-- the test). Limits are written while the version is a draft, then published.
update public.platform_package_versions
set status = 'retired', retired_at = now()
where package_id = (select package_id from public.platform_packages where package_key = 'elite')
  and status = 'published';

insert into public.platform_package_versions
  (id, package_id, version_number, status, display_name, public_description, value_explanation, price_usd_cents)
select 'c0000000-0000-0000-0000-0000000006c0', package_id, 991, 'draft',
  'Automation Overview Test Draft', 'Automation overview test version', 'Automation overview test', 9900
from public.platform_packages where package_key = 'elite';

select public.manage_platform_package_automation_limits(
  'c0000000-0000-0000-0000-0000000006c0',
  'numeric', 5,        -- active recipes
  'numeric', 6,        -- conditions per recipe
  'numeric', 10,       -- steps per recipe
  'numeric', 4,        -- customer messages per enrollment
  'numeric', 15,       -- min message spacing minutes
  'numeric', 90,       -- max delay days
  'unlimited', null,   -- max enrollment duration days
  'owner@example.test'
);

update public.platform_package_versions
set status = 'published', published_at = now()
where id = 'c0000000-0000-0000-0000-0000000006c0';

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
values ('10000000-0000-0000-0000-0000000006c0', 'c0000000-0000-0000-0000-0000000006c0', now() - interval '2 minutes', 'provisioning', 'Automation overview test baseline');

-- 3. Shape: always the seven keys, ordered ------------------------------------------------------------
select is(jsonb_array_length(public.get_organization_automation_limits('10000000-0000-0000-0000-0000000006c0')), 7,
  'the overview always returns exactly the seven automation limits');
select is(
  (public.get_organization_automation_limits('10000000-0000-0000-0000-0000000006c0') -> 0 ->> 'limit_key'),
  'automation_active_recipes',
  'the overview is ordered by limit key');

-- 4. Package default path (no exception) --------------------------------------------------------------
-- Helper: the object for one key.
create or replace function pg_temp.limit_obj(p_org uuid, p_key text)
returns jsonb language sql stable as $fn$
  select obj
  from jsonb_array_elements(public.get_organization_automation_limits(p_org)) as obj
  where obj ->> 'limit_key' = p_key;
$fn$;

select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'package_default' ->> 'state'), 'numeric',
  'active recipes reports its numeric package default state');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'package_default' ->> 'value'), '5',
  'active recipes reports its numeric package default value');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'effective' ->> 'value'), '5',
  'with no exception the effective value equals the package default');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'effective' ->> 'source'), 'package',
  'with no exception the effective source is the package');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') ->> 'exception'), null,
  'a key with no exception reports a null exception');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_max_enrollment_duration_days') -> 'package_default' ->> 'state'), 'unlimited',
  'an unlimited package default is reported as unlimited');

-- 5. Active exception: precedence, author, reason, active flag ----------------------------------------
select public.apply_organization_limit_exception(
  '10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes', 'numeric', 2,
  now() - interval '30 seconds', null, 'auto-overview-active-override',
  'Reduce active recipes for this pilot.', 'owner@example.test'
);

select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'effective' ->> 'value'), '2',
  'an active exception wins as the effective value');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'effective' ->> 'source'), 'override',
  'an active exception is the effective source');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'package_default' ->> 'value'), '5',
  'the package default is still reported alongside an active exception');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'exception' ->> 'reason'), 'Reduce active recipes for this pilot.',
  'the exception carries its private reason');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'exception' ->> 'actor_owner_email'), 'owner@example.test',
  'the exception carries its acting owner email');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'exception' ->> 'is_active'), 'true',
  'an in-window exception is reported active');

-- 6. Scheduled/expired exception: shown but not effective --------------------------------------------
select public.apply_organization_limit_exception(
  '10000000-0000-0000-0000-0000000006c0', 'automation_max_steps_per_recipe', 'numeric', 99,
  now() + interval '1 day', null, 'auto-overview-future-override',
  'A future steps override.', 'owner@example.test'
);

select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_max_steps_per_recipe') -> 'effective' ->> 'value'), '10',
  'a future-dated exception does not change the effective value');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_max_steps_per_recipe') -> 'exception' ->> 'is_active'), 'false',
  'a future-dated exception is reported as not active');

-- 7. Not_included fallback (no assignment) -----------------------------------------------------------
select is(
  (select bool_and((obj -> 'effective' ->> 'state') = 'not_included')
   from jsonb_array_elements(public.get_organization_automation_limits('10000000-0000-0000-0000-0000000006d0')) as obj),
  true,
  'an organization with no assignment fails closed to not_included on every key');

select * from finish();
rollback;
