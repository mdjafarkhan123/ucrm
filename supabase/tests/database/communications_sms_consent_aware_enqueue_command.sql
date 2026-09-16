-- Communications A2 / Stage 4A part 2: the one atomic consent-aware SMS enqueue command creates the intent,
-- message snapshot, credit reservation and outbox row together; rechecks consent (exact number + subject),
-- readiness/holds and balance; spends Promotional Credit before Purchased Credit; is idempotent by logical send
-- key and refuses a changed payload; and reschedules a send that lands in the platform quiet-hours window.
begin;

create extension if not exists pgtap with schema extensions;
select plan(40);

-- ---------------------------------------------------------------------------------------------------------------
-- Shape and access boundary.
-- ---------------------------------------------------------------------------------------------------------------
select has_table('public', 'communication_sms_quiet_hours_policy', 'the platform quiet-hours policy table exists');
select has_function('public', 'communication_sms_enqueue_operational',
  array['uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'boolean'],
  'the consent-aware enqueue command exists');
select has_function('public', 'communication_sms_estimate_segments', array['text'],
  'the segment-estimate helper exists');
select has_function('public', 'communication_sms_quiet_hours_available_at', array['timestamp with time zone'],
  'the quiet-hours scheduling helper exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_quiet_hours_policy'::regclass),
  'the quiet-hours policy keeps row-level security enabled');
select function_privs_are('public', 'communication_sms_enqueue_operational',
  array['uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'boolean'],
  'authenticated', array[]::text[],
  'authenticated clients cannot call the enqueue command directly');
select function_privs_are('public', 'communication_sms_enqueue_operational',
  array['uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'text', 'text', 'text', 'text', 'boolean'],
  'service_role', array['EXECUTE'],
  'the server role owns the enqueue command');

-- ---------------------------------------------------------------------------------------------------------------
-- Segment estimate: GSM-7 vs UCS-2 and the segment boundaries Twilio bills on.
-- ---------------------------------------------------------------------------------------------------------------
select is((select encoding from public.communication_sms_estimate_segments('Hi')), 'gsm7',
  'a plain body is GSM-7');
select is((select segment_count from public.communication_sms_estimate_segments('Hi')), 1,
  'a short body is one segment');
select is((select segment_count from public.communication_sms_estimate_segments(repeat('a', 160))), 1,
  '160 GSM-7 characters still fit one segment');
select is((select segment_count from public.communication_sms_estimate_segments(repeat('a', 161))), 2,
  '161 GSM-7 characters need a second segment');
select is((select encoding from public.communication_sms_estimate_segments('great 😀')), 'ucs2',
  'an emoji forces UCS-2');
select is((select segment_count from public.communication_sms_estimate_segments(repeat('я', 70))), 1,
  '70 UCS-2 characters fit one segment');
select is((select segment_count from public.communication_sms_estimate_segments(repeat('я', 71))), 2,
  '71 UCS-2 characters need a second segment');
select is((select segment_count from public.communication_sms_estimate_segments(repeat('a', 159) || '€')), 2,
  'a GSM-7 extension character counts as two, tipping 160 slots into a second segment');

-- ---------------------------------------------------------------------------------------------------------------
-- Fixtures.
-- ---------------------------------------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at) values
  ('e4000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'sms-sender@example.test', 'test', now(), now()),
  ('e4000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'sms-field@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e4100000-0000-0000-0000-000000000001', 'Enqueue Co', 'enqueue-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000002', 'field', 'active');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state) values
  ('e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'conversations.send', 'grant'),
  ('e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'customers.view', 'grant');

insert into public.clients (id, organization_id, display_name) values
  ('e4200000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-000000000001', 'Enqueue Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e4300000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-000000000001',
   'e4200000-0000-0000-0000-000000000001', 'phone', '+15551230001', true),
  ('e4300000-0000-0000-0000-000000000002', 'e4100000-0000-0000-0000-000000000001',
   'e4200000-0000-0000-0000-000000000001', 'phone', '+15551230002', false);

-- An approved registration with a live, SMS-capable default sending number. A fixture-only destination
-- ('ZZ') is used so no real published retail rate on the shared dev database shadows the test rate below.
insert into public.communication_sms_registrations (
  id, organization_id, country_code, sender_type, use_case, status,
  attested_by, attested_at, submitted_at, provider_outcome
) values (
  'e4500000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-000000000001',
  'ZZ', 'long_code', 'customer_care', 'approved',
  'e4000000-0000-0000-0000-000000000001', now(), now(), 'Approved'
);

insert into public.communication_sms_sender_identities (
  id, organization_id, phone_number, lifecycle_state, allows_manual, allows_automated,
  country_code, sender_type, capable_sms, registration_id, is_default_sender
) values (
  'e4400000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-000000000001',
  '+15559990001', 'ready', true, true, 'ZZ', 'long_code', true,
  'e4500000-0000-0000-0000-000000000001', true
);

-- Operational SMS mode, a published retail rate (5 cents per segment), and a funded credit account.
insert into public.communication_sms_org_modes (organization_id, package_max_mode, chosen_mode) values
  ('e4100000-0000-0000-0000-000000000001', 'operational', 'operational');

insert into public.communication_sms_retail_rates (
  destination, sender_type, message_unit, retail_rate_major, effective_from, set_by
) values (
  'ZZ', 'long_code', 'segment', 0.05, now() - interval '1 day', 'e4000000-0000-0000-0000-000000000001'
);

insert into public.communication_sms_credit_accounts (organization_id, settled_balance_minor, reserved_balance_minor)
values ('e4100000-0000-0000-0000-000000000001', 100, 0);

-- Consent: opted in for 'service' on number 1; number 2 has opted out globally.
select public.communication_sms_record_consent_proof(
  'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
  'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
  'signed_agreement', array['service']::text[], now() - interval '1 hour', 'consent-service-1');

insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values (
  'e4100000-0000-0000-0000-000000000001', 'e4200000-0000-0000-0000-000000000001',
  'e4300000-0000-0000-0000-000000000002', 'opt_out', 'client_reply', 'stop-2', now()
);

-- ---------------------------------------------------------------------------------------------------------------
-- Quiet-hours scheduling: a fixed window in UTC, tested with fixed timestamps so it is deterministic.
-- ---------------------------------------------------------------------------------------------------------------
select public.communication_sms_set_quiet_hours_policy(
  true, '21:00', '08:00', 'UTC', 'e4000000-0000-0000-0000-000000000001');
select is(
  public.communication_sms_quiet_hours_available_at('2026-06-15 23:00:00+00'),
  '2026-06-16 08:00:00+00'::timestamptz,
  'a send at 23:00 inside the window is rescheduled to the next 08:00');
select is(
  public.communication_sms_quiet_hours_available_at('2026-06-15 12:00:00+00'),
  '2026-06-15 12:00:00+00'::timestamptz,
  'a send at midday outside the window keeps its time');
select is(
  public.communication_sms_quiet_hours_available_at('2026-06-15 03:00:00+00'),
  '2026-06-15 08:00:00+00'::timestamptz,
  'a send at 03:00 in the early-morning tail is rescheduled to 08:00 the same day');

-- Disable quiet hours so the enqueue tests below schedule immediately and deterministically.
select public.communication_sms_set_quiet_hours_policy(
  false, '21:00', '08:00', 'UTC', 'e4000000-0000-0000-0000-000000000001');
select is(
  public.communication_sms_quiet_hours_available_at('2026-06-15 23:00:00+00'),
  '2026-06-15 23:00:00+00'::timestamptz,
  'a disabled quiet-hours policy never reschedules');

-- ---------------------------------------------------------------------------------------------------------------
-- Happy path: one send freezes the intent, snapshot, reservation and outbox row atomically.
-- ---------------------------------------------------------------------------------------------------------------
select lives_ok(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'Your crew is on the way.', 'manual', 'send-key-1')$$,
  'an authorized member can enqueue a consented operational SMS');

select is(
  (select count(*) from public.communication_delivery_intents
   where organization_id = 'e4100000-0000-0000-0000-000000000001' and logical_send_key = 'send-key-1'
     and channel = 'sms' and recipient_phone = '+15551230001'
     and sms_sender_identity_id = 'e4400000-0000-0000-0000-000000000001')::int,
  1, 'the send creates exactly one SMS intent for the default number');

select is(
  (select segment_count::int || ':' || encoding from public.communication_sms_message_snapshots snap
   join public.communication_delivery_intents i on i.id = snap.delivery_intent_id
   where i.logical_send_key = 'send-key-1'),
  '1:gsm7', 'the frozen snapshot records the estimated segments and encoding');

select is(
  (select reserved_purchased_minor || ':' || reserved_promotional_minor || ':' || amount_minor
   from public.communication_sms_credit_reservations r
   join public.communication_delivery_intents i on i.id = r.delivery_intent_id
   where i.logical_send_key = 'send-key-1'),
  '5:0:5', 'with no promotional credit the 5-cent cost is reserved entirely from purchased credit');

select is(
  (select reserved_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'e4100000-0000-0000-0000-000000000001'),
  5::bigint, 'the purchased reservation is held against the credit account');

select is(
  (select count(*) from public.communication_outbox_events e
   join public.communication_delivery_intents i on i.id = e.delivery_intent_id
   where i.logical_send_key = 'send-key-1' and e.channel = 'sms' and e.status = 'pending')::int,
  1, 'the send is handed to the SMS outbox');

-- ---------------------------------------------------------------------------------------------------------------
-- Idempotency and changed-payload conflict.
-- ---------------------------------------------------------------------------------------------------------------
select lives_ok(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'Your crew is on the way.', 'manual', 'send-key-1')$$,
  'the same logical send key with the same payload is a safe replay');
select is(
  (select count(*) from public.communication_delivery_intents
   where logical_send_key = 'send-key-1')::int,
  1, 'the replay does not create a second intent');
select is(
  (select reserved_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'e4100000-0000-0000-0000-000000000001'),
  5::bigint, 'the replay does not reserve credit twice');
select throws_like(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'A completely different message.', 'manual', 'send-key-1')$$,
  '%already queued with different details%',
  'the same key with a different payload is refused as a conflict');

-- ---------------------------------------------------------------------------------------------------------------
-- Consent refusals: unknown and opted out.
-- ---------------------------------------------------------------------------------------------------------------
select throws_like(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'billing_updates', 'Your invoice is ready.', 'manual', 'send-key-billing')$$,
  '%no SMS consent on file%',
  'a subject the customer never consented to is refused');
select throws_like(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000002',
      null, 'service', 'Hello there.', 'manual', 'send-key-optout')$$,
  '%opted out%',
  'a number that has opted out is refused');

-- ---------------------------------------------------------------------------------------------------------------
-- Permission.
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000002',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'Hi from an unauthorized member.', 'manual', 'send-key-noperm')$$,
  '42501', NULL,
  'a member without send permission cannot enqueue an SMS');

-- ---------------------------------------------------------------------------------------------------------------
-- Balance refusal: drain purchased credit so spendable is zero.
-- ---------------------------------------------------------------------------------------------------------------
update public.communication_sms_credit_accounts
set settled_balance_minor = 5
where organization_id = 'e4100000-0000-0000-0000-000000000001';
select throws_like(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'No money for this one.', 'manual', 'send-key-broke')$$,
  '%not enough SMS balance%',
  'a send is refused when spendable credit is insufficient');

-- ---------------------------------------------------------------------------------------------------------------
-- Promotional credit is spent first, before purchased credit.
-- ---------------------------------------------------------------------------------------------------------------
select public.communication_sms_grant_promotional_credit(
  'e4100000-0000-0000-0000-000000000001', 100, now() + interval '30 days', 'launch bonus',
  'promo-key-1', 'e4000000-0000-0000-0000-000000000001');
select lives_ok(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'Funded by promo credit.', 'manual', 'send-key-promo')$$,
  'a send succeeds when promotional credit covers it even though purchased credit is exhausted');
select is(
  (select reserved_promotional_minor || ':' || reserved_purchased_minor
   from public.communication_sms_credit_reservations r
   join public.communication_delivery_intents i on i.id = r.delivery_intent_id
   where i.logical_send_key = 'send-key-promo'),
  '5:0', 'the cost is drawn from promotional credit first, not purchased');
select is(
  (select reserved_balance_minor from public.communication_sms_credit_accounts
   where organization_id = 'e4100000-0000-0000-0000-000000000001'),
  5::bigint, 'a promotional-funded send does not touch the purchased reserved balance');

-- ---------------------------------------------------------------------------------------------------------------
-- MMS eligibility (Stage 6D-2): Twilio's own hard limit is both ends US/Canada; this system checks the
-- sender's own capable_mms flag and country_code (see the 6D-2 migration's header note for why).
-- ---------------------------------------------------------------------------------------------------------------
select throws_like(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'Picture attached.', 'manual', 'send-key-mms-ineligible', true)$$,
  '%Picture messaging is not available%',
  'a non-US/Canada, non-MMS-capable default sender refuses a send with media'
);

-- Readiness is computed per (org, country, sender type, use case) via its own registration row (not
-- through the sender's FK), so the US sender below needs its own approved US registration.
insert into public.communication_sms_registrations (
  id, organization_id, country_code, sender_type, use_case, status,
  attested_by, attested_at, submitted_at, provider_outcome
) values (
  'e4500000-0000-0000-0000-000000000002', 'e4100000-0000-0000-0000-000000000001',
  'US', 'long_code', 'customer_care', 'approved',
  'e4000000-0000-0000-0000-000000000001', now(), now(), 'Approved'
);
insert into public.communication_sms_sender_identities (
  id, organization_id, phone_number, lifecycle_state, allows_manual, allows_automated,
  country_code, sender_type, capable_sms, capable_mms, registration_id, is_default_sender
) values (
  'e4400000-0000-0000-0000-000000000002', 'e4100000-0000-0000-0000-000000000001',
  '+15559990099', 'ready', true, true, 'US', 'long_code', true, true,
  'e4500000-0000-0000-0000-000000000002', false
);
insert into public.communication_sms_retail_rates (
  destination, sender_type, message_unit, retail_rate_major, effective_from, set_by
) values (
  'US', 'long_code', 'segment', 0.05, now() - interval '1 day', 'e4000000-0000-0000-0000-000000000001'
);
select lives_ok(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      'e4400000-0000-0000-0000-000000000002', 'service', 'Picture attached.', 'manual',
      'send-key-mms-eligible', true)$$,
  'an MMS-capable US/Canada sender allows a send with media through'
);
select is(
  (select sms_sender_identity_id from public.communication_delivery_intents
    where logical_send_key = 'send-key-mms-eligible'),
  'e4400000-0000-0000-0000-000000000002'::uuid,
  'the eligible send used the explicitly chosen MMS-capable sender'
);

-- ---------------------------------------------------------------------------------------------------------------
-- Readiness/holds: an active outbound hold pauses new sends.
-- ---------------------------------------------------------------------------------------------------------------
insert into public.communication_sms_holds (scope, organization_id, reason, status) values
  ('organization', 'e4100000-0000-0000-0000-000000000001', 'test pause', 'active');
select throws_like(
  $$select public.communication_sms_enqueue_operational(
      'e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001',
      'e4200000-0000-0000-0000-000000000001', 'e4300000-0000-0000-0000-000000000001',
      null, 'service', 'Should be paused.', 'manual', 'send-key-hold')$$,
  '%paused%',
  'an active outbound hold pauses new sends');

select * from finish();
rollback;
