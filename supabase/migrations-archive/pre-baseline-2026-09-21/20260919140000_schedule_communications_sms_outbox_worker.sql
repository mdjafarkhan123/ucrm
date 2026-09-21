-- Stage 4C install: schedule the protected sms-outbox worker wake once a minute, INACTIVE.
-- Mirrors 20260829033723 (email). The wake is dispatched by public.dispatch_communication_sms_outbox_wake(),
-- which reads the live sms-worker URL and shared bearer from Vault, posts to the route with a correlation id,
-- records the attributable dispatch, and prunes its own ledger. The live URL stays in Vault, never in
-- migration history; the placeholder fails closed (the dispatcher raises) until deployment configuration
-- replaces it. The bearer secret (communications_worker_secret) is already declared and shared with email.
--
-- The job is created INACTIVE on purpose and stays that way until Stage 5 signed webhooks and the country
-- launch gate pass (Stage 4 stays dark: no send UI, no live traffic). Re-applying this migration never
-- touches an existing job, so it cannot silently re-disable a job Jafar has already activated.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'communications_sms_worker_target_url'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_sms_outbox_worker_route_url',
      'communications_sms_worker_target_url',
      'Full internal sms outbox worker URL ending in /api/internal/communications/sms-worker.'
    );
  end if;
end;
$$;

do $$
declare
  job_id bigint;
begin
  if not exists (
    select 1 from cron.job where jobname = 'communications-sms-outbox-wake-one-minute'
  ) then
    job_id := cron.schedule(
      'communications-sms-outbox-wake-one-minute',
      '* * * * *',
      $cron$select public.dispatch_communication_sms_outbox_wake();$cron$
    );
    perform cron.alter_job(job_id := job_id, active := false);
  end if;
end;
$$;
