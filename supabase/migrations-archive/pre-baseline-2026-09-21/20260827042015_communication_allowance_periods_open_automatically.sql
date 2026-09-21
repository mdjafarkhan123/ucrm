-- Communications: open the allowance period both channels already require.
--
-- Neither `communication_email_allowance_periods` nor `website_chat_allowance_periods` had a writer in
-- production code -- only pgTAP fixtures ever inserted one. Both channels resolve their allowance by
-- finding the period covering now(), so with no period open the outbound email worker parked every send
-- and `accept_website_chat_first_message` refused every first message with
-- `allowance_period_unavailable`. The channels were fail-closed against a window nobody opened.
--
-- Shape, and why it is not "the payment command opens the period":
--
--  1. Free access never touches `paid_through_date` -- `apply_organization_free_access_change` writes its
--     own grant chain and leaves the commercial projection's paid-through alone. A fix hung off a payment
--     event would starve every free-access organization.
--  2. Several commands advance commercial state directly (free access, limit exceptions, closure and
--     restore, legacy reconciliation), so no single existing command is the seam either.
--  3. What they all share is the final `update public.organization_commercial_state` -- that is the seam
--     used below. A trigger there also cannot read a stale projection the way a trigger on the event
--     insert would: in `apply_organization_commercial_command` the event row is inserted *before* the
--     state row is advanced, so an initial payment would still look unpaid.
--
-- The period itself is derived rather than recorded, following ordinary metered-billing practice
-- (Stripe, Lago and Orb all derive the current cycle from a stable anchor and open it idempotently
-- instead of writing one per billing event): the window is the monthly window containing `at`, anchored
-- on the organization's creation date in its own commercial timezone.
-- `platform_package_versions.billing_period` is `check (billing_period = 'monthly')`, so monthly is the
-- only cadence the product can have and the window is unambiguous.

-- 0. Foreign-key cover --------------------------------------------------------------------------------

-- `opened_by_commercial_event_id` has been nullable and unwritten since Part 2B, so its missing index
-- never cost anything. This command is the first thing to populate it, and an organization purge deletes
-- commercial events while this table grows by one row per organization per month -- an unindexed foreign
-- key would make each of those deletes scan the whole table. `website_chat_allowance_periods` already
-- carries the equivalent index; this brings email level with it.
create index if not exists communication_email_allowance_periods_commercial_event_idx
  on public.communication_email_allowance_periods (opened_by_commercial_event_id)
  where opened_by_commercial_event_id is not null;

-- 1. The window ---------------------------------------------------------------------------------------

-- Returns no row -- deliberately -- for an organization that is not active or has no current access.
-- Both channels then stay exactly as fail-closed as they are today, which is the honest answer for an
-- unpaid, pending, suspended, or closed organization: the entitlement resolvers
-- (`private.effective_website_chat_conversation_limit`, the email limit authority) read package limits
-- and overrides, not payment state, so this window is the only place access is checked before a unit can
-- be claimed.
create or replace function private.current_communication_allowance_window(
  target_organization_id uuid,
  at timestamptz default now()
)
returns table (
  window_starts_at timestamptz,
  window_ends_at timestamptz,
  commercial_event_id uuid
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with zone as (
    select coalesce(
      (
        select settings.commercial_timezone
        from public.organization_commercial_settings as settings
        where settings.organization_id = target_organization_id
      ),
      'UTC'
    ) as name
  ), active_organization as (
    -- 'pending_setup', 'suspended', 'pending_closure' and 'closed' never open a period.
    select organization.id, organization.created_at
    from public.organizations as organization
    where organization.id = target_organization_id
      and organization.lifecycle_status = 'active'
  ), local_today as (
    select ((at at time zone (select name from zone))::date) as value
  ), paid_access as (
    -- Grace counts as paid here for the same reason it does everywhere else: an organization inside its
    -- grace period still has access.
    select (state.grace_ends_at is not null and state.grace_ends_at > at) as active,
           state.last_event_id
    from public.organization_commercial_state as state
    where state.organization_id = target_organization_id
  ), free_events as (
    -- The grant chain, mirroring `computeFreeAccessState` in src/lib/server/access/effective.ts: events
    -- group by their root grant, the newest event in a group decides that grant's current end date, and
    -- an 'end' closes it.
    select event.id,
           event.target_grant_id,
           event.action,
           event.starts_at,
           event.access_until_date,
           event.occurred_at,
           coalesce(event.target_grant_id, event.id) as root_id
    from public.organization_free_access_events as event
    where event.organization_id = target_organization_id
  ), free_latest as (
    select distinct on (root_id) root_id, action, access_until_date
    from free_events
    order by root_id, occurred_at desc, id desc
  ), free_access as (
    select true as active
    from free_events as root
    join free_latest as latest on latest.root_id = root.id
    where root.target_grant_id is null
      and latest.action <> 'end'
      and root.starts_at <= (select value from local_today)
      and (
        latest.access_until_date is null
        or latest.access_until_date >= (select value from local_today)
      )
    limit 1
  ), anchor as (
    -- The organization's own creation date in its commercial timezone. Stable for the lifetime of the
    -- organization, so the window never shifts underneath a period that is already open, and the meter
    -- resets on the same calendar day the account started -- the ordinary monthly-from-signup anchor.
    select ((organization.created_at at time zone (select name from zone))::date) as value
    from active_organization as organization
  ), elapsed_months as (
    select (
      extract(year from age((select value from local_today), (select value from anchor))) * 12
      + extract(month from age((select value from local_today), (select value from anchor)))
    )::integer as value
  )
  select
    (
      (((select value from anchor) + make_interval(months => (select value from elapsed_months)))::timestamp)
      at time zone (select name from zone)
    ) as window_starts_at,
    (
      (((select value from anchor) + make_interval(months => (select value from elapsed_months) + 1))::timestamp)
      at time zone (select name from zone)
    ) as window_ends_at,
    (select last_event_id from paid_access) as commercial_event_id
  from active_organization
  where coalesce((select active from paid_access), false)
     or coalesce((select active from free_access), false);
$$;

comment on function private.current_communication_allowance_window(uuid, timestamptz) is
  'The monthly allowance window covering `at` for one organization, anchored on its creation date in '
  'its commercial timezone. No row means no current access, and both channels stay fail-closed.';

revoke all on function private.current_communication_allowance_window(uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- 2. Opening it ---------------------------------------------------------------------------------------

-- Both channels in one command, as the deferral required: they share the shape and shared the gap, and
-- opening only one would leave the other silently parked.
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

  -- Each channel is skipped when a period *already covers* `at`, not merely when this exact window is
  -- already stored. Neither table constrains overlap -- their unique key is (organization_id, starts_at)
  -- -- and the anchor is read through the organization's commercial timezone, so an owner changing that
  -- timezone mid-month would otherwise derive a slightly different starts_at and open a second,
  -- overlapping window. Both channels resolve their allowance with `starts_at desc limit 1`, so that
  -- second window would shadow the first and silently hand the organization a fresh allowance.
  --
  -- The ON CONFLICT below still stands behind this: it is what makes two callers racing on the *same*
  -- window -- two visitors, the cron sweep, a commercial command -- a no-op for the loser.
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
  'and it is not already open. Idempotent.';

revoke all on function private.ensure_communication_allowance_periods(uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- 3. When access changes ------------------------------------------------------------------------------

create or replace function private.open_communication_allowance_periods_on_commercial_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- now(), not the event's occurred_at: a backdated legacy import still needs today's window opened, and
  -- a future-dated one must not open a window early.
  perform private.ensure_communication_allowance_periods(new.organization_id, now());
  return null;
end;
$$;

revoke all on function private.open_communication_allowance_periods_on_commercial_change()
  from public, anon, authenticated, service_role;

-- Every commercial path -- initial payment, renewal, correction, refund, reversal, free access granted or
-- extended, reactivation, legacy reconciliation -- finishes by advancing this projection row, so this is
-- the one seam all of them cross. Commercial state changes are owner-driven and rare, so firing on every
-- update (rather than a narrow WHEN clause that would have to enumerate every access-granting shape) is
-- both cheaper to reason about and impossible to leave a path out of.
drop trigger if exists organization_commercial_state_open_allowance_periods
  on public.organization_commercial_state;
create trigger organization_commercial_state_open_allowance_periods
after update on public.organization_commercial_state
for each row
execute function private.open_communication_allowance_periods_on_commercial_change();

-- 4. Month rollover -----------------------------------------------------------------------------------

-- No commercial event fires at a month boundary, so the window has to roll on a schedule. The anti-join
-- is what keeps this cheap: in steady state it matches nothing, and just after a boundary it matches each
-- active organization exactly once. Both existing (organization_id, starts_at desc) indexes serve it.
create or replace function private.open_due_communication_allowance_periods()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  due_organization_id uuid;
  opened_count integer := 0;
begin
  for due_organization_id in
    select organization.id
    from public.organizations as organization
    where organization.lifecycle_status = 'active'
      and (
        not exists (
          select 1
          from public.website_chat_allowance_periods as period
          where period.organization_id = organization.id
            and period.starts_at <= now()
            and period.ends_at > now()
        )
        or not exists (
          select 1
          from public.communication_email_allowance_periods as period
          where period.organization_id = organization.id
            and period.starts_at <= now()
            and period.ends_at > now()
        )
      )
  loop
    perform private.ensure_communication_allowance_periods(due_organization_id, now());
    opened_count := opened_count + 1;
  end loop;

  return opened_count;
end;
$$;

comment on function private.open_due_communication_allowance_periods() is
  'Sweep: opens the current allowance window for every active organization missing one. Rolls the window '
  'at each month boundary and backfills organizations that predate this command.';

revoke all on function private.open_due_communication_allowance_periods()
  from public, anon, authenticated, service_role;

create extension if not exists pg_cron;

-- Pure SQL, so this runs directly rather than through the net.http_post -> internal route bridge the
-- closure and invitation jobs need for Node-side work. That also means it has no deployment or tunnel
-- dependency: it behaves in development exactly as it will in production. cron.schedule upserts by job
-- name, so re-running this migration is idempotent. Hourly, and off the hour, so a month boundary costs
-- at most an hour for an organization that is not otherwise active -- one that *is* active gets its
-- window from the commercial trigger the moment its access changes.
select cron.schedule(
  'communications-allowance-periods-hourly',
  '7 * * * *',
  $cron$select private.open_due_communication_allowance_periods();$cron$
);
