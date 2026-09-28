-- private.current_full_view_entity_types() (20260929150000) runs once per statement, but it answered through
-- seven separate has_permission / current_permission_scope calls, and Postgres plans each nested SQL-function
-- call afresh in every statement: about 6 ms of fixed cost on each side-table read, measured warm on Raad LTD
-- (one quote's 24 timeline rows: 8.5 ms, of which 6.1 ms was this function).
--
-- Same answer, read in one statement: the caller's membership, then each wanted permission's override and
-- role default, combined exactly as has_permission (an override decides; otherwise the role's grant) and
-- current_permission_scope (a deny override is 'none'; otherwise override scope, then role scope, then
-- 'none') combine them. Both tables are keyed so each wanted permission yields one row.

create or replace function private.current_full_view_entity_types()
returns text[]
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with caller as (
    select membership.organization_id, membership.user_id, membership.role
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and organization.lifecycle_status = 'active'
  ),
  access as (
    select
      wanted.permission_key,
      coalesce(override.override_state = 'grant', role_permission.permission_key is not null) as granted,
      coalesce(
        case when override.override_state = 'deny' then 'none' else override.access_scope end,
        role_permission.access_scope,
        'none'
      ) as scope
    from caller
    cross join (
      values ('customers.view'), ('requests.view'), ('quotes.view'), ('jobs.view'), ('expenses.manage_team')
    ) as wanted (permission_key)
    left join public.organization_member_permission_overrides as override
      on override.organization_id = caller.organization_id
     and override.user_id = caller.user_id
     and override.permission_key = wanted.permission_key
    left join public.role_permissions as role_permission
      on role_permission.role = caller.role
     and role_permission.permission_key = wanted.permission_key
  ),
  caller_access as (
    select
      bool_or(granted) filter (where permission_key = 'customers.view') as customers,
      bool_or(granted and scope <> 'assigned') filter (where permission_key = 'requests.view') as requests,
      bool_or(granted) filter (where permission_key = 'quotes.view') as quotes,
      bool_or(scope = 'all') filter (where permission_key = 'jobs.view') as all_jobs,
      bool_or(granted) filter (where permission_key = 'expenses.manage_team') as team_expenses
    from access
    having count(*) > 0
  )
  select array_remove(array[
    case when customers then 'client' end,
    case when customers then 'property' end,
    case when requests then 'request' end,
    case when quotes then 'quote' end,
    case when all_jobs then 'job' end,
    case when all_jobs then 'visit' end,
    case when all_jobs and team_expenses then 'job_expense' end
  ], null)
  from caller_access;
$$;
