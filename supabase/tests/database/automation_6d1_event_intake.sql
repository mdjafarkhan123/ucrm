-- Automation Part 6D-1: delivered callback -> one event -> one enrollment -> one first work item.
--
-- Covers the six foundation requirements: internal-only storage, duplicate/differently-keyed callback
-- collapse, replay safety, activation cutoff, tenant-scoped matching, and the permanent no-restart rule.

begin;

create extension if not exists pgtap with schema extensions;
select plan(31);

-- ---------------------------------------------------------------------------------------------------
-- Automation machinery is internal by construction.
-- ---------------------------------------------------------------------------------------------------
select is(has_schema_privilege('anon', 'private', 'usage'), false, 'anonymous callers cannot reach the private schema');
select is(has_schema_privilege('authenticated', 'private', 'usage'), false, 'contractors cannot reach the private schema');
select is(has_table_privilege('authenticated', 'private.automation_events', 'select'), false, 'contractors cannot read raw automation events');
select is(has_table_privilege('authenticated', 'private.automation_enrollments', 'select'), false, 'contractors cannot read raw enrollments');
select is(has_table_privilege('authenticated', 'private.automation_work_items', 'select'), false, 'contractors cannot read raw worker state');
select is(has_table_privilege('authenticated', 'private.automation_event_matches', 'select'), false, 'contractors cannot read raw match outcomes');
select is(has_function_privilege('authenticated', 'public.intake_automation_events(integer)', 'execute'), false, 'contractors cannot run intake');
select is(has_function_privilege('service_role', 'public.intake_automation_events(integer)', 'execute'), true, 'the service role runs intake');

set local role postgres;

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: one organization with Automation included, one delivered quote email.
-- ---------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status)
values ('6d100000-0000-0000-0000-000000000001', 'Automation 6D-1 Test', 'automation-6d1-test', 'active');

insert into public.organization_feature_overrides (organization_id, feature_key, override_state, reason)
values ('6d100000-0000-0000-0000-000000000001', 'automations', 'on', 'Test fixture.');

insert into public.clients (id, organization_id, display_name)
values ('6d100000-0000-0000-0000-000000000002', '6d100000-0000-0000-0000-000000000001', 'Test Customer');

-- normalized_value is a generated column; the fixture supplies only the raw value.
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('6d100000-0000-0000-0000-00000000000b', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000002', 'email', 'customer@example.test', true);

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('6d100000-0000-0000-0000-000000000003', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000002', '1 Test Street', 'Testville');

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values ('6d100000-0000-0000-0000-000000000004', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000002', '6d100000-0000-0000-0000-000000000003', 6001,
  'Roof replacement', 'awaiting_response', 'USD');

-- A published version must carry its publication stamp and document hash.
insert into public.quote_versions (id, organization_id, quote_id, version_number, status, currency_code, client_display_name, organization_name, published_at, document_hash)
values ('6d100000-0000-0000-0000-000000000005', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000004', 1, 'published', 'USD', 'Test Customer', 'Automation 6D-1 Test',
  now(), repeat('a', 64));

insert into public.quote_recipients (id, organization_id, quote_id, display_name, email)
values ('6d100000-0000-0000-0000-000000000006', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000004', 'Test Customer', 'customer@example.test');

insert into public.quote_access_links (id, organization_id, quote_id, quote_version_id, recipient_id, token_hash)
values ('6d100000-0000-0000-0000-000000000007', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000004', '6d100000-0000-0000-0000-000000000005',
  '6d100000-0000-0000-0000-000000000006', decode(repeat('ab', 32), 'hex'));

-- A: a fully identified quote send. B: a manual email (no quote). C: a quote send already hard bounced.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, quote_id, quote_version_id,
  quote_recipient_id, quote_access_link_id, logical_send_key, recipient_email, subject,
  html_content, text_content
) values (
  '6d100000-0000-0000-0000-000000000008', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000002', '6d100000-0000-0000-0000-00000000000b',
  '6d100000-0000-0000-0000-000000000004', '6d100000-0000-0000-0000-000000000005',
  '6d100000-0000-0000-0000-000000000006', '6d100000-0000-0000-0000-000000000007',
  'test-send-a', 'customer@example.test', 'Your quote', '<p>quote</p>', 'quote'
), (
  '6d100000-0000-0000-0000-000000000009', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000002', '6d100000-0000-0000-0000-00000000000b',
  null, null, null, null,
  'test-send-b', 'customer@example.test', 'Just a note', '<p>note</p>', 'note'
), (
  '6d100000-0000-0000-0000-00000000000a', '6d100000-0000-0000-0000-000000000001',
  '6d100000-0000-0000-0000-000000000002', '6d100000-0000-0000-0000-00000000000b',
  '6d100000-0000-0000-0000-000000000004', '6d100000-0000-0000-0000-000000000005',
  '6d100000-0000-0000-0000-000000000006', '6d100000-0000-0000-0000-000000000007',
  'test-send-c', 'customer@example.test', 'Your quote', '<p>quote</p>', 'quote'
);

update public.communication_delivery_intents
set delivery_outcome = 'hard_bounce', delivery_outcome_at = now()
where id = '6d100000-0000-0000-0000-00000000000a';

-- Send-time identity is all-or-nothing.
select throws_ok(
  $$insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, quote_id, quote_version_id,
      logical_send_key, recipient_email, subject, html_content, text_content
    ) values (
      '6d100000-0000-0000-0000-000000000001', '6d100000-0000-0000-0000-000000000002',
      '6d100000-0000-0000-0000-00000000000b', '6d100000-0000-0000-0000-000000000004',
      '6d100000-0000-0000-0000-000000000005', 'test-send-partial', 'customer@example.test',
      'Partial', '<p>x</p>', 'x'
    )$$,
  -- pgTAP only exposes a SQLSTATE form with four arguments: (sql, errcode, errmsg, description).
  -- A null message means "any message with this SQLSTATE".
  '23514'::char(5), null,
  'a half-identified quote send is rejected'
);

-- Two active recipes on the same trigger: A activated before the delivery, B activated after it.
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values
  ('6d100000-0000-0000-0000-000000000010', '6d100000-0000-0000-0000-000000000001', 'Follow up A', 'draft', 'custom',
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[{"key":"quote.current_status","config":{"statuses":["awaiting_response"]}}],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"days","amount":3}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb),
  ('6d100000-0000-0000-0000-000000000012', '6d100000-0000-0000-0000-000000000001', 'Follow up B', 'draft', 'custom',
   '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"days","amount":1}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb);

insert into public.automation_recipe_versions (
  id, recipe_id, organization_id, version_number, schema_version, definition, definition_hash,
  trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot
) values (
  '6d100000-0000-0000-0000-000000000011', '6d100000-0000-0000-0000-000000000010',
  '6d100000-0000-0000-0000-000000000001', 1, 1,
  (select draft_definition from public.automation_recipes where id = '6d100000-0000-0000-0000-000000000010'),
  'hash-a', 'quote.delivery_succeeded', 0, pg_current_snapshot()
), (
  '6d100000-0000-0000-0000-000000000013', '6d100000-0000-0000-0000-000000000012',
  '6d100000-0000-0000-0000-000000000001', 1, 1,
  (select draft_definition from public.automation_recipes where id = '6d100000-0000-0000-0000-000000000012'),
  'hash-b', 'quote.delivery_succeeded', 0,
  -- A cutoff far in the future: every real delivery is already visible in it, i.e. "before activation".
  '4000000000:4000000000:'::pg_snapshot
);

update public.automation_recipes
set status = 'active',
  current_version_id = '6d100000-0000-0000-0000-000000000011',
  active_trigger_key = 'quote.delivery_succeeded'
where id = '6d100000-0000-0000-0000-000000000010';

update public.automation_recipes
set status = 'active',
  current_version_id = '6d100000-0000-0000-0000-000000000013',
  active_trigger_key = 'quote.delivery_succeeded'
where id = '6d100000-0000-0000-0000-000000000012';

-- ---------------------------------------------------------------------------------------------------
-- Delivery truth writes exactly one event.
-- ---------------------------------------------------------------------------------------------------
insert into public.communication_provider_callback_events (provider_event_key, delivery_intent_id, event_kind, payload)
values
  ('key-a-1', '6d100000-0000-0000-0000-000000000008', 'delivered', '{}'::jsonb),
  -- The same delivery reported again under a different provider key.
  ('key-a-2', '6d100000-0000-0000-0000-000000000008', 'delivered', '{}'::jsonb),
  ('key-b-1', '6d100000-0000-0000-0000-000000000009', 'delivered', '{}'::jsonb),
  ('key-c-1', '6d100000-0000-0000-0000-00000000000a', 'delivered', '{}'::jsonb);

-- The drain is database-wide, so its return count is not a fixture assertion; assert on OUR four rows.
select ok(public.process_communication_provider_callbacks(100) >= 4, 'the callback drain runs');
select is(
  (select count(*)::integer from public.communication_provider_callback_events
   where provider_event_key in ('key-a-1', 'key-a-2', 'key-b-1', 'key-c-1') and processed_at is not null),
  4, 'all four fixture callbacks are processed'
);

select is(
  (select count(*)::integer from private.automation_events
   where source_event_id = '6d100000-0000-0000-0000-000000000008'),
  1, 'two differently keyed callbacks for one delivery produce one event'
);
select is(
  (select count(*)::integer from private.automation_events
   where source_event_id = '6d100000-0000-0000-0000-000000000009'),
  0, 'a delivered email with no quote identity produces no event'
);
select is(
  (select count(*)::integer from private.automation_events
   where source_event_id = '6d100000-0000-0000-0000-00000000000a'),
  0, 'a late delivered callback on an already bounced message produces no event'
);
select is(
  (select payload ->> 'quote_version_id' from private.automation_events
   where source_event_id = '6d100000-0000-0000-0000-000000000008'),
  '6d100000-0000-0000-0000-000000000005', 'the event carries the version that was actually sent'
);

-- ---------------------------------------------------------------------------------------------------
-- Intake: enrollment, first work item, and honest reasons.
-- ---------------------------------------------------------------------------------------------------
select is(public.intake_automation_events(25), 1, 'intake settles the one pending event');
select is(
  (select processing_error from private.automation_events
   where source_event_id = '6d100000-0000-0000-0000-000000000008'),
  null::text, 'intake settled the event without an error'
);
select is(
  (select count(*)::integer from private.automation_enrollments
   where organization_id = '6d100000-0000-0000-0000-000000000001'),
  1, 'exactly one enrollment is created'
);
select is(
  (select recipe_version_id from private.automation_enrollments
   where recipe_id = '6d100000-0000-0000-0000-000000000010'),
  '6d100000-0000-0000-0000-000000000011'::uuid, 'the enrollment is pinned to the frozen version'
);
select is(
  (select context ->> 'quote_recipient_id' from private.automation_enrollments
   where recipe_id = '6d100000-0000-0000-0000-000000000010'),
  '6d100000-0000-0000-0000-000000000006', 'the enrollment keeps send-time identity'
);
select is(
  (select outcome from private.automation_event_matches
   where recipe_id = '6d100000-0000-0000-0000-000000000010'),
  'enrolled', 'the recipe activated before the delivery enrolls'
);
select is(
  (select outcome from private.automation_event_matches
   where recipe_id = '6d100000-0000-0000-0000-000000000012'),
  'before_activation', 'the recipe activated after the delivery records why it did not enrol'
);
select is(
  (select count(*)::integer from private.automation_work_items
   where organization_id = '6d100000-0000-0000-0000-000000000001'),
  1, 'exactly one first work item is created'
);
select is(
  (select state || ':' || step_index::text from private.automation_work_items
   where organization_id = '6d100000-0000-0000-0000-000000000001'),
  'pending:0', 'the work item is the pending first step'
);

-- Replay: nothing is left to do, and nothing changes.
select is(public.intake_automation_events(25), 0, 'a second intake run has nothing to settle');
select is(
  (select count(*)::integer from private.automation_enrollments
   where organization_id = '6d100000-0000-0000-0000-000000000001'),
  1, 'replaying intake does not create a second enrollment'
);

-- ---------------------------------------------------------------------------------------------------
-- The permanent no-restart rule: same quote version, same recipient, second delivery.
-- ---------------------------------------------------------------------------------------------------
select isnt(
  private.emit_automation_event(
    '6d100000-0000-0000-0000-000000000001', 'quote.delivery_succeeded', 'quote',
    '6d100000-0000-0000-0000-000000000004',
    jsonb_build_object(
      'delivery_intent_id', '6d100000-0000-0000-0000-00000000000a',
      'quote_id', '6d100000-0000-0000-0000-000000000004',
      'quote_version_id', '6d100000-0000-0000-0000-000000000005',
      'quote_recipient_id', '6d100000-0000-0000-0000-000000000006',
      'client_id', '6d100000-0000-0000-0000-000000000002',
      'client_contact_method_id', '6d100000-0000-0000-0000-00000000000b'
    ),
    now(), 'communications', '6d100000-0000-0000-0000-00000000000a'
  ),
  null::uuid, 'a second delivery of the same document records its own event'
);
select is(public.intake_automation_events(25), 1, 'intake settles the second event');
select is(
  (select count(*)::integer from private.automation_enrollments
   where organization_id = '6d100000-0000-0000-0000-000000000001'),
  1, 'the same quote version and recipient never start a second reminder sequence'
);
select is(
  (select outcome from private.automation_event_matches as m
   join private.automation_events as e on e.id = m.event_id
   where m.recipe_id = '6d100000-0000-0000-0000-000000000010'
     and e.source_event_id = '6d100000-0000-0000-0000-00000000000a'),
  'already_enrolled', 'the second delivery says plainly why nothing started'
);

-- Emitting the identical source fact twice is a silent no-op, not an error.
select is(
  private.emit_automation_event(
    '6d100000-0000-0000-0000-000000000001', 'quote.delivery_succeeded', 'quote',
    '6d100000-0000-0000-0000-000000000004', '{}'::jsonb, now(),
    'communications', '6d100000-0000-0000-0000-00000000000a'
  ),
  null::uuid, 'a duplicate source fact collapses without raising'
);

select * from finish();

-- Single summary row, so a run through the Supabase MCP (which surfaces the last non-empty result set)
-- cannot hide a failure that scrolled past.
select case when num_failed() = 0 then 'ALL PASSED' else num_failed()::text || ' FAILED' end as result;

rollback;
