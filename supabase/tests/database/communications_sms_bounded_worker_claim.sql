-- Communications A2 / Stage 4B regression: the real SQL claim/finalize functions must complete an actual
-- healthy-path SMS claim end to end. Found while building Stage 8-3's scale evidence: every existing 4B test
-- exercised this contract through a mocked TypeScript client (vitest) or called finalize directly against an
-- already-'processing' row, so nothing had ever called claim_communication_sms_outbox_event() against a real,
-- fully eligible candidate -- which is exactly the case that hit its ambiguous `delivery_intent_id` column
-- reference (fixed 20260923100000). This test seeds a fully eligible send (including the Twilio account row
-- 4A's own test never needed) and drives the real claim -> finalize path with no mocking.
begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

-- The outbox-insert wake trigger fails closed against its Vault placeholder URL by design (see
-- 20260919140000's own header) until real deployment configuration replaces it, which a clean local/CI
-- database never has. Point it at a syntactically valid, unreachable URL for the life of this rolled-back
-- transaction so enqueuing below can insert its outbox row without depending on ambient host configuration.
-- vault.secrets is a view backed by a table pgTAP's role has no direct UPDATE grant on; go through the
-- vault-provided function instead, which is what every migration that manages these secrets already uses.
select vault.update_secret(
  (select id from vault.secrets where name = 'communications_sms_worker_target_url'),
  'https://example.invalid/api/internal/communications/sms-worker');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('e7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'sms-claim-owner@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e7100000-0000-0000-0000-000000000001', 'Claim Co', 'claim-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('e7100000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'owner', 'active');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state) values
  ('e7100000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'conversations.send', 'grant');

insert into public.clients (id, organization_id, display_name) values
  ('e7200000-0000-0000-0000-000000000001', 'e7100000-0000-0000-0000-000000000001', 'Claim Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e7300000-0000-0000-0000-000000000001', 'e7100000-0000-0000-0000-000000000001',
   'e7200000-0000-0000-0000-000000000001', 'phone', '+15557770001', true);

insert into public.communication_sms_registrations (
  id, organization_id, country_code, sender_type, use_case, status,
  attested_by, attested_at, submitted_at, provider_outcome
) values (
  'e7500000-0000-0000-0000-000000000001', 'e7100000-0000-0000-0000-000000000001',
  'ZZ', 'long_code', 'customer_care', 'approved',
  'e7000000-0000-0000-0000-000000000001', now(), now(), 'Approved'
);

insert into public.communication_sms_sender_identities (
  id, organization_id, phone_number, lifecycle_state, allows_manual, allows_automated,
  country_code, sender_type, capable_sms, registration_id, is_default_sender
) values (
  'e7400000-0000-0000-0000-000000000001', 'e7100000-0000-0000-0000-000000000001',
  '+15558880001', 'ready', true, true, 'ZZ', 'long_code', true,
  'e7500000-0000-0000-0000-000000000001', true
);

insert into public.communication_sms_org_modes (organization_id, package_max_mode, chosen_mode) values
  ('e7100000-0000-0000-0000-000000000001', 'operational', 'operational');

insert into public.communication_sms_retail_rates (
  destination, sender_type, message_unit, retail_rate_major, effective_from, set_by
) values (
  'ZZ', 'long_code', 'segment', 0.05, now() - interval '1 day', 'e7000000-0000-0000-0000-000000000001'
);

insert into public.communication_sms_credit_accounts (organization_id, settled_balance_minor, reserved_balance_minor)
values ('e7100000-0000-0000-0000-000000000001', 100, 0);

insert into public.communication_twilio_accounts (organization_id, subaccount_sid, messaging_service_sid, lifecycle_state)
values (
  'e7100000-0000-0000-0000-000000000001',
  'AC77770000000000000000000000000001', 'MG77770000000000000000000000000001', 'ready'
);

select public.communication_sms_record_consent_proof(
  'e7100000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001',
  'e7200000-0000-0000-0000-000000000001', 'e7300000-0000-0000-0000-000000000001',
  'signed_agreement', array['service']::text[], now() - interval '1 hour', 'consent-claim-1');

select public.communication_sms_set_quiet_hours_policy(
  false, '21:00', '08:00', 'UTC', 'e7000000-0000-0000-0000-000000000001');

select public.communication_sms_enqueue_operational(
  'e7100000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001',
  'e7200000-0000-0000-0000-000000000001', 'e7300000-0000-0000-0000-000000000001',
  null, 'service', 'Your crew is on the way.', 'manual', 'claim-send-key-1');

-- ---------------------------------------------------------------------------------------------------------------
-- The real claim function must succeed (not throw) against a fully eligible candidate, including reaching the
-- reservation-still-held check (step 7) that was ambiguous before the 20260923100000 fix.
-- ---------------------------------------------------------------------------------------------------------------
create temporary table claimed_row as
select * from public.claim_communication_sms_outbox_event();

select is((select count(*)::int from claimed_row), 1, 'the claim function returns exactly one row for one eligible candidate');
select is(
  (select delivery_intent_id from claimed_row),
  (select id from public.communication_delivery_intents where logical_send_key = 'claim-send-key-1'),
  'the claimed row is the one eligible SMS intent'
);
select is((select body from claimed_row), 'Your crew is on the way.', 'the claim returns the frozen message body');
select is(
  (select status from public.communication_delivery_intents where logical_send_key = 'claim-send-key-1'),
  'claimed', 'the intent is marked claimed'
);

select lives_ok(
  $$select public.finalize_communication_sms_outbox_event(
      (select outbox_event_id from claimed_row), (select claim_token from claimed_row),
      'submitted', 'SMtestmessageid00000000000000001', null, null)$$,
  'finalizing the real claim succeeds'
);
select is(
  (select status from public.communication_delivery_intents where logical_send_key = 'claim-send-key-1'),
  'submitted', 'the intent is submitted after finalize'
);

select * from finish();
rollback;
