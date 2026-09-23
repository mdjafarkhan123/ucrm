-- Files and Media, Part 7A: a job's work report picks its photos from the File Manager.
--
-- Since Part 5F a photo added to a job or visit is a File Manager File and no longer writes a legacy
-- public.attachments row, but the work report still chose its photos from public.attachments. New job photos
-- could therefore never reach a customer's work report. This moves the report onto public.files, the same way
-- Part 6B moved a quote's customer files and Part 6C its line photos.
--
--   * job_report_photos.attachment_id becomes file_id, backfilled losslessly from attachments.file_id.
--   * Links already issued keep the document frozen onto them; only the photo's identifier inside it is
--     rewritten from the attachment id to the same picture's File id, so the customer sees exactly what they
--     saw before.
--   * A photo on the report is linked to the job with the file_links role 'report_photo' ("Used in" shows it).
--     That link is protected while a live customer link still shows the photo, which is what the Trash
--     dialog's strongest warning and Restore both rely on.
--   * Trash lets go of the photo in the editable report selection. A customer link already issued keeps
--     naming it and shows "Photo removed" until it is restored.

-- ---------------------------------------------------------------------------------------------------------
-- 1. job_report_photos.attachment_id -> file_id
-- ---------------------------------------------------------------------------------------------------------

alter table public.job_report_photos add column file_id uuid;

update public.job_report_photos photo
set file_id = attachment.file_id
from public.attachments attachment
where attachment.organization_id = photo.organization_id
  and attachment.id = photo.attachment_id;

-- Every attachment was backfilled into a File in Part 2, so nothing is left behind here. Should one be, the
-- NOT NULL below stops the migration rather than silently dropping a photo off a report.
alter table public.job_report_photos alter column file_id set not null;

alter table public.job_report_photos drop constraint job_report_photos_attachment_fk;
alter table public.job_report_photos drop constraint job_report_photos_unique;
drop index public.job_report_photos_attachment_idx;
alter table public.job_report_photos drop column attachment_id;

-- RESTRICT, like the quote tables: permanent purge (Part 8) must retire a report's use of a File explicitly.
alter table public.job_report_photos
  add constraint job_report_photos_file_fk foreign key (organization_id, file_id)
    references public.files (organization_id, id) on delete restrict,
  add constraint job_report_photos_unique unique (organization_id, job_id, file_id);

create index job_report_photos_file_idx on public.job_report_photos (organization_id, file_id);

comment on column public.job_report_photos.file_id is
  'The File Manager photo chosen for this job''s work report. Must be an available image linked to the job or one of its visits.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. Documents already frozen onto customer links name the same photo by its File id
-- ---------------------------------------------------------------------------------------------------------

update public.job_report_access_links link
set frozen_document = jsonb_set(
  link.frozen_document,
  '{photos}',
  (
    select coalesce(jsonb_agg(
      jsonb_build_object('file_id', attachment.file_id, 'file_name', photo.value ->> 'file_name')
      order by photo.ordinality
    ), '[]'::jsonb)
    from jsonb_array_elements(link.frozen_document -> 'photos') with ordinality as photo(value, ordinality)
    join public.attachments attachment
      on attachment.organization_id = link.organization_id
     and attachment.id = (photo.value ->> 'attachment_id')::uuid
    where attachment.file_id is not null
  )
)
where jsonb_typeof(link.frozen_document -> 'photos') = 'array'
  and jsonb_array_length(link.frozen_document -> 'photos') > 0;

-- ---------------------------------------------------------------------------------------------------------
-- 3. The 'report_photo' links, and their protection
-- ---------------------------------------------------------------------------------------------------------

-- Part 2's backfill marked a job's ordinary attachment link protected when the legacy report used it. That
-- job now lives on the 'report_photo' link below, so the ordinary one goes back to being ordinary.
update public.file_links
set protected = false
where entity_type in ('job', 'visit')
  and role = 'attachment'
  and protected;

-- Brings one job's 'report_photo' links in line with its report. A photo has a link while the report selects
-- it or a live customer link shows it; the link is protected exactly while a live customer link shows it.
create or replace function private.sync_job_report_photo_links(target_organization_id uuid, target_job_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  with shown as (
    select distinct (photo.value ->> 'file_id')::uuid as file_id
    from public.job_report_access_links link
    cross join lateral jsonb_array_elements(coalesce(link.frozen_document -> 'photos', '[]'::jsonb)) as photo(value)
    where link.organization_id = target_organization_id
      and link.job_id = target_job_id
      and link.revoked_at is null
      and photo.value ->> 'file_id' is not null
  ),
  used as (
    select photo.file_id from public.job_report_photos photo
    where photo.organization_id = target_organization_id and photo.job_id = target_job_id
    union
    select shown.file_id from shown
  )
  insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
  select target_organization_id, file.id, 'job', target_job_id, 'report_photo', (select auth.uid())
  from used
  join public.files file on file.organization_id = target_organization_id and file.id = used.file_id
  where file.trashed_at is null and file.processing_state = 'available'
  on conflict (file_id, entity_type, entity_id, role) do nothing;

  update public.file_links link
  set protected = exists (
    select 1
    from public.job_report_access_links access_link
    cross join lateral jsonb_array_elements(coalesce(access_link.frozen_document -> 'photos', '[]'::jsonb)) as photo(value)
    where access_link.organization_id = target_organization_id
      and access_link.job_id = target_job_id
      and access_link.revoked_at is null
      and photo.value ->> 'file_id' = link.file_id::text
  )
  where link.organization_id = target_organization_id
    and link.entity_type = 'job'
    and link.entity_id = target_job_id
    and link.role = 'report_photo';

  delete from public.file_links link
  where link.organization_id = target_organization_id
    and link.entity_type = 'job'
    and link.entity_id = target_job_id
    and link.role = 'report_photo'
    and not link.protected
    and not exists (
      select 1 from public.job_report_photos photo
      where photo.organization_id = target_organization_id
        and photo.job_id = target_job_id
        and photo.file_id = link.file_id
    );
end;
$$;

revoke all on function private.sync_job_report_photo_links(uuid, uuid) from public, anon, authenticated;

comment on function private.sync_job_report_photo_links(uuid, uuid) is
  'Keeps one job''s ''report_photo'' file links equal to its report selection plus the photos a live customer link shows, protected exactly while a live link shows them.';

-- ---------------------------------------------------------------------------------------------------------
-- 4. The customer document reads Files
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
    'photos', (
      select coalesce(jsonb_agg(
        jsonb_build_object('file_id', file.id, 'file_name', file.display_name)
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

-- The customer's reader. The document stays frozen, but a photo moved to Trash since the link was issued is
-- shown as removed rather than silently dropped, the way a published quote shows it (Part 6C).
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
          else jsonb_build_object('file_id', null, 'file_name', null, 'removed', true)
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
-- 5. The editor read offers the job's File Manager photos
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
            'created_at', candidate.created_at
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
-- 6. Saving the report takes File ids
-- ---------------------------------------------------------------------------------------------------------

drop function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb);

create function public.save_job_report(
  target_job_id uuid,
  new_include_service_details boolean,
  new_include_price boolean,
  new_signature_id uuid default null,
  new_summary text default null,
  photo_file_ids uuid[] default '{}'::uuid[],
  checklist_selections jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  clean_summary text;
  had_content boolean;
  has_content_now boolean;
  photo_count integer;
  selection_count integer;
begin
  if caller is null then
    raise exception 'You must be signed in to save a report.' using errcode = 'insufficient_privilege';
  end if;

  select * into job_row from public.jobs where id = target_job_id for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if not private.member_has_permission(job_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  if new_include_service_details is null or new_include_price is null then
    raise exception 'A report needs its options set.' using errcode = 'P0400';
  end if;
  if new_include_price and not new_include_service_details then
    raise exception 'Show the work list before showing its prices.' using errcode = 'P0400';
  end if;
  if new_include_price
     and not private.member_has_permission(job_row.organization_id, caller, 'jobs.view_price') then
    raise exception 'You do not have access to show prices on this report.'
      using errcode = 'insufficient_privilege';
  end if;

  clean_summary := nullif(trim(coalesce(new_summary, '')), '');
  if clean_summary is not null and char_length(clean_summary) > 2000 then
    raise exception 'That summary is too long.' using errcode = 'P0400';
  end if;

  -- The signature, if one is chosen, must be this job's.
  if new_signature_id is not null then
    if not exists (
      select 1 from public.job_signatures as sig
      where sig.organization_id = job_row.organization_id
        and sig.id = new_signature_id
        and sig.job_id = target_job_id
    ) then
      raise exception 'That signature is not on this job.' using errcode = 'P0404';
    end if;
  end if;

  -- Every chosen photo must be a checked, un-trashed image linked to this job or one of its visits -- the
  -- same set job_report_state offers.
  if photo_file_ids is not null and array_length(photo_file_ids, 1) is not null then
    select count(*) into photo_count
    from public.files as file
    where file.organization_id = job_row.organization_id
      and file.id = any(photo_file_ids)
      and file.kind = 'image'
      and file.processing_state = 'available'
      and file.trashed_at is null
      and exists (
        select 1 from public.file_links as link
        where link.organization_id = job_row.organization_id
          and link.file_id = file.id
          and link.role <> 'line_photo'
          and (
            (link.entity_type = 'job' and link.entity_id = target_job_id)
            or (link.entity_type = 'visit' and link.entity_id in (
              select visit.id from public.job_visits as visit
              where visit.organization_id = job_row.organization_id and visit.job_id = target_job_id
            ))
          )
      );
    if photo_count <> cardinality(array(select distinct unnest(photo_file_ids))) then
      raise exception 'One of those photos does not belong to this job.' using errcode = 'P0400';
    end if;
  end if;

  -- Every chosen checklist answer must name a question and a visit that are both this job's.
  if checklist_selections is not null and jsonb_array_length(checklist_selections) > 0 then
    select count(*) into selection_count
    from jsonb_array_elements(checklist_selections) as choice
    where exists (
      select 1 from public.job_checklist_items as item
      where item.organization_id = job_row.organization_id
        and item.id = (choice ->> 'item_id')::uuid
        and item.job_id = target_job_id
    )
    and exists (
      select 1 from public.job_visits as visit
      where visit.organization_id = job_row.organization_id
        and visit.id = (choice ->> 'visit_id')::uuid
        and visit.job_id = target_job_id
    );
    if selection_count <> jsonb_array_length(checklist_selections) then
      raise exception 'One of those checklist answers does not belong to this job.'
        using errcode = 'P0400';
    end if;
  end if;

  had_content := private.job_report_has_content(job_row.organization_id, target_job_id);

  insert into public.job_reports (
    organization_id, job_id, include_service_details, include_price, signature_id, summary, updated_by
  ) values (
    job_row.organization_id, target_job_id, new_include_service_details, new_include_price,
    new_signature_id, clean_summary, caller
  )
  on conflict (organization_id, job_id) do update
    set include_service_details = excluded.include_service_details,
        include_price = excluded.include_price,
        signature_id = excluded.signature_id,
        summary = excluded.summary,
        updated_by = excluded.updated_by,
        updated_at = now();

  delete from public.job_report_photos
  where organization_id = job_row.organization_id and job_id = target_job_id;
  if photo_file_ids is not null and array_length(photo_file_ids, 1) is not null then
    insert into public.job_report_photos (organization_id, job_id, file_id)
    select job_row.organization_id, target_job_id, chosen
    from (select distinct unnest(photo_file_ids) as chosen) as distinct_photos;
  end if;

  perform private.sync_job_report_photo_links(job_row.organization_id, target_job_id);

  delete from public.job_report_checklist_items
  where organization_id = job_row.organization_id and job_id = target_job_id;
  if checklist_selections is not null and jsonb_array_length(checklist_selections) > 0 then
    insert into public.job_report_checklist_items (organization_id, job_id, visit_id, item_id)
    select distinct job_row.organization_id, target_job_id,
      (choice ->> 'visit_id')::uuid, (choice ->> 'item_id')::uuid
    from jsonb_array_elements(checklist_selections) as choice;
  end if;

  has_content_now := private.job_report_has_content(job_row.organization_id, target_job_id);

  -- Only a crossing is worth a feed line.
  if had_content <> has_content_now then
    insert into public.activity_events (
      organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
    ) values (
      job_row.organization_id, 'job', target_job_id,
      case when has_content_now then 'job.work_report_prepared' else 'job.work_report_cleared' end,
      case when has_content_now then 'Prepared a work report for the customer'
           else 'Cleared the work report' end,
      caller,
      jsonb_build_object('job_id', target_job_id)
    );
  end if;

  return jsonb_build_object('job_id', target_job_id, 'has_content', has_content_now);
end;
$$;

revoke all on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb) from public, anon;
grant execute on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb) to authenticated, service_role;

comment on function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb) is
  'Replaces a job''s whole work-report selection in one call; photos are File Manager Files linked to the job or its visits. Needs jobs.edit; include_price additionally needs jobs.view_price. Writes one feed line only when the report crosses between empty and not.';

-- ---------------------------------------------------------------------------------------------------------
-- 7. Issuing and turning off a customer link re-syncs which photos are protected
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.issue_job_report_access_link(target_job_id uuid, supplied_token_hash bytea)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_row public.jobs;
  report_row public.job_reports;
  business_name text;
  client_name text;
  client_email text;
  link_row public.job_report_access_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'A customer link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into job_row from public.jobs where id = target_job_id for update;
  if job_row.id is null
     or not private.member_has_permission(job_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(job_row.organization_id, target_job_id) then
    raise exception 'You do not have access to share this job.' using errcode = 'insufficient_privilege';
  end if;

  if not private.job_report_has_content(job_row.organization_id, target_job_id) then
    raise exception 'Add something to the work report before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = job_row.organization_id
             and method.client_id = job_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = job_row.organization_id and client.id = job_row.client_id;

  if client_email is null then
    raise exception 'Add an email address to this client before creating a customer link.'
      using errcode = 'check_violation';
  end if;

  select * into report_row
  from public.job_reports
  where organization_id = job_row.organization_id and job_id = target_job_id;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = job_row.organization_id;

  update public.job_report_access_links
  set revoked_at = now(), revoked_reason = 'rotated'
  where organization_id = job_row.organization_id
    and job_id = target_job_id
    and revoked_at is null;

  insert into public.job_report_access_links (
    organization_id, job_id, recipient_name, recipient_email, token_hash, issued_by, frozen_document
  ) values (
    job_row.organization_id, target_job_id,
    coalesce(nullif(trim(client_name), ''), client_email), client_email,
    supplied_token_hash, caller,
    private.job_report_customer_document(job_row, business_name, coalesce(report_row.include_price, false))
  )
  returning * into link_row;

  perform private.sync_job_report_photo_links(job_row.organization_id, target_job_id);

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    job_row.organization_id, 'job', target_job_id, 'job.work_report_link_issued',
    'Shared the work report with the customer', caller,
    jsonb_build_object('job_report_access_link_id', link_row.id, 'recipient_email', client_email)
  );

  return jsonb_build_object(
    'job_id', target_job_id,
    'job_report_access_link_id', link_row.id,
    'recipient_name', link_row.recipient_name,
    'recipient_email', link_row.recipient_email,
    'issued_at', link_row.issued_at,
    'expires_at', link_row.expires_at
  );
end;
$$;

create or replace function public.revoke_job_report_access_link(target_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  link_row public.job_report_access_links;
begin
  select * into link_row from public.job_report_access_links where id = target_link_id for update;

  if link_row.id is null
     or not private.member_has_permission(link_row.organization_id, caller, 'jobs.edit')
     or not private.can_view_job(link_row.organization_id, link_row.job_id) then
    raise exception 'You do not have access to change this link.' using errcode = 'insufficient_privilege';
  end if;

  if link_row.revoked_at is not null then
    return jsonb_build_object(
      'job_report_access_link_id', link_row.id, 'revoked_at', link_row.revoked_at,
      'already_revoked', true
    );
  end if;

  update public.job_report_access_links
  set revoked_at = now(), revoked_reason = 'revoked'
  where id = link_row.id
  returning * into link_row;

  perform private.sync_job_report_photo_links(link_row.organization_id, link_row.job_id);

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    link_row.organization_id, 'job', link_row.job_id, 'job.work_report_link_revoked',
    'Turned off the work report link', caller,
    jsonb_build_object('job_report_access_link_id', link_row.id)
  );

  return jsonb_build_object(
    'job_report_access_link_id', link_row.id, 'revoked_at', link_row.revoked_at,
    'already_revoked', false
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 8. Trash: a photo a customer's live work-report link shows gets the strongest warning
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.trash_file(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid,
  acknowledge_customer_copies boolean default false
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  trashed public.files;
  affected_quote_ids uuid[];
  affected_job_ids uuid[];
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  perform 1 from public.files file
  where file.id = target_file_id
    and file.organization_id = target_organization_id
    and file.trashed_at is null
  for update;
  if not found then
    raise exception 'That file was not found.' using errcode = 'no_data_found';
  end if;

  -- The hardest warning level. The ordinary confirm is not enough when a customer already received the File
  -- on a published quote or a live work-report link: their copy is about to change, so the contractor must
  -- have said so explicitly.
  if not coalesce(acknowledge_customer_copies, false) and (
    exists (
      select 1 from public.quote_version_attachments version_attachment
      join public.quote_versions version on version.id = version_attachment.quote_version_id
      where version_attachment.organization_id = target_organization_id
        and version_attachment.file_id = target_file_id
        and version.status = 'published'
    )
    or exists (
      select 1 from public.quote_version_lines line
      join public.quote_versions version on version.id = line.quote_version_id
      where line.organization_id = target_organization_id
        and line.image_file_id = target_file_id
        and version.status = 'published'
    )
    or exists (
      select 1 from public.file_links link
      where link.organization_id = target_organization_id
        and link.file_id = target_file_id
        and link.role = 'report_photo'
        and link.protected
    )
  ) then
    raise exception 'A customer already received this file. Confirm that their copy will show it as removed.'
      using errcode = 'P0412';
  end if;

  select coalesce(array_agg(distinct used.quote_id), '{}'::uuid[]) into affected_quote_ids
  from (
    select version_attachment.quote_id from public.quote_version_attachments version_attachment
    where version_attachment.organization_id = target_organization_id and version_attachment.file_id = target_file_id
    union
    select line.quote_id from public.quote_version_lines line
    where line.organization_id = target_organization_id and line.image_file_id = target_file_id
  ) as used;

  -- Everything still being edited lets go of the File now. Published quote versions and issued work-report
  -- links keep pointing at it: that frozen reference is what shows the customer the gap, and what Restore
  -- brings back.
  delete from public.quote_version_attachments version_attachment
  using public.quote_versions version
  where version_attachment.organization_id = target_organization_id
    and version_attachment.file_id = target_file_id
    and version.id = version_attachment.quote_version_id
    and version.status = 'draft';

  update public.quote_version_lines line
  set image_file_id = null
  from public.quote_versions version
  where line.organization_id = target_organization_id
    and line.image_file_id = target_file_id
    and version.id = line.quote_version_id
    and version.status = 'draft';

  update public.request_pricing_lines set image_file_id = null
  where organization_id = target_organization_id and image_file_id = target_file_id;
  update public.job_line_items set image_file_id = null
  where organization_id = target_organization_id and image_file_id = target_file_id;
  update public.job_visit_line_items set image_file_id = null
  where organization_id = target_organization_id and image_file_id = target_file_id;

  with removed as (
    delete from public.job_report_photos
    where organization_id = target_organization_id and file_id = target_file_id
    returning job_id
  )
  select coalesce(array_agg(distinct removed.job_id), '{}'::uuid[]) into affected_job_ids from removed;

  perform private.refresh_quote_file_protection(target_organization_id, quote_id)
  from unnest(affected_quote_ids) as quote_id;

  perform private.sync_job_report_photo_links(target_organization_id, job_id)
  from unnest(affected_job_ids) as job_id;

  -- Every ordinary use is detached, as the dialog said. A use a customer's copy still holds stays linked,
  -- which is what lets Restore put the File back where the customer saw it.
  delete from public.file_links
  where organization_id = target_organization_id
    and file_id = target_file_id
    and not protected;

  update public.files
  set trashed_at = now(),
      trashed_by = target_actor_id
  where id = target_file_id
    and organization_id = target_organization_id
  returning * into trashed;

  return trashed;
end;
$$;

comment on function public.trash_file(uuid, uuid, uuid, boolean) is
  'Moves one File to Trash. Any File can go. One a customer already received on a published quote or a live work-report link needs acknowledge_customer_copies (SQLSTATE P0412 otherwise); the customer''s copy then shows it as removed. Drafts, request pricing, job/visit lines and the editable work-report selection let go of it; ordinary links are detached and protected ones kept for Restore. Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- 9. "Used in" says a live work-report link shows the photo -- and works again for everyone
-- ---------------------------------------------------------------------------------------------------------

-- 20260924090000 joined public.marketing_campaigns straight into file_usage. file_usage runs as the caller and
-- authenticated has no SELECT on that table, so Postgres refused the whole query and every File's details
-- panel failed to load -- the same failure 20260923220000 fixed for messages. The campaign's name and status
-- now come from this security-definer lookup, only when the caller may view the campaign (the same
-- can_view_linked_entity rule file_links' own policy uses). No table grant is widened.
create or replace function public.file_link_marketing_campaign(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
) returns table (name text, status text)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select campaign.name, campaign.status
  from public.marketing_campaigns campaign
  where target_entity_type = 'marketing_campaign'
    and campaign.id = target_entity_id
    and campaign.organization_id = target_organization_id
    and private.can_view_linked_entity(target_organization_id, 'marketing_campaign', target_entity_id);
$$;

revoke all on function public.file_link_marketing_campaign(uuid, text, uuid) from public, anon;
grant execute on function public.file_link_marketing_campaign(uuid, text, uuid) to authenticated;

create or replace function public.file_usage(
  target_organization_id uuid,
  target_file_id uuid,
  target_limit integer default 10,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns table (
  id uuid, entity_type text, entity_id uuid, role text, protected boolean, customer_received boolean,
  title text, context text, status text, link_type text, link_id uuid, created_at timestamptz
)
language sql
stable
set search_path = pg_catalog, public
as $$
  select
    link.id,
    link.entity_type,
    link.entity_id,
    link.role,
    link.protected or link.entity_type = 'message' as protected,
    link.entity_type = 'quote' and (
      exists (
        select 1 from public.quote_version_attachments version_attachment
        join public.quote_versions version on version.id = version_attachment.quote_version_id
        where version_attachment.organization_id = link.organization_id
          and version_attachment.quote_id = link.entity_id
          and version_attachment.file_id = link.file_id
          and version.status = 'published'
      )
      or exists (
        select 1 from public.quote_version_lines line
        join public.quote_versions version on version.id = line.quote_version_id
        where line.organization_id = link.organization_id
          and line.quote_id = link.entity_id
          and line.image_file_id = link.file_id
          and version.status = 'published'
      )
    )
    or link.entity_type = 'message'
    or (link.entity_type = 'marketing_campaign' and campaign_record.status in ('sending', 'completed', 'needs_attention'))
    or (link.role = 'report_photo' and link.protected)
    as customer_received,
    case link.entity_type
      when 'client' then client_record.display_name
      when 'property' then coalesce(nullif(btrim(property_record.label), ''), property_record.address_line1)
      when 'request' then request_record.title
      when 'quote' then 'Quote #' || quote_record.quote_number
      when 'invoice' then 'Invoice #' || invoice_record.invoice_number
      when 'job' then 'Job #' || job_record.job_number
      when 'visit' then coalesce(nullif(btrim(visit_record.title), ''), 'Visit')
      when 'job_expense' then expense_record.name
      when 'organization' then 'Business logo'
      when 'marketing_campaign' then campaign_record.name
      when 'message' then
        case message_record.channel
          when 'email' then coalesce(nullif(btrim(message_record.subject), ''), 'Email')
          else 'Text message'
        end
    end as title,
    case link.entity_type
      when 'property' then nullif(btrim(concat_ws(', ', property_record.address_line1, property_record.city)), '')
      when 'quote' then nullif(btrim(quote_record.title), '')
      when 'invoice' then nullif(btrim(invoice_record.subject), '')
      when 'job' then nullif(btrim(job_record.title), '')
      when 'visit' then 'Job #' || visit_job.job_number
      when 'job_expense' then 'Job #' || expense_job.job_number
      when 'message' then message_record.client_name
    end as context,
    case link.entity_type
      when 'client' then client_record.lifecycle_status
      when 'request' then request_record.status
      when 'quote' then quote_record.status
      when 'job' then job_record.status
      when 'message' then message_record.status
      when 'marketing_campaign' then campaign_record.status
    end as status,
    -- A message has no page of its own, so it redirects like a visit or job expense does: into its parent,
    -- here the client's conversation rather than the client's own profile.
    case link.entity_type
      when 'visit' then 'job'
      when 'job_expense' then 'job'
      when 'message' then 'message'
      else link.entity_type
    end as link_type,
    case link.entity_type
      when 'visit' then visit_record.job_id
      when 'job_expense' then expense_record.job_id
      when 'message' then message_record.client_id
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
  left join public.invoices invoice_record
    on link.entity_type = 'invoice' and invoice_record.id = link.entity_id
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
  left join lateral public.file_link_marketing_campaign(link.organization_id, link.entity_type, link.entity_id) campaign_record
    on true
  left join lateral public.file_link_message(link.organization_id, link.entity_type, link.entity_id) message_record
    on true
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

-- ---------------------------------------------------------------------------------------------------------
-- 10. A report photo is not one of the job's own files, so it stays off the job's Files card
-- ---------------------------------------------------------------------------------------------------------

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
  only_attachable boolean default false
)
returns table (
  id uuid, display_name text, mime_type text, kind text, size_bytes bigint, has_thumbnail boolean,
  folder_id uuid, folder_name text, origin_type text, origin_id uuid, processing_state text,
  uploaded_by uuid, uploaded_by_name text, created_at timestamptz, trashed_at timestamptz, usage_count integer
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
    )::integer as usage_count
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

-- ---------------------------------------------------------------------------------------------------------
-- 11. Every existing report gets its 'report_photo' links
-- ---------------------------------------------------------------------------------------------------------

select private.sync_job_report_photo_links(job.organization_id, job.job_id)
from (
  select organization_id, job_id from public.job_report_photos
  union
  select organization_id, job_id from public.job_report_access_links where revoked_at is null
) as job;

-- ---------------------------------------------------------------------------------------------------------
-- 12. backfill_files_from_attachments: its protected check read job_report_photos.attachment_id, which no
--     longer exists. A work report's photos are protected on their own 'report_photo' link now, so the
--     ordinary 'attachment' link this backfills no longer takes protection from the report. Only that
--     exists-clause is removed.
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.backfill_files_from_attachments()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  created integer;
begin

insert into public.files (
  organization_id, display_name, mime_type, size_bytes, object_key, thumbnail_object_key,
  origin_type, origin_id, processing_state, uploaded_by, created_at, updated_at
)
select
  attachment.organization_id,
  attachment.file_name,
  attachment.mime_type,
  attachment.size_bytes,
  attachment.object_key,
  attachment.thumbnail_object_key,
  attachment.entity_type,
  attachment.entity_id,
  'available',
  attachment.uploaded_by,
  attachment.created_at,
  attachment.created_at
from public.attachments as attachment
on conflict (object_key) do nothing;

get diagnostics created = row_count;

update public.attachments as attachment
set file_id = file.id
from public.files as file
where file.object_key = attachment.object_key
  and file.organization_id = attachment.organization_id
  and attachment.file_id is distinct from file.id;

insert into public.file_links (
  organization_id, file_id, entity_type, entity_id, role, protected, created_by, created_at
)
select
  attachment.organization_id,
  attachment.file_id,
  attachment.entity_type,
  attachment.entity_id,
  'attachment',
  (
    exists (
      select 1 from public.quote_version_attachments as quote_file
      where quote_file.organization_id = attachment.organization_id
        and quote_file.file_id = attachment.file_id
    )
  ),
  attachment.uploaded_by,
  attachment.created_at
from public.attachments as attachment
where attachment.file_id is not null
on conflict (file_id, entity_type, entity_id, role) do nothing;

  return created;
end;
$$;

revoke all on function private.backfill_files_from_attachments() from public, anon, authenticated;
