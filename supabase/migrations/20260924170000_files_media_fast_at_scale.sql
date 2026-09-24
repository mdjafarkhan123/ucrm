-- Files and Media, Part 7B-3: the File Manager stays fast at 20,000+ files.
--
-- Measured 2026-09-24 in a rolled-back transaction at 20,000 files (5,000 linked to a client), as the owner:
-- a rare label took 0.4 s, a common label 0.7 s and any search 9.5 s. Two causes:
--
-- 1. The five Files SELECT policies called is_organization_member(organization_id) and
--    has_permission(organization_id, ...) with a column argument, so Postgres ran both for every file,
--    assignment, link and folder it looked at, before a label or search filter could narrow anything (ILIKE
--    and EXISTS are not leakproof, so policies go first). They now use the project's once-per-statement form,
--    the one the jobs, visits and checklist policies already use: (select private.current_organization()) for
--    membership, and has_permission on that constant organization for files.view. Same rules:
--    organization_members is UNIQUE (user_id), so "organization_id is the caller's one active organization" is
--    exactly is_organization_member(organization_id), and has_permission keeps its own override semantics
--    (current_permission_scope treats a scope-less grant differently, so it is deliberately not used here).
--    The genuinely per-row parts (file_has_visible_link, can_view_linked_entity, uploaded_by) are unchanged.
--
-- 2. list_files searched linked record names from each file outward: for every file, every link, eight
--    correlated record lookups. It now finds the matching records once (each record table still under its
--    own policy), turns them into matching file ids once, and tests files against that set. Same meaning: a
--    file matches when a link the caller can see points to a record the caller can see whose name or number
--    matches. The pattern is worked out once in PL/pgSQL and passed in, so a search-free call skips the
--    record lookups entirely.
--
-- Rolling back: restore the five policies from 20260101000000 / 20260924120000 and list_files from
-- 20260924150000.

alter policy "members can view permitted files" on public.files using (
  organization_id = (select private.current_organization())
  and (
    (select private.has_permission((select private.current_organization()), 'files.view'))
    or (trashed_at is null and processing_state = 'available' and private.file_has_visible_link(organization_id, id))
    or (uploaded_by = (select auth.uid()) and trashed_at is null)
  )
);

alter policy "members can view labels on files they can see" on public.file_label_assignments using (
  organization_id = (select private.current_organization())
  and (
    (select private.has_permission((select private.current_organization()), 'files.view'))
    or private.file_has_visible_link(organization_id, file_id)
  )
);

alter policy "members can view links to records they can see" on public.file_links using (
  organization_id = (select private.current_organization())
  and private.can_view_linked_entity(organization_id, entity_type, entity_id)
);

alter policy "library members can view folders" on public.file_folders using (
  organization_id = (select private.current_organization())
  and (select private.has_permission((select private.current_organization()), 'files.view'))
);

alter policy "members can view file labels" on public.file_labels using (
  organization_id = (select private.current_organization())
);

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
begin
  return query execute $q$
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
  $q$
  using target_organization_id, target_view, target_folder_id, target_search, target_limit, cursor_created_at, cursor_id, target_entity_type, target_entity_id, only_attachable, target_label_id,
    search_pattern, search_number;
end;
$fn$;
