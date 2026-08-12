-- Publish the first approved package definitions from the legacy entitlement matrix.
-- The legacy rows remain in place during the compatibility period; these immutable
-- versions become the source for new versioned assignments.

insert into public.platform_package_versions (
  package_id,
  version_number,
  status,
  display_name,
  public_description,
  value_explanation,
  price_usd_cents,
  currency,
  billing_period
)
select
  package.package_id,
  1,
  'draft',
  seed.display_name,
  seed.public_description,
  seed.value_explanation,
  seed.price_usd_cents,
  'USD',
  'monthly'
from (
  values
    ('starter', 'Starter', 'The essential workspace for running day-to-day contractor operations.', 'Core CRM workflow for a small field-service team.', 7900),
    ('growth', 'Growth', 'A connected workspace for teams ready to manage more leads, customers, and communication.', 'Expanded sales, communication, portal, automation, and reporting capabilities.', 14900),
    ('elite', 'Elite', 'The complete contractor operating workspace with advanced growth and integration capabilities.', 'The broadest CRM, growth, dispatch, and integration coverage.', 24900)
) as seed(package_key, display_name, public_description, value_explanation, price_usd_cents)
join public.platform_packages as package on package.package_key = seed.package_key
on conflict (package_id, version_number) do nothing;

insert into public.platform_package_version_features (package_version_id, feature_key)
select version.id, feature.feature_key
from public.platform_package_versions as version
join public.platform_packages as package on package.package_id = version.package_id
join public.package_features as feature on feature.package_key = package.package_key
where version.version_number = 1
  and version.status = 'draft'
on conflict do nothing;

insert into public.platform_package_version_limits (
  package_version_id,
  limit_key,
  limit_state,
  limit_value
)
select
  version.id,
  legacy.limit_key,
  case when legacy.is_unlimited then 'unlimited' else 'numeric' end,
  case when legacy.is_unlimited then null else legacy.limit_value end
from public.platform_package_versions as version
join public.platform_packages as package on package.package_id = version.package_id
join public.package_limits as legacy on legacy.package_key = package.package_key
where version.version_number = 1
  and version.status = 'draft'
on conflict do nothing;

update public.platform_package_versions
set status = 'published',
    published_at = coalesce(published_at, now())
where version_number = 1
  and status = 'draft';

update public.platform_packages
set status = 'published'
where package_id in (
  select package_id
  from public.platform_package_versions
  where version_number = 1
    and status = 'published'
);

-- The owner operation records a legacy package assignment and its billing state
-- atomically. It is callable only by the server-side service role.
create or replace function public.record_legacy_organization_package(
  target_organization_id uuid,
  target_package_version_id uuid,
  target_paid_through_date date,
  target_reason text
)
returns void
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  version_status text;
  package_status text;
  assignment_exists boolean;
begin
  if target_paid_through_date is null then
    raise exception 'A paid-through date is required for a legacy assignment.' using errcode = 'check_violation';
  end if;

  if target_reason is null or char_length(trim(target_reason)) not between 1 and 500 then
    raise exception 'A private reason is required for a legacy assignment.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organizations where id = target_organization_id;
  if not found then
    raise exception 'The organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  select version.status, package.status
  into version_status, package_status
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = target_package_version_id;

  if version_status is null or package_status is null then
    raise exception 'The package version does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if version_status <> 'published' or package_status <> 'published' then
    raise exception 'A legacy organization must use a published package version.' using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from public.organization_package_assignments
    where organization_id = target_organization_id
  ) into assignment_exists;
  if assignment_exists then
    raise exception 'This organization already has a versioned package assignment.' using errcode = 'unique_violation';
  end if;

  insert into public.organization_package_assignments (
    organization_id, package_version_id, assignment_source, reason
  ) values (
    target_organization_id, target_package_version_id, 'legacy_owner_action', trim(target_reason)
  );

  insert into public.organization_billing_accounts (
    organization_id, paid_through_date, paid_through_source
  ) values (
    target_organization_id, target_paid_through_date, 'legacy_owner_action'
  )
  on conflict (organization_id) do update
    set paid_through_date = excluded.paid_through_date,
        paid_through_source = excluded.paid_through_source,
        updated_at = now();
end;
$$;

revoke all on function public.record_legacy_organization_package(uuid, uuid, date, text) from public;
grant execute on function public.record_legacy_organization_package(uuid, uuid, date, text) to service_role;
