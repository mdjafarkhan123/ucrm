begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select is(
  has_function_privilege('anon', 'public.get_organization_communication_email_allowances(uuid, timestamptz)', 'execute'),
  false,
  'anonymous callers cannot read email allowance authority'
);
select is(
  has_function_privilege('authenticated', 'public.get_organization_communication_email_allowances(uuid, timestamptz)', 'execute'),
  false,
  'contractors cannot read owner email allowance authority'
);
select is(
  has_function_privilege('service_role', 'public.get_organization_communication_email_allowances(uuid, timestamptz)', 'execute'),
  true,
  'the owner service role can read email allowance authority'
);

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('90000000-0000-0000-0000-0000000002ba', 'Email Allowance Test', 'email-allowance-test', 'active');

-- The private test package: every working capability.
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
)
select '90000000-0000-0000-0000-0000000002ba', edition.id, 'month', 0, now() - interval '2 minutes', 'test_reset', 'Email allowance test baseline'
from public.package_editions edition
join public.packages package on package.id = edition.package_id
where package.slug = 'test-package' and edition.status = 'published';

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000002ba', now() - interval '1 minute', now() + interval '29 days');

select is(
  (select effective_source from public.get_organization_communication_email_allowances(
    '90000000-0000-0000-0000-0000000002ba', now()
  ) where limit_key = 'operational_email_recipients'),
  'package',
  'without an exception the edition sets the email allowance'
);

insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at,
   actor_owner_email)
values ('90000000-0000-0000-0000-0000000002ba', 'operational_email_recipients', 'numeric', 2500,
  'Approve the launch allowance for this pilot.', now() - interval '30 seconds', now() + interval '30 days',
  'owner@example.test');

select is(
  (select fallback_state from public.get_organization_communication_email_allowances(
    '90000000-0000-0000-0000-0000000002ba', now()
  ) where limit_key = 'operational_email_recipients'),
  'unlimited',
  'the owner read model still shows the edition''s allowance behind the exception'
);
select is(
  (select effective_value from public.get_organization_communication_email_allowances(
    '90000000-0000-0000-0000-0000000002ba', now()
  ) where limit_key = 'operational_email_recipients'),
  2500,
  'the exception''s recipient value is the effective allowance'
);
select is(
  (select effective_state from public.get_organization_communication_email_allowances(
    '90000000-0000-0000-0000-0000000002ba', now()
  ) where limit_key = 'operational_email_recipients'),
  'numeric',
  'the owner read model resolves the current exception'
);
select is(
  (select effective_source from public.get_organization_communication_email_allowances(
    '90000000-0000-0000-0000-0000000002ba', now()
  ) where limit_key = 'operational_email_recipients'),
  'override',
  'the owner read model identifies the exception as the source'
);
select is(
  (select count(*)::integer from public.get_organization_communication_email_allowances(
    '90000000-0000-0000-0000-0000000002ba', now()
  )),
  2,
  'the owner read model always returns both email capacities'
);

select * from finish();
rollback;
