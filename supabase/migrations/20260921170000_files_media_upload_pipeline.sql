-- Files and Media, Part 3A: the safe upload and verification pipeline.
--
-- Part 2 shipped the catalog with every File born `pending` and a comment promising that "the Part 3
-- pipeline has verified size, type and signature and scanned the object" before anything becomes
-- available. This migration is the database half of that promise: the columns the pipeline writes, the
-- claim/finalize pair a worker drives, and the sweep that removes uploads the browser never finished.
--
-- Nothing here promotes a File on its own. `finalize_file_processing` is the only path to 'available',
-- it is callable by the service role only, and it refuses to promote a File that was not scanned.
--
-- Derivatives (thumbnails, video posters) are Part 3B. A File still becomes fully usable without one.

-- ---------------------------------------------------------------------------------------------------------
-- The approved size ceiling
-- ---------------------------------------------------------------------------------------------------------

-- Jafar approved 100 MB on 2026-09-21, matching Jobber's and CompanyCam's documented limits. The 25 MB
-- ceiling Part 2 inherited from `attachments` stays on `attachments` itself: this raises the limit only for
-- the new catalog, whose uploads go through the verification the old path never had.
alter table public.files
  drop constraint if exists files_size_bytes_check;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'files_size_bytes_check'
      and conrelid = 'public.files'::regclass
  ) then
    alter table public.files
      add constraint files_size_bytes_check
      check (size_bytes > 0 and size_bytes <= 104857600);
  end if;
end
$$;

-- ---------------------------------------------------------------------------------------------------------
-- What the pipeline records
-- ---------------------------------------------------------------------------------------------------------

alter table public.files
  -- Null until the browser reports the bytes are in R2. The worker will not touch a File before this: an
  -- upload still in flight has nothing to verify, and claiming it would just burn an attempt.
  add column if not exists upload_completed_at timestamptz,
  add column if not exists processing_attempts smallint not null default 0,
  add column if not exists claimed_at timestamptz,
  add column if not exists claim_token uuid,
  add column if not exists scanned_at timestamptz,
  -- Hex sha256 of the stored bytes, computed in the same single pass that feeds the scanner. The contract's
  -- export section owes the contractor a checksum per File, and it costs nothing to take it here.
  add column if not exists checksum_sha256 text,
  -- One plain-English sentence the contractor actually sees next to a file that did not make it. Never a
  -- stack trace, a scanner signature name, or an R2 key.
  add column if not exists processing_error text;

comment on column public.files.upload_completed_at is
  'Set when the browser confirms the bytes reached R2. The processing worker claims only completed uploads; a row that never gets here is swept as abandoned.';

comment on column public.files.processing_attempts is
  'Claims so far. The claim function gives up after 5 and marks the File failed rather than retrying a poison object forever.';

comment on column public.files.checksum_sha256 is
  'Hex sha256 of the stored object, taken in the pipeline''s single streaming pass. Feeds the organization export manifest.';

comment on column public.files.processing_error is
  'Plain-English reason a File is failed or quarantined, written for the contractor to read. Never a scanner signature, stack trace or object key.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'files_checksum_sha256_check'
      and conrelid = 'public.files'::regclass
  ) then
    alter table public.files
      add constraint files_checksum_sha256_check
      check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$');
  end if;
end
$$;

-- An available File has been through the whole pipeline. This is the structural half of "never expose
-- unscanned content": promoting a row without a scan time and a checksum is rejected by the table itself,
-- not only by the function that does the promoting.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'files_available_means_verified_check'
      and conrelid = 'public.files'::regclass
  ) then
    alter table public.files
      add constraint files_available_means_verified_check
      check (
        processing_state <> 'available'
        or (scanned_at is not null and checksum_sha256 is not null)
      )
      -- The Part 2 backfill marked months of existing attachments available without a scan they never had;
      -- those rows are exempt, and every File created from here forward must satisfy it.
      not valid;
  end if;
end
$$;

-- ---------------------------------------------------------------------------------------------------------
-- The two queues
-- ---------------------------------------------------------------------------------------------------------

-- Work waiting to be verified. Tiny: rows leave the moment they are promoted or fail.
create index if not exists files_processing_queue_idx
  on public.files (upload_completed_at, id)
  where processing_state = 'pending' and upload_completed_at is not null;

-- Uploads the browser started and never finished -- a closed tab, a dead connection, a cancelled picker.
create index if not exists files_abandoned_upload_idx
  on public.files (created_at)
  where processing_state = 'pending' and upload_completed_at is null;

-- ---------------------------------------------------------------------------------------------------------
-- Registering an upload
-- ---------------------------------------------------------------------------------------------------------

-- `authenticated` holds no INSERT on public.files by design, so every upload is born here. The route has
-- already checked the caller's files.manage permission and that the origin record is theirs; this function
-- is the second lock rather than the first, which is why it takes the organization and the uploader as
-- explicit arguments and refuses anything that does not line up.
create or replace function public.register_pending_file(
  target_organization_id uuid,
  target_uploaded_by uuid,
  target_display_name text,
  target_mime_type text,
  target_size_bytes bigint,
  target_object_key text,
  target_origin_type text,
  target_origin_id uuid default null,
  target_folder_id uuid default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created public.files;
begin
  -- The key is minted server-side from the organization id; this proves the row cannot be parked under
  -- another tenant's prefix even if the caller passes a key it did not generate.
  if target_object_key not like target_organization_id::text || '/files/%' then
    raise exception 'That storage key was not issued for this organization.'
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from public.organization_members member
    where member.organization_id = target_organization_id
      and member.user_id = target_uploaded_by
  ) then
    raise exception 'That uploader is not a member of this organization.'
      using errcode = 'check_violation';
  end if;

  insert into public.files (
    organization_id, folder_id, display_name, mime_type, size_bytes, object_key,
    origin_type, origin_id, processing_state, uploaded_by
  )
  values (
    target_organization_id, target_folder_id, target_display_name, target_mime_type, target_size_bytes,
    target_object_key, target_origin_type, target_origin_id, 'pending', target_uploaded_by
  )
  returning * into created;

  return created;
end;
$$;

comment on function public.register_pending_file(uuid, uuid, text, text, bigint, text, text, uuid, uuid) is
  'Creates the pending File an upload writes into. Service role only: the calling route checks files.manage and the origin record first, and this re-checks tenant, membership and key prefix.';

-- The browser says the bytes landed. Only the File''s own uploader may say it, only once, and only while
-- the File is still pending -- a second call cannot reset a File that already failed or was quarantined.
create or replace function public.complete_file_upload(
  target_file_id uuid,
  target_organization_id uuid,
  target_uploaded_by uuid
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  completed public.files;
begin
  update public.files
  set upload_completed_at = now()
  where id = target_file_id
    and organization_id = target_organization_id
    and uploaded_by = target_uploaded_by
    and processing_state = 'pending'
    and upload_completed_at is null
  returning * into completed;

  if completed.id is null then
    raise exception 'That upload is not waiting to be finished.'
      using errcode = 'no_data_found';
  end if;

  return completed;
end;
$$;

comment on function public.complete_file_upload(uuid, uuid, uuid) is
  'Marks a pending File''s bytes as uploaded so the processing worker can claim it. Service role only, and only for the File''s own uploader.';

-- ---------------------------------------------------------------------------------------------------------
-- The processing worker's claim and finalize pair
-- ---------------------------------------------------------------------------------------------------------

-- Matches `claim_communication_inbound_attachment_imports`: one atomic claim, SKIP LOCKED so a second
-- invocation takes different rows, and a stale-claim window so a worker that died mid-file releases its
-- work instead of stranding it.
create or replace function public.claim_file_processing_jobs(batch_size integer default 10)
returns setof public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_claim_token uuid;
begin
  if batch_size not between 1 and 50 then
    raise exception 'The file processing batch is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  -- A file that has failed five claims is not going to succeed on the sixth: something about the object
  -- itself breaks the pass. It stops here with a message rather than cycling forever and starving real
  -- work. The original object is left in place for the abandoned sweep to collect.
  update public.files
  set processing_state = 'failed',
      claimed_at = null,
      claim_token = null,
      processing_error = 'We could not finish checking this file after several tries. Please upload it again.'
  where processing_state = 'pending'
    and upload_completed_at is not null
    and processing_attempts >= 5
    and (claimed_at is null or claimed_at <= now() - interval '10 minutes');

  new_claim_token := gen_random_uuid();

  return query
  update public.files file
  set claimed_at = now(),
      claim_token = new_claim_token,
      processing_attempts = file.processing_attempts + 1
  from (
    select id
    from public.files
    where processing_state = 'pending'
      and upload_completed_at is not null
      and processing_attempts < 5
      and (claimed_at is null or claimed_at <= now() - interval '10 minutes')
    order by upload_completed_at, id
    limit batch_size
    for update skip locked
  ) due
  where file.id = due.id
  returning file.*;
end;
$$;

comment on function public.claim_file_processing_jobs(integer) is
  'Atomically claims completed uploads for verification and scanning, and retires anything that has failed five passes. Service role only.';

-- The one door to 'available'. Everything the pipeline learned arrives together, and a claim token that no
-- longer matches means another worker took the File over -- that result is dropped rather than applied.
create or replace function public.finalize_file_processing(
  target_file_id uuid,
  target_claim_token uuid,
  target_state text,
  target_checksum_sha256 text default null,
  target_error text default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  finalized public.files;
begin
  if target_state not in ('available', 'failed', 'quarantined') then
    raise exception 'A file can only finish processing as available, failed or quarantined.'
      using errcode = 'check_violation';
  end if;

  -- Belt and braces with files_available_means_verified_check: the constraint states the rule for the
  -- table, this states it at the only call site that can reach it, with a message a developer can act on.
  if target_state = 'available' and target_checksum_sha256 is null then
    raise exception 'A file cannot be made available without the checksum from its verification pass.'
      using errcode = 'check_violation';
  end if;

  update public.files
  set processing_state = target_state,
      checksum_sha256 = coalesce(target_checksum_sha256, checksum_sha256),
      scanned_at = case when target_state = 'available' then now() else scanned_at end,
      processing_error = case when target_state = 'available' then null else target_error end,
      claimed_at = null,
      claim_token = null
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending'
  returning * into finalized;

  if finalized.id is null then
    raise exception 'That file processing claim is no longer current.'
      using errcode = 'no_data_found';
  end if;

  return finalized;
end;
$$;

comment on function public.finalize_file_processing(uuid, uuid, text, text, text) is
  'The only path from pending to available. Requires the current claim token and, for availability, the checksum proving the object was read and scanned. Service role only.';

-- Hands a File back untouched when the pipeline could not do its job -- the scanner is down, storage did
-- not answer. The attempt is given back too: an outage is not the File's fault, and without this a scanner
-- offline for an hour would permanently fail every good upload waiting on it.
create or replace function public.release_file_processing_claim(
  target_file_id uuid,
  target_claim_token uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.files
  set claimed_at = null,
      claim_token = null,
      processing_attempts = greatest(processing_attempts - 1, 0)
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending';
end;
$$;

comment on function public.release_file_processing_claim(uuid, uuid) is
  'Returns a claimed File to the queue without counting the attempt, for failures of our own infrastructure rather than the file. Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- Uploads that were never finished
-- ---------------------------------------------------------------------------------------------------------

-- Returns the R2 keys it removed so the worker can delete the objects behind them. Deliberately narrow: a
-- File that reached any other state, carries any link, or is younger than the cutoff is never touched, so
-- this can never collect an object another record is using.
create or replace function public.sweep_abandoned_file_uploads(
  older_than_hours integer default 24,
  batch_size integer default 200
)
returns table (id uuid, object_key text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if older_than_hours < 1 or batch_size not between 1 and 1000 then
    raise exception 'The abandoned upload sweep is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  return query
  delete from public.files file
  where file.id in (
    select candidate.id
    from public.files candidate
    where candidate.processing_state = 'pending'
      and candidate.upload_completed_at is null
      and candidate.created_at <= now() - make_interval(hours => older_than_hours)
      and not exists (
        select 1 from public.file_links link
        where link.organization_id = candidate.organization_id
          and link.file_id = candidate.id
      )
    order by candidate.created_at
    limit batch_size
    for update skip locked
  )
  returning file.id, file.object_key;
end;
$$;

comment on function public.sweep_abandoned_file_uploads(integer, integer) is
  'Removes pending Files whose bytes never arrived, returning their R2 keys so the worker can delete the objects. Never touches a File that is linked, finished, or still within the grace window.';

-- ---------------------------------------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------------------------------------

-- Supabase grants execute on new public functions to anon and authenticated by default. Every one of these
-- is a privileged server-side command; the browser reaches them only through an /api route that has already
-- checked the caller.
revoke all on function public.register_pending_file(uuid, uuid, text, text, bigint, text, text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.complete_file_upload(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.claim_file_processing_jobs(integer) from public, anon, authenticated;
revoke all on function public.finalize_file_processing(uuid, uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function public.release_file_processing_claim(uuid, uuid) from public, anon, authenticated;
revoke all on function public.sweep_abandoned_file_uploads(integer, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- The wake-up call
-- ---------------------------------------------------------------------------------------------------------

-- Same shape as every other worker in this database: pg_cron posts to the app, the app does the work. The
-- job is installed switched OFF, like the whole baseline set, because it needs its Vault URL and secret
-- before it can reach anything. Turn it on once those exist:
--
--   select cron.alter_job(jobid, active := true) from cron.job where jobname = 'files-processing-worker-wake-one-minute';
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'files-processing-worker-wake-one-minute') then
      perform cron.unschedule('files-processing-worker-wake-one-minute');
    end if;

    perform cron.schedule(
      'files-processing-worker-wake-one-minute',
      '* * * * *',
      $job$select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'files_processing_worker_target_url'
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
        timeout_milliseconds := 60000
      );$job$
    );

    perform cron.alter_job(jobid, active := false)
    from cron.job
    where jobname = 'files-processing-worker-wake-one-minute';
  end if;
end
$$;
