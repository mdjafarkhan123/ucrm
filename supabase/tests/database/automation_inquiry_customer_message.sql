-- CRM launch readiness Part 4, Stage 5: a website inquiry's customer message picks text or email, and a public
-- form's ticked service-SMS box becomes consent evidence.
--
-- Covers: a ticked box records one web-form opt-in for that exact number (never for an unticked box or a number
-- that belongs to someone else, never twice); text when eligible, email when consent or balance is missing; one
-- message per step on replay; the reply mark is set on send; a delivered staff reply stops the send; only a
-- provider-reported failure makes the email fallback due, and the fallback sends once unless the customer replied.

begin;

create extension if not exists pgtap with schema extensions;
select plan(31);

-- A local stack keeps placeholder worker addresses in Vault; a queued text wakes the SMS worker over pg_net, which
-- refuses a URL without a scheme. Point every placeholder at a closed local port for this rolled-back test only.
select vault.update_secret(id, 'http://127.0.0.1:9/test-wake')
from vault.decrypted_secrets where name like '%target_url' and decrypted_secret like 'REPLACE_ME%';

select function_privs_are('public', 'perform_automation_inquiry_message_effect', array['uuid', 'uuid'],
  'authenticated', array[]::text[], 'contractors cannot run the inquiry message effect directly');
select function_privs_are('public', 'process_automation_sms_email_fallbacks', array['integer'],
  'service_role', array['EXECUTE'], 'the service role drains email fallbacks');

-- ---------------------------------------------------------------------------------------------------
-- Fixtures: an SMS-ready and email-ready organization with automations on.
-- ---------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('4c000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'owner-4c@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('4c100000-0000-0000-0000-000000000001', 'Speedy Roofing', 'speedy-roofing-4c', 'active');
insert into public.organization_members (organization_id, user_id, role, status)
values ('4c100000-0000-0000-0000-000000000001', '4c000000-0000-0000-0000-000000000001', 'owner', 'active');
insert into public.organization_package_exceptions
  (organization_id, capability_key, capability_state, reason, starts_at, ends_at, actor_owner_email)
values ('4c100000-0000-0000-0000-000000000001', 'automations', 'on', 'Test fixture.', '2026-01-01T00:00:00Z', '2100-01-01T00:00:00Z',
  'owner@example.test');

-- Clients: T (text-eligible), E (phone without consent), N (no contact), F1..F4 (text-eligible, for fallbacks),
-- B (text-eligible, used after the balance runs out).
insert into public.clients (id, organization_id, display_name, lifecycle_status)
select ('4c200000-0000-0000-0000-0000000000' || suffix)::uuid, '4c100000-0000-0000-0000-000000000001', name, 'lead'
from (values ('01', 'Tina Text'), ('02', 'Ed Email'), ('03', 'Nora Nothing'), ('04', 'Fay One'),
  ('05', 'Fay Two'), ('06', 'Fay Three'), ('07', 'Fay Four'), ('08', 'Ben Balance'), ('09', 'Other Owner'))
  as c(suffix, name);

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
select ('4c300000-0000-0000-0000-000000000' || suffix || kind_code)::uuid, '4c100000-0000-0000-0000-000000000001',
  ('4c200000-0000-0000-0000-0000000000' || suffix)::uuid, kind, value, true
from (values
  ('01', 'a', 'phone', '+15553330001'), ('01', 'b', 'email', 'tina@example.test'),
  ('02', 'a', 'phone', '+15553330002'), ('02', 'b', 'email', 'ed@example.test'),
  ('04', 'a', 'phone', '+15553330004'), ('04', 'b', 'email', 'fay1@example.test'),
  ('05', 'a', 'phone', '+15553330005'), ('05', 'b', 'email', 'fay2@example.test'),
  ('06', 'a', 'phone', '+15553330006'), ('06', 'b', 'email', 'fay3@example.test'),
  ('07', 'a', 'phone', '+15553330007'), ('07', 'b', 'email', 'fay4@example.test'),
  ('08', 'a', 'phone', '+15553330008'), ('08', 'b', 'email', 'ben@example.test'),
  ('09', 'a', 'phone', '+15553330009')
) as m(suffix, kind_code, kind, value);

insert into public.communication_email_domains (id, organization_id, purpose, domain_name, lifecycle_state,
  provider_domain_id, provider_verified, provider_authenticated, ownership_status, dkim_status,
  dmarc_status, spf_status, inbound_mx_status, verified_at)
values ('4c400000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001', 'sending',
  'mail.speedy-4c.example', 'verified', 64001, true, true, 'passing', 'passing', 'passing', 'pending',
  'unchecked', now());
insert into public.communication_email_senders (id, organization_id, domain_id, email_address, display_name,
  lifecycle_state, is_organization_default, allows_manual, allows_automated)
values ('4c410000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001',
  '4c400000-0000-0000-0000-000000000001', 'hello@mail.speedy-4c.example', 'Speedy Roofing',
  'enabled', true, true, true);

insert into public.communication_sms_registrations (id, organization_id, country_code, sender_type, use_case,
  status, attested_by, attested_at, submitted_at, provider_outcome)
values ('4c500000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001', 'US', 'long_code',
  'customer_care', 'approved', '4c000000-0000-0000-0000-000000000001', now(), now(), 'Approved');
insert into public.communication_sms_sender_identities (id, organization_id, phone_number, lifecycle_state,
  allows_manual, allows_automated, country_code, sender_type, capable_sms, capable_mms, registration_id,
  is_default_sender)
values ('4c510000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001', '+15559994444', 'ready',
  true, true, 'US', 'long_code', true, false, '4c500000-0000-0000-0000-000000000001', true);
insert into public.communication_sms_org_modes (organization_id, package_max_mode, chosen_mode)
values ('4c100000-0000-0000-0000-000000000001', 'operational', 'operational');
insert into public.communication_sms_retail_rates (destination, sender_type, message_unit, retail_rate_major,
  effective_from, set_by)
values ('US', 'long_code', 'segment', 0.05, now() - interval '1 day', '4c000000-0000-0000-0000-000000000001');
insert into public.communication_sms_credit_accounts (organization_id, settled_balance_minor, reserved_balance_minor)
values ('4c100000-0000-0000-0000-000000000001', 100, 0);
select public.communication_sms_set_quiet_hours_policy(
  false, '21:00', '08:00', 'UTC', '4c000000-0000-0000-0000-000000000001');

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4c600000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'speedy-4c-form');
insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4c610000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001',
  '4c600000-0000-0000-0000-000000000001', 1, 'Get a quote');

-- One processed submission per client, each ticking the SMS box except E's; N's has no phone; the '0a' one
-- typed a number that belongs to a different client.
insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact)
select ('4c700000-0000-0000-0000-0000000000' || s.suffix)::uuid, '4c100000-0000-0000-0000-000000000001',
  '4c600000-0000-0000-0000-000000000001', '4c610000-0000-0000-0000-000000000001', 'sub-' || s.suffix,
  jsonb_strip_nulls(jsonb_build_object('name', 'Visitor', 'phone', s.phone,
    'sms_service_consent', jsonb_build_object('given', s.given, 'disclosure', 'I agree to texts from Speedy Roofing.')))
from (values ('01', '15553330001', true), ('02', '15553330002', false), ('03', null, true),
  ('04', '15553330004', true), ('05', '15553330005', true), ('06', '15553330006', true),
  ('07', '15553330007', true), ('08', '15553330008', true), ('0a', '15553330009', true))
  as s(suffix, phone, given);

update private.form_submissions set status = 'processed', processed_at = now(),
  result = jsonb_build_object('outcome', 'request', 'client_id',
    '4c200000-0000-0000-0000-0000000000' || case right(id::text, 2) when '0a' then '01' else right(id::text, 2) end)
where organization_id = '4c100000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------------------------------
-- Consent evidence
-- ---------------------------------------------------------------------------------------------------
select is(
  (select event_kind || '|' || source || '|' || proof_method || '|' || array_to_string(subjects, ',') || '|'
     || (evidence ->> 'disclosure')
   from public.communication_sms_consent_events where source_event_key = 'form_submission:4c700000-0000-0000-0000-000000000001'),
  'opt_in|system|web_form|service,work_updates|I agree to texts from Speedy Roofing.',
  'a ticked box records a web-form opt-in with the exact wording shown');
select is(public.communication_sms_consent_status('4c100000-0000-0000-0000-000000000001',
  '4c300000-0000-0000-0000-00000000002a', 'service'), 'unknown', 'an unticked box records nothing');
select is(
  (select count(*)::integer from public.communication_sms_consent_events
   where source_event_key = 'form_submission:4c700000-0000-0000-0000-00000000000a'),
  0, 'a typed number that belongs to another client gets no consent');

update private.form_submissions set status = 'pending' where id = '4c700000-0000-0000-0000-000000000001';
update private.form_submissions set status = 'processed' where id = '4c700000-0000-0000-0000-000000000001';
select is(
  (select count(*)::integer from public.communication_sms_consent_events
   where client_id = '4c200000-0000-0000-0000-000000000001'),
  1, 'reprocessing the same submission never records consent twice');

-- ---------------------------------------------------------------------------------------------------
-- Recipe and helpers
-- ---------------------------------------------------------------------------------------------------
insert into public.automation_recipes (id, organization_id, name, status, source, draft_definition)
values ('4c800000-0000-0000-0000-000000000001', '4c100000-0000-0000-0000-000000000001', 'Speed to lead', 'draft',
  'custom',
  '{"schema_version":1,"trigger":{"key":"website_inquiry.received","config":{}},"conditions":[],"steps":[{"type":"action","key":"action.send_customer_message","config":{"sms_body":"Hi {{customer_name}}, {{business_name}} got your request.","email_subject":"Thanks from {{business_name}}","email_body":"Hi {{customer_name}}, we got your request."}}],"stops":[]}'::jsonb);
insert into public.automation_recipe_versions (id, recipe_id, organization_id, version_number, schema_version,
  definition, definition_hash, trigger_key, activation_cutoff_sequence)
select '4c810000-0000-0000-0000-000000000001', id, organization_id, 1, 1, draft_definition, 'hash-4c',
  'website_inquiry.received', 0
from public.automation_recipes where id = '4c800000-0000-0000-0000-000000000001';
update public.automation_recipes set status = 'active', current_version_id = '4c810000-0000-0000-0000-000000000001',
  active_trigger_key = 'website_inquiry.received'
where id = '4c800000-0000-0000-0000-000000000001';

insert into private.automation_enrollments (id, organization_id, recipe_id, recipe_version_id, subject_type,
  subject_id, source, re_entry_key, context, anchor_at)
select ('4c900000-0000-0000-0000-0000000000' || suffix)::uuid, '4c100000-0000-0000-0000-000000000001',
  '4c800000-0000-0000-0000-000000000001', '4c810000-0000-0000-0000-000000000001', 'form_submission',
  ('4c700000-0000-0000-0000-0000000000' || suffix)::uuid, 'manual', 'form_submission:' || suffix, '{}'::jsonb,
  now() - interval '10 minutes'
from (values ('01'), ('02'), ('03'), ('04'), ('05'), ('06'), ('07'), ('08')) as e(suffix);

create function pg_temp.send(p_suffix text) returns text language plpgsql as $$
declare
  token uuid := gen_random_uuid();
  item_id uuid;
begin
  insert into private.automation_work_items (organization_id, enrollment_id, step_index, due_at, available_at,
    claim_token, claimed_at)
  values ('4c100000-0000-0000-0000-000000000001', ('4c900000-0000-0000-0000-0000000000' || p_suffix)::uuid, 0,
    now(), now(), token, now())
  on conflict (enrollment_id, step_index) do update set state = 'pending', claim_token = excluded.claim_token
  returning id into item_id;
  return public.perform_automation_inquiry_message_effect(item_id, token);
end;
$$;

create function pg_temp.channels(p_suffix text) returns text language sql stable as $$
  select coalesce(string_agg(i.channel, ',' order by i.channel), '')
  from public.communication_delivery_intents i
  where i.logical_send_key like 'automation-inquiry-message-%:4c900000-0000-0000-0000-0000000000' || p_suffix || ':%';
$$;

create function pg_temp.fallback(p_suffix text) returns text language sql stable as $$
  select state || '|' || coalesce(reason, sms_failure, '') from private.automation_sms_email_fallbacks
  where enrollment_id = ('4c900000-0000-0000-0000-0000000000' || p_suffix)::uuid;
$$;

create function pg_temp.sms_intent(p_suffix text) returns uuid language sql stable as $$
  select sms_delivery_intent_id from private.automation_sms_email_fallbacks
  where enrollment_id = ('4c900000-0000-0000-0000-0000000000' || p_suffix)::uuid;
$$;

-- ---------------------------------------------------------------------------------------------------
-- Channel rule
-- ---------------------------------------------------------------------------------------------------
select is(pg_temp.send('01'), 'action_sent', 'an eligible customer message sends');
select is(pg_temp.channels('01'), 'sms', 'a customer with consent and a ready sender is texted');
select is(
  (select body from public.communication_sms_message_snapshots
   where delivery_intent_id = pg_temp.sms_intent('01')),
  'Hi Tina Text, Speedy Roofing got your request.', 'the text fills the customer and business names');
select is(
  (select state || '|' || current_step_index || '|' || customer_messages_sent || '|' || (customer_reply_after = now())
   from private.automation_enrollments where id = '4c900000-0000-0000-0000-000000000001'),
  'active|1|1|true', 'sending advances, counts the message and starts counting customer replies');

select is(pg_temp.send('01'), 'action_sent', 'replaying the step settles again');
select is(pg_temp.channels('01'), 'sms', 'a replay never sends a second message');

select is(pg_temp.send('02'), 'action_sent', 'a customer without SMS consent still gets a message');
select is(pg_temp.channels('02'), 'email', 'without consent the message goes by email');
select is(
  (select subject from public.communication_delivery_intents
   where logical_send_key like 'automation-inquiry-message-email:4c900000-0000-0000-0000-000000000002:%'),
  'Thanks from Speedy Roofing', 'the email fills the business name');
select is(pg_temp.fallback('02'), null, 'an email send is not watched for a fallback');

select is(pg_temp.send('03'), 'action_cancelled', 'a customer with no phone or email cannot be reached');
select is(
  (select state || '|' || stop_reason from private.automation_enrollments
   where id = '4c900000-0000-0000-0000-000000000003'),
  'stopped|no_email_address', 'the enrollment stops with a plain reason');

-- A delivered staff text to F4 before the step runs: the send is stopped, not queued.
insert into public.communication_delivery_intents (organization_id, client_id, client_contact_method_id, channel,
  logical_send_key, recipient_phone, send_kind, delivery_outcome)
values ('4c100000-0000-0000-0000-000000000001', '4c200000-0000-0000-0000-000000000007',
  '4c300000-0000-0000-0000-00000000007a', 'sms', 'staff-text-4c', '+15553330007', 'manual', 'sms_delivered');
select is(pg_temp.send('07'), 'action_cancelled', 'a delivered staff reply stops the automatic message');
select is(pg_temp.channels('07'), '', 'nothing is sent after a person answered');

-- ---------------------------------------------------------------------------------------------------
-- Email fallback on a provider-reported failure only
-- ---------------------------------------------------------------------------------------------------
select is(pg_temp.send('04'), 'action_sent', 'F1 is texted');
select is(pg_temp.send('05'), 'action_sent', 'F2 is texted');
select is(pg_temp.send('06'), 'action_sent', 'F3 is texted');

update public.communication_delivery_intents set status = 'submission_unknown' where id = pg_temp.sms_intent('01');
select is(pg_temp.fallback('01'), 'watching|', 'an unknown submission outcome never triggers a fallback');

update public.communication_delivery_intents set delivery_outcome = 'sms_delivered' where id = pg_temp.sms_intent('04');
update public.communication_delivery_intents set delivery_outcome = 'sms_undelivered' where id = pg_temp.sms_intent('05');
update public.communication_delivery_intents set status = 'cancelled', failure_code = 'recipient_opted_out'
  where id = pg_temp.sms_intent('06');
select is(pg_temp.fallback('04') || ' / ' || pg_temp.fallback('05') || ' / ' || pg_temp.fallback('06'),
  'not_needed|sms_delivered / due|sms_undelivered / skipped|recipient_opted_out',
  'delivered closes the watch, a carrier failure makes the fallback due, an opt-out does not');

select is(public.process_automation_sms_email_fallbacks(25), 1, 'the drain handles the one due fallback');
select is(pg_temp.channels('05'), 'email,sms', 'the failed text is followed by exactly one email');
select is(public.process_automation_sms_email_fallbacks(25), 0, 'a sent fallback is never drained again');

-- A Twilio 4xx rejection is also final, but the customer replied first, so no email follows.
update private.automation_enrollments set customer_reply_after = now() - interval '1 minute'
where id = '4c900000-0000-0000-0000-000000000001';
insert into public.communication_inbound_messages (organization_id, client_id, client_contact_method_id, channel,
  provider, sender_phone, subject, text_content, created_at)
values ('4c100000-0000-0000-0000-000000000001', '4c200000-0000-0000-0000-000000000001',
  '4c300000-0000-0000-0000-00000000001a', 'sms', 'twilio', '+15553330001', '', 'Yes please', now());
update public.communication_delivery_intents set status = 'cancelled', failure_code = 'twilio_http_400'
  where id = pg_temp.sms_intent('01');
select public.process_automation_sms_email_fallbacks(25);
select is(pg_temp.fallback('01'), 'skipped|customer_replied', 'no fallback email after the customer replied');

-- ---------------------------------------------------------------------------------------------------
-- No balance: the message falls through to email instead of waiting.
-- ---------------------------------------------------------------------------------------------------
-- Everything left is already held for the texts queued above, so nothing is spendable.
update public.communication_sms_credit_accounts set settled_balance_minor = reserved_balance_minor
where organization_id = '4c100000-0000-0000-0000-000000000001';
select is(pg_temp.send('08'), 'action_sent', 'a customer is still reached when SMS balance runs out');
select is(pg_temp.channels('08'), 'email', 'without SMS balance the customer is emailed instead');

select * from finish();
rollback;
