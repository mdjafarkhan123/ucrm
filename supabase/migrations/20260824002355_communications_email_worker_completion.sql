-- Communications Part 1: atomically finish a claimed provider submission, schedule a bounded retry,
-- or quarantine an ambiguous submission. The HTTP request happens outside this transaction.

alter table public.communication_outbox_events
  add column finalized_claim_token uuid;

create or replace function public.finalize_communication_outbox_event(
  target_outbox_event_id uuid,
  target_claim_token uuid,
  target_outcome text,
  target_provider_message_id text default null,
  target_failure_code text default null,
  target_failure_message text default null
)
returns table (
  outbox_status text,
  intent_status text,
  attempt_count integer,
  available_at timestamptz,
  usage_recorded boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed_event public.communication_outbox_events;
  next_available_at timestamptz;
begin
  if target_outcome not in ('submitted', 'retry', 'submission_unknown', 'cancelled') then
    raise exception 'The communication outcome is invalid.' using errcode = 'check_violation';
  end if;

  select * into claimed_event
  from public.communication_outbox_events
  where id = target_outbox_event_id
  for update;

  if not found then
    raise exception 'The communication outbox event does not exist.' using errcode = 'no_data_found';
  end if;

  -- A lost RPC response may be retried by the caller. Return the already-committed outcome only for
  -- the exact lease that performed it; an old or foreign lease can never finalize this row.
  if claimed_event.status <> 'processing' then
    if claimed_event.finalized_claim_token is distinct from target_claim_token then
      raise exception 'The communication claim is no longer current.' using errcode = 'object_not_in_prerequisite_state';
    end if;

    return query
    select claimed_event.status, intent.status, claimed_event.attempt_count,
      claimed_event.available_at,
      exists (
        select 1 from public.communication_email_usage_events usage
        where usage.delivery_intent_id = claimed_event.delivery_intent_id
      )
    from public.communication_delivery_intents intent
    where intent.id = claimed_event.delivery_intent_id;
    return;
  end if;

  if claimed_event.claim_token is distinct from target_claim_token then
    raise exception 'The communication claim token is invalid.' using errcode = 'insufficient_privilege';
  end if;

  if target_outcome = 'submitted' then
    if nullif(trim(target_provider_message_id), '') is null then
      raise exception 'A submitted email requires a provider message identifier.' using errcode = 'not_null_violation';
    end if;

    update public.communication_delivery_intents
    set status = 'submitted', provider_message_id = trim(target_provider_message_id), accepted_at = now(),
      failure_code = null, failure_message = null
    where id = claimed_event.delivery_intent_id;

    insert into public.communication_email_usage_events (
      organization_id, delivery_intent_id, recipient_count
    ) values (
      claimed_event.organization_id, claimed_event.delivery_intent_id, 1
    ) on conflict (delivery_intent_id) do nothing;

    update public.communication_outbox_events
    set status = 'submitted', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token, last_error = null
    where id = claimed_event.id;

  elsif target_outcome = 'retry' then
    next_available_at := case claimed_event.attempt_count
      when 1 then now() + interval '5 minutes'
      when 2 then now() + interval '30 minutes'
      when 3 then now() + interval '2 hours'
      when 4 then now() + interval '8 hours'
      when 5 then now() + interval '24 hours'
      else 'infinity'::timestamptz
    end;

    update public.communication_delivery_intents
    set status = 'failed', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;

    update public.communication_outbox_events
    set status = 'failed', available_at = next_available_at, claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;

  elsif target_outcome = 'submission_unknown' then
    update public.communication_delivery_intents
    set status = 'submission_unknown', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;

    update public.communication_outbox_events
    set status = 'submission_unknown', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;

  else
    update public.communication_delivery_intents
    set status = 'cancelled', provider_message_id = null, accepted_at = null,
      failure_code = nullif(trim(target_failure_code), ''),
      failure_message = nullif(trim(target_failure_message), '')
    where id = claimed_event.delivery_intent_id;

    update public.communication_outbox_events
    set status = 'cancelled', claimed_at = null, claim_token = null,
      finalized_claim_token = target_claim_token,
      last_error = nullif(trim(target_failure_message), '')
    where id = claimed_event.id;
  end if;

  return query
  select event.status, intent.status, event.attempt_count, event.available_at,
    exists (
      select 1 from public.communication_email_usage_events usage
      where usage.delivery_intent_id = event.delivery_intent_id
    )
  from public.communication_outbox_events event
  join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
  where event.id = claimed_event.id;
end;
$$;

revoke all on function public.finalize_communication_outbox_event(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_communication_outbox_event(uuid, uuid, text, text, text, text)
  to service_role;
