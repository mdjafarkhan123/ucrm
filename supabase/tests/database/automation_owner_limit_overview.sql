-- Contractor Settings Part 6B, slice 3b: owner Automation limit-overview read model.
-- Proves get_organization_automation_limits assembles, for all seven keys in one call: the edition default
-- (active recipes) or platform safety setting (the other six), the effective value/source taken from the
-- authoritative resolver, and the reasoned/effective-dated exception (author, reason, window, active flag).
-- Also proves the privilege matrix (owner-only), the not_included fallback with no agreement, and that a
-- scheduled exception is shown but does not become the effective value.
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

-- A published edition with five active recipes, agreed by Org C; Org D has no agreement. The six safety
-- limits are one platform setting (ADR 0003 decision 4), set here and rolled back with the test.
insert into public.packages (id, slug, visibility)
values ('c0000000-0000-0000-0000-0000000006c1', 'automation-overview-test', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents)
values ('c0000000-0000-0000-0000-0000000006c0', 'c0000000-0000-0000-0000-0000000006c1',
  'Automation Overview Test', 9900);
insert into public.package_edition_capabilities (edition_id, capability_key)
values ('c0000000-0000-0000-0000-0000000006c0', 'automations');
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
values ('c0000000-0000-0000-0000-0000000006c0', 'automation_active_recipes', 'numeric', 5);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id = 'c0000000-0000-0000-0000-0000000006c0';

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
values ('10000000-0000-0000-0000-0000000006c0', 'c0000000-0000-0000-0000-0000000006c0', 'month', 9900,
  now() - interval '2 minutes', 'test_reset', 'Automation overview test baseline');

update public.platform_automation_safety_limits as safety
set limit_state = v.limit_state, limit_value = v.limit_value
from (values
  ('automation_max_conditions_per_recipe', 'numeric', 6),
  ('automation_max_steps_per_recipe', 'numeric', 10),
  ('automation_max_customer_messages_per_enrollment', 'numeric', 4),
  ('automation_min_customer_message_spacing_minutes', 'numeric', 15),
  ('automation_max_delay_days', 'numeric', 90),
  ('automation_max_enrollment_duration_days', 'unlimited', null)
) as v (limit_key, limit_state, limit_value)
where safety.limit_key = v.limit_key;

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
  'an unlimited platform safety limit is reported as unlimited');

-- 5. Active exception: precedence, author, reason, active flag ----------------------------------------
insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at,
   actor_owner_email)
values ('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes', 'numeric', 2, 'Reduce active recipes for this pilot.',
  now() - interval '30 seconds', '2100-01-01T00:00:00Z', 'owner@example.test');

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

-- 6. Scheduled exception: shown but not effective ------------------------------------------------------
insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at,
   actor_owner_email)
values ('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes', 'numeric', 99, 'A future recipes exception.',
  now() + interval '1 day', '2100-01-01T00:00:00Z', 'owner@example.test');

select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'effective' ->> 'value'), '2',
  'a future-dated exception does not change the effective value');
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006c0', 'automation_active_recipes') -> 'exception' ->> 'is_active'), 'false',
  'a future-dated exception is reported as not active');

-- 7. Not_included fallback (no agreement) ------------------------------------------------------------
select is((pg_temp.limit_obj('10000000-0000-0000-0000-0000000006d0', 'automation_active_recipes') -> 'effective' ->> 'state'),
  'not_included',
  'an organization with no agreement fails closed to not_included active recipes');

select * from finish();
rollback;
