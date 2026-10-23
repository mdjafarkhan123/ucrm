-- Hourly Page health checks use the existing protected Messenger worker and cron.
create index communication_messenger_connections_health_due_idx
  on public.communication_messenger_connections (last_checked_at nulls first, id)
  where status = 'active';

create or replace function public.dispatch_communication_messenger_worker_wake()
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
  -- Keep the worker idle unless messages or hourly Page health checks are due.
  if not exists (
    select 1 from public.communication_messenger_webhook_events
    where processed_at is null and processing_attempts < 10
  ) and not exists (
    select 1 from public.communication_outbox_events
    where channel = 'messenger'
      and ((status in ('pending', 'failed') and available_at <= now())
        or (status = 'processing' and claimed_at <= now() - interval '5 minutes'))
  ) and not exists (
    select 1 from public.communication_messenger_connections
    where status = 'active'
      and (last_checked_at is null or last_checked_at <= now() - interval '1 hour')
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

revoke all on function public.dispatch_communication_messenger_worker_wake() from public, anon, authenticated;
grant execute on function public.dispatch_communication_messenger_worker_wake() to service_role;
