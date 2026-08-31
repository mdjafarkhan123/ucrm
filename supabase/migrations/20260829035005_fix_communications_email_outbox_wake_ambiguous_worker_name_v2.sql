create or replace function public.dispatch_communication_email_outbox_wake()
  returns void
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_worker_name constant text := 'communications-email-outbox';
  v_job_name constant text := 'communications-email-outbox-wake-one-minute';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  select decrypted_secret into v_target_url
  from vault.decrypted_secrets
  where name = 'communications_email_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets
  where name = 'communications_worker_secret';

  if v_target_url is null or v_bearer is null then
    raise exception 'The communications email worker cron target url or bearer secret is not configured.'
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
$function$;
