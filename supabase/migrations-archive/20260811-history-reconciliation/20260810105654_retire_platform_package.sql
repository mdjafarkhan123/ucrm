-- Owner-only retirement; preserve every organization's current package access.
create or replace function public.retire_platform_package(target_package_key text, actor_email text)
returns uuid language plpgsql set search_path = pg_catalog, public as $$
declare package_row public.platform_packages%rowtype; before_state jsonb; after_state jsonb;
begin
  if actor_email is null or char_length(trim(actor_email)) = 0 then raise exception 'An owner email is required.' using errcode = 'not_null_violation'; end if;
  select * into package_row from public.platform_packages where package_key = target_package_key and status <> 'retired' for update;
  if not found then raise exception 'Package was not found.' using errcode = 'foreign_key_violation'; end if;
  if exists (
    select 1 from public.organization_package_assignments as assignment
    join public.platform_package_versions as version on version.id = assignment.package_version_id
    where version.package_id = package_row.package_id and not exists (
      select 1 from public.organization_package_assignments as later_assignment
      where later_assignment.organization_id = assignment.organization_id
      and (later_assignment.effective_at, later_assignment.id) > (assignment.effective_at, assignment.id)
    )
  ) or exists (
    select 1 from public.organizations as organization
    where not exists (select 1 from public.organization_package_assignments as assignment where assignment.organization_id = organization.id)
    and (organization.package_key = package_row.package_key or organization.scheduled_package_key = package_row.package_key)
  ) then raise exception 'Move every organization away from this package before retiring it.' using errcode = 'check_violation'; end if;
  before_state := to_jsonb(package_row);
  update public.platform_package_versions set status = 'retired', retired_at = coalesce(retired_at, now()) where package_id = package_row.package_id and status = 'published';
  update public.platform_packages set status = 'retired' where package_id = package_row.package_id returning * into package_row;
  after_state := to_jsonb(package_row);
  insert into public.platform_owner_audit_events (actor_owner_email, event_type, target_type, target_key, before_state, after_state)
  values (lower(trim(actor_email)), 'package.retire', 'platform_package', package_row.package_id::text, before_state, after_state);
  return package_row.package_id;
end;
$$;
revoke all on function public.retire_platform_package(text, text) from public;
grant execute on function public.retire_platform_package(text, text) to service_role;
