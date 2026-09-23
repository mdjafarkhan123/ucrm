-- Marketing M4 stage 5: marketing_cancel_campaign, and finalize_marketing_campaign_send's widened settlement
-- guard for a campaign cancelled while a recipient was still in flight.
--
-- Run this whole file as one transaction that is rolled back at the end, the same convention
-- marketing_campaign_dispatcher.sql documents. Do not run it through a runner that executes each statement
-- separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- Nobody outside server code reaches cancel. ---------------------------------------------------------------
select is(has_function_privilege('anon', 'public.marketing_cancel_campaign(uuid, uuid, uuid)', 'execute'),
  false, 'signed-out callers cannot cancel a marketing campaign');
select is(has_function_privilege('authenticated', 'public.marketing_cancel_campaign(uuid, uuid, uuid)', 'execute'),
  false, 'members cannot cancel a marketing campaign directly');

set local role postgres;

-- Fixtures --------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status, created_at)
values
  ('fc200000-0000-0000-0000-000000000001', 'Cancel Org A', 'cancel-org-a', 'active', now() - interval '40 days'),
  ('fc200000-0000-0000-0000-000000000002', 'Cancel Org B', 'cancel-org-b', 'active', now() - interval '40 days');

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values
  ('fc300000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'Still Waiting', 'person', 'customer'),
  ('fc300000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000001', 'Already Claimed', 'person', 'customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('fc400000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'fc300000-0000-0000-0000-000000000001', 'email', 'waiting@example.test', true),
  ('fc400000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000001', 'fc300000-0000-0000-0000-000000000002', 'email', 'claimed@example.test', true);

insert into public.marketing_email_allowance_periods (id, organization_id, starts_at, ends_at)
values ('fc800000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', now() - interval '1 day', now() + interval '29 days');

-- Case 1: a scheduled campaign, nothing claimed yet. ---------------------------------------------------
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, scheduled_for, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fc600000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'Scheduled Cancel Test',
  'promote_service', 'scheduled', '{}'::jsonb, now() + interval '2 days', now(), 'cancel-key-scheduled', 1, 1, 0
);
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
) values (
  'fc700000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001',
  'fc300000-0000-0000-0000-000000000001', 'fc400000-0000-0000-0000-000000000001', 'waiting@example.test', 'Still Waiting', 'waiting'
);
insert into public.marketing_email_capacity_reservations (
  id, organization_id, campaign_id, allowance_period_id, reserved_count
) values (
  'fc900000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001',
  'fc800000-0000-0000-0000-000000000001', 1
);

select is(
  (select public.marketing_cancel_campaign(
    'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001', null) ->> 'status'),
  'cancelled', 'cancelling a scheduled campaign moves it to cancelled');
select is(
  (select status from public.marketing_campaigns where id = 'fc600000-0000-0000-0000-000000000001'),
  'cancelled', 'the campaign row itself is cancelled');
select ok(
  (select cancelled_at is not null from public.marketing_campaigns where id = 'fc600000-0000-0000-0000-000000000001'),
  'cancelled_at is stamped');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fc700000-0000-0000-0000-000000000001'),
  'cancelled', 'the still-waiting recipient becomes cancelled');
select is(
  (select reservation_state from public.marketing_email_capacity_reservations where campaign_id = 'fc600000-0000-0000-0000-000000000001'),
  'settled', 'with nothing in flight, the reservation settles immediately');
select is(
  (select accepted_count from public.marketing_email_capacity_reservations where campaign_id = 'fc600000-0000-0000-0000-000000000001'),
  0, 'nothing was ever submitted, so accepted_count is zero');

-- Cancelling again is a harmless no-op, not an error. ---------------------------------------------------
select is(
  (select (public.marketing_cancel_campaign(
    'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000001', null) ->> 'cancelled_count')::int),
  0, 'cancelling an already-cancelled campaign reports zero newly-cancelled recipients, not an error');

-- Case 2: a sending campaign with one recipient already claimed (in flight) when cancel runs. -----------
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fc600000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000001', 'Sending Cancel Test',
  'promote_service', 'sending', '{}'::jsonb, now(), 'cancel-key-sending', 2, 2, 0
);
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status,
  claim_token, claimed_at, attempt_count
) values
  ('fc700000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000002',
    'fc300000-0000-0000-0000-000000000001', 'fc400000-0000-0000-0000-000000000001', 'waiting@example.test', 'Still Waiting',
    'waiting', null, null, 0),
  ('fc700000-0000-0000-0000-000000000003', 'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000002',
    'fc300000-0000-0000-0000-000000000002', 'fc400000-0000-0000-0000-000000000002', 'claimed@example.test', 'Already Claimed',
    'checking', 'cccccccc-cccc-cccc-cccc-cccccccccccc', now(), 1);
insert into public.marketing_email_capacity_reservations (
  id, organization_id, campaign_id, allowance_period_id, reserved_count
) values (
  'fc900000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000002',
  'fc800000-0000-0000-0000-000000000001', 2
);

select public.marketing_cancel_campaign(
  'fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000002', null);

select is(
  (select status from public.marketing_campaign_recipients where id = 'fc700000-0000-0000-0000-000000000002'),
  'cancelled', 'the still-waiting recipient becomes cancelled even though a sibling is in flight');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fc700000-0000-0000-0000-000000000003'),
  'checking', 'a recipient already claimed is left exactly as it was -- it must reach its real outcome');
select is(
  (select status from public.marketing_campaigns where id = 'fc600000-0000-0000-0000-000000000002'),
  'cancelled', 'the campaign itself is cancelled, stopping every future claim');
select is(
  (select reservation_state from public.marketing_email_capacity_reservations where campaign_id = 'fc600000-0000-0000-0000-000000000002'),
  'reserved', 'settlement is deferred while a recipient is still in flight');

-- The in-flight recipient reaches its real outcome after the campaign was already cancelled. finalize is what
-- settles the reservation now, and the campaign stays cancelled rather than completing.
select is(
  (select recipient_status from public.finalize_marketing_campaign_send(
    'fc700000-0000-0000-0000-000000000003', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'submitted', 'ses-msg-cancelled-flight'
  )),
  'submitted', 'the in-flight recipient still reaches SES and is recorded as submitted');
select is(
  (select status from public.marketing_campaigns where id = 'fc600000-0000-0000-0000-000000000002'),
  'cancelled', 'the campaign stays cancelled, it does not flip to completed');
select is(
  (select reservation_state from public.marketing_email_capacity_reservations where campaign_id = 'fc600000-0000-0000-0000-000000000002'),
  'settled', 'the last in-flight recipient finishing is what finally settles the reservation');
select is(
  (select accepted_count from public.marketing_email_capacity_reservations where campaign_id = 'fc600000-0000-0000-0000-000000000002'),
  1, 'accepted_count counts the one recipient that really reached SES before cancel');

-- Guardrails: a draft or completed campaign refuses to cancel; a wrong organization id finds nothing. -------
insert into public.marketing_campaigns (id, organization_id, name, goal, status, content)
values ('fc600000-0000-0000-0000-000000000003', 'fc200000-0000-0000-0000-000000000001', 'Draft Cancel Test', 'blank', 'draft', '{}'::jsonb);
select throws_ok(
  $$select public.marketing_cancel_campaign('fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000003', null)$$,
  '23514', null, 'a draft campaign refuses to cancel');

insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fc600000-0000-0000-0000-000000000004', 'fc200000-0000-0000-0000-000000000001', 'Completed Cancel Test',
  'blank', 'completed', '{}'::jsonb, now(), 'cancel-key-completed', 1, 1, 0
);
select throws_ok(
  $$select public.marketing_cancel_campaign('fc200000-0000-0000-0000-000000000001', 'fc600000-0000-0000-0000-000000000004', null)$$,
  '23514', null, 'a completed campaign refuses to cancel');

select throws_ok(
  $$select public.marketing_cancel_campaign('fc200000-0000-0000-0000-000000000002', 'fc600000-0000-0000-0000-000000000001', null)$$,
  '23514', null, 'a campaign id from another organization is not found, not cancelled across tenants');

select * from finish();
rollback;
