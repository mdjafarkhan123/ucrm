-- Part 2B-C: owner-managed package defaults. Published versions remain immutable;
-- Jafar sets these values on the next draft, alongside the package's other limits.
create or replace function public.manage_platform_package_email_allowances(
  target_version_id uuid,
  target_operational_state text,
  target_operational_value integer,
  target_essential_state text,
  target_essential_value integer,
  actor_email text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  version_row public.platform_package_versions%rowtype;
begin
  if char_length(trim(coalesce(actor_email, ''))) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if target_operational_state not in ('unlimited', 'not_included', 'numeric')
    or target_essential_state not in ('unlimited', 'not_included', 'numeric') then
    raise exception 'Choose a valid email allowance type.' using errcode = 'check_violation';
  end if;
  if (target_operational_state = 'numeric' and coalesce(target_operational_value, 0) < 1)
    or (target_operational_state <> 'numeric' and target_operational_value is not null)
    or (target_essential_state = 'numeric' and coalesce(target_essential_value, 0) < 1)
    or (target_essential_state <> 'numeric' and target_essential_value is not null) then
    raise exception 'A numeric email allowance must be at least one recipient.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.platform_package_versions
  where id = target_version_id
  for update;
  if not found or version_row.status <> 'draft' then
    raise exception 'Email allowances can only be changed on a draft package version.' using errcode = 'check_violation';
  end if;

  delete from public.platform_package_version_limits
  where package_version_id = version_row.id
    and limit_key in ('operational_email_recipients', 'essential_email_recipients');

  insert into public.platform_package_version_limits (package_version_id, limit_key, limit_state, limit_value)
  values
    (version_row.id, 'operational_email_recipients', target_operational_state,
      case when target_operational_state = 'numeric' then target_operational_value end),
    (version_row.id, 'essential_email_recipients', target_essential_state,
      case when target_essential_state = 'numeric' then target_essential_value end);

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    lower(trim(actor_email)), 'package.email_allowances_changed', 'platform_package_version', version_row.id::text,
    jsonb_build_object(
      'operational_state', target_operational_state, 'operational_value', target_operational_value,
      'essential_state', target_essential_state, 'essential_value', target_essential_value
    )
  );
  return version_row.id;
end;
$$;

revoke all on function public.manage_platform_package_email_allowances(uuid, text, integer, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.manage_platform_package_email_allowances(uuid, text, integer, text, integer, text)
  to service_role;
