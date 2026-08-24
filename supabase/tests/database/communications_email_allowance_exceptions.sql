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

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select '90000000-0000-0000-0000-0000000002ba', id, now() - interval '2 minutes', 'provisioning', 'Email allowance test baseline'
from public.platform_package_versions
where status = 'published'
order by version_number, id
limit 1;

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at)
values ('90000000-0000-0000-0000-0000000002ba', now() - interval '1 minute', now() + interval '29 days');

select is(
  (public.apply_organization_limit_exception(
    '90000000-0000-0000-0000-0000000002ba', 'operational_email_recipients', 'numeric', 2500,
    now() - interval '30 seconds', null, 'email-allowance-exception-1',
    'Approve the launch allowance for this pilot.', 'owner@example.test'
  ) ->> 'applied'),
  'true',
  'an operational email allowance exception applies through the established command'
);
select is(
  (select limit_state from public.organization_limit_overrides
   where organization_id = '90000000-0000-0000-0000-0000000002ba'
     and limit_key = 'operational_email_recipients'),
  'numeric',
  'the email override keeps its numeric state'
);
select is(
  (select limit_value from public.organization_limit_overrides
   where organization_id = '90000000-0000-0000-0000-0000000002ba'
     and limit_key = 'operational_email_recipients'),
  2500,
  'the email override keeps its recipient value'
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
