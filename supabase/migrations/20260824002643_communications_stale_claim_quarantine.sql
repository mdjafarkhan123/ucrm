-- A worker can disappear after the provider request left UCRM. Never make that lease retryable: Brevo may
-- already have accepted it. Quarantine stale leases in bounded batches for callback/admin reconciliation.

create index communication_outbox_events_stale_claim_idx
  on public.communication_outbox_events (claimed_at, id)
  where status = 'processing';

create or replace function public.quarantine_stale_communication_claims(
  batch_size integer default 50,
  stale_after interval default interval '15 minutes'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quarantined_count integer;
begin
  if batch_size < 1 or batch_size > 100 then
    raise exception 'The stale communication batch is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if stale_after < interval '1 minute' or stale_after > interval '1 day' then
    raise exception 'The stale communication threshold is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  with stale as (
    select id
    from public.communication_outbox_events
    where status = 'processing' and claimed_at <= now() - stale_after
    order by claimed_at, id
    limit batch_size
    for update skip locked
  ), quarantined as (
    update public.communication_outbox_events event
    set status = 'submission_unknown', finalized_claim_token = event.claim_token,
      claimed_at = null, claim_token = null,
      last_error = 'The worker lease expired before its provider outcome was recorded.'
    from stale
    where event.id = stale.id
    returning event.delivery_intent_id
  ), updated_intents as (
    update public.communication_delivery_intents intent
    set status = 'submission_unknown', failure_code = 'worker_lease_expired',
      failure_message = 'The worker lease expired before its provider outcome was recorded.'
    from quarantined
    where intent.id = quarantined.delivery_intent_id
    returning intent.id
  )
  select count(*)::integer into quarantined_count from updated_intents;

  return quarantined_count;
end;
$$;

revoke all on function public.quarantine_stale_communication_claims(integer, interval)
  from public, anon, authenticated;
grant execute on function public.quarantine_stale_communication_claims(integer, interval)
  to service_role;
