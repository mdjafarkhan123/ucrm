-- Jobs, Part 15a-3: an assigned-scope member sees only the assessments they are on.
--
-- 15a-2 narrowed jobs, visits and every field record that hangs off a job, but assessments were not part of
-- that sweep and still carried the original `private.is_organization_member` select policy. The Schedule draws
-- assessments beside visits, so a Field member's calendar showed every on-site assessment in the business --
-- including ones booked for other people, on requests the Field role holds no permission to open at all.
--
-- Jobber's boundary is the whole schedule, not just the job half of it: field crew "can see their own
-- schedule" and "cannot see another person's schedule" (Help Center, User Permissions). So an assessment
-- follows the same rule a visit does, keyed off the same jobs.view scope 15a-2 turned on -- that scope is
-- this product's one representation of "assigned work only", and splitting the Schedule across two different
-- scope sources would let the two halves disagree.
--
-- Shaped exactly like private.can_view_job and for the same reason: RLS evaluates this once per scanned row,
-- and nested SECURITY DEFINER calls do not inline, so the permission and scope rules are inlined here rather
-- than reached through private.has_permission / private.permission_scope. The assigned test itself lands on
-- assessment_assignees_pkey (assessment_id, user_id), so it costs one index probe and needs no new index.

create or replace function private.can_view_assessment(
  target_organization_id uuid,
  target_assessment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
      select 1
      from public.organization_members as membership
      where membership.organization_id = target_organization_id
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'
        -- private.permission_scope for jobs.view, inlined, and then the assigned test itself. Unlike a job,
        -- an assessment is not gated on holding jobs.view: it was visible to every member before this part
        -- and stays that way. Only a member whose scope is narrowed to 'assigned' is narrowed here.
        and (
          coalesce(
            (
              select case
                when override.override_state = 'deny' then 'none'
                else override.access_scope
              end
              from public.organization_member_permission_overrides as override
              where override.organization_id = membership.organization_id
                and override.user_id = membership.user_id
                and override.permission_key = 'jobs.view'
            ),
            (
              select role_permission.access_scope
              from public.role_permissions as role_permission
              where role_permission.role = membership.role
                and role_permission.permission_key = 'jobs.view'
            ),
            'all'
          ) <> 'assigned'
          or exists (
            select 1
            from public.assessment_assignees as assignee
            where assignee.assessment_id = target_assessment_id
              and assignee.user_id = membership.user_id
          )
        )
    );
$$;

comment on function private.can_view_assessment(uuid, uuid) is
  'Whether the caller may see this assessment on their schedule. Duplicates private.permission_scope for '
  'jobs.view on purpose -- RLS evaluates it once per scanned row and nested SECURITY DEFINER calls do not '
  'inline -- so changing that rule means changing this and private.can_view_job together. Note the '
  'coalesce default is ''all'', not ''none'': an assessment is visible to every member unless their scope '
  'narrows it, which is what it was before Part 15a-3.';

revoke all on function private.can_view_assessment(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.can_view_assessment(uuid, uuid) to authenticated;

drop policy "members can view assessments" on public.assessments;
create policy "members can view assessments"
on public.assessments for select to authenticated
using (private.can_view_assessment(organization_id, id));

-- Who else is on an assessment is part of the assessment, so the assignee rows inherit its visibility rather
-- than carrying a grant of their own -- the same derived-visibility rule every field record follows.
drop policy "members can view assessment assignees" on public.assessment_assignees;
create policy "members can view assessment assignees"
on public.assessment_assignees for select to authenticated
using (private.can_view_assessment(organization_id, assessment_id));

-- Narrowing a read opens a write hole -- the lesson 15a-2 paid for on visit completion. The assessment write
-- routes gate on membership alone and lean on RLS, so without this an assigned-scope member could edit or
-- delete an assessment they can no longer see. Insert is untouched: it was never reachable through what this
-- part narrowed, and who may book an assessment is a Requests question, not a Schedule one.
drop policy "members can update assessments" on public.assessments;
create policy "members can update assessments"
on public.assessments for update to authenticated
using (private.can_view_assessment(organization_id, id))
with check (private.can_view_assessment(organization_id, id));

drop policy "members can delete assessments" on public.assessments;
create policy "members can delete assessments"
on public.assessments for delete to authenticated
using (private.can_view_assessment(organization_id, id));
