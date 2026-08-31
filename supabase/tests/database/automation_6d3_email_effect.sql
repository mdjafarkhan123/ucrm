-- Automation Part 6D-3: the email effect. One follow-up email sends once, safely, with correct dynamic text.
--
-- Proves the completion gate: perform_automation_email_effect turns a claimed action step into exactly one
-- Communications delivery intent (never a second on replay), renders the contractor's copy with the four
-- allow-listed variables filled and every authored or customer character escaped, advances the enrollment,
-- and -- when a current fact says the send is moot or not ready -- stops or defers instead of sending.

begin;

create extension if not exists pgtap with schema extensions;
select plan(23);

-- ---------------------------------------------------------------------------------------------------
-- The send stays internal.
-- ---------------------------------------------------------------------------------------------------
select function_privs_are(
  'public', 'enqueue_automation_quote_email',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'bytea'],
  'service_role', array['EXECUTE'], 'the service role runs the automation send');
select function_privs_are(
  'public', 'enqueue_automation_quote_email',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'bytea'],
  'authenticated', array[]::text[], 'contractors cannot run the automation send directly');
select function_privs_are(
  'public', 'perform_automation_email_effect', array['uuid', 'uuid', 'text', 'bytea'],
  'service_role', array['EXECUTE'], 'the service role runs the action effect');
select function_privs_are(
  'public', 'perform_automation_email_effect', array['uuid', 'uuid', 'text', 'bytea'],
  'authenticated', array[]::text[], 'contractors cannot run the action effect directly');

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: a real published quote (built through the actual commands), a ready automated sender, the
-- automations feature entitled, and one active recipe whose only step sends the follow-up email.
-- ---------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at)
values ('6d300000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'owner-6d3@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('6d310000-0000-0000-0000-000000000001', 'Automation 6D-3', 'automation-6d3', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values ('6d310000-0000-0000-0000-000000000001', '6d300000-0000-0000-0000-000000000001', 'admin', 'active');

-- A customer whose name carries an ampersand, so escaping in the rendered HTML is actually exercised.
insert into public.clients (id, organization_id, display_name)
values ('6d320000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001', 'A & B Co');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('6d330000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  '6d320000-0000-0000-0000-000000000001', 'email', 'customer@6d3.example', true);

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('6d370000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  '6d320000-0000-0000-0000-000000000001', '1 Automation Way', 'Testville');

insert into public.communication_email_domains (id, organization_id, purpose, domain_name, lifecycle_state,
  provider_domain_id, provider_verified, provider_authenticated, ownership_status, dkim_status,
  dmarc_status, spf_status, inbound_mx_status, verified_at)
values ('6d340000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  'sending', 'mail.6d3.example', 'verified', 63001, true, true, 'passing', 'passing',
  'passing', 'pending', 'unchecked', now());

-- The automated org-default sender the automation send resolves.
insert into public.communication_email_senders (id, organization_id, domain_id, email_address, display_name,
  lifecycle_state, is_organization_default, allows_manual, allows_automated)
values ('6d350000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  '6d340000-0000-0000-0000-000000000001', 'hello@mail.6d3.example', 'Automation 6D-3',
  'enabled', true, true, true);

insert into public.organization_feature_overrides (organization_id, feature_key, override_state, reason)
values ('6d310000-0000-0000-0000-000000000001', 'automations', 'on', 'Test fixture.');

-- Build a genuinely published quote through the real commands.
select set_config('request.jwt.claim.sub', '6d300000-0000-0000-0000-000000000001', true);
select public.create_quote(
  '6d320000-0000-0000-0000-000000000001', '6d370000-0000-0000-0000-000000000001', 'Follow-up Quote', null);

create function pg_temp.qid() returns uuid language sql stable as
  'select id from public.quotes where title = ''Follow-up Quote''';
create function pg_temp.qrev() returns integer language sql stable as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Follow-up Quote'')';

select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.qrev(),
  jsonb_build_array(jsonb_build_object('name', 'Line', 'category', 'service', 'quantity', 1,
    'unit_price_minor', 10000, 'unit_cost_minor', 4000, 'is_taxable', false)));
select public.set_quote_draft_tax(pg_temp.qid(), pg_temp.qrev(), 'no_tax');
select public.publish_quote(pg_temp.qid(), pg_temp.qrev());
select set_config('request.jwt.claim.sub', '', true);

set local role postgres;

-- One active recipe whose single step sends the email. The body deliberately includes every variable plus a
-- script tag, to prove substitution AND escaping in one render.
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('6d3a0000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  'Follow up', 'draft', 'custom',
  '{"schema_version":1,"trigger":{"key":"quote.delivery_succeeded","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_email","config":{"subject":"Following up on quote {{quote_number}}","body":"Hi {{customer_name}}, this is {{business_name}}. View: {{quote_link}} <script>alert(1)</script>"}}],"stops":[{"key":"stop.quote_approved"}]}'::jsonb);

insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence, activation_cutoff_snapshot)
values ('6d3b0000-0000-0000-0000-000000000001', '6d3a0000-0000-0000-0000-000000000001',
  '6d310000-0000-0000-0000-000000000001', 1, 1,
  (select draft_definition from public.automation_recipes where id = '6d3a0000-0000-0000-0000-000000000001'),
  'hash-6d3', 'quote.delivery_succeeded', 0, pg_current_snapshot());

update public.automation_recipes
set status = 'active', current_version_id = '6d3b0000-0000-0000-0000-000000000001',
  active_trigger_key = 'quote.delivery_succeeded'
where id = '6d3a0000-0000-0000-0000-000000000001';

insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
  occurred_at, source_module, source_event_id, processed_at)
values ('6d3c0000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  'quote.delivery_succeeded', 'quote', pg_temp.qid(), '{}'::jsonb, now(),
  'communications', '6d3c0000-0000-0000-0000-0000000000aa', now());

insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, trigger_event_id, source, re_entry_key, context)
values ('6d3d0000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  '6d3a0000-0000-0000-0000-000000000001', '6d3b0000-0000-0000-0000-000000000001', 'quote',
  pg_temp.qid(), '6d3c0000-0000-0000-0000-000000000001', 'event', 'entry-1', '{}'::jsonb);

insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at,
  available_at, claim_token, claimed_at)
values ('6d3e0000-0000-0000-0000-000000000001', '6d310000-0000-0000-0000-000000000001',
  '6d3d0000-0000-0000-0000-000000000001', 0, now(), now(),
  '6d3f0000-0000-0000-0000-000000000001', now());

-- ---------------------------------------------------------------------------------------------------
-- The happy path: the action sends exactly one email with correct, safe dynamic text.
-- ---------------------------------------------------------------------------------------------------
select is(
  public.perform_automation_email_effect('6d3e0000-0000-0000-0000-000000000001',
    '6d3f0000-0000-0000-0000-000000000001', 'https://app.example.test/q/token-6d3', decode(repeat('ab', 32), 'hex')),
  'action_sent', 'a claimed email action sends and reports action_sent');

create function pg_temp.sent_key() returns text language sql stable as
  $$select 'automation-quote-follow-up:6d3d0000-0000-0000-0000-000000000001:6d3b0000-0000-0000-0000-000000000001:0'$$;

select is(
  (select count(*)::integer from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  1, 'exactly one delivery intent is enqueued for the effect');

select alike(
  (select subject from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  'Following up on quote %', 'the subject fills the quote number variable');

select alike(
  (select html_content from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  '%A &amp; B Co%', 'the customer name is escaped in the HTML body');

select is(
  (select strpos(html_content, '<script>') from public.communication_delivery_intents
   where logical_send_key = pg_temp.sent_key()),
  0, 'authored markup cannot reach the HTML body as live tags');

select alike(
  (select html_content from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  '%&lt;script&gt;alert(1)&lt;/script&gt;%', 'authored markup is escaped, not dropped');

select alike(
  (select html_content from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  '%<a href="https://app.example.test/q/token-6d3">%', 'the quote link becomes a real anchor to the minted URL');

select is(
  (select strpos(text_content, '<a ') from public.communication_delivery_intents
   where logical_send_key = pg_temp.sent_key()),
  0, 'the plain-text part carries the raw link, never an anchor tag');

select alike(
  (select text_content from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  '%https://app.example.test/q/token-6d3%', 'the plain-text part still contains the customer link');

select is(
  (select count(*)::integer from public.communication_outbox_events
   where delivery_intent_id = (select id from public.communication_delivery_intents
     where logical_send_key = pg_temp.sent_key())),
  1, 'the send is handed to the outbox the email worker drains');

select is(
  (select current_step_index || ':' || customer_messages_sent
   from private.automation_enrollments where id = '6d3d0000-0000-0000-0000-000000000001'),
  '1:1', 'the enrollment advances one step and records one customer message');

select is(
  (select state from private.automation_work_items where id = '6d3e0000-0000-0000-0000-000000000001'),
  'done', 'the settled action step is done, not left claimed');

select is(
  (select count(*)::integer from private.automation_work_items
   where enrollment_id = '6d3d0000-0000-0000-0000-000000000001' and step_index = 1),
  1, 'exactly one next transition is scheduled');

-- ---------------------------------------------------------------------------------------------------
-- Send once: replaying the same logical key enqueues nothing new.
-- ---------------------------------------------------------------------------------------------------
select is(
  (public.enqueue_automation_quote_email('6d310000-0000-0000-0000-000000000001', pg_temp.qid(),
    pg_temp.sent_key(), 'Re', 'Body {{quote_link}}', 'https://app.example.test/q/again',
    decode(repeat('cd', 32), 'hex'))) ->> 'status',
  'sent', 'replaying the same send key reports sent without re-sending');

select is(
  (select count(*)::integer from public.communication_delivery_intents where logical_send_key = pg_temp.sent_key()),
  1, 'the replay creates no second delivery intent');

-- ---------------------------------------------------------------------------------------------------
-- Not ready yet: no automated sender means defer, not send.
-- ---------------------------------------------------------------------------------------------------
update public.communication_email_senders set lifecycle_state = 'disabled'
  where id = '6d350000-0000-0000-0000-000000000001';
select is(
  (public.enqueue_automation_quote_email('6d310000-0000-0000-0000-000000000001', pg_temp.qid(),
    'automation-quote-follow-up:temp-key', 'S', 'B {{quote_link}}', 'https://app.example.test/q/t',
    decode(repeat('ab', 32), 'hex'))) ->> 'status',
  'skipped_temporary', 'no ready automated sender defers the send instead of failing it');
update public.communication_email_senders set lifecycle_state = 'enabled'
  where id = '6d350000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------------------------------
-- Moot: once the quote is no longer awaiting a response, the effect stops the whole enrollment.
-- ---------------------------------------------------------------------------------------------------
insert into private.automation_events (id, organization_id, event_type, subject_type, subject_id, payload,
  occurred_at, source_module, source_event_id, processed_at)
values ('6d3c0000-0000-0000-0000-000000000002', '6d310000-0000-0000-0000-000000000001',
  'quote.delivery_succeeded', 'quote', pg_temp.qid(), '{}'::jsonb, now(),
  'communications', '6d3c0000-0000-0000-0000-0000000000bb', now());
insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, trigger_event_id, source, re_entry_key, context)
values ('6d3d0000-0000-0000-0000-000000000002', '6d310000-0000-0000-0000-000000000001',
  '6d3a0000-0000-0000-0000-000000000001', '6d3b0000-0000-0000-0000-000000000001', 'quote',
  pg_temp.qid(), '6d3c0000-0000-0000-0000-000000000002', 'manual', 'entry-2', '{}'::jsonb);
insert into private.automation_work_items (id, organization_id, enrollment_id, step_index, due_at,
  available_at, claim_token, claimed_at)
values ('6d3e0000-0000-0000-0000-000000000002', '6d310000-0000-0000-0000-000000000001',
  '6d3d0000-0000-0000-0000-000000000002', 0, now(), now(),
  '6d3f0000-0000-0000-0000-000000000002', now());

update public.quotes set status = 'declined' where id = pg_temp.qid();

select is(
  public.perform_automation_email_effect('6d3e0000-0000-0000-0000-000000000002',
    '6d3f0000-0000-0000-0000-000000000002', 'https://app.example.test/q/token-2', decode(repeat('ab', 32), 'hex')),
  'action_cancelled', 'a quote that no longer awaits a response cancels the action');

select is(
  (select state || ':' || stop_reason from private.automation_enrollments
   where id = '6d3d0000-0000-0000-0000-000000000002'),
  'stopped:quote_not_sendable', 'the whole enrollment stops with a plain reason, so later steps never run');

select is(
  (select count(*)::integer from public.communication_delivery_intents
   where organization_id = '6d310000-0000-0000-0000-000000000001'
     and logical_send_key like 'automation-quote-follow-up:6d3d0000-0000-0000-0000-000000000002%'),
  0, 'a cancelled action sends nothing');

select * from finish();
rollback;
