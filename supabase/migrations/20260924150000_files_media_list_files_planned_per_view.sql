-- Files and Media, Part 7B-2: list_files is planned for the view actually asked for.
--
-- list_files was a plain SQL function, so Postgres planned its body once for every possible view and filter
-- at the same time. That plan cannot walk the newest-first files index and stop after one page, so it read
-- and permission-checked every file the organization has on each call: about 2 s at 20,000 files, measured
-- 2026-09-24 in a rolled-back transaction. Running the same statement through EXECUTE ... USING plans it
-- per call with the real arguments, so "All files" pages from the index again (0.2 s at 20,000 files).
--
-- Nothing else changes: same arguments, same columns, same rows, still security invoker under the files
-- policies. A rare label or a search with few matches still permission-checks every file it passes, which is
-- the next step of the campaign (Files and Media 7B-3 in Memory).
--
-- Rolling back: restore list_files from 20260924140000.

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
begin
  return query execute $q$
      with search as (
        select
          case
            when $4 is null or btrim($4) = '' then null
            else '%' || replace(replace(btrim($4), '\', '\\'), '%', '\%') || '%'
          end as pattern,
          nullif(regexp_replace(coalesce($4, ''), '\D', '', 'g'), '')::bigint as number
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
      cross join search
      left join public.file_folders folder
        on folder.organization_id = file.organization_id
       and folder.id = file.folder_id
      left join public.profiles uploader
        on uploader.id = file.uploaded_by
      where file.organization_id = $1
        and (case when $2 = 'trash' then file.trashed_at is not null else file.trashed_at is null end)
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
        and (
          $2 <> 'not_attached'
          or not exists (
            select 1
            from public.file_links link
            where link.organization_id = file.organization_id
              and link.file_id = file.id
          )
        )
        and (
          $2 <> 'on_record'
          or (
            $8 is not null
            and $9 is not null
            and exists (
              select 1
              from public.file_links link
              where link.organization_id = file.organization_id
                and link.entity_type = $8
                and link.entity_id = $9
                and link.file_id = file.id
                and link.role not in ('line_photo', 'report_photo')
            )
          )
        )
        and (not $10 or file.processing_state = 'available')
        and (
          search.pattern is null
          or file.display_name ilike search.pattern
          or file.caption ilike search.pattern
          or exists (
            select 1
            from public.file_links link
            where link.organization_id = file.organization_id
              and link.file_id = file.id
              and (
                (link.entity_type = 'client' and exists (
                  select 1 from public.clients record
                  where record.id = link.entity_id and record.display_name ilike search.pattern))
                or (link.entity_type = 'property' and exists (
                  select 1 from public.properties record
                  where record.id = link.entity_id
                    and (record.address_line1 ilike search.pattern
                      or record.city ilike search.pattern
                      or record.label ilike search.pattern)))
                or (link.entity_type = 'request' and exists (
                  select 1 from public.requests record
                  where record.id = link.entity_id and record.title ilike search.pattern))
                or (link.entity_type = 'quote' and exists (
                  select 1 from public.quotes record
                  where record.id = link.entity_id
                    and (record.title ilike search.pattern or record.quote_number = search.number)))
                or (link.entity_type = 'invoice' and exists (
                  select 1 from public.invoices record
                  where record.id = link.entity_id
                    and (record.subject ilike search.pattern or record.invoice_number = search.number)))
                or (link.entity_type = 'job' and exists (
                  select 1 from public.jobs record
                  where record.id = link.entity_id
                    and (record.title ilike search.pattern or record.job_number = search.number)))
                or (link.entity_type = 'visit' and exists (
                  select 1 from public.job_visits visit
                  join public.jobs record on record.id = visit.job_id
                  where visit.id = link.entity_id
                    and (visit.title ilike search.pattern
                      or record.title ilike search.pattern
                      or record.job_number = search.number)))
                or (link.entity_type = 'job_expense' and exists (
                  select 1 from public.job_expenses expense
                  join public.jobs record on record.id = expense.job_id
                  where expense.id = link.entity_id
                    and (expense.name ilike search.pattern
                      or record.title ilike search.pattern
                      or record.job_number = search.number)))
              )
          )
        )
        and (
          $6 is null
          or $7 is null
          or (file.created_at, file.id) < ($6, $7)
        )
      order by file.created_at desc, file.id desc
      limit least(greatest(coalesce($5, 40), 1), 100)
  $q$
  using target_organization_id, target_view, target_folder_id, target_search, target_limit, cursor_created_at, cursor_id, target_entity_type, target_entity_id, only_attachable, target_label_id;
end;
$fn$;
