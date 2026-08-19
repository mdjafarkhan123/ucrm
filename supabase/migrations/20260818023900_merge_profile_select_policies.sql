-- `profiles` carried two permissive select policies for `authenticated`: one for your own row, one for a
-- teammate's. Permissive policies are OR'd, so both were evaluated on every profile read -- and a profile is
-- read whenever the UI resolves who wrote a note, uploaded a file, or acted in the timeline. This merges
-- them into one policy with the same two branches. Access is unchanged: your own row, or anyone who shares
-- an organization with you.

drop policy if exists "users can view their profile" on public.profiles;
drop policy if exists "org co-members can view teammate profiles" on public.profiles;

create policy "users can view their own and teammate profiles"
on public.profiles for select to authenticated
using (
  (select auth.uid()) = id
  or exists (
    select 1
    from public.organization_members as viewer
    join public.organization_members as target
      on target.organization_id = viewer.organization_id
    where viewer.user_id = (select auth.uid())
      and target.user_id = profiles.id
  )
);
