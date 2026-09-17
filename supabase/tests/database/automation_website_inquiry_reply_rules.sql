-- CRM launch readiness Part 4, Stage 3: a website inquiry's follow-up stops on a delivered staff reply and
-- pauses its customer-facing steps on a customer reply to what it already sent.
--
-- Covers: only a delivered, staff-sent message stops (not automated, not merely accepted, not from before the
-- inquiry); a staff chat message stops; a second visitor message before anything was sent is not a reply;
-- a real reply pauses at the customer step, keeps its due time and survives Resume without re-pausing; an
-- auto-response never pauses; a wait is never paused.

begin;

create extension if not exists pgtap with schema extensions;
select plan(17);

set local role postgres;

-- ---------------------------------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status)
values ('4b100000-0000-0000-0000-000000000001', 'Reply Rules Test', 'reply-rules-test', 'active');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values
  ('4b100000-0000-0000-0000-00000000000a', '4b100000-0000-0000-0000-000000000001', 'Form Lead', 'lead'),
  ('4b100000-0000-0000-0000-00000000000b', '4b100000-0000-0000-0000-000000000001', 'Chat Lead', 'lead'),
  ('4b100000-0000-0000-0000-00000000000d', '4b100000-0000-0000-0000-000000000001', 'Texting Lead', 'lead');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('4b100000-0000-0000-0000-0000000000a1', '4b100000-0000-0000-0000-000000000001',
   '4b100000-0000-0000-0000-00000000000a', 'phone', '+15555550101', true),
  ('4b100000-0000-0000-0000-0000000000d1', '4b100000-0000-0000-0000-000000000001',
   '4b100000-0000-0000-0000-00000000000d', 'phone', '+15555550104', true);

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4b100000-0000-0000-0000-000000000003', '4b100000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'reply-rules-test-form');
insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4b100000-0000-0000-0000-000000000004', '4b100000-0000-0000-0000-000000000001',
  '4b100000-0000-0000-0000-000000000003', 1, 'Get a quote');

insert into private.form_submissions (
  id, organization_id, form_id, form_version_id, idempotency_key, contact, status, processed_at, result
) values
  ('4b100000-0000-0000-0000-0000000000fa', '4b100000-0000-0000-0000-000000000001',
   '4b100000-0000-0000-0000-000000000003', '4b100000-0000-0000-0000-000000000004', 'reply-a', '{}'::jsonb,
   'processed', now(), '{"outcome":"request","client_id":"4b100000-0000-0000-0000-00000000000a"}'::jsonb),
  ('4b100000-0000-0000-0000-0000000000fd', '4b100000-0000-0000-0000-000000000001',
   '4b100000-0000-0000-0000-000000000003', '4b100000-0000-0000-0000-000000000004', 'reply-d', '{}'::jsonb,
   'processed', now(), '{"outcome":"request","client_id":"4b100000-0000-0000-0000-00000000000d"}'::jsonb);

insert into public.website_chat_widgets (id, organization_id, name)
values ('4b100000-0000-0000-0000-000000000005', '4b100000-0000-0000-0000-000000000001', 'Main site');

insert into public.website_chat_sessions (
  id, organization_id, widget_id, client_id, match_status, visitor_name, submitted_email, normalized_email,
  session_token_hash, idempotency_key
) values
  ('4b100000-0000-0000-0000-0000000000cb', '4b100000-0000-0000-0000-000000000001',
   '4b100000-0000-0000-0000-000000000005', '4b100000-0000-0000-0000-00000000000b', 'resolved', 'Chat Lead',
   'chat@example.test', 'chat@example.test', repeat('b', 64), 'reply-chat-b'),
  ('4b100000-0000-0000-0000-0000000000cc', '4b100000-0000-0000-0000-000000000001',
   '4b100000-0000-0000-0000-000000000005', null, 'needs_review', 'Unsure Visitor',
   'unsure@example.test', 'unsure@example.test', repeat('e', 64), 'reply-chat-c');

-- One active recipe: wait 5 minutes, then text the customer.
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('4b100000-0000-0000-0000-000000000010', '4b100000-0000-0000-0000-000000000001', 'Speed to lead',
  'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"minutes","amount":5}},{"type":"action","key":"action.send_sms","config":{}}],"stops":[]}'::jsonb);
insert into public.automation_recipe_versions (
  id, recipe_id, organization_id, version_number, schema_version, definition, definition_hash, trigger_key,
  activation_cutoff_sequence
)
select '4b100000-0000-0000-0000-000000000011', id, organization_id, 1, 1, draft_definition, 'hash',
  'website_inquiry.received', 0
from public.automation_recipes where id = '4b100000-0000-0000-0000-000000000010';
update public.automation_recipes
set status = 'active', current_version_id = '4b100000-0000-0000-0000-000000000011',
  active_trigger_key = 'website_inquiry.received'
where id = '4b100000-0000-0000-0000-000000000010';

-- Enrollments anchored ten minutes ago: A (form, client A), B (chat, client B), C (chat needing review),
-- D (form, client D).
insert into private.automation_enrollments (
  id, organization_id, recipe_id, recipe_version_id, subject_type, subject_id, source, re_entry_key, context,
  anchor_at
)
select e.id, '4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-000000000010',
  '4b100000-0000-0000-0000-000000000011', e.subject_type, e.subject_id, 'manual',
  e.subject_type || ':' || e.subject_id, '{}'::jsonb, now() - interval '10 minutes'
from (values
  ('4b100000-0000-0000-0000-0000000000ea'::uuid, 'form_submission', '4b100000-0000-0000-0000-0000000000fa'::uuid),
  ('4b100000-0000-0000-0000-0000000000eb'::uuid, 'website_chat_session', '4b100000-0000-0000-0000-0000000000cb'::uuid),
  ('4b100000-0000-0000-0000-0000000000ec'::uuid, 'website_chat_session', '4b100000-0000-0000-0000-0000000000cc'::uuid),
  ('4b100000-0000-0000-0000-0000000000ed'::uuid, 'form_submission', '4b100000-0000-0000-0000-0000000000fd'::uuid)
) as e(id, subject_type, subject_id);

-- Claims one fresh item at a step and returns its advance outcome.
create function pg_temp.advance_at(p_enrollment uuid, p_step integer)
returns text language plpgsql as $$
declare
  token uuid := gen_random_uuid();
  item_id uuid;
begin
  insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at,
    claim_token, claimed_at)
  values ('4b100000-0000-0000-0000-000000000001', p_enrollment, p_step, now() - interval '1 minute', now(),
    token, now())
  on conflict (enrollment_id, step_index) do update
    set state = 'pending', claim_token = excluded.claim_token, claimed_at = now()
  returning id into item_id;
  return public.advance_automation_work_item(item_id, token);
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Stop on a delivered staff reply
-- ---------------------------------------------------------------------------------------------------
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ea', 0), 'waiting',
  'with no replies the wait proceeds');

insert into public.communication_delivery_intents (
  organization_id, client_id, client_contact_method_id, channel, logical_send_key, recipient_phone, send_kind,
  delivery_outcome, created_at
) values
  ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-00000000000a',
   '4b100000-0000-0000-0000-0000000000a1', 'sms', 'reply-rules-automated', '+15555550101', 'automated',
   'sms_delivered', now()),
  ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-00000000000a',
   '4b100000-0000-0000-0000-0000000000a1', 'sms', 'reply-rules-before-inquiry', '+15555550101', 'manual',
   'sms_delivered', now() - interval '1 hour'),
  ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-00000000000a',
   '4b100000-0000-0000-0000-0000000000a1', 'sms', 'reply-rules-staff', '+15555550101', 'manual',
   null, now());

select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ea', 1), 'action_due_sms',
  'an automated send, an older staff text and a not-yet-delivered staff text do not stop the follow-up');

update public.communication_delivery_intents set delivery_outcome = 'sms_delivered'
where logical_send_key = 'reply-rules-staff';

select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ea', 1), 'stop_condition_met',
  'a delivered staff text stops the pending follow-up');
select is(
  (select state || '|' || stop_reason from private.automation_enrollments
   where id = '4b100000-0000-0000-0000-0000000000ea'),
  'stopped|staff_replied', 'the enrollment records that staff replied'
);

insert into public.website_chat_messages (organization_id, session_id, client_id, direction, sender_type, body)
values ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-0000000000cb',
  '4b100000-0000-0000-0000-00000000000b', 'outbound', 'automation', 'Thanks, we got your message.');
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000eb', 0), 'waiting',
  'an automation chat message is not a staff reply');

insert into public.website_chat_messages (organization_id, session_id, client_id, direction, sender_type, body)
values ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-0000000000cb',
  '4b100000-0000-0000-0000-00000000000b', 'outbound', 'staff', 'Hi, this is Sam. When suits you?');
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000eb', 1), 'stop_condition_met',
  'a staff chat reply stops even during a wait-then-text sequence');

-- ---------------------------------------------------------------------------------------------------
-- Pause on a customer reply, only after this enrollment reached the customer
-- ---------------------------------------------------------------------------------------------------
insert into public.website_chat_messages (organization_id, session_id, direction, sender_type, body)
values ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-0000000000cc', 'inbound', 'visitor',
  'Also, it is a two storey house.');

select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ec', 1), 'action_due_sms',
  'a visitor adding detail before anything was sent to them does not pause the follow-up');

update private.automation_enrollments set customer_reply_after = now() - interval '5 minutes'
where id = '4b100000-0000-0000-0000-0000000000ec';

select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ec', 0), 'waiting',
  'a customer reply never pauses an internal wait');
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ec', 1), 'paused_customer_reply',
  'a customer reply to what was sent pauses the customer-facing step');
select is(
  (select state || '|' || current_step_index || '|' || (paused_work_due_at = now() - interval '1 minute')
     || '|' || (customer_reply_after = now())
   from private.automation_enrollments where id = '4b100000-0000-0000-0000-0000000000ec'),
  'paused|1|true|true', 'the pause keeps the step and its due time and remembers the reply it handled'
);
select is(
  (select state from private.automation_work_items
   where enrollment_id = '4b100000-0000-0000-0000-0000000000ec' and step_index = 1),
  'cancelled', 'the paused step leaves the queue'
);

select is(
  (public.resume_automation_enrollment('4b100000-0000-0000-0000-000000000001', gen_random_uuid(),
    '4b100000-0000-0000-0000-0000000000ec', gen_random_uuid())) ->> 'state',
  'active', 'staff can resume the reply-paused enrollment'
);
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ec', 1), 'action_due_sms',
  'after Resume the same reply does not pause it again');

-- Inbound texts matched to the form lead's client.
update private.automation_enrollments set customer_reply_after = now() - interval '5 minutes'
where id = '4b100000-0000-0000-0000-0000000000ed';

insert into public.communication_inbound_messages (
  organization_id, client_id, client_contact_method_id, channel, provider, sender_phone, subject, text_content,
  message_kind
) values ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-00000000000d',
  '4b100000-0000-0000-0000-0000000000d1', 'sms', 'twilio', '+15555550104', '', 'Away right now',
  'auto_response');
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ed', 1), 'action_due_sms',
  'an automatic response is not a customer reply');

insert into public.communication_inbound_messages (
  organization_id, client_id, client_contact_method_id, channel, provider, sender_phone, subject, text_content
) values ('4b100000-0000-0000-0000-000000000001', '4b100000-0000-0000-0000-00000000000d',
  '4b100000-0000-0000-0000-0000000000d1', 'sms', 'twilio', '+15555550104', '', 'Yes please call me');
select is(pg_temp.advance_at('4b100000-0000-0000-0000-0000000000ed', 1), 'paused_customer_reply',
  'a customer text reply pauses the form inquiry follow-up');

select is(
  private.automation_inquiry_stop_outcome('4b100000-0000-0000-0000-000000000001', 'form_submission',
    gen_random_uuid(), now()),
  'inquiry_not_found', 'a missing inquiry stops'
);
select is(
  private.automation_inquiry_customer_reply_at('4b100000-0000-0000-0000-000000000001', 'form_submission',
    '4b100000-0000-0000-0000-0000000000fd', null),
  null::timestamptz, 'nothing counts as a reply before the enrollment reached the customer'
);

select * from finish();
rollback;
