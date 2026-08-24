-- Team & access, part 3A, layer 4: one authority for the employee seat limit.
--
-- src/lib/server/access/effective.ts resolved this limit in TypeScript, duplicating the versioned-vs-legacy
-- package logic that already exists for every other entitlement. This gives the same resolution a single SQL
-- home so `effective.ts` can call it instead of re-deriving it, leaving TypeScript with presentation mapping
-- only.
--
-- Mirrors effective.ts exactly: the newest organization_package_assignments row wins when one exists, and its
-- platform_package_version_limits row supplies the limit; otherwise the organization's legacy package_key
-- applies, swapped for scheduled_package_key when scheduled_package_effective_at is due, and package_limits
-- supplies the limit. An in-window organization_limit_overrides row wins over either path.
--
-- One intentional divergence: package_limits carries no limit_state column, so effective.ts derives 'numeric'
-- vs 'not_included' from is_unlimited/limit_value. Its ternary uses `=== null` against an optional-chained
-- read, which is 'numeric' (not 'not_included') on a *missing* row -- a JS-only artifact of that comparison
-- with `undefined`. Every package ships a seeded employee_seats row, so a missing row cannot occur through any
-- real code path; this function reports 'not_included' for that unreachable case instead of replicating the
-- artifact.
--
-- Seats used and the advisory-lock reservation check land with organization_member_invitations: counting a
-- 'reserving' invitation as a held seat is part of the same formula, and a function cannot honestly claim to
-- prevent overbooking while the table it must read does not exist yet.

create or replace function private.effective_employee_seat_limit(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  state text,
  value integer,
  is_unlimited boolean,
  source text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  assignment_package_version_id uuid;
  override_limit_state text;
  override_limit_value integer;
  override_is_unlimited boolean;
  override_found boolean;
  package_limit_state text;
  package_limit_value integer;
  package_is_unlimited boolean;
  package_found boolean;
  organization_package_key text;
  organization_scheduled_package_key text;
  organization_scheduled_effective_at timestamptz;
  effective_package_key text;
begin
  select assignment.package_version_id
  into assignment_package_version_id
  from public.organization_package_assignments as assignment
  where assignment.organization_id = target_organization_id
  order by assignment.effective_at desc, assignment.id desc
  limit 1;

  select override.limit_state, override.limit_value, override.is_unlimited
  into override_limit_state, override_limit_value, override_is_unlimited
  from public.organization_limit_overrides as override
  where override.organization_id = target_organization_id
    and override.limit_key = 'employee_seats'
    and override.starts_at <= at
    and (override.expires_at is null or override.expires_at > at);
  override_found := found;

  if assignment_package_version_id is not null then
    select version_limit.limit_state, version_limit.limit_value
    into package_limit_state, package_limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = assignment_package_version_id
      and version_limit.limit_key = 'employee_seats';
    package_found := found;

    if override_found then
      state := override_limit_state;
      value := override_limit_value;
      is_unlimited := override_is_unlimited;
    elsif package_found then
      state := package_limit_state;
      value := case when package_limit_state = 'numeric' then package_limit_value else null end;
      is_unlimited := package_limit_state = 'unlimited';
    else
      state := 'not_included';
      value := null;
      is_unlimited := false;
    end if;
  else
    select organization.package_key, organization.scheduled_package_key,
           organization.scheduled_package_effective_at
    into organization_package_key, organization_scheduled_package_key, organization_scheduled_effective_at
    from public.organizations as organization
    where organization.id = target_organization_id;

    effective_package_key := case
      when organization_scheduled_package_key is not null
        and organization_scheduled_effective_at is not null
        and organization_scheduled_effective_at <= at
      then organization_scheduled_package_key
      else organization_package_key
    end;

    select package_limit.limit_value, package_limit.is_unlimited
    into package_limit_value, package_is_unlimited
    from public.package_limits as package_limit
    where package_limit.package_key = effective_package_key
      and package_limit.limit_key = 'employee_seats';
    package_found := found;

    if override_found then
      state := override_limit_state;
      value := override_limit_value;
      is_unlimited := override_is_unlimited;
    elsif package_found then
      is_unlimited := coalesce(package_is_unlimited, false);
      value := package_limit_value;
      state := case
        when package_is_unlimited then 'unlimited'
        when package_limit_value is null then 'not_included'
        else 'numeric'
      end;
    else
      state := 'not_included';
      value := null;
      is_unlimited := false;
    end if;
  end if;

  source := case when override_found then 'override' else 'package' end;

  return next;
  return;
end;
$function$;

comment on function private.effective_employee_seat_limit(uuid, timestamptz) is
  'Single authority for the employee_seats limit. effective.ts calls this instead of re-deriving it.';

-- Called directly from effective.ts via .rpc() as the signed-in member, exactly like permission_scope.
revoke all on function private.effective_employee_seat_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function private.effective_employee_seat_limit(uuid, timestamptz) to authenticated;
