-- Onboarding & Data Portability, Part 1: client import foundation (schema only).
--
-- Two user-facing tables behind the approved 4-screen flow (Upload -> Map -> Review -> Done):
--
--   * public.import_batches -- one row per uploaded file: where the file lives (R2), the chosen column
--     mapping, the match action, the consent affirmation, and the running per-outcome counts the Review and
--     Done screens display.
--   * public.import_rows    -- one row per data row in the file: the original cells, the decision the Review
--     dry-run computed for it, the concrete payload to write, and (after the worker runs) its result.
--
-- Both are in `public` with org-scoped RLS SELECT so the screens read them directly (keyset-paginated, like
-- the clients list) -- a 5,000-row Review is too much to funnel through an RPC. There is NO insert/update/
-- delete policy: every write happens inside a SECURITY DEFINER /api RPC (upload/map/review/commit) or the
-- service-role worker, never straight from the browser -- rule 12.
--
-- The claim RPC (public.process_next_import_row) and its pg_cron wake are deliberately NOT in this migration.
-- The row the worker executes is fully described by import_rows.resolved_payload, whose exact shape the Review
-- step fixes; writing the ~300-line create/update body before that contract is locked would be guesswork. This
-- migration locks the contract (documented below + enforced by the constraints) so the later worker migration
-- has a fixed target -- the same table-then-processor split the forms feature used (Part 4C table, 4D worker).
--
-- No customer-facing side effects, ever: the worker will create clients through the same client ->
-- client_contact_methods -> properties insert sequence public.create_client uses, and client creation emits
-- none of the events the automation/communications/review/dunning engines listen to (those fire on quotes and
-- invoices). We inline that sequence rather than call create_client for the identical reason the forms worker
-- does: create_client is `security invoker`, granted only to `authenticated`, and leans on RLS + auth.uid();
-- the worker runs as service_role with no logged-in user.

-- ---------------------------------------------------------------------------------------------------------
-- 1. import_batches -- one per uploaded file
-- ---------------------------------------------------------------------------------------------------------

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Part 1 imports clients; Part 3 will reuse this whole pipeline for the price book, so the entity is named
  -- rather than assumed.
  entity_type text not null default 'client' check (entity_type in ('client')),
  created_by uuid references auth.users(id) on delete set null,

  source_filename text not null check (char_length(source_filename) between 1 and 260),
  -- The uploaded file in R2. Kept after the run so a completed import stays auditable and re-downloadable.
  storage_object_key text not null check (char_length(storage_object_key) between 1 and 512),
  -- Data rows parsed out of the file (header row excluded). Null until the file is parsed at upload time.
  file_row_count integer check (file_row_count is null or file_row_count >= 0),

  -- What to do with a row that matches an existing client. 'skip' leaves the existing client untouched;
  -- 'update' writes the mapped fields onto it, honoring the per-field "don't overwrite" toggles in
  -- column_mapping. A match is NEVER imported as a second client -- the hard email/phone unique index forbids
  -- it and so do our dedupe rules.
  match_action text not null default 'skip' check (match_action in ('skip', 'update')),

  -- file column header -> { "field": "<our field>", "dont_overwrite": <bool> }. Empty until the Map step.
  column_mapping jsonb not null default '{}'::jsonb,

  status text not null default 'uploaded'
    check (status in ('uploaded', 'mapped', 'reviewed', 'importing', 'completed', 'failed', 'canceled')),

  -- HubSpot's consent gate, mirrored: the office affirms these contacts expect to hear from them before the
  -- import can be committed. Null until affirmed; the commit RPC will refuse without it.
  consent_affirmed_at timestamptz,

  -- Per-outcome tallies the worker maintains as it drains, so the Done screen needs no aggregate query.
  created_count integer not null default 0 check (created_count >= 0),
  updated_count integer not null default 0 check (updated_count >= 0),
  skipped_count integer not null default 0 check (skipped_count >= 0),
  held_count integer not null default 0 check (held_count >= 0),
  error_count integer not null default 0 check (error_count >= 0),

  -- The generated per-row error file (R2), offered on the Done screen. Null until a run produces errors.
  error_file_object_key text check (error_file_object_key is null or char_length(error_file_object_key) <= 512),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Lets import_rows carry a composite FK that pins a row to a batch in the same organization.
  constraint import_batches_org_id_unique unique (organization_id, id)
);

comment on table public.import_batches is
  'One uploaded import file: its R2 location, column mapping, match action, consent affirmation, and running '
  'per-outcome counts. Read directly by the import screens (RLS); written only by the import /api RPCs and the '
  'service-role worker.';

create index import_batches_org_created_idx on public.import_batches (organization_id, created_at desc);

create trigger import_batches_set_updated_at
before update on public.import_batches
for each row execute function public.set_updated_at();

alter table public.import_batches enable row level security;

create policy "members can view import batches"
on public.import_batches for select to authenticated
using (private.is_organization_member(organization_id));

-- ---------------------------------------------------------------------------------------------------------
-- 2. import_rows -- one per data row in the file
-- ---------------------------------------------------------------------------------------------------------

create table public.import_rows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  batch_id uuid not null,

  -- 1-based position of this row in the file (header excluded). With batch_id this is the idempotency/retry
  -- key: a re-run or a mid-batch crash can never create the same source row twice.
  source_row_number integer not null check (source_row_number >= 1),

  -- The original cells for this row, keyed by the file's column headers -- kept verbatim so the Review screen
  -- can show exactly what was in the file and the error file can echo it back.
  raw jsonb not null,

  -- What the Review dry-run decided for this row:
  --   create -> new client; execute the insert sequence from resolved_payload.
  --   update -> matched an existing client (match_client_id); apply resolved_payload's fields to it.
  --   skip   -> matched an existing client and match_action is 'skip'; nothing is written.
  --   hold   -> matched client A on email but client B on phone (a conflict); never guessed, needs a human.
  --   error  -> the row itself is invalid (failed Zod validation); nothing is written.
  planned_action text not null default 'create'
    check (planned_action in ('create', 'update', 'skip', 'hold', 'error')),

  -- The concrete, validated payload the worker writes. Fixed contract (documented on the column). Null for
  -- skip/hold/error rows, which the worker never touches.
  resolved_payload jsonb,

  -- The existing client this row matched, for update/skip/hold. Null for create/error.
  match_client_id uuid,
  -- Why it matched or was held, for row-level explainability on the Review and error outputs
  -- (e.g. 'email', 'phone', 'email_phone_conflict').
  match_reason text check (match_reason is null or char_length(match_reason) <= 80),
  -- Non-blocking notes carried onto the Review row, e.g. 'phone_shared_in_file' (a later row that lost a
  -- shared phone to an earlier one) or 'no_contact_method'.
  flags text[] not null default '{}',

  status text not null default 'pending_review'
    check (status in ('pending_review', 'ready', 'imported', 'skipped', 'held', 'failed')),
  error_message text,

  -- The client this row created (create) or updated (update), once the worker has run.
  result_client_id uuid,
  processed_at timestamptz,
  created_at timestamptz not null default now(),

  constraint import_rows_batch_fk foreign key (organization_id, batch_id)
    references public.import_batches (organization_id, id) on delete cascade,
  -- One row per {batch, source row number} ever -- the idempotency guarantee.
  constraint import_rows_source_unique unique (batch_id, source_row_number)
);

comment on table public.import_rows is
  'One data row from an import file: original cells, the Review dry-run decision, the concrete payload to '
  'write, and the per-row result. Read directly by the import screens (RLS); written only by the import /api '
  'RPCs and the service-role worker.';

comment on column public.import_rows.resolved_payload is
  'Fixed worker contract. planned_action=create: '
  '{ "client": { client_type, first_name, last_name, company_name, display_name, lifecycle_status, '
  'lead_source }, "email": text|null, "phone": text|null, "property": { label, address_line1, address_line2, '
  'city, state_region, postal_code, country }|null }. planned_action=update: the same shape but carrying ONLY '
  'the fields to change (the Review step drops any field whose "don''t overwrite" toggle is on and whose '
  'target already has a value); match_client_id names the client to update. Null for skip/hold/error rows.';

-- The worker's claim walks ready rows oldest-first; leading the partial index on exactly the claim's ORDER BY
-- keeps it a plain index walk with no sort (the lesson from form_submissions_claim_index_created_at). This is
-- the standard competing-consumer queue claim: `... where status='ready' order by created_at, source_row_number
-- for update skip locked limit 1`.
create index import_rows_ready_idx on public.import_rows (created_at, source_row_number)
  where status = 'ready';

-- Batch-scoped reads for the Review and Done screens (all rows of one batch, in file order) are served by the
-- leading columns of the import_rows_source_unique index (batch_id, source_row_number); no separate index.

alter table public.import_rows enable row level security;

create policy "members can view import rows"
on public.import_rows for select to authenticated
using (private.is_organization_member(organization_id));
