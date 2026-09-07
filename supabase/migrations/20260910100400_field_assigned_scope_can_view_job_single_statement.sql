-- Jobs, Part 15a-2: can_view_job answers in one statement.
--
-- The verification step of the performance gate, and what it found. Measured on a 5,000-job tenant with a
-- field worker on 500 of them, the Schedule's one-week window went from 27ms to 938ms and from 2,264 to
-- 17,105 buffers. The narrowing itself was not the cost. can_view_job called member_job_is_visible, which
-- called member_has_permission and member_permission_scope; all three are SECURITY DEFINER and so none of
-- them inline. RLS evaluates its predicate once per SCANNED row -- 876 of them in that window, of which
-- 786 were then discarded -- so every row paid for four nested function invocations and their lookups.
--
-- Asking the same question as one statement over the same tables took that window to 132ms, and took the
-- jobs list to 24ms, which is faster than the 35ms it cost before this part, because a field worker's list
-- now stops after their own jobs.
--
-- The duplication below is deliberate and load-bearing. private.has_permission and private.permission_scope
-- remain the single definition of the rule for every caller that is NOT evaluated per row -- the ten
-- SECURITY DEFINER read models still reach it through member_job_is_visible, once per request, where
-- clarity is worth more than nanoseconds. Change the permission or scope rule and you must change it here
-- too; the comment on the function says so at the other end.
--
-- Still outstanding, and deliberately not fixed here: 132ms is still ~5x the 27ms this window cost before,
-- and the reason is structural rather than per-row. The Schedule asks for the whole organization's week
-- and RLS discards what the field worker may not see, so the work scales with the tenant's visits rather
-- than with the worker's own. The fix is for the Schedule to ask for the worker's own visits when their
-- scope is 'assigned', which is an application-layer change and a product decision, not a policy one.
create or replace function private.can_view_job(
  target_organization_id uuid,
  target_job_id uuid
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
        -- private.has_permission, inlined.
        and coalesce(
          (
            select override.override_state = 'grant'
            from public.organization_member_permission_overrides as override
            where override.organization_id = membership.organization_id
              and override.user_id = membership.user_id
              and override.permission_key = 'jobs.view'
          ),
          exists (
            select 1
            from public.role_permissions as role_permission
            where role_permission.role = membership.role
              and role_permission.permission_key = 'jobs.view'
          )
        )
        -- private.permission_scope, inlined, and then the assigned test itself.
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
            'none'
          ) <> 'assigned'
          or exists (
            select 1
            from public.job_visit_assignments as assignment
            where assignment.organization_id = target_organization_id
              and assignment.user_id = membership.user_id
              and assignment.job_id = target_job_id
          )
        )
    )
    and exists (
      select 1
      from public.jobs
      where id = target_job_id
        and organization_id = target_organization_id
    );
$$;

comment on function private.can_view_job(uuid, uuid) is
  'Whether the caller may see this job, and the seam every field record inherits. Deliberately a single '
  'statement rather than a call to member_job_is_visible: RLS evaluates this once per scanned row, and '
  'nested SECURITY DEFINER calls do not inline. It duplicates private.has_permission and '
  'private.permission_scope for jobs.view on purpose; change those and you must change this.';
