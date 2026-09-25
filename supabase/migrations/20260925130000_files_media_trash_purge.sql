-- Files and Media, Part 8A: permanently free a trashed File's storage 30 days after Trash.
--
-- Purge never deletes the files row. It only clears object_key and thumbnail_object_key -- the R2 bytes are
-- gone for good -- and stamps purged_at. Every customer-facing route that can serve a File's bytes already
-- re-checks trashed_at is null before it ever reads object_key (the quote, work-report and file-share
-- routes), and quote_version_attachments/job_report_photos/quote_version_lines all show a permanent "removed"
-- placeholder for exactly as long as trashed_at is set, whichever way it was decided. Keeping the row is what
-- lets that promise hold forever instead of only for 30 days (Jafar, 2026-09-25): the customer's document
-- never changes again once a photo has already been marked removed on it.
--
-- This is why nothing here touches request_pricing_lines/quote_version_lines/job_line_items/
-- job_visit_line_items/quote_version_attachments/job_report_photos or their foreign keys: they were left
-- RESTRICT (or no ON DELETE) specifically so a real `delete from files` could never run underneath a still
-- referenced row. Since purge never deletes that row, none of those constraints are ever tested.

-- ---------------------------------------------------------------------------------------------------------
-- 1. purged_at, and letting object_key go null once purged
-- ---------------------------------------------------------------------------------------------------------

alter table public.files
  add column purged_at timestamptz,
  alter column object_key drop not null;

alter table public.files
  add constraint files_purged_needs_trashed_check
    check (purged_at is null or trashed_at is not null),
  add constraint files_purged_clears_keys_check
    check (purged_at is null or (object_key is null and thumbnail_object_key is null));

comment on column public.files.purged_at is
  'When the daily sweep freed this File''s storage, 30+ days after Trash. The row is kept forever -- only object_key and thumbnail_object_key are cleared -- so every downstream "removed" indicator keeps working.';

-- Both indexes existed to serve "trashed, and not yet gone for good"; a purged row has nothing left to
-- restore and nothing left for the sweep to do, so both narrow to exclude it.
drop index if exists public.files_trashed_catalog_idx;
create index files_trashed_catalog_idx
  on public.files (organization_id, created_at desc, id desc)
  where trashed_at is not null and purged_at is null;

drop index if exists public.files_trashed_idx;
create index files_trashed_idx
  on public.files (organization_id, trashed_at)
  where trashed_at is not null and purged_at is null;

-- ---------------------------------------------------------------------------------------------------------
-- 2. The purge log -- the audit trail the behavior contract asks for
-- ---------------------------------------------------------------------------------------------------------

create table if not exists public.file_purge_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  file_id uuid not null,
  display_name text not null,
  object_key text not null,
  had_thumbnail boolean not null,
  trashed_at timestamptz not null,
  trashed_by uuid references auth.users (id) on delete set null,
  purged_at timestamptz not null default now(),
  constraint file_purge_log_file_fkey
    foreign key (organization_id, file_id)
    references public.files (organization_id, id) on delete cascade
);

comment on table public.file_purge_log is
  'One row per File the daily sweep freed the storage of. The File row itself lives on with object_key null; this is the receipt of what was deleted, when, and who trashed it.';

create index file_purge_log_organization_purged_idx
  on public.file_purge_log (organization_id, purged_at desc);

alter table public.file_purge_log enable row level security;

-- Same reach as Trash itself: whoever may trash and restore a File may see what was permanently deleted.
create policy "trash holders can view the purge log" on public.file_purge_log
  for select to authenticated
  using (
    private.is_organization_member(organization_id)
    and private.has_permission(organization_id, 'files.trash')
  );

revoke all on table public.file_purge_log from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.file_purge_log from authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 3. The sweep itself
-- ---------------------------------------------------------------------------------------------------------

-- Same shape as sweep_abandoned_file_uploads: the database decides what has earned its purge and hands back
-- the keys, and only those keys, so the worker can delete the R2 objects behind them. `for update skip
-- locked` means a second call (a retried invocation, an overlapping tick) can never double-log or double
-- -clear the same row.
create or replace function public.purge_expired_trashed_files(
  older_than_days integer default 30,
  batch_size integer default 100
)
returns table (id uuid, object_key text, thumbnail_object_key text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if older_than_days < 1 or batch_size not between 1 and 1000 then
    raise exception 'The trash purge sweep is outside its safe bounds.'
      using errcode = 'check_violation';
  end if;

  return query
  with candidates as (
    select file.id, file.organization_id, file.display_name, file.object_key,
           file.thumbnail_object_key, file.trashed_at, file.trashed_by
    from public.files file
    where file.trashed_at is not null
      and file.purged_at is null
      and file.object_key is not null
      and file.trashed_at <= now() - make_interval(days => older_than_days)
    order by file.trashed_at
    limit batch_size
    for update skip locked
  ),
  logged as (
    insert into public.file_purge_log (
      organization_id, file_id, display_name, object_key, had_thumbnail, trashed_at, trashed_by
    )
    select candidates.organization_id, candidates.id, candidates.display_name, candidates.object_key,
           candidates.thumbnail_object_key is not null, candidates.trashed_at, candidates.trashed_by
    from candidates
  )
  update public.files file
  set purged_at = now(),
      object_key = null,
      thumbnail_object_key = null,
      updated_at = now()
  from candidates
  where file.id = candidates.id
  returning file.id, candidates.object_key, candidates.thumbnail_object_key;
end;
$$;

comment on function public.purge_expired_trashed_files(integer, integer) is
  'Logs and clears the storage keys of every File trashed 30+ days ago and not yet purged, returning the R2 keys so the worker can delete the objects. Never deletes the files row.';

revoke all on function public.purge_expired_trashed_files(integer, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 4. restore_file and list_files learn about purged_at
-- ---------------------------------------------------------------------------------------------------------

-- A purged File has no bytes left to restore. Refusing it here is defense in depth: list_files' Trash view
-- (below) already stops offering Restore on one before this could ever be reached in the normal app.
create or replace function public.restore_file(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  restored public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  update public.files
  set trashed_at = null,
      trashed_by = null
  where id = target_file_id
    and organization_id = target_organization_id
    and trashed_at is not null
    and purged_at is null
  returning * into restored;

  if restored.id is null then
    raise exception 'That file is not in Trash.' using errcode = 'no_data_found';
  end if;

  return restored;
end;
$$;

comment on function public.restore_file(uuid, uuid, uuid) is
  'Takes one File back out of Trash, into the folder it was in. Refuses a File whose storage was already purged. Does not re-attach it to records. Service role only.';

-- Unchanged from Part 7B-4 except the Trash branch of the view predicate: a purged File no longer belongs in
-- the Trash list, the same way it no longer belongs in any other view.
create or replace function public.list_files(
  target_organization_id uuid,
  target_view text default 'all',
  target_folder_id uuid default null,
  target_search text default null,
  target_limit integer default 40,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null,
  target_entity_type text default null,
  target_entity_id uuid default null,
  only_attachable boolean default false,
  target_label_id uuid default null
)
returns table (
  id uuid, display_name text, mime_type text, kind text, size_bytes bigint, has_thumbnail boolean,
  folder_id uuid, folder_name text, origin_type text, origin_id uuid, processing_state text,
  uploaded_by uuid, uploaded_by_name text, created_at timestamptz, trashed_at timestamptz, usage_count integer,
  caption text
)
language plpgsql
stable
set search_path = pg_catalog, public
as $fn$
declare
  search_pattern text := case
    when target_search is null or btrim(target_search) = '' then null
    else '%' || replace(replace(btrim(target_search), '\', '\\'), '%', '\%') || '%'
  end;
  search_number bigint := nullif(regexp_replace(coalesce(target_search, ''), '\D', '', 'g'), '')::bigint;
  -- Start from the record's links, so the files policy runs only on the record's files.
  record_join text := case
    when target_view = 'on_record' then $j$
      join (
        select distinct link.file_id
        from public.file_links link
        where link.organization_id = $1
          and link.entity_type = $8
          and link.entity_id = $9
          and link.role not in ('line_photo', 'report_photo')
      ) on_record on on_record.file_id = file.id
    $j$
    else ''
  end;
  not_attached_filter text := case
    when target_view = 'not_attached' then $j$
      and not exists (
        select 1
        from public.file_links link
        where link.organization_id = file.organization_id
          and link.file_id = file.id
      )
    $j$
    else ''
  end;
begin
  return query execute format($q$
      with matched_records (entity_type, entity_id) as (
        -- Records whose name or number matches, found once per search under each record table's own policy,
        -- rather than once per file per link.
        select 'client', record.id from public.clients record
        where $12 is not null and record.organization_id = $1 and record.display_name ilike $12
        union all
        select 'property', record.id from public.properties record
        where $12 is not null and record.organization_id = $1
          and (record.address_line1 ilike $12 or record.city ilike $12 or record.label ilike $12)
        union all
        select 'request', record.id from public.requests record
        where $12 is not null and record.organization_id = $1 and record.title ilike $12
        union all
        select 'quote', record.id from public.quotes record
        where $12 is not null and record.organization_id = $1
          and (record.title ilike $12 or record.quote_number = $13)
        union all
        select 'invoice', record.id from public.invoices record
        where $12 is not null and record.organization_id = $1
          and (record.subject ilike $12 or record.invoice_number = $13)
        union all
        select 'job', record.id from public.jobs record
        where $12 is not null and record.organization_id = $1
          and (record.title ilike $12 or record.job_number = $13)
        union all
        select 'visit', visit.id from public.job_visits visit
        join public.jobs record on record.id = visit.job_id
        where $12 is not null and visit.organization_id = $1
          and (visit.title ilike $12 or record.title ilike $12 or record.job_number = $13)
        union all
        select 'job_expense', expense.id from public.job_expenses expense
        join public.jobs record on record.id = expense.job_id
        where $12 is not null and expense.organization_id = $1
          and (expense.name ilike $12 or record.title ilike $12 or record.job_number = $13)
      ),
      matched_files as (
        select link.file_id
        from public.file_links link
        join matched_records matched
          on matched.entity_type = link.entity_type
         and matched.entity_id = link.entity_id
        where link.organization_id = $1
      )
      select
        file.id,
        file.display_name,
        file.mime_type,
        file.kind,
        file.size_bytes,
        file.thumbnail_object_key is not null as has_thumbnail,
        file.folder_id,
        folder.name as folder_name,
        file.origin_type,
        file.origin_id,
        file.processing_state,
        file.uploaded_by,
        uploader.full_name as uploaded_by_name,
        file.created_at,
        file.trashed_at,
        (
          select count(distinct (link.entity_type, link.entity_id))
          from public.file_links link
          where link.organization_id = file.organization_id
            and link.file_id = file.id
        )::integer as usage_count,
        file.caption
      from public.files file
      %1$s
      left join public.file_folders folder
        on folder.organization_id = file.organization_id
       and folder.id = file.folder_id
      left join public.profiles uploader
        on uploader.id = file.uploaded_by
      where file.organization_id = $1
        and (
          case when $2 = 'trash' then file.trashed_at is not null and file.purged_at is null
          else file.trashed_at is null end
        )
        and ($2 <> 'recent' or file.created_at >= now() - interval '30 days')
        and ($2 <> 'photos' or file.kind = 'image')
        and ($2 <> 'videos' or file.kind = 'video')
        and ($2 <> 'documents' or file.kind = 'document')
        and ($3 is null or file.folder_id = $3)
        and (
          $11 is null
          or exists (
            select 1
            from public.file_label_assignments assignment
            where assignment.organization_id = file.organization_id
              and assignment.file_id = file.id
              and assignment.label_id = $11
          )
        )
        %2$s
        and (not $10 or file.processing_state = 'available')
        and (
          $12 is null
          or file.display_name ilike $12
          or file.caption ilike $12
          or file.id in (select matched_files.file_id from matched_files)
        )
        and (
          $6 is null
          or $7 is null
          or (file.created_at, file.id) < ($6, $7)
        )
      order by file.created_at desc, file.id desc
      limit least(greatest(coalesce($5, 40), 1), 100)
  $q$, record_join, not_attached_filter)
  using target_organization_id, target_view, target_folder_id, target_search, target_limit, cursor_created_at, cursor_id, target_entity_type, target_entity_id, only_attachable, target_label_id,
    search_pattern, search_number;
end;
$fn$;
