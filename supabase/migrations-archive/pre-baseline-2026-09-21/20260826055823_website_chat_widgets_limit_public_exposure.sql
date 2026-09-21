-- Correction to 20260902150000: PostgREST only exposes the public schema, exactly like
-- 20260826090100 had to correct effective_employee_seat_limit. effective.ts calls this
-- directly via supabase-js .rpc(), which never reaches `private`. Moving it to `public` and
-- security invoker, matching effective_employee_seat_limit's corrected shape exactly: the
-- tables it reads are already selectable by an authenticated member of the target
-- organization through existing RLS, so invoker mode means a caller naming an organization
-- they do not belong to gets rows filtered to nothing rather than a real answer computed
-- under bypassed policies. Also grants service_role, since resolveOrganizationAccess is
-- called by both the signed-in member path and every /jafar organization route.

drop function if exists private.effective_website_chat_widgets_limit(uuid, timestamptz);

create or replace function public.effective_website_chat_widgets_limit(
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
  package_found boolean;
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
    and override.limit_key = 'website_chat_widgets'
    and override.starts_at <= at
    and (override.expires_at is null or override.expires_at > at);
  override_found := found;

  if assignment_package_version_id is not null then
    select version_limit.limit_state, version_limit.limit_value
    into package_limit_state, package_limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = assignment_package_version_id
      and version_limit.limit_key = 'website_chat_widgets';
    package_found := found;
  else
    package_found := false;
  end if;

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

  source := case when override_found then 'override' else 'package' end;

  return next;
  return;
end;
$function$;

comment on function public.effective_website_chat_widgets_limit(uuid, timestamptz) is
  'Single authority for the website_chat_widgets limit. Mirrors effective_employee_seat_limit.';

revoke all on function public.effective_website_chat_widgets_limit(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.effective_website_chat_widgets_limit(uuid, timestamptz) to authenticated;
grant execute on function public.effective_website_chat_widgets_limit(uuid, timestamptz) to service_role;
