-- Communications A2 / Stage 2B: append-only, sanitized history of every Twilio provisioning and
-- credential-rotation step. This is the audit spine for the resumable provisioning saga. It stores no
-- secret: ciphertext lives in communication_twilio_credentials and plaintext never enters Postgres.
-- The saga itself reconciles from the durable account/credential records; this table records what happened
-- for operators and for the Stage 2C owner surface, not the machine state.

create table public.communication_twilio_provisioning_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Null only for a subaccount-creation step that failed before the account record was written; every later
  -- step carries the owning account. on delete set null keeps history readable if an account row is removed.
  twilio_account_id uuid references public.communication_twilio_accounts(id) on delete set null,
  operation text not null,
  step text not null,
  result text not null,
  -- Sanitized only: safe SIDs (AC/SK/MG), counts, reasons. Never an Auth Token, API-key secret, or raw
  -- provider response body.
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint communication_twilio_provisioning_events_operation_check
    check (operation in ('provision', 'rotate_auth_token', 'rotate_restricted_key')),
  constraint communication_twilio_provisioning_events_result_check
    check (result in ('succeeded', 'skipped', 'rolled_back', 'needs_review', 'failed')),
  constraint communication_twilio_provisioning_events_step_check
    check (step ~ '^[a-z][a-z0-9_]{1,63}$'),
  constraint communication_twilio_provisioning_events_detail_object_check
    check (jsonb_typeof(detail) = 'object')
);

-- History reads are always "latest events for this organization", newest first.
create index communication_twilio_provisioning_events_org_recent_idx
  on public.communication_twilio_provisioning_events (organization_id, created_at desc);

-- Correlate every step of one subaccount when investigating a partial provision.
create index communication_twilio_provisioning_events_account_idx
  on public.communication_twilio_provisioning_events (twilio_account_id)
  where twilio_account_id is not null;

alter table public.communication_twilio_provisioning_events enable row level security;

revoke all on table public.communication_twilio_provisioning_events from public, anon, authenticated;
revoke all on table public.communication_twilio_provisioning_events from service_role;

-- Append-only: the server writes and reads history but never updates or deletes it, so a partial provision
-- or a rotation rollback stays permanently visible.
grant select, insert on table public.communication_twilio_provisioning_events to service_role;

comment on table public.communication_twilio_provisioning_events is
  'Append-only sanitized history of Twilio provisioning and credential-rotation steps. No secret belongs here.';
