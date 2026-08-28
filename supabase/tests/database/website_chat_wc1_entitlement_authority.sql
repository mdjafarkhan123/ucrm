-- Website Chat WC1: platform entitlement authority. Mirrors
-- communications_email_allowance_exceptions.sql's shape for the two new limit_keys
-- (website_chat_widgets, website_chat_accepted_conversations), their own SQL authority
-- functions, and the widened apply_organization_limit_exception.
begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- 1. Privilege matrix for the three new/extended functions -------------------------------------------------

select is(
  has_function_privilege('anon', 'public.effective_website_chat_widgets_limit(uuid, timestamptz)', 'execute'),
  false,
  'anonymous callers cannot read the website chat widgets entitlement'
);
select is(
  has_function_privilege('authenticated', 'public.effective_website_chat_widgets_limit(uuid, timestamptz)', 'execute'),
  true,
  'a signed-in session can read the website chat widgets entitlement, same as effective_employee_seat_limit'
);
select is(
  has_function_privilege('service_role', 'public.effective_website_chat_widgets_limit(uuid, timestamptz)', 'execute'),
  true,
  'the owner service role can read the website chat widgets entitlement'
);
select is(
  has_function_privilege('anon', 'public.get_organization_communication_website_chat_allowance(uuid, timestamptz)', 'execute'),
  false,
  'anonymous callers cannot read website chat allowance authority'
);
select is(
  has_function_privilege('authenticated', 'public.get_organization_communication_website_chat_allowance(uuid, timestamptz)', 'execute'),
  false,
  'contractors cannot read owner website chat allowance authority'
);
select is(
  has_function_privilege('service_role', 'public.get_organization_communication_website_chat_allowance(uuid, timestamptz)', 'execute'),
  true,
  'the owner service role can read website chat allowance authority'
);
select is(
  has_function_privilege('anon', 'public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text)', 'execute'),
  false,
  'anonymous callers cannot write package website chat limits'
);
select is(
  has_function_privilege('authenticated', 'public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text)', 'execute'),
  false,
  'contractors cannot write package website chat limits'
);
select is(
  has_function_privilege('service_role', 'public.manage_platform_package_website_chat_limits(uuid, text, integer, text, integer, text)', 'execute'),
  true,
  'the owner service role can write package website chat limits'
);

set local role postgres;

-- 2. Organization override path: apply_organization_limit_exception + effective_website_chat_widgets_limit --

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000003ba', 'Website Chat Entitlement Test', 'website-chat-entitlement-test', 'active');

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select '90000000-0000-0000-0000-0000000003ba', id, now() - interval '2 minutes', 'provisioning', 'Website Chat entitlement test baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

select is(
  (select state from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-0000000003ba', now())),
  'not_included',
  'a package with no website_chat_widgets row falls back to not_included, not an error'
);

select is(
  (public.apply_organization_limit_exception(
    '90000000-0000-0000-0000-0000000003ba', 'website_chat_widgets', 'numeric', 4,
    now() - interval '30 seconds', null, 'website-chat-widgets-exception-1',
    'Approve a pilot widget allowance for this organization.', 'owner@example.test'
  ) ->> 'applied'),
  'true',
  'a website chat widgets exception applies through the established command'
);
select is(
  (select limit_state from public.organization_limit_overrides
   where organization_id = '90000000-0000-0000-0000-0000000003ba' and limit_key = 'website_chat_widgets'),
  'numeric',
  'the widgets override keeps its numeric state'
);
select is(
  (select state from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-0000000003ba', now())),
  'numeric',
  'the effective widgets limit resolves the current exception'
);
select is(
  (select value from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-0000000003ba', now())),
  4,
  'the effective widgets limit resolves the exception value'
);
select is(
  (select source from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-0000000003ba', now())),
  'override',
  'the effective widgets limit identifies the exception as its source'
);

-- 3. Organization override path: get_organization_communication_website_chat_allowance -----------------------

select is(
  (public.apply_organization_limit_exception(
    '90000000-0000-0000-0000-0000000003ba', 'website_chat_accepted_conversations', 'unlimited', null,
    now() - interval '30 seconds', null, 'website-chat-conversations-exception-1',
    'Approve unlimited accepted conversations for this pilot.', 'owner@example.test'
  ) ->> 'applied'),
  'true',
  'an accepted-conversations exception applies through the same established command'
);
select is(
  (select is_unlimited from public.organization_limit_overrides
   where organization_id = '90000000-0000-0000-0000-0000000003ba' and limit_key = 'website_chat_accepted_conversations'),
  true,
  'the accepted-conversations override is stored as unlimited'
);
select is(
  (select effective_state from public.get_organization_communication_website_chat_allowance(
    '90000000-0000-0000-0000-0000000003ba', now()
  )),
  'unlimited',
  'the owner read model resolves the current accepted-conversations exception'
);
select is(
  (select effective_source from public.get_organization_communication_website_chat_allowance(
    '90000000-0000-0000-0000-0000000003ba', now()
  )),
  'override',
  'the owner read model identifies the exception as the source'
);
select is(
  (select period_id from public.get_organization_communication_website_chat_allowance(
    '90000000-0000-0000-0000-0000000003ba', now()
  )),
  null,
  'the read model reports no usage period until one is opened by later work'
);
select is(
  (select count(*)::integer from public.get_organization_communication_website_chat_allowance(
    '90000000-0000-0000-0000-0000000003ba', now()
  )),
  1,
  'the owner read model always returns exactly the one accepted-conversations row'
);

-- 4. Package-side write path + the numeric-floor correction (20260902150200) ----------------------------------

select lives_ok($$select public.manage_platform_package_version(
  'create_draft', 'elite', null, 'Elite WC1 Test Draft', 'Draft used only for the WC1 pgTAP test',
  'Draft value', 24900, array['sales.pipeline']::text[], 'numeric', 60, 'owner@example.test'
)$$, 'the owner can create a package draft to test website chat limit writes');

select lives_ok($$select public.manage_platform_package_website_chat_limits(
  (select version.id from public.platform_package_versions as version
     join public.platform_packages as package on package.package_id = version.package_id
   where package.package_key = 'elite' and version.status = 'draft'),
  'numeric', 5, 'unlimited', null, 'owner@example.test'
)$$, 'the owner can set both website chat limits on a draft version');

select is(
  (select limit_value from public.platform_package_version_limits
   where package_version_id = (select version.id from public.platform_package_versions as version
     join public.platform_packages as package on package.package_id = version.package_id
     where package.package_key = 'elite' and version.status = 'draft')
     and limit_key = 'website_chat_widgets'),
  5,
  'the draft stores the requested widgets value'
);
select is(
  (select limit_state from public.platform_package_version_limits
   where package_version_id = (select version.id from public.platform_package_versions as version
     join public.platform_packages as package on package.package_id = version.package_id
     where package.package_key = 'elite' and version.status = 'draft')
     and limit_key = 'website_chat_accepted_conversations'),
  'unlimited',
  'the draft stores the requested accepted-conversations state'
);

select throws_ok($$select public.manage_platform_package_website_chat_limits(
  (select version.id from public.platform_package_versions as version
     join public.platform_packages as package on package.package_id = version.package_id
   where package.package_key = 'elite' and version.status = 'draft'),
  'numeric', 0, 'unlimited', null, 'owner@example.test'
)$$, '23514', null, 'a numeric widgets value of zero is rejected by the raised floor, matching every other package limit');

select * from finish();
rollback;
