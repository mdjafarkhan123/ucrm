-- Same gap as organization_commercial_state/settings/free_access_events: resolveOrganizationAccess reads
-- organization_package_assignments first, via the request-scoped client, to find the org's active package
-- version. No grant and no policy existed, so this failed before commercial state was even reached.

create policy "members can view their organization package assignments"
on public.organization_package_assignments for select to authenticated
using (private.is_organization_member(organization_id));

grant select on public.organization_package_assignments to authenticated;
