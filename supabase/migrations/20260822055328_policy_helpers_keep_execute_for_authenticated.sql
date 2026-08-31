-- A row level security policy expression is evaluated with the privileges of the user running the query,
-- not the table owner. So a SECURITY DEFINER helper named inside a policy must remain executable by
-- `authenticated`, or every read that policy guards fails with "permission denied for function" instead of
-- returning no rows. Least privilege here means: revoke from PUBLIC and anon, keep exactly the roles that
-- have to evaluate the policy.
--
-- These four are safe to expose. Each one reports a fact about the caller's own membership, derived from
-- (select auth.uid()), and takes no argument that could make it answer for somebody else.

grant execute on function private.is_organization_member(uuid) to authenticated;
grant execute on function private.is_organization_admin(uuid) to authenticated;
grant execute on function private.has_permission(uuid, text) to authenticated;
grant execute on function private.permitted_organizations(text) to authenticated;

-- member_has_permission(organization, user, key) answers for an arbitrary user, so it stays internal. It
-- appears in no policy: its only callers are SECURITY DEFINER functions owned by postgres, which do not
-- need a grant to call it.
revoke all on function private.member_has_permission(uuid, uuid, text)
  from public, anon, authenticated, service_role;
