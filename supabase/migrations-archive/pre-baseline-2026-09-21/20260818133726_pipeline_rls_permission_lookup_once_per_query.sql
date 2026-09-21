-- The Pipeline board policies called the membership and permission helpers once per returned row.
-- Measured on 50,000 opportunities: a 50-row page cost 11 ms and 766 buffers, against 0.18 ms and
-- 5 buffers for the same index scan without RLS. The answer is identical for every row in a query,
-- so it is resolved once here instead.

-- Returns the organizations the caller may use this permission in. No column is referenced, so
-- Postgres evaluates it a single time per query rather than per row. The rule inside is the same one
-- private.is_organization_member and private.has_permission apply together.
create or replace function private.permitted_organizations(target_permission_key text)
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select membership.organization_id
  from public.organization_members as membership
  join public.organizations as organization
    on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid())
    and organization.lifecycle_status = 'active'
    and coalesce(
      (
        select override.override_state = 'grant'
        from public.organization_member_permission_overrides as override
        where override.organization_id = membership.organization_id
          and override.user_id = membership.user_id
          and override.permission_key = target_permission_key
      ),
      exists (
        select 1
        from public.role_permissions as role_permission
        where role_permission.role = membership.role
          and role_permission.permission_key = target_permission_key
      )
    );
$$;

revoke all on function private.permitted_organizations(text) from public;
grant execute on function private.permitted_organizations(text) to authenticated;

drop policy "permitted members can view opportunities" on public.opportunities;
drop policy "permitted members can create opportunities" on public.opportunities;
drop policy "permitted members can update opportunities" on public.opportunities;
drop policy "permitted members can view opportunity stage events" on public.opportunity_stage_events;

create policy "permitted members can view opportunities"
on public.opportunities for select to authenticated
using (organization_id in (select private.permitted_organizations('pipeline.view')));

create policy "permitted members can create opportunities"
on public.opportunities for insert to authenticated
with check (organization_id in (select private.permitted_organizations('pipeline.edit')));

create policy "permitted members can update opportunities"
on public.opportunities for update to authenticated
using (organization_id in (select private.permitted_organizations('pipeline.edit')))
with check (organization_id in (select private.permitted_organizations('pipeline.edit')));

create policy "permitted members can view opportunity stage events"
on public.opportunity_stage_events for select to authenticated
using (organization_id in (select private.permitted_organizations('pipeline.view')));
