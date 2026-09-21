-- Files and Media, Part 4: the two read functions the File Manager workspace is built on.
--
-- Part 2 gave `public.files`, `public.file_links` and `public.file_folders` their tables, their indexes and
-- their reading rules. Nothing has read them yet. This migration adds only reads -- no table, column,
-- constraint, policy or grant on a table changes here, and rolling it back is `drop function`.
--
-- Why functions instead of PostgREST queries. Two of the workspace's facts cannot be asked for over the
-- REST interface without either many round trips or a total that lies:
--
--   * "Used in 5 places" is a count of the *distinct records the reader may already view*. The file_links
--     policy filters those rows for us, so the count has to be taken in the database, in the same statement
--     that pages the catalog -- one query for a page of files, never one query per file.
--   * "Not attached" is the absence of such a row, which is an anti-join, and search has to reach through a
--     link into a client, property, request, quote or job. Both are joins PostgREST cannot express across a
--     composite foreign key.
--
-- Both functions are `security invoker`, so every policy written in Part 2 still decides what comes back:
-- a member without files.view sees only files reachable through a record they may view, a hidden job is
-- absent from a usage list, and it is absent from the count as well because the count is taken over the
-- same filtered rows. The functions add no access of their own; they only ask the question efficiently.

-- ---------------------------------------------------------------------------------------------------------
-- Index
-- ---------------------------------------------------------------------------------------------------------

-- The Trash view pages in the same newest-first order as every other view, and files_catalog_idx is partial
-- on `trashed_at is null`, so it cannot serve it. Trash holds at most 30 days of deletions, but ordering it
-- without an index means sorting whatever that is on every page.
create index if not exists files_trashed_catalog_idx
  on public.files (organization_id, created_at desc, id desc)
  where trashed_at is not null;

-- ---------------------------------------------------------------------------------------------------------
-- The catalog page
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.list_files(
  target_organization_id uuid,
  target_view text default 'all',
  target_folder_id uuid default null,
  target_search text default null,
  target_limit integer default 40,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns table (
  id uuid,
  display_name text,
  mime_type text,
  kind text,
  size_bytes bigint,
  has_thumbnail boolean,
  folder_id uuid,
  folder_name text,
  origin_type text,
  origin_id uuid,
  processing_state text,
  uploaded_by uuid,
  uploaded_by_name text,
  created_at timestamptz,
  trashed_at timestamptz,
  usage_count integer
)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  with search as (
    select
      case
        when target_search is null or btrim(target_search) = '' then null
        else '%' || replace(replace(btrim(target_search), '\', '\\'), '%', '\%') || '%'
      end as pattern,
      -- "Quote 3108" and "#3108" both mean the number 3108 to a contractor. Anything that is not all
      -- digits after the noise is stripped simply never matches a record number.
      nullif(regexp_replace(coalesce(target_search, ''), '\D', '', 'g'), '')::bigint as number
  )
  select
    file.id,
    file.display_name,
    file.mime_type,
    file.kind,
    file.size_bytes,
    -- The key itself is storage detail the browser never needs: it asks /api/files/<id>/view?size=thumb.
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
    )::integer as usage_count
  from public.files file
  cross join search
  left join public.file_folders folder
    on folder.organization_id = file.organization_id
   and folder.id = file.folder_id
  left join public.profiles uploader
    on uploader.id = file.uploaded_by
  where file.organization_id = target_organization_id
    -- Trash is its own view. Every other view is the live catalog.
    and (case when target_view = 'trash' then file.trashed_at is not null else file.trashed_at is null end)
    and (target_view <> 'recent' or file.created_at >= now() - interval '30 days')
    and (target_view <> 'photos' or file.kind = 'image')
    and (target_view <> 'videos' or file.kind = 'video')
    and (target_view <> 'documents' or file.kind = 'document')
    and (target_folder_id is null or file.folder_id = target_folder_id)
    -- "Not attached" is the absence of a use the reader can see. Taking it over the same policy-filtered
    -- rows as the count is what keeps the two from ever disagreeing on one screen.
    and (
      target_view <> 'not_attached'
      or not exists (
        select 1
        from public.file_links link
        where link.organization_id = file.organization_id
          and link.file_id = file.id
      )
    )
    and (
      search.pattern is null
      or file.display_name ilike search.pattern
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
            -- A visit and a job expense are both searched by their owning job, because "Job #2" is what
            -- the contractor remembers -- neither carries a number of its own.
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
    -- Keyset pagination on the same (created_at desc, id desc) the catalog indexes are built for, so the
    -- hundredth page costs what the first one did.
    and (
      cursor_created_at is null
      or cursor_id is null
      or (file.created_at, file.id) < (cursor_created_at, cursor_id)
    )
  order by file.created_at desc, file.id desc
  limit least(greatest(coalesce(target_limit, 40), 1), 100);
$$;

comment on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid) is
  'One page of the File Manager catalog, newest first, with the number of distinct records the reader may view. Security invoker: the Part 2 policies decide every row, so a hidden record is absent from the list and from the count.';

revoke all on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid) from public, anon;
grant execute on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- "Used in"
-- ---------------------------------------------------------------------------------------------------------

-- One row per distinct record using this File, already resolved to the words the panel shows. Resolving the
-- titles here rather than in the app is what keeps the panel to one request instead of one per usage row,
-- and every record table is read under the reader's own policies.
create or replace function public.file_usage(
  target_organization_id uuid,
  target_file_id uuid,
  target_limit integer default 10,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns table (
  id uuid,
  entity_type text,
  entity_id uuid,
  role text,
  protected boolean,
  title text,
  context text,
  status text,
  -- The record the row opens. A visit and a job expense both live inside a job, so they open the job.
  link_type text,
  link_id uuid,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select
    link.id,
    link.entity_type,
    link.entity_id,
    link.role,
    link.protected,
    case link.entity_type
      when 'client' then client_record.display_name
      when 'property' then coalesce(nullif(btrim(property_record.label), ''), property_record.address_line1)
      when 'request' then request_record.title
      when 'quote' then 'Quote #' || quote_record.quote_number
      when 'job' then 'Job #' || job_record.job_number
      when 'visit' then coalesce(nullif(btrim(visit_record.title), ''), 'Visit')
      when 'job_expense' then expense_record.name
    end as title,
    case link.entity_type
      when 'property' then nullif(btrim(concat_ws(', ', property_record.address_line1, property_record.city)), '')
      when 'quote' then nullif(btrim(quote_record.title), '')
      when 'job' then nullif(btrim(job_record.title), '')
      when 'visit' then 'Job #' || visit_job.job_number
      when 'job_expense' then 'Job #' || expense_job.job_number
    end as context,
    case link.entity_type
      when 'client' then client_record.lifecycle_status
      when 'request' then request_record.status
      when 'quote' then quote_record.status
      when 'job' then job_record.status
    end as status,
    case link.entity_type
      when 'visit' then 'job'
      when 'job_expense' then 'job'
      else link.entity_type
    end as link_type,
    case link.entity_type
      when 'visit' then visit_record.job_id
      when 'job_expense' then expense_record.job_id
      else link.entity_id
    end as link_id,
    link.created_at
  from public.file_links link
  left join public.clients client_record
    on link.entity_type = 'client' and client_record.id = link.entity_id
  left join public.properties property_record
    on link.entity_type = 'property' and property_record.id = link.entity_id
  left join public.requests request_record
    on link.entity_type = 'request' and request_record.id = link.entity_id
  left join public.quotes quote_record
    on link.entity_type = 'quote' and quote_record.id = link.entity_id
  left join public.jobs job_record
    on link.entity_type = 'job' and job_record.id = link.entity_id
  left join public.job_visits visit_record
    on link.entity_type = 'visit' and visit_record.id = link.entity_id
  left join public.jobs visit_job
    on visit_job.id = visit_record.job_id
  left join public.job_expenses expense_record
    on link.entity_type = 'job_expense' and expense_record.id = link.entity_id
  left join public.jobs expense_job
    on expense_job.id = expense_record.job_id
  where link.organization_id = target_organization_id
    and link.file_id = target_file_id
    and (
      cursor_created_at is null
      or cursor_id is null
      or (link.created_at, link.id) < (cursor_created_at, cursor_id)
    )
  order by link.created_at desc, link.id desc
  limit least(greatest(coalesce(target_limit, 10), 1), 50);
$$;

comment on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) is
  'The "Used in" list for one File, resolved to the record titles the details panel shows. Security invoker, so a record the reader may not view produces no row at all.';

revoke all on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) from public, anon;
grant execute on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Folders
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.list_file_folders(target_organization_id uuid)
returns table (id uuid, name text, file_count integer)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select
    folder.id,
    folder.name,
    (
      select count(*)
      from public.files file
      where file.organization_id = folder.organization_id
        and file.folder_id = folder.id
        and file.trashed_at is null
    )::integer as file_count
  from public.file_folders folder
  where folder.organization_id = target_organization_id
  order by lower(btrim(folder.name)) asc;
$$;

comment on function public.list_file_folders(uuid) is
  'The organization''s flat File Manager folders with how many live files sit in each. Security invoker, so only a files.view holder sees any of them.';

revoke all on function public.list_file_folders(uuid) from public, anon;
grant execute on function public.list_file_folders(uuid) to authenticated;
