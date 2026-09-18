-- Fix: creating a Request failed with "new row violates row-level security policy for table requests".
--
-- Root cause (confirmed by reproducing in SQL as an active admin of an active organization): the app does
-- INSERT ... RETURNING. Postgres checks the RETURNING row against the SELECT policy, which calls
-- private.can_view_request. That function ended with "and exists (select 1 from public.requests where id =
-- target_request_id ...)". The function is STABLE, so it runs on the statement's snapshot, and a row inserted
-- by the statement that is still running is not visible to it. The existence check was therefore false for
-- every freshly inserted request, the SELECT policy failed, and Postgres reported it as an RLS violation.
-- The same INSERT without RETURNING succeeded, which is what pinned this down.
--
-- The existence check was never load-bearing. Every table that points at a request does so through a
-- composite (organization_id, request_id) foreign key, so a request id from another organization cannot be
-- stored at all. private.can_view_job, the precedent this function was modelled on, has no such check.
-- The membership, active-organization, requests.view permission, and assigned-scope tests are unchanged.
--
-- Trade-off accepted: private.can_view_linked_entity('request', <id>) now answers true for an 'all'-scope
-- member even when <id> does not exist in their organization, so a polymorphic note/tag/attachment row can be
-- created against a request id that does not exist. That is a harmless dangling row in the caller's own
-- organization, and private.can_view_client already behaves the same way for clients.
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
    );
$$;

comment on function private.can_view_request(uuid, uuid) is
  'Whether the caller may see this request, and the seam Request pricing and linked records inherit. '
  'Single statement for the same per-row-cost reason private.can_view_job documents; change '
  'has_permission/permission_scope for requests.view and you must change this too. "Assigned" means the '
  'request''s own assessment, if it has one, lists this member as an assignee. Deliberately does not check '
  'that the request row exists: as the SELECT policy on public.requests it would not see a row being '
  'inserted by the current statement, which broke INSERT ... RETURNING.';
