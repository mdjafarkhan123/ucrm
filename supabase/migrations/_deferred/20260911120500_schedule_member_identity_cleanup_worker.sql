-- HELD, NOT APPLIED. It sits in _deferred/ so the Supabase CLI cannot pick it up: scheduling is waiting on
-- the production topology decision about where background jobs run (database pg_cron, as the invitation
-- worker does today, or a dedicated worker container on the VPS). Decide that once, for every worker, then
-- either move this file back into supabase/migrations/ with a fresh timestamp or replace it with whatever
-- the chosen scheduler needs. Until then the worker is run on demand.
--
-- Contractor Settings 3E-2b: invoke the protected member identity cleanup route every five minutes.
-- The live URL and bearer secret stay in Vault, never in migration history. Placeholder values fail closed
-- at the route until deployment configuration replaces them, so scheduling this early changes nothing.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'team_member_identity_worker_target_url') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_member_identity_worker_route_url',
      'team_member_identity_worker_target_url',
      'Full internal worker URL ending in /api/internal/team-members/identity-cleanup/worker.'
    );
  end if;

  if not exists (select 1 from vault.secrets where name = 'team_member_identity_worker_secret') then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_member_identity_worker_bearer_secret',
      'team_member_identity_worker_secret',
      'Bearer secret for the member identity worker route. Must match TEAM_MEMBER_IDENTITY_WORKER_SECRET.'
    );
  end if;
end;
$$;

select cron.schedule(
  'team-member-identity-cleanup-five-minutes',
  '*/5 * * * *',
  $cron$
  select net.http_post(
    url := (
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'team_member_identity_worker_target_url'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'team_member_identity_worker_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);
