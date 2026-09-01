-- Automation Part 6E-1: retention sweep. Aged rows age out in bounded batches; live work, the audit trail,
-- and the permanent no-restart guard are never touched; the sweep is restartable and safe to re-run.
--
-- The sweep is a platform-wide job, and this runs against a shared remote, so assertions on its return
-- counts use >= and every "did the right row go / stay" check is scoped to this test's own fixtures.

begin;

create extension if not exists pgtap with schema extensions;
select plan(34);

select ok(
  not has_function_privilege('anon', 'private.automation_retention_sweep(integer, integer)', 'EXECUTE'),
  'anon cannot run the retention sweep');
select ok(
  not has_function_privilege('authenticated', 'private.automation_retention_sweep(integer, integer)', 'EXECUTE'),
  'authenticated cannot run the retention sweep');

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: one org, one active recipe + version.
-- ---------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status)
values ('6e100000-0000-0000-0000-000000000001', 'Automation 6E-1', 'automation-6e1', 'active');

set local role postgres;

insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('6e1a0000-0000-0000-0000-000000000001', '6e100000-0000-0000-0000-000000000001',
  'Quote follow-up', 'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.delay","config":{"amount":2,"unit":"days"}}],"stops":[]}'::jsonb);

insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot)
values ('6e1b0000-0000-0000-0000-000000000001', '6e1a0000-0000-0000-0000-000000000001',
  '6e100000-0000-0000-0000-000000000001', 1, 1,
  (select draft_definition from public.automation_recipes where id = '6e1a0000-0000-0000-0000-000000000001'),
  'hash-6e1', 'quote.delivery_succeeded', 0, pg_current_snapshot());

update public.automation_recipes
set status = 'active', current_version_id = '6e1b0000-0000-0000-0000-000000000001',
  active_trigger_key = 'quote.delivery_succeeded'
where id = '6e1a0000-0000-0000-0000-000000000001';

create function pg_temp.org() returns uuid language sql immutable as $$select '6e100000-0000-0000-0000-000000000001'::uuid$$;
create function pg_temp.rec() returns uuid language sql immutable as $$select '6e1a0000-0000-0000-0000-000000000001'::uuid$$;
create function pg_temp.ver() returns uuid language sql immutable as $$select '6e1b0000-0000-0000-0000-000000000001'::uuid$$;

create function pg_temp.mk_event(p_id uuid, p_age interval, p_processed boolean) returns void
language sql as $$
  insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
    occurred_at, source_module, source_event_id, created_at, processed_at)
  values (p_id, pg_temp.org(), 'quote.delivery_succeeded', 'quote', gen_random_uuid(), '{}'::jsonb,
    now() - p_age, 'communications', gen_random_uuid(), now() - p_age,
    case when p_processed then now() - p_age end);
$$;

create function pg_temp.mk_enr(p_id uuid, p_age interval, p_state text, p_key text, p_event uuid)
returns void language sql as $$
  insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
    subject_id, trigger_event_id, source, state, re_entry_key, context, created_at, updated_at,
    completed_at, stopped_at)
  values (p_id, pg_temp.org(), pg_temp.rec(), pg_temp.ver(), 'quote', gen_random_uuid(), p_event,
    case when p_event is null then 'manual' else 'event' end,
    p_state, p_key, '{"customer_name":"Real Person"}'::jsonb, now() - p_age, now() - p_age,
    case when p_state = 'completed' then now() - p_age end,
    case when p_state in ('stopped','failed') then now() - p_age end);
$$;

-- ================================================================================================
-- Work items: settled rows past 90d go; younger and non-settled stay.
-- ================================================================================================
select pg_temp.mk_enr('6e1e0000-0000-0000-0000-0000000000a1', interval '10 days', 'active', 'k-live', null);
insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, source, state, re_entry_key, context)
values ('6e1e0000-0000-0000-0000-0000000000a2', pg_temp.org(), pg_temp.rec(), pg_temp.ver(), 'quote',
  gen_random_uuid(), 'manual', 'active', 'k-live-2', '{}'::jsonb);

insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at, state, updated_at)
values
  ('6e1c0000-0000-0000-0000-0000000000d1', pg_temp.org(), '6e1e0000-0000-0000-0000-0000000000a1', 0,
   now() - interval '95 days', 'done', now() - interval '95 days'),
  ('6e1c0000-0000-0000-0000-0000000000d2', pg_temp.org(), '6e1e0000-0000-0000-0000-0000000000a1', 1,
   now() - interval '95 days', 'cancelled', now() - interval '95 days'),
  ('6e1c0000-0000-0000-0000-0000000000d3', pg_temp.org(), '6e1e0000-0000-0000-0000-0000000000a1', 2,
   now() - interval '80 days', 'done', now() - interval '80 days'),
  ('6e1c0000-0000-0000-0000-0000000000d4', pg_temp.org(), '6e1e0000-0000-0000-0000-0000000000a1', 3,
   now() - interval '300 days', 'pending', now() - interval '300 days');
insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at, state,
  updated_at, attention_reason, attention_at)
values ('6e1c0000-0000-0000-0000-0000000000d5', pg_temp.org(), '6e1e0000-0000-0000-0000-0000000000a2', 0,
   now() - interval '300 days', 'needs_attention', now() - interval '300 days', 'action_not_available',
   now() - interval '300 days');

select ok((select work_items_deleted from private.automation_retention_sweep()) >= 2,
  'sweep reports deleting the settled work items past 90d');
select ok(not exists (select 1 from private.automation_work_items
  where id in ('6e1c0000-0000-0000-0000-0000000000d1', '6e1c0000-0000-0000-0000-0000000000d2')),
  'the aged done and cancelled rows are gone');
select ok(exists (select 1 from private.automation_work_items where id = '6e1c0000-0000-0000-0000-0000000000d3'),
  'a settled row only 80 days old survives');
select ok(exists (select 1 from private.automation_work_items where id = '6e1c0000-0000-0000-0000-0000000000d4'),
  'a 300-day-old pending row is never a retention target');
select ok(exists (select 1 from private.automation_work_items where id = '6e1c0000-0000-0000-0000-0000000000d5'),
  'a 300-day-old needs_attention row under a live enrollment survives');

-- ================================================================================================
-- Terminal enrollments: past 180d -> tombstone; younger / active untouched. No-restart guard survives.
-- ================================================================================================
select pg_temp.mk_event('6e1d0000-0000-0000-0000-0000000000e1', interval '200 days', true);
select pg_temp.mk_enr('6e1e0000-0000-0000-0000-0000000000b1', interval '190 days', 'completed', 'k-old-done',
  '6e1d0000-0000-0000-0000-0000000000e1');
select pg_temp.mk_enr('6e1e0000-0000-0000-0000-0000000000b2', interval '170 days', 'stopped', 'k-recent-stop', null);
select pg_temp.mk_enr('6e1e0000-0000-0000-0000-0000000000b3', interval '400 days', 'active', 'k-old-active', null);
insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at, state,
  updated_at, attention_reason, attention_at)
values ('6e1c0000-0000-0000-0000-0000000000d6', pg_temp.org(), '6e1e0000-0000-0000-0000-0000000000b1', 0,
   now() - interval '190 days', 'needs_attention', now() - interval '190 days', 'action_not_available',
   now() - interval '190 days');

select ok((select enrollments_compacted from private.automation_retention_sweep()) >= 1,
  'sweep compacts the terminal enrollment past 180d');

select is((select context::text from private.automation_enrollments
  where id = '6e1e0000-0000-0000-0000-0000000000b1'), '{}',
  'compaction clears the enrollment context');
select ok((select compacted_at is not null and trigger_event_id is null
  from private.automation_enrollments where id = '6e1e0000-0000-0000-0000-0000000000b1'),
  'compaction stamps compacted_at and severs the trigger event');
select is((select re_entry_key from private.automation_enrollments
  where id = '6e1e0000-0000-0000-0000-0000000000b1'), 'k-old-done',
  'the tombstone keeps its re_entry_key');
select ok(not exists (select 1 from private.automation_work_items where id = '6e1c0000-0000-0000-0000-0000000000d6'),
  'the terminal enrollment''s leftover parked work item is removed with it');

select ok((select compacted_at is null from private.automation_enrollments
  where id = '6e1e0000-0000-0000-0000-0000000000b2'),
  'a terminal enrollment only 170 days old is left intact');
select ok((select compacted_at is null from private.automation_enrollments
  where id = '6e1e0000-0000-0000-0000-0000000000b3'),
  'a 400-day-old still-active enrollment is never compacted');

select throws_ok($q$
  insert into private.automation_enrollments (organization_id, recipe_id, recipe_version_id, subject_type,
    subject_id, source, state, re_entry_key, context)
  values ('6e100000-0000-0000-0000-000000000001', '6e1a0000-0000-0000-0000-000000000001',
    '6e1b0000-0000-0000-0000-000000000001', 'quote', gen_random_uuid(), 'manual', 'active', 'k-old-done',
    '{}'::jsonb) $q$,
  '23505', null, 'the no-restart guard still blocks re-enrollment for a compacted key');

-- ================================================================================================
-- Events: processed + past 180d + unreferenced go (matches cascade); referenced or unprocessed stay.
-- ================================================================================================
select pg_temp.mk_event('6e1d0000-0000-0000-0000-0000000000e2', interval '200 days', true);
select pg_temp.mk_event('6e1d0000-0000-0000-0000-0000000000e3', interval '200 days', true);
select pg_temp.mk_event('6e1d0000-0000-0000-0000-0000000000e4', interval '200 days', false);
select pg_temp.mk_event('6e1d0000-0000-0000-0000-0000000000e5', interval '10 days', true);
select pg_temp.mk_enr('6e1e0000-0000-0000-0000-0000000000c1', interval '150 days', 'active', 'k-ref-active',
  '6e1d0000-0000-0000-0000-0000000000e3');

insert into private.automation_event_matches (event_id, organization_id, recipe_id, outcome)
values
  ('6e1d0000-0000-0000-0000-0000000000e2', pg_temp.org(), pg_temp.rec(), 'condition_failed'),
  ('6e1d0000-0000-0000-0000-0000000000e3', pg_temp.org(), pg_temp.rec(), 'enrolled');

select ok((select events_deleted from private.automation_retention_sweep()) >= 1,
  'sweep deletes the old unreferenced processed event');
select ok(not exists (select 1 from private.automation_events where id = '6e1d0000-0000-0000-0000-0000000000e2'),
  'the orphan event is gone');
select ok(not exists (select 1 from private.automation_event_matches
  where event_id = '6e1d0000-0000-0000-0000-0000000000e2'),
  'its match rows cascade away with it');
select ok(exists (select 1 from private.automation_events where id = '6e1d0000-0000-0000-0000-0000000000e3'),
  'an old event still referenced by a live enrollment survives');
select ok(exists (select 1 from private.automation_events where id = '6e1d0000-0000-0000-0000-0000000000e4'),
  'an old but unprocessed event is never a retention target');
select ok(exists (select 1 from private.automation_events where id = '6e1d0000-0000-0000-0000-0000000000e5'),
  'a processed event only 10 days old survives');

select ok(not exists (select 1 from private.automation_events where id = '6e1d0000-0000-0000-0000-0000000000e1'),
  'the event behind an enrollment is removed once that enrollment is compacted');

-- ================================================================================================
-- Idempotency receipts: past 30d go, younger stay. Scoped to this test's org (shared remote).
-- ================================================================================================
insert into public.automation_draft_command_receipts (organization_id, idempotency_key, command, result, created_at)
values
  (pg_temp.org(), '6e1f0000-0000-0000-0000-0000000000f1', 'create_draft', '{}'::jsonb, now() - interval '31 days'),
  (pg_temp.org(), '6e1f0000-0000-0000-0000-0000000000f2', 'save_draft', '{}'::jsonb, now() - interval '20 days');
insert into public.automation_enrollment_command_receipts (organization_id, idempotency_key, command, result, created_at)
values
  (pg_temp.org(), '6e1f0000-0000-0000-0000-0000000000f3', 'enroll', '{}'::jsonb, now() - interval '31 days'),
  (pg_temp.org(), '6e1f0000-0000-0000-0000-0000000000f4', 'pause', '{}'::jsonb, now() - interval '5 days');

select ok((select draft_receipts_deleted from private.automation_retention_sweep()) >= 1,
  'sweep deletes at least the one aged draft receipt');
select ok(not exists (select 1 from public.automation_draft_command_receipts
  where idempotency_key = '6e1f0000-0000-0000-0000-0000000000f1'),
  'the 31-day draft receipt is gone');
select ok(exists (select 1 from public.automation_draft_command_receipts
  where idempotency_key = '6e1f0000-0000-0000-0000-0000000000f2'),
  'the 20-day draft receipt survives');
select ok(not exists (select 1 from public.automation_enrollment_command_receipts
  where idempotency_key = '6e1f0000-0000-0000-0000-0000000000f3'),
  'the 31-day enrollment receipt is gone');
select ok(exists (select 1 from public.automation_enrollment_command_receipts
  where idempotency_key = '6e1f0000-0000-0000-0000-0000000000f4'),
  'the 5-day enrollment receipt survives');

-- ================================================================================================
-- Batch cap + restartability.
-- ================================================================================================
insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, source, state, re_entry_key, context, created_at, updated_at, completed_at)
select gen_random_uuid(), pg_temp.org(), pg_temp.rec(), pg_temp.ver(), 'quote', gen_random_uuid(), 'manual',
  'completed', 'k-batch-' || g, '{"x":1}'::jsonb, now() - interval '190 days', now() - interval '190 days',
  now() - interval '190 days'
from generate_series(1, 3) g;

select ok((select hit_cap from private.automation_retention_sweep(1, 1)),
  'a run that leaves a full batch behind reports hit_cap');
select ok((select count(*)::int from private.automation_enrollments
  where re_entry_key like 'k-batch-%' and compacted_at is null) between 1 and 2,
  'the capped run compacted only part of the backlog');
select ok((select enrollments_compacted from private.automation_retention_sweep(100, 100)) >= 2,
  'a follow-up run finishes the backlog it could not reach before');
select is((select count(*)::int from private.automation_enrollments
  where re_entry_key like 'k-batch-%' and compacted_at is null), 0,
  'no k-batch enrollment is left un-compacted');

-- ================================================================================================
-- Ledger + clean-slate no-op.
-- ================================================================================================
select ok((select count(*) from private.automation_retention_runs) >= 5,
  'every sweep call writes a run-ledger row');
select ok((select bool_and(finished_at is not null) from private.automation_retention_runs),
  'every ledger row is marked finished');
select is(
  (select r.work_items_deleted + r.enrollments_compacted + r.events_deleted
     + r.draft_receipts_deleted + r.enrollment_receipts_deleted
   from private.automation_retention_sweep() r),
  0, 'a sweep with nothing left to do deletes nothing');

select * from finish();
rollback;
