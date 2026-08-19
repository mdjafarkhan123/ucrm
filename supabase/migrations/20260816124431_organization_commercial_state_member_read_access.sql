-- Bug found while verifying the Part 3 collaboration components: requireClientPermission ->
-- resolveOrganizationAccess reads organization_commercial_state, organization_commercial_settings, and
-- organization_free_access_events using the request-scoped (RLS-bound) client for every permission check
-- on the contractor side. These three tables have RLS enabled but were never granted SELECT to
-- `authenticated` and never got a policy, so every permission check for any org with commercial state
-- (i.e. every real active org) threw "permission denied" -- breaking not just this session's new routes
-- but the already-shipped Client/Property creation flow too. Restoring member-scoped read access.

create policy "members can view their organization commercial state"
on public.organization_commercial_state for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view their organization commercial settings"
on public.organization_commercial_settings for select to authenticated
using (private.is_organization_member(organization_id));

create policy "members can view their organization free access events"
on public.organization_free_access_events for select to authenticated
using (private.is_organization_member(organization_id));

grant select on public.organization_commercial_state to authenticated;
grant select on public.organization_commercial_settings to authenticated;
grant select on public.organization_free_access_events to authenticated;
