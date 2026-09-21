-- Part 6B follow-up: legacy package assignment through the commercial command seam.
--
-- The package assignment remains a compatibility operation for organizations that predate
-- versioned commercial state. Its paid-through baseline must use the immutable commercial ledger
-- and projection; the legacy billing tables are frozen historical records after Part 6B.

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

  perform public.apply_organization_commercial_command(
    target_organization_id => target_organization_id,
    event_kind => 'paid_through_adjusted',
    idempotency_key => 'legacy-package-assignment:' || target_organization_id::text,
    summary => 'Legacy paid-through baseline recorded.',
    paid_through_effect => 'set',
    paid_through_date => target_paid_through_date,
    private_reason => trim(target_reason),
    is_legacy_import => true,
    safe_kind => 'access_period_updated',
    safe_payload => jsonb_build_object('paid_through_date', target_paid_through_date)
  );
end;
$$;

revoke all on function public.record_legacy_organization_package(uuid, uuid, date, text) from public;
grant execute on function public.record_legacy_organization_package(uuid, uuid, date, text) to service_role;
