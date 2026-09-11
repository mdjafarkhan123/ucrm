-- Paid-launch trust, Part 3: wire requests.view to real visibility.
--
-- Part 2 only seeded the requests.view scope switch: Owner/Administrator/Office/Sales/Finance at 'all',
-- Field at 'assigned'. Nothing read it yet -- public.requests, public.request_pricing_lines and
-- private.can_view_request still accepted any organization member. This closes that: a Field member now
-- sees a Request only when its assessment (zero or one per request, per assessment_schema) lists them as
-- an assignee. Everyone else is unaffected. Same rule jobs.view already enforces for Jobs, applied here to
-- Requests.
--
-- Jafar was told plainly, and approved, that existing Field users lose visibility into Requests they are
-- not assigned to assess.
--
-- Shaped like private.can_view_job (field_assigned_scope_can_view_job_single_statement): one statement,
-- not a call to member_permission_scope, because RLS evaluates this once per scanned row and nested
-- SECURITY DEFINER calls do not inline -- that nesting cost the Jobs list 27ms -> 938ms at 5,000 rows.
-- private.has_permission and private.permission_scope for requests.view are duplicated here on purpose;
-- change those and this must change too.
--
-- Deliberately keeping organization.lifecycle_status in the check, where private.can_view_job's inlined
-- version does not: the policy this replaces was private.is_organization_member, which already required an
-- active organization, so narrowing must not also silently drop that guarantee. (can_view_job's missing
-- lifecycle_status check is a pre-existing gap in the Jobs precedent, out of scope here.)
--
-- Out of scope, left for Part 4: Request notes/tags/attachments/activity events (they inherit
-- can_view_request already, so they narrow for free the moment it changes -- consistent, not yet verified
-- here) and the write hole in public.replace_request_pricing_lines, which authorizes on plain organization
-- membership and does not yet check can_view_request. A Field member who can no longer see a Request could
-- still call that function to edit its pricing until Part 4 closes it -- the same write-hole lesson Jobs
-- Part 15a-2 paid for on visit completion.

create or replace function private.can_view_request(
  target_organization_id uuid,
  target_request_id uuid
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
      join public.organizations as organization
        on organization.id = membership.organization_id
      where membership.organization_id = target_organization_id
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'
        and organization.lifecycle_status = 'active'
        -- private.has_permission, inlined, for requests.view.
        and coalesce(
          (
            select override.override_state = 'grant'
            from public.organization_member_permission_overrides as override
            where override.organization_id = membership.organization_id
              and override.user_id = membership.user_id
              and override.permission_key = 'requests.view'
          ),
          exists (
            select 1
            from public.role_permissions as role_permission
            where role_permission.role = membership.role
              and role_permission.permission_key = 'requests.view'
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
                and override.permission_key = 'requests.view'
            ),
            (
              select role_permission.access_scope
              from public.role_permissions as role_permission
              where role_permission.role = membership.role
                and role_permission.permission_key = 'requests.view'
            ),
            'none'
          ) <> 'assigned'
          or exists (
            select 1
            from public.assessments as assessment
            join public.assessment_assignees as assignee
              on assignee.assessment_id = assessment.id
            where assessment.organization_id = target_organization_id
              and assessment.request_id = target_request_id
              and assignee.user_id = membership.user_id
          )
        )
    )
    and exists (
      select 1
      from public.requests
      where id = target_request_id
        and organization_id = target_organization_id
    );
$$;

comment on function private.can_view_request(uuid, uuid) is
  'Whether the caller may see this request, and the seam Request pricing and (from Part 4) linked records '
  'inherit. Single statement for the same per-row-cost reason private.can_view_job documents; change '
  'has_permission/permission_scope for requests.view and you must change this too. "Assigned" means the '
  'request''s own assessment, if it has one, lists this member as an assignee.';

drop policy "members can view requests" on public.requests;
create policy "members can view requests"
on public.requests for select to authenticated
using (private.can_view_request(organization_id, id));

drop policy "members can update requests" on public.requests;
create policy "members can update requests"
on public.requests for update to authenticated
using (private.can_view_request(organization_id, id))
with check (private.can_view_request(organization_id, id));

drop policy "members can view request pricing" on public.request_pricing_lines;
create policy "members can view request pricing"
on public.request_pricing_lines for select to authenticated
using (private.can_view_request(organization_id, request_id));
