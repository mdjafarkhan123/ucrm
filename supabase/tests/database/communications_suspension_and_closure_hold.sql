-- Communications Part 8.1: suspension and closure hold contractor outbound email.
--
-- A suspended organization, and one inside its recoverable 30-day closure window, claim nothing. Their
-- queued mail is deferred and annotated, never cancelled, so reactivation and closure restore release it
-- through the ordinary claim checks. Provider callbacks keep processing throughout -- the contract keeps
-- inbound replies, unsubscribes, complaints and delivery callbacks flowing while outbound is stopped.
begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e8100000-0000-0000-0000-000000000001', 'Hold Test Suspended', 'hold-test-suspended', 'suspended'),
  ('e8100000-0000-0000-0000-000000000002', 'Hold Test Closing', 'hold-test-closing', 'active'),
  ('e8100000-0000-0000-0000-000000000003', 'Hold Test Active', 'hold-test-active', 'active');

insert into public.clients (id, organization_id, display_name) values
  ('e8200000-0000-0000-0000-000000000001', 'e8100000-0000-0000-0000-000000000001', 'Suspended Client'),
  ('e8200000-0000-0000-0000-000000000002', 'e8100000-0000-0000-0000-000000000002', 'Closing Client'),
  ('e8200000-0000-0000-0000-000000000003', 'e8100000-0000-0000-0000-000000000003', 'Active Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e8300000-0000-0000-0000-000000000001', 'e8100000-0000-0000-0000-000000000001',
   'e8200000-0000-0000-0000-000000000001', 'email', 'held@hold-test.example', true),
  ('e8300000-0000-0000-0000-000000000002', 'e8100000-0000-0000-0000-000000000002',
   'e8200000-0000-0000-0000-000000000002', 'email', 'closing@hold-test.example', true),
  ('e8300000-0000-0000-0000-000000000003', 'e8100000-0000-0000-0000-000000000003',
   'e8200000-0000-0000-0000-000000000003', 'email', 'active@hold-test.example', true);

-- The closing organization's open 30-day window.
insert into public.organization_closure_records (
  id, organization_id, reason, prior_lifecycle_status, started_by_owner_email, deadline_at, status
) values (
  'e8600000-0000-0000-0000-000000000001', 'e8100000-0000-0000-0000-000000000002',
  'Owner asked to close the account.', 'active', 'jafar@example.com', now() + interval '30 days',
  'pending_closure'
);

-- Park any send already queued in this database so the claim assertions below see only our fixture.
update public.communication_outbox_events set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
) values
  ('e8400000-0000-0000-0000-000000000001', 'e8100000-0000-0000-0000-000000000001',
   'e8200000-0000-0000-0000-000000000001', 'e8300000-0000-0000-0000-000000000001',
   'hold-test-suspended-1', 'held@hold-test.example', 'Held subject', '<p>held</p>', 'held'),
  ('e8400000-0000-0000-0000-000000000002', 'e8100000-0000-0000-0000-000000000002',
   'e8200000-0000-0000-0000-000000000002', 'e8300000-0000-0000-0000-000000000002',
   'hold-test-closing-1', 'closing@hold-test.example', 'Closing subject', '<p>closing</p>', 'closing'),
  ('e8400000-0000-0000-0000-000000000003', 'e8100000-0000-0000-0000-000000000003',
   'e8200000-0000-0000-0000-000000000003', 'e8300000-0000-0000-0000-000000000003',
   'hold-test-active-1', 'active@hold-test.example', 'Active subject', '<p>active</p>', 'active');

insert into public.communication_outbox_events (id, organization_id, delivery_intent_id, available_at) values
  ('e8500000-0000-0000-0000-000000000001', 'e8100000-0000-0000-0000-000000000001',
   'e8400000-0000-0000-0000-000000000001', now() - interval '1 minute'),
  ('e8500000-0000-0000-0000-000000000002', 'e8100000-0000-0000-0000-000000000002',
   'e8400000-0000-0000-0000-000000000002', now() - interval '1 minute'),
  ('e8500000-0000-0000-0000-000000000003', 'e8100000-0000-0000-0000-000000000003',
   'e8400000-0000-0000-0000-000000000003', now() - interval '1 minute');

-- ------------------------------------------------------------------------------------------------
-- The claim hands out nothing, and each stopped tenant is held for its own reason.
-- ------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the claim hands out no send for a suspended, closing, or otherwise ineligible fixture'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e8400000-0000-0000-0000-000000000001'),
  'organization_suspended',
  'the suspended tenant send is annotated as suspended'
);

select ok(
  (select status = 'pending' and available_at > now() + interval '50 minutes'
   from public.communication_outbox_events where id = 'e8500000-0000-0000-0000-000000000001'),
  'the suspended send is deferred on the long human-clock backoff, not cancelled'
);

select is(
  (select failure_code from public.communication_delivery_intents
   where id = 'e8400000-0000-0000-0000-000000000002'),
  'organization_closing',
  'the closing tenant send is annotated as closing'
);

select ok(
  (select status = 'pending' and available_at > now() + interval '50 minutes'
   from public.communication_outbox_events where id = 'e8500000-0000-0000-0000-000000000002'),
  'the closing send is deferred, not cancelled -- restore must be able to release it'
);

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e8400000-0000-0000-0000-000000000003'), 'none'),
  'organization_suspended',
  'an active organization is never held by the suspension branch'
);

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e8400000-0000-0000-0000-000000000003'), 'none'),
  'organization_closing',
  'an active organization is never held by the closure branch'
);

-- The hold is recorded once in the shared message history, with its retry time.
select is(
  (select count(*)::int from public.communication_message_events
   where delivery_intent_id = 'e8400000-0000-0000-0000-000000000001'
     and event_kind = 'deferred' and reason_code = 'organization_suspended'
     and retry_at > now()),
  1,
  'the suspension hold is recorded once in the message history with its retry time'
);

-- ------------------------------------------------------------------------------------------------
-- Inbound keeps flowing: a delivery callback for the suspended tenant still processes.
-- ------------------------------------------------------------------------------------------------

insert into public.communication_provider_callback_events (
  id, provider_event_key, delivery_intent_id, event_kind, occurred_at, payload
) values (
  'e8700000-0000-0000-0000-000000000001', 'hold-test-callback-1',
  'e8400000-0000-0000-0000-000000000001', 'delivered', now(), '{}'::jsonb
);

-- Its own statement: a volatile function's writes are not visible to the rest of the statement that
-- calls it, so the assertion below has to read the row afterwards.
select public.process_communication_provider_callbacks(500);

select ok(
  (select processed_at is not null and normalized_kind = 'delivered'
   from public.communication_provider_callback_events
   where id = 'e8700000-0000-0000-0000-000000000001'),
  'provider callbacks keep processing while the organization is suspended'
);

-- ------------------------------------------------------------------------------------------------
-- Reactivation and restore release the hold: the claim stops citing suspension or closure.
-- ------------------------------------------------------------------------------------------------

update public.organizations set lifecycle_status = 'active'
where id = 'e8100000-0000-0000-0000-000000000001';
update public.organization_closure_records
set status = 'restored', restored_at = now(), restored_by_owner_email = 'jafar@example.com',
  restoration_evidence_note = 'Owner changed their mind.'
where id = 'e8600000-0000-0000-0000-000000000001';
update public.communication_outbox_events set available_at = now() - interval '1 minute'
where id in ('e8500000-0000-0000-0000-000000000001', 'e8500000-0000-0000-0000-000000000002');

select is(
  (select count(*)::int from public.claim_communication_outbox_event()),
  0,
  'the released sends still fail the remaining checks -- this fixture has no sender or verified domain'
);

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e8400000-0000-0000-0000-000000000001'), 'none'),
  'organization_suspended',
  'reactivation stops the suspension hold; the claim moves on to its other checks'
);

select isnt(
  coalesce((select failure_code from public.communication_delivery_intents
   where id = 'e8400000-0000-0000-0000-000000000002'), 'none'),
  'organization_closing',
  'closure restore stops the closing hold; the claim moves on to its other checks'
);

select * from finish();
rollback;
