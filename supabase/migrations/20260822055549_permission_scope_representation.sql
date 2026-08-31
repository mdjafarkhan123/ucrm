-- Team & access, part 3A, layer 3: a shape for "Assigned work only", switched off.
--
-- Grant and deny booleans cannot express the three answers the product promises: No access, Assigned work
-- only, and All work. This adds the representation and its validation, and deliberately activates it for
-- nothing.
--
-- Why nothing: a scope is only honest when the domain behind it enforces it. Right now none does.
-- private.client_is_assigned_to_current_user is still a stub returning false, clients.owner_user_id is
-- never written by any code path, and no screen can assign a client to anybody. Turning customer scope on
-- today would ship a setting that silently shows an empty list. Customer scope is activated together with
-- the Clients owner-assignment workflow -- its API, its screen, and its tests -- as one piece of work.
--
-- Until then every permission stays scope_model = 'none' and the database refuses to store 'assigned' for
-- any of them. A later domain opts in by setting its own key's scope_model and teaching its own policy to
-- read permission_scope. Nothing about these two tables needs redesigning for that.

alter table public.permissions
  add column if not exists scope_model text not null default 'none';

alter table public.role_permissions
  add column if not exists access_scope text not null default 'all';

alter table public.organization_member_permission_overrides
  add column if not exists access_scope text not null default 'all';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'permissions_scope_model_check'
      and conrelid = 'public.permissions'::regclass
  ) then
    alter table public.permissions
      add constraint permissions_scope_model_check
      check (scope_model in ('none', 'assigned_or_all'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'role_permissions_access_scope_check'
      and conrelid = 'public.role_permissions'::regclass
  ) then
    alter table public.role_permissions
      add constraint role_permissions_access_scope_check
      check (access_scope in ('assigned', 'all'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_member_permission_overrides_access_scope_check'
      and conrelid = 'public.organization_member_permission_overrides'::regclass
  ) then
    alter table public.organization_member_permission_overrides
      add constraint organization_member_permission_overrides_access_scope_check
      check (access_scope in ('assigned', 'all'));
  end if;

  -- A denial has no scope. Storing one would suggest a narrowing that is really a refusal.
  if not exists (
    select 1 from pg_constraint
    where conname = 'organization_member_permission_overrides_deny_has_no_scope_check'
      and conrelid = 'public.organization_member_permission_overrides'::regclass
  ) then
    alter table public.organization_member_permission_overrides
      add constraint organization_member_permission_overrides_deny_has_no_scope_check
      check (override_state <> 'deny' or access_scope = 'all');
  end if;
end $$;

-- One validator, shared by both tables that can carry a scope. A permission whose domain does not enforce
-- scope cannot be given one, whatever writes the row.
create or replace function private.assert_scope_is_supported()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  supported_model text;
begin
  if new.access_scope = 'all' then
    return new;
  end if;

  select scope_model into supported_model
  from public.permissions
  where key = new.permission_key;

  if supported_model is distinct from 'assigned_or_all' then
    raise exception
      'Permission % does not support an assigned scope, because no domain enforces it yet.',
      new.permission_key
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke all on function private.assert_scope_is_supported() from public, anon, authenticated, service_role;

drop trigger if exists role_permissions_scope_is_supported on public.role_permissions;
create trigger role_permissions_scope_is_supported
  before insert or update of access_scope, permission_key on public.role_permissions
  for each row
  execute function private.assert_scope_is_supported();

drop trigger if exists member_permission_overrides_scope_is_supported
  on public.organization_member_permission_overrides;
create trigger member_permission_overrides_scope_is_supported
  before insert or update of access_scope, permission_key
  on public.organization_member_permission_overrides
  for each row
  execute function private.assert_scope_is_supported();

-- The resolvers a policy will call once a domain opts in. They return three answers rather than a boolean:
-- 'none' means refused, 'assigned' means only the caller's own work, 'all' means everything in the tenant.
-- A personal override wins over the role, exactly as the boolean helpers already behave.
create or replace function private.permission_scope(
  target_organization_id uuid,
  target_permission_key text
)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select coalesce(
    (
      select case
        when override.override_state = 'deny' then 'none'
        else override.access_scope
      end
      from public.organization_member_permission_overrides as override
      join public.organization_members as membership
        on membership.organization_id = override.organization_id
       and membership.user_id = override.user_id
      where override.organization_id = target_organization_id
        and override.user_id = (select auth.uid())
        and override.permission_key = target_permission_key
        and membership.status = 'active'
    ),
    (
      select role_permission.access_scope
      from public.organization_members as membership
      join public.role_permissions as role_permission
        on role_permission.role = membership.role
      where membership.organization_id = target_organization_id
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'
        and role_permission.permission_key = target_permission_key
    ),
    'none'
  );
$function$;

create or replace function private.member_permission_scope(
  target_organization_id uuid,
  target_user_id uuid,
  target_permission_key text
)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select coalesce(
    (
      select case
        when override.override_state = 'deny' then 'none'
        else override.access_scope
      end
      from public.organization_member_permission_overrides as override
      join public.organization_members as membership
        on membership.organization_id = override.organization_id
       and membership.user_id = override.user_id
      where override.organization_id = target_organization_id
        and override.user_id = target_user_id
        and override.permission_key = target_permission_key
        and membership.status = 'active'
    ),
    (
      select role_permission.access_scope
      from public.organization_members as membership
      join public.role_permissions as role_permission
        on role_permission.role = membership.role
      where membership.organization_id = target_organization_id
        and membership.user_id = target_user_id
        and membership.status = 'active'
        and role_permission.permission_key = target_permission_key
    ),
    'none'
  );
$function$;

-- permission_scope answers about the caller, so a policy may evaluate it. member_permission_scope answers
-- about somebody else, so only SECURITY DEFINER callers get it.
revoke all on function private.permission_scope(uuid, text) from public, anon, authenticated, service_role;
grant execute on function private.permission_scope(uuid, text) to authenticated;
revoke all on function private.member_permission_scope(uuid, uuid, text)
  from public, anon, authenticated, service_role;

comment on column public.permissions.scope_model is
  'none = this permission is all-or-nothing. assigned_or_all = its domain enforces Assigned work only.';
comment on column public.role_permissions.access_scope is
  'Scope this role grants. Stays all until the owning domain sets scope_model.';
comment on column public.organization_member_permission_overrides.access_scope is
  'Per-person scope. A deny override always stores all, because a refusal has no scope.';
