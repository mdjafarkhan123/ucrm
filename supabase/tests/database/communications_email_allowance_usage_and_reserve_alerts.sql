-- Communications Part 7.6b: when an organization uses up its protected essential reserve, the claim
-- holds the essential message, the organization is warned once through the usage read, and Jafar is
-- alerted exactly once for that billing period.

begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

-- --- Shape -----------------------------------------------------------------------------------------

select has_table(
  'public', 'communication_email_allowance_alerts',
  'the once-per-period allowance alert has a table'
);
select hasnt_trigger(
  'public', 'communication_delivery_intents',
  'communication_delivery_intents_essential_reserve_exhausted',
  'the exhaustion trigger is gone -- essential email never sets the failure_code it used to key off (Part 7)'
);
select function_privs_are(
  'public', 'get_organization_communication_email_usage', array['uuid'], 'authenticated',
  array[]::text[], 'a contractor session cannot read the usage function directly'
);

-- Park every message already due so only the fixtures below are claimable, and clear in-flight
-- reservations so this organization's counters are defined entirely by this test.
update public.communication_outbox_events
set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');
delete from public.communication_email_capacity_reservations
where reservation_state in ('reserved', 'submission_unknown');

-- --- Fixtures --------------------------------------------------------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e1000000-0000-0000-0000-000000000001', 'Reserve Org', 'reserve-org', 'active');
insert into public.communication_email_allowance_periods (id, organization_id, starts_at, ends_at) values
  ('e0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   now() - interval '1 minute', now() + interval '29 days');
insert into public.organization_package_exceptions
  (organization_id, allowance_key, allowance_state, allowance_value, reason, starts_at, ends_at,
   actor_owner_email)
-- The protected essential reserve is 10% of this allowance: two recipients (package builder, 2026-09-30).
values ('e1000000-0000-0000-0000-000000000001', 'operational_email_recipients', 'numeric', 20, 'Fixture reason.',
  now() - interval '1 minute', '2100-01-01T00:00:00Z', 'owner@example.test');

insert into public.clients (id, organization_id, display_name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'Reserve Customer');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'email', 'customer@reserve.test', true);
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state,
  provider_verified, provider_authenticated, ownership_status, dkim_status, spf_status, verified_at
) values (
  'e4000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'sending', 'sending.reserve.test', 'verified', true, true, 'passing', 'passing', 'pending',
  now() - interval '30 days'
);
insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values (
  'e5000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
  'e4000000-0000-0000-0000-000000000001', 'svc@sending.reserve.test', 'Reserve', 'enabled',
  true, true, true
);

-- Two accepted essential recipients: the whole fixture reserve is already spent.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id,
  status, accepted_at, provider_message_id
) values
  ('e6000000-0000-0000-0000-0000000000a1', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
   'reserve-prior-1', 'customer@reserve.test', 'Prior', '<p>Prior</p>', 'Prior', 'automated',
   'essential', 'e5000000-0000-0000-0000-000000000001', 'submitted', now() - interval '2 hours', 'prov-reserve-a1'),
  ('e6000000-0000-0000-0000-0000000000a2', 'e1000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
   'reserve-prior-2', 'customer@reserve.test', 'Prior', '<p>Prior</p>', 'Prior', 'automated',
   'essential', 'e5000000-0000-0000-0000-000000000001', 'submitted', now() - interval '2 hours', 'prov-reserve-a2');
insert into public.communication_email_usage_events (
  organization_id, delivery_intent_id, recipient_count, allowance_period_id, allowance_class
) values
  ('e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a1', 1,
   'e0000000-0000-0000-0000-000000000001', 'essential'),
  ('e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000a2', 1,
   'e0000000-0000-0000-0000-000000000001', 'essential');

-- --- The next essential message is claimed and sent anyway, and Jafar is alerted once --------------
-- (2026-09-24 contract change, built in Part 7: essential email never queues for an exhausted reserve.)

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'e6000000-0000-0000-0000-0000000000b1', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'reserve-held-1', 'customer@reserve.test', 'Invoice', '<p>Invoice</p>', 'Invoice', 'automated',
  'essential', 'e5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000b1');

select public.claim_communication_outbox_event();

select results_eq(
  $$select event.status, intent.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'e6000000-0000-0000-0000-0000000000b1'$$,
  $$values ('processing'::text, 'claimed'::text, null::text)$$,
  'essential mail past the reserve is claimed and sent anyway, never held'
);
select is(
  (select count(*) from public.communication_email_allowance_alerts
   where organization_id = 'e1000000-0000-0000-0000-000000000001'),
  1::bigint, 'the exhaustion is recorded once for the period'
);
select is(
  (select count(*) from public.platform_owner_notifications
   where kind = 'communication_email_essential_reserve_exhausted'
     and target_id = 'e1000000-0000-0000-0000-000000000001'),
  1::bigint, 'Jafar is alerted about the exhausted reserve'
);

-- --- A second essential message past reserve still sends, and does not alert again ------------------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'e6000000-0000-0000-0000-0000000000b2', 'e1000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  'reserve-held-2', 'customer@reserve.test', 'Receipt', '<p>Receipt</p>', 'Receipt', 'automated',
  'essential', 'e5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('e1000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-0000000000b2');

select public.claim_communication_outbox_event();

select is(
  (select count(*) from public.communication_email_allowance_alerts
   where organization_id = 'e1000000-0000-0000-0000-000000000001'),
  1::bigint, 'a second exhausted send does not record a second alert'
);
select is(
  (select count(*) from public.platform_owner_notifications
   where kind = 'communication_email_essential_reserve_exhausted'
     and target_id = 'e1000000-0000-0000-0000-000000000001'),
  1::bigint, 'a second exhausted send does not alert Jafar again'
);

-- --- The organization-facing usage read -----------------------------------------------------------

create temporary table usage_read on commit drop as
select * from public.get_organization_communication_email_usage('e1000000-0000-0000-0000-000000000001');

select is((select essential_used from usage_read), 4,
  'the read counts the 2 accepted plus the 2 exhausted-but-still-sent essential recipients (Part 7: essential never queues)');
select is((select essential_limit_value from usage_read), 2,
  'the read carries the effective essential reserve');
select ok((select essential_reserve_exhausted from usage_read),
  'the read tells the organization its essential reserve is exhausted');
select ok((select essential_reserve_exhausted_at from usage_read) is not null,
  'the read carries when the exhaustion was first detected');
select is((select optional_used from usage_read), 0,
  'no ordinary email has been spent this period');
select is((select optional_limit_state from usage_read), 'numeric',
  'the read carries the effective ordinary allowance state');
select is((select period_ends_at from usage_read),
  (select ends_at from public.communication_email_allowance_periods
   where id = 'e0000000-0000-0000-0000-000000000001'),
  'the read carries the exact period boundary the card resets on');
select is((select organization_timezone from usage_read), 'UTC',
  'the read carries a timezone for the reset date even with no settings row');

select * from finish();
rollback;
