-- Team & access, part 3A, layer 4 correction: PostgREST only exposes the public schema.
--
-- effective_employee_seat_limit was written into `private`, following every other resolver in this area.
-- But `private` functions are internal helpers -- reachable only from policies and from other functions on
-- the same call stack -- never from supabase-js .rpc(), which only ever reaches `public`. effective.ts needs
-- to call this one directly, so it has to live where public.create_client and public.check_rate_limit do.
--
-- security invoker, not definer: every table this reads is already selectable by an authenticated member of
-- the target organization through existing RLS (effective.ts's plain .from() calls prove it today), and
-- invoker mode means a caller who names an organization they do not belong to gets rows filtered to nothing
-- by RLS rather than a real answer computed under bypassed policies. Matches public.create_client and
-- public.check_rate_limit, both invoker.

drop function if exists private.effective_employee_seat_limit(uuid, timestamptz);

create or replace function public.effective_employee_seat_limit(
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
security invoker
set search_path = pg_catalog, public
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

comment on function public.effective_employee_seat_limit(uuid, timestamptz) is
  'Single authority for the employee_seats limit. effective.ts calls this instead of re-deriving it.';

revoke all on function public.effective_employee_seat_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.effective_employee_seat_limit(uuid, timestamptz) to authenticated;
