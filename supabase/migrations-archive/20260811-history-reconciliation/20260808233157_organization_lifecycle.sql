alter table public.organizations
add column lifecycle_status text not null default 'pending_setup'
check (lifecycle_status in ('pending_setup', 'active', 'suspended'));

create or replace function private.is_organization_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and organization.lifecycle_status = 'active'
  );
$$;

revoke all on function private.is_organization_member(uuid) from public;
grant execute on function private.is_organization_member(uuid) to authenticated;
