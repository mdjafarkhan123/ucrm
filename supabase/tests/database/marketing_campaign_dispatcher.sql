-- Marketing M4 stage 3: claim_marketing_campaign_recipient, finalize_marketing_campaign_send, and
-- quarantine_stale_marketing_campaign_claims.
--
-- Run this whole file as one transaction that is rolled back at the end, the same convention
-- marketing_campaign_launch.sql documents. Do not run it through a runner that executes each statement
-- separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- Nobody outside server code reaches the dispatcher. -----------------------------------------------------
select is(has_function_privilege('anon', 'public.claim_marketing_campaign_recipient()', 'execute'),
  false, 'signed-out callers cannot claim a marketing recipient');
select is(has_function_privilege('authenticated', 'public.claim_marketing_campaign_recipient()', 'execute'),
  false, 'members cannot claim a marketing recipient directly');
select is(has_function_privilege('authenticated',
  'public.finalize_marketing_campaign_send(uuid, uuid, text, text, text, text)', 'execute'),
  false, 'members cannot finalize a marketing send directly');
select is(has_function_privilege('authenticated',
  'public.quarantine_stale_marketing_campaign_claims(integer, interval)', 'execute'),
  false, 'members cannot quarantine marketing claims directly');

set local role postgres;

-- Fixtures --------------------------------------------------------------------------------------------
insert into public.organizations (id, name, slug, lifecycle_status, created_at)
values ('fd200000-0000-0000-0000-000000000001', 'Dispatch Org A', 'dispatch-org-a', 'active', now() - interval '40 days');

insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values
  ('fd300000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'Ready One', 'person', 'customer'),
  ('fd300000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000001', 'Unsubscribes Later', 'person', 'customer'),
  ('fd300000-0000-0000-0000-000000000003', 'fd200000-0000-0000-0000-000000000001', 'Warmup Blocked', 'person', 'customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('fd400000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'email', 'ready@example.test', true),
  ('fd400000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000002', 'email', 'later@example.test', true),
  ('fd400000-0000-0000-0000-000000000003', 'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000003', 'email', 'warmup@example.test', true);

insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
)
values
  ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'dispatch-one', now()),
  ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000002', 'fd400000-0000-0000-0000-000000000002', 'opt_in', 'staff', 'dispatch-two', now()),
  ('fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000003', 'fd400000-0000-0000-0000-000000000003', 'opt_in', 'staff', 'dispatch-three', now());

-- The org's Marketing identity: verified, and just past its warmup start so the days_1_3 platform default
-- ceiling (100/day) applies.
insert into public.communication_email_domains (
  id, organization_id, purpose, domain_name, lifecycle_state, provider, provider_verified,
  provider_authenticated, ownership_status, dkim_status, spf_status, verified_at, warmup_started_at
) values (
  'fd500000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'marketing_sending',
  'news.dispatch-org-a.test', 'verified', 'ses', true, true, 'passing', 'passing', 'passing',
  now() - interval '1 day', now() - interval '1 day'
);

-- A campaign already in flight, as a real launch would leave it: two waiting recipients and its allowance
-- reservation already held.
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launched_by, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fd600000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'Dispatch Test Campaign',
  'promote_service', 'sending', '{}'::jsonb, now(), null, 'dispatch-key-one', 2, 2, 0
);

insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
) values
  ('fd700000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001',
    'fd300000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', 'ready@example.test', 'Ready One', 'waiting'),
  ('fd700000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001',
    'fd300000-0000-0000-0000-000000000002', 'fd400000-0000-0000-0000-000000000002', 'later@example.test', 'Unsubscribes Later', 'waiting');

insert into public.marketing_email_allowance_periods (id, organization_id, starts_at, ends_at)
values ('fd800000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', now() - interval '1 day', now() + interval '29 days');

insert into public.marketing_email_capacity_reservations (
  id, organization_id, campaign_id, allowance_period_id, reserved_count
) values (
  'fd900000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001',
  'fd800000-0000-0000-0000-000000000001', 2
);

-- A platform-wide pause stops every organization at once. -------------------------------------------------
insert into public.communication_email_sending_pauses (id, scope, applies_to, source, reason, engaged_by_owner_email)
values ('fda00000-0000-0000-0000-000000000001', 'platform', 'all', 'manual', 'Dispatcher test pause', 'owner@example.test');

select is_empty(
  $$select * from public.claim_marketing_campaign_recipient()$$,
  'a platform-wide sending pause blocks every claim');

delete from public.communication_email_sending_pauses where id = 'fda00000-0000-0000-0000-000000000001';

-- The customer who will unsubscribe changes their mind before their turn comes up. --------------------
insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values (
  'fd200000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000002', 'fd400000-0000-0000-0000-000000000002',
  'opt_out', 'unsubscribe', 'dispatch-two-out', now() + interval '1 hour'
);

-- First claim: the still-consented recipient comes back; the freshly unsubscribed one is excluded, not
-- returned, and never claimed as a send.
select results_eq(
  $$select recipient_id, recipient_email from public.claim_marketing_campaign_recipient()$$,
  $$values ('fd700000-0000-0000-0000-000000000001'::uuid, 'ready@example.test'::text)$$,
  'claim returns the one recipient who still passes an eligibility recheck');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000001'),
  'checking', 'the claimed row moves to checking');
select ok(
  (select claim_token is not null and claimed_at is not null from public.marketing_campaign_recipients
   where id = 'fd700000-0000-0000-0000-000000000001'),
  'the claimed row carries a live claim token and timestamp');
select is(
  (select attempt_count from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000001'),
  1, 'the claim counts as this row''s first attempt');

-- A second claim call is what actually reaches the second recipient (the first call stopped as soon as it
-- claimed one row): it discovers the now-unsubscribed customer, excludes them, and then finds nothing else
-- claimable in the same call.
select is_empty(
  $$select * from public.claim_marketing_campaign_recipient()$$,
  'nothing else is claimable once the only two recipients are checking/excluded');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000002'),
  'excluded', 'the customer who unsubscribed before their turn is excluded, not sent');
select is(
  (select excluded_reason from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000002'),
  'unsubscribed', 'the exclusion carries the real reason');

-- Finalize: a stale or mismatched claim token is refused. --------------------------------------------------
select throws_ok(
  $$select public.finalize_marketing_campaign_send('fd700000-0000-0000-0000-000000000001', gen_random_uuid(), 'submitted', 'ses-msg-wrong')$$,
  '55000', null, 'finalize refuses a claim token that does not match the live claim');

-- Finalize: submitting the last recipient completes the campaign and settles its reservation. ---------------
select is(
  (select recipient_status from public.finalize_marketing_campaign_send(
    'fd700000-0000-0000-0000-000000000001',
    (select claim_token from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000001'),
    'submitted', 'ses-msg-one'
  )),
  'submitted', 'a submitted outcome marks the recipient submitted');
select is(
  (select status from public.marketing_campaigns where id = 'fd600000-0000-0000-0000-000000000001'),
  'completed', 'the campaign completes once nothing is left waiting or checking');
select is(
  (select reservation_state from public.marketing_email_capacity_reservations where campaign_id = 'fd600000-0000-0000-0000-000000000001'),
  'settled', 'the campaign''s reservation settles on completion');
select is(
  (select accepted_count from public.marketing_email_capacity_reservations where campaign_id = 'fd600000-0000-0000-0000-000000000001'),
  1, 'accepted_count counts only what was actually submitted, not the excluded customer');
select is(
  (select provider_message_id from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000001'),
  'ses-msg-one', 'the provider message id is recorded');

-- Retry semantics on a second campaign: back to waiting until the third attempt, then a permanent failure. --
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fd600000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000001', 'Retry Test Campaign',
  'promote_service', 'sending', '{}'::jsonb, now(), 'dispatch-key-retry', 1, 1, 0
);
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
) values (
  'fd700000-0000-0000-0000-000000000003', 'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000002',
  'fd300000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', 'ready@example.test', 'Ready One', 'waiting'
);

select public.claim_marketing_campaign_recipient();
select is(
  (select recipient_status from public.finalize_marketing_campaign_send(
    'fd700000-0000-0000-0000-000000000003',
    (select claim_token from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000003'),
    'retry', 'ses_throttled', 'SES asked us to slow down.'
  )),
  'waiting', 'the first retryable failure goes back to waiting, not permanently failed');
select is(
  (select attempt_count from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000003'),
  1, 'attempt_count is preserved across a retry so a third failure can be recognised');

select public.claim_marketing_campaign_recipient();
select public.finalize_marketing_campaign_send(
  'fd700000-0000-0000-0000-000000000003',
  (select claim_token from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000003'),
  'retry', 'ses_throttled', 'SES asked us to slow down.'
);
select public.claim_marketing_campaign_recipient();
select is(
  (select recipient_status from public.finalize_marketing_campaign_send(
    'fd700000-0000-0000-0000-000000000003',
    (select claim_token from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000003'),
    'retry', 'ses_throttled', 'SES asked us to slow down.'
  )),
  'failed', 'the third retryable failure gives up rather than retrying forever');

-- Quarantine: a claim a crashed worker never finalized becomes submission_unknown, never waiting. -----------
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fd600000-0000-0000-0000-000000000003', 'fd200000-0000-0000-0000-000000000001', 'Quarantine Test Campaign',
  'promote_service', 'sending', '{}'::jsonb, now(), 'dispatch-key-quarantine', 1, 1, 0
);
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name,
  status, claim_token, claimed_at, attempt_count
) values (
  'fd700000-0000-0000-0000-000000000004', 'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000003',
  'fd300000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', 'ready@example.test', 'Ready One',
  'checking', gen_random_uuid(), now() - interval '30 minutes', 1
);

select is(
  public.quarantine_stale_marketing_campaign_claims(50, interval '15 minutes'),
  1, 'quarantine reclaims exactly the one abandoned claim');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000004'),
  'submission_unknown', 'an abandoned claim becomes submission_unknown, never a blind retry');
select ok(
  (select claim_token is null and claimed_at is null from public.marketing_campaign_recipients
   where id = 'fd700000-0000-0000-0000-000000000004'),
  'quarantine clears the claim token and timestamp');

-- Warmup ceiling: a Marketing warm-up override of 1/day stops a second send on the same day. -----------------
insert into public.marketing_warmup_state (domain_id, organization_id, step, step_started_at, limit_override)
values ('fd500000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 1, now() - interval '1 day', 1)
on conflict (domain_id) do update set limit_override = excluded.limit_override;
insert into public.marketing_campaigns (
  id, organization_id, name, goal, status, content, launched_at, launch_idempotency_key,
  recipient_total_count, recipient_eligible_count, recipient_excluded_count
) values (
  'fd600000-0000-0000-0000-000000000004', 'fd200000-0000-0000-0000-000000000001', 'Warmup Test Campaign',
  'promote_service', 'sending', '{}'::jsonb, now(), 'dispatch-key-warmup', 1, 1, 0
);
insert into public.marketing_campaign_recipients (
  id, organization_id, campaign_id, client_id, client_contact_method_id, recipient_email, display_name, status
) values (
  'fd700000-0000-0000-0000-000000000005', 'fd200000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000004',
  'fd300000-0000-0000-0000-000000000003', 'fd400000-0000-0000-0000-000000000003', 'warmup@example.test', 'Warmup Blocked', 'waiting'
);

-- The campaign completed earlier in this file already submitted one email today, which is this
-- organization's whole ceiling of 1 under the override just inserted.
select is_empty(
  $$select * from public.claim_marketing_campaign_recipient()$$,
  'a warmed-up organization at its daily ceiling gets nothing claimed today');
select is(
  (select status from public.marketing_campaign_recipients where id = 'fd700000-0000-0000-0000-000000000005'),
  'waiting', 'the ceiling-blocked recipient is left waiting for tomorrow, not failed');

select * from finish();
rollback;
