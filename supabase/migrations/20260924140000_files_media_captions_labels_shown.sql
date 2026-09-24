-- Files and Media, Part 7B-2: photo captions and labels are shown.
--
-- 7B-1 stored them. This puts them where the contract says a photo appears
-- (docs/files-media-behavior-contract.md, Part 7B):
--   * A work report's customer document carries each photo's caption and label names. An issued link
--     freezes that document, so the customer keeps the words they were sent; later edits change only the
--     editable report and links issued after them.
--   * The report editor's photo candidates carry them too, so the contractor sees what the customer will.
--   * list_files returns the caption, matches it in search, and filters to one label (the rail's label list).
--
-- No new index: the label filter probes file_label_assignments by its primary key (organization, file,
-- label) while walking the existing newest-first files index, and the caption is matched on the row the
-- search already reads.
--
-- Rolling back: restore the four function bodies from 20260924100000 (drop the 11-argument list_files first).

-- ---------------------------------------------------------------------------------------------------------
-- 1. The customer document: each photo carries its caption and label names
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.job_report_customer_document(job_row public.jobs, business_name text, include_price boolean)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  report_row public.job_reports;
  client_row public.clients;
  property_row public.properties;
begin
  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = job_row.id;
  if not found then
    return null;
  end if;

  select * into client_row
  from public.clients
  where organization_id = job_row.organization_id and id = job_row.client_id;

  select * into property_row
  from public.properties
  where organization_id = job_row.organization_id and id = job_row.property_id;

  return jsonb_build_object(
    'business', jsonb_build_object('name', business_name),
    'job', jsonb_build_object(
      'job_number', job_row.job_number,
      'title', job_row.title,
      'job_type', job_row.job_type,
      'currency_code', job_row.currency_code
    ),
    'client', jsonb_build_object(
      'display_name', client_row.display_name,
      'company_name', client_row.company_name,
      'first_name', client_row.first_name,
      'last_name', client_row.last_name
    ),
    'property', jsonb_build_object(
      'label', property_row.label,
      'address_line1', property_row.address_line1,
      'address_line2', property_row.address_line2,
      'city', property_row.city,
      'state_region', property_row.state_region,
      'postal_code', property_row.postal_code,
      'country', property_row.country
    ),
    'summary', nullif(trim(coalesce(report_row.summary, '')), ''),
    -- Photos, resolved live from the File Manager. The public file route allow-lists exactly these ids.
    -- Label names, not ids: an issued link must keep saying "Before" even after the label is renamed.
    'photos', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'file_id', file.id,
          'file_name', file.display_name,
          'caption', file.caption,
          'labels', (
            select coalesce(jsonb_agg(label.name order by lower(label.name), label.id), '[]'::jsonb)
            from public.file_label_assignments as assignment
            join public.file_labels as label
              on label.organization_id = assignment.organization_id and label.id = assignment.label_id
            where assignment.organization_id = file.organization_id
              and assignment.file_id = file.id
          )
        )
        order by file.created_at, file.id
      ), '[]'::jsonb)
      from public.job_report_photos as photo
      join public.files as file
        on file.organization_id = photo.organization_id and file.id = photo.file_id
      where photo.organization_id = job_row.organization_id
        and photo.job_id = job_row.id
        and file.trashed_at is null
        and file.processing_state = 'available'
    ),
    -- Checklist answers, grouped by visit and resolved live. The inner join to visit_checklist_answers is
    -- what makes "always current" true: a cleared answer produces no row, so it drops off the report until
    -- it is answered again.
    'checklist', (
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'visit_id', grp.visit_id,
          'visit_date', grp.visit_date,
          'items', grp.items
        ) order by grp.visit_date, grp.visit_id
      ), '[]'::jsonb)
      from (
        select sel.visit_id,
               visit.visit_date,
               jsonb_agg(
                 jsonb_build_object(
                   'item_id', item.id,
                   'label', item.label,
                   'item_type', item.item_type,
                   'value', answer.value
                 ) order by item.position, item.id
               ) as items
        from public.job_report_checklist_items as sel
        join public.job_visits as visit
          on visit.organization_id = sel.organization_id and visit.id = sel.visit_id
        join public.job_checklist_items as item
          on item.organization_id = sel.organization_id and item.id = sel.item_id
        join public.visit_checklist_answers as answer
          on answer.organization_id = sel.organization_id
         and answer.visit_id = sel.visit_id
         and answer.item_id = sel.item_id
        where sel.organization_id = job_row.organization_id and sel.job_id = job_row.id
        group by sel.visit_id, visit.visit_date
      ) as grp
    ),
    -- The work list, only when the report shows it, and its prices only when it shows those. The check
    -- constraint means include_price already implies include_service_details.
    'service_details', case when report_row.include_service_details then jsonb_build_object(
      'lines', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'line_id', line.id,
            'position', line.position,
            'line_kind', line.line_kind,
            'category', line.category,
            'name', line.name,
            'description', line.description,
            'unit_label', line.unit_label,
            'quantity', line.quantity
          )
          || case when include_price
               then jsonb_build_object(
                 'unit_price_minor', line.unit_price_minor,
                 'line_total_minor', line.line_total_minor)
               else '{}'::jsonb end
          order by line.position, line.id
        ), '[]'::jsonb)
        from public.job_line_items as line
        where line.organization_id = job_row.organization_id and line.job_id = job_row.id
      ),
      'totals', case when include_price then jsonb_build_object(
        'subtotal_minor', job_row.subtotal_minor,
        'discount_minor', job_row.discount_minor,
        'tax_minor', job_row.tax_minor,
        'total_minor', job_row.total_minor
      ) else null end
    ) else null end,
    -- The chosen signature, as facts the customer may read. The drawn image is not streamed on the public
    -- page in this part -- the customer sees who signed, what they agreed to and when.
    'signature', (
      select case when sig.id is null then null else jsonb_build_object(
        'signer_name', sig.signer_name,
        'signer_role', sig.signer_role,
        'signature_type', sig.signature_type,
        'statement', sig.statement,
        'method', sig.method,
        'has_image', sig.image_object_key is not null,
        'collected_at', sig.collected_at
      ) end
      from public.job_signatures as sig
      where sig.organization_id = job_row.organization_id and sig.id = report_row.signature_id
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 2. The customer's reader: a removed photo loses its words along with its picture
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.resolve_job_report_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.job_report_access_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.job_report_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  return jsonb_set(
    link_row.frozen_document,
    '{photos}',
    (
      select coalesce(jsonb_agg(
        case when file.id is not null and file.trashed_at is null
          then photo.value || jsonb_build_object('removed', false)
          else jsonb_build_object('file_id', null, 'file_name', null, 'caption', null, 'labels', '[]'::jsonb,
            'removed', true)
        end
        order by photo.ordinality
      ), '[]'::jsonb)
      from jsonb_array_elements(coalesce(link_row.frozen_document -> 'photos', '[]'::jsonb))
        with ordinality as photo(value, ordinality)
      left join public.files file
        on file.organization_id = link_row.organization_id
       and file.id = (photo.value ->> 'file_id')::uuid
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 3. The report editor shows each candidate photo's caption and labels
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.job_report_state(target_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  org uuid;
  report_row public.job_reports;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.organization_id into org from public.jobs as job where job.id = target_job_id;
  if org is null then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if not private.member_has_permission(org, caller, 'jobs.edit')
     or not private.can_view_job(org, target_job_id) then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = org and job_id = target_job_id;

  return jsonb_build_object(
    'report', jsonb_build_object(
      'include_service_details', coalesce(report_row.include_service_details, true),
      'include_price', coalesce(report_row.include_price, false),
      'signature_id', report_row.signature_id,
      'summary', report_row.summary,
      'photo_ids', (
        select coalesce(jsonb_agg(photo.file_id order by photo.created_at, photo.file_id), '[]'::jsonb)
        from public.job_report_photos as photo
        where photo.organization_id = org and photo.job_id = target_job_id
      ),
      'checklist', (
        select coalesce(jsonb_agg(jsonb_build_object('visit_id', sel.visit_id, 'item_id', sel.item_id)),
          '[]'::jsonb)
        from public.job_report_checklist_items as sel
        where sel.organization_id = org and sel.job_id = target_job_id
      )
    ),
    'has_content', private.job_report_has_content(org, target_job_id),
    'can_view_price', private.member_has_permission(org, caller, 'jobs.view_price'),
    'candidates', jsonb_build_object(
      -- Every checked, un-trashed photo linked to the job itself or to any of its visits. A line photo is a
      -- picture of what was priced, not of the work, so it is not offered.
      'photos', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'file_id', candidate.id,
            'file_name', candidate.display_name,
            'mime_type', candidate.mime_type,
            'has_thumbnail', candidate.thumbnail_object_key is not null,
            'created_at', candidate.created_at,
            'caption', candidate.caption,
            'labels', (
              select coalesce(jsonb_agg(label.name order by lower(label.name), label.id), '[]'::jsonb)
              from public.file_label_assignments as assignment
              join public.file_labels as label
                on label.organization_id = assignment.organization_id and label.id = assignment.label_id
              where assignment.organization_id = org
                and assignment.file_id = candidate.id
            )
          ) order by candidate.created_at, candidate.id
        ), '[]'::jsonb)
        from public.files as candidate
        where candidate.organization_id = org
          and candidate.kind = 'image'
          and candidate.processing_state = 'available'
          and candidate.trashed_at is null
          and exists (
            select 1 from public.file_links as link
            where link.organization_id = org
              and link.file_id = candidate.id
              and link.role <> 'line_photo'
              and (
                (link.entity_type = 'job' and link.entity_id = target_job_id)
                or (link.entity_type = 'visit' and link.entity_id in (
                  select visit.id from public.job_visits as visit
                  where visit.organization_id = org and visit.job_id = target_job_id
                ))
              )
          )
      ),
      -- Answered checklist questions, grouped by the visit that answered them. Only answered ones are
      -- pickable: there is nothing to show a customer for a blank question.
      'visits', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'visit_id', grp.visit_id,
            'visit_date', grp.visit_date,
            'items', grp.items
          ) order by grp.visit_date, grp.visit_id
        ), '[]'::jsonb)
        from (
          select visit.id as visit_id,
                 visit.visit_date,
                 jsonb_agg(
                   jsonb_build_object(
                     'item_id', item.id,
                     'label', item.label,
                     'item_type', item.item_type,
                     'value', answer.value
                   ) order by item.position, item.id
                 ) as items
          from public.visit_checklist_answers as answer
          join public.job_visits as visit
            on visit.organization_id = answer.organization_id and visit.id = answer.visit_id
          join public.job_checklist_items as item
            on item.organization_id = answer.organization_id and item.id = answer.item_id
          where answer.organization_id = org and answer.job_id = target_job_id
          group by visit.id, visit.visit_date
        ) as grp
      ),
      -- The job's signatures, so one can be shown on the report.
      'signatures', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', sig.id,
            'signer_name', sig.signer_name,
            'signature_type', sig.signature_type,
            'collected_at', sig.collected_at
          ) order by sig.collected_at desc, sig.id desc
        ), '[]'::jsonb)
        from public.job_signatures as sig
        where sig.organization_id = org and sig.job_id = target_job_id
      )
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 4. list_files: caption in the row and in search, and a one-label filter
-- ---------------------------------------------------------------------------------------------------------

-- The return type gains a column, which create or replace cannot do.
drop function if exists public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean);

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
language sql
stable
set search_path = pg_catalog, public
as $$
  with search as (
    select
      case
        when target_search is null or btrim(target_search) = '' then null
        else '%' || replace(replace(btrim(target_search), '\', '\\'), '%', '\%') || '%'
      end as pattern,
      nullif(regexp_replace(coalesce(target_search, ''), '\D', '', 'g'), '')::bigint as number
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
  where file.organization_id = target_organization_id
    and (case when target_view = 'trash' then file.trashed_at is not null else file.trashed_at is null end)
    and (target_view <> 'recent' or file.created_at >= now() - interval '30 days')
    and (target_view <> 'photos' or file.kind = 'image')
    and (target_view <> 'videos' or file.kind = 'video')
    and (target_view <> 'documents' or file.kind = 'document')
    and (target_folder_id is null or file.folder_id = target_folder_id)
    and (
      target_label_id is null
      or exists (
        select 1
        from public.file_label_assignments assignment
        where assignment.organization_id = file.organization_id
          and assignment.file_id = file.id
          and assignment.label_id = target_label_id
      )
    )
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
            and link.role not in ('line_photo', 'report_photo')
        )
      )
    )
    and (not only_attachable or file.processing_state = 'available')
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
      cursor_created_at is null
      or cursor_id is null
      or (file.created_at, file.id) < (cursor_created_at, cursor_id)
    )
  order by file.created_at desc, file.id desc
  limit least(greatest(coalesce(target_limit, 40), 1), 100);
$$;

comment on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean, uuid) is
  'One page of the File Manager catalog, newest first, with the number of distinct records the reader may view. Search matches the file name, the photo caption, and the records the file is on; target_label_id narrows to photos carrying that label. The "on_record" view is the picker''s "already on this record" section. Security invoker: the Part 2 policies decide every row, so a hidden record is absent from the list and from the count.';

revoke all on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean, uuid)
  from public, anon;
grant execute on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean, uuid)
  to authenticated;
