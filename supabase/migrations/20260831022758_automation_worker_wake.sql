-- Automation Part 6D-2: wake the worker.
--
-- Same proven mechanism Communications already runs -- a statement-level trigger that fires pg_net on write
-- for immediacy, plus a once-a-minute Cron sweep that owns the guarantee. This is the shape Supabase Database
-- Webhooks use. LISTEN/NOTIFY would be lower latency but needs the persistent worker container we do not run
-- yet; it is the upgrade once that lands, and it changes no semantics here.
--
-- Two things the Cron sweep specifically owns, because no insert-time wake can cover them:
--   * a work item scheduled into the future by a wait step (the trigger deliberately ignores it), and
--   * a row whose retry backoff has not elapsed yet.
-- Both simply become due later, and the next sweep claims them.
--
-- The wake carries no correctness. Losing every wake only delays work to the next minute boundary; the
-- SKIP LOCKED claim in 20260918090000 remains the exactly-once boundary.
--
-- Deliberately absent: the single-flight worker lease Communications takes. Concurrent automation wakes are
-- safe by construction and must stay that way, because production runs several worker containers.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------------------------------
-- 1. Attributable wake ledger.
-- ---------------------------------------------------------------------------------------------------
-- Its own table rather than a column added to the Communications ledger: the two workers report different
-- counts, and a shared table would either grow union-of-both columns or lose meaning. One row per wake, no
-- URL, secret, payload, or recipient.
create table private.automation_worker_wake_ledger (
  id uuid primary key default gen_random_uuid(),
  worker_name text not null,
  job_name text,
  wake_correlation_id uuid not null unique,
  net_request_id bigint,
  dispatched_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  -- The route's own reported reason: idle | max_claims | time_budget | route_deadline | error. NULL while a
  -- wake is dispatched but the route has not yet reported.
  route_outcome text,
  events_processed integer,
  claimed integer,
  waited integer,
  completed integer,
  cancelled integer,
  parked integer,
  retried integer,
  created_at timestamptz not null default now()
);

comment on table private.automation_worker_wake_ledger is
  'One row per automation worker wake. Correlates the dispatch (pg_net request id) with the route-reported '
  'outcome and drain counts. Stores no URL, secret, or customer content; pruned to a bounded window.';

create index automation_worker_wake_ledger_worker_dispatched_idx
  on private.automation_worker_wake_ledger (worker_name, dispatched_at desc);

-- ---------------------------------------------------------------------------------------------------
-- 2. Ledger writes.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.record_automation_worker_wake_dispatch(
  p_worker_name text,
  p_job_name text,
  p_wake_correlation_id uuid,
  p_net_request_id bigint
)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into private.automation_worker_wake_ledger (
    worker_name, job_name, wake_correlation_id, net_request_id, dispatched_at
  )
  values (p_worker_name, p_job_name, p_wake_correlation_id, p_net_request_id, now())
  on conflict (wake_correlation_id) do update
    set net_request_id = excluded.net_request_id,
      job_name = coalesce(private.automation_worker_wake_ledger.job_name, excluded.job_name);
$$;

create or replace function public.record_automation_worker_wake_result(
  p_worker_name text,
  p_wake_correlation_id uuid,
  p_started_at timestamptz,
  p_finished_at timestamptz,
  p_route_outcome text,
  p_events_processed integer default null,
  p_claimed integer default null,
  p_waited integer default null,
  p_completed integer default null,
  p_cancelled integer default null,
  p_parked integer default null,
  p_retried integer default null
)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into private.automation_worker_wake_ledger (
    worker_name, wake_correlation_id, started_at, finished_at, route_outcome,
    events_processed, claimed, waited, completed, cancelled, parked, retried
  )
  values (
    p_worker_name, p_wake_correlation_id, p_started_at, p_finished_at, p_route_outcome,
    p_events_processed, p_claimed, p_waited, p_completed, p_cancelled, p_parked, p_retried
  )
  on conflict (wake_correlation_id) do update
    set started_at = excluded.started_at,
      finished_at = excluded.finished_at,
      route_outcome = excluded.route_outcome,
      events_processed = excluded.events_processed,
      claimed = excluded.claimed,
      waited = excluded.waited,
      completed = excluded.completed,
      cancelled = excluded.cancelled,
      parked = excluded.parked,
      retried = excluded.retried;
$$;

revoke all on function public.record_automation_worker_wake_dispatch(text, text, uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.record_automation_worker_wake_dispatch(text, text, uuid, bigint)
  to service_role;
revoke all on function public.record_automation_worker_wake_result(
  text, uuid, timestamptz, timestamptz, text, integer, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.record_automation_worker_wake_result(
  text, uuid, timestamptz, timestamptz, text, integer, integer, integer, integer, integer, integer, integer
) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. The Cron dispatch. The guaranteed sweep.
-- ---------------------------------------------------------------------------------------------------
-- The live URL stays in Vault, never in migration history; the placeholder fails closed (this raises) until
-- deployment configuration replaces it, so a misconfiguration is loud rather than silent.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'automation_worker_target_url') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_automation_worker_route_url',
      'automation_worker_target_url',
      'Full internal automation worker URL ending in /api/internal/automation/worker.'
    );
  end if;
  if not exists (select 1 from vault.secrets where name = 'automation_worker_secret') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_automation_worker_bearer_secret',
      'automation_worker_secret',
      'Bearer secret shared with AUTOMATION_WORKER_SECRET in the app environment.'
    );
  end if;
end;
$$;

create or replace function public.dispatch_automation_worker_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  worker_name constant text := 'automation-worker';
  job_name constant text := 'automation-worker-wake-one-minute';
  correlation uuid := gen_random_uuid();
  target_url text;
  bearer text;
  request_id bigint;
begin
  select decrypted_secret into target_url
  from vault.decrypted_secrets where name = 'automation_worker_target_url';
  select decrypted_secret into bearer
  from vault.decrypted_secrets where name = 'automation_worker_secret';

  if target_url is null or bearer is null then
    raise exception 'The automation worker cron target url or bearer secret is not configured.'
      using errcode = 'no_data_found';
  end if;

  select net.http_post(
    url := target_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || bearer,
      'X-Wake-Correlation-Id', correlation::text
    ),
    body := jsonb_build_object('wake_correlation_id', correlation),
    timeout_milliseconds := 50000
  ) into request_id;

  perform public.record_automation_worker_wake_dispatch(worker_name, job_name, correlation, request_id);

  -- Bounded retention: roughly a week of wakes for health and debugging, nothing older.
  delete from private.automation_worker_wake_ledger
  where worker_name = dispatch_automation_worker_wake.worker_name
    and dispatched_at < now() - interval '7 days';
end;
$$;

comment on function public.dispatch_automation_worker_wake() is
  'Cron entry point: records a wake, calls the protected automation worker route via pg_net, prunes old '
  'ledger rows. This sweep is what finds future-dated waits and backed-off retries.';

revoke all on function public.dispatch_automation_worker_wake() from public, anon, authenticated;
grant execute on function public.dispatch_automation_worker_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. The immediate nudge. Best-effort, never raises, never prunes.
-- ---------------------------------------------------------------------------------------------------
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

  -- A wake problem must never fail the transaction that produced the work. The row is durable and the minute
  -- sweep will find it.
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

  perform public.record_automation_worker_wake_dispatch(
    v_worker_name, v_job_name, v_correlation, v_request_id
  );
end;
$$;

comment on function public.request_automation_worker_wake() is
  'Best-effort immediate automation wake for the write path. Never raises and never prunes; the minute Cron '
  'sweep remains the guarantee and the SKIP LOCKED claim remains the exactly-once boundary.';

revoke all on function public.request_automation_worker_wake() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 5. Fire the nudge automatically on both queues.
-- ---------------------------------------------------------------------------------------------------
-- Statement-level with a transition table, not row-level: one enqueueing statement fires exactly one wake
-- however many rows it wrote. Both triggers guard on due-now, so a future-dated wait step raises no wake and
-- waits for the sweep -- which is the whole point of having a sweep.
create or replace function private.trigger_automation_worker_wake()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from inserted where inserted.available_at <= now()) then
    perform public.request_automation_worker_wake();
  end if;
  return null;
end;
$$;

comment on function private.trigger_automation_worker_wake() is
  'Statement-level AFTER INSERT wake for the automation event and work queues: one best-effort nudge per '
  'statement, only when a newly inserted row is due now.';

revoke all on function private.trigger_automation_worker_wake() from public, anon, authenticated;

create trigger automation_events_wake_on_insert
  after insert on private.automation_events
  referencing new table as inserted
  for each statement
  execute function private.trigger_automation_worker_wake();

create trigger automation_work_items_wake_on_insert
  after insert on private.automation_work_items
  referencing new table as inserted
  for each statement
  execute function private.trigger_automation_worker_wake();

-- ---------------------------------------------------------------------------------------------------
-- 6. The schedule, INACTIVE.
-- ---------------------------------------------------------------------------------------------------
-- Activated only after the deployment configuration is in place and the 6D-2 verification gate passes.
-- Re-applying this migration never touches an existing job, so it cannot silently re-disable a job Jafar has
-- already activated.
do $$
declare
  job_id bigint;
begin
  if not exists (select 1 from cron.job where jobname = 'automation-worker-wake-one-minute') then
    job_id := cron.schedule(
      'automation-worker-wake-one-minute',
      '* * * * *',
      $cron$select public.dispatch_automation_worker_wake();$cron$
    );
    perform cron.alter_job(job_id := job_id, active := false);
  end if;
end;
$$;
