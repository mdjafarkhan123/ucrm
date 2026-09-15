-- Communications A2 / Stage 9A: server-only ledger for the Twilio Trust Hub / A2P 10DLC submission saga.
--
-- Gap this closes: communication_sms_registrations captures a contractor's attested answers (Stage 3A), but
-- nothing ever forwards them to Twilio -- provider_registration_sid stays null forever. As an ISV, submitting
-- one contractor's registration is itself a multi-step Twilio Trust Hub saga (Secondary Customer Profile ->
-- business/authorized-representative End Users -> Address -> entity assignments -> evaluate -> submit -> A2P
-- Trust Product -> Brand Registration -> Campaign), each step its own billable, independently retryable Twilio
-- API call. This migration only adds the durable state for that saga; the saga itself (the code that actually
-- calls Twilio) is a later part.
--
-- Mirrors Stage 2B's split exactly: communication_sms_trust_hub_resources is the current-state reconciler
-- target (like communication_twilio_accounts), communication_sms_trust_hub_events is the append-only sanitized
-- step history (like communication_twilio_provisioning_events). No secret and no raw provider response body
-- belongs in either -- SIDs, short status strings and sanitized reasons only. Both tables are pure server
-- state: no contractor-facing command wraps them, the same way twilio-provisioning-store.ts writes
-- communication_twilio_accounts directly.

create table public.communication_sms_trust_hub_resources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  registration_id uuid not null references public.communication_sms_registrations(id) on delete cascade,
  resource_role text not null,
  provider_sid text,
  -- Twilio's own short status string for this resource (e.g. draft, pending-review, twilio-approved, PENDING,
  -- APPROVED, FAILED). Kept free-form because each Trust Hub/Brand/Campaign resource has its own vocabulary;
  -- status below is our normalized cross-resource read.
  provider_status text,
  status text not null default 'pending',
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_sms_trust_hub_resources_role_key unique (registration_id, resource_role),
  constraint communication_sms_trust_hub_resources_role_check check (resource_role in (
    'customer_profile', 'end_user_business_information', 'end_user_authorized_representative',
    'supporting_document_address', 'a2p_trust_product', 'brand_registration', 'campaign'
  )),
  constraint communication_sms_trust_hub_resources_status_check
    check (status in ('pending', 'created', 'submitted', 'approved', 'rejected', 'failed')),
  constraint communication_sms_trust_hub_resources_provider_sid_check
    check (provider_sid is null or char_length(trim(provider_sid)) between 1 and 64),
  constraint communication_sms_trust_hub_resources_provider_status_check
    check (provider_status is null or char_length(provider_status) <= 100),
  constraint communication_sms_trust_hub_resources_failure_reason_check
    check (failure_reason is null or char_length(failure_reason) <= 2000)
);

create index communication_sms_trust_hub_resources_registration_idx
  on public.communication_sms_trust_hub_resources (organization_id, registration_id);

create table public.communication_sms_trust_hub_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  registration_id uuid not null references public.communication_sms_registrations(id) on delete cascade,
  -- Null for a whole-saga event (e.g. the saga starting or a rate-limit backoff) that isn't about one resource.
  resource_role text,
  operation text not null,
  step text not null,
  result text not null,
  -- Sanitized only: SIDs, short status strings, counts, reasons. Never a raw Twilio response body -- that
  -- body echoes the contractor's attested business/representative details already stored once in
  -- communication_sms_registration_submissions, and duplicating it here would spread PII across tables for
  -- no reconciliation benefit.
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint communication_sms_trust_hub_events_operation_check
    check (operation in ('submit_registration', 'sync_status')),
  constraint communication_sms_trust_hub_events_step_check
    check (step ~ '^[a-z][a-z0-9_]{1,63}$'),
  constraint communication_sms_trust_hub_events_result_check
    check (result in ('succeeded', 'skipped', 'rolled_back', 'needs_review', 'failed')),
  constraint communication_sms_trust_hub_events_role_check check (resource_role is null or resource_role in (
    'customer_profile', 'end_user_business_information', 'end_user_authorized_representative',
    'supporting_document_address', 'a2p_trust_product', 'brand_registration', 'campaign'
  )),
  constraint communication_sms_trust_hub_events_detail_object_check
    check (jsonb_typeof(detail) = 'object')
);

create index communication_sms_trust_hub_events_registration_idx
  on public.communication_sms_trust_hub_events (organization_id, registration_id, created_at desc);

alter table public.communication_sms_trust_hub_resources enable row level security;
alter table public.communication_sms_trust_hub_events enable row level security;

revoke all on table public.communication_sms_trust_hub_resources from public, anon, authenticated;
revoke all on table public.communication_sms_trust_hub_events from public, anon, authenticated;
revoke all on table public.communication_sms_trust_hub_resources from service_role;
revoke all on table public.communication_sms_trust_hub_events from service_role;

-- Current-state ledger: the saga reconciler reads and upserts it directly, the same way the Stage 2B store
-- writes communication_twilio_accounts. No delete: a resubmission updates a role's existing row rather than
-- recreating it, since Twilio Brand registration carries a real fee and must not be repeated by accident.
grant select, insert, update on table public.communication_sms_trust_hub_resources to service_role;

-- Append-only: the saga appends and reads history but never rewrites it.
grant select, insert on table public.communication_sms_trust_hub_events to service_role;

comment on table public.communication_sms_trust_hub_resources is
  'Server-owned current state of each Twilio Trust Hub/Brand/Campaign object created while submitting one SMS '
  'registration as an ISV. No secret and no raw provider response body belongs here.';
comment on table public.communication_sms_trust_hub_events is
  'Append-only sanitized history of the Twilio Trust Hub submission saga''s steps, mirroring '
  'communication_twilio_provisioning_events for the A2P registration path.';
