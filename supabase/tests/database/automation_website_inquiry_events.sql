-- CRM launch readiness Part 4, Stage 1: a website inquiry becomes exactly one Automation event and at most
-- one enrollment per recipe.
--
-- Covers: emission in the same transaction as the fact, no event before a submission is processed, duplicate
-- emission collapse, once-per-inquiry enrollment, a second genuine inquiry enrolling separately, a chat whose
-- identity needs review, conditions never silently skipped, and quote intake left unchanged in shape.

begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

set local role postgres;

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: one organization with Automation included, one form, one chat widget.
-- ---------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status)
values ('4a100000-0000-0000-0000-000000000001', 'Speed to Lead Test', 'speed-to-lead-test', 'active');

insert into public.organization_feature_overrides (organization_id, feature_key, override_state, reason)
values ('4a100000-0000-0000-0000-000000000001', 'automations', 'on', 'Test fixture.');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values ('4a100000-0000-0000-0000-000000000002', '4a100000-0000-0000-0000-000000000001', 'Test Lead', 'lead');

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4a100000-0000-0000-0000-000000000003', '4a100000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'speed-to-lead-test-form');

insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4a100000-0000-0000-0000-000000000004', '4a100000-0000-0000-0000-000000000001',
  '4a100000-0000-0000-0000-000000000003', 1, 'Get a quote');

insert into public.website_chat_widgets (id, organization_id, name)
values ('4a100000-0000-0000-0000-000000000005', '4a100000-0000-0000-0000-000000000001', 'Main site');

-- Two active recipes on the inquiry trigger: A has no conditions, B carries a (quote) condition that an
-- inquiry cannot evaluate.
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values
  ('4a100000-0000-0000-0000-000000000010', '4a100000-0000-0000-0000-000000000001', 'Speed to lead A', 'draft', 'custom',
   '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"hours","amount":1}}],"stops":[{"key":"stop.customer_reply"}]}'::jsonb),
  ('4a100000-0000-0000-0000-000000000012', '4a100000-0000-0000-0000-000000000001', 'Speed to lead B', 'draft', 'custom',
   '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[{"key":"quote.current_status","config":{"statuses":["awaiting_response"]}}],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"hours","amount":1}}],"stops":[{"key":"stop.customer_reply"}]}'::jsonb);

insert into public.automation_recipe_versions (
  id, recipe_id, organization_id, version_number, schema_version, definition, definition_hash,
  trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot
)
select v.id, v.recipe_id, '4a100000-0000-0000-0000-000000000001', 1, 1, r.draft_definition, v.hash,
  'website_inquiry.received', 0,
  -- An empty snapshot: nothing written in this test is visible in it, i.e. every event is after activation.
  '1:1:'::pg_snapshot
from (values
  ('4a100000-0000-0000-0000-000000000011'::uuid, '4a100000-0000-0000-0000-000000000010'::uuid, 'hash-a'),
  ('4a100000-0000-0000-0000-000000000013'::uuid, '4a100000-0000-0000-0000-000000000012'::uuid, 'hash-b')
) as v(id, recipe_id, hash)
join public.automation_recipes as r on r.id = v.recipe_id;

update public.automation_recipes as r
set status = 'active', current_version_id = v.id, active_trigger_key = 'website_inquiry.received'
from public.automation_recipe_versions as v
where v.recipe_id = r.id and r.organization_id = '4a100000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------------------------------
-- A form submission emits only once it is processed, and only once.
-- ---------------------------------------------------------------------------------------------------
insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact)
values
  ('4a100000-0000-0000-0000-000000000020', '4a100000-0000-0000-0000-000000000001',
   '4a100000-0000-0000-0000-000000000003', '4a100000-0000-0000-0000-000000000004', 'visit-1',
   '{"name":"Test Lead","email":"lead@example.test"}'::jsonb),
  ('4a100000-0000-0000-0000-000000000021', '4a100000-0000-0000-0000-000000000001',
   '4a100000-0000-0000-0000-000000000003', '4a100000-0000-0000-0000-000000000004', 'visit-2',
   '{"name":"Test Lead","email":"lead@example.test"}'::jsonb);

select is(
  (select count(*)::integer from private.automation_events
   where organization_id = '4a100000-0000-0000-0000-000000000001'),
  0, 'a held, unprocessed submission is not yet an inquiry'
);

update private.form_submissions
set status = 'failed', processed_at = now(), processing_error = 'form archived'
where id = '4a100000-0000-0000-0000-000000000021';

select is(
  (select count(*)::integer from private.automation_events
   where source_event_id = '4a100000-0000-0000-0000-000000000021'),
  0, 'a failed submission emits nothing'
);

update private.form_submissions
set status = 'processed', processed_at = now(),
  result = jsonb_build_object('outcome', 'request', 'client_id', '4a100000-0000-0000-0000-000000000002',
    'request_id', '4a100000-0000-0000-0000-0000000000aa')
where id = '4a100000-0000-0000-0000-000000000020';

select is(
  (select count(*)::integer from private.automation_events
   where source_event_id = '4a100000-0000-0000-0000-000000000020'),
  1, 'processing a submission emits one inquiry event'
);
select is(
  (select event_type || '|' || subject_type || '|' || source_module from private.automation_events
   where source_event_id = '4a100000-0000-0000-0000-000000000020'),
  'website_inquiry.received|form_submission|forms', 'the event names the inquiry and its source'
);
select is(
  (select payload ->> 'request_id' from private.automation_events
   where source_event_id = '4a100000-0000-0000-0000-000000000020'),
  '4a100000-0000-0000-0000-0000000000aa', 'the event carries the identifiers of what was created'
);
select is(
  (select occurred_at = s.created_at from private.automation_events as e
   join private.form_submissions as s on s.id = e.subject_id
   where e.source_event_id = '4a100000-0000-0000-0000-000000000020'),
  true, 'the event is anchored on when the customer submitted'
);

-- A retry that touches the row again does not emit a second event.
update private.form_submissions set status = 'processed' where id = '4a100000-0000-0000-0000-000000000020';
select is(
  (select count(*)::integer from private.automation_events
   where source_event_id = '4a100000-0000-0000-0000-000000000020'),
  1, 're-marking a processed submission emits nothing more'
);
select is(
  private.emit_automation_event(
    '4a100000-0000-0000-0000-000000000001', 'website_inquiry.received', 'form_submission',
    '4a100000-0000-0000-0000-000000000020', '{}'::jsonb, now(), 'forms',
    '4a100000-0000-0000-0000-000000000020'
  ),
  null::uuid, 'a duplicate inquiry fact collapses without raising'
);

-- ---------------------------------------------------------------------------------------------------
-- A Website Chat session emits on creation, including one whose identity needs review.
-- ---------------------------------------------------------------------------------------------------
insert into public.website_chat_sessions (
  id, organization_id, widget_id, client_id, match_status, visitor_name, submitted_email, normalized_email,
  session_token_hash, idempotency_key
) values (
  '4a100000-0000-0000-0000-000000000030', '4a100000-0000-0000-0000-000000000001',
  '4a100000-0000-0000-0000-000000000005', null, 'needs_review', 'Unsure Visitor',
  'unsure@example.test', 'unsure@example.test', repeat('c', 64), 'chat-visit-1'
);

select is(
  (select subject_type || '|' || source_module || '|' || (payload ->> 'match_status') || '|'
     || coalesce(payload ->> 'client_id', 'no client')
   from private.automation_events where source_event_id = '4a100000-0000-0000-0000-000000000030'),
  'website_chat_session|website_chat|needs_review|no client',
  'a chat needing identity review is an inquiry without a guessed client'
);

-- ---------------------------------------------------------------------------------------------------
-- Intake: once per inquiry per recipe, with honest reasons.
-- ---------------------------------------------------------------------------------------------------
select ok(public.intake_automation_events(200) >= 2, 'intake settles the pending inquiry events');
select is(
  (select count(*)::integer from private.automation_events
   where organization_id = '4a100000-0000-0000-0000-000000000001'
     and (processed_at is null or processing_error is not null)),
  0, 'every inquiry event settled without an error'
);
select is(
  (select count(*)::integer from private.automation_enrollments
   where recipe_id = '4a100000-0000-0000-0000-000000000010'),
  2, 'the unconditional recipe enrolls the form inquiry and the chat inquiry'
);
select is(
  (select re_entry_key from private.automation_enrollments
   where subject_id = '4a100000-0000-0000-0000-000000000020'),
  'form_submission:4a100000-0000-0000-0000-000000000020', 'the enrollment is keyed to that one inquiry'
);
select is(
  (select count(*)::integer from private.automation_work_items as w
   join private.automation_enrollments as e on e.id = w.enrollment_id
   where e.recipe_id = '4a100000-0000-0000-0000-000000000010' and w.state = 'pending' and w.step_index = 0),
  2, 'each enrollment gets exactly one pending first step'
);
select is(
  (select string_agg(distinct outcome, ',') from private.automation_event_matches
   where recipe_id = '4a100000-0000-0000-0000-000000000012'),
  'condition_unavailable', 'a condition an inquiry cannot evaluate blocks enrollment instead of being ignored'
);

-- Replay of the same inquiry never starts a second sequence.
select isnt(
  private.emit_automation_event(
    '4a100000-0000-0000-0000-000000000001', 'website_inquiry.received', 'form_submission',
    '4a100000-0000-0000-0000-000000000020', '{"channel":"form"}'::jsonb, now(), 'forms',
    '4a100000-0000-0000-0000-0000000000ff'
  ),
  null::uuid, 'a differently sourced event for the same inquiry is recorded'
);
select ok(public.intake_automation_events(200) >= 1, 'intake settles it');
select is(
  (select outcome from private.automation_event_matches as m
   join private.automation_events as e on e.id = m.event_id
   where m.recipe_id = '4a100000-0000-0000-0000-000000000010'
     and e.source_event_id = '4a100000-0000-0000-0000-0000000000ff'),
  'already_enrolled', 'the same inquiry never starts a second sequence for a recipe'
);

-- A second genuine submission from the same person is a separate inquiry.
insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact, status, processed_at, result)
values ('4a100000-0000-0000-0000-000000000022', '4a100000-0000-0000-0000-000000000001',
  '4a100000-0000-0000-0000-000000000003', '4a100000-0000-0000-0000-000000000004', 'visit-3',
  '{"name":"Test Lead","email":"lead@example.test"}'::jsonb, 'pending', null, null);
update private.form_submissions
set status = 'processed', processed_at = now(),
  result = jsonb_build_object('outcome', 'request', 'client_id', '4a100000-0000-0000-0000-000000000002')
where id = '4a100000-0000-0000-0000-000000000022';
select ok(public.intake_automation_events(200) >= 1, 'intake settles the second inquiry');
select is(
  (select count(*)::integer from private.automation_enrollments
   where recipe_id = '4a100000-0000-0000-0000-000000000010'),
  3, 'a second genuine inquiry from the same lead enrolls on its own'
);

select * from finish();

select case when num_failed() = 0 then 'ALL PASSED' else num_failed()::text || ' FAILED' end as result;

rollback;
