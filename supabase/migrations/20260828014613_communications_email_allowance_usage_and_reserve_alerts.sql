-- Communications Part 7.6b: the organization-facing allowance usage read, plus the one-time
-- "protected essential reserve is exhausted" alerting.
--
-- Contract (docs/contractor-email-contract.md § Package allowances and counting):
--   "Optional email pauses at the normal allowance. The protected reserve permits requested quotes,
--    invoices, receipts, security notices, and direct human replies. If the reserve is exhausted,
--    queue essential mail temporarily, warn the organization, and alert Jafar."
--
-- The claim already decides exhaustion: it stamps the delivery intent with
-- failure_code = 'email_allowance_exhausted' and holds the outbox event. Following Part 7.6a, the
-- alert is written by a trigger on the table that already records the fact rather than by an edit
-- inside the claim, so no claim branch can silently skip it and there is no dual write to drift.
--
-- Warning-once: the alert row is unique per (organization, allowance period, kind). Only the insert
-- that actually creates the row writes the Jafar notification, so a period in which hundreds of
-- essential messages are held still produces exactly one alert. The trigger's WHEN clause keeps a
-- repeated deferral (failure_code unchanged) from firing at all.
--
-- The contractor-facing warning itself is derived live from the counters in the read below, so
-- nothing has to be cleared when the next period opens or an override raises the reserve.

-- 1. One row per organization per allowance period per alert kind.
create table public.communication_email_allowance_alerts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  allowance_period_id uuid not null references public.communication_email_allowance_periods(id) on delete cascade,
  alert_kind text not null check (alert_kind in ('essential_reserve_exhausted')),
  first_detected_at timestamptz not null default now(),
  constraint communication_email_allowance_alerts_once
    unique (organization_id, allowance_period_id, alert_kind)
);

create index communication_email_allowance_alerts_period_idx
  on public.communication_email_allowance_alerts (allowance_period_id);

alter table public.communication_email_allowance_alerts enable row level security;
revoke all on public.communication_email_allowance_alerts from anon, authenticated;
grant select, insert on public.communication_email_allowance_alerts to service_role;

-- 2. Detect the exhaustion once and alert Jafar.
create or replace function private.record_communication_email_reserve_exhaustion()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  active_allowance record;
  organization_name text;
begin
  select * into active_allowance
  from private.resolve_communication_email_allowance(new.organization_id, now());
  if not found then
    return null;
  end if;

  insert into public.communication_email_allowance_alerts (
    organization_id, allowance_period_id, alert_kind
  ) values (new.organization_id, active_allowance.period_id, 'essential_reserve_exhausted')
  on conflict on constraint communication_email_allowance_alerts_once do nothing;
  if not found then
    return null;
  end if;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = new.organization_id;

  insert into public.platform_owner_notifications (kind, severity, title, body, target_kind, target_id)
  values (
    'communication_email_essential_reserve_exhausted',
    'urgent',
    'Protected essential email reserve exhausted',
    coalesce(organization_name, 'An organization')
      || ' has used its whole protected essential email reserve for the current billing period. '
      || 'Requested quotes, invoices, receipts, security notices, and direct replies are being held '
      || 'until the period resets or the allowance is raised.',
    'organization',
    new.organization_id
  );
  return null;
end;
$$;

revoke all on function private.record_communication_email_reserve_exhaustion() from public, anon, authenticated;

create trigger communication_delivery_intents_essential_reserve_exhausted
after update on public.communication_delivery_intents
for each row
when (
  new.allowance_class = 'essential'
  and new.failure_code = 'email_allowance_exhausted'
  and old.failure_code is distinct from new.failure_code
)
execute function private.record_communication_email_reserve_exhaustion();

-- 3. The organization-facing read behind the usage card. One row; both counters are the same sums
--    the claim itself takes (accepted usage plus live reservations), so the card and the claim can
--    never disagree about what is left. Both sums ride existing composite indexes.
create or replace function public.get_organization_communication_email_usage(
  p_organization_id uuid
)
returns table (
  period_id uuid,
  period_starts_at timestamptz,
  period_ends_at timestamptz,
  organization_timezone text,
  optional_limit_state text,
  optional_limit_value integer,
  optional_used integer,
  essential_limit_state text,
  essential_limit_value integer,
  essential_used integer,
  essential_reserve_exhausted boolean,
  essential_reserve_exhausted_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  with allowance as (
    select * from private.resolve_communication_email_allowance(p_organization_id, now())
  ), counted as (
    select
      allowance.*,
      (
        select coalesce(sum(usage.recipient_count), 0)::integer
        from public.communication_email_usage_events usage
        where usage.organization_id = p_organization_id
          and usage.allowance_period_id = allowance.period_id
          and usage.allowance_class = 'optional'
      ) + (
        select coalesce(sum(reservation.recipient_count), 0)::integer
        from public.communication_email_capacity_reservations reservation
        where reservation.organization_id = p_organization_id
          and reservation.allowance_period_id = allowance.period_id
          and reservation.allowance_class = 'optional'
          and reservation.reservation_state in ('reserved', 'submission_unknown')
      ) as optional_used,
      (
        select coalesce(sum(usage.recipient_count), 0)::integer
        from public.communication_email_usage_events usage
        where usage.organization_id = p_organization_id
          and usage.allowance_period_id = allowance.period_id
          and usage.allowance_class = 'essential'
      ) + (
        select coalesce(sum(reservation.recipient_count), 0)::integer
        from public.communication_email_capacity_reservations reservation
        where reservation.organization_id = p_organization_id
          and reservation.allowance_period_id = allowance.period_id
          and reservation.allowance_class = 'essential'
          and reservation.reservation_state in ('reserved', 'submission_unknown')
      ) as essential_used
    from allowance
  )
  select
    counted.period_id,
    counted.period_starts_at,
    counted.period_ends_at,
    coalesce(settings.timezone, 'UTC'),
    counted.operational_limit_state,
    counted.operational_limit_value,
    counted.optional_used,
    counted.essential_limit_state,
    counted.essential_limit_value,
    counted.essential_used,
    counted.essential_limit_state = 'numeric'
      and counted.essential_limit_value is not null
      and counted.essential_used >= counted.essential_limit_value,
    alert.first_detected_at
  from counted
  left join public.organization_settings as settings on settings.organization_id = p_organization_id
  left join public.communication_email_allowance_alerts as alert
    on alert.organization_id = p_organization_id
    and alert.allowance_period_id = counted.period_id
    and alert.alert_kind = 'essential_reserve_exhausted'
  ;
$$;

revoke all on function public.get_organization_communication_email_usage(uuid)
  from public, anon, authenticated;
grant execute on function public.get_organization_communication_email_usage(uuid) to service_role;
