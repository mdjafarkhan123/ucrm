-- Communications R2: immediate on-send email-outbox wake.
--
-- The once-a-minute Cron wake (20260909120000 / dispatch_communication_email_outbox_wake) is the safety-net
-- that guarantees the outbox always drains. But a conversational inbox must feel instant like GHL/WhatsApp,
-- and waiting up to a full minute for the next Cron tick is the wrong latency for "I just hit send". This
-- adds a lean, best-effort wake the send API calls the moment a message is enqueued, so dispatch happens in
-- ~1s instead of on the next minute boundary. This is the standard "notify now, sweep on a timer as backup"
-- pattern: the immediate nudge is best-effort and never a correctness boundary; the Cron sweep still owns the
-- guarantee, and the SKIP LOCKED outbox claim still owns exactly-once send.
--
-- Memory/campaigns/communications-activation/NOW.md (R2)
--
-- It deliberately reuses the EXACT proven path the Cron already uses -- same vault secret, same bearer, same
-- single-flight lease (via the route), same attributable wake ledger -- and differs from the Cron dispatch in
-- only two ways:
--   1. It does NOT prune the ledger. Pruning on every send would run a delete on the hot send path; the Cron
--      dispatch already owns 7-day retention once a minute, which is plenty.
--   2. It never raises. A missing vault secret or a pg_net hiccup must never fail a send -- the message is
--      already durably enqueued and the Cron sweep will still deliver it. The Cron path keeps the loud
--      misconfiguration signal (it raises), so this staying quiet hides nothing.
-- A distinct job_name label keeps on-send wakes attributable separately from the minute Cron in the ledger.

create or replace function public.request_communication_email_outbox_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_worker_name constant text := 'communications-email-outbox';
  v_job_name constant text := 'communications-email-outbox-wake-on-send';
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

  -- Best-effort: if the wake cannot be configured or fired, the message stays enqueued and the minute Cron
  -- sweep delivers it. Never let a wake problem surface as a failed send.
  if v_target_url is null or v_bearer is null then
    return;
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
end;
$$;

comment on function public.request_communication_email_outbox_wake() is
  'Best-effort immediate email-outbox wake for the send path (R2). Reuses the Cron pg_net wake path and '
  'ledger but never prunes and never raises; the minute Cron remains the guaranteed drain and the SKIP LOCKED '
  'claim remains the exactly-once boundary.';

revoke all on function public.request_communication_email_outbox_wake() from public, anon, authenticated;
grant execute on function public.request_communication_email_outbox_wake() to service_role;
