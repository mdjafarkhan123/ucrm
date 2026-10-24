-- Data privacy Part 3 follow-up: keep Amazon SES's raw marketing event bodies for 30 days, the event-log history
-- SendGrid and Mailgun keep (SendGrid Email Logs API: "30 days of email event history"; Mailgun logs: up to 30 days).
--
-- Each row in marketing_campaign_recipient_events keeps SES's whole JSON body, which names the recipient's email.
-- A permanent customer delete removes the events of that customer's campaign sends, but an event with no recipient
-- row (a test send, a simulator address) would keep the address forever. Once the event consumer has processed an
-- event its body is never read again: delivery, bounce and complaint facts already live on the recipient row and in
-- the event's own normalized_kind, received_at and provider_message_id columns, which reputation and warm-up
-- counting read. So the row stays and only the raw body is emptied after 30 days.

create index if not exists marketing_campaign_recipient_events_payload_trim_idx
  on public.marketing_campaign_recipient_events (received_at)
  where processed_at is not null and payload <> '{}'::jsonb;

-- Empties processed event bodies older than the retention period in batches, so one night after a large campaign
-- never holds a long lock. Returns how many bodies it emptied; whatever is left waits for the next night.
create or replace function private.trim_marketing_event_payloads(
  p_retention interval default interval '30 days',
  p_batch_size integer default 5000,
  p_max_batches integer default 40
) returns integer
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  trimmed integer := 0;
  batch_count integer;
begin
  for batch in 1..p_max_batches loop
    update public.marketing_campaign_recipient_events as event
    set payload = '{}'::jsonb
    where event.id in (
      select candidate.id
      from public.marketing_campaign_recipient_events as candidate
      where candidate.processed_at is not null
        and candidate.payload <> '{}'::jsonb
        and candidate.received_at < now() - p_retention
      order by candidate.received_at
      limit p_batch_size
      for update skip locked
    );
    get diagnostics batch_count = row_count;
    trimmed := trimmed + batch_count;
    exit when batch_count < p_batch_size;
  end loop;
  return trimmed;
end;
$$;

alter function private.trim_marketing_event_payloads(interval, integer, integer) owner to postgres;
revoke all on function private.trim_marketing_event_payloads(interval, integer, integer)
  from public, anon, authenticated;

comment on function private.trim_marketing_event_payloads(interval, integer, integer) is
  'Empties the raw SES body of processed marketing events older than the retention period (30 days by default), keeping the row and its counted facts.';

select cron.schedule(
  'marketing-event-payload-trim-nightly',
  '53 4 * * *',
  $job$select private.trim_marketing_event_payloads();$job$
);
