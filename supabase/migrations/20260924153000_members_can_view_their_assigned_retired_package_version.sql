-- A business keeps the package version it was sold even after the owner publishes a newer one and the old
-- version is retired (docs/jafar-onboarding-implementation-contract.md: "A retired version remains visible
-- ... on affected organizations"). The existing read rules only let anyone see *published* versions, so the
-- moment a version was retired every member of a business still on it lost sight of their own plan, and the
-- access check failed on every page ("The organization package version is missing").
--
-- These rules add, alongside the public published-only ones, that a member may read any version their own
-- organization has been assigned — its row, its features and its limits. Nothing about other businesses' plans
-- or unassigned drafts becomes visible.

create policy "members can view their organization assigned package versions"
  on public.platform_package_versions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.organization_package_assignments as assignment
      where assignment.package_version_id = platform_package_versions.id
        and private.is_organization_member(assignment.organization_id)
    )
  );

create policy "members can view their organization assigned package version features"
  on public.platform_package_version_features
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.organization_package_assignments as assignment
      where assignment.package_version_id = platform_package_version_features.package_version_id
        and private.is_organization_member(assignment.organization_id)
    )
  );

create policy "members can view their organization assigned package version limits"
  on public.platform_package_version_limits
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.organization_package_assignments as assignment
      where assignment.package_version_id = platform_package_version_limits.package_version_id
        and private.is_organization_member(assignment.organization_id)
    )
  );
