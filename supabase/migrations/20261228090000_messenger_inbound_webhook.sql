-- Messenger Part 5 (docs/messenger-implementation-plan.md § Server shape, Webhook): the worker side of the inbound
-- webhook. The route only checks Meta's signature and saves the delivery (communication_messenger_webhook_events,
-- Part 3), then answers Meta at once; a worker turns saved deliveries into inbox messages.
--
-- 1. Claiming saved deliveries. Several workers may run at once (the route's own instant wake and the one-minute
--    cron); SKIP LOCKED gives each a different batch. A claim older than five minutes belongs to a worker that died
--    and is taken over. After ten failed attempts a delivery stays unprocessed with its error for a person to read.
-- 2. The one-minute cron wake, same shape as the SES inbound wake: installed inert until the
--    'communications_messenger_worker_target_url' Vault secret is set.

-- 1. Claiming saved deliveries --------------------------------------------------------------------------------

create function public.claim_communication_messenger_webhook_events(p_limit integer, p_stale_seconds integer default 300)
returns setof public.communication_messenger_webhook_events
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $$
  with picked as (
    select id
    from public.communication_messenger_webhook_events
    where processed_at is null
      and processing_attempts < 10
      and (claimed_at is null or claimed_at < now() - make_interval(secs => greatest(p_stale_seconds, 30)))
    order by received_at
    limit least(greatest(p_limit, 1), 100)
    for update skip locked
  )
  update public.communication_messenger_webhook_events as event
  set claim_token = gen_random_uuid(),
    claimed_at = now(),
    processing_attempts = event.processing_attempts + 1
  from picked
  where event.id = picked.id
  returning event.*;
$$;

revoke all on function public.claim_communication_messenger_webhook_events(integer, integer)
  from public, anon, authenticated;
grant execute on function public.claim_communication_messenger_webhook_events(integer, integer) to service_role;

-- 2. The one-minute cron wake ---------------------------------------------------------------------------------

create function public.dispatch_communication_messenger_worker_wake()
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_worker_name constant text := 'communications-messenger-inbound';
  v_job_name constant text := 'communications-messenger-inbound-wake-one-minute';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  -- Nothing waiting: no request, no ledger row. Most minutes end here.
  if not exists (
    select 1 from public.communication_messenger_webhook_events
    where processed_at is null and processing_attempts < 10
  ) then
    return;
  end if;

  select decrypted_secret into v_target_url
  from vault.decrypted_secrets
  where name = 'communications_messenger_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets
  where name = 'communications_worker_secret';

  if v_target_url is null or v_bearer is null then
    raise exception 'The Messenger worker cron target url or bearer secret is not configured.'
      using errcode = 'no_data_found';
  end if;

  select net.http_post(
    url := v_target_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_bearer,
      'X-Wake-Correlation-Id', v_correlation::text
    ),
    body := jsonb_build_object('wake_correlation_id', v_correlation),
    timeout_milliseconds := 50000
  ) into v_request_id;

  perform public.record_communication_worker_wake_dispatch(v_worker_name, v_job_name, v_correlation, v_request_id);

  delete from private.communication_worker_wake_ledger
  where worker_name = v_worker_name
    and dispatched_at < now() - interval '7 days';
end;
$$;

alter function public.dispatch_communication_messenger_worker_wake() owner to postgres;

comment on function public.dispatch_communication_messenger_worker_wake() is
  'Cron entry point: when Messenger deliveries are waiting, calls the protected messenger-worker route via pg_net. Inert until the communications_messenger_worker_target_url Vault secret is set.';

revoke all on function public.dispatch_communication_messenger_worker_wake() from public, anon, authenticated;
grant execute on function public.dispatch_communication_messenger_worker_wake() to service_role;

select cron.schedule(
  'communications-messenger-inbound-wake-one-minute',
  '* * * * *',
  $job$select public.dispatch_communication_messenger_worker_wake();$job$
);
