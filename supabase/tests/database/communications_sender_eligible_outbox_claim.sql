-- Communications Part 2: the worker receives sender authority only from the atomic database claim.
begin;

create extension if not exists pgtap with schema extensions;
select plan(16);

select has_column(
  'public', 'communication_delivery_intents', 'send_kind',
  'queued email records whether it is manual or automated'
);
select has_column(
  'public', 'communication_delivery_intents', 'sender_id',
  'queued email retains its sender preference'
);
select has_index(
  'public', 'communication_delivery_intents', 'communication_delivery_intents_sender_idx',
  'queued sender references have a narrow foreign-key index'
);
select function_privs_are(
  'public', 'claim_communication_outbox_event', array[]::text[], 'service_role',
  array['EXECUTE'],
  'only the service worker can execute the sender-resolving claim'
);

insert into public.organizations (id, name, slug, lifecycle_status)
values ('f1000000-0000-0000-0000-000000000001', 'Sender Claim Test', 'sender-claim-test', 'active');

insert into public.communication_email_allowance_periods (organization_id, starts_at, ends_at)
values ('f1000000-0000-0000-0000-000000000001', now() - interval '1 minute', now() + interval '29 days');

select public.apply_organization_limit_exception(
  'f1000000-0000-0000-0000-000000000001', 'operational_email_recipients', 'numeric', 1,
  now() - interval '1 minute', null, 'sender-claim-operational-capacity',
  'Keep the sender-claim fixture to one optional recipient.', 'owner@example.test'
);
select public.apply_organization_limit_exception(
  'f1000000-0000-0000-0000-000000000001', 'essential_email_recipients', 'numeric', 1,
  now() - interval '1 minute', null, 'sender-claim-essential-capacity',
  'Keep the sender-claim fixture to one essential recipient.', 'owner@example.test'
);

insert into public.clients (id, organization_id, display_name)
values (
  'f2000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'Sender Claim Customer'
);

insert into public.client_contact_methods (
  id, organization_id, client_id, kind, value, is_primary
) values (
  'f3000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001',
  'email', 'customer@sender-claim.test', true
);

insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state,
  provider_verified, provider_authenticated, ownership_status, dkim_status, spf_status
) values
  ('f4000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'sending', 'mail.sender-claim.test', 'verified', true, true, 'passing', 'passing', 'pending'),
  ('f4000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'sending', 'waiting.sender-claim.test', 'verified', true, true, 'passing', 'passing', 'passing');

insert into public.communication_email_senders (
  id, organization_id, domain_id, email_address, display_name, lifecycle_state,
  is_organization_default, allows_manual, allows_automated
) values
  ('f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f4000000-0000-0000-0000-000000000001', 'service@mail.sender-claim.test', 'Sender Claim',
   'enabled', true, true, true),
  ('f5000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'f4000000-0000-0000-0000-000000000001', 'disabled@mail.sender-claim.test', 'Disabled',
   'disabled', false, false, false),
  ('f5000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001',
   'f4000000-0000-0000-0000-000000000002', 'service@waiting.sender-claim.test', 'Waiting',
   'enabled', false, true, true);

-- A sender can become temporarily ineligible when a previously healthy domain regresses.
update public.communication_email_domains
set lifecycle_state = 'unhealthy', provider_verified = false, provider_authenticated = false,
  ownership_status = 'failing', dkim_status = 'failing', spf_status = 'failing'
where id = 'f4000000-0000-0000-0000-000000000002';

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, sender_id
) values
  ('f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
   'claim-manual-review', 'customer@sender-claim.test', 'Manual', '<p>Manual</p>', 'Manual',
   'manual', null),
  ('f6000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
   'claim-automated-cancel', 'customer@sender-claim.test', 'Automated', '<p>Automated</p>', 'Automated',
   'automated', 'f5000000-0000-0000-0000-000000000002'),
  ('f6000000-0000-0000-0000-000000000003', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
   'claim-temporary-domain', 'customer@sender-claim.test', 'Temporary', '<p>Temporary</p>', 'Temporary',
   'automated', 'f5000000-0000-0000-0000-000000000003'),
  ('f6000000-0000-0000-0000-000000000004', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
   'claim-eligible', 'customer@sender-claim.test', 'Eligible', '<p>Eligible</p>', 'Eligible',
   'automated', 'f5000000-0000-0000-0000-000000000001');

insert into public.communication_outbox_events (organization_id, delivery_intent_id)
select 'f1000000-0000-0000-0000-000000000001', id
from public.communication_delivery_intents
where id in (
  'f6000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000002',
  'f6000000-0000-0000-0000-000000000003', 'f6000000-0000-0000-0000-000000000004'
);

create temporary table claimed_sender on commit drop as
select * from public.claim_communication_outbox_event();
-- The eligible row may sort before an invalid row. A second pass settles every remaining due row.
select public.claim_communication_outbox_event();

select is(
  (select delivery_intent_id from claimed_sender),
  'f6000000-0000-0000-0000-000000000004'::uuid,
  'the claim skips blocked work and leases one eligible message'
);
select results_eq(
  $$select sender_id, sender_email, sender_name from claimed_sender$$,
  $$values (
    'f5000000-0000-0000-0000-000000000001'::uuid,
    'service@mail.sender-claim.test'::text,
    'Sender Claim'::text
  )$$,
  'the claim returns the sender resolved from stored UCRM authority'
);
select results_eq(
  $$select status, failure_code from public.communication_delivery_intents
    where id = 'f6000000-0000-0000-0000-000000000001'$$,
  $$values ('failed'::text, 'manual_sender_review_required'::text)$$,
  'an invalid manual sender is held for review'
);
select ok(
  (select status = 'failed' and available_at = 'infinity'::timestamptz and claim_token is null
   from public.communication_outbox_events
   where delivery_intent_id = 'f6000000-0000-0000-0000-000000000001'),
  'a manual review hold cannot enter the automatic retry queue'
);
select results_eq(
  $$select status, failure_code from public.communication_delivery_intents
    where id = 'f6000000-0000-0000-0000-000000000002'$$,
  $$values ('cancelled'::text, 'automated_sender_invalid'::text)$$,
  'an invalid configured automated sender is cancelled'
);
select ok(
  (select status = 'pending' and available_at > now() and claim_token is null
   from public.communication_outbox_events
   where delivery_intent_id = 'f6000000-0000-0000-0000-000000000003'),
  'temporary domain failure is deferred without taking a worker lease'
);
select ok(
  (select event.status = 'processing' and event.claim_token = claimed.claim_token
   from public.communication_outbox_events event
   cross join claimed_sender claimed
   where event.delivery_intent_id = 'f6000000-0000-0000-0000-000000000004'),
  'the eligible message and returned sender share one atomic claim lease'
);
select ok(
  exists (
    select 1 from public.communication_email_capacity_reservations reservation
    where reservation.delivery_intent_id = 'f6000000-0000-0000-0000-000000000004'
      and reservation.allowance_class = 'optional' and reservation.reservation_state = 'reserved'
  ),
  'an optional claim holds a recipient slot before the provider call'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'f6000000-0000-0000-0000-000000000005', 'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
  'claim-essential', 'customer@sender-claim.test', 'Essential', '<p>Essential</p>', 'Essential',
  'automated', 'essential', 'f5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('f1000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000005');
create temporary table claimed_essential on commit drop as
select * from public.claim_communication_outbox_event();
select is(
  (select delivery_intent_id from claimed_essential),
  'f6000000-0000-0000-0000-000000000005'::uuid,
  'essential mail can claim its protected reserve after optional capacity is held'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, send_kind, allowance_class, sender_id
) values (
  'f6000000-0000-0000-0000-000000000006', 'f1000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
  'claim-optional-over-limit', 'customer@sender-claim.test', 'Optional', '<p>Optional</p>', 'Optional',
  'automated', 'optional', 'f5000000-0000-0000-0000-000000000001'
);
insert into public.communication_outbox_events (organization_id, delivery_intent_id)
values ('f1000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000006');
select public.claim_communication_outbox_event();
select results_eq(
  $$select event.status, intent.failure_code
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.delivery_intent_id = 'f6000000-0000-0000-0000-000000000006'$$,
  $$values ('pending'::text, 'email_allowance_exhausted'::text)$$,
  'optional mail stays queued when normal capacity is fully reserved'
);
select throws_ok(
  $$set local role authenticated; select public.claim_communication_outbox_event()$$,
  '42501', null,
  'authenticated callers cannot claim contractor email'
);
reset role;
select throws_ok(
  $$set local role anon; select public.claim_communication_outbox_event()$$,
  '42501', null,
  'anonymous callers cannot claim contractor email'
);

select * from finish();
rollback;
