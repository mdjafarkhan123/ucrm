-- Part 9: recoverable closure and strict purge -- schema foundation.
--
-- Extends the existing lifecycle_status column and the shared commercial event/safe-event streams
-- (from 6A/6D/6C) with closure-related states and event kinds. Adds the actor_kind value needed for
-- the day-30 automatic purge, which is triggered by a database timer rather than a human owner.

-- ---------------------------------------------------------------------------
-- Lifecycle status
-- ---------------------------------------------------------------------------

alter table public.organizations
  drop constraint if exists organizations_lifecycle_status_check;

alter table public.organizations
  add constraint organizations_lifecycle_status_check check (
    lifecycle_status in ('pending_setup', 'active', 'suspended', 'pending_closure', 'closed')
  );

-- ---------------------------------------------------------------------------
-- Commercial events: new kinds, a system actor for the automatic purge, and reason enforcement
-- ---------------------------------------------------------------------------

alter table public.organization_commercial_events
  drop constraint if exists organization_commercial_events_event_kind_check;

alter table public.organization_commercial_events
  add constraint organization_commercial_events_event_kind_check check (
    event_kind in (
      'initial_payment_confirmed',
      'renewal_confirmed',
      'payment_correction_recorded',
      'refund_recorded',
      'payment_reversal_recorded',
      'paid_through_adjusted',
      'commercial_timezone_changed',
      'free_access_granted',
      'free_access_extended',
      'free_access_converted_forever',
      'free_access_ended',
      'organization_suspended',
      'organization_reactivated',
      'pending_setup_resolved',
      'package_version_changed',
      'feature_exception_changed',
      'limit_exception_changed',
      'organization_closure_started',
      'organization_closure_restored',
      'organization_closure_completed'
    )
  );

alter table public.organization_commercial_events
  drop constraint if exists organization_commercial_events_actor_kind_check;

alter table public.organization_commercial_events
  alter column actor_kind drop default;

alter table public.organization_commercial_events
  add constraint organization_commercial_events_actor_kind_check check (
    actor_kind in ('platform_owner', 'system')
  );

alter table public.organization_commercial_events
  alter column actor_kind set default 'platform_owner';

alter table public.organization_commercial_events
  drop constraint if exists organization_commercial_events_actor_email_kind_check;

-- Two existing legacy-import rows have actor_kind = 'platform_owner' with no recorded email --
-- tolerate that (no real actor to attribute), but require a real email for every non-legacy owner
-- action and require the automatic system actor to never claim a human email.
alter table public.organization_commercial_events
  add constraint organization_commercial_events_actor_email_kind_check check (
    (actor_kind = 'system' and actor_owner_email is null)
    or (actor_kind = 'platform_owner' and (is_legacy_import or actor_owner_email is not null))
  );

alter table public.organization_commercial_events
  drop constraint if exists organization_commercial_events_reason_check;

alter table public.organization_commercial_events
  add constraint organization_commercial_events_reason_check check (
    is_legacy_import
    or event_kind not in (
      'organization_suspended',
      'organization_reactivated',
      'paid_through_adjusted',
      'refund_recorded',
      'payment_reversal_recorded',
      'payment_correction_recorded',
      'commercial_timezone_changed',
      'pending_setup_resolved',
      'package_version_changed',
      'feature_exception_changed',
      'limit_exception_changed',
      'organization_closure_started',
      'organization_closure_restored'
    )
    or char_length(trim(coalesce(private_reason, ''))) > 0
  );

-- ---------------------------------------------------------------------------
-- Safe events: new kinds and payload keys
-- ---------------------------------------------------------------------------

alter table public.organization_safe_events
  drop constraint if exists organization_safe_events_safe_kind_check;

alter table public.organization_safe_events
  add constraint organization_safe_events_safe_kind_check check (
    safe_kind in (
      'payment_recorded',
      'renewal_recorded',
      'access_period_updated',
      'account_suspended',
      'account_reactivated',
      'free_access_updated',
      'commercial_timezone_updated',
      'package_changed',
      'feature_access_changed',
      'limit_access_changed',
      'closure_started',
      'closure_restored',
      'closure_completed'
    )
  );

create or replace function private.organization_safe_event_payload_is_allowed(payload jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(
    bool_and(
      payload_key in (
        'paid_through_date',
        'grace_ends_at',
        'access_status',
        'effective_at',
        'package_display_name',
        'package_version_number',
        'free_access_until_date',
        'commercial_timezone',
        'feature_key',
        'limit_key',
        'limit_state',
        'limit_value',
        'closure_deadline_at'
      )
      and jsonb_typeof(payload -> payload_key) in ('string', 'number', 'boolean', 'null')
    ),
    true
  )
  from jsonb_object_keys(payload) as payload_key;
$$;

revoke all on function private.organization_safe_event_payload_is_allowed(jsonb) from public;
grant execute on function private.organization_safe_event_payload_is_allowed(jsonb) to authenticated, service_role;
