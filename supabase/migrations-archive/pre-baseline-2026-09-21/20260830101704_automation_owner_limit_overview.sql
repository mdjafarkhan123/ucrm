-- Contractor Settings Part 6B, slice 3b: owner read model for the organization-detail Automation surface.
--
-- docs/automation-behavior-contract.md § Platform Owner surfaces: "Existing organization detail owns
-- effective values and reasoned/effective-dated feature, limit, action, and suspension exceptions. It shows
-- package default, current exception, effective value, author/reason/time, and fallback."
--
-- This is the single owner read model that assembles those columns for all seven Automation limits in one
-- round trip. The effective value and its source are taken from the authoritative resolver
-- (effective_automation_limits) rather than recomputed here, so precedence and effective-date behaviour can
-- never drift from the runtime the contractor sees. The package default and the reasoned/effective-dated
-- exception (author, reason, window) are read directly for display. Shape and grants follow the sibling
-- read model get_organization_automation_authority (20260913090200): owner-only, service_role execute.

create or replace function public.get_organization_automation_limits(
  p_organization_id uuid,
  at timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with keys (limit_key) as (
    values
      ('automation_active_recipes'),
      ('automation_max_conditions_per_recipe'),
      ('automation_max_steps_per_recipe'),
      ('automation_max_customer_messages_per_enrollment'),
      ('automation_min_customer_message_spacing_minutes'),
      ('automation_max_delay_days'),
      ('automation_max_enrollment_duration_days')
  ),
  current_assignment as (
    select assignment.package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = p_organization_id
    order by assignment.effective_at desc, assignment.id desc
    limit 1
  ),
  package_default as (
    select version_limit.limit_key, version_limit.limit_state, version_limit.limit_value
    from public.platform_package_version_limits as version_limit
    where version_limit.package_version_id = (select package_version_id from current_assignment)
      and version_limit.limit_key in (
        'automation_active_recipes', 'automation_max_conditions_per_recipe',
        'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
        'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
        'automation_max_enrollment_duration_days'
      )
  ),
  exception_row as (
    select override.limit_key, override.limit_state, override.limit_value, override.is_unlimited,
           override.reason, override.actor_owner_email, override.starts_at, override.expires_at,
           (override.starts_at <= at and (override.expires_at is null or override.expires_at > at)) as is_active
    from public.organization_limit_overrides as override
    where override.organization_id = p_organization_id
      and override.limit_key in (
        'automation_active_recipes', 'automation_max_conditions_per_recipe',
        'automation_max_steps_per_recipe', 'automation_max_customer_messages_per_enrollment',
        'automation_min_customer_message_spacing_minutes', 'automation_max_delay_days',
        'automation_max_enrollment_duration_days'
      )
  ),
  effective as (
    select resolved.limit_key, resolved.state, resolved.value, resolved.is_unlimited, resolved.source
    from public.effective_automation_limits(p_organization_id, at) as resolved
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'limit_key', keys.limit_key,
        'package_default', jsonb_build_object(
          'state', coalesce(package_default.limit_state, 'not_included'),
          'value', case when package_default.limit_state = 'numeric' then package_default.limit_value end
        ),
        'effective', jsonb_build_object(
          'state', effective.state,
          'value', effective.value,
          'is_unlimited', effective.is_unlimited,
          'source', effective.source
        ),
        'exception', case
          when exception_row.limit_key is null then null
          else jsonb_build_object(
            'state', exception_row.limit_state,
            'value', case when exception_row.limit_state = 'numeric' then exception_row.limit_value end,
            'is_unlimited', exception_row.is_unlimited,
            'is_active', exception_row.is_active,
            'reason', exception_row.reason,
            'actor_owner_email', exception_row.actor_owner_email,
            'starts_at', exception_row.starts_at,
            'expires_at', exception_row.expires_at
          )
        end
      )
      order by keys.limit_key
    ),
    '[]'::jsonb
  )
  from keys
  left join package_default on package_default.limit_key = keys.limit_key
  left join exception_row on exception_row.limit_key = keys.limit_key
  left join effective on effective.limit_key = keys.limit_key;
$$;

comment on function public.get_organization_automation_limits(uuid, timestamptz) is
  'Owner-only read model: package default, effective value/source (from effective_automation_limits), and the reasoned/effective-dated exception for each of the seven Automation limits.';

revoke all on function public.get_organization_automation_limits(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.get_organization_automation_limits(uuid, timestamptz) to service_role;
