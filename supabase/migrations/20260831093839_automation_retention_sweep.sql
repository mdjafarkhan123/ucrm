-- Contractor Settings Part 6E-1: Automation retention -- fixed durations + one nightly batched cleanup.
--
-- docs/automation-behavior-contract.md § Retention and cleanup. 6E-1 is the engine half: the durations are
-- constants here (the owner-facing preset/shortening surface is 6E-2, deferred with 6D-6). One pg_cron job
-- runs a pure-SQL sweep that deletes aged rows in small id-ordered batches under a statement timeout, and is
-- inherently restartable -- each run just re-scans "older than the cutoff" and continues where the last left
-- off, no cursor.
--
-- Industry pattern (GHL, HubSpot, Jobber, ActiveCampaign): the re-enrollment guard lives with the subject
-- record, never on an independent timer. So a terminal enrollment is COMPACTED, not deleted -- its personal
-- context is stripped but the (recipe_id, re_entry_key) tombstone stays, keeping the permanent "same quote
-- version to the same recipient never restarts a sequence" rule intact. The tombstone goes only when the
-- organization is purged (existing cascade).
--
-- Retention clocks (approved by Jafar 2026-08-31):
--   processed events + their match rows ....... 180 days   (matches cascade with the event)
--   settled work items (done / cancelled) ..... 90 days
--   terminal enrollments -> tombstone ......... 180 days   (tombstone then lives for the org's lifetime)
--   idempotency command receipts ............. 30 days
-- Out of scope: automation_worker_wake_ledger (already self-prunes to 7d), automation_authority_events
-- (audit -- kept), automation_recipe_versions (immutable definitions -- kept).
--
-- Cadence and batch ceiling are deliberately conservative and are the knobs 6E-2 tunes once 6D-6's isolated
-- environment gives real storage and drain evidence. Nothing here is time-critical: a backlog just drains
-- over the following nights.

-- ---------------------------------------------------------------------------------------------------
-- 1. Compaction marker + a relaxed evidence rule for compacted rows.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_enrollments
  add column compacted_at timestamptz;

comment on column private.automation_enrollments.compacted_at is
  'Set when retention stripped this terminal enrollment to a tombstone: context, enrolled_by, and '
  'trigger_event_id are cleared, but recipe_id + re_entry_key stay so re-enrollment is still blocked. '
  'Null for every live or un-compacted enrollment.';

-- The source/evidence check (an event-sourced enrollment must carry its trigger event) no longer applies
-- once the row is a tombstone -- compaction deliberately severs that link before the event is deleted.
alter table private.automation_enrollments
  drop constraint automation_enrollments_source_evidence_ck;
alter table private.automation_enrollments
  add constraint automation_enrollments_source_evidence_ck check (
    compacted_at is not null
    or ((source = 'event') = (trigger_event_id is not null))
  );

-- ---------------------------------------------------------------------------------------------------
-- 2. Selection indexes -- one per delete, each keyed exactly on its predicate + (clock, id) order.
-- ---------------------------------------------------------------------------------------------------
-- Partial so each stays the size of the deletable backlog, not the table. Every row ends up processed, so
-- the events predicate only excludes the tiny pending set.
create index automation_events_retention_idx
  on private.automation_events (processed_at, id)
  where processed_at is not null;

create index automation_work_items_retention_idx
  on private.automation_work_items (updated_at, id)
  where state in ('done', 'cancelled');

create index automation_enrollments_retention_idx
  on private.automation_enrollments (updated_at, id)
  where state in ('completed', 'stopped', 'failed') and compacted_at is null;

-- The draft-receipt table already has (created_at, id); the enrollment-receipt table was created without it.
create index automation_enrollment_command_receipts_age_idx
  on public.automation_enrollment_command_receipts (created_at, id);

-- Defence in depth: this public table only ever gets written through SECURITY DEFINER commands, but it was
-- created without RLS. Enable it with no policy so a direct anon/authenticated path stays denied.
alter table public.automation_enrollment_command_receipts enable row level security;

-- ---------------------------------------------------------------------------------------------------
-- 3. Run ledger -- one row per sweep, for health and debugging. No personal data.
-- ---------------------------------------------------------------------------------------------------
create table private.automation_retention_runs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  work_items_deleted integer not null default 0,
  enrollments_compacted integer not null default 0,
  events_deleted integer not null default 0,
  event_matches_deleted integer not null default 0,
  draft_receipts_deleted integer not null default 0,
  enrollment_receipts_deleted integer not null default 0,
  -- True when a category still had a full batch waiting when its per-run cap was hit: the next run clears it.
  hit_cap boolean not null default false
);

comment on table private.automation_retention_runs is
  'One row per automation retention sweep: what each category deleted and whether the run hit its batch cap. '
  'Bounded by the nightly cadence; not itself swept.';

create index automation_retention_runs_started_idx
  on private.automation_retention_runs (started_at desc);

revoke all on table private.automation_retention_runs from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 4. The sweep.
-- ---------------------------------------------------------------------------------------------------
create function private.automation_retention_sweep(
  p_batch integer default 2000,
  p_max_batches integer default 25
)
returns private.automation_retention_runs
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  -- Retention windows in days. 6E-2 will resolve these per organization from a policy row; until then they
  -- are the single platform default.
  c_events_days constant integer := 180;
  c_work_days constant integer := 90;
  c_enrollment_days constant integer := 180;
  c_receipt_days constant integer := 30;

  v_now timestamptz := now();
  v_run_id uuid;
  v_result private.automation_retention_runs;
  v_deleted integer;
  v_compacted integer;
  v_matches integer;
  v_loops integer;
  v_last_full boolean;

  v_wi integer := 0;
  v_en integer := 0;
  v_ev integer := 0;
  v_em integer := 0;
  v_dr integer := 0;
  v_er integer := 0;
  v_hit_cap boolean := false;
begin
  if p_batch < 1 or p_batch > 10000 then
    raise exception 'The retention batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_max_batches < 1 or p_max_batches > 500 then
    raise exception 'The retention batch cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  -- Bound the whole sweep. Each DELETE is an index range, but the ceiling protects the nightly window if a
  -- backlog is unexpectedly large.
  set local statement_timeout = '10min';
  set local lock_timeout = '5s';

  insert into private.automation_retention_runs default values returning id into v_run_id;

  -- (a) Settled work items past their window. needs_attention rows are NOT touched here: an open one under a
  --     live enrollment is a real problem; one under a terminal enrollment is cleared in step (b).
  v_loops := 0;
  loop
    delete from private.automation_work_items w
    using (
      select id
      from private.automation_work_items
      where state in ('done', 'cancelled')
        and updated_at < v_now - make_interval(days => c_work_days)
      order by updated_at, id
      limit p_batch
      for update skip locked
    ) d
    where w.id = d.id;
    get diagnostics v_deleted = row_count;
    v_wi := v_wi + v_deleted;
    v_loops := v_loops + 1;
    v_last_full := v_deleted >= p_batch;
    exit when not v_last_full or v_loops >= p_max_batches;
  end loop;
  v_hit_cap := v_hit_cap or (v_last_full and v_loops >= p_max_batches);

  -- (b) Terminal enrollments past their window -> tombstone. The permanent no-restart tombstone keeps
  --     recipe_id + re_entry_key + state + timestamps; context and the person/link columns are cleared, and
  --     trigger_event_id is severed so step (c) can delete the event. Any leftover work items for the
  --     enrollment (a stuck needs_attention, say) go too -- the enrollment is terminal, nothing will act.
  v_loops := 0;
  loop
    with victims as (
      select id
      from private.automation_enrollments
      where state in ('completed', 'stopped', 'failed')
        and compacted_at is null
        and updated_at < v_now - make_interval(days => c_enrollment_days)
      order by updated_at, id
      limit p_batch
      for update skip locked
    ),
    wiped_items as (
      delete from private.automation_work_items w
      using victims
      where w.enrollment_id = victims.id
      returning 1
    ),
    compacted as (
      update private.automation_enrollments e
      set context = '{}'::jsonb,
        enrolled_by = null,
        paused_work_due_at = null,
        trigger_event_id = null,
        compacted_at = v_now
      from victims
      where e.id = victims.id
      returning 1
    )
    select (select count(*) from compacted), (select count(*) from wiped_items)
    into v_compacted, v_deleted;
    v_en := v_en + v_compacted;
    v_wi := v_wi + v_deleted;
    v_loops := v_loops + 1;
    v_last_full := v_compacted >= p_batch;
    exit when not v_last_full or v_loops >= p_max_batches;
  end loop;
  v_hit_cap := v_hit_cap or (v_last_full and v_loops >= p_max_batches);

  -- (c) Processed events past their window whose trigger no enrollment still references. A long-running
  --     enrollment (not yet terminal, so not yet compacted) keeps its event alive -- correct: that is live
  --     evidence. automation_event_matches rows cascade with the event.
  v_loops := 0;
  loop
    with victims as (
      select ev.id
      from private.automation_events ev
      where ev.processed_at is not null
        and ev.processed_at < v_now - make_interval(days => c_events_days)
        and not exists (
          select 1 from private.automation_enrollments en where en.trigger_event_id = ev.id
        )
      order by ev.processed_at, ev.id
      limit p_batch
      for update skip locked
    ),
    counted_matches as (
      select count(*)::integer as n
      from private.automation_event_matches m
      where m.event_id in (select id from victims)
    ),
    deleted_events as (
      delete from private.automation_events e
      using victims
      where e.id = victims.id
      returning 1
    )
    select (select count(*) from deleted_events), (select n from counted_matches)
    into v_deleted, v_matches;
    v_ev := v_ev + v_deleted;
    v_em := v_em + v_matches;
    v_loops := v_loops + 1;
    v_last_full := v_deleted >= p_batch;
    exit when not v_last_full or v_loops >= p_max_batches;
  end loop;
  v_hit_cap := v_hit_cap or (v_last_full and v_loops >= p_max_batches);

  -- (d) Idempotency receipts past their window. A retry never arrives 30 days late.
  v_loops := 0;
  loop
    delete from public.automation_draft_command_receipts r
    using (
      select id from public.automation_draft_command_receipts
      where created_at < v_now - make_interval(days => c_receipt_days)
      order by created_at, id
      limit p_batch
      for update skip locked
    ) d
    where r.id = d.id;
    get diagnostics v_deleted = row_count;
    v_dr := v_dr + v_deleted;
    v_loops := v_loops + 1;
    v_last_full := v_deleted >= p_batch;
    exit when not v_last_full or v_loops >= p_max_batches;
  end loop;
  v_hit_cap := v_hit_cap or (v_last_full and v_loops >= p_max_batches);

  v_loops := 0;
  loop
    delete from public.automation_enrollment_command_receipts r
    using (
      select id from public.automation_enrollment_command_receipts
      where created_at < v_now - make_interval(days => c_receipt_days)
      order by created_at, id
      limit p_batch
      for update skip locked
    ) d
    where r.id = d.id;
    get diagnostics v_deleted = row_count;
    v_er := v_er + v_deleted;
    v_loops := v_loops + 1;
    v_last_full := v_deleted >= p_batch;
    exit when not v_last_full or v_loops >= p_max_batches;
  end loop;
  v_hit_cap := v_hit_cap or (v_last_full and v_loops >= p_max_batches);

  update private.automation_retention_runs
  set finished_at = now(),
    work_items_deleted = v_wi,
    enrollments_compacted = v_en,
    events_deleted = v_ev,
    event_matches_deleted = v_em,
    draft_receipts_deleted = v_dr,
    enrollment_receipts_deleted = v_er,
    hit_cap = v_hit_cap
  where id = v_run_id;

  select * into v_result from private.automation_retention_runs where id = v_run_id;
  return v_result;
end;
$$;

comment on function private.automation_retention_sweep(integer, integer) is
  'Deletes aged automation rows in id-ordered batches: settled work items (90d), processed events + matches '
  '(180d), terminal enrollments compacted to no-restart tombstones (180d), and idempotency receipts (30d). '
  'Restartable, bounded, and safe to re-run. Internal.';

revoke all on function private.automation_retention_sweep(integer, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 5. Nightly schedule. Pure SQL, so pg_cron invokes it directly (the pattern the Communications callback
--    processor already uses). 03:17 UTC -- off the top of the hour, in the quiet window.
-- ---------------------------------------------------------------------------------------------------
create extension if not exists pg_cron;

select cron.schedule(
  'automation-retention-nightly',
  '17 3 * * *',
  $cron$ select private.automation_retention_sweep(); $cron$
);
