-- Files and Media, Part 4C: attaching an existing File to a record, and the picker's two extra questions.
--
-- Part 4A gave the workspace its reads, Part 4B its manage actions. What is missing is reuse itself: the
-- point of one File with many links is that the second use of a photo is a row, not a second upload. This
-- migration adds the command that writes that row, and the two arguments the picker needs to ask
-- `list_files` a question it cannot ask today -- "which of these are already on this job?" and "which of
-- these are safe to attach at all?".
--
-- Nothing structural changes. No table, column, constraint, policy or table grant is touched. Rolling back
-- means dropping `attach_file_to_record` and restoring the previous `list_files` body from 20260921190000.

-- ---------------------------------------------------------------------------------------------------------
-- The catalog page, with record context
-- ---------------------------------------------------------------------------------------------------------

-- Dropped rather than replaced: the three new arguments change the signature, and a `create or replace` at a
-- new argument list would leave two overloads behind. Every existing call names its arguments, so a second
-- candidate would turn into "function is not unique" at runtime rather than a clean error here.
drop function if exists public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid);

create or replace function public.list_files(
  target_organization_id uuid,
  target_view text default 'all',
  target_folder_id uuid default null,
  target_search text default null,
  target_limit integer default 40,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null,
  -- The record the picker was opened from. Only read by the 'on_record' view; every other view ignores it.
  target_entity_type text default null,
  target_entity_id uuid default null,
  -- The picker's rule, not the library's: a file still being checked, one that failed a check, and one the
  -- scanner flagged cannot be attached to anything. The workspace still lists all three, with their status.
  only_attachable boolean default false
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
    -- The picker's first section: what is already on the record it was opened from. Served by
    -- file_links_entity_idx, the same index "a record's own files" was created for. A null entity is an
    -- empty section rather than the whole library, because "everything" is never the answer to "what is
    -- already on this job?".
    and (
      target_view <> 'on_record'
      or (
        target_entity_type is not null
        and target_entity_id is not null
        and exists (
          select 1
          from public.file_links link
          where link.organization_id = file.organization_id
            and link.entity_type = target_entity_type
            and link.entity_id = target_entity_id
            and link.file_id = file.id
        )
      )
    )
    and (not only_attachable or file.processing_state = 'available')
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

comment on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean) is
  'One page of the File Manager catalog, newest first, with the number of distinct records the reader may view. The "on_record" view is the picker''s "already on this record" section. Security invoker: the Part 2 policies decide every row, so a hidden record is absent from the list and from the count.';

revoke all on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean)
  from public, anon;
grant execute on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- Attach
-- ---------------------------------------------------------------------------------------------------------

-- Reuse, in one statement. The calling route has already checked that this person may write to the record --
-- attaching a document to a quote is an edit of the quote, not of the library, which is why a sales member
-- with files.view but no files.manage can still do it. What is checked here is everything that route cannot
-- safely take on trust: that the actor belongs to the organization, that the File is this organization's, is
-- live, and has actually passed its checks.
--
-- Attaching twice is the same as attaching once. The picker sends a whole selection, and a contractor who
-- double-clicks Attach, or picks a file a colleague attached a second earlier, has not made a mistake worth
-- an error message -- `file_links_unique_use_key` already says one File is on one record in one role once.
create or replace function public.attach_file_to_record(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_role text default 'attachment'
)
returns public.file_links
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  attached public.file_links;
  file_state text;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  select file.processing_state into file_state
  from public.files file
  where file.id = target_file_id
    and file.organization_id = target_organization_id
    and file.trashed_at is null;

  if file_state is null then
    raise exception 'That file was not found.' using errcode = 'no_data_found';
  end if;

  -- The contract is explicit: pending, failed and quarantined content cannot be attached. Refusing here
  -- rather than only in the route means an unchecked file cannot reach a customer-facing record through any
  -- caller, including one written later.
  if file_state <> 'available' then
    raise exception 'That file is still being checked, so it cannot be attached yet.'
      using errcode = 'check_violation';
  end if;

  insert into public.file_links (
    organization_id, file_id, entity_type, entity_id, role, created_by
  )
  values (
    target_organization_id, target_file_id, target_entity_type, target_entity_id, target_role,
    target_actor_id
  )
  on conflict (file_id, entity_type, entity_id, role) do nothing
  returning * into attached;

  -- Nothing inserted means the link was already there. The caller asked for this File to be on this record,
  -- and it is, so the answer is the existing row rather than a failure.
  if attached.id is null then
    select * into attached
    from public.file_links link
    where link.organization_id = target_organization_id
      and link.file_id = target_file_id
      and link.entity_type = target_entity_type
      and link.entity_id = target_entity_id
      and link.role = target_role;
  end if;

  return attached;
end;
$$;

comment on function public.attach_file_to_record(uuid, uuid, uuid, text, uuid, text) is
  'Adds one use of an existing File to a CRM record, idempotently. Never copies the stored object. Service role only: the calling route checks the caller may write to that record first, and the file_links entity trigger checks the record exists in this organization.';

-- Same posture as every other Files command: the service role calls it from a route that has already checked
-- the permission, and a signed-in user cannot reach it directly.
revoke all on function public.attach_file_to_record(uuid, uuid, uuid, text, uuid, text)
  from public, anon, authenticated;
