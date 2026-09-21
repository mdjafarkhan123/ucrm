-- Part 9, step 7: extensions and Vault-backed secrets for the daily closure cron job.
--
-- pg_cron runs inside Postgres with no HTTP/Node context, so it cannot send emails or delete Auth
-- users directly -- both need real server code. The bridge is pg_cron -> pg_net (net.http_post) ->
-- the internal /api/jafar/internal/closure-cron route, which does the actual work and is
-- authorized by a shared secret (a scheduled job has no owner session to check).
--
-- Both the target URL and the secret live in Supabase Vault, not in migration SQL (which is
-- committed to git) and not baked into the cron job's command text. This migration only creates
-- the two secrets with clearly-labeled placeholder values -- the real values are set once,
-- directly against the live database, the same way `.env` (real, gitignored) differs from
-- `.env.example` (placeholder, committed). When this project moves off the dev tunnel to a real
-- deployment, only the `closure_cron_target_url` secret's value needs to change -- the schedule
-- created in the next migration reads it fresh every time it fires.
--
-- pg_net installs its own extension-control entry into the public schema by default and does not
-- support relocation (ALTER EXTENSION ... SET SCHEMA errors on it) -- its actual functions
-- (net.http_post etc.) already live in their own dedicated `net` schema regardless, so this is a
-- known, accepted, informational security-linter note (extension_in_public) rather than something
-- fixable here.

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare
  target_url_secret_id uuid;
  cron_secret_secret_id uuid;
begin
  select id into target_url_secret_id from vault.secrets where name = 'closure_cron_target_url';
  if target_url_secret_id is null then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_internal_route_url_directly_against_the_live_database',
      'closure_cron_target_url',
      'Internal URL the daily organization-closure cron job calls (net.http_post target). Update this value directly when the deployment target changes -- no migration or code change needed.'
    );
  end if;

  select id into cron_secret_secret_id from vault.secrets where name = 'closure_cron_secret';
  if cron_secret_secret_id is null then
    perform vault.create_secret(
      'REPLACE_ME_set_the_real_bearer_secret_directly_against_the_live_database',
      'closure_cron_secret',
      'Bearer secret sent as the Authorization header to the internal closure-cron route. Must match the app''s CLOSURE_CRON_SECRET environment variable.'
    );
  end if;
end;
$$;
