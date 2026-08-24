-- Team & access, part 3A, layer 2b: the two policies the seam could not reach.
--
-- Layer 2 threaded `status = 'active'` through the five shared helpers, which covers every policy that
-- calls one. Verifying it against real tables found two policies that do their own membership reasoning
-- instead, so status meant nothing to them:
--
--   * notes: the read policy had a standalone `created_by = auth.uid()` branch with no membership check at
--     all. A deactivated -- or permanently removed -- person kept reading every note they had ever
--     written, including notes on clients and requests they no longer have any business seeing.
--
--   * profiles: the teammate branch joined organization_members twice with no status filter, so a
--     deactivated member could still read their colleagues' profiles.
--
-- Both are fixed here rather than left for the layer that trips over them.

-- A note is still visible to its author, but only while they actually work here.
drop policy if exists "permitted members can view notes" on public.notes;
create policy "permitted members can view notes"
  on public.notes
  for select
  to authenticated
  using (
    (
      created_by = (select auth.uid())
      and private.is_organization_member(organization_id)
    )
    or exists (
      select 1
      from public.note_links as link
      where link.note_id = notes.id
        and private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
    )
  );

-- A person always sees their own profile row -- that is their account, not tenant data.
--
-- The teammate branch needs the viewer to be active, but deliberately allows a target in any state except
-- removed: the team directory has to show pending invitees and deactivated members by name. A permanently
-- removed member is excluded here on purpose, because their name is read from
-- organization_members.display_name_at_removal instead, which is exactly why that snapshot exists.
drop policy if exists "users can view their own and teammate profiles" on public.profiles;
create policy "users can view their own and teammate profiles"
  on public.profiles
  for select
  to authenticated
  using (
    (select auth.uid()) = id
    or exists (
      select 1
      from public.organization_members as viewer
      join public.organization_members as target
        on target.organization_id = viewer.organization_id
      where viewer.user_id = (select auth.uid())
        and viewer.status = 'active'
        and target.user_id = profiles.id
        and target.status <> 'removed'
    )
  );
