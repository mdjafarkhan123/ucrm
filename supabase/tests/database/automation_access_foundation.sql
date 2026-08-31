-- Contractor Settings Part 6B: Automation access foundation.
-- Proves the entitlement/permission seed, the single effective_automation_limits resolver (package
-- default, override precedence, effective dates, every key, not_included fallback, cross-tenant denial),
-- and the two-axis authority writer/read model (engage, idempotency, no-op, independence, release).
--
-- Written for a single-session, single-transaction run (Supabase MCP execute_sql or `supabase test db`).
-- Do not run through a runner that executes each statement separately: `set local role` would not survive.
begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

-- 1. Privilege matrix ---------------------------------------------------------------------------------
select is(has_function_privilege('anon', 'public.effective_automation_limits(uuid, timestamptz)', 'execute'), false,
  'anonymous callers cannot read automation limits');
select is(has_function_privilege('authenticated', 'public.effective_automation_limits(uuid, timestamptz)', 'execute'), true,
  'a signed-in session can read automation limits');
select is(has_function_privilege('service_role', 'public.effective_automation_limits(uuid, timestamptz)', 'execute'), true,
  'the owner service role can read automation limits');
select is(has_function_privilege('authenticated', 'public.manage_platform_package_automation_limits(uuid, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text)', 'execute'), false,
  'contractors cannot write package automation limits');
select is(has_function_privilege('service_role', 'public.manage_platform_package_automation_limits(uuid, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text, integer, text)', 'execute'), true,
  'the owner service role can write package automation limits');
select is(has_function_privilege('authenticated', 'public.set_organization_automation_authority(uuid, text, boolean, text, text, uuid)', 'execute'), false,
  'contractors cannot write automation authority');
select is(has_function_privilege('service_role', 'public.set_organization_automation_authority(uuid, text, boolean, text, text, uuid)', 'execute'), true,
  'the owner service role can write automation authority');
select is(has_function_privilege('authenticated', 'public.get_organization_automation_authority(uuid)', 'execute'), false,
  'contractors cannot read the owner automation authority model');
select is(has_function_privilege('service_role', 'public.get_organization_automation_authority(uuid)', 'execute'), true,
  'the owner service role can read the automation authority model');

-- 2. Fixtures -----------------------------------------------------------------------------------------
set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000006a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'auto-a@example.test', 'test', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000006b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'auto-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('10000000-0000-0000-0000-0000000006a0', 'Automation Org A', 'automation-org-a', 'active'),
  ('10000000-0000-0000-0000-0000000006b0', 'Automation Org B', 'automation-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-0000000006a0', '00000000-0000-0000-0000-0000000006a1', 'admin'),
  ('10000000-0000-0000-0000-0000000006b0', '00000000-0000-0000-0000-0000000006b1', 'admin');

-- A published package version carrying all seven automation limits, assigned to Org A. An assignment
-- must reference a published version, so the seed elite published version is retired first (rolled back
-- with the whole test). Automation limits are written while the version is still a draft, then published.
update public.platform_package_versions
set status = 'retired', retired_at = now()
where package_id = (select package_id from public.platform_packages where package_key = 'elite')
  and status = 'published';

insert into public.platform_package_versions
  (id, package_id, version_number, status, display_name, public_description, value_explanation, price_usd_cents)
select 'c0000000-0000-0000-0000-0000000006f0', package_id, 990, 'draft',
  'Automation Foundation Test Draft', 'Automation foundation test version', 'Automation limits test', 9900
from public.platform_packages where package_key = 'elite';

select public.manage_platform_package_automation_limits(
  'c0000000-0000-0000-0000-0000000006f0',
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
where id = 'c0000000-0000-0000-0000-0000000006f0';

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
values ('10000000-0000-0000-0000-0000000006a0', 'c0000000-0000-0000-0000-0000000006f0', now() - interval '2 minutes', 'provisioning', 'Automation foundation test baseline');

-- 3. Seed: feature and permissions --------------------------------------------------------------------
select is((select count(*)::integer from public.features where feature_key = 'automations'), 1,
  'the automations feature exists in the catalog');
select is(
  (select (
    (select count(*) from public.package_features where feature_key = 'automations')
    + (select count(*) from public.platform_package_version_features where feature_key = 'automations')
  )::integer),
  0,
  'the automations feature is attached to no package, so no ordinary contractor can reach it in 6B');
select is((select count(*)::integer from public.role_permissions
  where role = 'owner' and permission_key like 'automations.%'), 4,
  'owner receives all four automation permissions by default');
select is((select count(*)::integer from public.role_permissions
  where role = 'field' and permission_key like 'automations.%'), 0,
  'employees receive no automation permission in 6B');

-- 4. Resolver: package default path (all seven keys) --------------------------------------------------
select is((select count(*)::integer from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())), 7,
  'the resolver always returns exactly the seven automation limits');
select is((select state from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'numeric',
  'active recipes resolves the package numeric state');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 5,
  'active recipes resolves the package value');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'package',
  'active recipes identifies the package as its source');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_conditions_per_recipe'), 6,
  'conditions per recipe resolves the package value');
select is((select is_unlimited from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_enrollment_duration_days'), true,
  'an unlimited package limit resolves as unlimited');
select is((select state from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_enrollment_duration_days'), 'unlimited',
  'the unlimited limit keeps its unlimited state');

-- 5. Resolver: not_included fallback (no assignment) --------------------------------------------------
select is((select bool_and(state = 'not_included') from public.effective_automation_limits('10000000-0000-0000-0000-0000000006b0', now())), true,
  'an organization with no assignment fails closed to not_included on every key');
select is((select count(*)::integer from public.effective_automation_limits('10000000-0000-0000-0000-0000000006b0', now())), 7,
  'the not_included fallback still returns all seven keys');

-- 6. Resolver: override precedence and effective dates ------------------------------------------------
select is((public.apply_organization_limit_exception(
  '10000000-0000-0000-0000-0000000006a0', 'automation_active_recipes', 'numeric', 2,
  now() - interval '30 seconds', null, 'auto-active-recipes-override',
  'Reduce active recipes for this pilot organization.', 'owner@example.test'
) ->> 'applied'), 'true', 'an automation limit exception applies through the established command');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 2,
  'an active override wins over the package value');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'override',
  'the resolver identifies the override as its source');
select is((public.apply_organization_limit_exception(
  '10000000-0000-0000-0000-0000000006a0', 'automation_max_steps_per_recipe', 'numeric', 99,
  now() - interval '2 hours', now() - interval '1 hour', 'auto-steps-expired-override',
  'A steps override that has already expired.', 'owner@example.test'
) ->> 'applied'), 'true', 'an expired-window exception still records');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_steps_per_recipe'), 10,
  'an expired override is ignored and the package value applies');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_steps_per_recipe'), 'package',
  'the expired override does not become the source');

-- 7. Authority writer: engage, idempotency, no-op, independence, release ------------------------------
select is((public.set_organization_automation_authority(
  '10000000-0000-0000-0000-0000000006a0', 'operational', true, 'Investigating suspected abuse.',
  'owner@example.test', 'e0000000-0000-0000-0000-000000000001'
) ->> 'applied'), 'true', 'an operational disable applies');
select is((select operational_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'disabled',
  'the projection records the operational disable');
select isnt((select operational_reason from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), null,
  'the projection records a safe operational reason');
select is((select count(*)::integer from public.automation_authority_events
  where organization_id = '10000000-0000-0000-0000-0000000006a0' and event_kind = 'operational_disable_engaged'), 1,
  'the operational disable appends exactly one history event');
select is((select count(*)::integer from public.platform_owner_audit_events
  where target_key = '10000000-0000-0000-0000-0000000006a0'
    and event_type = 'automations.authority_operational_disable_engaged'), 1,
  'the operational disable writes an owner audit event');
select is((public.set_organization_automation_authority(
  '10000000-0000-0000-0000-0000000006a0', 'operational', true, 'Investigating suspected abuse.',
  'owner@example.test', 'e0000000-0000-0000-0000-000000000001'
) ->> 'applied'), 'false', 'the same idempotency key does not reapply');
select is((public.set_organization_automation_authority(
  '10000000-0000-0000-0000-0000000006a0', 'operational', true, 'Still disabled.',
  'owner@example.test', 'e0000000-0000-0000-0000-000000000009'
) ->> 'no_change'), 'true', 'engaging an already-disabled axis is a no-op');
select is((public.set_organization_automation_authority(
  '10000000-0000-0000-0000-0000000006a0', 'security', true, 'Security hold pending review.',
  'owner@example.test', 'e0000000-0000-0000-0000-000000000002'
) ->> 'applied'), 'true', 'a security suspension applies on a second axis');
select is((select security_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'suspended',
  'the projection records the security suspension');
select is((select operational_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'disabled',
  'the two axes are independent: operational stays disabled under a security suspension');
select is((public.set_organization_automation_authority(
  '10000000-0000-0000-0000-0000000006a0', 'operational', false, 'Abuse review cleared.',
  'owner@example.test', 'e0000000-0000-0000-0000-000000000003'
) ->> 'applied'), 'true', 'releasing the operational axis applies');
select is((select operational_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'enabled',
  'the operational axis returns to enabled after release');
select is((select security_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'suspended',
  'releasing operational leaves the security suspension in place');

-- 8. Owner read model ---------------------------------------------------------------------------------
select is((public.get_organization_automation_authority('10000000-0000-0000-0000-0000000006a0') ->> 'security_state'), 'suspended',
  'the owner read model reports the current security state');
select is(jsonb_array_length(public.get_organization_automation_authority('10000000-0000-0000-0000-0000000006a0') -> 'recent_events'), 3,
  'the owner read model lists the three applied authority events');

-- 9. Member perspective under RLS: own overrides visible, package draft hidden, cross-tenant denied ----
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000006a1', true);

select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 2,
  'a member sees their own active-recipes override');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'override',
  'the override is the member-visible source');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_conditions_per_recipe'), 6,
  'a member sees their published package conditions limit under RLS');
select is((select bool_and(state = 'not_included') from public.effective_automation_limits('10000000-0000-0000-0000-0000000006b0', now())), true,
  'a member of Org A resolves nothing but not_included for Org B (cross-tenant denial)');
select is((select security_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'suspended',
  'a member can read their own organization authority projection');
select is((select count(*)::integer from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006b0'), 0,
  'a member cannot read another organization authority projection');

select * from finish();
rollback;
