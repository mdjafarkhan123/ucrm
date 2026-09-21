-- Communications A1: automatic monitored email-outbox drain.
--
-- Outbound sending and the return path are proven live, but nothing wakes the worker on its own -- a human or
-- an external call has to poke `/api/internal/communications/email-worker`. This migration adds the pieces a
-- once-a-minute Supabase Cron wake needs to run that drain safely and observably, following the standard
-- transactional-outbox / competing-consumer pattern. Postgres stays the sole owner of eligibility, retry
-- timing, and recovery; nothing here changes the outbox claim, finalize, or quarantine logic.
--
-- docs/research/communications-email-outbox-autodrain-production-pattern.md
-- Memory/campaigns/communications-activation/parts/A1-auto-drain.md
--
-- Everything is additive:
--   1. A private single-flight lease so two overlapping wakes never both drain. The atomic SKIP LOCKED claim
--      remains the real correctness boundary; the lease only avoids wasted concurrent work.
--   2. A private, attributable wake ledger: one row per wake with its correlation id, pg_net request id, and
--      the route's own reported outcome. It stores no URL, secret, message body, or recipient -- only counts
--      and timing -- and is pruned to a bounded window. Health joins the request id to net._http_response for
--      the ACTUAL HTTP status, so "Cron fired" is never shown as "the worker succeeded".
--   3. A cron-facing dispatch function that records the wake, calls the protected route through pg_net, and
--      prunes old ledger rows.
--   4. A Platform-Owner health read for the email worker, keyed on the stable job name.
--
-- The cron job itself is created INACTIVE by a separate step, after the controlled verification gate.

-- ---------------------------------------------------------------------------------------------------
-- 1. Single-flight lease. One row per worker name. A wake acquires the lease only if no live lease
--    exists (none, or an expired one it may take over) and gets back a token; an overlapping wake gets
--    nothing and reports `already_running`. The lease is short and self-expiring so a crashed wake that
--    never releases cannot wedge the worker past one lease window.
-- ---------------------------------------------------------------------------------------------------

create table private.communication_worker_leases (
  worker_name text primary key,
  lease_token uuid not null,
  acquired_at timestamptz not null default now(),
  expires_at timestamptz not null
);

comment on table private.communication_worker_leases is
  'Single-flight leases for background communication workers. One row per worker name; the SKIP LOCKED '
  'outbox claim remains the correctness boundary, this only prevents wasted overlapping drains.';

create or replace function public.acquire_communication_worker_lease(
  p_worker_name text,
  p_ttl_seconds integer
)
returns uuid
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into private.communication_worker_leases as lease (worker_name, lease_token, acquired_at, expires_at)
  values (p_worker_name, gen_random_uuid(), now(), now() + make_interval(secs => greatest(p_ttl_seconds, 1)))
  on conflict (worker_name) do update
    set lease_token = excluded.lease_token,
      acquired_at = excluded.acquired_at,
      expires_at = excluded.expires_at
    where lease.expires_at <= now()
  returning lease_token;
$$;

comment on function public.acquire_communication_worker_lease(text, integer) is
  'Returns a new lease token if the named worker is free (or its prior lease expired), or NULL if a live '
  'lease is held. Callers that get NULL must not run and should report already_running.';

create or replace function public.release_communication_worker_lease(
  p_worker_name text,
  p_lease_token uuid
)
returns boolean
language sql
security definer
set search_path = pg_catalog, public
as $$
  with removed as (
    delete from private.communication_worker_leases
    where worker_name = p_worker_name and lease_token = p_lease_token
    returning 1
  )
  select exists (select 1 from removed);
$$;

comment on function public.release_communication_worker_lease(text, uuid) is
  'Releases a lease only if the token matches, so a wake can never release a lease a later wake took over.';

revoke all on function public.acquire_communication_worker_lease(text, integer) from public, anon, authenticated;
grant execute on function public.acquire_communication_worker_lease(text, integer) to service_role;
revoke all on function public.release_communication_worker_lease(text, uuid) from public, anon, authenticated;
grant execute on function public.release_communication_worker_lease(text, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 2. Attributable wake ledger. One row per wake. The dispatch function inserts it with the correlation
--    id and pg_net request id; the authenticated route fills in start/finish, the outcome it observed,
--    and the bounded drain counts. No URL, secret, body, or recipient is ever stored here.
-- ---------------------------------------------------------------------------------------------------

create table private.communication_worker_wake_ledger (
  id uuid primary key default gen_random_uuid(),
  worker_name text not null,
  job_name text,
  wake_correlation_id uuid not null unique,
  net_request_id bigint,
  dispatched_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  -- The route's own reported reason: idle | max_claims | time_budget | already_running | error. NULL while a
  -- wake is dispatched but the route has not yet reported (in flight, timed out, or unreachable).
  route_outcome text,
  stale_claims_quarantined integer,
  claimed integer,
  submitted integer,
  retried integer,
  cancelled integer,
  submission_unknown integer,
  created_at timestamptz not null default now()
);

comment on table private.communication_worker_wake_ledger is
  'One row per worker wake. Correlates the cron dispatch (pg_net request id) with the route-reported outcome '
  'and drain counts for health. Stores no URL, secret, message body, or recipient; pruned to a bounded window.';

-- Health and pruning both scan by worker and recency.
create index communication_worker_wake_ledger_worker_dispatched_idx
  on private.communication_worker_wake_ledger (worker_name, dispatched_at desc);

-- ---------------------------------------------------------------------------------------------------
-- 3. Ledger writes. The dispatch function (cron) creates the row; the route records its result. Both are
--    keyed on the correlation id so a manual invocation with no prior dispatch row still records cleanly.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.record_communication_worker_wake_dispatch(
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
  insert into private.communication_worker_wake_ledger (
    worker_name, job_name, wake_correlation_id, net_request_id, dispatched_at
  )
  values (p_worker_name, p_job_name, p_wake_correlation_id, p_net_request_id, now())
  on conflict (wake_correlation_id) do update
    set net_request_id = excluded.net_request_id,
      job_name = coalesce(private.communication_worker_wake_ledger.job_name, excluded.job_name);
$$;

create or replace function public.record_communication_worker_wake_result(
  p_worker_name text,
  p_wake_correlation_id uuid,
  p_started_at timestamptz,
  p_finished_at timestamptz,
  p_route_outcome text,
  p_stale_claims_quarantined integer default null,
  p_claimed integer default null,
  p_submitted integer default null,
  p_retried integer default null,
  p_cancelled integer default null,
  p_submission_unknown integer default null
)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into private.communication_worker_wake_ledger (
    worker_name, wake_correlation_id, started_at, finished_at, route_outcome,
    stale_claims_quarantined, claimed, submitted, retried, cancelled, submission_unknown
  )
  values (
    p_worker_name, p_wake_correlation_id, p_started_at, p_finished_at, p_route_outcome,
    p_stale_claims_quarantined, p_claimed, p_submitted, p_retried, p_cancelled, p_submission_unknown
  )
  on conflict (wake_correlation_id) do update
    set started_at = excluded.started_at,
      finished_at = excluded.finished_at,
      route_outcome = excluded.route_outcome,
      stale_claims_quarantined = excluded.stale_claims_quarantined,
      claimed = excluded.claimed,
      submitted = excluded.submitted,
      retried = excluded.retried,
      cancelled = excluded.cancelled,
      submission_unknown = excluded.submission_unknown;
$$;

revoke all on function public.record_communication_worker_wake_dispatch(text, text, uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.record_communication_worker_wake_dispatch(text, text, uuid, bigint) to service_role;
revoke all on function public.record_communication_worker_wake_result(
  text, uuid, timestamptz, timestamptz, text, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.record_communication_worker_wake_result(
  text, uuid, timestamptz, timestamptz, text, integer, integer, integer, integer, integer, integer
) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Cron dispatch. Records the wake, calls the protected route through pg_net with the correlation id in
--    a header, and prunes old ledger rows. Same vault + bearer convention as every other net-post job.
--    SECURITY DEFINER (owned by postgres) so it can read the vault secrets; created but not scheduled here.
-- ---------------------------------------------------------------------------------------------------

create or replace function public.dispatch_communication_email_outbox_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  worker_name constant text := 'communications-email-outbox';
  job_name constant text := 'communications-email-outbox-wake-one-minute';
  correlation uuid := gen_random_uuid();
  target_url text;
  bearer text;
  request_id bigint;
begin
  select decrypted_secret into target_url
  from vault.decrypted_secrets
  where name = 'communications_email_worker_target_url';
  select decrypted_secret into bearer
  from vault.decrypted_secrets
  where name = 'communications_worker_secret';

  if target_url is null or bearer is null then
    raise exception 'The communications email worker cron target url or bearer secret is not configured.'
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

  perform public.record_communication_worker_wake_dispatch(worker_name, job_name, correlation, request_id);

  -- Bounded retention: keep roughly a week of wakes for health and debugging, nothing older.
  delete from private.communication_worker_wake_ledger
  where worker_name = dispatch_communication_email_outbox_wake.worker_name
    and dispatched_at < now() - interval '7 days';
end;
$$;

comment on function public.dispatch_communication_email_outbox_wake() is
  'Cron entry point: records a wake, calls the protected email-worker route via pg_net, prunes old ledger '
  'rows. Scheduled by a separate inactive cron job after the A1 verification gate.';

revoke all on function public.dispatch_communication_email_outbox_wake() from public, anon, authenticated;
grant execute on function public.dispatch_communication_email_outbox_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 5. Platform-Owner email-worker health. Read-only and bounded, keyed on the stable job name (never the
--    numeric id). Shows the cron job's active flag and last run, the last few ledger wakes with their
--    ACTUAL HTTP status from net._http_response, current due backlog and oldest due age, in-flight
--    processing and oldest claim, unknown outcomes, and recent cap/budget pressure. The initial age
--    thresholds (warn 5m, critical 15m) are surfaced for the reader; they are values to verify, not
--    capacity evidence.
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
    -- The last successful attributable drain: a wake the route actually answered 2xx, whatever its outcome.
    'last_successful_drain_at', (
      select max(l.finished_at)
      from private.communication_worker_wake_ledger l
      left join net._http_response r on r.id = l.net_request_id
      where l.worker_name = 'communications-email-outbox'
        and l.route_outcome is not null
        and l.route_outcome <> 'error'
        and coalesce(r.status_code, 0) between 200 and 299
    ),
    -- Recent wakes with the real HTTP result joined in, so Cron success is never mistaken for worker success.
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
    -- Two consecutive wakes whose route never returned a clean 2xx is the degraded signal to watch.
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
      where status in ('pending', 'failed') and available_at <= now()
    ),
    'oldest_due_age_seconds', (
      select extract(epoch from (now() - min(available_at)))::bigint
      from public.communication_outbox_events
      where status in ('pending', 'failed') and available_at <= now()
    ),
    'processing_count', (
      select count(*) from public.communication_outbox_events where status = 'processing'
    ),
    'oldest_claim_age_seconds', (
      select extract(epoch from (now() - min(claimed_at)))::bigint
      from public.communication_outbox_events where status = 'processing'
    ),
    'submission_unknown_count', (
      select count(*) from public.communication_outbox_events where status = 'submission_unknown'
    ),
    -- Repeated cap/budget stops across the recent window are the signal to MEASURE, never an automatic
    -- concurrency increase.
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
  'due backlog and oldest-due age, in-flight processing, unknown outcomes, and recent cap/budget pressure.';

revoke all on function public.get_communication_email_worker_health() from public, anon, authenticated;
grant execute on function public.get_communication_email_worker_health() to service_role;
