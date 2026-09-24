-- Files and Media, Part 7B-3 (second step): links are checked once per query, and the record views start
-- from the record's links.
--
-- After 20260924170000, three File Manager views were still slow at 20,000 files: a client-name search
-- matching 5,000 files, "Not attached", and a field worker's files on a job. What remained was
-- private.can_view_linked_entity, about 0.7 ms per link, because it re-runs membership and permission lookups
-- for every link row the file_links policy looks at.
--
-- 1. The file_links policy now tries a cheaper test before that function. When the caller's organization-wide
--    permission already answers for the link's record type, the answer comes from values worked out once per
--    statement, plus a single indexed existence lookup where can_view_linked_entity itself checks existence.
--    Every such test is true only when can_view_linked_entity is true for the same row (see below), and
--    can_view_linked_entity still runs whenever the cheaper test is false, so the policy admits exactly the
--    same links:
--      client        can_view_client: member (= current organization) and customers.view
--      job           can_view_job: current organization and jobs.view scope 'all'
--      request       can_view_request: requests.view granted and its scope is not 'assigned'
--      organization  entity_id = organization_id, the function's own test
--      property      can_view_client of the owning client, for an existing property: customers.view
--      quote         quotes.view, for an existing quote
--      invoice       member and invoices.view, for an existing invoice
--      visit         can_view_job of the visit's job, for an existing visit: jobs.view scope 'all'
--      job_expense   can_view_job ('all') and expenses.manage_team, for an existing expense
--      message       customers.view, for an existing delivery intent
--      marketing_campaign  marketing.view, for an existing campaign
--    Field workers and anyone else without an organization-wide grant fall through to the old per-link test.
--
-- 2. list_files adds the "On this record" and "Not attached" conditions only for those views, as a plain join
--    and NOT EXISTS. Inside an OR with the view parameter they could not become joins, so Postgres ran the
--    files policy (file_has_visible_link for a field worker) on every file before narrowing to the record.
--    Same meaning as before: a file is on the record when a link the caller can see ties it there with a role
--    other than line_photo or report_photo; a file is not attached when the caller can see no link to it.
--
-- Rolling back: restore the file_links policy from 20260924170000, list_files from 20260924170000, and drop
-- private.linked_record_exists.

create function private.linked_record_exists(target_organization_id uuid, target_entity_type text, target_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    case target_entity_type
      when 'property' then exists (
        select 1 from public.properties record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      when 'quote' then exists (
        select 1 from public.quotes record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      when 'invoice' then exists (
        select 1 from public.invoices record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      when 'visit' then exists (
        select 1 from public.job_visits record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      when 'job_expense' then exists (
        select 1 from public.job_expenses record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      when 'message' then exists (
        select 1 from public.communication_delivery_intents record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      when 'marketing_campaign' then exists (
        select 1 from public.marketing_campaigns record
        where record.id = target_entity_id and record.organization_id = target_organization_id
      )
      else false
    end,
    false
  );
$$;

revoke all on function private.linked_record_exists(uuid, text, uuid) from public, anon;
grant execute on function private.linked_record_exists(uuid, text, uuid) to authenticated;

alter policy "members can view links to records they can see" on public.file_links using (
  organization_id = (select private.current_organization())
  and (
    case entity_type
      when 'client' then (select private.has_permission((select private.current_organization()), 'customers.view'))
      when 'job' then (select private.current_permission_scope('jobs.view')) = 'all'
      when 'request' then
        (select private.has_permission((select private.current_organization()), 'requests.view'))
        and (select private.current_permission_scope('requests.view')) <> 'assigned'
      when 'organization' then entity_id = organization_id
      else false
    end
    or (
      case entity_type
        when 'property' then (select private.has_permission((select private.current_organization()), 'customers.view'))
        when 'quote' then (select private.has_permission((select private.current_organization()), 'quotes.view'))
        when 'invoice' then (select private.has_permission((select private.current_organization()), 'invoices.view'))
        when 'visit' then (select private.current_permission_scope('jobs.view')) = 'all'
        when 'job_expense' then
          (select private.current_permission_scope('jobs.view')) = 'all'
          and (select private.has_permission((select private.current_organization()), 'expenses.manage_team'))
        when 'message' then (select private.has_permission((select private.current_organization()), 'customers.view'))
        when 'marketing_campaign' then
          (select private.has_permission((select private.current_organization()), 'marketing.view'))
        else false
      end
      and private.linked_record_exists(organization_id, entity_type, entity_id)
    )
    or private.can_view_linked_entity(organization_id, entity_type, entity_id)
  )
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
