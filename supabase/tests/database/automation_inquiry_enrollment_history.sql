-- CRM launch readiness Part 4, Stage 6: a website inquiry's follow-up history on its Request or chat session.
--
-- Covers: a staff Pause records "staff", a customer-reply pause records "customer_reply", leaving paused clears
-- it; the read finds the enrollment behind a Request (through its form submission) and behind a chat session,
-- never another organization's, and reports why the next step is held; browser roles cannot call it.

begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('4b600000-0000-0000-0000-000000000001', 'History Test', 'inquiry-history-test', 'active'),
  ('4b600000-0000-0000-0000-000000000002', 'Other Org', 'inquiry-history-other', 'active');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values ('4b600000-0000-0000-0000-00000000000a', '4b600000-0000-0000-0000-000000000001', 'Form Lead', 'lead');

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4b600000-0000-0000-0000-000000000003', '4b600000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'inquiry-history-test-form');
insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4b600000-0000-0000-0000-000000000004', '4b600000-0000-0000-0000-000000000001',
  '4b600000-0000-0000-0000-000000000003', 1, 'Get a quote');

insert into private.form_submissions (
  id, organization_id, form_id, form_version_id, idempotency_key, contact, status, processed_at, result
) values
  ('4b600000-0000-0000-0000-0000000000fa', '4b600000-0000-0000-0000-000000000001',
   '4b600000-0000-0000-0000-000000000003', '4b600000-0000-0000-0000-000000000004', 'history-a', '{}'::jsonb,
   'processed', now(),
   '{"outcome":"request","client_id":"4b600000-0000-0000-0000-00000000000a","request_id":"4b600000-0000-0000-0000-0000000000aa"}'::jsonb);

insert into public.website_chat_widgets (id, organization_id, name)
values ('4b600000-0000-0000-0000-000000000005', '4b600000-0000-0000-0000-000000000001', 'Main site');
insert into public.website_chat_sessions (
  id, organization_id, widget_id, client_id, match_status, visitor_name, submitted_email, normalized_email,
  session_token_hash, idempotency_key
) values
  ('4b600000-0000-0000-0000-0000000000cb', '4b600000-0000-0000-0000-000000000001',
   '4b600000-0000-0000-0000-000000000005', null, 'needs_review', 'Chat Lead',
   'chat@example.test', 'chat@example.test', repeat('c', 64), 'history-chat-b');

insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('4b600000-0000-0000-0000-000000000010', '4b600000-0000-0000-0000-000000000001', 'Quick reply',
  'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"minutes","amount":5}},{"type":"action","key":"action.send_customer_message","config":{"email_subject":"Hi","email_body":"Thanks"}}],"stops":[]}'::jsonb);
insert into public.automation_recipe_versions (
  id, recipe_id, organization_id, version_number, schema_version, definition, definition_hash, trigger_key,
  activation_cutoff_sequence
)
select '4b600000-0000-0000-0000-000000000011', id, organization_id, 1, 1, draft_definition, 'hash',
  'website_inquiry.received', 0
from public.automation_recipes where id = '4b600000-0000-0000-0000-000000000010';
update public.automation_recipes
set status = 'active', current_version_id = '4b600000-0000-0000-0000-000000000011',
  active_trigger_key = 'website_inquiry.received'
where id = '4b600000-0000-0000-0000-000000000010';

insert into private.automation_enrollments (
  id, organization_id, recipe_id, recipe_version_id, subject_type, subject_id, source, re_entry_key, context,
  anchor_at
)
select e.id, '4b600000-0000-0000-0000-000000000001', '4b600000-0000-0000-0000-000000000010',
  '4b600000-0000-0000-0000-000000000011', e.subject_type, e.subject_id, 'manual',
  e.subject_type || ':' || e.subject_id, '{}'::jsonb, now()
from (values
  ('4b600000-0000-0000-0000-0000000000ea'::uuid, 'form_submission', '4b600000-0000-0000-0000-0000000000fa'::uuid),
  ('4b600000-0000-0000-0000-0000000000eb'::uuid, 'website_chat_session', '4b600000-0000-0000-0000-0000000000cb'::uuid)
) as e(id, subject_type, subject_id);

insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at,
  last_error_code)
values
  ('4b600000-0000-0000-0000-000000000001', '4b600000-0000-0000-0000-0000000000ea', 1, now() + interval '5 minutes',
   now() + interval '5 minutes', 'email_sender_not_ready'),
  ('4b600000-0000-0000-0000-000000000001', '4b600000-0000-0000-0000-0000000000eb', 1, now() + interval '5 minutes',
   now() + interval '5 minutes', null);

-- ---------------------------------------------------------------------------------------------------
-- Pause reason
-- ---------------------------------------------------------------------------------------------------
select public.pause_automation_enrollment('4b600000-0000-0000-0000-000000000001', gen_random_uuid(),
  '4b600000-0000-0000-0000-0000000000eb', gen_random_uuid());
select is((select paused_reason from private.automation_enrollments where id = '4b600000-0000-0000-0000-0000000000eb'),
  'staff', 'a staff Pause records staff');

select public.resume_automation_enrollment('4b600000-0000-0000-0000-000000000001', gen_random_uuid(),
  '4b600000-0000-0000-0000-0000000000eb', gen_random_uuid());
select is((select paused_reason from private.automation_enrollments where id = '4b600000-0000-0000-0000-0000000000eb'),
  null, 'Resume clears the pause reason');

-- The engine's reply-pause shape (Stage 3): paused while moving customer_reply_after.
update private.automation_enrollments
set state = 'paused', paused_work_due_at = now() + interval '5 minutes', customer_reply_after = now()
where id = '4b600000-0000-0000-0000-0000000000eb';
select is((select paused_reason from private.automation_enrollments where id = '4b600000-0000-0000-0000-0000000000eb'),
  'customer_reply', 'a customer-reply pause records customer_reply');

update private.automation_enrollments set stop_reason = 'staff_replied'
where id = '4b600000-0000-0000-0000-0000000000eb';
select is((select paused_reason from private.automation_enrollments where id = '4b600000-0000-0000-0000-0000000000eb'),
  'customer_reply', 'an update that does not change state keeps the reason');

-- ---------------------------------------------------------------------------------------------------
-- The read
-- ---------------------------------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.automation_inquiry_enrollments('4b600000-0000-0000-0000-000000000001',
    '4b600000-0000-0000-0000-0000000000aa', null)),
  1, 'a Request finds the follow-up of the form submission it came from');

select results_eq(
  $$select subject_type, state, held_reason, next_due_at is not null
    from public.automation_inquiry_enrollments('4b600000-0000-0000-0000-000000000001',
      '4b600000-0000-0000-0000-0000000000aa', null)$$,
  $$values ('form_submission'::text, 'active'::text, 'email_sender_not_ready'::text, true)$$,
  'the Request read reports subject, state, why the next step is held, and when it is due');

select results_eq(
  $$select subject_type, state, paused_reason
    from public.automation_inquiry_enrollments('4b600000-0000-0000-0000-000000000001', null,
      '4b600000-0000-0000-0000-0000000000cb')$$,
  $$values ('website_chat_session'::text, 'paused'::text, 'customer_reply'::text)$$,
  'a chat session finds its own follow-up with the pause reason');

update private.automation_work_items set state = 'needs_attention', attention_reason = 'action_not_available',
  attention_at = now()
where enrollment_id = '4b600000-0000-0000-0000-0000000000ea';
select is(
  (select held_reason from public.automation_inquiry_enrollments('4b600000-0000-0000-0000-000000000001',
    '4b600000-0000-0000-0000-0000000000aa', null)),
  'action_not_available', 'a step needing attention is reported');

select is(
  (select count(*)::integer from public.automation_inquiry_enrollments('4b600000-0000-0000-0000-000000000002',
    '4b600000-0000-0000-0000-0000000000aa', '4b600000-0000-0000-0000-0000000000cb')),
  0, 'another organization sees nothing');

select is(
  (select count(*)::integer from public.automation_inquiry_enrollments('4b600000-0000-0000-0000-000000000001',
    '4b600000-0000-0000-0000-0000000000ff', null)),
  0, 'an unrelated Request sees nothing');

select ok(
  not has_function_privilege('authenticated', 'public.automation_inquiry_enrollments(uuid, uuid, uuid, integer)',
    'execute'),
  'signed-in browsers cannot call the read directly');
select ok(
  not has_function_privilege('anon', 'public.automation_inquiry_enrollments(uuid, uuid, uuid, integer)', 'execute'),
  'anonymous visitors cannot call the read');

select * from finish();
rollback;
