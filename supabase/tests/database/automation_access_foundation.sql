-- Contractor Settings Part 6B: Automation access foundation.
-- Proves the entitlement/permission seed, the single effective_automation_limits resolver (edition
-- allowance, platform safety limits, exception precedence, effective dates, every key, not_included
-- fallback, cross-tenant denial),
-- and the two-axis authority writer/read model (engage, idempotency, no-op, independence, release).
--
-- Written for a single-session, single-transaction run (Supabase MCP execute_sql or `supabase test db`).
-- Do not run through a runner that executes each statement separately: `set local role` would not survive.
begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

-- 1. Privilege matrix ---------------------------------------------------------------------------------
select is(has_function_privilege('anon', 'public.effective_automation_limits(uuid, timestamptz)', 'execute'), false,
  'anonymous callers cannot read automation limits');
select is(has_function_privilege('authenticated', 'public.effective_automation_limits(uuid, timestamptz)', 'execute'), true,
  'a signed-in session can read automation limits');
select is(has_function_privilege('service_role', 'public.effective_automation_limits(uuid, timestamptz)', 'execute'), true,
  'the owner service role can read automation limits');
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
  ('10000000-0000-0000-0000-0000000006b0', 'Automation Org B', 'automation-org-b', 'active'),
  ('10000000-0000-0000-0000-0000000006c0', 'Automation Org C', 'automation-org-c', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('10000000-0000-0000-0000-0000000006a0', '00000000-0000-0000-0000-0000000006a1', 'admin'),
  ('10000000-0000-0000-0000-0000000006b0', '00000000-0000-0000-0000-0000000006b1', 'admin');

-- A published edition with automations and five active recipes, agreed by Org A. Org B is on the test
-- package (unlimited recipes); Org C has no agreement. The six safety limits are one platform setting for
-- every organization (ADR 0003 decision 4), set here for the test and rolled back with it.
insert into public.packages (id, slug, visibility)
values ('c0000000-0000-0000-0000-0000000006f1', 'automation-foundation-test', 'private');
insert into public.package_editions (id, package_id, name, monthly_price_usd_cents)
values ('c0000000-0000-0000-0000-0000000006f0', 'c0000000-0000-0000-0000-0000000006f1',
  'Automation Foundation Test', 9900);
insert into public.package_edition_capabilities (edition_id, capability_key)
values ('c0000000-0000-0000-0000-0000000006f0', 'automations');
insert into public.package_edition_allowances (edition_id, allowance_key, allowance_state, allowance_value)
values ('c0000000-0000-0000-0000-0000000006f0', 'automation_active_recipes', 'numeric', 5);
update public.package_editions set status = 'published', edition_number = 1, published_at = now()
where id = 'c0000000-0000-0000-0000-0000000006f0';

insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
values ('10000000-0000-0000-0000-0000000006a0', 'c0000000-0000-0000-0000-0000000006f0', 'month', 9900,
  now() - interval '2 minutes', 'test_reset', 'Automation foundation test baseline');
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
select '10000000-0000-0000-0000-0000000006b0', edition.id, 'month', 0, now() - interval '2 minutes', 'test_reset',
  'Automation foundation test baseline'
from public.package_editions edition
join public.packages package on package.id = edition.package_id
where package.slug = 'test-package' and edition.status = 'published';

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

-- 3. Seed: feature and permissions --------------------------------------------------------------------
select is((select count(*)::integer from public.features where feature_key = 'automations'), 1,
  'the automations feature exists in the catalog');
select is((select kind from public.package_capabilities where capability_key = 'automations'), 'extra',
  'automations is an extra capability, so only packages that include it reach it');
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
  'conditions per recipe resolves the platform value');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_conditions_per_recipe'), 'platform',
  'the safety limits identify the platform setting as their source');
select is((select is_unlimited from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_enrollment_duration_days'), true,
  'an unlimited safety limit resolves as unlimited');
select is((select state from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_enrollment_duration_days'), 'unlimited',
  'the unlimited limit keeps its unlimited state');

-- 5. Resolver: not_included fallback (no agreement) ---------------------------------------------------
select is((select state from public.effective_automation_limits('10000000-0000-0000-0000-0000000006c0', now())
  where limit_key = 'automation_active_recipes'), 'not_included',
  'an organization with no agreement fails closed to not_included active recipes');
select is((select bool_and(source = 'platform') from public.effective_automation_limits('10000000-0000-0000-0000-0000000006c0', now())
  where limit_key <> 'automation_active_recipes'), true,
  'the safety limits still come from the one platform setting');
select is((select count(*)::integer from public.effective_automation_limits('10000000-0000-0000-0000-0000000006c0', now())), 7,
  'the not_included fallback still returns all seven keys');

-- 6. Resolver: exception precedence and effective dates -----------------------------------------------
insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email)
values ('10000000-0000-0000-0000-0000000006a0', 'automation_active_recipes', 'numeric', 99,
  'An active-recipes exception that has already ended.', now() - interval '2 hours', now() - interval '1 hour',
  'owner@example.test');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 5,
  'an ended exception is ignored and the edition value applies');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'package',
  'the ended exception does not become the source');

insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email)
values ('10000000-0000-0000-0000-0000000006a0', 'automation_active_recipes', 'numeric', 2,
  'Reduce active recipes for this pilot organization.', now() - interval '30 seconds', now() + interval '30 days',
  'owner@example.test');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 2,
  'an active exception wins over the edition value');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'override',
  'the resolver identifies the exception as its source');

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

-- 9. Member perspective under RLS: own exceptions visible, cross-tenant denied ----------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000006a1', true);

select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 2,
  'a member sees their own active-recipes exception');
select is((select source from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_active_recipes'), 'override',
  'the exception is the member-visible source');
select is((select value from public.effective_automation_limits('10000000-0000-0000-0000-0000000006a0', now())
  where limit_key = 'automation_max_conditions_per_recipe'), 6,
  'a member sees the platform conditions limit under RLS');
select is((select state from public.effective_automation_limits('10000000-0000-0000-0000-0000000006b0', now())
  where limit_key = 'automation_active_recipes'), 'not_included',
  'a member of Org A cannot read Org B''s unlimited active recipes (cross-tenant denial)');
select is((select security_state from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006a0'), 'suspended',
  'a member can read their own organization authority projection');
select is((select count(*)::integer from public.organization_automation_authority
  where organization_id = '10000000-0000-0000-0000-0000000006b0'), 0,
  'a member cannot read another organization authority projection');

select * from finish();
rollback;
