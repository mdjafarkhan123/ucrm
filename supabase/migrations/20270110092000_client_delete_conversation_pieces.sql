-- Data privacy Part 6b: the last conversation pieces that read past row security. Design:
-- docs/data-privacy-client-delete-restore.md § Hiding.
--
--   1. forwarded emails carry the mark too, so the inbox and search drop them with the customer
--   2. a Messenger reply queued for a deleted customer is cancelled at claim time, like email and text

alter table public.communication_forward_events add column client_deleted_at timestamptz;

update public.communication_forward_events as forward set client_deleted_at = client.deleted_at
from public.client_deletions as deletion
join public.clients as client on client.organization_id = deletion.organization_id and client.id = deletion.client_id
where deletion.restored_at is null and deletion.purged_at is null
  and forward.organization_id = deletion.organization_id and forward.client_id = deletion.client_id;

create or replace function private.set_client_deleted_mark(org uuid, c uuid, mark timestamptz)
  returns void
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  perform set_config('app.client_lifecycle_in_progress', 'true', true);

  -- On restore a phone or email a newer client now holds stays hidden on this one (one business never holds the
  -- same value twice); the row is kept because its messages and consent history point at it.
  update public.client_contact_methods as mine set client_deleted_at = mark
  where mine.organization_id = org and mine.client_id = c
    and (mark is not null or not exists (
      select 1 from public.client_contact_methods as theirs
      where theirs.organization_id = org and theirs.kind = mine.kind
        and theirs.normalized_value = mine.normalized_value and theirs.client_deleted_at is null));
  update public.properties set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.assessments as assessment set client_deleted_at = mark
  from public.requests as request
  where request.organization_id = org and request.client_id = c
    and assessment.organization_id = org and assessment.request_id = request.id;
  update public.requests set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.job_visits as visit set client_deleted_at = mark
  from public.jobs as job
  where job.organization_id = org and job.client_id = c
    and visit.organization_id = org and visit.job_id = job.id;
  update public.jobs set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.quotes set client_deleted_at = mark where organization_id = org and client_id = c;
  -- Only drafts go with the customer; issued invoices stay in Invoices and reports.
  update public.invoices set client_deleted_at = mark
  where organization_id = org and client_id = c and issued_at is null and recognized_at is null;
  update public.opportunities set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.review_requests set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.communication_delivery_intents set client_deleted_at = mark
  where organization_id = org and client_id = c;
  update public.communication_inbound_messages set client_deleted_at = mark
  where organization_id = org and client_id = c;
  update public.website_chat_sessions set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.website_chat_messages set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.communication_forward_events set client_deleted_at = mark
  where organization_id = org and client_id = c;
  update public.clients set deleted_at = mark where organization_id = org and id = c;

  perform set_config('app.client_lifecycle_in_progress', 'false', true);
end;
$$;


CREATE OR REPLACE FUNCTION public.claim_communication_messenger_outbox_event()
 RETURNS TABLE(outbox_event_id uuid, delivery_intent_id uuid, organization_id uuid, connection_id uuid, page_id text, psid text, claim_token uuid, attempt_number integer, body text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  candidate record;
  new_claim_token uuid;
  new_attempt integer;
begin
  for candidate in
    select event.id as event_id, event.delivery_intent_id as intent_id, event.attempt_count,
      intent.organization_id as org_id, intent.text_content, intent.client_deleted_at as client_deleted_at,
      identity.psid as identity_psid, identity.last_inbound_at,
      connection.id as conn_id, connection.page_id as conn_page_id, connection.status as conn_status
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    join public.communication_messenger_identities identity on identity.id = intent.messenger_identity_id
    join public.communication_messenger_connections connection on connection.id = identity.connection_id
    where event.channel = 'messenger' and event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    -- A customer in Recently Deleted gets nothing; a reply due while they were deleted is never sent late.
    if candidate.client_deleted_at is not null then
      perform private.cancel_communication_messenger_send(
        candidate.event_id, candidate.intent_id, 'recipient_no_longer_eligible',
        'This customer was deleted before this message was sent.');
      continue;
    end if;
    -- The Page or the window can change while a reply waits (a retry minutes later): never send outside them.
    if candidate.conn_status <> 'active' then
      perform private.cancel_communication_messenger_send(
        candidate.event_id, candidate.intent_id,
        case when candidate.conn_status = 'disconnected'
          then 'messenger_page_disconnected' else 'messenger_page_needs_reconnect' end,
        case when candidate.conn_status = 'disconnected'
          then 'The Facebook Page was disconnected before this message was sent.'
          else 'Facebook stopped accepting messages from this Page. Reconnect it in Settings.' end);
      continue;
    end if;
    if candidate.last_inbound_at is null or candidate.last_inbound_at <= now() - interval '24 hours' then
      perform private.cancel_communication_messenger_send(
        candidate.event_id, candidate.intent_id, 'messenger_window_closed',
        'Messenger''s 24-hour reply window closed before this message was sent.');
      continue;
    end if;

    new_claim_token := gen_random_uuid();
    new_attempt := candidate.attempt_count + 1;

    update public.communication_outbox_events
    set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = new_attempt, last_error = null
    where id = candidate.event_id;
    update public.communication_delivery_intents
    set status = 'claimed', failure_code = null, failure_message = null
    where id = candidate.intent_id;

    return query select candidate.event_id, candidate.intent_id, candidate.org_id, candidate.conn_id,
      candidate.conn_page_id, candidate.identity_psid, new_claim_token, new_attempt, candidate.text_content;
    return;
  end loop;
end;
$function$;
