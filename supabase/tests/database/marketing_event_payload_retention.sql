-- Data privacy Part 3 follow-up: private.trim_marketing_event_payloads empties the raw SES body of processed
-- marketing events older than 30 days and keeps every row and its counted facts. Migration
-- 20270109095000_marketing_event_payload_retention.sql.
--
-- Run as one transaction that is rolled back at the end, the same convention client_permanent_delete.sql uses.
begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

insert into public.marketing_campaign_recipient_events (
  id, provider_event_key, provider_message_id, event_kind, normalized_kind, occurred_at, received_at, payload,
  processed_at
) values
  ('b9100000-0000-0000-0000-000000000001', 'trim-test-old-processed', 'trim-msg-1', 'Bounce', 'hard_bounce',
   now() - interval '40 days', now() - interval '40 days', '{"mail": {"destination": ["old@example.test"]}}',
   now() - interval '40 days'),
  ('b9100000-0000-0000-0000-000000000002', 'trim-test-recent-processed', 'trim-msg-2', 'Delivery', 'delivered',
   now() - interval '5 days', now() - interval '5 days', '{"mail": {"destination": ["recent@example.test"]}}',
   now() - interval '5 days'),
  ('b9100000-0000-0000-0000-000000000003', 'trim-test-old-unprocessed', 'trim-msg-3', 'Delivery', null,
   now() - interval '40 days', now() - interval '40 days', '{"mail": {"destination": ["waiting@example.test"]}}',
   null);

select cmp_ok(private.trim_marketing_event_payloads(), '>=', 1, 'the trim reports what it emptied');

select is((select payload from public.marketing_campaign_recipient_events
  where id = 'b9100000-0000-0000-0000-000000000001'), '{}'::jsonb,
  'a processed event older than 30 days loses its raw body');
select is((select normalized_kind || ':' || provider_message_id from public.marketing_campaign_recipient_events
  where id = 'b9100000-0000-0000-0000-000000000001'), 'hard_bounce:trim-msg-1',
  'the row and the facts reputation counts read stay');
select is((select payload -> 'mail' -> 'destination' ->> 0 from public.marketing_campaign_recipient_events
  where id = 'b9100000-0000-0000-0000-000000000002'), 'recent@example.test',
  'a processed event inside 30 days keeps its body');
select is((select payload -> 'mail' -> 'destination' ->> 0 from public.marketing_campaign_recipient_events
  where id = 'b9100000-0000-0000-0000-000000000003'), 'waiting@example.test',
  'an event the consumer has not processed keeps its body, however old');
select ok(exists (select 1 from cron.job where jobname = 'marketing-event-payload-trim-nightly'
  and command like '%trim_marketing_event_payloads%'), 'the trim runs nightly');

select * from finish();
rollback;
