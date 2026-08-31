-- Automation Part 6D-1: the durable event spine -- events, enrollments, and due work.
--
-- Pattern: transactional outbox + idempotent receiver, the same shape Communications already runs for
-- provider callbacks. A domain fact and its event commit together; a separate bounded drain (next migration)
-- consumes them. Nothing here sends anything.
--
-- EVERYTHING LIVES IN `private`. Raw events, payloads, enrollment context, and work state are internal
-- machinery: the `private` schema has no grants to anon/authenticated and is not exposed through PostgREST,
-- so a contractor can never read them directly. Contractor-facing history (6D-4) and record controls (6D-5)
-- will expose deliberate, safe projections through security-definer read functions instead.
--
-- Deliberately NOT built here (6D-2 owns it): claim/lease columns, worker route, cron wake, retries,
-- dead-letter, Needs attention. Work items carry only what 6D-1 must persist.

-- ---------------------------------------------------------------------------------------------------
-- 1. Events: immutable statements that a domain fact occurred.
-- ---------------------------------------------------------------------------------------------------
create table private.automation_events (
  id uuid primary key default gen_random_uuid(),
  -- Insertion order. Used for drain order and as the human-readable activation marker.
  seq bigint generated always as identity not null,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_type text not null check (event_type in ('quote.delivery_succeeded')),
  payload_schema_version integer not null default 1 check (payload_schema_version >= 1),
  subject_type text not null check (subject_type in ('quote')),
  subject_id uuid not null,
  -- Identifiers and trigger evidence only. Never a customer snapshot, message body, or authorization
  -- decision -- intake re-resolves current truth from the owning domain.
  payload jsonb not null,
  occurred_at timestamptz not null,
  source_module text not null check (source_module in ('communications')),
  -- Stable identity of the fact in the source module. For quote delivery this is the delivery intent id,
  -- so however many differently-keyed provider callbacks arrive for that intent, they collapse to one event.
  source_event_id uuid not null,
  -- The transaction that wrote this row. Activation compares against a stored snapshot instead of a clock
  -- or a max(seq), which is what makes the cutoff correct when a delivery and an activation race.
  created_xid xid8 not null default pg_current_xact_id(),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_attempts integer not null default 0 check (processing_attempts >= 0),
  processing_error text,
  constraint automation_events_seq_key unique (seq),
  constraint automation_events_source_key unique (source_module, source_event_id, event_type)
);

comment on table private.automation_events is
  'Durable domain events for Automation, written in the same transaction as the fact that caused them. '
  'Internal: no contractor read path. See docs/automation-behavior-contract.md § Events and transaction ownership.';

-- The drain: pending rows in insertion order. Partial, so the index stays the size of the backlog rather
-- than the size of history.
create index automation_events_pending_idx
  on private.automation_events (seq) where processed_at is null;
-- Leading organization_id covers the organizations -> events cascade and per-tenant inspection.
create index automation_events_organization_idx
  on private.automation_events (organization_id, seq desc);

-- ---------------------------------------------------------------------------------------------------
-- 2. Enrollments: one subject running one frozen recipe version.
-- ---------------------------------------------------------------------------------------------------
create table private.automation_enrollments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  recipe_id uuid not null,
  recipe_version_id uuid not null,
  subject_type text not null check (subject_type in ('quote')),
  subject_id uuid not null,
  -- RESTRICT on purpose: an enrollment must never outlive the evidence of why it started. Retention (6E)
  -- deletes enrollments before their events, never the other way round.
  trigger_event_id uuid not null references private.automation_events(id) on delete restrict,
  source text not null default 'event' check (source in ('event', 'manual')),
  state text not null default 'active'
    check (state in ('active', 'paused', 'completed', 'stopped', 'failed')),
  current_step_index integer not null default 0 check (current_step_index >= 0),
  -- Why this subject may not enroll again. For quote follow-up: quote version + quote recipient.
  re_entry_key text not null check (char_length(re_entry_key) between 1 and 200),
  -- Frozen send-time identity carried from the event; current truth is always re-read, never taken here.
  context jsonb not null,
  customer_messages_sent integer not null default 0 check (customer_messages_sent >= 0),
  -- Null when the organization's maximum enrollment duration is unlimited or unset.
  expires_at timestamptz,
  stop_reason text,
  stopped_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- The pinned version must belong to this recipe AND this organization (composite unique on the versions
  -- table); a cross-tenant or cross-recipe pin is impossible.
  constraint automation_enrollments_version_fkey
    foreign key (recipe_version_id, recipe_id, organization_id)
    references public.automation_recipe_versions(id, recipe_id, organization_id) on delete restrict,
  -- Automatic enrollment identity (contract: recipe version + trigger event + subject).
  constraint automation_enrollments_trigger_key unique (recipe_version_id, trigger_event_id, subject_id),
  -- The permanent no-restart rule Jafar approved: the same quote version delivered again to the same
  -- recipient never starts a second reminder sequence for this recipe.
  constraint automation_enrollments_re_entry_key unique (recipe_id, re_entry_key)
);

comment on table private.automation_enrollments is
  'One subject executing one frozen recipe version. Pinned to its version and to send-time identity; all '
  'consent, status, and recipient truth is re-read from the owning domain before any effect.';

-- Record-scoped read for the Quote detail card (6D-5) and history (6D-4).
create index automation_enrollments_subject_idx
  on private.automation_enrollments (organization_id, subject_type, subject_id, updated_at desc, id desc);
-- FK index accounting: (recipe_version_id, recipe_id, organization_id) is covered by the trigger unique's
-- leading recipe_version_id; recipe_id is covered by the re-entry unique; organization_id by the subject
-- index; trigger_event_id gets its own index below because event retention checks it.
create index automation_enrollments_trigger_event_idx
  on private.automation_enrollments (trigger_event_id);

create trigger automation_enrollments_set_updated_at
before update on private.automation_enrollments
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------------
-- 3. Match outcomes: why each active recipe did or did not enroll for an event.
-- ---------------------------------------------------------------------------------------------------
create table private.automation_event_matches (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references private.automation_events(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  recipe_id uuid not null,
  recipe_version_id uuid,
  outcome text not null check (outcome in (
    'enrolled', 'already_enrolled', 'before_activation', 'not_entitled', 'authority_blocked',
    'subject_gone', 'condition_failed', 'condition_unavailable'
  )),
  enrollment_id uuid references private.automation_enrollments(id) on delete set null,
  detail text,
  created_at timestamptz not null default now(),
  constraint automation_event_matches_event_recipe_key unique (event_id, recipe_id)
);

comment on table private.automation_event_matches is
  'One row per (event, active recipe): enrolled, or the plain reason it did not. This is what answers '
  '"why did my automation not run" in 6D-4 history.';

create index automation_event_matches_organization_idx
  on private.automation_event_matches (organization_id, created_at desc, id desc);
create index automation_event_matches_enrollment_idx
  on private.automation_event_matches (enrollment_id) where enrollment_id is not null;

-- ---------------------------------------------------------------------------------------------------
-- 4. Due work: the next transition for an enrollment. One row at a time, never a pre-expanded sequence.
-- ---------------------------------------------------------------------------------------------------
create table private.automation_work_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  enrollment_id uuid not null references private.automation_enrollments(id) on delete cascade,
  step_index integer not null check (step_index >= 0),
  due_at timestamptz not null,
  state text not null default 'pending' check (state in ('pending', 'done', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- At most one work item per step of an enrollment.
  constraint automation_work_items_step_key unique (enrollment_id, step_index)
);

comment on table private.automation_work_items is
  'The single next due transition per enrollment. 6D-2 adds claim leases, attempts, and recovery columns; '
  '6D-1 only creates the first row.';

-- The claim shape 6D-2 will use: due first, tenant, unique tie-breaker. Partial so it tracks the backlog,
-- not history.
create index automation_work_items_due_idx
  on private.automation_work_items (due_at, organization_id, id) where state = 'pending';

create trigger automation_work_items_set_updated_at
before update on private.automation_work_items
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------------------------------
-- 5. Activation cutoff that survives a race.
-- ---------------------------------------------------------------------------------------------------
-- max(seq) alone is wrong: sequence numbers are handed out at INSERT, but rows become visible at COMMIT, so
-- a delivery that took its number before an activation can commit after it (and vice versa). The snapshot
-- answers the only question that matters -- "was this delivery already a committed fact when the contractor
-- activated?" -- using Postgres's own visibility rules. activation_cutoff_sequence stays as a readable
-- marker for history and debugging; the snapshot is the authority.
alter table public.automation_recipe_versions
  add column activation_cutoff_snapshot pg_snapshot;

comment on column public.automation_recipe_versions.activation_cutoff_snapshot is
  'Commit-visibility snapshot taken at activation. An event whose transaction is NOT visible in it counts '
  'as later than activation. Authoritative; activation_cutoff_sequence is only a readable marker.';

-- Versions frozen before the engine existed carry neither a snapshot nor a marker. They are NOT backfilled:
-- activated versions are immutable by trigger, and there is nothing to correct -- no automation event
-- existed before this migration, so intake's `coalesce(activation_cutoff_sequence, 0)` fallback already
-- treats every event as later than those activations, which is exactly right.

-- Live trigger matching for intake: active recipes of one organization for one trigger key.
create index automation_recipes_active_trigger_idx
  on public.automation_recipes (organization_id, active_trigger_key, id)
  where status = 'active';

-- ---------------------------------------------------------------------------------------------------
-- 6. Emission seam. Called from inside the transaction that establishes the domain fact.
-- ---------------------------------------------------------------------------------------------------
create function private.emit_automation_event(
  p_organization_id uuid,
  p_event_type text,
  p_subject_type text,
  p_subject_id uuid,
  p_payload jsonb,
  p_occurred_at timestamptz,
  p_source_module text,
  p_source_event_id uuid
)
returns uuid
language sql
security definer
set search_path = pg_catalog, public, private
as $$
  insert into private.automation_events (
    organization_id, event_type, subject_type, subject_id, payload, occurred_at,
    source_module, source_event_id
  )
  values (
    p_organization_id, p_event_type, p_subject_type, p_subject_id, p_payload,
    coalesce(p_occurred_at, now()), p_source_module, p_source_event_id
  )
  on conflict (source_module, source_event_id, event_type) do nothing
  returning id;
$$;

comment on function private.emit_automation_event(uuid, text, text, uuid, jsonb, timestamptz, text, uuid) is
  'Records one domain event for Automation. Duplicate source facts collapse silently at the source unique '
  'key, so a replayed provider callback can never create a second event.';

revoke all on function private.emit_automation_event(uuid, text, text, uuid, jsonb, timestamptz, text, uuid)
  from public, anon, authenticated;
