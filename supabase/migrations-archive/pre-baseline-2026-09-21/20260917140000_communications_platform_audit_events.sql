-- Communications A2 / Stage 2C (part 5c, platform-scoped prerequisite): an audit trail for Platform Owner
-- actions that are not about any single contractor -- a platform-wide SMS hold, a published retail rate. The
-- existing public.access_audit_events keeps organization_id NOT NULL by design (a tenant-scoped log must never
-- carry a blank-tenant row); loosening that constraint would let a platform action masquerade as belonging to
-- no organization inside an otherwise strictly org-scoped table. Standard multi-tenant practice instead gives
-- platform-wide events their own small table. Decided with Jafar 2026-09-14 (see Memory/campaigns/
-- communications-activation/NOW.md).
--
-- Same shape as access_audit_events, minus the organization tag: who (the owner's email -- Jafar has no
-- Supabase user id), when, what the action was, what it targeted, and a before/after snapshot. Server-owned:
-- no browser client (anon or authenticated) may read or write it; only service_role does, via
-- recordPlatformAudit in $lib/server/access/owner.ts.

create table public.platform_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_owner_email text not null,
  event_type text not null check (event_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_type text not null check (target_type ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  target_key text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now()
);

create index platform_audit_events_created_idx
  on public.platform_audit_events (created_at desc);

create index platform_audit_events_target_idx
  on public.platform_audit_events (target_type, target_key, created_at desc);

comment on table public.platform_audit_events is
  'Audit trail for Platform Owner actions with no single owning organization (a platform-wide SMS hold, a '
  'published retail rate). Append-only; server-owned via recordPlatformAudit. Contractor-scoped owner actions '
  'keep using public.access_audit_events -- this table is only for the platform-wide case that table cannot '
  'represent.';

alter table public.platform_audit_events enable row level security;

revoke all on table public.platform_audit_events from public, anon, authenticated;
revoke all on table public.platform_audit_events from service_role;
grant select, insert on table public.platform_audit_events to service_role;
