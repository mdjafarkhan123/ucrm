-- Versioned organization package assignments.
--
-- Assignments are append-only events. The current package is the assignment with
-- the greatest effective_at for an organization. This preserves every package
-- change without mutating the organization's historical commercial record.

create table public.organization_package_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  package_version_id uuid not null references public.platform_package_versions(id),
  effective_at timestamptz not null default now(),
  assignment_source text not null check (
    assignment_source in ('legacy_owner_action', 'provisioning', 'package_change')
  ),
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (organization_id, effective_at)
);

create index organization_package_assignments_current_idx
  on public.organization_package_assignments (organization_id, effective_at desc);

create index organization_package_assignments_version_idx
  on public.organization_package_assignments (package_version_id, organization_id);

create or replace function private.validate_organization_package_assignment()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  version_status text;
  package_status text;
begin
  select version.status, package.status
  into version_status, package_status
  from public.platform_package_versions as version
  join public.platform_packages as package on package.package_id = version.package_id
  where version.id = new.package_version_id;

  if version_status is null or package_status is null then
    raise exception 'The package version does not exist.' using errcode = 'foreign_key_violation';
  end if;

  if version_status <> 'published' or package_status <> 'published' then
    raise exception 'A new organization package assignment must use a published package version.'
      using errcode = 'check_violation';
  end if;

  if new.effective_at > now() then
    raise exception 'Organization package assignments cannot be scheduled for a future date.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_organization_package_assignment() from public;

create trigger organization_package_assignments_validate
before insert on public.organization_package_assignments
for each row execute function private.validate_organization_package_assignment();

create or replace function private.prevent_organization_package_assignment_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Organization package assignment history is append-only.' using errcode = 'check_violation';
end;
$$;

revoke all on function private.prevent_organization_package_assignment_mutation() from public;

create trigger organization_package_assignments_immutable
before update or delete on public.organization_package_assignments
for each row execute function private.prevent_organization_package_assignment_mutation();

alter table public.organization_package_assignments enable row level security;

revoke all on public.organization_package_assignments from anon, authenticated;
grant select, insert on public.organization_package_assignments to service_role;;
