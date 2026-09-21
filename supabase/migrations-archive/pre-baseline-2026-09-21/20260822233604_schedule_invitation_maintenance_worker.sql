-- Contractor Settings 3B: invoke the protected invitation maintenance route every five minutes.
-- The live URL and bearer secret remain in Vault, never in migration history. Placeholder values fail
-- closed at the route until deployment configuration replaces them.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'team_invitation_worker_target_url') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_invitation_worker_route_url',
      'team_invitation_worker_target_url',
      'Full internal invitation worker URL ending in /api/internal/team-invitations/worker.'
    );
  end if;

  if not exists (select 1 from vault.secrets where name = 'team_invitation_worker_secret') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_invitation_worker_bearer_secret',
      'team_invitation_worker_secret',
      'Bearer secret for the invitation worker route. Must match TEAM_INVITATION_WORKER_SECRET.'
    );
  end if;
end;
$$;

select cron.schedule(
  'team-invitation-maintenance-five-minutes',
  '*/5 * * * *',
  $cron$
  select net.http_post(
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
  );
  $cron$
);
