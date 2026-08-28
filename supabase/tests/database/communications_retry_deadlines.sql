-- Communications Part 8.2: per-class retry deadlines.
--
-- Every message carries the useful life its kind is given in docs/contractor-email-contract.md, resolved
-- once when it is queued. The claim checks that clock before anything else: past the deadline the message
-- is cancelled with a reason a person can read, and the cancellation lands in the shared history. A
-- message inside its deadline is untouched by this rule, whatever its class. And a tenant suspended for
-- longer than a message's life gets that message cancelled while it is still suspended, so reactivation
-- releases only mail that is still worth sending.
begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

-- ------------------------------------------------------------------------------------------------
-- The class-to-clock rule itself.
-- ------------------------------------------------------------------------------------------------

select is(
  private.resolve_communication_email_retry_deadline(
    'standard', '2026-09-08 10:00:00+00'::timestamptz, null),
  '2026-09-09 10:00:00+00'::timestamptz,
  'replies, requested quotes and invoices run on a 24-hour clock'
);

select is(
  private.resolve_communication_email_retry_deadline(
    'payment_receipt', '2026-09-08 10:00:00+00'::timestamptz, null),
  '2026-09-11 10:00:00+00'::timestamptz,
  'a payment receipt runs on a 72-hour clock'
);

select is(
  private.resolve_communication_email_retry_deadline(
    'appointment_reminder', '2026-09-08 10:00:00+00'::timestamptz,
    '2026-09-08 14:00:00+00'::timestamptz),
  '2026-09-08 14:00:00+00'::timestamptz,
  'a reminder expires when its own appointment window passes, not on a fixed number of hours'
);

select is(
  private.resolve_communication_email_retry_deadline(
    'optional_followup', '2026-09-08 10:00:00+00'::timestamptz,
    '2026-09-08 18:00:00+00'::timestamptz),
  '2026-09-08 18:00:00+00'::timestamptz,
  'an optional follow-up dies at its next scheduled boundary when that comes first'
);

select is(
  private.resolve_communication_email_retry_deadline(
    'optional_followup', '2026-09-08 10:00:00+00'::timestamptz,
    '2026-09-20 18:00:00+00'::timestamptz),
  '2026-09-09 10:00:00+00'::timestamptz,
  'an optional follow-up still dies at 24 hours when its next boundary is far away'
);

-- ------------------------------------------------------------------------------------------------
-- Fixture. Two tenants: one ordinary, one suspended for longer than a standard message lives.
-- ------------------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e9100000-0000-0000-0000-000000000001', 'Deadline Test Active', 'deadline-test-active', 'active'),
  ('e9100000-0000-0000-0000-000000000002', 'Deadline Test Suspended', 'deadline-test-suspended', 'suspended');

insert into public.clients (id, organization_id, display_name) values
  ('e9200000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001', 'Deadline Client'),
  ('e9200000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000002', 'Suspended Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e9300000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'email', 'active@deadline-test.example', true),
  ('e9300000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000002',
   'e9200000-0000-0000-0000-000000000002', 'email', 'suspended@deadline-test.example', true);

-- Park any send already queued in this database so the claim assertions below see only our fixture.
update public.communication_outbox_events set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

-- A reminder with no window has no clock to run on, so it cannot be queued at all.
select throws_ok(
  $$insert into public.communication_delivery_intents (
      organization_id, client_id, client_contact_method_id, logical_send_key,
      recipient_email, subject, html_content, text_content, retry_class
    ) values (
      'e9100000-0000-0000-0000-000000000001', 'e9200000-0000-0000-0000-000000000001',
      'e9300000-0000-0000-0000-000000000001', 'deadline-test-reminder-no-window',
      'active@deadline-test.example', 'Reminder', '<p>r</p>', 'r', 'appointment_reminder')$$,
  '23514',
  'An appointment reminder needs the end of its reminder window.',
  'an appointment reminder cannot be queued without the window it expires on'
);

-- Four sends, all queued 30 hours ago: past the 24-hour clock, inside the 72-hour one.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, retry_class, retry_window_ends_at, created_at
) values
  ('e9400000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'deadline-test-standard', 'active@deadline-test.example', 'Standard', '<p>s</p>', 's',
   'standard', null, now() - interval '30 hours'),
  ('e9400000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'deadline-test-receipt', 'active@deadline-test.example', 'Receipt', '<p>r</p>', 'r',
   'payment_receipt', null, now() - interval '30 hours'),
  ('e9400000-0000-0000-0000-000000000003', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'deadline-test-reminder', 'active@deadline-test.example', 'Reminder', '<p>r</p>', 'r',
   'appointment_reminder', now() - interval '2 hours', now() - interval '30 hours'),
  ('e9400000-0000-0000-0000-000000000004', 'e9100000-0000-0000-0000-000000000001',
   'e9200000-0000-0000-0000-000000000001', 'e9300000-0000-0000-0000-000000000001',
   'deadline-test-followup', 'active@deadline-test.example', 'Follow-up', '<p>f</p>', 'f',
   'optional_followup', now() + interval '5 days', now() - interval '30 hours');

select is(
  (select expires_at from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000002'),
  (select created_at + interval '72 hours' from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000002'),
  'queueing a message stores its deadline; no caller has to work it out'
);

insert into public.communication_outbox_events (id, organization_id, delivery_intent_id, available_at) values
  ('e9500000-0000-0000-0000-000000000001', 'e9100000-0000-0000-0000-000000000001',
   'e9400000-0000-0000-0000-000000000001', now() - interval '1 minute'),
  ('e9500000-0000-0000-0000-000000000002', 'e9100000-0000-0000-0000-000000000001',
   'e9400000-0000-0000-0000-000000000002', now() - interval '1 minute'),
  ('e9500000-0000-0000-0000-000000000003', 'e9100000-0000-0000-0000-000000000001',
   'e9400000-0000-0000-0000-000000000003', now() - interval '1 minute'),
  ('e9500000-0000-0000-0000-000000000004', 'e9100000-0000-0000-0000-000000000001',
   'e9400000-0000-0000-0000-000000000004', now() - interval '1 minute');

-- ------------------------------------------------------------------------------------------------
-- Each class expires on its own clock. One claim pass, four different verdicts.
-- ------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the claim hands out no send: the live one has no eligible sender in this fixture'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000001'),
  'retry_deadline_passed',
  'a reply/quote/invoice send is cancelled once it has waited more than 24 hours'
);

select ok(
  (select status = 'cancelled' and failure_message like '%24 hours%'
   from public.communication_delivery_intents where id = 'e9400000-0000-0000-0000-000000000001'),
  'the expired send is cancelled with a reason a person can read, not released quietly'
);

select ok(
  (select status = 'cancelled' and claim_token is null
   from public.communication_outbox_events where id = 'e9500000-0000-0000-0000-000000000001'),
  'its queue row is cancelled too, so nothing retries it'
);

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000002'), 'none'),
  'retry_deadline_passed',
  'a payment receipt at the same 30 hours is still inside its own 72-hour clock'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000003'),
  'retry_deadline_passed',
  'a reminder whose appointment window has passed is cancelled, however recently it was queued'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000004'),
  'retry_deadline_passed',
  'an optional follow-up is cancelled at 24 hours even though its next boundary is days away'
);

select is(
  (select count(*)::int from public.communication_message_events
   where delivery_intent_id = 'e9400000-0000-0000-0000-000000000001'
     and event_kind = 'cancelled' and reason_code = 'retry_deadline_passed'),
  1,
  'the expiry is recorded once in the shared message history'
);

-- ------------------------------------------------------------------------------------------------
-- A long suspension. The stale send dies while the tenant is still stopped, so reactivation releases
-- only mail that is still worth sending.
-- ------------------------------------------------------------------------------------------------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, created_at
) values
  ('e9400000-0000-0000-0000-000000000005', 'e9100000-0000-0000-0000-000000000002',
   'e9200000-0000-0000-0000-000000000002', 'e9300000-0000-0000-0000-000000000002',
   'deadline-test-suspended-stale', 'suspended@deadline-test.example', 'Stale', '<p>s</p>', 's',
   now() - interval '40 hours'),
  ('e9400000-0000-0000-0000-000000000006', 'e9100000-0000-0000-0000-000000000002',
   'e9200000-0000-0000-0000-000000000002', 'e9300000-0000-0000-0000-000000000002',
   'deadline-test-suspended-fresh', 'suspended@deadline-test.example', 'Fresh', '<p>f</p>', 'f',
   now() - interval '10 minutes');

insert into public.communication_outbox_events (id, organization_id, delivery_intent_id, available_at) values
  ('e9500000-0000-0000-0000-000000000005', 'e9100000-0000-0000-0000-000000000002',
   'e9400000-0000-0000-0000-000000000005', now() - interval '1 minute'),
  ('e9500000-0000-0000-0000-000000000006', 'e9100000-0000-0000-0000-000000000002',
   'e9400000-0000-0000-0000-000000000006', now() - interval '1 minute');

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'a suspended organization still claims nothing'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000005'),
  'retry_deadline_passed',
  'the stale send expires during the suspension instead of being held indefinitely'
);

select ok(
  (select event.status = 'pending' and event.available_at <= intent.expires_at
   from public.communication_outbox_events event
   join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
   where event.id = 'e9500000-0000-0000-0000-000000000006'),
  'the fresh send is held, and its hold never sleeps past its own deadline'
);

-- Reactivation: only the live message is still there to release.
update public.organizations set lifecycle_status = 'active'
where id = 'e9100000-0000-0000-0000-000000000002';
update public.communication_outbox_events set available_at = now() - interval '1 minute'
where id = 'e9500000-0000-0000-0000-000000000006';

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the released send still fails the remaining checks -- this fixture has no sender or verified domain'
);

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e9400000-0000-0000-0000-000000000006'), 'none'),
  'retry_deadline_passed',
  'reactivation releases the message that is still inside its deadline'
);

select * from finish();
rollback;
