-- Baseline, part 4 of 4: the scheduled jobs.
--
-- All 15 jobs are installed switched OFF. A new environment must not inherit live sweeps by accident: the
-- ones that call the app need the Vault URL and secret set first (see part 2), and a rehearsal or staging
-- copy must never wake workers that point at production. Turning them on is deployment configuration, done
-- once the Vault values exist:
--
--   select cron.alter_job(jobid, active := true) from cron.job;
--
-- (On managed production today 12 are on and the three SMS jobs marked below are off. Turn on the same set.)
-- Schedules and commands are copied exactly from the live database on 2026-09-21.

-- organization-closure-daily  -- live: on
select cron.schedule(
  'organization-closure-daily',
  '0 6 * * *',
  $job$select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'closure_cron_target_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'closure_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );$job$
);

-- team-invitation-maintenance-five-minutes  -- live: on
select cron.schedule(
  'team-invitation-maintenance-five-minutes',
  '*/5 * * * *',
  $job$select net.http_post(
    url := (
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'team_invitation_worker_target_url'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'team_invitation_worker_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );$job$
);

-- communications-inbound-attachment-import-five-minutes  -- live: on
select cron.schedule(
  'communications-inbound-attachment-import-five-minutes',
  '*/5 * * * *',
  $job$select net.http_post(
    url := (
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'communications_inbound_attachment_worker_target_url'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'communications_worker_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );$job$
);

-- communications-allowance-periods-hourly  -- live: on
select cron.schedule(
  'communications-allowance-periods-hourly',
  '7 * * * *',
  $job$select private.open_due_communication_allowance_periods();$job$
);

-- communications-provider-callback-processor  -- live: on
select cron.schedule(
  'communications-provider-callback-processor',
  '*/2 * * * *',
  $job$select public.process_communication_provider_callbacks(500);$job$
);

-- communications-email-reputation-sweep  -- live: on
select cron.schedule(
  'communications-email-reputation-sweep',
  '*/5 * * * *',
  $job$select public.sweep_communication_email_reputation(200);$job$
);

-- communications-email-outbox-wake-one-minute  -- live: on
select cron.schedule(
  'communications-email-outbox-wake-one-minute',
  '* * * * *',
  $job$select public.dispatch_communication_email_outbox_wake();$job$
);

-- automation-worker-wake-one-minute  -- live: on
select cron.schedule(
  'automation-worker-wake-one-minute',
  '* * * * *',
  $job$select public.dispatch_automation_worker_wake();$job$
);

-- automation-retention-nightly  -- live: on
select cron.schedule(
  'automation-retention-nightly',
  '17 3 * * *',
  $job$select private.automation_retention_sweep();$job$
);

-- client-import-worker-wake-one-minute  -- live: on
select cron.schedule(
  'client-import-worker-wake-one-minute',
  '* * * * *',
  $job$select public.dispatch_client_import_worker_wake();$job$
);

-- communications-sms-outbox-wake-one-minute  -- live: OFF (SMS not live yet)
select cron.schedule(
  'communications-sms-outbox-wake-one-minute',
  '* * * * *',
  $job$select public.dispatch_communication_sms_outbox_wake();$job$
);

-- trust-hub-status-sync-daily  -- live: on
select cron.schedule(
  'trust-hub-status-sync-daily',
  '30 6 * * *',
  $job$select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'trust_hub_status_cron_target_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'trust_hub_status_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );$job$
);

-- communications-sms-price-reconciliation  -- live: OFF (SMS not live yet)
select cron.schedule(
  'communications-sms-price-reconciliation',
  '*/30 * * * *',
  $job$select net.http_post(
        url := (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'sms_price_reconciliation_cron_target_url'
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select decrypted_secret from vault.decrypted_secrets
            where name = 'sms_price_reconciliation_cron_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000
      );$job$
);

-- communications-sms-usage-reconciliation  -- live: OFF (SMS not live yet)
select cron.schedule(
  'communications-sms-usage-reconciliation',
  '30 7 * * *',
  $job$select net.http_post(
        url := (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'sms_usage_reconciliation_cron_target_url'
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select decrypted_secret from vault.decrypted_secrets
            where name = 'sms_usage_reconciliation_cron_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000
      );$job$
);

-- form-submission-worker-wake-one-minute  -- live: on
select cron.schedule(
  'form-submission-worker-wake-one-minute',
  '* * * * *',
  $job$select public.dispatch_form_submission_worker_wake();$job$
);

select cron.alter_job(job_id := jobid, active := false) from cron.job;
