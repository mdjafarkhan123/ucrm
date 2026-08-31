-- Communications Part 2B-A: email allowance authority.
-- Values remain platform-owner managed package limits; the outbox integration lands in 2B-B.

alter table public.platform_package_version_limits
  drop constraint platform_package_version_limits_limit_key_check;

alter table public.platform_package_version_limits
  add constraint platform_package_version_limits_limit_key_check
  check (limit_key in ('employee_seats', 'operational_email_recipients', 'essential_email_recipients'));

alter table public.organization_limit_overrides
  drop constraint organization_limit_overrides_limit_key_check;

alter table public.organization_limit_overrides
  add constraint organization_limit_overrides_limit_key_check
  check (limit_key in ('employee_seats', 'operational_email_recipients', 'essential_email_recipients'));

-- The existing commercial record has only a calendar date. Email allowance resets need an
-- exact UTC interval, so a billing command must create this record instead of guessing one.
create table public.communication_email_allowance_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  opened_by_commercial_event_id uuid references public.organization_commercial_events(id),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  unique (organization_id, starts_at)
);

create index communication_email_allowance_periods_active_idx
  on public.communication_email_allowance_periods (organization_id, starts_at desc)
  where ends_at > starts_at;

alter table public.communication_email_allowance_periods enable row level security;
revoke all on public.communication_email_allowance_periods from anon, authenticated;
grant select, insert on public.communication_email_allowance_periods to service_role;

create or replace function private.resolve_communication_email_allowance(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  period_id uuid,
  period_starts_at timestamptz,
  period_ends_at timestamptz,
  operational_limit_state text,
  operational_limit_value integer,
  essential_limit_state text,
  essential_limit_value integer
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with active_period as (
    select period.id, period.starts_at, period.ends_at
    from public.communication_email_allowance_periods as period
    where period.organization_id = target_organization_id
      and period.starts_at <= at
      and period.ends_at > at
    order by period.starts_at desc
    limit 1
  ), package_version as (
    select assignment.package_version_id
    from public.organization_package_assignments as assignment
    where assignment.organization_id = target_organization_id
      and assignment.effective_at <= at
    order by assignment.effective_at desc, assignment.id desc
    limit 1
  ), resolved_limits as (
    select limit_key, limit_state, limit_value
    from public.platform_package_version_limits
    where package_version_id = (select package_version_id from package_version)
      and limit_key in ('operational_email_recipients', 'essential_email_recipients')
  ), active_overrides as (
    select limit_key, limit_state, limit_value
    from public.organization_limit_overrides
    where organization_id = target_organization_id
      and limit_key in ('operational_email_recipients', 'essential_email_recipients')
      and starts_at <= at
      and (expires_at is null or expires_at > at)
  )
  select
    period.id,
    period.starts_at,
    period.ends_at,
    coalesce(operational_override.limit_state, operational.limit_state),
    coalesce(operational_override.limit_value, operational.limit_value),
    coalesce(essential_override.limit_state, essential.limit_state),
    coalesce(essential_override.limit_value, essential.limit_value)
  from active_period as period
  left join resolved_limits as operational on operational.limit_key = 'operational_email_recipients'
  left join resolved_limits as essential on essential.limit_key = 'essential_email_recipients'
  left join active_overrides as operational_override on operational_override.limit_key = 'operational_email_recipients'
  left join active_overrides as essential_override on essential_override.limit_key = 'essential_email_recipients';
$$;

revoke all on function private.resolve_communication_email_allowance(uuid, timestamptz) from public;
