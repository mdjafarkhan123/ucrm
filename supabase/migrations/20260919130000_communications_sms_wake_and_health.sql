-- Communications A2 Stage 4C: SMS outbox wake (immediate + scheduled) and owner health.
--
-- Mirrors the proven email autodrain (20260829030837 / 20260830043551) using the SAME generic lease and wake
-- ledger (worker-name-keyed, already installed): a cron-facing dispatch function, a best-effort immediate
-- wake fired by an insert trigger, and a Platform-Owner health read. Postgres remains the sole owner of
-- eligibility, retry timing and money; nothing here changes the Stage 4B SMS claim/finalize/quarantine logic.
--
-- docs/communications-a2-implementation-plan.md Sec4C
-- Memory/campaigns/communications-activation/NOW.md
--
-- Two pre-existing bugs are fixed here because they sit on the exact surface this stage touches:
--   1. trigger_communication_email_outbox_wake() predates the channel column (added 20260913) and fires the
--      EMAIL wake for ANY inserted row, SMS included. Scoped to channel = 'email' below.
--   2. get_communication_email_worker_health() also predates channel and counts SMS outbox rows in the email
--      backlog/processing/unknown numbers. Every count is scoped to channel = 'email' below.
-- Stage 4 stays dark: the scheduled wake is created INACTIVE by a separate migration, and the immediate
-- insert-trigger wake targets a route that requires the (still absent) COMMUNICATIONS_WORKER_SECRET / vault
-- target URL to do anything -- both fail closed to a no-op today.

-- ---------------------------------------------------------------------------------------------------
-- 1. Cron-facing SMS dispatch. Same shape as dispatch_communication_email_outbox_wake: record the wake,
--    call the protected sms-worker route via pg_net, prune old ledger rows for this worker.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.dispatch_communication_sms_outbox_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_worker_name constant text := 'communications-sms-outbox';
  v_job_name constant text := 'communications-sms-outbox-wake-one-minute';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  select decrypted_secret into v_target_url
  from vault.decrypted_secrets
  where name = 'communications_sms_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets
  where name = 'communications_worker_secret';

  if v_target_url is null or v_bearer is null then
    raise exception 'The communications sms worker cron target url or bearer secret is not configured.'
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

  -- Bounded retention: keep roughly a week of wakes for health and debugging, nothing older.
  delete from private.communication_worker_wake_ledger
  where worker_name = v_worker_name
    and dispatched_at < now() - interval '7 days';
end;
$$;

comment on function public.dispatch_communication_sms_outbox_wake() is
  'Cron entry point: records a wake, calls the protected sms-worker route via pg_net, prunes old ledger '
  'rows. Scheduled by a separate inactive cron job; stays inactive until Stage 5 webhooks + launch gate.';

revoke all on function public.dispatch_communication_sms_outbox_wake() from public, anon, authenticated;
grant execute on function public.dispatch_communication_sms_outbox_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2. Best-effort immediate SMS wake, fired by the insert trigger below. Mirrors
--    request_communication_email_outbox_wake: never raises (a wake problem must never fail the enqueue),
--    never prunes (the minute Cron dispatch already owns 7-day retention).
-- ---------------------------------------------------------------------------------------------------

create or replace function public.request_communication_sms_outbox_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_worker_name constant text := 'communications-sms-outbox';
  v_job_name constant text := 'communications-sms-outbox-wake-on-insert';
  v_correlation uuid := gen_random_uuid();
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  select decrypted_secret into v_target_url
  from vault.decrypted_secrets
  where name = 'communications_sms_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets
  where name = 'communications_worker_secret';

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

comment on function public.request_communication_sms_outbox_wake() is
  'Best-effort immediate SMS-outbox wake for the insert-trigger path. Never raises and never prunes; the '
  'minute Cron dispatch remains the guaranteed drain and the SKIP LOCKED claim remains exactly-once.';

revoke all on function public.request_communication_sms_outbox_wake() from public, anon, authenticated;
grant execute on function public.request_communication_sms_outbox_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. Fix the pre-channel email trigger, and add its SMS counterpart. Two statement-level AFTER INSERT
--    triggers share the same table event and the same NEW-table transition ("inserted"); each filters to
--    its own channel so one enqueue only ever wakes its own worker.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.trigger_communication_email_outbox_wake()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from inserted where channel = 'email' and available_at <= now()) then
    perform public.request_communication_email_outbox_wake();
  end if;
  return null;
end;
$$;

comment on function public.trigger_communication_email_outbox_wake() is
  'Statement-level AFTER INSERT trigger on communication_outbox_events: fires one best-effort immediate '
  'email-outbox wake per enqueue when a newly-inserted EMAIL row is due now. Scoped to channel = ''email'' '
  '(Stage 4C fix -- SMS shares this table and must not wake the email worker).';

create or replace function public.trigger_communication_sms_outbox_wake()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from inserted where channel = 'sms' and available_at <= now()) then
    perform public.request_communication_sms_outbox_wake();
  end if;
  return null;
end;
$$;

comment on function public.trigger_communication_sms_outbox_wake() is
  'Statement-level AFTER INSERT trigger on communication_outbox_events: fires one best-effort immediate '
  'SMS-outbox wake per enqueue when a newly-inserted SMS row is due now. Automatic instant dispatch for '
  'every SMS sender; the minute Cron remains the guaranteed backstop. Stage 4 stays dark until Stage 5 + '
  'launch gate.';

revoke all on function public.trigger_communication_sms_outbox_wake() from public, anon, authenticated;

create trigger communication_sms_outbox_wake_on_insert
  after insert on public.communication_outbox_events
  referencing new table as inserted
  for each statement
  execute function public.trigger_communication_sms_outbox_wake();

-- ---------------------------------------------------------------------------------------------------
-- 4. SMS worker health. Identical shape to get_communication_email_worker_health so the Jafar control
--    room can render both with the same component; every read scoped to channel = 'sms'.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_sms_worker_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, net
as $$
  select jsonb_build_object(
    'worker_name', 'communications-sms-outbox',
    'job_name', 'communications-sms-outbox-wake-one-minute',
    'warn_oldest_due_seconds', 300,
    'critical_oldest_due_seconds', 900,
    'job', (
      select jsonb_build_object('active', j.active, 'schedule', j.schedule)
      from cron.job j
      where j.jobname = 'communications-sms-outbox-wake-one-minute'
    ),
    'last_run', (
      select jsonb_build_object('status', d.status, 'ran_at', d.start_time, 'finished_at', d.end_time)
      from cron.job j
      join cron.job_run_details d on d.jobid = j.jobid
      where j.jobname = 'communications-sms-outbox-wake-one-minute'
      order by d.start_time desc
      limit 1
    ),
    'last_successful_drain_at', (
      select max(l.finished_at)
      from private.communication_worker_wake_ledger l
      left join net._http_response r on r.id = l.net_request_id
      where l.worker_name = 'communications-sms-outbox'
        and l.route_outcome is not null
        and l.route_outcome <> 'error'
        and coalesce(r.status_code, 0) between 200 and 299
    ),
    'recent_wakes', coalesce((
      select jsonb_agg(w order by w.dispatched_at desc)
      from (
        select
          l.dispatched_at,
          l.finished_at,
          l.route_outcome,
          l.claimed,
          l.submitted,
          l.retried,
          l.submission_unknown,
          r.status_code as http_status,
          r.timed_out as http_timed_out,
          nullif(r.error_msg, '') as http_error
        from private.communication_worker_wake_ledger l
        left join net._http_response r on r.id = l.net_request_id
        where l.worker_name = 'communications-sms-outbox'
        order by l.dispatched_at desc
        limit 10
      ) w
    ), '[]'::jsonb),
    'recent_failed_wakes', (
      select count(*) from (
        select l.net_request_id, l.route_outcome
        from private.communication_worker_wake_ledger l
        where l.worker_name = 'communications-sms-outbox'
        order by l.dispatched_at desc
        limit 2
      ) recent
      left join net._http_response r on r.id = recent.net_request_id
      where recent.route_outcome is null
        or recent.route_outcome = 'error'
        or coalesce(r.status_code, 0) not between 200 and 299
    ),
    'due_count', (
      select count(*) from public.communication_outbox_events
      where channel = 'sms' and status in ('pending', 'failed') and available_at <= now()
    ),
    'oldest_due_age_seconds', (
      select extract(epoch from (now() - min(available_at)))::bigint
      from public.communication_outbox_events
      where channel = 'sms' and status in ('pending', 'failed') and available_at <= now()
    ),
    'processing_count', (
      select count(*) from public.communication_outbox_events
      where channel = 'sms' and status = 'processing'
    ),
    'oldest_claim_age_seconds', (
      select extract(epoch from (now() - min(claimed_at)))::bigint
      from public.communication_outbox_events
      where channel = 'sms' and status = 'processing'
    ),
    'submission_unknown_count', (
      select count(*) from public.communication_outbox_events
      where channel = 'sms' and status = 'submission_unknown'
    ),
    'recent_capped_wakes', (
      select count(*) from (
        select l.route_outcome
        from private.communication_worker_wake_ledger l
        where l.worker_name = 'communications-sms-outbox'
        order by l.dispatched_at desc
        limit 10
      ) recent
      where recent.route_outcome in ('max_claims', 'time_budget')
    )
  );
$$;

comment on function public.get_communication_sms_worker_health() is
  'Platform-Owner read: sms-worker cron/job status by stable name, recent wakes with real HTTP outcome, '
  'due backlog and oldest-due age, in-flight processing, unknown outcomes, and recent cap/budget pressure. '
  'Scoped to channel = ''sms'' throughout.';

revoke all on function public.get_communication_sms_worker_health() from public, anon, authenticated;
grant execute on function public.get_communication_sms_worker_health() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. Fix: get_communication_email_worker_health() predates the channel column and its outbox counts
--    (due/processing/oldest-claim/unknown) were unscoped, so an SMS backlog inflated the email numbers.
--    Every count below is scoped to channel = 'email'; the cron/job-name/ledger reads were already
--    worker-name-scoped and are unchanged.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.get_communication_email_worker_health()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, net
as $$
  select jsonb_build_object(
    'worker_name', 'communications-email-outbox',
    'job_name', 'communications-email-outbox-wake-one-minute',
    'warn_oldest_due_seconds', 300,
    'critical_oldest_due_seconds', 900,
    'job', (
      select jsonb_build_object('active', j.active, 'schedule', j.schedule)
      from cron.job j
      where j.jobname = 'communications-email-outbox-wake-one-minute'
    ),
    'last_run', (
      select jsonb_build_object('status', d.status, 'ran_at', d.start_time, 'finished_at', d.end_time)
      from cron.job j
      join cron.job_run_details d on d.jobid = j.jobid
      where j.jobname = 'communications-email-outbox-wake-one-minute'
      order by d.start_time desc
      limit 1
    ),
    'last_successful_drain_at', (
      select max(l.finished_at)
      from private.communication_worker_wake_ledger l
      left join net._http_response r on r.id = l.net_request_id
      where l.worker_name = 'communications-email-outbox'
        and l.route_outcome is not null
        and l.route_outcome <> 'error'
        and coalesce(r.status_code, 0) between 200 and 299
    ),
    'recent_wakes', coalesce((
      select jsonb_agg(w order by w.dispatched_at desc)
      from (
        select
          l.dispatched_at,
          l.finished_at,
          l.route_outcome,
          l.claimed,
          l.submitted,
          l.retried,
          l.submission_unknown,
          r.status_code as http_status,
          r.timed_out as http_timed_out,
          nullif(r.error_msg, '') as http_error
        from private.communication_worker_wake_ledger l
        left join net._http_response r on r.id = l.net_request_id
        where l.worker_name = 'communications-email-outbox'
        order by l.dispatched_at desc
        limit 10
      ) w
    ), '[]'::jsonb),
    'recent_failed_wakes', (
      select count(*) from (
        select l.net_request_id, l.route_outcome
        from private.communication_worker_wake_ledger l
        where l.worker_name = 'communications-email-outbox'
        order by l.dispatched_at desc
        limit 2
      ) recent
      left join net._http_response r on r.id = recent.net_request_id
      where recent.route_outcome is null
        or recent.route_outcome = 'error'
        or coalesce(r.status_code, 0) not between 200 and 299
    ),
    'due_count', (
      select count(*) from public.communication_outbox_events
      where channel = 'email' and status in ('pending', 'failed') and available_at <= now()
    ),
    'oldest_due_age_seconds', (
      select extract(epoch from (now() - min(available_at)))::bigint
      from public.communication_outbox_events
      where channel = 'email' and status in ('pending', 'failed') and available_at <= now()
    ),
    'processing_count', (
      select count(*) from public.communication_outbox_events
      where channel = 'email' and status = 'processing'
    ),
    'oldest_claim_age_seconds', (
      select extract(epoch from (now() - min(claimed_at)))::bigint
      from public.communication_outbox_events
      where channel = 'email' and status = 'processing'
    ),
    'submission_unknown_count', (
      select count(*) from public.communication_outbox_events
      where channel = 'email' and status = 'submission_unknown'
    ),
    'recent_capped_wakes', (
      select count(*) from (
        select l.route_outcome
        from private.communication_worker_wake_ledger l
        where l.worker_name = 'communications-email-outbox'
        order by l.dispatched_at desc
        limit 10
      ) recent
      where recent.route_outcome in ('max_claims', 'time_budget')
    )
  );
$$;

comment on function public.get_communication_email_worker_health() is
  'Platform-Owner read: email-worker cron/job status by stable name, recent wakes with real HTTP outcome, '
  'due backlog and oldest-due age, in-flight processing, unknown outcomes, and recent cap/budget pressure. '
  'Scoped to channel = ''email'' throughout (Stage 4C fix -- SMS shares this table).';

revoke all on function public.get_communication_email_worker_health() from public, anon, authenticated;
grant execute on function public.get_communication_email_worker_health() to service_role;
