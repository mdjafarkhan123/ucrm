-- Automation Part 6D-5a: record-level enrollment controls. Enroll / pause / resume / skip / stop work, the
-- per-record read projects safe columns only, and every write is tenant-scoped, idempotent, and state-guarded.
--
-- Resume timing is GHL-accurate: pause parks the next step at its ORIGINAL due time; resume restores it there.

begin;

create extension if not exists pgtap with schema extensions;
select plan(35);

-- ---------------------------------------------------------------------------------------------------
-- The commands and the read stay internal: service_role only, never anon/authenticated.
-- ---------------------------------------------------------------------------------------------------
select function_privs_are('public', 'preview_automation_manual_enrollment',
  array['uuid', 'uuid', 'text', 'uuid'], 'service_role', array['EXECUTE'],
  'the service role runs the enroll preview');
select function_privs_are('public', 'preview_automation_manual_enrollment',
  array['uuid', 'uuid', 'text', 'uuid'], 'authenticated', array[]::text[],
  'contractors cannot run the enroll preview directly');
select function_privs_are('public', 'manual_enroll_automation',
  array['uuid', 'uuid', 'uuid', 'text', 'uuid', 'integer', 'uuid'], 'service_role', array['EXECUTE'],
  'the service role runs manual enroll');
select function_privs_are('public', 'manual_enroll_automation',
  array['uuid', 'uuid', 'uuid', 'text', 'uuid', 'integer', 'uuid'], 'authenticated', array[]::text[],
  'contractors cannot run manual enroll directly');
select function_privs_are('public', 'automation_record_enrollments',
  array['uuid', 'text', 'uuid', 'integer'], 'service_role', array['EXECUTE'],
  'the service role runs the per-record read');
select function_privs_are('public', 'automation_record_enrollments',
  array['uuid', 'text', 'uuid', 'integer'], 'authenticated', array[]::text[],
  'contractors cannot run the per-record read directly');

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: one org, one active recipe whose version has two action steps around one wait step.
-- ---------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status)
values ('6d510000-0000-0000-0000-000000000001', 'Automation 6D-5', 'automation-6d5', 'active');

set local role postgres;

insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('6d5a0000-0000-0000-0000-000000000001', '6d510000-0000-0000-0000-000000000001',
  'Quote follow-up', 'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{}},{"type":"wait","key":"wait.delay","config":{"amount":2,"unit":"days"}},{"type":"action","key":"action.send_email","config":{}}],"stops":[]}'::jsonb);

insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot)
values ('6d5b0000-0000-0000-0000-000000000001', '6d5a0000-0000-0000-0000-000000000001',
  '6d510000-0000-0000-0000-000000000001', 1, 1,
  (select draft_definition from public.automation_recipes where id = '6d5a0000-0000-0000-0000-000000000001'),
  'hash-6d5', 'quote.delivery_succeeded', 0, pg_current_snapshot());

update public.automation_recipes
set status = 'active', current_version_id = '6d5b0000-0000-0000-0000-000000000001',
  active_trigger_key = 'quote.delivery_succeeded'
where id = '6d5a0000-0000-0000-0000-000000000001';

-- Constant test uuids.
create function pg_temp.org() returns uuid language sql immutable as $$select '6d510000-0000-0000-0000-000000000001'::uuid$$;
create function pg_temp.actor() returns uuid language sql immutable as $$select '6d500000-0000-0000-0000-000000000009'::uuid$$;
create function pg_temp.recipe() returns uuid language sql immutable as $$select '6d5a0000-0000-0000-0000-000000000001'::uuid$$;
create function pg_temp.quoteA() returns uuid language sql immutable as $$select '6d5c0000-0000-0000-0000-00000000000a'::uuid$$;
create function pg_temp.quoteB() returns uuid language sql immutable as $$select '6d5c0000-0000-0000-0000-00000000000b'::uuid$$;
create function pg_temp.keyA() returns uuid language sql immutable as $$select '6d5d0000-0000-0000-0000-00000000000a'::uuid$$;
create function pg_temp.eidA() returns uuid language sql stable as
  $$select enrollment_id from public.automation_enrollment_command_receipts
     where organization_id = pg_temp.org() and idempotency_key = pg_temp.keyA()$$;

-- ---------------------------------------------------------------------------------------------------
-- The source/evidence check makes event and manual enrollments mutually exclusive on trigger_event_id.
-- ---------------------------------------------------------------------------------------------------
select throws_ok($$
  insert into private.automation_enrollments (organization_id, recipe_id, recipe_version_id, subject_type,
    subject_id, trigger_event_id, source, re_entry_key, context)
  values ('6d510000-0000-0000-0000-000000000001', '6d5a0000-0000-0000-0000-000000000001',
    '6d5b0000-0000-0000-0000-000000000001', 'quote', '6d5c0000-0000-0000-0000-0000000000ff',
    '6d5c0000-0000-0000-0000-0000000000fe', 'manual', 'bad-manual', '{}'::jsonb) $$,
  '23514', null, 'a manual enrollment may not carry a trigger event');

select throws_ok($$
  insert into private.automation_enrollments (organization_id, recipe_id, recipe_version_id, subject_type,
    subject_id, trigger_event_id, source, re_entry_key, context)
  values ('6d510000-0000-0000-0000-000000000001', '6d5a0000-0000-0000-0000-000000000001',
    '6d5b0000-0000-0000-0000-000000000001', 'quote', '6d5c0000-0000-0000-0000-0000000000fd',
    null, 'event', 'bad-event', '{}'::jsonb) $$,
  '23514', null, 'an event enrollment must carry a trigger event');

-- ---------------------------------------------------------------------------------------------------
-- Preview before enrolling: eligible, two expected messages, no overlap.
-- ---------------------------------------------------------------------------------------------------
select is((public.preview_automation_manual_enrollment(pg_temp.org(), pg_temp.recipe(), 'quote', pg_temp.quoteA())) ->> 'eligible',
  'true', 'an un-enrolled quote is eligible for manual enroll');
select is((public.preview_automation_manual_enrollment(pg_temp.org(), pg_temp.recipe(), 'quote', pg_temp.quoteA())) ->> 'expected_message_count',
  '2', 'preview counts the two action steps as expected messages');
select is((public.preview_automation_manual_enrollment(pg_temp.org(), pg_temp.recipe(), 'quote', pg_temp.quoteA())) ->> 'overlap_same_recipe',
  '0', 'preview shows no same-recipe overlap before enrolling');

-- ---------------------------------------------------------------------------------------------------
-- Manual enroll: one active manual enrollment with no event, seeded at step 0.
-- ---------------------------------------------------------------------------------------------------
select is((public.manual_enroll_automation(pg_temp.org(), pg_temp.actor(), pg_temp.recipe(), 'quote',
  pg_temp.quoteA(), 30, pg_temp.keyA())) ->> 'state', 'active', 'manual enroll returns an active enrollment');

select is(
  (select source || ':' || (trigger_event_id is null)::text
   from private.automation_enrollments where id = pg_temp.eidA()),
  'manual:true', 'the enrollment is a manual one with no trigger event');

select is((select re_entry_key from private.automation_enrollments where id = pg_temp.eidA()),
  'manual:' || pg_temp.keyA()::text, 'the manual re-entry key is derived from the command id');

select is(
  (select step_index || ':' || state from private.automation_work_items where enrollment_id = pg_temp.eidA()),
  '0:pending', 'a single pending first step is scheduled at step 0');

-- Idempotent replay: same key, same enrollment, no second row.
select is((public.manual_enroll_automation(pg_temp.org(), pg_temp.actor(), pg_temp.recipe(), 'quote',
  pg_temp.quoteA(), 30, pg_temp.keyA())) ->> 'idempotent_replay', 'true', 'replaying the enroll key is idempotent');
select is(
  (select count(*)::integer from private.automation_enrollments
   where organization_id = pg_temp.org() and subject_id = pg_temp.quoteA()),
  1, 'the idempotent replay creates no second enrollment');

-- A fresh key for the same live subject+recipe is refused.
select throws_ok($$
  select public.manual_enroll_automation('6d510000-0000-0000-0000-000000000001',
    '6d5c0000-0000-0000-0000-000000000009', '6d5a0000-0000-0000-0000-000000000001', 'quote',
    '6d5c0000-0000-0000-0000-00000000000a', 30, '6d5d0000-0000-0000-0000-0000000000ee') $$,
  '23505', null, 'a second live enroll of the same quote+recipe is refused');

-- Preview now reports the live enrollment.
select is((public.preview_automation_manual_enrollment(pg_temp.org(), pg_temp.recipe(), 'quote', pg_temp.quoteA())) ->> 'eligible',
  'false', 'an already-enrolled quote is not eligible again');

-- ---------------------------------------------------------------------------------------------------
-- Safe per-record read: recipe/version/state/source and a real next-due time; nothing internal.
-- ---------------------------------------------------------------------------------------------------
select is(
  (select recipe_name || '|' || version_number || '|' || state || '|' || source
   from public.automation_record_enrollments(pg_temp.org(), 'quote', pg_temp.quoteA())),
  'Quote follow-up|1|active|manual', 'the read projects recipe, version, state, and source');
select isnt(
  (select next_due_at from public.automation_record_enrollments(pg_temp.org(), 'quote', pg_temp.quoteA())),
  null, 'the read exposes the next step''s due time');

-- ---------------------------------------------------------------------------------------------------
-- Pause: park the step at its original due time; take it out of the claimable pool.
-- ---------------------------------------------------------------------------------------------------
select is((public.pause_automation_enrollment(pg_temp.org(), pg_temp.actor(), pg_temp.eidA(),
  '6d5d0000-0000-0000-0000-0000000000a1')) ->> 'state', 'paused', 'pause reports paused');
select is(
  (select e.state || ':' || (e.paused_work_due_at is not null)::text || ':' || w.state
   from private.automation_enrollments e
   join private.automation_work_items w on w.enrollment_id = e.id and w.step_index = 0
   where e.id = pg_temp.eidA()),
  'paused:true:cancelled', 'pause records the original due time and cancels the pending step');
select throws_ok($$
  select public.pause_automation_enrollment('6d510000-0000-0000-0000-000000000001',
    '6d5c0000-0000-0000-0000-000000000009', pg_temp.eidA(), '6d5d0000-0000-0000-0000-0000000000a2') $$,
  '23001', null, 'a paused enrollment cannot be paused again');

-- ---------------------------------------------------------------------------------------------------
-- Resume: restore the same step at its original due time; clear the parked marker.
-- ---------------------------------------------------------------------------------------------------
select is((public.resume_automation_enrollment(pg_temp.org(), pg_temp.actor(), pg_temp.eidA(),
  '6d5d0000-0000-0000-0000-0000000000b1')) ->> 'state', 'active', 'resume reports active');
select is(
  (select e.state || ':' || (e.paused_work_due_at is null)::text || ':' || w.state
   from private.automation_enrollments e
   join private.automation_work_items w on w.enrollment_id = e.id and w.step_index = 0
   where e.id = pg_temp.eidA()),
  'active:true:pending', 'resume resurrects the step 0 row and clears the parked marker');

-- ---------------------------------------------------------------------------------------------------
-- Skip: cancel the current step and advance; the last skip completes the enrollment.
-- ---------------------------------------------------------------------------------------------------
select is((public.skip_automation_enrollment_step(pg_temp.org(), pg_temp.actor(), pg_temp.eidA(),
  '6d5d0000-0000-0000-0000-0000000000c1')) ->> 'current_step_index', '1', 'first skip advances to step 1');
select is(
  (select count(*)::integer from private.automation_work_items
   where enrollment_id = pg_temp.eidA() and step_index = 1 and state = 'pending'),
  1, 'first skip schedules the next step now');
select is((public.skip_automation_enrollment_step(pg_temp.org(), pg_temp.actor(), pg_temp.eidA(),
  '6d5d0000-0000-0000-0000-0000000000c2')) ->> 'current_step_index', '2', 'second skip advances to step 2');
select is((public.skip_automation_enrollment_step(pg_temp.org(), pg_temp.actor(), pg_temp.eidA(),
  '6d5d0000-0000-0000-0000-0000000000c3')) ->> 'state', 'completed', 'skipping past the last step completes it');
select is(
  (select count(*)::integer from private.automation_work_items
   where enrollment_id = pg_temp.eidA() and state = 'pending'),
  0, 'a completed enrollment has no pending work');

-- ---------------------------------------------------------------------------------------------------
-- Stop: terminal, with a reason, cancelling pending work. Tenant isolation guards the command.
-- ---------------------------------------------------------------------------------------------------
select public.manual_enroll_automation(pg_temp.org(), pg_temp.actor(), pg_temp.recipe(), 'quote',
  pg_temp.quoteB(), null, '6d5d0000-0000-0000-0000-0000000000d0');

create function pg_temp.eidB() returns uuid language sql stable as
  $$select enrollment_id from public.automation_enrollment_command_receipts
     where organization_id = pg_temp.org() and idempotency_key = '6d5d0000-0000-0000-0000-0000000000d0'$$;

-- A command scoped to the wrong organization cannot see the enrollment at all.
select throws_ok($$
  select public.pause_automation_enrollment('6d510000-0000-0000-0000-0000000000ff',
    '6d5c0000-0000-0000-0000-000000000009', pg_temp.eidB(), '6d5d0000-0000-0000-0000-0000000000d1') $$,
  'P0002', null, 'a command scoped to another organization does not find the enrollment');

select is((public.stop_automation_enrollment(pg_temp.org(), pg_temp.actor(), pg_temp.eidB(),
  'Customer called to decline', '6d5d0000-0000-0000-0000-0000000000d2')) ->> 'state', 'stopped',
  'stop reports stopped');
select is(
  (select e.state || ':' || e.stop_reason || ':' || coalesce(
     (select w.state from private.automation_work_items w where w.enrollment_id = e.id and w.step_index = 0), 'none')
   from private.automation_enrollments e where e.id = pg_temp.eidB()),
  'stopped:Customer called to decline:cancelled', 'stop records the reason and cancels pending work');
select throws_ok($$
  select public.stop_automation_enrollment(pg_temp.org(), pg_temp.actor(), pg_temp.eidB(),
    'again', '6d5d0000-0000-0000-0000-0000000000d3') $$,
  '23001', null, 'a finished enrollment cannot be stopped again');

select * from finish();
rollback;
