-- CRM launch readiness Part 4, Stage 4: every website inquiry alerts the team.
--
-- Covers: owner-only fallback when nobody is chosen; a replayed event never alerts twice; only people who can
-- see every inquiry may be chosen, and only by someone who manages connections; chosen people replace the
-- owner; a chosen person losing access falls back to the owner; a customer-reply pause alerts, a staff pause
-- does not; the email queue skips people who no longer qualify, retries with backoff and stops at five tries;
-- marking read touches only the caller's alerts; a person reads only their own alerts.

begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

set local role postgres;

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: owner, admin, office (no team inbox), office granted the team inbox.
-- ---------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at,
  updated_at)
values
  ('4c000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'owner-4c@example.test', 'test', now(), now(), now()),
  ('4c000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'admin-4c@example.test', 'test', now(), now(), now()),
  ('4c000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'office-4c@example.test', 'test', now(), now(), now()),
  ('4c000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'office-inbox-4c@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('4c100000-0000-0000-0000-000000000001', 'Inquiry Alerts Test', 'inquiry-alerts-test', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('4c100000-0000-0000-0000-000000000001', '4c000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('4c100000-0000-0000-0000-000000000001', '4c000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('4c100000-0000-0000-0000-000000000001', '4c000000-0000-0000-0000-000000000003', 'office', 'active'),
  ('4c100000-0000-0000-0000-000000000001', '4c000000-0000-0000-0000-000000000004', 'office', 'active');

insert into public.organization_member_permission_overrides (organization_id, user_id, permission_key,
  override_state)
values ('4c100000-0000-0000-0000-000000000001', '4c000000-0000-0000-0000-000000000004',
  'conversations.view_team', 'grant');

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4c100000-0000-0000-0000-000000000003', '4c100000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'inquiry-alerts-test-form');
insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4c100000-0000-0000-0000-000000000004', '4c100000-0000-0000-0000-000000000001',
  '4c100000-0000-0000-0000-000000000003', 1, 'Get a quote');

insert into public.website_chat_widgets (id, organization_id, name)
values ('4c100000-0000-0000-0000-000000000005', '4c100000-0000-0000-0000-000000000001', 'Main site');

create function pg_temp.alerts(p_source text)
returns bigint language sql as $$
  select count(*) from public.team_notifications
  where organization_id = '4c100000-0000-0000-0000-000000000001' and source_key = p_source;
$$;

create function pg_temp.new_chat(p_id uuid, p_name text)
returns void language sql as $$
  insert into public.website_chat_sessions (id, organization_id, widget_id, match_status, visitor_name,
    submitted_email, normalized_email, session_token_hash, idempotency_key)
  values (p_id, '4c100000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000005', 'needs_review',
    p_name, p_id::text || '@example.test', p_id::text || '@example.test', md5(p_id::text) || md5(p_name),
    p_id::text);
$$;

-- ---------------------------------------------------------------------------------------------------
-- Nobody chosen: the owner only
-- ---------------------------------------------------------------------------------------------------
select pg_temp.new_chat('4c100000-0000-0000-0000-0000000000c1', 'Sam Visitor');

select is(
  (select array_agg(user_id) from public.team_notifications
   where source_key = 'inquiry:website_chat_session:4c100000-0000-0000-0000-0000000000c1'),
  array['4c000000-0000-0000-0000-000000000001'::uuid],
  'with nobody chosen, a new chat alerts only the account owner'
);

select is(
  (select title || ' | ' || body from public.team_notifications
   where source_key = 'inquiry:website_chat_session:4c100000-0000-0000-0000-0000000000c1'),
  'New website inquiry from Sam Visitor | Started a Website Chat.',
  'the chat alert names the visitor'
);

select private.emit_automation_event('4c100000-0000-0000-0000-000000000001', 'website_inquiry.received',
  'website_chat_session', '4c100000-0000-0000-0000-0000000000c1', '{}'::jsonb, now(), 'website_chat',
  '4c100000-0000-0000-0000-0000000000c1');
select is(pg_temp.alerts('inquiry:website_chat_session:4c100000-0000-0000-0000-0000000000c1'), 1::bigint,
  'a replayed inquiry event never alerts twice');

-- ---------------------------------------------------------------------------------------------------
-- Choosing recipients
-- ---------------------------------------------------------------------------------------------------
select throws_ok(
  $$ select public.set_inquiry_alert_recipients('4c100000-0000-0000-0000-000000000001',
       '4c000000-0000-0000-0000-000000000001', array['4c000000-0000-0000-0000-000000000003'::uuid]) $$,
  '23514', 'Someone chosen cannot see every website inquiry.',
  'a member who cannot see the team inbox cannot be chosen'
);

select throws_ok(
  $$ select public.set_inquiry_alert_recipients('4c100000-0000-0000-0000-000000000001',
       '4c000000-0000-0000-0000-000000000003', array['4c000000-0000-0000-0000-000000000002'::uuid]) $$,
  '42501', 'You do not have permission to change inquiry alerts.',
  'only someone who manages connections may choose recipients'
);

select is(
  public.set_inquiry_alert_recipients('4c100000-0000-0000-0000-000000000001',
    '4c000000-0000-0000-0000-000000000001',
    array['4c000000-0000-0000-0000-000000000002'::uuid, '4c000000-0000-0000-0000-000000000004'::uuid,
      '4c000000-0000-0000-0000-000000000004'::uuid]),
  2, 'an admin and a granted office member can be chosen; duplicates collapse'
);

select is(
  public.set_inquiry_alert_recipients('4c100000-0000-0000-0000-000000000001',
    '4c000000-0000-0000-0000-000000000001', array['4c000000-0000-0000-0000-000000000002'::uuid]),
  1, 'saving again replaces the whole set'
);

select is(
  (select array_agg(user_id) from public.inquiry_alert_recipients
   where organization_id = '4c100000-0000-0000-0000-000000000001'),
  array['4c000000-0000-0000-0000-000000000002'::uuid],
  'the removed person is no longer chosen'
);

-- A processed form submission now alerts the chosen admin instead of the owner.
insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact,
  status)
values ('4c100000-0000-0000-0000-0000000000f1', '4c100000-0000-0000-0000-000000000001',
  '4c100000-0000-0000-0000-000000000003', '4c100000-0000-0000-0000-000000000004', 'alerts-f1',
  '{"name":"Jamie Lead"}'::jsonb, 'pending');

select is(pg_temp.alerts('inquiry:form_submission:4c100000-0000-0000-0000-0000000000f1'), 0::bigint,
  'a submission still being processed does not alert yet');

update private.form_submissions set status = 'processed', processed_at = now(), result = '{"outcome":"request"}'
where id = '4c100000-0000-0000-0000-0000000000f1';

select is(
  (select array_agg(user_id) from public.team_notifications
   where source_key = 'inquiry:form_submission:4c100000-0000-0000-0000-0000000000f1'),
  array['4c000000-0000-0000-0000-000000000002'::uuid],
  'a processed form alerts the chosen person, not the owner'
);

select is(
  (select title || ' | ' || body from public.team_notifications
   where source_key = 'inquiry:form_submission:4c100000-0000-0000-0000-0000000000f1'),
  'New website inquiry from Jamie Lead | Sent the Get a quote form.',
  'the form alert names the person and the form'
);

-- The chosen admin is deactivated: nobody chosen still qualifies, so the owner is alerted.
update public.organization_members set status = 'deactivated', deactivated_at = now()
where user_id = '4c000000-0000-0000-0000-000000000002';

select pg_temp.new_chat('4c100000-0000-0000-0000-0000000000c2', 'Pat Visitor');
select is(
  (select array_agg(user_id) from public.team_notifications
   where source_key = 'inquiry:website_chat_session:4c100000-0000-0000-0000-0000000000c2'),
  array['4c000000-0000-0000-0000-000000000001'::uuid],
  'when every chosen person lost access, the owner is alerted instead'
);

-- ---------------------------------------------------------------------------------------------------
-- A customer reply pauses the follow-up
-- ---------------------------------------------------------------------------------------------------
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('4c100000-0000-0000-0000-000000000010', '4c100000-0000-0000-0000-000000000001', 'Speed to lead',
  'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_sms","config":{}}],"stops":[]}'::jsonb);
insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence)
select '4c100000-0000-0000-0000-000000000011', id, organization_id, 1, 1, draft_definition, 'hash',
  'website_inquiry.received', 0
from public.automation_recipes where id = '4c100000-0000-0000-0000-000000000010';

insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, source, re_entry_key, context, anchor_at, customer_reply_after)
values ('4c100000-0000-0000-0000-0000000000e1', '4c100000-0000-0000-0000-000000000001',
  '4c100000-0000-0000-0000-000000000010', '4c100000-0000-0000-0000-000000000011', 'website_chat_session',
  '4c100000-0000-0000-0000-0000000000c1', 'manual', 'alerts-e1', '{}'::jsonb, now() - interval '1 hour',
  now() - interval '30 minutes');

-- A staff Pause leaves customer_reply_after untouched.
update private.automation_enrollments set state = 'paused', paused_work_due_at = now()
where id = '4c100000-0000-0000-0000-0000000000e1';
select is(
  (select count(*) from public.team_notifications where kind = 'website_inquiry.customer_replied'),
  0::bigint, 'a staff pause does not alert the team'
);

update private.automation_enrollments set state = 'active', paused_work_due_at = null
where id = '4c100000-0000-0000-0000-0000000000e1';
update private.automation_enrollments set state = 'paused', paused_work_due_at = now(),
  customer_reply_after = now() - interval '1 minute'
where id = '4c100000-0000-0000-0000-0000000000e1';

select is(
  (select title from public.team_notifications
   where kind = 'website_inquiry.customer_replied' and user_id = '4c000000-0000-0000-0000-000000000001'),
  'Sam Visitor replied to your automatic follow-up',
  'a customer-reply pause alerts the team'
);

-- ---------------------------------------------------------------------------------------------------
-- The email queue
-- ---------------------------------------------------------------------------------------------------
create temp table claimed on commit drop as
select * from public.claim_team_notification_emails(100, 120);

select is(
  (select email_state from public.team_notifications
   where source_key = 'inquiry:form_submission:4c100000-0000-0000-0000-0000000000f1'),
  'not_needed', 'a person who lost access is not emailed'
);

select is(
  (select array_agg(distinct recipient_email) from claimed), array['owner-4c@example.test'],
  'the claim returns the qualifying recipient''s sign-in email'
);

select is((select count(*) from public.claim_team_notification_emails(100, 120)), 0::bigint,
  'a claimed email is not claimed again while its lease holds');

select is(
  public.settle_team_notification_email((select notification_id from claimed limit 1),
    gen_random_uuid(), true),
  'claim_lost', 'settling with the wrong claim changes nothing'
);

select is(
  public.settle_team_notification_email(
    (select notification_id from claimed order by notification_id limit 1),
    (select claim_token from claimed order by notification_id limit 1), false, 'Brevo is down'),
  'retry', 'a failed send goes back to the queue'
);

select ok(
  (select email_available_at > now() and email_attempts = 1 from public.team_notifications
   where id = (select notification_id from claimed order by notification_id limit 1)),
  'a retry waits before it can be claimed again'
);

-- Four more failures reach the limit.
update public.team_notifications set email_attempts = 4, email_claim_token = gen_random_uuid(),
  email_claimed_until = now() + interval '1 minute'
where id = (select notification_id from claimed order by notification_id limit 1);
select is(
  public.settle_team_notification_email(
    (select notification_id from claimed order by notification_id limit 1),
    (select email_claim_token from public.team_notifications
     where id = (select notification_id from claimed order by notification_id limit 1)), false, 'still down'),
  'failed', 'the fifth failure stops retrying'
);

select is(
  public.settle_team_notification_email(
    (select notification_id from claimed order by notification_id desc limit 1),
    (select claim_token from claimed order by notification_id desc limit 1), true),
  'sent', 'a delivered alert email is recorded as sent'
);

-- ---------------------------------------------------------------------------------------------------
-- Reading and marking
-- ---------------------------------------------------------------------------------------------------
select is(
  public.mark_team_notifications_read('4c100000-0000-0000-0000-000000000001',
    '4c000000-0000-0000-0000-000000000004', null),
  0, 'marking all read touches none of another person''s alerts'
);

set local role authenticated;
set local request.jwt.claims to '{"sub":"4c000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is((select count(*) from public.team_notifications), 1::bigint,
  'a person reads only their own alerts');

select * from finish();
rollback;
