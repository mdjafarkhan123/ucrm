-- Team & access, part 3A, layer 2: status becomes real everywhere, through one seam.
--
-- Every row level security policy in this app funnels through five small functions. None of them looked at
-- status, because until now a membership row existing meant the person worked here. Adding
-- `status = 'active'` to these five is the entire change: clients, properties, requests, assessments,
-- quotes, opportunities, tasks, notes, tags, attachments and settings all inherit it at once, with no
-- policy rewritten and nothing for a future table to remember.
--
-- Nothing else about these functions changes. They keep their existing shape, their SECURITY DEFINER
-- boundary, their pinned search_path, and the `(select auth.uid())` wrapping that keeps the lookup to one
-- call per query rather than one per row.
--
-- Consequence worth stating plainly: a pending invitee and a deactivated or removed member now fail every
-- authorization check in the product. Any command that must legitimately act on a non-active membership --
-- invitation acceptance, restoration, ownership transfer, Platform Owner recovery -- has to authorize
-- itself explicitly instead of drifting through these helpers.

create or replace function private.is_organization_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select exists (
    select 1
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and organization.lifecycle_status = 'active'
  );
$function$;

create or replace function private.is_organization_admin(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select exists (
    select 1
    from public.organization_members as membership
    join public.organizations as organization
      on organization.id = membership.organization_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.role in ('owner', 'admin')
      and membership.status = 'active'
      and organization.lifecycle_status = 'active'
  );
$function$;

create or replace function private.has_permission(
  target_organization_id uuid,
  target_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and coalesce(
        (
          select override.override_state = 'grant'
          from public.organization_member_permission_overrides as override
          where override.organization_id = membership.organization_id
            and override.user_id = membership.user_id
            and override.permission_key = target_permission_key
        ),
        exists (
          select 1
          from public.role_permissions as role_permission
          where role_permission.role = membership.role
            and role_permission.permission_key = target_permission_key
        )
      )
  );
$function$;

create or replace function private.member_has_permission(
  target_organization_id uuid,
  target_user_id uuid,
  target_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select exists (
    select 1
    from public.organization_members as membership
    where membership.organization_id = target_organization_id
      and membership.user_id = target_user_id
      and membership.status = 'active'
      and coalesce(
        (
          select override.override_state = 'grant'
          from public.organization_member_permission_overrides as override
          where override.organization_id = membership.organization_id
            and override.user_id = membership.user_id
            and override.permission_key = target_permission_key
        ),
        exists (
          select 1
          from public.role_permissions as role_permission
          where role_permission.role = membership.role
            and role_permission.permission_key = target_permission_key
        )
      )
  );
$function$;

create or replace function private.permitted_organizations(target_permission_key text)
returns setof uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select membership.organization_id
  from public.organization_members as membership
  join public.organizations as organization
    on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid())
    and membership.status = 'active'
    and organization.lifecycle_status = 'active'
    and coalesce(
      (
        select override.override_state = 'grant'
        from public.organization_member_permission_overrides as override
        where override.organization_id = membership.organization_id
          and override.user_id = membership.user_id
          and override.permission_key = target_permission_key
      ),
      exists (
        select 1
        from public.role_permissions as role_permission
        where role_permission.role = membership.role
          and role_permission.permission_key = target_permission_key
      )
    );
$function$;

-- These are internal authorization helpers. Policies call them as the table owner; nobody else needs to.
revoke all on function private.is_organization_member(uuid) from public, anon, authenticated, service_role;
revoke all on function private.is_organization_admin(uuid) from public, anon, authenticated, service_role;
revoke all on function private.has_permission(uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.member_has_permission(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function private.permitted_organizations(text)
  from public, anon, authenticated, service_role;
