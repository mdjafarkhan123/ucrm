-- Automation Part 6D-2b activation fix: dispatch_automation_worker_wake() raised
--   42702 column reference "worker_name" is ambiguous
-- on its ledger-pruning DELETE, because the bare `worker_name` matched both the
-- automation_worker_wake_ledger column and the function's local constant. The bug never surfaced before now:
-- the function had never run (cron job 8 stays inactive until activation, and no manual dispatch had reached
-- the DELETE). Alias the ledger table so the left-hand reference is unambiguously the column; the right-hand
-- reference stays function-name-qualified to the local constant. Behavior is otherwise identical.
--
-- CREATE OR REPLACE forward-fix (the original 20260831022758 is already applied on remote). The locals are
-- renamed to the `v_` convention the sibling request_automation_worker_wake() already uses, so no local name
-- collides with the ledger's own `worker_name` column and no fragile function-name qualification is needed.

create or replace function public.dispatch_automation_worker_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_worker_name constant text := 'automation-worker';
  v_job_name constant text := 'automation-worker-wake-one-minute';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  select decrypted_secret into v_target_url
  from vault.decrypted_secrets where name = 'automation_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets where name = 'automation_worker_secret';

  if v_target_url is null or v_bearer is null then
    raise exception 'The automation worker cron target url or bearer secret is not configured.'
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

  perform public.record_automation_worker_wake_dispatch(v_worker_name, v_job_name, v_correlation, v_request_id);

  -- Bounded retention: roughly a week of wakes for health and debugging, nothing older.
  delete from private.automation_worker_wake_ledger
  where worker_name = v_worker_name
    and dispatched_at < now() - interval '7 days';
end;
$$;
