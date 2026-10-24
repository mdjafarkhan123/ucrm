-- Data privacy Part 3b (docs/data-privacy-deletion-engine.md § Provider cleanup): the daily retry for stored file
-- copies a permanent customer delete could not remove straight away.
--
-- The delete that makes a receipt cleans up its own files right after it commits; this job calls the internal
-- client-deletion-cleanup route once a day to finish any receipt left in_progress or failed_partial, the same way
-- organization-closure-daily retries a closed business's provider cleanup.
--
-- Vault holds placeholders only, as in the baseline (20260101000100): every environment sets its real URL and
-- secret directly in Vault. The secret must match the app's CLIENT_DELETION_CRON_SECRET.

do $$
declare
  placeholder record;
begin
  for placeholder in
    select * from (values
    ('client_deletion_cron_secret',
     'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
     'Bearer secret sent as the Authorization header to the internal client-deletion-cleanup route. Must match the app''s CLIENT_DELETION_CRON_SECRET environment variable.'),
    ('client_deletion_cron_target_url',
     'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
     'Full internal URL ending in /api/internal/privacy/client-deletion-cleanup that the daily client-deletion cleanup job calls.')
    ) as p(secret_name, secret_value, secret_description)
  loop
    if not exists (select 1 from vault.secrets where name = placeholder.secret_name) then
      perform vault.create_secret(placeholder.secret_value, placeholder.secret_name, placeholder.secret_description);
    end if;
  end loop;
end;
$$;

select cron.schedule(
  'client-deletion-cleanup-daily',
  '40 6 * * *',
  $job$select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'client_deletion_cron_target_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'client_deletion_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );$job$
);
