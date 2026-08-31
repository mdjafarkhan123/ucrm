-- Automation Part 6D-2, correction: make the immediate wake genuinely unable to break the write that
-- produced the work.
--
-- 20260918090100 returned early only when a vault secret was missing. But the migration installs PLACEHOLDER
-- secrets, so `automation_worker_target_url` is non-null junk from the moment it is applied, and the wake
-- would hand `REPLACE_ME_...` to net.http_post on every intake and every work-item insert. That is a
-- statement-level AFTER INSERT trigger, so anything it raises rolls back the enrollment or event that fired
-- it -- the exact opposite of best-effort.
--
-- Two guards, both cheap: require a real http(s) URL before dispatching, and swallow anything the dispatch
-- itself raises after logging it. The work is already durable and the minute Cron sweep still finds it, so a
-- wake problem must never be visible to the caller. The Cron dispatch keeps its loud failure on purpose --
-- that is where a misconfiguration should be noticed.

create or replace function public.request_automation_worker_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_worker_name constant text := 'automation-worker';
  v_job_name constant text := 'automation-worker-wake-on-write';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  select decrypted_secret into v_target_url
  from vault.decrypted_secrets where name = 'automation_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets where name = 'automation_worker_secret';

  -- Not configured yet, or still the placeholder: stay silent. The Cron sweep is the guarantee.
  if v_bearer is null or v_target_url is null or v_target_url !~ '^https?://[^[:space:]]+$' then
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

  perform public.record_automation_worker_wake_dispatch(
    v_worker_name, v_job_name, v_correlation, v_request_id
  );
exception
  when others then
    -- Best-effort by contract. Never let a wake failure roll back the enrollment or event that produced it.
    raise warning 'The immediate automation worker wake could not be dispatched: %', sqlerrm;
end;
$$;

comment on function public.request_automation_worker_wake() is
  'Best-effort immediate automation wake for the write path. Refuses to dispatch to an unconfigured or '
  'placeholder URL and swallows every dispatch failure, so it can never roll back the write that fired it. '
  'The minute Cron sweep remains the guarantee and the SKIP LOCKED claim remains the exactly-once boundary.';

revoke all on function public.request_automation_worker_wake() from public, anon, authenticated;
