-- Communications Part 1: a claimed provider submission has one atomic, lease-protected outcome.
begin;

create extension if not exists pgtap with schema extensions;
select plan(19);

select has_function(
  'public', 'quarantine_stale_communication_claims', array['integer', 'interval'],
  'stale worker leases have a bounded quarantine command'
);
select has_index(
  'public', 'communication_outbox_events', 'communication_outbox_events_stale_claim_idx',
  'stale worker leases have a narrow partial index'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values ('e1000000-0000-0000-0000-000000000001', 'Email Worker Test', 'email-worker-test', 'active');

insert into public.clients (id, organization_id, display_name)
values (
  'e2000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000001',
  'Email Customer'
);

insert into public.client_contact_methods (
  id, organization_id, client_id, kind, value, is_primary
) values (
  'e3000000-0000-0000-0000-000000000001',
  'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001',
  'email', 'customer@example.test', true
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
) values
  ('e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
   'email-test-submitted', 'customer@example.test', 'Submitted', '<p>Submitted</p>', 'Submitted'),
  ('e4000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
   'email-test-retry', 'customer@example.test', 'Retry', '<p>Retry</p>', 'Retry'),
  ('e4000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
   'email-test-unknown', 'customer@example.test', 'Unknown', '<p>Unknown</p>', 'Unknown'),
  ('e4000000-0000-0000-0000-000000000005', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
   'email-test-stale', 'customer@example.test', 'Stale', '<p>Stale</p>', 'Stale');

insert into public.communication_outbox_events (
  id, organization_id, delivery_intent_id, status, claimed_at, claim_token, attempt_count
) values
  ('e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000001', 'processing', now(),
   'e6000000-0000-0000-0000-000000000001', 1),
  ('e5000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000002', 'processing', now(),
   'e6000000-0000-0000-0000-000000000002', 1),
  ('e5000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000003', 'processing', now(),
   'e6000000-0000-0000-0000-000000000003', 1),
  ('e5000000-0000-0000-0000-000000000005', 'e1000000-0000-0000-0000-000000000001',
   'e4000000-0000-0000-0000-000000000005', 'processing', now() - interval '1 hour',
   'e6000000-0000-0000-0000-000000000005', 1);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
) values (
  'e4000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'email-test-old-lease', 'customer@example.test', 'Lease', '<p>Lease</p>', 'Lease'
);
insert into public.communication_outbox_events (
  id, organization_id, delivery_intent_id, status, claimed_at, claim_token, attempt_count
) values (
  'e5000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000004', 'processing', now(),
  'e6000000-0000-0000-0000-000000000004', 1
);

select results_eq(
  $$select outbox_status, intent_status, attempt_count, usage_recorded
    from public.finalize_communication_outbox_event(
      'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
      'submitted', 'brevo-message-1'
    )$$,
  $$values ('submitted'::text, 'submitted'::text, 1, true)$$,
  'provider acceptance atomically submits the intent, outbox row, and usage event'
);
select is(
  (select count(*)::int from public.communication_email_usage_events
   where delivery_intent_id = 'e4000000-0000-0000-0000-000000000001'),
  1, 'one accepted recipient produces one usage event'
);
select is(
  (select provider_message_id from public.communication_delivery_intents
   where id = 'e4000000-0000-0000-0000-000000000001'),
  'brevo-message-1', 'provider acceptance retains the provider message identifier'
);

select results_eq(
  $$select outbox_status, intent_status, attempt_count, usage_recorded
    from public.finalize_communication_outbox_event(
      'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
      'submitted', 'brevo-message-1'
    )$$,
  $$values ('submitted'::text, 'submitted'::text, 1, true)$$,
  'repeating the exact completion lease returns the committed outcome'
);
select is(
  (select count(*)::int from public.communication_email_usage_events
   where delivery_intent_id = 'e4000000-0000-0000-0000-000000000001'),
  1, 'repeating completion cannot count the recipient twice'
);

select throws_ok(
  $$select public.finalize_communication_outbox_event(
    'e5000000-0000-0000-0000-000000000004', 'e6000000-0000-0000-0000-000000000099',
    'submitted', 'brevo-message-stolen'
  )$$,
  '42501', 'The communication claim token is invalid.',
  'a foreign claim token cannot finish a current lease'
);
select is(
  (select status from public.communication_outbox_events
   where id = 'e5000000-0000-0000-0000-000000000004'),
  'processing', 'a refused foreign claim leaves the current lease untouched'
);

select public.finalize_communication_outbox_event(
  'e5000000-0000-0000-0000-000000000002', 'e6000000-0000-0000-0000-000000000002',
  'retry', null, 'provider_503', 'Provider unavailable'
);
select is(
  (select status from public.communication_outbox_events
   where id = 'e5000000-0000-0000-0000-000000000002'),
  'failed', 'a retryable failure releases the lease into the retry queue'
);
select ok(
  (select available_at >= now() + interval '4 minutes 55 seconds'
     and available_at <= now() + interval '5 minutes 5 seconds'
   from public.communication_outbox_events
   where id = 'e5000000-0000-0000-0000-000000000002'),
  'the first retry uses the approved five-minute delay'
);
select is(
  (select count(*)::int from public.communication_email_usage_events
   where delivery_intent_id = 'e4000000-0000-0000-0000-000000000002'),
  0, 'a retryable failure does not consume allowance'
);

select public.finalize_communication_outbox_event(
  'e5000000-0000-0000-0000-000000000003', 'e6000000-0000-0000-0000-000000000003',
  'submission_unknown', null, 'network_after_submit', 'Provider outcome is unknown'
);
select is(
  (select status from public.communication_outbox_events
   where id = 'e5000000-0000-0000-0000-000000000003'),
  'submission_unknown', 'an ambiguous submission is quarantined instead of retried'
);
select is(
  (select count(*)::int from public.communication_email_usage_events
   where delivery_intent_id = 'e4000000-0000-0000-0000-000000000003'),
  0, 'an ambiguous submission is not counted before provider reconciliation'
);

select is(
  public.quarantine_stale_communication_claims(10, interval '15 minutes'),
  1, 'one stale worker lease is quarantined in the bounded batch'
);
select results_eq(
  $$select event.status, intent.status, event.claim_token is null
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.id = 'e5000000-0000-0000-0000-000000000005'$$,
  $$values ('submission_unknown'::text, 'submission_unknown'::text, true)$$,
  'a stale lease becomes unknown and cannot return to the automatic retry queue'
);

select throws_ok(
  $$set local role authenticated;
    select public.finalize_communication_outbox_event(
      'e5000000-0000-0000-0000-000000000004', 'e6000000-0000-0000-0000-000000000004',
      'cancelled', null, 'cancelled', 'Cancelled'
    )$$,
  '42501', null,
  'authenticated callers cannot execute the server-only completion command'
);
reset role;

select throws_ok(
  $$set local role anon;
    select public.finalize_communication_outbox_event(
      'e5000000-0000-0000-0000-000000000004', 'e6000000-0000-0000-0000-000000000004',
      'cancelled', null, 'cancelled', 'Cancelled'
    )$$,
  '42501', null,
  'anonymous callers cannot execute the server-only completion command'
);
reset role;

select function_privs_are(
  'public', 'finalize_communication_outbox_event',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text'], 'service_role',
  array['EXECUTE'],
  'only the service worker receives execute privilege'
);

select * from finish();
rollback;
