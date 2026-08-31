-- Automation Part 6D-2: due work is claimed once, fairly, under a lease that recovers itself, and stays
-- visible when it gets stuck.
--
-- Covers the slice's five promises: bounded fair claims, per-row leases with no global lock, one transition
-- per claim, retry/dead-letter, and a resume that makes the pre-6D-3 action park safe. Nothing sends.

begin;

create extension if not exists pgtap with schema extensions;
select plan(34);

-- ---------------------------------------------------------------------------------------------------
-- The engine stays internal.
-- ---------------------------------------------------------------------------------------------------
select is(has_function_privilege('authenticated', 'public.claim_automation_work_items(integer, integer, integer, integer, text)', 'execute'), false, 'contractors cannot claim automation work');
select is(has_function_privilege('service_role', 'public.claim_automation_work_items(integer, integer, integer, integer, text)', 'execute'), true, 'the service role claims automation work');
select is(has_function_privilege('authenticated', 'public.advance_automation_work_item(uuid, uuid)', 'execute'), false, 'contractors cannot advance a work item');
select is(has_function_privilege('authenticated', 'public.resume_automation_work_items(uuid, text, integer)', 'execute'), false, 'contractors cannot resume parked work');
select is(has_function_privilege('authenticated', 'public.request_automation_worker_wake()', 'execute'), false, 'contractors cannot fire a worker wake');

set local role postgres;

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: three tenants, each with one active recipe whose sequence is "wait 2 days, then send an email".
-- Enrollments and work items are created directly, so this file tests 6D-2 and not 6D-1's intake.
-- ---------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status)
select ('6d200000-0000-0000-0000-00000000000' || g)::uuid, 'Automation 6D-2 Org ' || g,
  'automation-6d2-org-' || g, 'active'
from generate_series(1, 3) as g;

insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
select ('6d200000-0000-0000-0000-00000000001' || g)::uuid,
  ('6d200000-0000-0000-0000-00000000000' || g)::uuid,
  'Follow up', 'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"days","amount":2}},{"type":"action","key":"action.send_email","config":{"template_id":"6d200000-0000-0000-0000-0000000000ff"}}],"stops":[]}'::jsonb
from generate_series(1, 3) as g;

insert into public.automation_recipe_versions (
  id, recipe_id, organization_id, version_number, schema_version, definition, definition_hash,
  trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot
)
select ('6d200000-0000-0000-0000-00000000002' || g)::uuid,
  ('6d200000-0000-0000-0000-00000000001' || g)::uuid,
  ('6d200000-0000-0000-0000-00000000000' || g)::uuid,
  1, 1,
  (select draft_definition from public.automation_recipes
   where id = ('6d200000-0000-0000-0000-00000000001' || g)::uuid),
  'hash-6d2-' || g, 'quote.delivery_succeeded', 0, pg_current_snapshot()
from generate_series(1, 3) as g;

update public.automation_recipes
set status = 'active',
  current_version_id = ('6d200000-0000-0000-0000-00000000002' || right(id::text, 1))::uuid,
  active_trigger_key = 'quote.delivery_succeeded'
where id::text like '6d200000-0000-0000-0000-00000000001%';

-- Five enrollments per tenant, each with one work item due five minutes ago.
insert into private.automation_events (
  id, organization_id, event_type, subject_type, subject_id, payload, occurred_at,
  source_module, source_event_id, processed_at
)
select ('6d200000-0000-0000-0000-0000000003' || g || k)::uuid,
  ('6d200000-0000-0000-0000-00000000000' || g)::uuid,
  'quote.delivery_succeeded', 'quote', gen_random_uuid(), '{}'::jsonb, now(),
  'communications', ('6d200000-0000-0000-0000-0000000004' || g || k)::uuid, now()
from generate_series(1, 3) as g cross join generate_series(1, 5) as k;

insert into private.automation_enrollments (
  id, organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
  trigger_event_id, source, re_entry_key, context
)
select ('6d200000-0000-0000-0000-0000000005' || g || k)::uuid,
  ('6d200000-0000-0000-0000-00000000000' || g)::uuid,
  ('6d200000-0000-0000-0000-00000000001' || g)::uuid,
  ('6d200000-0000-0000-0000-00000000002' || g)::uuid,
  'quote', gen_random_uuid(),
  ('6d200000-0000-0000-0000-0000000003' || g || k)::uuid,
  'event', 'entry-' || g || '-' || k, '{}'::jsonb
from generate_series(1, 3) as g cross join generate_series(1, 5) as k;

insert into private.automation_work_items (
  id, organization_id, enrollment_id, step_index, due_at, available_at
)
select ('6d200000-0000-0000-0000-0000000006' || g || k)::uuid,
  ('6d200000-0000-0000-0000-00000000000' || g)::uuid,
  ('6d200000-0000-0000-0000-0000000005' || g || k)::uuid,
  0, now() - interval '5 minutes', now() - interval '5 minutes'
from generate_series(1, 3) as g cross join generate_series(1, 5) as k;

-- ---------------------------------------------------------------------------------------------------
-- Fairness: no tenant takes the batch.
-- ---------------------------------------------------------------------------------------------------
create temporary table claim_one on commit drop as
select * from public.claim_automation_work_items(6, 2, 120, 8, 'test-worker');

select is((select count(*)::integer from claim_one), 6, 'the claim returns exactly the batch it was asked for');
select is(
  (select count(distinct organization_id)::integer from claim_one), 3,
  'a batch spreads across every tenant with due work'
);
select is(
  (select max(per_org)::integer from (
    select count(*) as per_org from claim_one group by organization_id
  ) as counted), 2,
  'no tenant exceeds the per-organization cap while others are waiting'
);

-- ---------------------------------------------------------------------------------------------------
-- The lease: a claimed row simply is not due, and it recovers on its own.
-- ---------------------------------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.claim_automation_work_items(6, 6, 120, 8, 'test-worker-two')
   where work_item_id in (select work_item_id from claim_one)),
  0,
  'a second worker cannot take a row that is already leased'
);

select is(
  (select count(*)::integer from private.automation_work_items
   where id in (select work_item_id from claim_one) and available_at > now()),
  6,
  'claiming pushes the row out of the due window for the length of the lease'
);

-- Simulate an abandoned claim: the lease passes with the row still pending. Dated well before every other
-- due row so the deterministic claim order picks this one and the assertion is about recovery, not luck.
update private.automation_work_items
set available_at = now() - interval '1 hour'
where id = (select work_item_id from claim_one order by work_item_id limit 1);

select is(
  (select count(*)::integer from public.claim_automation_work_items(1, 1, 120, 8, 'test-worker-three')),
  1,
  'an abandoned claim returns to the queue when its lease passes, with no quarantine sweep'
);
select is(
  (select attempts from private.automation_work_items
   where id = (select work_item_id from claim_one order by work_item_id limit 1)),
  2,
  'a re-claim counts the abandoned attempt, so a crash loop reaches the dead-letter cap'
);

-- ---------------------------------------------------------------------------------------------------
-- Over-cap fill and future work.
-- ---------------------------------------------------------------------------------------------------
-- Everything currently unclaimed belongs to tenants with more due rows than the cap allows, so a batch that
-- cannot be filled fairly must still fill.
update private.automation_work_items set available_at = now() - interval '5 minutes'
where state = 'pending';

-- Three tenants and a cap of one: the fair pass can only place three, so the fourth slot proves that
-- over-cap rows still fill capacity rather than the batch coming back short.
select is(
  (select count(*)::integer from public.claim_automation_work_items(4, 1, 120, 8, 'test-worker-fill')),
  4,
  'rows over the fairness cap still fill capacity the fair pass left empty'
);

update private.automation_work_items
set available_at = now() + interval '2 days', due_at = now() + interval '2 days', state = 'pending',
  claim_token = null, claimed_at = null;

select is(
  (select count(*)::integer from public.claim_automation_work_items(25, 5, 120, 8, 'test-worker-future')),
  0,
  'work scheduled into the future is not claimed early; the Cron sweep finds it when it is due'
);

-- ---------------------------------------------------------------------------------------------------
-- One transition: a wait step schedules exactly one next step.
-- ---------------------------------------------------------------------------------------------------
update private.automation_work_items
set available_at = now() - interval '1 minute', due_at = now() - interval '1 minute',
  attempts = 0, state = 'pending', claim_token = null, claimed_at = null
where enrollment_id = '6d200000-0000-0000-0000-000000000511';

create temporary table wait_claim on commit drop as
select * from public.claim_automation_work_items(1, 1, 120, 8, 'test-worker-wait');

select is(
  (select public.advance_automation_work_item(work_item_id, claim_token) from wait_claim),
  'waiting',
  'a wait step reports that it is waiting'
);
select is(
  (select state from private.automation_work_items where id = (select work_item_id from wait_claim)),
  'done',
  'the completed wait step is settled, not left claimed'
);
select is(
  (select count(*)::integer from private.automation_work_items
   where enrollment_id = '6d200000-0000-0000-0000-000000000511' and step_index = 1),
  1,
  'exactly one next transition is created, never a pre-expanded sequence'
);
select ok(
  (select due_at > now() + interval '47 hours' from private.automation_work_items
   where enrollment_id = '6d200000-0000-0000-0000-000000000511' and step_index = 1),
  'the next step is scheduled at the configured delay'
);
select is(
  (select current_step_index from private.automation_enrollments
   where id = '6d200000-0000-0000-0000-000000000511'),
  1,
  'the enrollment advances with the step, in the same transaction'
);

-- ---------------------------------------------------------------------------------------------------
-- The pre-6D-3 action park, and the resume that makes it safe.
-- ---------------------------------------------------------------------------------------------------
update private.automation_work_items
set available_at = now() - interval '1 minute', due_at = now() - interval '1 minute'
where enrollment_id = '6d200000-0000-0000-0000-000000000511' and step_index = 1;

create temporary table action_claim on commit drop as
select * from public.claim_automation_work_items(1, 1, 120, 8, 'test-worker-action');

select is(
  (select public.advance_automation_work_item(work_item_id, claim_token) from action_claim),
  'action_not_available',
  'an action step parks truthfully while it has no adapter'
);
select is(
  (select state || ':' || attention_reason from private.automation_work_items
   where id = (select work_item_id from action_claim)),
  'needs_attention:action_not_available',
  'the parked step says why it is waiting for a person'
);
select is(
  (select state from private.automation_enrollments where id = '6d200000-0000-0000-0000-000000000511'),
  'active',
  'parking a step does not end the enrollment'
);
select is(
  public.resume_automation_work_items('6d200000-0000-0000-0000-000000000001', 'action_not_available', 100),
  1,
  'a parked step can be put back on the queue'
);
select is(
  (select state || ':' || attempts::text from private.automation_work_items
   where id = (select work_item_id from action_claim)),
  'pending:0',
  'resuming clears the attempt budget so every check runs again on the next claim'
);

-- ---------------------------------------------------------------------------------------------------
-- The claim token is the only authority over a row.
-- ---------------------------------------------------------------------------------------------------
select is(
  public.advance_automation_work_item(
    (select work_item_id from action_claim), '6d200000-0000-0000-0000-0000000000ee'
  ),
  'claim_lost',
  'a worker whose lease was taken over cannot settle the row it lost'
);

-- ---------------------------------------------------------------------------------------------------
-- Retry and dead-letter.
-- ---------------------------------------------------------------------------------------------------
update private.automation_work_items
set available_at = now() - interval '1 minute'
where id = (select work_item_id from action_claim);

create temporary table retry_claim on commit drop as
select * from public.claim_automation_work_items(1, 1, 120, 8, 'test-worker-retry');

select is(
  (select public.retry_automation_work_item(work_item_id, claim_token, 'temporary_glitch', 'A transient failure.', false) from retry_claim),
  'retry_scheduled',
  'a transient failure backs the row off instead of losing it'
);
select ok(
  (select available_at > now() from private.automation_work_items
   where id = (select work_item_id from retry_claim)),
  'the backed-off row is not immediately re-claimable'
);

update private.automation_work_items
set attempts = 8, available_at = now() - interval '1 minute'
where id = (select work_item_id from retry_claim);

select is(
  (select count(*)::integer from public.claim_automation_work_items(5, 5, 120, 8, 'test-worker-dead')),
  0,
  'a row that has burned its attempts is not claimed again'
);
select is(
  (select state || ':' || attention_reason from private.automation_work_items
   where id = (select work_item_id from retry_claim)),
  'needs_attention:max_attempts',
  'it becomes visible as needing attention rather than disappearing'
);

-- ---------------------------------------------------------------------------------------------------
-- Live safety rechecks on every transition.
-- ---------------------------------------------------------------------------------------------------
update private.automation_work_items
set available_at = now() - interval '1 minute', due_at = now() - interval '1 minute',
  attempts = 0, state = 'pending', attention_reason = null, attention_at = null,
  claim_token = null, claimed_at = null
where enrollment_id = '6d200000-0000-0000-0000-000000000521';
update public.automation_recipes set status = 'paused'
where id = '6d200000-0000-0000-0000-000000000012';

create temporary table paused_claim on commit drop as
select * from public.claim_automation_work_items(1, 1, 120, 8, 'test-worker-paused');

select is(
  (select public.advance_automation_work_item(work_item_id, claim_token) from paused_claim),
  'recipe_not_active',
  'a paused recipe stops its running enrollments instead of acting under a retired definition'
);

update private.automation_enrollments set expires_at = now() - interval '1 day'
where id = '6d200000-0000-0000-0000-000000000531';
update private.automation_work_items
set available_at = now() - interval '1 minute', due_at = now() - interval '1 minute',
  attempts = 0, state = 'pending', claim_token = null, claimed_at = null
where enrollment_id = '6d200000-0000-0000-0000-000000000531';

create temporary table expired_claim on commit drop as
select * from public.claim_automation_work_items(1, 1, 120, 8, 'test-worker-expired');

select is(
  (select public.advance_automation_work_item(work_item_id, claim_token) from expired_claim),
  'enrollment_expired',
  'an enrollment past the organization maximum duration stops rather than continuing'
);

-- ---------------------------------------------------------------------------------------------------
-- Intake honours its retry clock.
-- ---------------------------------------------------------------------------------------------------
insert into private.automation_events (
  organization_id, event_type, subject_type, subject_id, payload, occurred_at,
  source_module, source_event_id, available_at
) values (
  '6d200000-0000-0000-0000-000000000001', 'quote.delivery_succeeded', 'quote', gen_random_uuid(),
  '{}'::jsonb, now(), 'communications', '6d200000-0000-0000-0000-0000000000aa',
  now() + interval '10 minutes'
);

select is(
  public.intake_automation_events(25), 0,
  'a backed-off event is not re-read until its retry time arrives'
);

-- ---------------------------------------------------------------------------------------------------
-- The wake is wired, and switched off until deployment says otherwise.
-- ---------------------------------------------------------------------------------------------------
select is(
  (select count(*)::integer from pg_trigger
   where tgname in ('automation_events_wake_on_insert', 'automation_work_items_wake_on_insert')
     and not tgisinternal),
  2,
  'both queues nudge the worker the moment due work lands'
);
select is(
  (select active from cron.job where jobname = 'automation-worker-wake-one-minute'),
  false,
  'the minute sweep is installed but not running until deployment configuration is in place'
);

select * from finish();
rollback;
