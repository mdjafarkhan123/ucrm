-- Website Chat WC1: platform entitlement authority. Mirrors
-- communications_email_allowance_exceptions.sql's shape for the two website chat allowances
-- (website_chat_widgets, website_chat_accepted_conversations): the edition sets them, and an
-- organization's package exception wins over the edition while it lasts.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

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
set local role postgres;

-- 2. Edition and exception path: effective_website_chat_widgets_limit -------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000003ba', 'Website Chat Entitlement Test', 'website-chat-entitlement-test', 'active');

-- The private test package: every working capability.
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
select '90000000-0000-0000-0000-0000000003ba', edition.id, 'month', 0, now() - interval '2 minutes', 'test_reset', 'Website Chat entitlement test baseline'
from public.package_editions edition
join public.packages package on package.id = edition.package_id
where package.slug = 'test-package' and edition.status = 'published';

select is(
  (select state from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-000000000399', now())),
  'not_included',
  'an organization with no agreement has no widgets, not an error'
);
select is(
  (select value from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-0000000003ba', now())),
  5,
  'the test package edition sets five widgets'
);
select is(
  (select source from public.effective_website_chat_widgets_limit('90000000-0000-0000-0000-0000000003ba', now())),
  'package',
  'without an exception the edition is the source'
);

insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email)
values ('90000000-0000-0000-0000-0000000003ba', 'website_chat_widgets', 'numeric', 4,
  'Approve a pilot widget allowance for this organization.', now() - interval '30 seconds',
  now() + interval '30 days', 'owner@example.test');

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

-- 3. Exception path: get_organization_communication_website_chat_allowance ---------------------------------

insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at, actor_owner_email)
values ('90000000-0000-0000-0000-0000000003ba', 'website_chat_accepted_conversations', 'unlimited', null,
  'Approve unlimited accepted conversations for this pilot.', now() - interval '30 seconds',
  now() + interval '30 days', 'owner@example.test');

select is(
  (select fallback_value from public.get_organization_communication_website_chat_allowance(
    '90000000-0000-0000-0000-0000000003ba', now()
  )),
  20,
  'the owner read model still shows the edition''s twenty conversations behind the exception'
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

select * from finish();
rollback;
