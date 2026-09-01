-- Automation Part 6F-1: Jobber Quote-follow-up parity.
--
-- Proves three behaviours the engine was missing:
--   1. The client's saved "quote follow-ups" preference is honoured at intake AND immediately before a send.
--   2. Live work stops as soon as the quote is no longer Awaiting response -- not only when a send is reached.
--   3. Day/hour waits are measured from the original send, cumulatively, at the same local time of day --
--      never from the moment a worker happened to pick the step up.

begin;

create extension if not exists pgtap with schema extensions;
select plan(26);

-- ---------------------------------------------------------------------------------------------------
-- The stop check stays internal.
-- ---------------------------------------------------------------------------------------------------
select ok(
  not has_function_privilege('anon', 'private.automation_quote_stop_outcome(uuid, uuid)', 'EXECUTE'),
  'anon cannot run the quote stop check');
select ok(
  not has_function_privilege('authenticated', 'private.automation_quote_stop_outcome(uuid, uuid)', 'EXECUTE'),
  'authenticated cannot run the quote stop check');
select col_not_null('private', 'automation_enrollments', 'anchor_at',
  'every enrollment carries the anchor its waits are measured from');

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: a published quote, a ready automated sender, entitlement, and the two-reminder recipe.
-- ---------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at)
values ('6f100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'owner-6f1@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('6f110000-0000-0000-0000-000000000001', 'Automation 6F-1', 'automation-6f1', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values ('6f110000-0000-0000-0000-000000000001', '6f100000-0000-0000-0000-000000000001', 'admin', 'active');

-- A real, non-UTC operational timezone, so "same local time of day" is actually exercised.
update public.organization_settings set timezone = 'America/Toronto'
where organization_id = '6f110000-0000-0000-0000-000000000001';

insert into public.clients (id, organization_id, display_name)
values ('6f120000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001', 'Follow-up Co');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('6f130000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001',
  '6f120000-0000-0000-0000-000000000001', 'email', 'customer@6f1.example', true);

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('6f140000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001',
  '6f120000-0000-0000-0000-000000000001', '1 Automation Way', 'Testville');

insert into public.communication_email_domains (id, organization_id, purpose, domain_name, lifecycle_state,
  provider_domain_id, provider_verified, provider_authenticated, ownership_status, dkim_status,
  dmarc_status, spf_status, inbound_mx_status, verified_at)
values ('6f150000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001',
  'sending', 'mail.6f1.example', 'verified', 63101, true, true, 'passing', 'passing',
  'passing', 'pending', 'unchecked', now());

insert into public.communication_email_senders (id, organization_id, domain_id, email_address, display_name,
  lifecycle_state, is_organization_default, allows_manual, allows_automated)
values ('6f160000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001',
  '6f150000-0000-0000-0000-000000000001', 'hello@mail.6f1.example', 'Automation 6F-1',
  'enabled', true, true, true);

insert into public.organization_feature_overrides (organization_id, feature_key, override_state, reason)
values ('6f110000-0000-0000-0000-000000000001', 'automations', 'on', 'Test fixture.');

select set_config('request.jwt.claim.sub', '6f100000-0000-0000-0000-000000000001', true);
select public.create_quote(
  '6f120000-0000-0000-0000-000000000001', '6f140000-0000-0000-0000-000000000001', '6F1 Quote', null);

create function pg_temp.qid() returns uuid language sql stable as
  'select id from public.quotes where title = ''6F1 Quote''';
create function pg_temp.qrev() returns integer language sql stable as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''6F1 Quote'')';

select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.qrev(),
  jsonb_build_array(jsonb_build_object('name', 'Line', 'category', 'service', 'quantity', 1,
    'unit_price_minor', 10000, 'unit_cost_minor', 4000, 'is_taxable', false)));
select public.set_quote_draft_tax(pg_temp.qid(), pg_temp.qrev(), 'no_tax');
select public.publish_quote(pg_temp.qid(), pg_temp.qrev());
select set_config('request.jwt.claim.sub', '', true);

set local role postgres;

-- The shipped preset shape: reminder one after 3 days, reminder two 4 days later (day 7 after the send).
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('6f1a0000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001',
  'Quote follow-up', 'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"amount":3,"unit":"days"}},{"type":"action","key":"action.send_email","config":{"subject":"Following up on {{quote_number}}","body":"Hi {{customer_name}} -- {{quote_link}}"}},{"type":"wait","key":"wait.relative_delay","config":{"amount":4,"unit":"days"}},{"type":"action","key":"action.send_email","config":{"subject":"Still interested in {{quote_number}}?","body":"Hi {{customer_name}} -- {{quote_link}}"}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb);

insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot)
values ('6f1b0000-0000-0000-0000-000000000001', '6f1a0000-0000-0000-0000-000000000001',
  '6f110000-0000-0000-0000-000000000001', 1, 1,
  (select draft_definition from public.automation_recipes where id = '6f1a0000-0000-0000-0000-000000000001'),
  'hash-6f1', 'quote.delivery_succeeded', 0, pg_current_snapshot());

update public.automation_recipes
set status = 'active', current_version_id = '6f1b0000-0000-0000-0000-000000000001',
  active_trigger_key = 'quote.delivery_succeeded'
where id = '6f1a0000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------------------------------
-- 1. Intake honours the saved follow-up preference.
-- ---------------------------------------------------------------------------------------------------
update public.client_communication_preferences set quote_follow_ups = false
where organization_id = '6f110000-0000-0000-0000-000000000001'
  and client_id = '6f120000-0000-0000-0000-000000000001';

insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
  occurred_at, source_module, source_event_id)
values ('6f1c0000-0000-0000-0000-000000000001', '6f110000-0000-0000-0000-000000000001',
  'quote.delivery_succeeded', 'quote', pg_temp.qid(),
  jsonb_build_object('quote_recipient_id', '6f1e0000-0000-0000-0000-000000000001'),
  now() - interval '10 days', 'communications', '6f1c0000-0000-0000-0000-0000000000aa');

select ok(public.intake_automation_events(50) >= 1, 'intake processes the declined-preference event');

select is(
  (select outcome from private.automation_event_matches
   where event_id = '6f1c0000-0000-0000-0000-000000000001'),
  'follow_ups_declined', 'a client who declined quote follow-ups is recorded, not enrolled');

select is(
  (select count(*)::integer from private.automation_enrollments
   where organization_id = '6f110000-0000-0000-0000-000000000001'),
  0, 'no enrollment is created for a client who declined follow-ups');

update public.client_communication_preferences set quote_follow_ups = true
where organization_id = '6f110000-0000-0000-0000-000000000001'
  and client_id = '6f120000-0000-0000-0000-000000000001';

insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
  occurred_at, source_module, source_event_id)
values ('6f1c0000-0000-0000-0000-000000000002', '6f110000-0000-0000-0000-000000000001',
  'quote.delivery_succeeded', 'quote', pg_temp.qid(),
  jsonb_build_object('quote_recipient_id', '6f1e0000-0000-0000-0000-000000000002'),
  now() - interval '10 days', 'communications', '6f1c0000-0000-0000-0000-0000000000bb');

select ok(public.intake_automation_events(50) >= 1, 'intake processes the allowed event');

select is(
  (select outcome from private.automation_event_matches
   where event_id = '6f1c0000-0000-0000-0000-000000000002'),
  'enrolled', 'a client who allows quote follow-ups enrolls');

create function pg_temp.eid() returns uuid language sql stable as
  'select id from private.automation_enrollments
   where trigger_event_id = ''6f1c0000-0000-0000-0000-000000000002''';

select is(
  (select anchor_at from private.automation_enrollments where id = pg_temp.eid()),
  (select occurred_at from private.automation_events where id = '6f1c0000-0000-0000-0000-000000000002'),
  'the enrollment anchors on the original send, not on when intake ran');

-- ---------------------------------------------------------------------------------------------------
-- 2. Waits are measured from the original send, cumulatively, at the same local time of day.
-- ---------------------------------------------------------------------------------------------------
update private.automation_work_items
set claim_token = '6f1f0000-0000-0000-0000-000000000001', claimed_at = now()
where enrollment_id = pg_temp.eid() and step_index = 0;

select is(
  public.advance_automation_work_item(
    (select id from private.automation_work_items where enrollment_id = pg_temp.eid() and step_index = 0),
    '6f1f0000-0000-0000-0000-000000000001'),
  'waiting', 'the first step is a wait');

create function pg_temp.due(p_step integer) returns timestamptz language sql stable as
  'select due_at from private.automation_work_items
   where enrollment_id = (select id from private.automation_enrollments
     where trigger_event_id = ''6f1c0000-0000-0000-0000-000000000002'') and step_index = $1';

create function pg_temp.anchor() returns timestamptz language sql stable as
  'select anchor_at from private.automation_enrollments
   where trigger_event_id = ''6f1c0000-0000-0000-0000-000000000002''';

select is(pg_temp.due(1), pg_temp.anchor() + interval '3 days',
  'reminder one is due three days after the original send');

select ok(pg_temp.due(1) < now(),
  'a send that should already have happened stays overdue instead of being pushed three days out');

select is(
  (pg_temp.due(1) at time zone 'America/Toronto')::time,
  (pg_temp.anchor() at time zone 'America/Toronto')::time,
  'the reminder keeps the local time of day the quote was sent at');

-- Reminder two: the recipe waits four more days, so it lands on day seven after the send, not day seven
-- after whenever the worker processed the previous step.
update private.automation_enrollments set current_step_index = 2 where id = pg_temp.eid();
insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at,
  claim_token, claimed_at)
values ('6f110000-0000-0000-0000-000000000001', pg_temp.eid(), 2, now(), now(),
  '6f1f0000-0000-0000-0000-000000000002', now());

select is(
  public.advance_automation_work_item(
    (select id from private.automation_work_items where enrollment_id = pg_temp.eid() and step_index = 2),
    '6f1f0000-0000-0000-0000-000000000002'),
  'waiting', 'the third step is a wait');

select is(pg_temp.due(3), pg_temp.anchor() + interval '7 days',
  'reminder two is due seven days after the original send, not seven days after the last worker run');

-- ---------------------------------------------------------------------------------------------------
-- 3. Live work stops the moment the quote stops awaiting a response.
-- ---------------------------------------------------------------------------------------------------
insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
  occurred_at, source_module, source_event_id, processed_at)
values ('6f1c0000-0000-0000-0000-000000000003', '6f110000-0000-0000-0000-000000000001',
  'quote.delivery_succeeded', 'quote', pg_temp.qid(), '{}'::jsonb, now(),
  'communications', '6f1c0000-0000-0000-0000-0000000000cc', now());

insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, trigger_event_id, source, re_entry_key, context, anchor_at)
values ('6f1d0000-0000-0000-0000-000000000003', '6f110000-0000-0000-0000-000000000001',
  '6f1a0000-0000-0000-0000-000000000001', '6f1b0000-0000-0000-0000-000000000001', 'quote',
  pg_temp.qid(), '6f1c0000-0000-0000-0000-000000000003', 'event', 'entry-3', '{}'::jsonb, now());
insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at,
  available_at, claim_token, claimed_at)
values ('6f1e0000-0000-0000-0000-000000000003', '6f110000-0000-0000-0000-000000000001',
  '6f1d0000-0000-0000-0000-000000000003', 0, now(), now(),
  '6f1f0000-0000-0000-0000-000000000003', now());

update public.quotes set status = 'approved' where id = pg_temp.qid();

select is(
  public.advance_automation_work_item('6f1e0000-0000-0000-0000-000000000003',
    '6f1f0000-0000-0000-0000-000000000003'),
  'stop_condition_met', 'an approved quote stops the enrollment at the very next transition');

select is(
  (select state || ':' || stop_reason from private.automation_enrollments
   where id = '6f1d0000-0000-0000-0000-000000000003'),
  'stopped:quote_not_awaiting_response', 'the stop records why, so history can explain it');

select is(
  (select state from private.automation_work_items where id = '6f1e0000-0000-0000-0000-000000000003'),
  'cancelled', 'the pending step is cancelled, not left waiting');

select is(
  (public.enqueue_automation_quote_email('6f110000-0000-0000-0000-000000000001', pg_temp.qid(),
    'automation-6f1-approved', 'S', 'B {{quote_link}}', 'https://app.example.test/q/t',
    decode(repeat('ab', 32), 'hex'))) ->> 'reason',
  'quote_not_awaiting_response', 'the send refuses an approved quote permanently');

select is(
  (select count(*)::integer from public.communication_delivery_intents
   where logical_send_key = 'automation-6f1-approved'),
  0, 'nothing is enqueued for a quote that no longer awaits a response');

update public.quotes set status = 'awaiting_response' where id = pg_temp.qid();

-- ---------------------------------------------------------------------------------------------------
-- 4. A preference switched off mid-sequence stops live work and blocks the send.
-- ---------------------------------------------------------------------------------------------------
insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
  occurred_at, source_module, source_event_id, processed_at)
values ('6f1c0000-0000-0000-0000-000000000004', '6f110000-0000-0000-0000-000000000001',
  'quote.delivery_succeeded', 'quote', pg_temp.qid(), '{}'::jsonb, now(),
  'communications', '6f1c0000-0000-0000-0000-0000000000dd', now());

insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, trigger_event_id, source, re_entry_key, context, anchor_at)
values ('6f1d0000-0000-0000-0000-000000000004', '6f110000-0000-0000-0000-000000000001',
  '6f1a0000-0000-0000-0000-000000000001', '6f1b0000-0000-0000-0000-000000000001', 'quote',
  pg_temp.qid(), '6f1c0000-0000-0000-0000-000000000004', 'event', 'entry-4', '{}'::jsonb, now());
insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at,
  available_at, claim_token, claimed_at)
values ('6f1e0000-0000-0000-0000-000000000004', '6f110000-0000-0000-0000-000000000001',
  '6f1d0000-0000-0000-0000-000000000004', 0, now(), now(),
  '6f1f0000-0000-0000-0000-000000000004', now());

update public.client_communication_preferences set quote_follow_ups = false
where organization_id = '6f110000-0000-0000-0000-000000000001'
  and client_id = '6f120000-0000-0000-0000-000000000001';

select is(
  public.advance_automation_work_item('6f1e0000-0000-0000-0000-000000000004',
    '6f1f0000-0000-0000-0000-000000000004'),
  'stop_condition_met', 'turning the preference off stops live work at the next transition');

select is(
  (select stop_reason from private.automation_enrollments
   where id = '6f1d0000-0000-0000-0000-000000000004'),
  'follow_ups_declined', 'the stop names the customer preference');

select is(
  (public.enqueue_automation_quote_email('6f110000-0000-0000-0000-000000000001', pg_temp.qid(),
    'automation-6f1-declined', 'S', 'B {{quote_link}}', 'https://app.example.test/q/t',
    decode(repeat('ab', 32), 'hex'))) ->> 'reason',
  'follow_ups_declined', 'the send refuses a client who declined follow-ups');

select is(
  (select count(*)::integer from public.communication_delivery_intents
   where logical_send_key = 'automation-6f1-declined'),
  0, 'nothing is enqueued for a client who declined follow-ups');

-- ---------------------------------------------------------------------------------------------------
-- 5. A still-eligible quote is untouched by any of this.
-- ---------------------------------------------------------------------------------------------------
update public.client_communication_preferences set quote_follow_ups = true
where organization_id = '6f110000-0000-0000-0000-000000000001'
  and client_id = '6f120000-0000-0000-0000-000000000001';

select is(
  private.automation_quote_stop_outcome('6f110000-0000-0000-0000-000000000001', pg_temp.qid()),
  null::text, 'an awaiting-response quote whose client allows follow-ups has no stop reason');

select is(
  private.automation_quote_stop_outcome('6f110000-0000-0000-0000-000000000001',
    '6f190000-0000-0000-0000-0000000000ff'),
  'quote_not_sendable', 'a quote that no longer exists stops the enrollment');

select * from finish();
rollback;
