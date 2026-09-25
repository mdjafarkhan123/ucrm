-- Files and Media, Part 8B follow-up: two bugs caught by the pgTAP suite immediately after
-- 20260925140000 was pushed, fixed the same session before anything downstream depended on the broken
-- behavior. Matches this migration set's existing bridge/drop-bridge precedent for a same-day correction
-- (20260923140000/20260923150000) rather than rewriting an already-applied file's history.
--
--   1. claim_next_organization_export returned a single public.organization_exports row even when nothing
--      was queued -- a plpgsql function with a scalar return type always answers with exactly one row (all
--      columns null on no match), so "is there a job?" read as true when the queue was empty. Changed to
--      `returns setof` so "nothing queued" is genuinely zero rows.
--   2. purge_expired_organization_exports's RETURNING clause read oe.object_key after the same statement's
--      SET had already cleared it to null, so the worker was always handed back null instead of the key it
--      needed to delete from R2. The old value is now captured in the CTE before the UPDATE overwrites it.
--
-- 20260925140000's own source has already been corrected to match this; this migration exists only to
-- bring the copy already applied to the remote in line with it (CREATE OR REPLACE, no data touched).

-- The scalar-returning version must be dropped, not replaced: Postgres refuses CREATE OR REPLACE across a
-- return-type change (SQLSTATE 42P13), and this one changes from a single row to setof.
drop function if exists public.claim_next_organization_export();

create function public.claim_next_organization_export()
returns setof public.organization_exports
language sql
security definer
set search_path = pg_catalog, public
as $$
  update public.organization_exports
  set status = 'processing'
  where id = (
    select id
    from public.organization_exports
    where status = 'queued'
    order by requested_at
    limit 1
    for update skip locked
  )
  returning *;
$$;

comment on function public.claim_next_organization_export() is
  'Claims the oldest queued organization export for the worker to build, or returns zero rows if none is waiting. Service role only.';

revoke all on function public.claim_next_organization_export() from public, anon, authenticated;
grant execute on function public.claim_next_organization_export() to service_role;

create or replace function public.purge_expired_organization_exports(
  batch_size integer default 20
)
returns table (object_key text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return query
  with due as (
    select oe.id, oe.object_key as old_object_key
    from public.organization_exports as oe
    where oe.status = 'available'
      and oe.expires_at < now()
    order by oe.expires_at
    limit greatest(batch_size, 0)
    for update skip locked
  )
  update public.organization_exports as oe
  set status = 'expired',
      object_key = null
  from due
  where oe.id = due.id
  returning due.old_object_key;
end;
$$;

comment on function public.purge_expired_organization_exports(integer) is
  'Moves each available organization export past its expiry to expired and hands back its object key so the worker can delete the R2 object. The row is kept; only its storage key is cleared.';
