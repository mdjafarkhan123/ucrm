-- "Stop texting this customer": any active member can record a stop for one number, a customer's own STOP is
-- never replaced or undone by staff, and taking back a staff stop restores exactly the earlier consent.
begin;

create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'stop-owner@example.test', 'test', now(), now()),
  ('e0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'stop-office@example.test', 'test', now(), now()),
  ('e0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'stop-removed@example.test', 'test', now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e1000000-0000-0000-0000-000000000001', 'Stop Co A', 'stop-co-a', 'active'),
  ('e1000000-0000-0000-0000-000000000002', 'Stop Co B', 'stop-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status) values
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'office', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000003', 'office', 'deactivated');

insert into public.clients (id, organization_id, display_name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'Stop Client A'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'Never Agreed Client'),
  ('e2000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000002', 'Other Org Client');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'phone', '+15550000201', true),
  ('e3000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000002', 'phone', '+15550000202', true),
  ('e3000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000002',
   'e2000000-0000-0000-0000-000000000003', 'phone', '+15550000203', true),
  ('e3000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'email', 'stop-client@example.test', false);

-- Access boundary: server-only.
select function_privs_are('public', 'communication_sms_staff_stop',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'text'], 'authenticated', array[]::text[],
  'signed-in clients cannot call the stop command directly');
select function_privs_are('public', 'communication_sms_staff_stop_undo',
  array['uuid', 'uuid', 'uuid', 'uuid', 'text'], 'authenticated', array[]::text[],
  'signed-in clients cannot call the undo command directly');
select function_privs_are('public', 'communication_sms_client_stop_state',
  array['uuid', 'uuid'], 'authenticated', array[]::text[],
  'signed-in clients cannot read the stop state directly');

-- Before anything: unknown, nothing to undo.
select is(
  (select state from public.communication_sms_client_stop_state(
    'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001')),
  'unknown', 'a number with no consent evidence is unknown');
select is(
  (select count(*)::int from public.communication_sms_client_stop_state(
    'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001')),
  1, 'only phone numbers are listed, not emails');

-- Earlier consent: service + work_updates by signed agreement.
select lives_ok(
  $$select public.communication_sms_record_consent_proof(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
      'signed_agreement', array['service', 'work_updates']::text[], '2026-09-14 10:00:00+00', 'stop-proof-1')$$,
  'consent proof is recorded');
select is(
  (select state from public.communication_sms_client_stop_state(
    'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001')),
  'opted_in', 'the number can now be texted');

-- Stop: any active member may, with the actor recorded.
select throws_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000003',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', null, 'stop-deactivated')$$,
  '42501', null, 'a deactivated member cannot stop texts');
select throws_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000004', null, 'stop-email')$$,
  'P0001', null, 'only a phone number can be stopped');
select throws_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003', null, 'stop-foreign')$$,
  'P0001', null, 'a number from another organization cannot be stopped');
select lives_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
      'Asked on the phone', 'stop-1')$$,
  'an office member can stop texts');
select is(
  public.communication_sms_consent_status(
    'e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'service'),
  'opted_out', 'the stop blocks the service subject through the ordinary gate');
select is(
  public.communication_sms_consent_status(
    'e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'work_updates'),
  'opted_out', 'the stop blocks every subject');
select results_eq(
  $$select state, stopped_by, note, can_undo, stopped_by_user
    from public.communication_sms_client_stop_state(
      'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001')$$,
  $$values ('opted_out'::text, 'staff'::text, 'Asked on the phone'::text, true,
            'e0000000-0000-0000-0000-000000000002'::uuid)$$,
  'the state names staff, the note, the person, and that it can be taken back');
select is(
  (select count(*)::int from public.communication_sms_consent_events
   where organization_id = 'e1000000-0000-0000-0000-000000000001' and source_event_key = 'stop-1'),
  1, 'the stop is one append-only evidence event');
select lives_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
      'Asked on the phone', 'stop-1')$$,
  'repeating the same request key is harmless');
select is(
  (select count(*)::int from public.communication_sms_consent_events
   where organization_id = 'e1000000-0000-0000-0000-000000000001' and source_event_key = 'stop-1'),
  1, 'the repeated request added nothing');
select throws_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', null, 'stop-2')$$,
  'P0001', null, 'a second stop on an already stopped number is refused');

-- Undo restores exactly the earlier consent.
select lives_ok(
  $$select public.communication_sms_staff_stop_undo(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'undo-1')$$,
  'a staff stop can be taken back');
select results_eq(
  $$select public.communication_sms_consent_status(
      'e1000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', s)
    from unnest(array['service', 'work_updates', 'billing_updates']) s$$,
  $$values ('opted_in'::text), ('opted_in'::text), ('opted_out'::text)$$,
  'the undo restores the two subjects the customer agreed to; the third stays blocked, no consent is invented');
select is(
  (select proof_method from public.communication_sms_consent_events
   where organization_id = 'e1000000-0000-0000-0000-000000000001' and source_event_key = 'undo-1'),
  'signed_agreement', 'the undo keeps the original proof method');

-- A customer's own STOP is locked against staff.
insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
  proof_method, occurred_at)
values ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000001', 'opt_out', 'client_reply', 'customer-stop-1',
  'client_reply', clock_timestamp());
select results_eq(
  $$select stopped_by, can_undo from public.communication_sms_client_stop_state(
      'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001')$$,
  $$values ('customer'::text, false)$$,
  'a customer STOP is labelled as theirs and cannot be taken back');
select throws_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', null, 'stop-over-customer')$$,
  'P0001', null, 'staff cannot stack a stop on a customer STOP');
select throws_ok(
  $$select public.communication_sms_staff_stop_undo(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'undo-customer-stop')$$,
  'P0001', null, 'staff cannot undo a customer STOP, not even an owner');

-- Nothing to restore when the customer never agreed.
select lives_ok(
  $$select public.communication_sms_staff_stop(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', null, 'stop-never-agreed')$$,
  'a number that never agreed can still be marked stopped');
select results_eq(
  $$select can_undo from public.communication_sms_client_stop_state(
      'e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002')$$,
  $$values (false)$$, 'with no earlier consent there is nothing to take back');
select throws_ok(
  $$select public.communication_sms_staff_stop_undo(
      'e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', 'undo-never-agreed')$$,
  'P0001', null, 'the undo is refused rather than inventing consent');

select * from finish();
rollback;
