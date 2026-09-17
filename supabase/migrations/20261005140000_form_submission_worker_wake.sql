-- CRM Launch Readiness Part 4: wake the form-submission worker.
--
-- Contractor Settings 4D built the queue (private.form_submissions, status 'pending') and its drain route
-- (/api/internal/forms/worker) but nothing ever called that route, so a public form stayed pending forever:
-- no Request, no website_inquiry.received event, no staff alert.
--
-- Same proven mechanism as the client-import and automation workers (20260916150000_client_import_worker_wake):
-- a best-effort pg_net nudge the moment a submission is saved, plus a once-a-minute Cron sweep that owns the
-- guarantee. Industry name: transactional outbox with an immediate "just-in-time" dispatch and a polling
-- backstop; the nudge is the shape Supabase Database Webhooks use. pg_net sends only after commit, so the
-- worker never races an uncommitted row.
--
-- The wake carries no correctness. The SKIP LOCKED claim in process_next_form_submission remains the
-- exactly-once boundary, and concurrent wakes are safe by construction. No wake ledger (minimal scope).

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------------------------------
-- 1. Vault placeholders. The live URL and secret stay in Vault, never in migration history.
-- ---------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'form_submission_worker_target_url') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_form_submission_worker_route_url',
      'form_submission_worker_target_url',
      'Full internal form-submission worker URL ending in /api/internal/forms/worker.'
    );
  end if;
  if not exists (select 1 from vault.secrets where name = 'form_submission_worker_secret') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_form_submission_worker_bearer_secret',
      'form_submission_worker_secret',
      'Bearer secret shared with FORM_SUBMISSION_WORKER_SECRET in the app environment.'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 2. The Cron dispatch: the guaranteed sweep. Fails closed until deployment sets the real secrets.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.dispatch_form_submission_worker_wake()
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
  from vault.decrypted_secrets where name = 'form_submission_worker_target_url';
  select decrypted_secret into bearer
  from vault.decrypted_secrets where name = 'form_submission_worker_secret';

  if target_url is null or bearer is null then
    raise exception 'The form submission worker cron target url or bearer secret is not configured.'
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

comment on function public.dispatch_form_submission_worker_wake() is
  'Cron entry point for the form-submission worker: calls the protected worker route via pg_net once a minute. '
  'This sweep is the guarantee -- it drains any pending submission a lost nudge or a failed attempt left '
  'behind. SECURITY DEFINER; service_role only.';

revoke all on function public.dispatch_form_submission_worker_wake() from public, anon, authenticated;
grant execute on function public.dispatch_form_submission_worker_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. The immediate nudge. Best-effort, never raises: a wake problem must never refuse a customer's form.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.request_form_submission_worker_wake()
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
  from vault.decrypted_secrets where name = 'form_submission_worker_target_url';
  select decrypted_secret into v_bearer
  from vault.decrypted_secrets where name = 'form_submission_worker_secret';

  -- The submission is durable and pending; the minute sweep will find it if the nudge cannot go out now.
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
exception
  when others then
    return;
end;
$$;

comment on function public.request_form_submission_worker_wake() is
  'Best-effort immediate wake for the form-submission worker, fired when a submission is saved. Never raises; '
  'the minute Cron sweep remains the guarantee and the SKIP LOCKED claim remains the exactly-once boundary.';

revoke all on function public.request_form_submission_worker_wake() from public, anon, authenticated;
grant execute on function public.request_form_submission_worker_wake() to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Fire the nudge automatically when a submission is saved.
-- ---------------------------------------------------------------------------------------------------
-- Statement-level with a transition table: one insert fires exactly one nudge. submit_form_response is the only
-- writer, and every new row starts 'pending'; the worker only updates rows, so it never re-triggers a wake.
create or replace function private.trigger_form_submission_worker_wake()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from inserted_rows where inserted_rows.status = 'pending') then
    perform public.request_form_submission_worker_wake();
  end if;
  return null;
end;
$$;

comment on function private.trigger_form_submission_worker_wake() is
  'Statement-level AFTER INSERT wake for form_submissions: one best-effort nudge per saved submission.';

revoke all on function private.trigger_form_submission_worker_wake() from public, anon, authenticated;

create trigger form_submissions_wake_worker_on_insert
  after insert on private.form_submissions
  referencing new table as inserted_rows
  for each statement
  execute function private.trigger_form_submission_worker_wake();

-- ---------------------------------------------------------------------------------------------------
-- 5. The schedule, INACTIVE. Activated only after deployment sets the real Vault secrets.
-- ---------------------------------------------------------------------------------------------------
-- Re-applying this migration never touches an existing job, so it cannot silently re-disable one Jafar has
-- already activated.
do $$
declare
  job_id bigint;
begin
  if not exists (select 1 from cron.job where jobname = 'form-submission-worker-wake-one-minute') then
    job_id := cron.schedule(
      'form-submission-worker-wake-one-minute',
      '* * * * *',
      $cron$select public.dispatch_form_submission_worker_wake();$cron$
    );
    perform cron.alter_job(job_id := job_id, active := false);
  end if;
end;
$$;
