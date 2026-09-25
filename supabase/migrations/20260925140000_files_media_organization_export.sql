-- Files and Media, Part 8B: complete organization export.
--
-- Jafar approved (2026-09-25) an owner-only "export everything" button: a background job builds one zip of
-- every File's metadata, its links (what record it is attached to), its checksum, and the blob itself, then
-- emails the owner when it is ready. Not the client-book/accounting export's instant in-memory zip
-- (src/lib/server/exports/client-export.ts) -- those are bounded record counts; a File Manager can hold
-- gigabytes of blobs, so this needs a job row, its own worker and a real object in storage.
--
-- Deliberately owner-only: files.export is mapped to no role but owner, unlike files.manage's
-- owner/admin/office spread, because a full-organization backup is a materially more sensitive capability
-- than day-to-day library management.

-- ---------------------------------------------------------------------------------------------------------
-- Permission
-- ---------------------------------------------------------------------------------------------------------

insert into public.permissions (description, key, scope_model)
values
  ('Download a complete export of every File, its links and its blob', 'files.export', 'none')
on conflict (key) do nothing;

insert into public.role_permissions (access_scope, permission_key, role)
values
  ('all', 'files.export', 'owner')
on conflict (role, permission_key) do nothing;

-- ---------------------------------------------------------------------------------------------------------
-- The job table
-- ---------------------------------------------------------------------------------------------------------

create table if not exists public.organization_exports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  requested_by uuid references auth.users (id) on delete set null,
  status text not null default 'queued',
  object_key text,
  file_count integer,
  total_bytes bigint,
  error text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz,
  constraint organization_exports_status_check
    check (status = any (array['queued', 'processing', 'available', 'failed', 'expired'])),
  -- An available export always names where its zip lives and when the link stops working. A purged
  -- (expired) one has already had object_key cleared by the sweep below, so this only binds while available.
  constraint organization_exports_available_fields_check
    check (status <> 'available' or (object_key is not null and expires_at is not null)),
  constraint organization_exports_terminal_completed_at_check
    check (status not in ('available', 'failed') or completed_at is not null),
  constraint organization_exports_file_count_check check (file_count is null or file_count >= 0),
  constraint organization_exports_total_bytes_check check (total_bytes is null or total_bytes >= 0)
);

create index if not exists organization_exports_org_requested_idx
  on public.organization_exports (organization_id, requested_at desc);

-- The claim step below scans for one queued row across every organization; without this the sweep is a
-- sequential scan of the whole table once jobs pile up.
create index if not exists organization_exports_queued_idx
  on public.organization_exports (requested_at)
  where status = 'queued';

-- The purge sweep below scans for an expired-but-still-available row across every organization.
create index if not exists organization_exports_expiring_idx
  on public.organization_exports (expires_at)
  where status = 'available';

alter table public.organization_exports enable row level security;

-- Read-only for the owner who can trigger one. No insert/update/delete policy: every write goes through a
-- SECURITY DEFINER function below, called by a service-role route that has already checked files.export --
-- the same shape as file_shares/create_file_share (20260925100000_files_media_customer_shares.sql).
create policy "owners can view their organization's exports" on public.organization_exports
  for select to authenticated
  using (private.has_permission(organization_id, 'files.export'));

-- ---------------------------------------------------------------------------------------------------------
-- Requesting one
-- ---------------------------------------------------------------------------------------------------------

-- Starts a new export, or hands back the one already queued/processing rather than piling up duplicates --
-- an owner double-clicking "Export everything" gets the same job, not two zips racing each other. Service
-- role only: the calling route checks files.export first.
create or replace function public.request_organization_export(
  target_organization_id uuid,
  target_actor_id uuid
)
returns public.organization_exports
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  existing public.organization_exports;
  created public.organization_exports;
begin
  select * into existing
  from public.organization_exports
  where organization_id = target_organization_id
    and status in ('queued', 'processing')
  order by requested_at desc
  limit 1;

  if found then
    return existing;
  end if;

  insert into public.organization_exports (organization_id, requested_by)
  values (target_organization_id, target_actor_id)
  returning * into created;

  return created;
end;
$$;

comment on function public.request_organization_export(uuid, uuid) is
  'Starts an organization export, or returns the already-queued/processing one for that organization. Service role only: the calling route checks files.export first.';

-- ---------------------------------------------------------------------------------------------------------
-- The worker's claim and finish
-- ---------------------------------------------------------------------------------------------------------

-- One row at a time: an export build is a long, heavy operation (unlike the per-file processing queue's
-- small bounded batches), so its own worker route claims exactly one job per invocation. skip locked means a
-- second invocation overlapping the first (should the cron ever double-fire) finds nothing rather than
-- racing on the same row.
create or replace function public.claim_next_organization_export()
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
  'Claims the oldest queued organization export for the worker to build, or returns null if none is waiting. Service role only.';

-- Ends one claim: 'available' names the zip and when the link expires, 'failed' records why. Service role
-- only -- the worker calls this after it has actually written (or failed to write) the object.
create or replace function public.finalize_organization_export(
  target_export_id uuid,
  target_state text,
  target_object_key text default null,
  target_file_count integer default null,
  target_total_bytes bigint default null,
  target_expires_at timestamptz default null,
  target_error text default null
)
returns public.organization_exports
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  finished public.organization_exports;
begin
  if target_state not in ('available', 'failed') then
    raise exception 'An export can only finish available or failed.' using errcode = 'check_violation';
  end if;

  if target_state = 'available' and (target_object_key is null or target_expires_at is null) then
    raise exception 'An available export needs its object key and expiry.' using errcode = 'check_violation';
  end if;

  update public.organization_exports
  set status = target_state,
      object_key = case when target_state = 'available' then target_object_key else object_key end,
      file_count = coalesce(target_file_count, file_count),
      total_bytes = coalesce(target_total_bytes, total_bytes),
      expires_at = case when target_state = 'available' then target_expires_at else expires_at end,
      error = case when target_state = 'failed' then target_error else null end,
      completed_at = now()
  where id = target_export_id and status = 'processing'
  returning * into finished;

  if not found then
    raise exception 'That export was not claimed for processing.' using errcode = 'P0002';
  end if;

  return finished;
end;
$$;

comment on function public.finalize_organization_export(uuid, text, text, integer, bigint, timestamptz, text) is
  'Ends one claimed organization export as available (with its zip key and expiry) or failed (with why). Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- Expiry sweep
-- ---------------------------------------------------------------------------------------------------------

-- An available export past its expiry loses its object_key and becomes 'expired' -- never deleted, matching
-- the Part 8A call on Trash purge (keep the row, clear the storage; here there is no customer-facing
-- placeholder to preserve, just a plain history of past exports). Runs on the existing one-minute sweep
-- (cheap, indexed, usually zero rows), not the export build's own slower cron.
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
    -- object_key is captured here, before the update below overwrites it with null, so RETURNING hands
    -- back the key that is actually being deleted rather than the row's new (already-cleared) value.
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

-- ---------------------------------------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------------------------------------

revoke all on function public.request_organization_export(uuid, uuid) from public, anon, authenticated;
revoke all on function public.claim_next_organization_export() from public, anon, authenticated;
revoke all on function public.finalize_organization_export(uuid, text, text, integer, bigint, timestamptz, text)
  from public, anon, authenticated;
revoke all on function public.purge_expired_organization_exports(integer) from public, anon, authenticated;

grant execute on function public.request_organization_export(uuid, uuid) to service_role;
grant execute on function public.claim_next_organization_export() to service_role;
grant execute on function public.finalize_organization_export(uuid, text, text, integer, bigint, timestamptz, text)
  to service_role;
grant execute on function public.purge_expired_organization_exports(integer) to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- The wake-up call
-- ---------------------------------------------------------------------------------------------------------

-- A separate cron and route from the one-minute file-processing wake (files-processing-worker-wake-one-minute,
-- 20260921170000_files_media_upload_pipeline.sql): that job's HTTP call times out at 60 seconds, which is
-- fine for a bounded batch of small files but not for streaming a whole organization's blobs into a zip.
-- This job gets a much longer timeout and a slower cadence, since an export is rare and not latency-sensitive
-- (the owner already agreed to wait for an email). Ships switched off, like every other worker cron, until
-- deployment adds its own Vault URL secret (files_export_worker_target_url) pointing at
-- /api/internal/files/export-worker -- it reuses files_processing_worker_secret for the bearer token, so no
-- new secret value is needed, only the new URL entry:
--
--   select cron.alter_job(jobid, active := true) from cron.job where jobname = 'files-export-worker-wake-five-minutes';
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'files-export-worker-wake-five-minutes') then
      perform cron.unschedule('files-export-worker-wake-five-minutes');
    end if;

    perform cron.schedule(
      'files-export-worker-wake-five-minutes',
      '*/5 * * * *',
      $job$select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'files_export_worker_target_url'
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'files_processing_worker_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 1800000
      );$job$
    );

    perform cron.alter_job(jobid, active := false)
    from cron.job
    where jobname = 'files-export-worker-wake-five-minutes';
  end if;
end
$$;
