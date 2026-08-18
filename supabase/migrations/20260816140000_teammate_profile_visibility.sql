-- Notes, tags, attachments, and activity events all record who did what (created_by, edited_by,
-- uploaded_by, actor_user_id). Until now `profiles` only let a user read their own row, so the UI
-- could never show a teammate's name -- only "you" was resolvable. This adds one additional select
-- policy (policies are OR'd) letting a member see the name/avatar of anyone who shares an
-- organization with them. `profiles` holds only `full_name` and `avatar_url`, nothing sensitive.

create policy "org co-members can view teammate profiles"
on public.profiles for select to authenticated
using (
  exists (
    select 1
    from public.organization_members as viewer
    join public.organization_members as target
      on target.organization_id = viewer.organization_id
    where viewer.user_id = (select auth.uid())
      and target.user_id = profiles.id
  )
);
