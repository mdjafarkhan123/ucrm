create or replace function private.ensure_communication_allowance_periods(
  target_organization_id uuid,
  at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  allowance_window record;
begin
  select * into allowance_window
  from private.current_communication_allowance_window(target_organization_id, at);
  if not found then
    return;
  end if;

  if not exists (
    select 1
    from public.communication_email_allowance_periods as period
    where period.organization_id = target_organization_id
      and period.starts_at <= at
      and period.ends_at > at
  ) then
    insert into public.communication_email_allowance_periods (
      organization_id, starts_at, ends_at, opened_by_commercial_event_id
    )
    values (
      target_organization_id,
      allowance_window.window_starts_at,
      allowance_window.window_ends_at,
      allowance_window.commercial_event_id
    )
    on conflict (organization_id, starts_at) do nothing;
  end if;

  if not exists (
    select 1
    from public.website_chat_allowance_periods as period
    where period.organization_id = target_organization_id
      and period.starts_at <= at
      and period.ends_at > at
  ) then
    insert into public.website_chat_allowance_periods (
      organization_id, starts_at, ends_at, opened_by_commercial_event_id
    )
    values (
      target_organization_id,
      allowance_window.window_starts_at,
      allowance_window.window_ends_at,
      allowance_window.commercial_event_id
    )
    on conflict (organization_id, starts_at) do nothing;
  end if;
end;
$$;

comment on function private.ensure_communication_allowance_periods(uuid, timestamptz) is
  'Opens the current allowance window for both Communications channels, if the organization has access '
  'and no period already covers the moment. Idempotent.';

revoke all on function private.ensure_communication_allowance_periods(uuid, timestamptz)
  from public, anon, authenticated, service_role;
