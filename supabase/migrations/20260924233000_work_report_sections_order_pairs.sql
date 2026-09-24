-- Files and Media, Part 7C: a work report's photos in the contractor's order, under optional headings, with
-- before/after pairs (decisions approved by Jafar 2026-09-24; Memory/campaigns/files-media/parts/7C-*).
--
--   * public.job_report_sections holds a report's optional headings, each with an optional note, in order.
--   * public.job_report_photos gains the photo's place: its section (null = above the first heading), its
--     position there, and a pair side. Two photos sharing a section and position, one 'before' and one
--     'after', are one before/after pair. A photo still appears at most once in a report (the existing
--     unique key), so a photo is either on its own or in one pair.
--   * save_job_report takes the whole arrangement as one layout document instead of a bare photo list.
--   * The customer document lists photos in the arranged order and, only when the report has a heading or a
--     pair, adds a `layout` that places them by index into that list. A report with neither produces exactly
--     the document it produced before, so no link already sent looks changed.
--   * job_report_state reports whether the live customer link still matches what a new link would show.
--
-- Existing reports keep their photos in today's order (upload time), with no headings.
--
-- Rolling back: restore save_job_report, job_report_state and private.job_report_customer_document from
-- 20260924100000 / 20260924140000, drop the three new job_report_photos columns and job_report_sections.

-- ---------------------------------------------------------------------------------------------------------
-- 0. Guard: every existing report's customer document, as the current function builds it
-- ---------------------------------------------------------------------------------------------------------

-- Compared at the end (section 6). Any difference aborts the whole migration, so no report or customer link
-- can change by this migration alone.
create temporary table work_report_documents_before on commit drop as
select report.organization_id, report.job_id,
       private.job_report_customer_document(job, 'guard', report.include_price) as document
from public.job_reports as report
join public.jobs as job on job.organization_id = report.organization_id and job.id = report.job_id;

-- ---------------------------------------------------------------------------------------------------------
-- 1. Headings
-- ---------------------------------------------------------------------------------------------------------

create table public.job_report_sections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  job_id uuid not null,
  position integer not null check (position >= 0),
  heading text not null check (char_length(heading) between 1 and 80 and heading = btrim(heading)),
  note text check (note is null or (char_length(note) between 1 and 1000 and note = btrim(note))),
  created_at timestamptz not null default now(),
  constraint job_report_sections_job_fk foreign key (organization_id, job_id)
    references public.jobs (organization_id, id) on delete cascade,
  -- Also the index every read of a report's headings walks.
  constraint job_report_sections_position_unique unique (organization_id, job_id, position),
  -- The target of job_report_photos' section key, which keeps a photo inside its own job's headings.
  constraint job_report_sections_job_scope unique (organization_id, job_id, id)
);

-- Like every other work-report table: no policies, reached only through the security-definer commands.
alter table public.job_report_sections enable row level security;
revoke all on table public.job_report_sections from public, anon, authenticated;
grant all on table public.job_report_sections to service_role;

comment on table public.job_report_sections is
  'A work report''s optional headings, in order, each with an optional note. Photos above the first heading have no section.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. Each photo's place
-- ---------------------------------------------------------------------------------------------------------

alter table public.job_report_photos
  add column section_id uuid,
  add column position integer,
  add column pair_side text;

-- Today's order is the customer document's: upload time, then id.
update public.job_report_photos photo
set position = ranked.position
from (
  select report_photo.id,
         (row_number() over (
           partition by report_photo.organization_id, report_photo.job_id
           order by file.created_at, file.id
         ) - 1)::integer as position
  from public.job_report_photos report_photo
  join public.files file
    on file.organization_id = report_photo.organization_id and file.id = report_photo.file_id
) as ranked
where ranked.id = photo.id;

alter table public.job_report_photos
  alter column position set not null,
  add constraint job_report_photos_position_check check (position >= 0),
  add constraint job_report_photos_pair_side_check check (pair_side is null or pair_side in ('before', 'after')),
  -- RESTRICT: save_job_report removes a report's photos before its headings.
  add constraint job_report_photos_section_fk foreign key (organization_id, job_id, section_id)
    references public.job_report_sections (organization_id, job_id, id) on delete restrict,
  -- One photo per place, or one 'before' and one 'after' sharing it. Leads with the section key's columns,
  -- so it also serves that foreign key.
  add constraint job_report_photos_place_unique
    unique nulls not distinct (organization_id, job_id, section_id, position, pair_side);

comment on column public.job_report_photos.section_id is
  'The heading this photo sits under; null places it above the first heading.';
comment on column public.job_report_photos.position is
  'The photo''s place within its section (or above the first heading), from 0.';
comment on column public.job_report_photos.pair_side is
  'before/after when this photo is half of a before/after pair; its other half shares section_id and position. A half left alone (the other was trashed) shows as a single photo.';

-- ---------------------------------------------------------------------------------------------------------
-- 3. The customer document follows the arrangement
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
  photos_json jsonb;
  top_json jsonb;
  sections_json jsonb;
  has_layout boolean;
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

  -- Photos, resolved live from the File Manager, in the arranged order: above the first heading, then each
  -- heading in turn, a pair's 'before' ahead of its 'after'. The public file route allow-lists exactly these
  -- ids. Label names, not ids: an issued link must keep saying "Before" even after the label is renamed.
  -- `layout` places them by their index in this list, which resolve_job_report_access_link preserves.
  with visible as (
    select photo.section_id,
           section.position as section_position,
           photo.position,
           photo.pair_side,
           file.id as file_id,
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
           ) as photo
    from public.job_report_photos as photo
    join public.files as file
      on file.organization_id = photo.organization_id and file.id = photo.file_id
    left join public.job_report_sections as section
      on section.organization_id = photo.organization_id
     and section.job_id = photo.job_id
     and section.id = photo.section_id
    where photo.organization_id = job_row.organization_id
      and photo.job_id = job_row.id
      and file.trashed_at is null
      and file.processing_state = 'available'
  ),
  numbered as (
    select visible.*,
           (row_number() over (
             order by coalesce(visible.section_position, -1), visible.position,
                      case visible.pair_side when 'after' then 1 else 0 end, visible.file_id
           ) - 1)::integer as idx
    from visible
  ),
  -- A place holding both halves is a pair; a lone half (its partner trashed) is a single photo.
  places as (
    select numbered.section_id,
           numbered.position,
           case when count(*) = 2
             then jsonb_build_object(
               'before', min(numbered.idx) filter (where numbered.pair_side = 'before'),
               'after', min(numbered.idx) filter (where numbered.pair_side = 'after'))
             else jsonb_build_object('photo', min(numbered.idx))
           end as item,
           count(*) = 2 as is_pair
    from numbered
    group by numbered.section_id, numbered.position
  )
  select
    (select coalesce(jsonb_agg(numbered.photo order by numbered.idx), '[]'::jsonb) from numbered),
    (select coalesce(jsonb_agg(places.item order by places.position), '[]'::jsonb)
     from places where places.section_id is null),
    (select coalesce(jsonb_agg(
       jsonb_build_object(
         'heading', section.heading,
         'note', section.note,
         'items', (
           select coalesce(jsonb_agg(places.item order by places.position), '[]'::jsonb)
           from places where places.section_id = section.id
         )
       ) order by section.position
     ), '[]'::jsonb)
     from public.job_report_sections as section
     where section.organization_id = job_row.organization_id and section.job_id = job_row.id),
    exists (
      select 1 from public.job_report_sections as section
      where section.organization_id = job_row.organization_id and section.job_id = job_row.id
    ) or exists (select 1 from places where places.is_pair)
  into photos_json, top_json, sections_json, has_layout;

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
    'photos', photos_json,
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
  )
  -- Only an arranged report carries a layout, so a plain one is byte-for-byte what it was before 7C.
  || case when has_layout
       then jsonb_build_object('layout', jsonb_build_object('top', top_json, 'sections', sections_json))
       else '{}'::jsonb end;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Saving takes the whole arrangement
-- ---------------------------------------------------------------------------------------------------------

drop function public.save_job_report(uuid, boolean, boolean, uuid, text, uuid[], jsonb);

-- new_layout: {"top": [item], "sections": [{"heading": text, "note": text|null, "items": [item]}]}
-- where item is {"file_id": uuid} or {"before_file_id": uuid, "after_file_id": uuid}.
create function public.save_job_report(
  target_job_id uuid,
  new_include_service_details boolean,
  new_include_price boolean,
  new_signature_id uuid default null,
  new_summary text default null,
  new_layout jsonb default '{"top": [], "sections": []}'::jsonb,
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
  section_count integer;
  layout_top jsonb;
  layout_sections jsonb;
  layout_places jsonb;
  photo_file_ids uuid[];
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

  -- The layout's shape. The route's Zod schema already shaped it; this is the command's own guard.
  layout_top := coalesce(new_layout -> 'top', '[]'::jsonb);
  layout_sections := coalesce(new_layout -> 'sections', '[]'::jsonb);
  if jsonb_typeof(layout_top) <> 'array' or jsonb_typeof(layout_sections) <> 'array' then
    raise exception 'That report layout is not readable.' using errcode = 'P0400';
  end if;
  section_count := jsonb_array_length(layout_sections);
  if section_count > 50 then
    raise exception 'That is too many headings for one report.' using errcode = 'P0400';
  end if;
  if exists (
    select 1 from jsonb_array_elements(layout_sections) as section
    where jsonb_typeof(section -> 'items') is distinct from 'array'
       or nullif(btrim(coalesce(section ->> 'heading', '')), '') is null
       or char_length(btrim(section ->> 'heading')) > 80
       or char_length(btrim(coalesce(section ->> 'note', ''))) > 1000
  ) then
    raise exception 'Every heading needs a name of up to 80 characters, and a note of up to 1000.'
      using errcode = 'P0400';
  end if;

  -- Every place in the layout, flattened: which section (null = above the first heading), its position, and
  -- the photo(s) in it.
  select coalesce(jsonb_agg(jsonb_build_object(
           'section_index', place.section_index, 'position', place.position,
           'file_id', half.file_id, 'pair_side', half.pair_side)), '[]'::jsonb)
  into layout_places
  from (
    select null::integer as section_index, (item.ordinality - 1)::integer as position, item.value
    from jsonb_array_elements(layout_top) with ordinality as item(value, ordinality)
    union all
    select (section.ordinality - 1)::integer, (item.ordinality - 1)::integer, item.value
    from jsonb_array_elements(layout_sections) with ordinality as section(value, ordinality)
    cross join lateral jsonb_array_elements(section.value -> 'items') with ordinality as item(value, ordinality)
  ) as place
  cross join lateral (
    select (place.value ->> 'file_id')::uuid, null::text where place.value ? 'file_id'
    union all
    select (place.value ->> 'before_file_id')::uuid, 'before' where not place.value ? 'file_id'
    union all
    select (place.value ->> 'after_file_id')::uuid, 'after' where not place.value ? 'file_id'
  ) as half(file_id, pair_side);

  if exists (
    select 1 from jsonb_to_recordset(layout_places) as place(file_id uuid) where place.file_id is null
  ) then
    raise exception 'A before/after pair needs both photos.' using errcode = 'P0400';
  end if;

  select coalesce(array_agg(place.file_id), '{}'::uuid[]) into photo_file_ids
  from jsonb_to_recordset(layout_places) as place(file_id uuid);
  if cardinality(photo_file_ids) > 300 then
    raise exception 'That is too many photos to add.' using errcode = 'P0400';
  end if;
  if cardinality(photo_file_ids) <> cardinality(array(select distinct unnest(photo_file_ids))) then
    raise exception 'A photo can appear only once in a report.' using errcode = 'P0400';
  end if;

  -- Every chosen photo must be a checked, un-trashed image linked to this job or one of its visits -- the
  -- same set job_report_state offers.
  if cardinality(photo_file_ids) > 0 then
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
    if photo_count <> cardinality(photo_file_ids) then
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

  -- Photos first: they point at the headings.
  delete from public.job_report_photos
  where organization_id = job_row.organization_id and job_id = target_job_id;
  delete from public.job_report_sections
  where organization_id = job_row.organization_id and job_id = target_job_id;

  insert into public.job_report_sections (organization_id, job_id, position, heading, note)
  select job_row.organization_id, target_job_id, (section.ordinality - 1)::integer,
         btrim(section.value ->> 'heading'), nullif(btrim(coalesce(section.value ->> 'note', '')), '')
  from jsonb_array_elements(layout_sections) with ordinality as section(value, ordinality);

  insert into public.job_report_photos (organization_id, job_id, file_id, section_id, position, pair_side)
  select job_row.organization_id, target_job_id, place.file_id, section.id, place.position, place.pair_side
  from jsonb_to_recordset(layout_places)
    as place(section_index integer, position integer, file_id uuid, pair_side text)
  left join public.job_report_sections as section
    on section.organization_id = job_row.organization_id
   and section.job_id = target_job_id
   and section.position = place.section_index;

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

revoke all on function public.save_job_report(uuid, boolean, boolean, uuid, text, jsonb, jsonb) from public, anon;
grant execute on function public.save_job_report(uuid, boolean, boolean, uuid, text, jsonb, jsonb) to authenticated, service_role;

comment on function public.save_job_report(uuid, boolean, boolean, uuid, text, jsonb, jsonb) is
  'Replaces a job''s whole work report in one call: options, and the photo layout (photos above the first heading, then headings with their photos; an item is one photo or a before/after pair). Photos are File Manager Files linked to the job or its visits, each at most once. Needs jobs.edit; include_price additionally needs jobs.view_price. Writes one feed line only when the report crosses between empty and not.';

-- ---------------------------------------------------------------------------------------------------------
-- 5. The editor reads the arrangement, and whether the customer's link is behind it
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
  job_row public.jobs;
  org uuid;
  report_row public.job_reports;
  link_row public.job_report_access_links;
  business_name text;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;

  select * into job_row from public.jobs as job where job.id = target_job_id;
  org := job_row.organization_id;
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

  -- At most one link is live at a time: issuing a new one turns the old one off.
  select * into link_row
  from public.job_report_access_links as link
  where link.organization_id = org
    and link.job_id = target_job_id
    and link.revoked_at is null
    and (link.expires_at is null or link.expires_at > now())
  order by link.issued_at desc
  limit 1;

  if link_row.id is not null then
    select organization.name into business_name
    from public.organizations as organization
    where organization.id = org;
  end if;

  return jsonb_build_object(
    'report', jsonb_build_object(
      'include_service_details', coalesce(report_row.include_service_details, true),
      'include_price', coalesce(report_row.include_price, false),
      'signature_id', report_row.signature_id,
      'summary', report_row.summary,
      -- Every photo on the report, in its arranged order.
      'photo_ids', (
        select coalesce(jsonb_agg(photo.file_id
          order by section.position nulls first, photo.position,
                   case photo.pair_side when 'after' then 1 else 0 end), '[]'::jsonb)
        from public.job_report_photos as photo
        left join public.job_report_sections as section
          on section.organization_id = photo.organization_id
         and section.job_id = photo.job_id
         and section.id = photo.section_id
        where photo.organization_id = org and photo.job_id = target_job_id
      ),
      -- The same arrangement save_job_report takes. A lone pair half (its partner trashed) reads back as a
      -- single photo, so the next save stores it as one.
      'layout', jsonb_build_object(
        'top', private.job_report_layout_items(org, target_job_id, null),
        'sections', (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'heading', section.heading,
              'note', section.note,
              'items', private.job_report_layout_items(org, target_job_id, section.id)
            ) order by section.position
          ), '[]'::jsonb)
          from public.job_report_sections as section
          where section.organization_id = org and section.job_id = target_job_id
        )
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
    -- The customer's live link, if any, and whether it still shows what a new link would. Compared as whole
    -- documents, so an edited caption or work list counts as a change the customer has not been sent.
    'live_link', case when link_row.id is null then null else jsonb_build_object(
      'issued_at', link_row.issued_at,
      'recipient_email', link_row.recipient_email,
      'up_to_date', link_row.frozen_document is not distinct from private.job_report_customer_document(
        job_row, business_name, coalesce(report_row.include_price, false))
    ) end,
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

-- One section's items (or, for a null section, those above the first heading) in save_job_report's shape.
create or replace function private.job_report_layout_items(
  target_organization_id uuid,
  target_job_id uuid,
  target_section_id uuid
)
returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(place.item order by place.position), '[]'::jsonb)
  from (
    select photo.position,
           case when count(*) = 2
             then jsonb_build_object(
               'before_file_id', min(photo.file_id::text) filter (where photo.pair_side = 'before'),
               'after_file_id', min(photo.file_id::text) filter (where photo.pair_side = 'after'))
             else jsonb_build_object('file_id', min(photo.file_id::text))
           end as item
    from public.job_report_photos as photo
    where photo.organization_id = target_organization_id
      and photo.job_id = target_job_id
      and photo.section_id is not distinct from target_section_id
    group by photo.position
  ) as place;
$$;

revoke all on function private.job_report_layout_items(uuid, uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 6. Guard: no existing report's customer document changed
-- ---------------------------------------------------------------------------------------------------------

do $$
declare
  changed integer;
begin
  select count(*) into changed
  from pg_temp.work_report_documents_before as before
  join public.jobs as job on job.organization_id = before.organization_id and job.id = before.job_id
  join public.job_reports as report
    on report.organization_id = before.organization_id and report.job_id = before.job_id
  where before.document is distinct from
        private.job_report_customer_document(job, 'guard', report.include_price);
  if changed > 0 then
    raise exception '7C would change % existing work report document(s); aborting.', changed;
  end if;
end;
$$;
