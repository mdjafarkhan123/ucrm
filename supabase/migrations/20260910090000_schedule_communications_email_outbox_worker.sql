-- A1 auto-drain install: schedule the protected email-outbox worker wake once a minute, INACTIVE.
-- The wake is dispatched by public.dispatch_communication_email_outbox_wake(), which reads the live worker
-- URL and bearer from Vault, posts to the route with a correlation id, records the attributable dispatch,
-- and prunes its own ledger. The live URL stays in Vault, never in migration history; the placeholder fails
-- closed (the dispatcher raises) until deployment configuration replaces it. The bearer secret
-- (communications_worker_secret) is already declared by an earlier migration.
--
-- The job is created INACTIVE on purpose. It is activated only after the A1 activation/verification gate
-- passes with the app and Cloudflare Tunnel reachable. Re-applying this migration never touches an existing
-- job, so it cannot silently re-disable a job Jafar has already activated.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'communications_email_worker_target_url'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_email_outbox_worker_route_url',
      'communications_email_worker_target_url',
      'Full internal email outbox worker URL ending in /api/internal/communications/email-worker.'
    );
  end if;
end;
$$;

do $$
declare
  job_id bigint;
begin
  if not exists (
    select 1 from cron.job where jobname = 'communications-email-outbox-wake-one-minute'
  ) then
    job_id := cron.schedule(
      'communications-email-outbox-wake-one-minute',
      '* * * * *',
      $cron$select public.dispatch_communication_email_outbox_wake();$cron$
    );
    perform cron.alter_job(job_id := job_id, active := false);
  end if;
end;
$$;
