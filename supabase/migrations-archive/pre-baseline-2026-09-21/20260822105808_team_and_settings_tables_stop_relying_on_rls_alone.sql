-- Team & access, part 3A, item 7: grant cleanup.
--
-- Supabase's default privileges hand INSERT, UPDATE, DELETE and TRUNCATE (and on the older tables
-- REFERENCES and TRIGGER) to anon and authenticated on every new table in public. RLS refuses all of it
-- today, so nothing here is reachable from a browser session -- but the grant should not be the thing a
-- policy has to stand in front of. Every write to these tables already goes through a SECURITY DEFINER
-- command, so the grant buys nothing and costs a whole layer of defence.
--
-- Where the writes actually happen, checked path by path before writing this file:
--   organization_settings, organization_settings_audit, organization_business_hours
--       save_organization_business_profile, save_organization_branding, set_organization_logo,
--       remove_organization_logo, save_organization_business_hours -- part 1 writes nothing directly.
--   organization_member_invitations
--       the eleven service_role primitives from item 3.
--   permissions, role_permissions
--       reference data seeded by migrations. Nothing writes them at runtime.
--   organization_members, organization_member_permission_overrides
--       item 6's seven member commands -- EXCEPT the two API routes item 8 has not replaced yet.
--
-- That exception is why authenticated keeps its grants on those last two tables for now.
-- PATCH /api/team/members/[userId] still updates organization_members.role directly, and
-- PUT /api/team/members/[userId]/permissions/[permissionKey] still upserts and deletes on the overrides
-- table, both as the signed-in user. Item 8 moves them onto change_team_member_role and
-- save_team_member_permissions; the matching revoke belongs to that migration, so the app never spends a
-- commit with those two screens broken. anon has no such excuse on any of the eight and loses everything
-- here.

-- anon: no write path exists on any of these tables, and none is planned.
revoke insert, update, delete, truncate, references, trigger
  on public.organization_members,
     public.organization_member_invitations,
     public.organization_member_permission_overrides,
     public.organization_settings,
     public.organization_settings_audit,
     public.organization_business_hours,
     public.permissions,
     public.role_permissions
  from anon;

-- authenticated: everything whose writes already run through a definer command.
revoke insert, update, delete, truncate, references, trigger
  on public.organization_member_invitations,
     public.organization_settings,
     public.organization_settings_audit,
     public.organization_business_hours,
     public.permissions,
     public.role_permissions
  from authenticated;
