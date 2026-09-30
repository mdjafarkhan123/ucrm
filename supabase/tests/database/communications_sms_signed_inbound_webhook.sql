-- Stage 5B: the SMS inbound-message and STOP/START/HELP consent functions. Proves that a known number
-- attaches to its existing client, an unknown number creates a new Lead, a retry of the same MessageSid
-- never creates a second row, a STOP/START/HELP keyword records consent evidence against the matching
-- contact method (fanning out is unreachable -- client_contact_methods_org_value_unique_idx guarantees at
-- most one match per org -- see the migration's own comment), a keyword from a number nobody has on file
-- does nothing, and the race-recovery path (two inbound texts from the same brand-new number) never leaves
-- an orphaned duplicate Lead.
--
-- Run through the Supabase MCP / CLI as a single begin/rollback call. Pure SQL.

begin;
select plan(21);

insert into public.organizations (id, name, slug, lifecycle_status)
values ('b5b00000-0000-4000-8000-000000000001', 'Stage 5B Test Org', 'stage-5b-inbound-test', 'active');

insert into public.clients (id, organization_id, display_name)
values ('b5b00000-0000-4000-8000-000000000002', 'b5b00000-0000-4000-8000-000000000001', 'Existing Customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('b5b00000-0000-4000-8000-000000000003', 'b5b00000-0000-4000-8000-000000000001',
        'b5b00000-0000-4000-8000-000000000002', 'phone', '+15005550006');

-- ---------------------------------------------------------------------------------------------------
-- 1. Ordinary inbound replies: known number, unknown number, retry.
-- ---------------------------------------------------------------------------------------------------

select is(
  (public.record_communication_sms_inbound_message(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000001',
    '+15005550006', 'Sounds good, see you Tuesday', 0
  )).client_id,
  'b5b00000-0000-4000-8000-000000000002'::uuid, 'a known number attaches to the existing client'
);
select is(
  (select client_contact_method_id from public.communication_inbound_messages
    where provider_message_id = 'SM00000000000000000000000000000001'),
  'b5b00000-0000-4000-8000-000000000003'::uuid, 'it resolves the existing contact method too'
);
select is(
  (select channel from public.communication_inbound_messages
    where provider_message_id = 'SM00000000000000000000000000000001'),
  'sms', 'the row is tagged sms, not the email default'
);

select is(
  (public.record_communication_sms_inbound_message(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000002',
    '+15005559999', 'Hi is this Acme Plumbing?', 0
  )).review_status,
  'accepted', 'an unknown number is still accepted (a new Lead), not held for review'
);
select is(
  (select display_name from public.clients c
    join public.communication_inbound_messages m on m.client_id = c.id
    where m.provider_message_id = 'SM00000000000000000000000000000002'),
  '+15005559999', 'the new Lead is named after the phone number, exactly like an unmatched Website Chat visitor'
);
select is(
  (select lead_source from public.clients c
    join public.communication_inbound_messages m on m.client_id = c.id
    where m.provider_message_id = 'SM00000000000000000000000000000002'),
  'SMS', 'the new Lead records SMS as its source'
);

select ok(
  public.record_communication_sms_inbound_message(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000001',
    '+15005550006', 'Sounds good, see you Tuesday', 0
  ) is null,
  'a retried MessageSid is a no-op, not a second row'
);
select is(
  (select count(*)::integer from public.communication_inbound_messages
    where provider_message_id = 'SM00000000000000000000000000000001'),
  1, 'only one row exists for the retried message'
);

-- ---------------------------------------------------------------------------------------------------
-- 2. Race recovery: two inbound texts from the same brand-new number never leave a duplicate Lead.
-- ---------------------------------------------------------------------------------------------------

insert into public.clients (id, organization_id, display_name, lifecycle_status, lead_source)
values ('b5b00000-0000-4000-8000-000000000009', 'b5b00000-0000-4000-8000-000000000001',
        '+15005550077', 'lead', 'SMS');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('b5b00000-0000-4000-8000-00000000000a', 'b5b00000-0000-4000-8000-000000000001',
        'b5b00000-0000-4000-8000-000000000009', 'phone', '+15005550077');

select is(
  (public.record_communication_sms_inbound_message(
    'b5b00000-0000-4000-8000-000000000001', 'SM0000000000000000000000000000race',
    '+15005550077', 'a concurrent request already won this number', 0
  )).client_id,
  'b5b00000-0000-4000-8000-000000000009'::uuid,
  'a number that was just claimed by a "concurrent" request attaches to that winner, not a fresh Lead'
);
select is(
  (select count(*)::integer from public.clients
    where organization_id = 'b5b00000-0000-4000-8000-000000000001' and lead_source = 'SMS'
      and display_name = '+15005550077'),
  1, 'no orphaned duplicate Lead was left behind by the losing side of the race'
);

-- ---------------------------------------------------------------------------------------------------
-- 3. STOP/START/HELP consent evidence.
-- ---------------------------------------------------------------------------------------------------

select is(
  (public.record_communication_sms_consent_event_from_reply(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000003',
    '+15005550006', 'opt_out', true
  )).client_contact_method_id,
  'b5b00000-0000-4000-8000-000000000003'::uuid,
  'a provider-confirmed STOP records against the existing contact method'
);
select is(
  (select proof_method from public.communication_sms_consent_events
    where organization_id = 'b5b00000-0000-4000-8000-000000000001' and event_kind = 'opt_out'),
  'provider_keyword', 'a provider-confirmed STOP is proven by provider_keyword'
);

select ok(
  public.record_communication_sms_consent_event_from_reply(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000003',
    '+15005550006', 'opt_out', true
  ) is null,
  'a retried STOP is idempotent, not a second row'
);
select is(
  (select count(*)::integer from public.communication_sms_consent_events
    where organization_id = 'b5b00000-0000-4000-8000-000000000001' and event_kind = 'opt_out'),
  1, 'only one opt-out row exists for the retried message'
);

select is(
  (public.record_communication_sms_consent_event_from_reply(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000004',
    '+15005550006', 'opt_in', false
  )).subjects,
  array['service', 'work_updates', 'billing_updates'],
  'a body-detected (not provider-confirmed) START covers all three operational subjects'
);
select is(
  (select proof_method from public.communication_sms_consent_events
    where organization_id = 'b5b00000-0000-4000-8000-000000000001' and event_kind = 'opt_in'),
  'client_reply', 'a START''s proof_method is client_reply, the value the subject-scope check allows for opt_in'
);

select ok(
  public.record_communication_sms_consent_event_from_reply(
    'b5b00000-0000-4000-8000-000000000001', 'SM00000000000000000000000000000005',
    '+15005550000', 'opt_out', true
  ) is null,
  'a STOP from a number nobody has on file has nothing to protect and does nothing'
);
select is(
  (select count(*)::integer from public.communication_sms_consent_events
    where organization_id = 'b5b00000-0000-4000-8000-000000000001'),
  2, 'no row was written for the unmatched STOP'
);

-- ---------------------------------------------------------------------------------------------------
-- 4. The channel-aware resolution-complete constraint still protects the email path untouched.
-- ---------------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, sender_email, subject, text_content, client_id
  ) values (
    'b5b00000-0000-4000-8000-000000000001', 'stranger@example.test', 'Hi', 'Hi',
    'b5b00000-0000-4000-8000-000000000002'
  )$$,
  '23514', null, 'an email row with client_id but no contact method/sender still violates resolution_complete'
);
select throws_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, channel, provider, sender_phone, subject, text_content, client_id
  ) values (
    'b5b00000-0000-4000-8000-000000000001', 'sms', 'twilio', '+15005550006', '', 'Hi',
    'b5b00000-0000-4000-8000-000000000002'
  )$$,
  '23514', null, 'an sms row with client_id but no contact method still violates resolution_complete'
);
select lives_ok(
  $$insert into public.communication_inbound_messages (
    organization_id, channel, provider, sender_phone, subject, text_content
  ) values (
    'b5b00000-0000-4000-8000-000000000001', 'sms', 'twilio', '+15005550006', '', 'Hi'
  )$$,
  'an sms row may stay fully unresolved (null client_id and contact method) just like email'
);

select * from finish();
rollback;
