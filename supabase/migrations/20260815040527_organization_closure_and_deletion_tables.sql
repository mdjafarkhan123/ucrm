-- Part 9: recoverable closure and strict purge -- new tables.
--
-- organization_closure_records tracks the current (and past) closure window for an organization.
-- organization_closure_notices makes the daily reminder job idempotent -- each notice kind sends at
-- most once per closure. organization_deletion_receipts is intentionally standalone (no foreign key
-- to organizations, no name, no personal data) so it survives the organization it describes being
-- fully purged.

create table public.organization_deletion_receipts (
  operation_id uuid primary key default gen_random_uuid(),
  trigger_kind text not null check (trigger_kind in ('scheduled', 'early_manual')),
  initiated_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'in_progress' check (
    status in ('in_progress', 'completed', 'failed_partial')
  ),
  component_results jsonb not null default '{}'::jsonb,
  retry_count integer not null default 0 check (retry_count >= 0),
  created_at timestamptz not null default now(),
  constraint organization_deletion_receipts_component_results_object_check check (
    jsonb_typeof(component_results) = 'object'
  ),
  constraint organization_deletion_receipts_completed_fields_check check (
    (status = 'completed') = (completed_at is not null)
  )
);

create table public.organization_closure_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  reason text not null check (char_length(trim(reason)) between 1 and 1000),
  prior_lifecycle_status text not null check (prior_lifecycle_status in ('active', 'suspended')),
  started_at timestamptz not null default now(),
  started_by_owner_email text not null check (char_length(trim(started_by_owner_email)) between 3 and 320),
  deadline_at timestamptz not null,
  status text not null default 'pending_closure' check (
    status in ('pending_closure', 'restored', 'purge_in_progress', 'purged')
  ),
  restored_at timestamptz,
  restored_by_owner_email text,
  restoration_evidence_note text check (
    restoration_evidence_note is null or char_length(trim(restoration_evidence_note)) between 1 and 1000
  ),
  purge_started_at timestamptz,
  purge_operation_id uuid references public.organization_deletion_receipts(operation_id),
  created_at timestamptz not null default now(),
  constraint organization_closure_records_deadline_after_start_check check (deadline_at > started_at),
  constraint organization_closure_records_restored_fields_check check (
    (status = 'restored') = (
      restored_at is not null and restored_by_owner_email is not null
      and restoration_evidence_note is not null
    )
  ),
  constraint organization_closure_records_purge_fields_check check (
    (status in ('purge_in_progress', 'purged')) = (purge_started_at is not null)
  )
);

create unique index organization_closure_records_one_open_idx
  on public.organization_closure_records (organization_id)
  where status in ('pending_closure', 'purge_in_progress');

create index organization_closure_records_history_idx
  on public.organization_closure_records (organization_id, started_at desc);

create index organization_closure_records_due_idx
  on public.organization_closure_records (deadline_at)
  where status = 'pending_closure';

create table public.organization_closure_notices (
  id uuid primary key default gen_random_uuid(),
  closure_record_id uuid not null references public.organization_closure_records(id) on delete cascade,
  notice_kind text not null check (
    notice_kind in ('closure_started', 'fourteen_day_reminder', 'three_day_reminder', 'closure_completed')
  ),
  sent_at timestamptz not null default now(),
  outbox_delivery_id uuid references public.platform_outbox_deliveries(id),
  created_at timestamptz not null default now(),
  unique (closure_record_id, notice_kind)
);

-- ---------------------------------------------------------------------------
-- Row level security and privileges -- owner-private, no contractor access at all
-- ---------------------------------------------------------------------------

alter table public.organization_closure_records enable row level security;
alter table public.organization_closure_notices enable row level security;
alter table public.organization_deletion_receipts enable row level security;

revoke all on public.organization_closure_records from anon, authenticated;
revoke all on public.organization_closure_notices from anon, authenticated;
revoke all on public.organization_deletion_receipts from anon, authenticated;

grant select, insert, update on public.organization_closure_records to service_role;
grant select, insert on public.organization_closure_notices to service_role;
grant select, insert, update on public.organization_deletion_receipts to service_role;
