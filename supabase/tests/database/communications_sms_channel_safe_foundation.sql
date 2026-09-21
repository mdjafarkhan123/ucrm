-- Communications A2 / Stage 1: shared delivery records are channel-safe before SMS transport exists.
begin;

create extension if not exists pgtap with schema extensions;
select plan(25);

select has_column('public', 'communication_delivery_intents', 'recipient_phone',
  'delivery intents preserve an SMS destination snapshot');
select has_column('public', 'communication_outbox_events', 'channel',
  'outbox work names its channel explicitly');
select has_column('public', 'communication_provider_callback_events', 'channel',
  'provider callbacks name their channel explicitly');
select has_index('public', 'communication_outbox_events', 'communication_outbox_events_email_claim_idx',
  'email claims have a channel-specific bounded index');
select has_index('public', 'communication_outbox_events', 'communication_outbox_events_sms_claim_idx',
  'SMS claims have a separate bounded index');
select has_index('public', 'communication_provider_callback_events',
  'communication_provider_callback_events_email_unprocessed_idx',
  'email callback projection has a channel-specific bounded index');
select has_index('public', 'communication_provider_callback_events',
  'communication_provider_callback_events_sms_unprocessed_idx',
  'SMS callback projection has a separate bounded index');
select has_index('public', 'communication_sms_consent_events', 'communication_sms_consent_events_projection_idx',
  'consent projection reads have deterministic ordered support');
select has_index('public', 'communication_sms_reconciliation_items', 'communication_sms_reconciliation_items_claim_idx',
  'reconciliation claims are bounded by a partial index');

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('a2100000-0000-0000-0000-000000000001', 'SMS Foundation A', 'sms-foundation-a', 'active'),
  ('a2100000-0000-0000-0000-000000000002', 'SMS Foundation B', 'sms-foundation-b', 'active');

insert into public.clients (id, organization_id, display_name) values
  ('a2200000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001', 'SMS Client A'),
  ('a2200000-0000-0000-0000-000000000002', 'a2100000-0000-0000-0000-000000000002', 'SMS Client B');

insert into public.client_contact_methods (
  id, organization_id, client_id, kind, value, is_primary
) values
  ('a2300000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001',
   'a2200000-0000-0000-0000-000000000001', 'phone', '+15550000001', true),
  ('a2300000-0000-0000-0000-000000000002', 'a2100000-0000-0000-0000-000000000002',
   'a2200000-0000-0000-0000-000000000002', 'phone', '+15550000002', true);

insert into public.communication_sms_sender_identities (
  id, organization_id, phone_number, lifecycle_state, allows_manual
) values (
  'a2400000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001',
  '+15551110001', 'ready', true
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key,
  recipient_phone, sms_sender_identity_id
) values (
  'a2500000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001',
  'a2200000-0000-0000-0000-000000000001', 'a2300000-0000-0000-0000-000000000001',
  'sms', 'sms-foundation-one', '+15550000001', 'a2400000-0000-0000-0000-000000000001'
);
insert into public.communication_sms_message_snapshots (
  organization_id, delivery_intent_id, raw_body, body, encoding, segment_count
) values (
  'a2100000-0000-0000-0000-000000000001', 'a2500000-0000-0000-0000-000000000001',
  'Your appointment is tomorrow.', 'Your appointment is tomorrow.', 'gsm7', 1
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id, channel)
values ('a2100000-0000-0000-0000-000000000001', 'a2500000-0000-0000-0000-000000000001', 'sms');

select is(
  (select count(*)::integer from public.claim_communication_outbox_event()), 0,
  'the existing email worker does not claim due SMS work'
);
select results_eq(
  $$select status, attempt_count from public.communication_outbox_events
    where delivery_intent_id = 'a2500000-0000-0000-0000-000000000001'$$,
  $$values ('pending'::text, 0)$$,
  'an email claim leaves the SMS lease untouched'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key,
  recipient_phone
) values (
  'a2500000-0000-0000-0000-000000000002', 'a2100000-0000-0000-0000-000000000001',
  'a2200000-0000-0000-0000-000000000001', 'a2300000-0000-0000-0000-000000000001',
  'sms', 'sms-foundation-two', '+15550000001'
);

select throws_ok(
  $$insert into public.communication_outbox_events (organization_id, delivery_intent_id, channel)
    values ('a2100000-0000-0000-0000-000000000001',
      'a2500000-0000-0000-0000-000000000002', 'email')$$,
  '23503', null,
  'an outbox row cannot disagree with its intent channel'
);
select throws_ok(
  $$insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, channel, logical_send_key,
      recipient_phone, recipient_email, subject, html_content, text_content
    ) values (
      'a2100000-0000-0000-0000-000000000001', 'a2200000-0000-0000-0000-000000000001',
      'a2300000-0000-0000-0000-000000000001', 'sms', 'bad-sms-email-payload',
      '+15550000001', 'leak@example.test', 'Wrong', '<p>Wrong</p>', 'Wrong'
    )$$,
  '23514', null,
  'SMS intents cannot carry email-only payload fields'
);
select throws_ok(
  $$insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, channel, logical_send_key,
      recipient_phone, sms_sender_identity_id
    ) values (
      'a2100000-0000-0000-0000-000000000002', 'a2200000-0000-0000-0000-000000000002',
      'a2300000-0000-0000-0000-000000000002', 'sms', 'cross-tenant-sender',
      '+15550000002', 'a2400000-0000-0000-0000-000000000001'
    )$$,
  '23503', null,
  'an SMS intent cannot borrow another organization sender identity'
);
select throws_ok(
  $$insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, channel, logical_send_key,
      recipient_phone
    ) values (
      'a2100000-0000-0000-0000-000000000001', 'a2200000-0000-0000-0000-000000000001',
      'a2300000-0000-0000-0000-000000000001', 'sms', 'sms-foundation-one',
      '+15550000001'
    )$$,
  '23505', null,
  'a retry cannot duplicate one logical send'
);

insert into public.communication_sms_consent_events (
  id, organization_id, client_id, client_contact_method_id, event_kind, source,
  source_event_key, occurred_at
) values (
  'a2600000-0000-0000-0000-000000000002', 'a2100000-0000-0000-0000-000000000001',
  'a2200000-0000-0000-0000-000000000001', 'a2300000-0000-0000-0000-000000000001',
  'opt_out', 'client_reply', 'message-stop', '2026-09-13 10:00:00+00'
);
insert into public.communication_sms_consent_events (
  id, organization_id, client_id, client_contact_method_id, event_kind, source,
  source_event_key, occurred_at, subjects, proof_method
) values (
  'a2600000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001',
  'a2200000-0000-0000-0000-000000000001', 'a2300000-0000-0000-0000-000000000001',
  'opt_in', 'import', 'older-import', '2026-09-13 09:00:00+00', array['service'], 'signed_agreement'
);
select is(
  public.communication_sms_consent_status(
    'a2100000-0000-0000-0000-000000000001', 'a2300000-0000-0000-0000-000000000001', 'service'),
  'opted_out',
  'a delayed older consent event cannot overwrite the newer customer reply'
);
select throws_ok(
  $$insert into public.communication_sms_consent_events (
      organization_id, client_id, client_contact_method_id, event_kind, source,
      source_event_key, occurred_at, subjects, proof_method
    ) values (
      'a2100000-0000-0000-0000-000000000001', 'a2200000-0000-0000-0000-000000000001',
      'a2300000-0000-0000-0000-000000000002', 'opt_in', 'staff', 'cross-tenant-method', now(),
      array['service'], 'signed_agreement'
    )$$,
  '23503', null,
  'consent evidence cannot attach another organization contact method'
);

insert into public.communication_sms_credit_accounts (
  organization_id, settled_balance_minor, reserved_balance_minor
) values ('a2100000-0000-0000-0000-000000000001', 1000, 0);
insert into public.communication_sms_credit_reservations (
  id, organization_id, delivery_intent_id, source_key, amount_minor, segment_count,
  reserved_purchased_minor
) values (
  'a2700000-0000-0000-0000-000000000001', 'a2100000-0000-0000-0000-000000000001',
  'a2500000-0000-0000-0000-000000000001', 'manual:sms-foundation-one', 25, 1, 25
);
insert into public.communication_sms_credit_ledger_entries (
  organization_id, reservation_id, source_key, entry_kind, amount_minor, balance_after_minor
) values (
  'a2100000-0000-0000-0000-000000000001', 'a2700000-0000-0000-0000-000000000001',
  'manual:sms-foundation-one', 'charge', -25, 975
);
select throws_ok(
  $$insert into public.communication_sms_credit_reservations (
      organization_id, delivery_intent_id, source_key, amount_minor, segment_count,
      reserved_purchased_minor
    ) values (
      'a2100000-0000-0000-0000-000000000001', 'a2500000-0000-0000-0000-000000000001',
      'manual:sms-foundation-one-retry', 25, 1, 25
    )$$,
  '23505', null,
  'one delivery intent can reserve credit only once'
);
select throws_ok(
  $$insert into public.communication_sms_credit_ledger_entries (
      organization_id, reservation_id, source_key, entry_kind, amount_minor, balance_after_minor
    ) values (
      'a2100000-0000-0000-0000-000000000001', 'a2700000-0000-0000-0000-000000000001',
      'manual:sms-foundation-one', 'charge', -25, 950
    )$$,
  '23505', null,
  'one logical source cannot be charged twice'
);

select table_privs_are('public', 'communication_sms_consent_events', 'authenticated', array[]::text[],
  'authenticated clients have no direct SMS consent table privileges');
select table_privs_are('public', 'communication_sms_credit_ledger_entries', 'authenticated', array[]::text[],
  'authenticated clients have no direct SMS ledger privileges');
select table_privs_are('public', 'communication_sms_sender_identities', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'the server role owns sender identity persistence');
select table_privs_are('public', 'communication_sms_consent_events', 'service_role',
  array['SELECT', 'INSERT'],
  'the server role can append but not rewrite consent evidence');
select table_privs_are('public', 'communication_sms_credit_ledger_entries', 'service_role',
  array['SELECT', 'INSERT'],
  'the server role can append but not rewrite ledger evidence');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_delivery_intents'::regclass),
  'the shared delivery intent table keeps row-level security enabled'
);

select * from finish();
rollback;
