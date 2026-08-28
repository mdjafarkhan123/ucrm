-- Part 4 item 4: invoke the protected inbound attachment import worker route every five minutes.
-- The live URL stays in Vault, never in migration history. The placeholder value fails closed at the
-- route until deployment configuration replaces it. The bearer secret reuses the already-declared
-- COMMUNICATIONS_WORKER_SECRET env var, so only its Vault target-url secret is new here.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'communications_inbound_attachment_worker_target_url'
  ) then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_inbound_attachment_worker_route_url',
      'communications_inbound_attachment_worker_target_url',
      'Full internal inbound attachment worker URL ending in /api/internal/communications/inbound-attachment-worker.'
    );
  end if;

  if not exists (select 1 from vault.secrets where name = 'communications_worker_secret') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_communications_worker_bearer_secret',
      'communications_worker_secret',
      'Bearer secret for communications worker routes. Must match COMMUNICATIONS_WORKER_SECRET.'
    );
  end if;
end;
$$;

select cron.schedule(
  'communications-inbound-attachment-import-five-minutes',
  '*/5 * * * *',
  $cron$
  select net.http_post(
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
  );
  $cron$
);
