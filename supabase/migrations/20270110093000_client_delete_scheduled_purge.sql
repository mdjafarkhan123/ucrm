-- Data privacy Part 6c: on day 30 the permanent delete runs on its own. Design:
-- docs/data-privacy-client-delete-restore.md § Day 30.
--
-- The existing client-deletion job now runs every hour instead of once a day and calls the same internal route,
-- which first permanently deletes every customer whose 30 days are up, then finishes stored-file cleanup. No new
-- Vault secret or URL: the route and its secret are unchanged.
--
--   1. public.claim_due_client_deletions  -- a 30-minute lease on due rows, skip-locked, oldest day 30 first
--   2. public.record_client_deletion_purge_failure -- keeps the reason; says when a day of failures needs an alert

alter table public.client_deletions add column purge_alerted_at timestamptz;

create or replace function public.claim_due_client_deletions(batch_size integer default 5)
  returns setof public.client_deletions
  language sql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
  update public.client_deletions as deletion
  set purge_attempted_at = now()
  where deletion.id in (
    select due.id from public.client_deletions as due
    where due.restored_at is null and due.purged_at is null and due.purge_after <= now()
      and (due.purge_attempted_at is null or due.purge_attempted_at < now() - interval '30 minutes')
    order by due.purge_after, due.id
    limit greatest(1, least(batch_size, 50))
    for update skip locked
  )
  returning deletion.*;
$$;

revoke all on function public.claim_due_client_deletions(integer) from public, anon, authenticated;
grant execute on function public.claim_due_client_deletions(integer) to service_role;

-- Returns true once, when the delete has kept failing for a day, so the caller raises one alert.
create or replace function public.record_client_deletion_purge_failure(target_deletion_id uuid, failure text)
  returns boolean
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  deletion public.client_deletions;
begin
  update public.client_deletions
  set purge_failure = left(coalesce(nullif(btrim(failure), ''), 'Unknown error.'), 500),
    purge_failed_since = coalesce(purge_failed_since, now())
  where id = target_deletion_id and restored_at is null and purged_at is null
  returning * into deletion;

  if deletion.id is null or deletion.purge_alerted_at is not null
     or deletion.purge_failed_since > now() - interval '1 day' then
    return false;
  end if;

  update public.client_deletions set purge_alerted_at = now() where id = deletion.id;
  return true;
end;
$$;

revoke all on function public.record_client_deletion_purge_failure(uuid, text) from public, anon, authenticated;
grant execute on function public.record_client_deletion_purge_failure(uuid, text) to service_role;

-- Hourly, so a customer is deleted for good within the hour after their 30 days, and a large batch of deletes on
-- one day is spread over a few runs rather than many days.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'client-deletion-cleanup-daily') then
    perform cron.unschedule('client-deletion-cleanup-daily');
  end if;
end;
$$;

select cron.schedule(
  'client-deletion-hourly',
  '40 * * * *',
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
