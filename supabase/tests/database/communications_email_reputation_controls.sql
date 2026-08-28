-- Communications Part 7.4: reputation rates, configurable thresholds, and the optional-only
-- automatic pause. Rates are measured over rolling windows; an organization override may only
-- tighten the platform ceiling; a breach pauses optional mail and only Jafar resumes it.
begin;

create extension if not exists pgtap with schema extensions;
select plan(35);

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d8100000-0000-0000-0000-000000000001', 'Reputation Test A', 'reputation-test-a', 'active'),
  ('d8100000-0000-0000-0000-000000000002', 'Reputation Test B', 'reputation-test-b', 'active'),
  ('d8100000-0000-0000-0000-000000000003', 'Reputation Test C', 'reputation-test-c', 'active');

insert into public.clients (id, organization_id, display_name) values
  ('d8200000-0000-0000-0000-000000000001', 'd8100000-0000-0000-0000-000000000001', 'Reputation Client A'),
  ('d8200000-0000-0000-0000-000000000002', 'd8100000-0000-0000-0000-000000000002', 'Reputation Client B'),
  ('d8200000-0000-0000-0000-000000000003', 'd8100000-0000-0000-0000-000000000003', 'Reputation Client C');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary) values
  ('d8300000-0000-0000-0000-000000000001', 'd8100000-0000-0000-0000-000000000001',
   'd8200000-0000-0000-0000-000000000001', 'email', 'watched@reputation-test.example', true),
  ('d8300000-0000-0000-0000-000000000002', 'd8100000-0000-0000-0000-000000000002',
   'd8200000-0000-0000-0000-000000000002', 'email', 'small@reputation-test.example', true),
  ('d8300000-0000-0000-0000-000000000003', 'd8100000-0000-0000-0000-000000000003',
   'd8200000-0000-0000-0000-000000000003', 'email', 'measured@reputation-test.example', true);

-- Park any send already queued in this database so the claim assertions below see only our fixture.
update public.communication_outbox_events set available_at = 'infinity'::timestamptz
where status in ('pending', 'failed');

-- ------------------------------------------------------------------------------------------------
-- Contract defaults
-- ------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.communication_email_reputation_thresholds
   where scope = 'platform' and effective_to is null),
  6,
  'three signals across two rolling windows are seeded as the platform ceiling'
);

select is(
  (select pause_rate from public.communication_email_reputation_thresholds
   where scope = 'platform' and signal = 'complaint' and window_key = 'rolling_24h'
     and effective_to is null),
  0.1000::numeric,
  'the complaint pause threshold is the contract default of 0.10%'
);

select is(
  (select min_event_count from public.communication_email_reputation_thresholds
   where scope = 'platform' and signal = 'hard_bounce' and window_key = 'rolling_24h'
     and effective_to is null),
  20,
  'the hard-bounce early trigger is 20 events'
);

-- ------------------------------------------------------------------------------------------------
-- Threshold resolution: an override may only tighten
-- ------------------------------------------------------------------------------------------------

select is(
  (select pause_rate from private.communication_email_effective_reputation_thresholds(
     'd8100000-0000-0000-0000-000000000001', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  0.1000::numeric,
  'an organization with no override inherits the ceiling'
);

select throws_ok(
  $$select public.set_communication_email_reputation_threshold(
      'organization', 'd8100000-0000-0000-0000-000000000001', 'complaint', 'rolling_24h',
      null, null, 5.0, null, null, 'too generous', 'jafar@example.com')$$,
  '23514',
  null,
  'an organization pause rate above the platform ceiling is rejected'
);

select lives_ok(
  $$select public.set_communication_email_reputation_threshold(
      'organization', 'd8100000-0000-0000-0000-000000000001', 'complaint', 'rolling_24h',
      null, null, 0.0600, null, null, 'stricter while under review', 'JAFAR@Example.com')$$,
  'a stricter organization override is accepted'
);

select is(
  (select pause_rate from private.communication_email_effective_reputation_thresholds(
     'd8100000-0000-0000-0000-000000000001', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  0.0600::numeric,
  'the stricter override wins'
);

select is(
  (select warn_rate from private.communication_email_effective_reputation_thresholds(
     'd8100000-0000-0000-0000-000000000001', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  0.0500::numeric,
  'fields the override leaves alone still come from the ceiling'
);

-- A weaker row that somehow reaches the table directly still cannot weaken the ceiling.
insert into public.communication_email_reputation_thresholds (
  scope, organization_id, signal, window_key, pause_rate, reason, actor_owner_email
) values (
  'organization', 'd8100000-0000-0000-0000-000000000002', 'complaint', 'rolling_24h', 9.0000,
  'inserted behind the command', 'rogue@example.com'
);

select is(
  (select pause_rate from private.communication_email_effective_reputation_thresholds(
     'd8100000-0000-0000-0000-000000000002', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  0.1000::numeric,
  'resolution clamps a weaker override back to the platform ceiling'
);

select throws_ok(
  $$select public.set_communication_email_reputation_threshold(
      'platform', null, 'unsubscribe', 'rolling_7d', 168, 0.4, 0.8, 1000, null,
      'tightening', 'jafar@example.com')$$,
  '23514',
  null,
  'changing the platform ceiling without confirmation is refused'
);

select is(
  (public.set_communication_email_reputation_threshold(
     'platform', null, 'unsubscribe', 'rolling_7d', 168, 0.4, 0.8, 1000, null,
     'tightening after a provider warning', 'jafar@example.com', true)
   ->> 'organization_overrides_affected')::int,
  0,
  'a confirmed platform change reports its impact'
);

select is(
  (select count(*)::int from public.communication_email_reputation_thresholds
   where scope = 'platform' and signal = 'unsubscribe' and window_key = 'rolling_7d'),
  2,
  'the superseded ceiling row is kept as history'
);

-- ------------------------------------------------------------------------------------------------
-- Measurement
-- ------------------------------------------------------------------------------------------------

-- Organization C: 2,000 accepted recipients and 3 complaints in the last 24 hours = 0.15%.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
)
select
  ('d8400000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
  'd8100000-0000-0000-0000-000000000003',
  'd8200000-0000-0000-0000-000000000003', 'd8300000-0000-0000-0000-000000000003',
  'reputation-measured-' || g, 'measured@reputation-test.example', 'S', '<p>s</p>', 's'
from generate_series(1, 3) g;

insert into public.communication_email_usage_events (organization_id, delivery_intent_id, recipient_count, occurred_at)
values ('d8100000-0000-0000-0000-000000000003', 'd8400000-0000-0000-0000-000000000001', 2000,
  now() - interval '2 hours');

insert into public.communication_provider_callback_events (
  provider_event_key, event_kind, delivery_intent_id, payload, organization_id, normalized_kind,
  processed_at, occurred_at
)
select 'reputation-complaint-' || g, 'spam',
  ('d8400000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
  '{}'::jsonb, 'd8100000-0000-0000-0000-000000000003', 'complaint', now(), now() - interval '1 hour'
from generate_series(1, 3) g;

select is(
  (select rate from private.communication_email_reputation_metrics(
     'd8100000-0000-0000-0000-000000000003', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  0.1500::numeric,
  'the complaint rate is complaints over accepted recipients in the window'
);

select is(
  (select status from private.communication_email_reputation_metrics(
     'd8100000-0000-0000-0000-000000000003', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  'pause',
  'a rate above the pause threshold with a full sample is a pause'
);

select is(
  (select status from private.communication_email_reputation_metrics(
     'd8100000-0000-0000-0000-000000000003', now())
   where signal = 'hard_bounce' and window_key = 'rolling_24h'),
  'ok',
  'a signal with no events stays ok'
);

-- Organization B: only 100 accepted recipients, but 3 complaints -- the early event trigger fires.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
)
select
  ('d8410000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
  'd8100000-0000-0000-0000-000000000002',
  'd8200000-0000-0000-0000-000000000002', 'd8300000-0000-0000-0000-000000000002',
  'reputation-small-' || g, 'small@reputation-test.example', 'S', '<p>s</p>', 's'
from generate_series(1, 3) g;

insert into public.communication_email_usage_events (organization_id, delivery_intent_id, recipient_count, occurred_at)
values ('d8100000-0000-0000-0000-000000000002', 'd8410000-0000-0000-0000-000000000001', 100,
  now() - interval '2 hours');

insert into public.communication_provider_callback_events (
  provider_event_key, event_kind, delivery_intent_id, payload, organization_id, normalized_kind,
  processed_at, occurred_at
)
select 'reputation-small-complaint-' || g, 'spam',
  ('d8410000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
  '{}'::jsonb, 'd8100000-0000-0000-0000-000000000002', 'complaint', now(), now() - interval '1 hour'
from generate_series(1, 3) g;

select is(
  (select status from private.communication_email_reputation_metrics(
     'd8100000-0000-0000-0000-000000000002', now())
   where signal = 'complaint' and window_key = 'rolling_24h'),
  'pause',
  'three complaints pause a small sender before the 1,000-recipient sample'
);

-- ------------------------------------------------------------------------------------------------
-- Automatic pause
-- ------------------------------------------------------------------------------------------------

select is(
  (public.evaluate_communication_email_reputation('d8100000-0000-0000-0000-000000000003', now())
   ->> 'paused')::boolean,
  true,
  'evaluating a breaching organization engages the pause'
);

select is(
  (select applies_to from public.communication_email_sending_pauses
   where organization_id = 'd8100000-0000-0000-0000-000000000003'
     and source = 'auto_reputation' and released_at is null),
  'optional',
  'the automatic pause holds optional mail only'
);

select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'communications.email_reputation_pause_engaged'),
  1,
  'engaging the automatic pause wrote one owner audit event'
);

select public.evaluate_communication_email_reputation('d8100000-0000-0000-0000-000000000003', now());

select is(
  (select count(*)::int from public.communication_email_sending_pauses
   where organization_id = 'd8100000-0000-0000-0000-000000000003' and source = 'auto_reputation'),
  1,
  're-evaluating does not open a second pause'
);

select is(
  (select worst_status from public.communication_email_reputation_state
   where organization_id = 'd8100000-0000-0000-0000-000000000003'),
  'pause',
  'the evaluation is recorded as derived state'
);

-- A manual freeze and the automatic pause can be live on the same tenant at once.
select lives_ok(
  $$select public.set_communication_email_organization_pause(
      'd8100000-0000-0000-0000-000000000003', true, 'manual investigation', 'jafar@example.com')$$,
  'a manual pause can be engaged alongside the automatic one'
);

select is(
  (select count(*)::int from public.communication_email_sending_pauses
   where organization_id = 'd8100000-0000-0000-0000-000000000003' and released_at is null),
  2,
  'both pauses are live'
);

select public.set_communication_email_organization_pause(
  'd8100000-0000-0000-0000-000000000003', false, 'manual review finished', 'jafar@example.com');

select is(
  (select count(*)::int from public.communication_email_sending_pauses
   where organization_id = 'd8100000-0000-0000-0000-000000000003'
     and source = 'auto_reputation' and released_at is null),
  1,
  'releasing the manual pause never touches the automatic one'
);

-- ------------------------------------------------------------------------------------------------
-- The claim: optional mail is held, essential mail is not
-- ------------------------------------------------------------------------------------------------

insert into public.communication_email_sending_pauses (
  scope, organization_id, reason, engaged_by_owner_email, source, applies_to
) values (
  'organization', 'd8100000-0000-0000-0000-000000000001', 'complaint rate breach', 'system',
  'auto_reputation', 'optional'
);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content, allowance_class
) values
  ('d8500000-0000-0000-0000-000000000001', 'd8100000-0000-0000-0000-000000000001',
   'd8200000-0000-0000-0000-000000000001', 'd8300000-0000-0000-0000-000000000001',
   'reputation-optional-1', 'watched@reputation-test.example', 'Optional', '<p>o</p>', 'o', 'optional'),
  ('d8500000-0000-0000-0000-000000000002', 'd8100000-0000-0000-0000-000000000001',
   'd8200000-0000-0000-0000-000000000001', 'd8300000-0000-0000-0000-000000000001',
   'reputation-essential-1', 'watched@reputation-test.example', 'Essential', '<p>e</p>', 'e', 'essential');

insert into public.communication_outbox_events (id, organization_id, delivery_intent_id, available_at)
values
  ('d8600000-0000-0000-0000-000000000001', 'd8100000-0000-0000-0000-000000000001',
   'd8500000-0000-0000-0000-000000000001', now() - interval '1 minute'),
  ('d8600000-0000-0000-0000-000000000002', 'd8100000-0000-0000-0000-000000000001',
   'd8500000-0000-0000-0000-000000000002', now() - interval '1 minute');

select lives_ok(
  $$select * from public.claim_communication_outbox_event()$$,
  'the claim runs with a reputation pause live'
);

select ok(
  (select failure_code from public.communication_delivery_intents
   where id = 'd8500000-0000-0000-0000-000000000001') = 'sending_paused_reputation'
  and (select status from public.communication_outbox_events
   where id = 'd8600000-0000-0000-0000-000000000001') = 'pending'
  and (select available_at > now() from public.communication_outbox_events
   where id = 'd8600000-0000-0000-0000-000000000001'),
  'optional mail is deferred and annotated by the reputation pause'
);

select isnt(
  (select failure_code from public.communication_delivery_intents
   where id = 'd8500000-0000-0000-0000-000000000002'),
  'sending_paused_reputation',
  'essential mail is not held by a reputation pause'
);

-- ------------------------------------------------------------------------------------------------
-- Resume: Jafar only, confirmed while still breaching, and never releasing stale optional mail
-- ------------------------------------------------------------------------------------------------

select is(
  (public.resume_communication_email_reputation_pause(
     'd8100000-0000-0000-0000-000000000002', 'nothing paused here', 'jafar@example.com')
   ->> 'released')::boolean,
  false,
  'resuming an organization with no automatic pause is a no-op'
);

select throws_ok(
  $$select public.resume_communication_email_reputation_pause(
      'd8100000-0000-0000-0000-000000000003', 'looks fine now', 'jafar@example.com')$$,
  '23514',
  null,
  'resuming while still breaching requires remediation confirmation'
);

-- Age the held optional send past the 24-hour optional retry ceiling.
update public.communication_delivery_intents
set created_at = now() - interval '30 hours'
where id = 'd8500000-0000-0000-0000-000000000001';

select is(
  (public.resume_communication_email_reputation_pause(
     'd8100000-0000-0000-0000-000000000001', 'remediation complete', 'jafar@example.com', true)
   ->> 'expired_optional_messages')::int,
  1,
  'resuming cancels the stale optional backlog instead of releasing it'
);

select is(
  (select status from public.communication_outbox_events
   where id = 'd8600000-0000-0000-0000-000000000001'),
  'cancelled',
  'the stale optional send is cancelled'
);

-- ------------------------------------------------------------------------------------------------
-- The sweep queue: an adverse callback flags its organization, the sweep drains the flag
-- ------------------------------------------------------------------------------------------------

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, logical_send_key,
  recipient_email, subject, html_content, text_content
) values (
  'd8400000-0000-0000-0000-000000000009', 'd8100000-0000-0000-0000-000000000002',
  'd8200000-0000-0000-0000-000000000002', 'd8300000-0000-0000-0000-000000000002',
  'reputation-sweep-queue-1', 'small@reputation-test.example', 'Queued', '<p>q</p>', 'q'
);

insert into public.communication_provider_callback_events (
  provider, provider_event_key, delivery_intent_id, event_kind, payload, received_at
) values (
  'brevo', 'reputation-sweep-queue-1', 'd8400000-0000-0000-0000-000000000009', 'spam', '{}'::jsonb, now()
);

select ok(
  public.process_communication_provider_callbacks(500) >= 1,
  'the callback processor handles the new complaint'
);

select ok(
  (select evaluation_requested_at is not null from public.communication_email_reputation_state
   where organization_id = 'd8100000-0000-0000-0000-000000000002'),
  'processing an adverse event queues its organization for re-evaluation'
);

select ok(
  public.sweep_communication_email_reputation(200) >= 1,
  'the sweep evaluates the queued organization'
);

select ok(
  (select evaluation_requested_at is null and metrics <> '[]'::jsonb
   from public.communication_email_reputation_state
   where organization_id = 'd8100000-0000-0000-0000-000000000002'),
  'the swept organization is measured and its request cleared'
);

select * from finish();
rollback;
