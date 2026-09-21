-- Onboarding & Data Portability, Part 1, step 5b: wake the client-import worker.
--
-- Same proven mechanism the automation worker runs (20260831022758_automation_worker_wake): a best-effort
-- pg_net nudge the moment a batch is committed (rows flip to 'ready'), plus a once-a-minute Cron sweep that
-- owns the guarantee. This is the shape Supabase Database Webhooks use.
--
-- The wake carries no correctness. Losing every wake only delays the import to the next minute boundary; the
-- SKIP LOCKED claim in process_next_import_row remains the exactly-once boundary, and the sweep is also what
-- finalizes a fully-drained batch that no in-flight wake happened to finish.
--
-- Deliberately absent (minimal scope): the attributable wake ledger the automation worker keeps. That is
-- automation-specific monitoring; import correctness does not need it. Concurrent wakes are safe by
-- construction (SKIP LOCKED) and no single-flight lease is taken.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------------------------------
-- 1. Vault placeholders. The live URL and secret stay in Vault, never in migration history.
-- ---------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'client_import_worker_target_url') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_client_import_worker_route_url',
      'client_import_worker_target_url',
      'Full internal client-import worker URL ending in /api/internal/imports/clients/worker.'
    );
  end if;
  if not exists (select 1 from vault.secrets where name = 'client_import_worker_secret') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_client_import_worker_bearer_secret',
      'client_import_worker_secret',
      'Bearer secret shared with CLIENT_IMPORT_WORKER_SECRET in the app environment.'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 2. The Cron dispatch: the guaranteed sweep. Fails closed until deployment sets the real secrets.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.dispatch_client_import_worker_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_url text;
  bearer text;
  request_id bigint;
begin
  select decrypted_secret into target_url
  from vault.decrypted_secrets where name = 'client_import_worker_target_url';
  select decrypted_secret into bearer
  from vault.decrypted_secrets where name = 'client_import_worker_secret';

  if target_url is null or bearer is null then
    raise exception 'The client import worker cron target url or bearer secret is not configured.'
      using errcode = 'no_data_found';
  end if;

  select net.http_post(
    url := target_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || bearer
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 50000
  ) into request_id;
end;
$$;

comment on function public.dispatch_client_import_worker_wake() is
  'Cron entry point for the client-import worker: calls the protected worker route via pg_net once a minute. '
  'This sweep is the guarantee -- it drains any ''ready'' rows a lost nudge left behind and finalizes a '
  'fully-drained importing batch. SECURITY DEFINER; service_role only.';

revoke all on function public.dispatch_client_import_worker_wake() from public, anon, authenticated;
grant execute on function public.dispatch_client_import_worker_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. The immediate nudge. Best-effort, never raises: a wake problem must never fail the commit.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.request_client_import_worker_wake()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_target_url text;
  v_bearer text;
  v_request_id bigint;
begin
  select decrypted_secret into v_target_url
  from vault.decrypted_secrets where name = 'client_import_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets where name = 'client_import_worker_secret';

  -- The rows are durable and 'ready'; the minute sweep will find them if the nudge cannot go out now.
  if v_target_url is null or v_bearer is null then
    return;
  end if;

  select net.http_post(
    url := v_target_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_bearer
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 50000
  ) into v_request_id;
end;
$$;

comment on function public.request_client_import_worker_wake() is
  'Best-effort immediate wake for the client-import worker, fired when a commit queues rows. Never raises; the '
  'minute Cron sweep remains the guarantee and the SKIP LOCKED claim remains the exactly-once boundary.';

revoke all on function public.request_client_import_worker_wake() from public, anon, authenticated;
grant execute on function public.request_client_import_worker_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Fire the nudge automatically when a commit flips rows to 'ready'.
-- ---------------------------------------------------------------------------------------------------
-- Statement-level with a transition table, not row-level: one commit fires exactly one nudge however many
-- rows it queued. commit_import_batch is the only writer that sets status = 'ready'; the worker's own
-- ready -> imported/failed updates carry a different new.status and so never re-trigger a wake.
create or replace function private.trigger_client_import_worker_wake()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from ready_rows where ready_rows.status = 'ready') then
    perform public.request_client_import_worker_wake();
  end if;
  return null;
end;
$$;

comment on function private.trigger_client_import_worker_wake() is
  'Statement-level AFTER UPDATE wake for import_rows: one best-effort nudge per commit that flipped rows to '
  '''ready''. No wake when the worker updates a row to imported/failed.';

revoke all on function private.trigger_client_import_worker_wake() from public, anon, authenticated;

create trigger import_rows_wake_on_ready
  after update on public.import_rows
  referencing new table as ready_rows
  for each statement
  execute function private.trigger_client_import_worker_wake();

-- ---------------------------------------------------------------------------------------------------
-- 5. The schedule, INACTIVE. Activated only after deployment configuration and the 5b verification gate.
-- ---------------------------------------------------------------------------------------------------
-- Re-applying this migration never touches an existing job, so it cannot silently re-disable one Jafar has
-- already activated.
do $$
declare
  job_id bigint;
begin
  if not exists (select 1 from cron.job where jobname = 'client-import-worker-wake-one-minute') then
    job_id := cron.schedule(
      'client-import-worker-wake-one-minute',
      '* * * * *',
      $cron$select public.dispatch_client_import_worker_wake();$cron$
    );
    perform cron.alter_job(job_id := job_id, active := false);
  end if;
end;
$$;
