-- Part 9, step 7: the real daily pg_cron schedule, approved over on-page-load lazy checks.
--
-- Reads both the target URL and the bearer secret from Vault at the moment it fires (not baked
-- into this command text), so updating either Vault secret's value later -- e.g. moving off the
-- dev tunnel to a real deployment -- changes what the job does without touching this schedule or
-- shipping a new migration. cron.schedule upserts by job name, so re-running this migration is
-- idempotent. net.http_post is fire-and-forget from Postgres's side (it returns a request id
-- immediately; the HTTP call itself happens on a background worker), so a slow or unreachable
-- target (e.g. the dev tunnel being down) never blocks or fails the cron job itself -- it just
-- means that day's sweep silently doesn't happen, which is expected until there's an always-on
-- deployment.

select cron.schedule(
  'organization-closure-daily',
  '0 6 * * *',
  $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'closure_cron_target_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'closure_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);
