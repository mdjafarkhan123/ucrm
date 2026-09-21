-- Team & access, part 3A, item 8: the last two direct write paths close.
--
-- Item 7 took every write privilege off anon and authenticated on six of the eight team and settings
-- tables, and deliberately left organization_members and organization_member_permission_overrides alone.
-- The reason was written into 20260831090000: PATCH /api/team/members/[userId] still updated a role
-- directly and the per-permission route still upserted and deleted overrides, both as the signed-in user,
-- so revoking then would have broken those two screens for as long as the two commits were apart.
--
-- Those routes now call change_team_member_role and save_team_member_permissions as the service role, and
-- nothing in the app writes either table as `authenticated` any more. Every remaining write goes through a
-- SECURITY DEFINER command that checks who is asking before it changes anything, so the grant has nothing
-- left to allow. RLS still refuses these writes as well; this removes the layer the policy was standing in
-- front of, which is the point -- one mistaken policy should not be all that separates a browser session
-- from somebody else's role.
--
-- SELECT stays. The team screen reads both tables as the signed-in user and RLS scopes it to their own
-- organization.

revoke insert, update, delete, truncate, references, trigger
  on public.organization_members,
     public.organization_member_permission_overrides
  from authenticated;

-- The spare index, agreed with Jafar on 2026-09-01.
--
-- organization_member_permission_overrides_user_idx is (organization_id, user_id). The primary key is
-- (organization_id, user_id, permission_key) -- the same two columns, in the same order, with a third
-- appended -- so every lookup this index could serve is already served by the key, and the planner never
-- had a reason to choose it. What it did do was cost a second index write on every row
-- save_team_member_permissions inserts, updates or deletes, which is the whole adjustment set each time
-- somebody saves that section.
drop index if exists public.organization_member_permission_overrides_user_idx;
