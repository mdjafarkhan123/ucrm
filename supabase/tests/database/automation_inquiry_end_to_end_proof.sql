-- CRM launch readiness Part 4, Stage 6 step 4: end-to-end proof for the website speed-to-lead starter preset
-- (Wait 5 minutes -> reply by text or email), driven through the real claim -> advance -> effect chain.
--
-- Covers: a double-submitted form or chat cannot create two inquiries; two overlapping worker wakes enroll one
-- inquiry once; a worker that dies after claiming the reply step leaves the row leased, a second worker cannot
-- take it early, the row comes back when the lease passes, exactly one message goes out, and the dead worker's
-- late effect is refused; a staff reply that lands between the check and the send stops it; a customer adding
-- detail before any reply was sent still gets the reply; the sequence then finishes.

begin;

create extension if not exists pgtap with schema extensions;
select plan(33);

-- A local stack keeps placeholder worker addresses in Vault; a queued send wakes its worker over pg_net, which
-- refuses a URL without a scheme. Point every placeholder at a closed local port for this rolled-back test only.
select vault.update_secret(id, 'http://127.0.0.1:9/test-wake')
from vault.decrypted_secrets where name like '%target_url' and decrypted_secret like 'REPLACE_ME%';

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: an email-ready organization with automations on and the starter preset live.
-- ---------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('4d000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'owner-4d@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('4d100000-0000-0000-0000-000000000001', 'Proof Plumbing', 'proof-plumbing-4d', 'active');
insert into public.organization_members (organization_id, user_id, role, status)
values ('4d100000-0000-0000-0000-000000000001', '4d000000-0000-0000-0000-000000000001', 'owner', 'active');
insert into public.organization_feature_overrides (organization_id, feature_key, override_state, reason)
values ('4d100000-0000-0000-0000-000000000001', 'automations', 'on', 'Test fixture.');

insert into public.communication_email_domains (id, organization_id, purpose, domain_name, lifecycle_state,
  provider_domain_id, provider_verified, provider_authenticated, ownership_status, dkim_status,
  dmarc_status, spf_status, inbound_mx_status, verified_at)
values ('4d400000-0000-0000-0000-000000000001', '4d100000-0000-0000-0000-000000000001', 'sending',
  'mail.proof-4d.example', 'verified', 64002, true, true, 'passing', 'passing', 'passing', 'pending',
  'unchecked', now());
insert into public.communication_email_senders (id, organization_id, domain_id, email_address, display_name,
  lifecycle_state, is_organization_default, allows_manual, allows_automated)
values ('4d410000-0000-0000-0000-000000000001', '4d100000-0000-0000-0000-000000000001',
  '4d400000-0000-0000-0000-000000000001', 'hello@mail.proof-4d.example', 'Proof Plumbing',
  'enabled', true, true, true);

-- Clients: A (crash proof), B (customer detail before any reply), C (chat, staff reply race).
insert into public.clients (id, organization_id, display_name, lifecycle_status)
select ('4d200000-0000-0000-0000-0000000000' || suffix)::uuid, '4d100000-0000-0000-0000-000000000001', name, 'lead'
from (values ('0a', 'Ann Crash'), ('0b', 'Bob Detail'), ('0c', 'Cam Chat')) as c(suffix, name);
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
select ('4d300000-0000-0000-0000-0000000000' || suffix)::uuid, '4d100000-0000-0000-0000-000000000001',
  ('4d200000-0000-0000-0000-0000000000' || suffix)::uuid, 'email', email, true
from (values ('0a', 'ann@example.test'), ('0b', 'bob@example.test'), ('0c', 'cam@example.test')) as m(suffix, email);

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4d600000-0000-0000-0000-000000000001', '4d100000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'proof-4d-form');
insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4d610000-0000-0000-0000-000000000001', '4d100000-0000-0000-0000-000000000001',
  '4d600000-0000-0000-0000-000000000001', 1, 'Get a quote');
insert into public.website_chat_widgets (id, organization_id, name)
values ('4d620000-0000-0000-0000-000000000001', '4d100000-0000-0000-0000-000000000001', 'Main site');

-- The starter preset exactly as shipped: Wait 5 minutes, then one reply; the two inquiry stops are always on.
insert into public.automation_recipes (id, organization_id, name, status, source, preset_key, preset_version,
  draft_definition)
values ('4d800000-0000-0000-0000-000000000001', '4d100000-0000-0000-0000-000000000001', 'Website inquiry quick reply',
  'draft', 'preset', 'website_speed_to_lead', 1,
  '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[],"steps":[{"type":"wait","key":"wait.relative_delay","config":{"unit":"minutes","amount":5}},{"type":"action","key":"action.send_customer_message","config":{"email_subject":"Thanks for contacting {{business_name}}","email_body":"Hi {{customer_name}}, we got your message and will be in touch shortly."}}],"stops":[{"key":"stop.inquiry_staff_reply"},{"key":"stop.inquiry_customer_reply"}]}'::jsonb);
insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence)
select '4d810000-0000-0000-0000-000000000001', id, organization_id, 1, 1, draft_definition, 'hash-4d',
  'website_inquiry.received', 0
from public.automation_recipes where id = '4d800000-0000-0000-0000-000000000001';
update public.automation_recipes set status = 'active', current_version_id = '4d810000-0000-0000-0000-000000000001',
  active_trigger_key = 'website_inquiry.received'
where id = '4d800000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------------------------------
-- Helpers: a worker claims only this organization's due rows; enrollment and message lookups by subject.
-- ---------------------------------------------------------------------------------------------------
create table pg_temp.claims (worker text, work_item_id uuid, claim_token uuid, step_index integer, attempts integer);

-- A fair batch with a per-organization cap of one guarantees this tenant's due row is taken when there is one,
-- whatever else the local queue holds. Rows claimed for other tenants are rolled back with the test.
create function pg_temp.claim(p_worker text) returns integer language plpgsql as $$
declare
  taken integer;
begin
  insert into pg_temp.claims (worker, work_item_id, claim_token, step_index, attempts)
  select p_worker, c.work_item_id, c.claim_token, c.step_index, c.attempts
  from public.claim_automation_work_items(200, 1, 120, 8, p_worker) as c
  where c.organization_id = '4d100000-0000-0000-0000-000000000001';
  get diagnostics taken = row_count;
  return taken;
end;
$$;

create function pg_temp.advance(p_worker text) returns text language sql as $$
  select public.advance_automation_work_item(c.work_item_id, c.claim_token)
  from pg_temp.claims c where c.worker = p_worker order by c.step_index desc limit 1;
$$;

create function pg_temp.effect(p_worker text) returns text language sql as $$
  select public.perform_automation_inquiry_message_effect(c.work_item_id, c.claim_token)
  from pg_temp.claims c where c.worker = p_worker order by c.step_index desc limit 1;
$$;

create function pg_temp.enrollment(p_subject uuid) returns private.automation_enrollments language sql stable as $$
  select e from private.automation_enrollments e where e.subject_id = p_subject;
$$;

create function pg_temp.messages(p_subject uuid) returns integer language sql stable as $$
  select count(*)::integer from public.communication_delivery_intents i
  where i.logical_send_key like 'automation-inquiry-message-%:' || (pg_temp.enrollment(p_subject)).id || ':%';
$$;

create function pg_temp.make_due(p_subject uuid) returns void language sql as $$
  update private.automation_work_items
  set due_at = now() - interval '1 minute', available_at = now() - interval '1 minute'
  where enrollment_id = (pg_temp.enrollment(p_subject)).id and state = 'pending';
$$;

-- ---------------------------------------------------------------------------------------------------
-- 1. A double-submitted form or chat cannot become two inquiries.
-- ---------------------------------------------------------------------------------------------------
insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact)
values
  ('4d700000-0000-0000-0000-00000000000a', '4d100000-0000-0000-0000-000000000001',
   '4d600000-0000-0000-0000-000000000001', '4d610000-0000-0000-0000-000000000001', 'visit-a',
   '{"name":"Ann Crash","email":"ann@example.test"}'::jsonb),
  ('4d700000-0000-0000-0000-00000000000b', '4d100000-0000-0000-0000-000000000001',
   '4d600000-0000-0000-0000-000000000001', '4d610000-0000-0000-0000-000000000001', 'visit-b',
   '{"name":"Bob Detail","email":"bob@example.test"}'::jsonb);

select throws_ok(
  $$insert into private.form_submissions (organization_id, form_id, form_version_id, idempotency_key, contact)
    values ('4d100000-0000-0000-0000-000000000001', '4d600000-0000-0000-0000-000000000001',
      '4d610000-0000-0000-0000-000000000001', 'visit-a', '{"name":"Ann Crash"}'::jsonb)$$,
  '23505', null, 'the same form visit submitted twice is one submission, not two'
);

insert into public.website_chat_sessions (
  id, organization_id, widget_id, client_id, match_status, visitor_name, submitted_email, normalized_email,
  session_token_hash, idempotency_key
) values (
  '4d630000-0000-0000-0000-00000000000c', '4d100000-0000-0000-0000-000000000001',
  '4d620000-0000-0000-0000-000000000001', '4d200000-0000-0000-0000-00000000000c', 'resolved', 'Cam Chat',
  'cam@example.test', 'cam@example.test', repeat('d', 64), 'chat-visit-c'
);
select throws_ok(
  $$insert into public.website_chat_sessions (organization_id, widget_id, client_id, match_status, visitor_name,
      submitted_email, normalized_email, session_token_hash, idempotency_key)
    values ('4d100000-0000-0000-0000-000000000001', '4d620000-0000-0000-0000-000000000001',
      '4d200000-0000-0000-0000-00000000000c', 'resolved', 'Cam Chat', 'cam@example.test', 'cam@example.test',
      repeat('e', 64), 'chat-visit-c')$$,
  '23505', null, 'the same chat start sent twice is one session, not two'
);

-- ---------------------------------------------------------------------------------------------------
-- 2. Two overlapping worker wakes enroll each inquiry exactly once.
-- ---------------------------------------------------------------------------------------------------
update private.form_submissions
set status = 'processed', processed_at = now(),
  result = jsonb_build_object('outcome', 'request', 'client_id',
    '4d200000-0000-0000-0000-0000000000' || right(id::text, 2))
where organization_id = '4d100000-0000-0000-0000-000000000001';

select ok(public.intake_automation_events(200) >= 3, 'the first wake settles the three inquiry events');
select is(public.intake_automation_events(200), 0, 'an overlapping second wake finds nothing left to enroll');
select is(
  (select count(*)::integer from private.automation_enrollments
   where organization_id = '4d100000-0000-0000-0000-000000000001'),
  3, 'each inquiry is enrolled exactly once'
);
select is(
  (select count(*)::integer from private.automation_work_items
   where organization_id = '4d100000-0000-0000-0000-000000000001' and state = 'pending' and step_index = 0),
  3, 'each enrollment has exactly one first step waiting'
);

-- ---------------------------------------------------------------------------------------------------
-- 3. The wait schedules the reply five minutes out, and a worker that dies after claiming the reply step
--    cannot cause a missed or doubled message.
-- ---------------------------------------------------------------------------------------------------
-- Only Ann's step is due for now; the others stay in the future until their scenario.
update private.automation_work_items set due_at = now() + interval '1 day', available_at = now() + interval '1 day'
where organization_id = '4d100000-0000-0000-0000-000000000001'
  and enrollment_id <> (pg_temp.enrollment('4d700000-0000-0000-0000-00000000000a')).id;

select is(pg_temp.claim('worker-a'), 1, 'a worker claims the due first step');
select is(pg_temp.advance('worker-a'), 'waiting', 'the first step is the five-minute wait');
select ok(
  (select due_at between now() + interval '4 minutes' and now() + interval '6 minutes'
   from private.automation_work_items
   where enrollment_id = (pg_temp.enrollment('4d700000-0000-0000-0000-00000000000a')).id and step_index = 1),
  'the reply is scheduled five minutes after the wait began'
);
select is(pg_temp.claim('worker-b'), 0, 'the reply step is not claimable before its time');

select pg_temp.make_due('4d700000-0000-0000-0000-00000000000a');
delete from pg_temp.claims;
select is(pg_temp.claim('worker-a'), 1, 'when the five minutes pass, a worker claims the reply step');
select is(pg_temp.advance('worker-a'), 'action_due_customer_message',
  'the advance says the reply is due and leaves the row leased for the send');
-- worker-a dies here, before running the effect.

select is(pg_temp.claim('worker-b'), 0, 'while the lease holds, another worker cannot take the reply step');
select is(pg_temp.messages('4d700000-0000-0000-0000-00000000000a'), 0, 'nothing was sent by the dead worker');

-- The lease passes with the row still pending.
update private.automation_work_items set available_at = now() - interval '1 hour'
where enrollment_id = (pg_temp.enrollment('4d700000-0000-0000-0000-00000000000a')).id and step_index = 1;

select is(pg_temp.claim('worker-b'), 1, 'when the lease passes, the reply step returns to the queue');
select is((select attempts from pg_temp.claims where worker = 'worker-b'), 2,
  'the abandoned attempt is counted');
select is(pg_temp.advance('worker-b'), 'action_due_customer_message',
  'the second worker re-runs every check before sending');
select is(pg_temp.effect('worker-b'), 'action_sent', 'the second worker sends the reply');
select is(pg_temp.messages('4d700000-0000-0000-0000-00000000000a'), 1, 'exactly one message went out');

-- worker-a wakes up late and runs the effect it was about to run.
select is(pg_temp.effect('worker-a'), 'claim_lost', 'the dead worker''s late send is refused');
-- worker-b crashes right after its send committed and replays the same effect on restart.
select is(pg_temp.effect('worker-b'), 'claim_lost', 'replaying a finished send is refused');
select is(pg_temp.messages('4d700000-0000-0000-0000-00000000000a'), 1, 'the customer still has exactly one message');

delete from pg_temp.claims;
select is(pg_temp.claim('worker-b'), 1, 'the step after the reply is claimable at once');
select is(pg_temp.advance('worker-b'), 'completed', 'the sequence finishes after its only reply');
select is(
  (select state || '|' || customer_messages_sent from private.automation_enrollments
   where subject_id = '4d700000-0000-0000-0000-00000000000a'),
  'completed|1', 'the history shows a finished sequence with one message'
);

-- ---------------------------------------------------------------------------------------------------
-- 4. A staff reply that lands between the check and the send stops the send.
-- ---------------------------------------------------------------------------------------------------
delete from pg_temp.claims;
select pg_temp.make_due('4d630000-0000-0000-0000-00000000000c');
select is(pg_temp.claim('worker-c'), 1, 'the chat inquiry''s first step is claimed');
select is(pg_temp.advance('worker-c'), 'waiting', 'the chat inquiry waits its five minutes');
select pg_temp.make_due('4d630000-0000-0000-0000-00000000000c');
delete from pg_temp.claims;
select pg_temp.claim('worker-c');
select is(pg_temp.advance('worker-c'), 'action_due_customer_message', 'the chat reply is due');

insert into public.website_chat_messages (organization_id, session_id, client_id, direction, sender_type, body)
values ('4d100000-0000-0000-0000-000000000001', '4d630000-0000-0000-0000-00000000000c',
  '4d200000-0000-0000-0000-00000000000c', 'outbound', 'staff', 'Hi Cam, this is Pat. How can I help?');

select is(pg_temp.effect('worker-c'), 'action_cancelled', 'a staff reply in the last instant stops the send');
select is(
  (select state || '|' || stop_reason || '|' || pg_temp.messages('4d630000-0000-0000-0000-00000000000c')
   from private.automation_enrollments where subject_id = '4d630000-0000-0000-0000-00000000000c'),
  'stopped|staff_replied|0', 'the history says a person replied and nothing was sent'
);

-- ---------------------------------------------------------------------------------------------------
-- 5. A customer adding detail before any reply was sent still gets the reply.
-- ---------------------------------------------------------------------------------------------------
delete from pg_temp.claims;
select pg_temp.make_due('4d700000-0000-0000-0000-00000000000b');
select pg_temp.claim('worker-d');
select pg_temp.advance('worker-d');
select pg_temp.make_due('4d700000-0000-0000-0000-00000000000b');
delete from pg_temp.claims;
select pg_temp.claim('worker-d');
select is(pg_temp.advance('worker-d'), 'action_due_customer_message', 'Bob''s reply is due');

insert into public.communication_inbound_messages (organization_id, client_id, client_contact_method_id, channel,
  sender_id, sender_email, subject, text_content)
values ('4d100000-0000-0000-0000-000000000001', '4d200000-0000-0000-0000-00000000000b',
  '4d300000-0000-0000-0000-00000000000b', 'email', '4d410000-0000-0000-0000-000000000001', 'bob@example.test',
  'One more thing',
  'Forgot to say: the leak is under the kitchen sink.');

select is(pg_temp.effect('worker-d'), 'action_sent',
  'detail the customer adds before any reply was sent does not stop the reply');
select is(pg_temp.messages('4d700000-0000-0000-0000-00000000000b'), 1, 'Bob gets exactly one message');

select * from finish();

select case when num_failed() = 0 then 'ALL PASSED' else num_failed()::text || ' FAILED' end as result;

rollback;
