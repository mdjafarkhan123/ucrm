-- Files and Media, Part 7B-4: the clients, properties, requests and invoices read policies are worked out once
-- per query instead of once per row.
--
-- Each of these policies called a function per row (can_view_client, can_view_request, is_organization_member
-- plus has_permission) that re-ran the caller's membership and permission lookups for every row it looked at.
-- The File Manager's search reads all four tables, and every list page does too.
--
-- The rewrite rests on one fact the schema enforces: organization_members_user_id_key makes a user a member of
-- at most one organization. So for any row, is_organization_member(organization_id) is true exactly when
-- organization_id = current_organization() (both require an active membership in an active organization), and
-- has_permission / permission scope for that organization equal their current-organization forms. Each policy
-- below is therefore the same predicate as before, with the per-row function calls replaced by values computed
-- once per statement:
--
--   clients     is_member and (customers.view or the client is on one of the caller's visit assignments)
--   properties  the same test for the property's client
--   requests    is_member and requests.view and (its scope is not 'assigned' or the caller is an assignee of
--               an assessment on the request)
--   invoices    is_member and invoices.view
--
-- The "assigned to me" sets come from two security definer functions, so they read assignments exactly as the
-- old functions did, without the caller's policies on those tables.
--
-- Rolling back: restore the four policies to their previous expressions (below) and drop the two functions.
--   clients     private.can_view_client(organization_id, id)
--   properties  private.can_view_client(organization_id, client_id)
--   requests    private.can_view_request(organization_id, id)
--   invoices    private.is_organization_member(organization_id) and private.has_permission(organization_id, 'invoices.view')

-- The clients the caller has a visit assignment on, in their organization: client_is_assigned_to_current_user
-- as a set.
create function private.current_user_assigned_client_ids()
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select job.client_id
  from public.job_visit_assignments as assignment
  join public.jobs as job
    on job.organization_id = assignment.organization_id
   and job.id = assignment.job_id
  where assignment.organization_id = (select private.current_organization())
    and assignment.user_id = (select auth.uid());
$$;

-- The requests the caller is an assessment assignee on, in their organization: can_view_request's assigned
-- test as a set.
create function private.current_user_assigned_request_ids()
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select assessment.request_id
  from public.assessments as assessment
  join public.assessment_assignees as assignee
    on assignee.assessment_id = assessment.id
  where assessment.organization_id = (select private.current_organization())
    and assignee.user_id = (select auth.uid());
$$;

revoke all on function private.current_user_assigned_client_ids() from public, anon;
revoke all on function private.current_user_assigned_request_ids() from public, anon;
grant execute on function private.current_user_assigned_client_ids() to authenticated;
grant execute on function private.current_user_assigned_request_ids() to authenticated;

alter policy "permitted members can view clients" on public.clients using (
  organization_id = (select private.current_organization())
  and (
    (select private.has_permission((select private.current_organization()), 'customers.view'))
    or id in (select private.current_user_assigned_client_ids())
  )
);

alter policy "permitted members can view properties" on public.properties using (
  organization_id = (select private.current_organization())
  and (
    (select private.has_permission((select private.current_organization()), 'customers.view'))
    or client_id in (select private.current_user_assigned_client_ids())
  )
);

alter policy "members can view requests" on public.requests using (
  organization_id = (select private.current_organization())
  and (select private.has_permission((select private.current_organization()), 'requests.view'))
  and (
    (select private.current_permission_scope('requests.view')) <> 'assigned'
    or id in (select private.current_user_assigned_request_ids())
  )
);

alter policy "permitted members can view invoices" on public.invoices using (
  organization_id = (select private.current_organization())
  and (select private.has_permission((select private.current_organization()), 'invoices.view'))
);
