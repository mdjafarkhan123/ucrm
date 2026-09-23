-- Files and Media, Part 6C: line-item photos move onto the File Manager, and the File Manager's deletion
-- rule changes (Jafar, 2026-09-23).
--
-- Line photos. request_pricing_lines, quote_version_lines, job_line_items and job_visit_line_items swap
-- image_attachment_id (a legacy public.attachments id) for image_file_id (a public.files id), backfilled
-- losslessly from attachments.file_id. A line photo is linked to its request, quote or job with the new
-- file_links role 'line_photo', so it shows in the library's "Used in" and an assigned field member can see a
-- job's photos, but it is not one of the record's own files: it stays off the record's Files card and out of
-- a quote's customer file list. An upload from a line says so up front (files.origin_role), because the
-- processing worker only links a File to its record once the File has been checked.
--
-- Deletion. Any File can now go to Trash, wherever it is used. A File a customer already received on a
-- published quote version needs an explicit acknowledgement (trash_file's acknowledge_customer_copies), and
-- the customer's copy then shows it as removed instead of silently changing. Editable copies (request pricing,
-- draft quote versions, job and visit lines) let go of it; published versions keep pointing at it, and their
-- file_links stay (still protected), so Restore puts it back where the customer saw it.

-- ---------------------------------------------------------------------------------------------------------
-- 1. The 'line_photo' role, and the role an upload from a record will be linked with
-- ---------------------------------------------------------------------------------------------------------

alter table public.file_links drop constraint file_links_role_check;
alter table public.file_links add constraint file_links_role_check
  check (role = any (array['attachment', 'work_photo', 'report_photo', 'line_photo']));

alter table public.files
  add column origin_role text not null default 'attachment',
  add constraint files_origin_role_check check (origin_role = any (array['attachment', 'line_photo'])),
  add constraint files_origin_role_needs_record_check
    check (origin_role = 'attachment' or origin_type <> 'file_manager');

comment on column public.files.origin_role is
  'The file_links role the processing worker links an upload to its origin record with, once it is available. ''line_photo'' is a photo picked on a pricing line.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. image_attachment_id -> image_file_id on the four line tables
-- ---------------------------------------------------------------------------------------------------------

-- Published quote lines are frozen by trigger, and the backfill must not look like an edit to any line, so
-- the guard and the updated_at stamps are off for these statements only.
alter table public.quote_version_lines disable trigger quote_version_lines_reject_published_change;
alter table public.quote_version_lines disable trigger quote_version_lines_set_updated_at;
alter table public.request_pricing_lines disable trigger request_pricing_lines_set_updated_at;
alter table public.job_line_items disable trigger job_line_items_set_updated_at;
alter table public.job_visit_line_items disable trigger job_visit_line_items_set_updated_at;

alter table public.request_pricing_lines add column image_file_id uuid;
alter table public.quote_version_lines add column image_file_id uuid;
alter table public.job_line_items add column image_file_id uuid;
alter table public.job_visit_line_items add column image_file_id uuid;

update public.request_pricing_lines line set image_file_id = attachment.file_id
from public.attachments attachment
where attachment.organization_id = line.organization_id and attachment.id = line.image_attachment_id;

update public.quote_version_lines line set image_file_id = attachment.file_id
from public.attachments attachment
where attachment.organization_id = line.organization_id and attachment.id = line.image_attachment_id;

update public.job_line_items line set image_file_id = attachment.file_id
from public.attachments attachment
where attachment.organization_id = line.organization_id and attachment.id = line.image_attachment_id;

update public.job_visit_line_items line set image_file_id = attachment.file_id
from public.attachments attachment
where attachment.organization_id = line.organization_id and attachment.id = line.image_attachment_id;

do $$
declare
  unresolved integer;
begin
  select
    (select count(*) from public.request_pricing_lines where image_attachment_id is not null and image_file_id is null)
    + (select count(*) from public.quote_version_lines where image_attachment_id is not null and image_file_id is null)
    + (select count(*) from public.job_line_items where image_attachment_id is not null and image_file_id is null)
    + (select count(*) from public.job_visit_line_items where image_attachment_id is not null and image_file_id is null)
  into unresolved;
  if unresolved > 0 then
    raise exception '% line photos have no File Manager file to move to.', unresolved;
  end if;
end;
$$;

alter table public.quote_version_lines enable trigger quote_version_lines_reject_published_change;
alter table public.quote_version_lines enable trigger quote_version_lines_set_updated_at;
alter table public.request_pricing_lines enable trigger request_pricing_lines_set_updated_at;
alter table public.job_line_items enable trigger job_line_items_set_updated_at;
alter table public.job_visit_line_items enable trigger job_visit_line_items_set_updated_at;

-- Dropping the column takes its old foreign key, index and column grant with it.
alter table public.request_pricing_lines drop column image_attachment_id;
alter table public.quote_version_lines drop column image_attachment_id;
alter table public.job_line_items drop column image_attachment_id;
alter table public.job_visit_line_items drop column image_attachment_id;

-- END OF BACKFILL

-- Editable lines let go of a purged File. A published quote line deliberately has no ON DELETE action: its
-- frozen reference is what shows the customer a removed photo, so Part 8's purge decides what it keeps.
alter table public.request_pricing_lines add constraint request_pricing_lines_image_file_fk
  foreign key (organization_id, image_file_id) references public.files (organization_id, id)
  on delete set null (image_file_id);
alter table public.quote_version_lines add constraint quote_version_lines_image_file_fk
  foreign key (organization_id, image_file_id) references public.files (organization_id, id);
alter table public.job_line_items add constraint job_line_items_image_file_fk
  foreign key (organization_id, image_file_id) references public.files (organization_id, id)
  on delete set null (image_file_id);
alter table public.job_visit_line_items add constraint job_visit_line_items_image_file_fk
  foreign key (organization_id, image_file_id) references public.files (organization_id, id)
  on delete set null (image_file_id);

create index request_pricing_lines_image_file_idx on public.request_pricing_lines (organization_id, image_file_id)
  where image_file_id is not null;
create index quote_version_lines_image_file_idx on public.quote_version_lines (organization_id, image_file_id)
  where image_file_id is not null;
create index job_line_items_image_file_idx on public.job_line_items (organization_id, image_file_id)
  where image_file_id is not null;
create index job_visit_line_items_image_file_idx on public.job_visit_line_items (organization_id, image_file_id)
  where image_file_id is not null;

grant select (image_file_id) on public.request_pricing_lines to authenticated;
grant select (image_file_id) on public.quote_version_lines to authenticated;
grant select (image_file_id) on public.job_line_items to authenticated;
grant select (image_file_id) on public.job_visit_line_items to authenticated;

comment on column public.quote_version_lines.image_file_id is
  'The line''s photo, a File Manager file. Copied forward on revise and conversion. A published version keeps it even after the File is moved to Trash, so the customer''s copy shows the photo as removed.';

-- ---------------------------------------------------------------------------------------------------------
-- 3. Line-photo helpers. Called only from the security-definer commands below, which run as the owner.
-- ---------------------------------------------------------------------------------------------------------

-- Every photo the lines of one record point at. A job's photos are the job's and all of its visits'.
create or replace function private.line_photo_file_ids(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns setof uuid
language sql
stable
set search_path = pg_catalog, public
as $$
  select line.image_file_id from public.request_pricing_lines line
  where target_entity_type = 'request' and line.organization_id = target_organization_id
    and line.request_id = target_entity_id and line.image_file_id is not null
  union
  select line.image_file_id from public.quote_version_lines line
  where target_entity_type = 'quote' and line.organization_id = target_organization_id
    and line.quote_id = target_entity_id and line.image_file_id is not null
  union
  select line.image_file_id from public.job_line_items line
  where target_entity_type = 'job' and line.organization_id = target_organization_id
    and line.job_id = target_entity_id and line.image_file_id is not null
  union
  select line.image_file_id from public.job_visit_line_items line
  where target_entity_type = 'job' and line.organization_id = target_organization_id
    and line.job_id = target_entity_id and line.image_file_id is not null;
$$;

-- A copied photo carries over only while its File is out of Trash.
create or replace function private.live_line_photo(target_organization_id uuid, target_file_id uuid)
returns uuid
language sql
stable
set search_path = pg_catalog, public
as $$
  select file.id from public.files file
  where file.organization_id = target_organization_id
    and file.id = target_file_id
    and file.trashed_at is null;
$$;

-- The photo a saved line may keep. One already on this record's lines stays (unless it went to Trash, which
-- drops it quietly so a form opened before the delete still saves). A new one must be an image uploaded from
-- this record, still being checked or checked, or a File already linked to it. Anything else is refused.
create or replace function private.line_photo_for_save(
  target_organization_id uuid,
  target_file_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  already_on_record uuid[],
  line_number integer
)
returns uuid
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  file_row public.files;
begin
  if target_file_id is null then
    return null;
  end if;

  select * into file_row
  from public.files file
  where file.organization_id = target_organization_id and file.id = target_file_id;

  if file_row.id is not null and file_row.trashed_at is not null then
    return null;
  end if;

  if target_file_id = any(already_on_record) and file_row.id is not null then
    return file_row.id;
  end if;

  if file_row.id is null
     or file_row.processing_state not in ('pending', 'available')
     or file_row.mime_type not like 'image/%'
     or not (
       (file_row.origin_type = target_entity_type and file_row.origin_id = target_entity_id)
       or exists (
         select 1 from public.file_links link
         where link.organization_id = target_organization_id
           and link.file_id = target_file_id
           and link.entity_type = target_entity_type
           and link.entity_id = target_entity_id
       )
     ) then
    raise exception 'Line % points at a photo that was not uploaded for this record.', line_number
      using errcode = 'check_violation';
  end if;

  return file_row.id;
end;
$$;

-- A quote link is protected while any version of that quote, draft or published, still carries the File as a
-- customer file or a line photo. Protection no longer blocks Trash; it keeps the link (and so Restore) alive,
-- and stops the File being quietly taken off the quote from its Files card.
create or replace function private.refresh_quote_file_protection(target_organization_id uuid, target_quote_id uuid)
returns void
language sql
set search_path = pg_catalog, public
as $$
  update public.file_links link
  set protected = exists (
      select 1 from public.quote_version_attachments version_attachment
      where version_attachment.organization_id = link.organization_id
        and version_attachment.quote_id = target_quote_id
        and version_attachment.file_id = link.file_id
    ) or exists (
      select 1 from public.quote_version_lines line
      where line.organization_id = link.organization_id
        and line.quote_id = target_quote_id
        and line.image_file_id = link.file_id
    )
  where link.organization_id = target_organization_id
    and link.entity_type = 'quote'
    and link.entity_id = target_quote_id;
$$;

-- Brings one record's 'line_photo' links in line with its lines: checked photos get a link, photos no line
-- uses any more lose theirs. A still-pending upload gets its link from the processing worker instead.
create or replace function private.sync_line_photo_links(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
  select target_organization_id, file.id, target_entity_type, target_entity_id, 'line_photo', (select auth.uid())
  from private.line_photo_file_ids(target_organization_id, target_entity_type, target_entity_id) as used(file_id)
  join public.files file on file.organization_id = target_organization_id and file.id = used.file_id
  where file.trashed_at is null and file.processing_state = 'available'
  on conflict (file_id, entity_type, entity_id, role) do nothing;

  if target_entity_type = 'quote' then
    perform private.refresh_quote_file_protection(target_organization_id, target_entity_id);
  end if;

  delete from public.file_links link
  where link.organization_id = target_organization_id
    and link.entity_type = target_entity_type
    and link.entity_id = target_entity_id
    and link.role = 'line_photo'
    and not link.protected
    and link.file_id not in (
      select used.file_id
      from private.line_photo_file_ids(target_organization_id, target_entity_type, target_entity_id) as used(file_id)
    );
end;
$$;

revoke all on function private.line_photo_file_ids(uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.live_line_photo(uuid, uuid) from public, anon, authenticated;
revoke all on function private.line_photo_for_save(uuid, uuid, text, uuid, uuid[], integer) from public, anon, authenticated;
revoke all on function private.refresh_quote_file_protection(uuid, uuid) from public, anon, authenticated;
revoke all on function private.sync_line_photo_links(uuid, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Existing photos get their links. Part 5 had filed each one as an ordinary 'attachment' on the record it
--    was uploaded from; none of them is a quote customer file, so each becomes that record's line photo.
--    Records that inherited a photo (a quote from its request, a job from its quote) get their own link.
-- ---------------------------------------------------------------------------------------------------------

update public.file_links link
set role = 'line_photo'
where link.role = 'attachment'
  and link.entity_type in ('request', 'quote', 'job')
  and link.file_id in (
    select used.file_id
    from private.line_photo_file_ids(link.organization_id, link.entity_type, link.entity_id) as used(file_id)
  )
  and not exists (
    select 1 from public.quote_version_attachments version_attachment
    where version_attachment.organization_id = link.organization_id
      and version_attachment.file_id = link.file_id
      and link.entity_type = 'quote'
      and version_attachment.quote_id = link.entity_id
  );

do $$
declare
  record_row record;
begin
  for record_row in
    select distinct organization_id, 'request' as entity_type, request_id as entity_id
    from public.request_pricing_lines where image_file_id is not null
    union
    select distinct organization_id, 'quote', quote_id from public.quote_version_lines where image_file_id is not null
    union
    select distinct organization_id, 'job', job_id from public.job_line_items where image_file_id is not null
    union
    select distinct organization_id, 'job', job_id from public.job_visit_line_items where image_file_id is not null
  loop
    perform private.sync_line_photo_links(record_row.organization_id, record_row.entity_type, record_row.entity_id);
  end loop;
end;
$$;


-- 5a. replace_request_pricing_lines
CREATE OR REPLACE FUNCTION "public"."replace_request_pricing_lines"("target_request_id" "uuid", "expected_revision" integer, "new_lines" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  previous_photo_ids uuid[];
  request_row public.requests;
  line jsonb;
  line_index integer := 0;
  clean_quantity numeric;
  clean_price bigint;
  clean_cost bigint;
  clean_category text;
  clean_name text;
  clean_catalog_item_id uuid;
  clean_image_file_id uuid;
  new_revision integer;
  new_subtotal bigint;
  new_count integer;
begin
  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'Pricing must be sent as a list of lines.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_lines) > 200 then
    raise exception 'A request can hold up to 200 pricing lines.' using errcode = 'program_limit_exceeded';
  end if;

  select * into request_row from public.requests where id = target_request_id for update;

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way. Now the
  -- same decision the parent Request's own RLS makes, not plain membership.
  if request_row.id is null
     or not private.can_view_request(request_row.organization_id, target_request_id) then
    raise exception 'You do not have access to price this request.' using errcode = 'insufficient_privilege';
  end if;

  if request_row.status in ('converted', 'archived') then
    raise exception 'This request is closed and its pricing cannot be changed.'
      using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from request_row.pricing_revision then
    raise exception 'Someone else changed this pricing while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  previous_photo_ids := array(select private.line_photo_file_ids(request_row.organization_id, 'request', target_request_id));

  delete from public.request_pricing_lines
  where organization_id = request_row.organization_id
    and request_id = target_request_id;

  for line in select * from jsonb_array_elements(new_lines)
  loop
    clean_name := nullif(trim(coalesce(line ->> 'name', '')), '');
    clean_category := coalesce(line ->> 'category', 'service');
    clean_quantity := coalesce((line ->> 'quantity')::numeric, 0);
    clean_price := coalesce((line ->> 'unit_price_minor')::bigint, 0);
    clean_cost := coalesce((line ->> 'unit_cost_minor')::bigint, 0);
    clean_catalog_item_id := nullif(line ->> 'catalog_item_id', '')::uuid;
    clean_image_file_id := nullif(line ->> 'image_file_id', '')::uuid;

    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
      raise exception 'Line % needs a name between 2 and 160 characters.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_category not in ('product', 'service') then
      raise exception 'Line % must be a product or a service.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_quantity <= 0 or clean_quantity > 1000000 then
      raise exception 'Line % needs a quantity above zero.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_price < 0 or clean_price > 1000000000000 or clean_cost < 0 or clean_cost > 1000000000000 then
      raise exception 'Line % has a price or cost outside the allowed range.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- An archived item is still readable, because old lines reference it, but it cannot start a new one.
    if clean_catalog_item_id is not null and not exists (
      select 1 from public.catalog_items
      where id = clean_catalog_item_id
        and organization_id = request_row.organization_id
        and archived_at is null
    ) then
      raise exception 'Line % points at a price list item that is no longer available.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- A line may keep a photo it already had, or claim one uploaded from, or linked to, this request.
    -- One deleted since the editor loaded is dropped rather than refused, so a stale form still saves.
    clean_image_file_id := private.line_photo_for_save(
      request_row.organization_id, clean_image_file_id, 'request', target_request_id, previous_photo_ids,
      line_index + 1
    );

    insert into public.request_pricing_lines (
      organization_id, request_id, position, catalog_item_id, category, is_labor,
      name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
      image_file_id
    ) values (
      request_row.organization_id,
      target_request_id,
      line_index,
      clean_catalog_item_id,
      clean_category,
      coalesce((line ->> 'is_labor')::boolean, false),
      clean_name,
      nullif(trim(coalesce(line ->> 'description', '')), ''),
      nullif(trim(coalesce(line ->> 'unit_label', '')), ''),
      clean_quantity,
      clean_price,
      clean_cost,
      coalesce((line ->> 'is_taxable')::boolean, true),
      clean_image_file_id
    );

    line_index := line_index + 1;
  end loop;

  perform private.sync_line_photo_links(request_row.organization_id, 'request', target_request_id);

  select coalesce(sum(line_total_minor), 0), count(*)
  into new_subtotal, new_count
  from public.request_pricing_lines
  where organization_id = request_row.organization_id
    and request_id = target_request_id;

  update public.requests
  set pricing_revision = pricing_revision + 1,
      pricing_subtotal_minor = new_subtotal
  where id = target_request_id
  returning pricing_revision into new_revision;

  return jsonb_build_object(
    'revision', new_revision,
    'line_count', new_count,
    'subtotal_minor', new_subtotal
  );
end;
$$;

-- 5b. replace_quote_version_lines
CREATE OR REPLACE FUNCTION "public"."replace_quote_version_lines"("target_quote_id" "uuid", "expected_revision" integer, "new_lines" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  previous_photo_ids uuid[];
  draft_row public.quote_versions;
  line jsonb;
  line_index integer := 0;
  clean_kind text;
  clean_selection text;
  clean_recommended boolean;
  clean_quantity numeric;
  clean_price bigint;
  clean_cost bigint;
  clean_category text;
  clean_name text;
  clean_catalog_item_id uuid;
  clean_image_file_id uuid;
  new_count integer;
  result jsonb;
begin
  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'Lines must be sent as a list.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_lines) > 200 then
    raise exception 'A quote can hold up to 200 lines.' using errcode = 'program_limit_exceeded';
  end if;

  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  -- Every version's photos, the draft's included, so a revision keeps what it carried forward.
  previous_photo_ids := array(select private.line_photo_file_ids(draft_row.organization_id, 'quote', target_quote_id));

  delete from public.quote_version_lines
  where organization_id = draft_row.organization_id
    and quote_id = draft_row.quote_id
    and quote_version_id = draft_row.id;

  for line in select * from jsonb_array_elements(new_lines)
  loop
    clean_name := nullif(trim(coalesce(line ->> 'name', '')), '');
    clean_kind := coalesce(nullif(line ->> 'line_kind', ''), 'priced');
    clean_selection := coalesce(nullif(line ->> 'selection_kind', ''), 'required');
    clean_recommended := coalesce((line ->> 'is_recommended')::boolean, false);

    if clean_kind not in ('priced', 'text', 'heading') then
      raise exception 'Line % is not a kind of line this quote understands.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_name is null or char_length(clean_name) < 2 or char_length(clean_name) > 160 then
      raise exception 'Line % needs a name between 2 and 160 characters.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_kind <> 'priced' then
      insert into public.quote_version_lines (
        organization_id, quote_id, quote_version_id, position, name, description, is_taxable,
        line_kind, selection_kind
      ) values (
        draft_row.organization_id, draft_row.quote_id, draft_row.id, line_index, clean_name,
        nullif(trim(coalesce(line ->> 'description', '')), ''), false, clean_kind, 'required'
      );
      line_index := line_index + 1;
      continue;
    end if;

    clean_category := coalesce(line ->> 'category', 'service');
    clean_quantity := coalesce((line ->> 'quantity')::numeric, 0);
    clean_price := coalesce((line ->> 'unit_price_minor')::bigint, 0);
    clean_cost := coalesce((line ->> 'unit_cost_minor')::bigint, 0);
    clean_catalog_item_id := nullif(line ->> 'catalog_item_id', '')::uuid;
    clean_image_file_id := nullif(line ->> 'image_file_id', '')::uuid;

    if clean_category not in ('product', 'service') then
      raise exception 'Line % must be a product or a service.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_quantity <= 0 or clean_quantity > 1000000 then
      raise exception 'Line % needs a quantity above zero.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_price < 0 or clean_price > 1000000000000 or clean_cost < 0 or clean_cost > 1000000000000 then
      raise exception 'Line % has a price or cost outside the allowed range.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_selection not in ('required', 'optional') then
      raise exception 'Line % must be required work or an add-on.', line_index + 1
        using errcode = 'check_violation';
    end if;
    if clean_recommended and clean_selection <> 'optional' then
      raise exception 'Line % cannot be marked as recommended.', line_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_catalog_item_id is not null and not exists (
      select 1 from public.catalog_items
      where id = clean_catalog_item_id
        and organization_id = draft_row.organization_id
        and archived_at is null
    ) then
      raise exception 'Line % points at a price list item that is no longer available.', line_index + 1
        using errcode = 'check_violation';
    end if;

    -- A photo already on any version of this quote, or one uploaded from, or linked to, this quote. One
    -- deleted since the editor loaded is dropped rather than refused.
    clean_image_file_id := private.line_photo_for_save(
      draft_row.organization_id, clean_image_file_id, 'quote', target_quote_id, previous_photo_ids,
      line_index + 1
    );

    insert into public.quote_version_lines (
      organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
      name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
      image_file_id, line_kind, selection_kind, is_recommended
    ) values (
      draft_row.organization_id,
      draft_row.quote_id,
      draft_row.id,
      line_index,
      clean_catalog_item_id,
      clean_category,
      coalesce((line ->> 'is_labor')::boolean, false),
      clean_name,
      nullif(trim(coalesce(line ->> 'description', '')), ''),
      nullif(trim(coalesce(line ->> 'unit_label', '')), ''),
      clean_quantity,
      clean_price,
      clean_cost,
      coalesce((line ->> 'is_taxable')::boolean, true),
      clean_image_file_id,
      'priced',
      clean_selection,
      clean_recommended
    );

    line_index := line_index + 1;
  end loop;

  perform private.sync_line_photo_links(draft_row.organization_id, 'quote', draft_row.quote_id);

  select count(*) into new_count
  from public.quote_version_lines
  where organization_id = draft_row.organization_id
    and quote_id = draft_row.quote_id
    and quote_version_id = draft_row.id;

  result := private.bump_quote_draft(draft_row.id);

  return result || jsonb_build_object(
    'line_count', new_count,
    'subtotal_minor', (result -> 'totals' ->> 'subtotal_minor')::bigint
  );
end;
$$;

-- 5c. replace_job_line_items
CREATE OR REPLACE FUNCTION "public"."replace_job_line_items"("target_organization_id" "uuid", "target_job_id" "uuid", "expected_revision" integer, "new_lines" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  previous_photo_ids uuid[];
  caller uuid := (select auth.uid());
  current_job public.jobs;
  line_count integer;
begin
  current_job := private.lock_job_for_edit(target_organization_id, target_job_id, expected_revision);

  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'The job scope must be a list of lines.' using errcode = 'check_violation';
  end if;

  previous_photo_ids := array(select private.line_photo_file_ids(target_organization_id, 'job', target_job_id));

  delete from public.job_line_items
  where organization_id = target_organization_id
    and job_id = target_job_id;

  insert into public.job_line_items (
    organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_file_id
  )
  select
    target_organization_id,
    target_job_id,
    (row_number() over (order by (line.value->>'position')::integer, ordinality) - 1)::integer,
    nullif(line.value->>'source_catalog_item_id', '')::uuid,
    coalesce(line.value->>'line_kind', 'priced'),
    nullif(line.value->>'category', ''),
    coalesce((line.value->>'is_labor')::boolean, false),
    line.value->>'name',
    nullif(line.value->>'description', ''),
    nullif(line.value->>'unit_label', ''),
    (line.value->>'quantity')::numeric,
    (line.value->>'unit_price_minor')::bigint,
    (line.value->>'unit_cost_minor')::bigint,
    coalesce((line.value->>'is_taxable')::boolean, true),
    private.line_photo_for_save(
      target_organization_id, nullif(line.value->>'image_file_id', '')::uuid, 'job', target_job_id,
      previous_photo_ids, line.ordinality::integer
    )
  from jsonb_array_elements(new_lines) with ordinality as line(value, ordinality);

  get diagnostics line_count = row_count;

  perform private.sync_line_photo_links(target_organization_id, 'job', target_job_id);

  perform private.store_job_money(target_job_id);

  update public.jobs
  set revision = current_job.revision + 1
  where organization_id = target_organization_id
    and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'scope_updated',
    caller,
    jsonb_build_object('line_count', line_count)
  );

  return jsonb_build_object('revision', current_job.revision + 1, 'line_count', line_count);
end;
$$;

-- 5d. replace_job_visit_line_items
CREATE OR REPLACE FUNCTION "public"."replace_job_visit_line_items"("target_organization_id" "uuid", "target_job_id" "uuid", "target_visit_id" "uuid", "expected_revision" integer, "new_lines" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  previous_photo_ids uuid[];
  caller uuid := (select auth.uid());
  current_job public.jobs;
  current_visit public.job_visits;
  line_count integer := 0;
begin
  if caller is null then
    raise exception 'You must be signed in to price a visit.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.edit') then
    raise exception 'You do not have access to edit this job.' using errcode = 'insufficient_privilege';
  end if;

  if new_lines is null or jsonb_typeof(new_lines) <> 'array' then
    raise exception 'A visit''s pricing must be a list of lines.' using errcode = 'check_violation';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  if current_job.status <> 'active' then
    raise exception 'A closed job''s visits cannot be repriced.' using errcode = 'P0410';
  end if;

  if current_job.price_basis is distinct from 'per_visit' then
    raise exception 'Only a job billed per visit can price its visits separately.'
      using errcode = 'check_violation',
      hint = 'Change the job''s billing to per visit first.';
  end if;

  select visit.* into current_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = target_visit_id
  for update;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;

  if current_visit.completed_at is not null then
    raise exception 'A completed visit''s pricing cannot be changed.' using errcode = 'P0410',
      hint = 'Reopen the visit first if the work was different from what was recorded.';
  end if;

  if exists (
    select 1
    from public.invoice_sources as claim
    where claim.organization_id = target_organization_id
      and claim.visit_id = target_visit_id
      and claim.source_kind = 'visit'
  ) then
    raise exception 'An invoiced visit''s pricing cannot be changed.' using errcode = 'P0410';
  end if;

  if current_visit.revision is distinct from expected_revision then
    raise exception 'Someone else changed this visit. Reload to see the latest.' using errcode = 'P0409';
  end if;

  previous_photo_ids := array(select private.line_photo_file_ids(target_organization_id, 'job', target_job_id));

  delete from public.job_visit_line_items
  where organization_id = target_organization_id
    and visit_id = target_visit_id;

  insert into public.job_visit_line_items (
    organization_id, job_id, visit_id, position, source_job_line_item_id, source_catalog_item_id,
    line_kind, category, is_labor, name, description, unit_label, quantity, unit_price_minor,
    unit_cost_minor, is_taxable, image_file_id
  )
  select
    target_organization_id,
    target_job_id,
    target_visit_id,
    (numbered.rank - 1)::integer,
    case when numbered.source_rank = 1 then numbered.source_job_line_item_id end,
    numbered.source_catalog_item_id,
    numbered.line_kind,
    numbered.category,
    numbered.is_labor,
    numbered.name,
    numbered.description,
    numbered.unit_label,
    numbered.quantity,
    numbered.unit_price_minor,
    numbered.unit_cost_minor,
    numbered.is_taxable,
    numbered.image_file_id
  from (
    select
      row_number() over (order by (line.value->>'position')::integer, line.ordinality) as rank,
      nullif(line.value->>'source_job_line_item_id', '')::uuid as source_job_line_item_id,
      row_number() over (
        partition by nullif(line.value->>'source_job_line_item_id', '')::uuid
        order by (line.value->>'position')::integer, line.ordinality
      ) as source_rank,
      nullif(line.value->>'source_catalog_item_id', '')::uuid as source_catalog_item_id,
      coalesce(line.value->>'line_kind', 'priced') as line_kind,
      nullif(line.value->>'category', '') as category,
      coalesce((line.value->>'is_labor')::boolean, false) as is_labor,
      line.value->>'name' as name,
      nullif(line.value->>'description', '') as description,
      nullif(line.value->>'unit_label', '') as unit_label,
      (line.value->>'quantity')::numeric as quantity,
      (line.value->>'unit_price_minor')::bigint as unit_price_minor,
      (line.value->>'unit_cost_minor')::bigint as unit_cost_minor,
      coalesce((line.value->>'is_taxable')::boolean, true) as is_taxable,
      private.line_photo_for_save(
        target_organization_id, nullif(line.value->>'image_file_id', '')::uuid, 'job', target_job_id,
        previous_photo_ids, line.ordinality::integer
      ) as image_file_id
    from jsonb_array_elements(new_lines) with ordinality as line(value, ordinality)
  ) as numbered;

  get diagnostics line_count = row_count;

  perform private.sync_line_photo_links(target_organization_id, 'job', target_job_id);

  if exists (
    select 1
    from public.job_visit_line_items as item
    join public.job_line_items as source
      on source.organization_id = item.organization_id
     and source.id = item.source_job_line_item_id
    where item.organization_id = target_organization_id
      and item.visit_id = target_visit_id
      and source.job_id <> target_job_id
  ) then
    raise exception 'A visit can only change lines that belong to its own job.' using errcode = 'check_violation';
  end if;

  update public.job_visits
  set revision = current_visit.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id
    and id = target_visit_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visit_updated',
    caller,
    target_visit_id,
    jsonb_build_object(
      'changed', to_jsonb(array['pricing']),
      'line_count', line_count,
      'has_override', line_count > 0
    )
  );

  return jsonb_build_object(
    'revision', current_visit.revision + 1,
    'line_count', line_count,
    'has_override', line_count > 0
  );
end;
$$;

-- 6a. convert_request_to_quote
CREATE OR REPLACE FUNCTION "public"."convert_request_to_quote"("target_request_id" "uuid", "idempotency_key" "text", "request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  request_row public.requests;
  source_opportunity public.opportunities;
  existing_quote public.quotes;
  new_quote public.quotes;
  new_version public.quote_versions;
  new_opportunity_id uuid;
  allocated_number integer;
  organization_currency text;
  organization_name text;
  client_name text;
  property_row public.properties;
  copied_count integer;
  copied_subtotal bigint;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- Lock order matches the outcome engine: the pipeline card first, then its request. Two commands racing
  -- on the same work therefore queue up instead of deadlocking against each other.
  select * into source_opportunity
  from public.opportunities
  where request_id = target_request_id
  for update;

  select * into request_row
  from public.requests
  where id = target_request_id
  for update;

  -- One answer for "no such request" and "not your request": a stranger learns nothing either way.
  if request_row.id is null
     or not private.member_has_permission(
       request_row.organization_id, (select auth.uid()), 'quotes.create'
     ) then
    raise exception 'You do not have access to create a quote from this request.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotency is checked before state. A retry that arrives after the first call already succeeded must
  -- be recognised as the same command, not rejected as "already converted".
  select * into existing_quote
  from public.quotes
  where organization_id = request_row.organization_id
    and request_id = target_request_id
  for update;

  if found then
    if existing_quote.conversion_idempotency_key is not distinct from idempotency_key
       and existing_quote.conversion_request_hash is not distinct from request_hash then
      return jsonb_build_object(
        'applied', false,
        'quote_id', existing_quote.id,
        'quote_number', existing_quote.quote_number,
        'quote_version_id', existing_quote.draft_version_id,
        'status', existing_quote.status
      );
    end if;

    raise exception 'This request already has a quote.' using errcode = 'P0409';
  end if;

  -- A finished assessment is still convertible: in Jobber that is exactly the moment the office is meant
  -- to price the work. Completed, converted, and archived requests are not live work any more.
  if request_row.status not in ('new', 'unscheduled', 'assessment_completed') then
    raise exception 'This request cannot be turned into a quote right now.' using errcode = 'check_violation';
  end if;

  select settings.currency_code into organization_currency
  from public.organization_settings as settings
  where settings.organization_id = request_row.organization_id;

  select organization.name into organization_name
  from public.organizations as organization
  where organization.id = request_row.organization_id;

  select client.display_name into client_name
  from public.clients as client
  where client.id = request_row.client_id;

  select * into property_row
  from public.properties
  where id = request_row.property_id;

  allocated_number := private.allocate_quote_number(request_row.organization_id);

  insert into public.quotes (
    organization_id, client_id, property_id, request_id, quote_number, title, currency_code,
    conversion_idempotency_key, conversion_request_hash, created_by
  ) values (
    request_row.organization_id,
    request_row.client_id,
    request_row.property_id,
    target_request_id,
    allocated_number,
    request_row.title,
    coalesce(organization_currency, 'USD'),
    idempotency_key,
    request_hash,
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code,
    client_display_name, organization_name,
    service_address_line1, service_address_line2, service_city,
    service_state_region, service_postal_code, service_country,
    created_by
  ) values (
    new_quote.organization_id,
    new_quote.id,
    1,
    'draft',
    new_quote.currency_code,
    client_name,
    organization_name,
    property_row.address_line1,
    property_row.address_line2,
    property_row.city,
    property_row.state_region,
    property_row.postal_code,
    property_row.country,
    (select auth.uid())
  )
  returning * into new_version;

  -- The copy is what makes the quote its own document. From here the catalog and the request can change
  -- as much as anyone likes and these numbers do not move.
  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_file_id
  )
  select
    line.organization_id, new_quote.id, new_version.id, line.position, line.catalog_item_id,
    line.category, line.is_labor, line.name, line.description, line.unit_label,
    line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_file_id
  from public.request_pricing_lines as line
  where line.organization_id = request_row.organization_id
    and line.request_id = target_request_id;

  select coalesce(sum(line.line_total_minor), 0), count(*)
  into copied_subtotal, copied_count
  from public.quote_version_lines as line
  where line.organization_id = new_quote.organization_id
    and line.quote_id = new_quote.id
    and line.quote_version_id = new_version.id;

  perform private.sync_line_photo_links(new_quote.organization_id, 'quote', new_quote.id);

  update public.quote_versions set subtotal_minor = copied_subtotal where id = new_version.id;
  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- The quote gets its own card. The stage trigger parks it off the board.
  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title)
  returning id into new_opportunity_id;

  -- Only work still to be done follows the quote. A task somebody already finished belongs to the request
  -- as history and stays where it happened. No limit check is needed: the new card starts empty and the
  -- old one already respected the five-open cap.
  if source_opportunity.id is not null then
    update public.tasks
    set opportunity_id = new_opportunity_id
    where organization_id = new_quote.organization_id
      and opportunity_id = source_opportunity.id
      and status = 'open';
  end if;

  -- This one update is also what takes the original request card off the board: the Part 1 resync trigger
  -- recomputes its stage from the new status without any extra code here.
  update public.requests set status = 'converted' where id = target_request_id;

  return jsonb_build_object(
    'applied', true,
    'quote_id', new_quote.id,
    'quote_number', new_quote.quote_number,
    'quote_version_id', new_version.id,
    'status', new_quote.status,
    'line_count', copied_count,
    'subtotal_minor', copied_subtotal
  );
end;
$$;

-- 6b. clone_quote_version_to_draft
CREATE OR REPLACE FUNCTION "public"."clone_quote_version_to_draft"("target_quote_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  quote_row public.quotes;
  source_row public.quote_versions;
  new_draft public.quote_versions;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to revise this quote.' using errcode = 'insufficient_privilege';
  end if;
  if quote_row.draft_version_id is not null then
    raise exception 'This quote already has a draft.' using errcode = 'P0409';
  end if;
  select * into source_row from public.quote_versions
  where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
  for share;
  if source_row.id is null or source_row.status <> 'published' then
    raise exception 'This quote has no published version to revise.' using errcode = 'check_violation';
  end if;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code, client_display_name,
    organization_name, logo_object_key, brand_color, service_address_line1, service_address_line2,
    service_city, service_state_region, service_postal_code, service_country, subtotal_minor, created_by,
    revision, contract_disclaimer, introduction, client_message, show_quantities, show_unit_prices,
    show_line_totals, show_totals, discount_name, discount_type, discount_value, tax_name,
    tax_rate_basis_points, tax_source, tax_rate_id, deposit_type, representative_enabled, representative_name, representative_title,
    representative_signature_object_key, require_customer_signature
  ) values (
    source_row.organization_id, source_row.quote_id, 0, 'draft', source_row.currency_code,
    source_row.client_display_name, source_row.organization_name, source_row.logo_object_key,
    source_row.brand_color, source_row.service_address_line1,
    source_row.service_address_line2, source_row.service_city, source_row.service_state_region,
    source_row.service_postal_code, source_row.service_country, source_row.subtotal_minor,
    (select auth.uid()), 1, source_row.contract_disclaimer, source_row.introduction,
    source_row.client_message, source_row.show_quantities, source_row.show_unit_prices,
    source_row.show_line_totals, source_row.show_totals, source_row.discount_name,
    source_row.discount_type, source_row.discount_value, source_row.tax_name, source_row.tax_rate_basis_points,
    source_row.tax_source, source_row.tax_rate_id, source_row.deposit_type,
    source_row.representative_enabled, source_row.representative_name, source_row.representative_title,
    source_row.representative_signature_object_key, source_row.require_customer_signature
  ) returning * into new_draft;

  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_file_id, line_kind, selection_kind, is_recommended
  ) select line.organization_id, line.quote_id, new_draft.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    private.live_line_photo(line.organization_id, line.image_file_id), line.line_kind, line.selection_kind, line.is_recommended
  from public.quote_version_lines line
  where line.quote_version_id = source_row.id order by line.position, line.id;

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, file_id, position, customer_visible, display_name
  ) select organization_id, quote_id, new_draft.id, file_id, position, customer_visible, display_name
  from public.quote_version_attachments where quote_version_id = source_row.id order by position, id;

  insert into public.quote_version_schedule_items (
    organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
  ) select item.organization_id, item.quote_id, new_draft.id, item.position, item.description,
    item.value_type, item.value, item.is_deposit
  from public.quote_version_schedule_items item
  where item.quote_version_id = source_row.id order by item.position, item.id;

  perform private.refresh_quote_draft_totals(new_draft.id);

  update public.quotes set draft_version_id = new_draft.id where id = quote_row.id;
  return jsonb_build_object('quote_id', quote_row.id, 'quote_version_id', new_draft.id, 'revision', 1);
end;
$$;

-- 6c. create_similar_quote
CREATE OR REPLACE FUNCTION "public"."create_similar_quote"("target_quote_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  source_quote public.quotes;
  source_version public.quote_versions;
  organization_display_name text;
  allocated_number integer;
  new_quote public.quotes;
  new_version public.quote_versions;
begin
  select * into source_quote from public.quotes where id = target_quote_id;
  if source_quote.id is null or not private.member_has_permission(
    source_quote.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to copy this quote.' using errcode = 'insufficient_privilege';
  end if;

  select * into source_version from public.quote_versions
  where organization_id = source_quote.organization_id
    and id = coalesce(source_quote.draft_version_id, source_quote.current_published_version_id);
  if source_version.id is null then
    raise exception 'This quote has no version to copy.' using errcode = 'check_violation';
  end if;

  select organization.name into organization_display_name
  from public.organizations as organization
  where organization.id = source_quote.organization_id;

  allocated_number := private.allocate_quote_number(source_quote.organization_id);

  insert into public.quotes (
    organization_id, client_id, property_id, quote_number, title, currency_code, created_by
  ) values (
    source_quote.organization_id,
    source_quote.client_id,
    source_quote.property_id,
    allocated_number,
    left(source_quote.title || ' (copy)', 160),
    source_quote.currency_code,
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code, client_display_name,
    organization_name, service_address_line1, service_address_line2, service_city, service_state_region,
    service_postal_code, service_country, subtotal_minor, created_by, revision, contract_disclaimer,
    introduction, client_message, show_quantities, show_unit_prices, show_line_totals, show_totals,
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points, tax_source, tax_rate_id,
    deposit_type
  ) values (
    new_quote.organization_id, new_quote.id, 1, 'draft', source_version.currency_code,
    source_version.client_display_name, coalesce(organization_display_name, source_version.organization_name),
    source_version.service_address_line1, source_version.service_address_line2, source_version.service_city,
    source_version.service_state_region, source_version.service_postal_code, source_version.service_country,
    source_version.subtotal_minor, (select auth.uid()), 1, source_version.contract_disclaimer,
    source_version.introduction, source_version.client_message, source_version.show_quantities,
    source_version.show_unit_prices, source_version.show_line_totals, source_version.show_totals,
    source_version.discount_name, source_version.discount_type, source_version.discount_value,
    source_version.tax_name, source_version.tax_rate_basis_points, source_version.tax_source,
    source_version.tax_rate_id, source_version.deposit_type
  )
  returning * into new_version;

  insert into public.quote_version_lines (
    organization_id, quote_id, quote_version_id, position, source_catalog_item_id, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_file_id, line_kind, selection_kind, is_recommended
  )
  select line.organization_id, new_quote.id, new_version.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    private.live_line_photo(line.organization_id, line.image_file_id), line.line_kind, line.selection_kind, line.is_recommended
  from public.quote_version_lines line
  where line.organization_id = source_version.organization_id
    and line.quote_id = source_version.quote_id
    and line.quote_version_id = source_version.id
  order by line.position, line.id;

  insert into public.quote_version_schedule_items (
    organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
  )
  select item.organization_id, new_quote.id, new_version.id, item.position, item.description,
    item.value_type, item.value, item.is_deposit
  from public.quote_version_schedule_items item
  where item.organization_id = source_version.organization_id
    and item.quote_id = source_version.quote_id
    and item.quote_version_id = source_version.id
  order by item.position, item.id;

  perform public.attach_file_to_record(att.organization_id, att.file_id, (select auth.uid()), 'quote', new_quote.id)
  from public.quote_version_attachments att
  where att.organization_id = source_version.organization_id
    and att.quote_id = source_version.quote_id
    and att.quote_version_id = source_version.id;

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, file_id, position, customer_visible, display_name
  )
  select att.organization_id, new_quote.id, new_version.id, att.file_id, att.position,
    att.customer_visible, att.display_name
  from public.quote_version_attachments att
  where att.organization_id = source_version.organization_id
    and att.quote_id = source_version.quote_id
    and att.quote_version_id = source_version.id
  order by att.position, att.id;

  perform private.sync_line_photo_links(new_quote.organization_id, 'quote', new_quote.id);

  perform private.refresh_quote_draft_totals(new_version.id);

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (
    new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title
  );

  return jsonb_build_object('quote_id', new_quote.id, 'quote_number', new_quote.quote_number);
end;
$$;

-- 6d. convert_quote_to_job
CREATE OR REPLACE FUNCTION "public"."convert_quote_to_job"("target_quote_id" "uuid", "idempotency_key" "text", "request_hash" "text", "new_job_type" "text" DEFAULT 'one_off'::"text", "new_price_basis" "text" DEFAULT NULL::"text", "new_title" "text" DEFAULT NULL::"text", "new_billing_timing" "text" DEFAULT 'on_closure'::"text", "new_is_as_needed" boolean DEFAULT false, "new_instructions" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  existing_job public.jobs;
  created_job public.jobs;
  chosen_addons uuid[];
  resolved_basis text;
  resolved_title text;
  copied_count integer;
  copied_stage_count integer := 0;
  calculated jsonb;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(request_hash, ''))) < 1 then
    raise exception 'A quote fingerprint is required.' using errcode = 'check_violation';
  end if;
  if new_job_type not in ('one_off', 'recurring') then
    raise exception 'A job is either one-off or recurring.' using errcode = 'check_violation';
  end if;

  select * into quote_row from public.quotes where id = target_quote_id for update;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.convert'
     )
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'jobs.create'
     ) then
    raise exception 'You do not have access to turn this quote into a job.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into existing_job
  from public.jobs
  where organization_id = quote_row.organization_id
    and quote_id = target_quote_id
  for update;

  if found then
    if existing_job.conversion_idempotency_key is not distinct from idempotency_key
       and existing_job.conversion_request_hash is not distinct from request_hash then
      return jsonb_build_object(
        'applied', false,
        'job_id', existing_job.id,
        'job_number', existing_job.job_number,
        'quote_id', quote_row.id,
        'quote_status', quote_row.status
      );
    end if;

    raise exception 'This quote already has a job.' using errcode = 'P0409';
  end if;

  if quote_row.status <> 'approved' then
    raise exception 'Only an approved quote can become a job.' using errcode = 'check_violation';
  end if;

  if not public.quote_ready_for_job(target_quote_id) then
    raise exception 'This quote is not ready for a job yet.' using errcode = 'check_violation';
  end if;

  select * into version_row
  from public.quote_versions
  where organization_id = quote_row.organization_id
    and id = quote_row.current_published_version_id
  for update;

  if version_row.id is null then
    raise exception 'This quote has no approved version to copy.' using errcode = 'check_violation';
  end if;

  resolved_basis := coalesce(
    new_price_basis,
    case when new_job_type = 'one_off' then 'job_total' else 'per_visit' end
  );
  resolved_title := coalesce(nullif(trim(coalesce(new_title, '')), ''), quote_row.title);

  created_job := private.create_job(
    quote_row.organization_id,
    quote_row.client_id,
    quote_row.property_id,
    resolved_title,
    new_job_type,
    resolved_basis,
    quote_row.currency_code,
    (select auth.uid()),
    coalesce(new_is_as_needed, false),
    coalesce(new_billing_timing, 'on_closure'),
    new_instructions,
    quote_row.id,
    version_row.id,
    idempotency_key,
    request_hash
  );

  update public.jobs
  set discount_name = version_row.discount_name,
      discount_type = version_row.discount_type,
      discount_value = version_row.discount_value,
      tax_source = version_row.tax_source,
      tax_name = version_row.tax_name,
      tax_rate_basis_points = version_row.tax_rate_basis_points,
      tax_rate_id = version_row.tax_rate_id
  where id = created_job.id;

  select coalesce(array_agg((chosen.value #>> '{}')::uuid), '{}'::uuid[])
  into chosen_addons
  from jsonb_array_elements(
    case
      when jsonb_typeof(version_row.calculation->'selected_addon_ids') = 'array'
        then version_row.calculation->'selected_addon_ids'
      else '[]'::jsonb
    end
  ) as chosen(value);

  insert into public.job_line_items (
    organization_id, job_id, position, source_catalog_item_id, line_kind, category, is_labor,
    name, description, unit_label, quantity, unit_price_minor, unit_cost_minor, is_taxable,
    image_file_id
  )
  select
    created_job.organization_id,
    created_job.id,
    (row_number() over (order by line.position, line.id))::integer - 1,
    line.source_catalog_item_id,
    line.line_kind,
    line.category,
    line.is_labor,
    line.name,
    line.description,
    line.unit_label,
    line.quantity,
    line.unit_price_minor,
    line.unit_cost_minor,
    line.is_taxable,
    private.live_line_photo(line.organization_id, line.image_file_id)
  from public.quote_version_lines as line
  where line.organization_id = quote_row.organization_id
    and line.quote_id = quote_row.id
    and line.quote_version_id = version_row.id
    and (line.selection_kind = 'required' or line.id = any(chosen_addons));

  get diagnostics copied_count = row_count;

  perform private.sync_line_photo_links(created_job.organization_id, 'job', created_job.id);

  calculated := private.store_job_money(created_job.id);

  if (calculated->>'total_minor')::bigint is distinct from version_row.total_minor then
    raise exception 'The job total does not match the approved quote total.' using errcode = 'check_violation';
  end if;

  if version_row.deposit_type = 'schedule' and created_job.job_type = 'one_off' then
    insert into public.job_payment_schedule_items (
      organization_id, job_id, position, description, value_type, value, is_deposit
    )
    select
      created_job.organization_id,
      created_job.id,
      (row_number() over (order by item.position, item.id))::integer - 1,
      item.description,
      item.value_type,
      item.value,
      item.is_deposit
    from public.quote_version_schedule_items as item
    where item.organization_id = quote_row.organization_id
      and item.quote_id = quote_row.id
      and item.quote_version_id = version_row.id;

    get diagnostics copied_stage_count = row_count;

    perform private.price_job_payment_schedule(created_job.id);
  end if;

  update public.quotes set status = 'converted' where id = quote_row.id;

  insert into public.job_events (
    organization_id, job_id, event_type, actor_id, new_status, related_quote_id, metadata
  ) values (
    created_job.organization_id,
    created_job.id,
    'job_converted_from_quote',
    (select auth.uid()),
    'active',
    quote_row.id,
    jsonb_build_object(
      'quote_number', quote_row.quote_number,
      'quote_version_number', version_row.version_number,
      'line_count', copied_count,
      'payment_stage_count', copied_stage_count
    )
  );

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id, 'quote.converted',
    'Turned this quote into a job',
    (select auth.uid()),
    jsonb_build_object(
      'job_number', created_job.job_number,
      'version_number', version_row.version_number,
      'line_count', copied_count
    )
  );

  return jsonb_build_object(
    'applied', true,
    'job_id', created_job.id,
    'job_number', created_job.job_number,
    'job_type', created_job.job_type,
    'price_basis', created_job.price_basis,
    'line_count', copied_count,
    'payment_stage_count', copied_stage_count,
    'quote_id', quote_row.id,
    'quote_status', 'converted'
  );
end;
$$;

-- 6e. add_job_visits: rename only (it copies the job's own lines, whose photos are already linked to the job)
CREATE OR REPLACE FUNCTION "public"."add_job_visits"("target_organization_id" "uuid", "target_job_id" "uuid", "visits" "jsonb", "new_idempotency_key" "text", "new_request_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  visit_count integer;
  next_position integer;
  visit_element jsonb;
  new_visit public.job_visits;
  assignee_element jsonb;
  copy_source_id uuid;
  added_ids uuid[] := array[]::uuid[];
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  visit_count := coalesce(jsonb_array_length(visits), 0);
  if visit_count < 1 or visit_count > 20 then
    raise exception 'Between 1 and 20 visits can be added at once.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- The job must exist in this organization and still be open. A closed job is not scheduled against; it is
  -- reopened first, which is an explicit later action. Not found and forbidden read the same to a stranger.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    raise exception 'A closed job cannot be scheduled. Reopen it first.' using errcode = 'P0410';
  end if;

  -- Claim the key before any work. on conflict do nothing waits for a racing transaction to commit and then
  -- returns no row, so the loser reads the winner's committed result instead of adding a second batch.
  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'add_job_visits', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'add_job_visits'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'Those visits were already added with different details.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  -- New visits append after the job's current visits. position orders the job's own list, not the calendar.
  select coalesce(max(visit.position), -1) + 1 into next_position
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id;

  for visit_element in select value from jsonb_array_elements(visits) as v(value)
  loop
    insert into public.job_visits (
      organization_id, job_id, position, visit_date, start_time, end_time, all_day, title, instructions,
      source
    ) values (
      target_organization_id,
      target_job_id,
      next_position,
      nullif(visit_element->>'visit_date', '')::date,
      nullif(visit_element->>'start_time', '')::time,
      nullif(visit_element->>'end_time', '')::time,
      coalesce((visit_element->>'all_day')::boolean, false),
      nullif(trim(visit_element->>'title'), ''),
      nullif(trim(visit_element->>'instructions'), ''),
      coalesce(nullif(visit_element->>'source', ''), 'manual')
    )
    returning * into new_visit;

    next_position := next_position + 1;
    added_ids := array_append(added_ids, new_visit.id);

    if jsonb_typeof(visit_element->'assignee_ids') = 'array' then
      for assignee_element in select value from jsonb_array_elements(visit_element->'assignee_ids') as a(value)
      loop
        insert into public.job_visit_assignments (organization_id, visit_id, user_id)
        values (target_organization_id, new_visit.id, (assignee_element #>> '{}')::uuid)
        on conflict do nothing;
      end loop;
    end if;

    -- A faithful copy of the source visit's own lines, or nothing at all. A source that carries no lines of
    -- its own copies nothing, which is exactly right: the copy then bills the job's lines, as it did.
    copy_source_id := nullif(visit_element->>'copy_lines_from_visit_id', '')::uuid;
    if copy_source_id is not null then
      -- The source must be another visit of this same job in this same organization. Anything else is a
      -- mistake or a probe, and raising rolls the whole add back rather than quietly mispricing the copy.
      if not exists (
        select 1
        from public.job_visits as source
        where source.organization_id = target_organization_id
          and source.job_id = target_job_id
          and source.id = copy_source_id
      ) then
        raise exception 'The visit being copied could not be found.' using errcode = 'P0404';
      end if;

      -- source_job_line_item_id rides along: its uniqueness is scoped to one visit, so the copy's rows
      -- cannot collide with the original's, and the copy keeps the same once-per-visit override provenance.
      insert into public.job_visit_line_items (
        organization_id, job_id, visit_id, position, source_job_line_item_id, source_catalog_item_id,
        line_kind, category, is_labor, name, description, unit_label, quantity, unit_price_minor,
        unit_cost_minor, is_taxable, image_file_id
      )
      select
        target_organization_id, target_job_id, new_visit.id, item.position, item.source_job_line_item_id,
        item.source_catalog_item_id, item.line_kind, item.category, item.is_labor, item.name,
        item.description, item.unit_label, item.quantity, item.unit_price_minor,
        item.unit_cost_minor, item.is_taxable, item.image_file_id
      from public.job_visit_line_items as item
      where item.organization_id = target_organization_id
        and item.visit_id = copy_source_id
      order by item.position;
    end if;
  end loop;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visits_added',
    caller,
    jsonb_build_object('count', visit_count)
  );

  final_result := jsonb_build_object('applied', true, 'added_count', visit_count, 'visit_ids', to_jsonb(added_ids));
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

-- 7a. job_visit_effective_lines: the returned column is renamed, so the function is dropped and recreated.
drop function private.job_visit_effective_lines(uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION "private"."job_visit_effective_lines"("target_organization_id" "uuid", "target_job_id" "uuid", "target_visit_id" "uuid") RETURNS TABLE("id" "uuid", "is_override" boolean, "position" integer, "source_job_line_item_id" "uuid", "source_catalog_item_id" "uuid", "line_kind" "text", "category" "text", "is_labor" boolean, "name" "text", "description" "text", "unit_label" "text", "quantity" numeric, "unit_price_minor" bigint, "unit_cost_minor" bigint, "is_taxable" boolean, "image_file_id" "uuid", "line_total_minor" bigint)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  select
    item.id, true, item.position, item.source_job_line_item_id, item.source_catalog_item_id,
    item.line_kind, item.category, item.is_labor, item.name, item.description, item.unit_label,
    item.quantity, item.unit_price_minor, item.unit_cost_minor, item.is_taxable,
    item.image_file_id, item.line_total_minor
  from public.job_visit_line_items as item
  where item.organization_id = target_organization_id
    and item.visit_id = target_visit_id

  union all

  select
    line.id, false, line.position, line.id, line.source_catalog_item_id,
    line.line_kind, line.category, line.is_labor, line.name, line.description, line.unit_label,
    line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_file_id, line.line_total_minor
  from public.job_line_items as line
  where line.organization_id = target_organization_id
    and line.job_id = target_job_id
    and not exists (
      select 1
      from public.job_visit_line_items as override
      where override.organization_id = target_organization_id
        and override.visit_id = target_visit_id
    )

  order by 3, 1;
$$;

revoke all on function private.job_visit_effective_lines(uuid, uuid, uuid) from public;
comment on function private.job_visit_effective_lines(uuid, uuid, uuid) is
  'One visit''s effective lines: its own rows if it has any, otherwise the job''s. The single answer every reader, editor and biller uses, so none of them can price a visit differently from another.';

-- 7b. job_visit_lines: rename only
CREATE OR REPLACE FUNCTION "public"."job_visit_lines"("target_organization_id" "uuid", "target_job_id" "uuid", "target_visit_ids" "uuid"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  caller uuid := (select auth.uid());
  can_price boolean;
  can_cost boolean;
  wanted uuid[] := coalesce(target_visit_ids, '{}'::uuid[]);
  answer jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to view this job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  if cardinality(wanted) > 100 then
    raise exception 'Too many visits were asked for at once.' using errcode = '54000';
  end if;

  can_price := private.member_has_permission(target_organization_id, caller, 'jobs.view_price');
  can_cost := private.member_has_permission(target_organization_id, caller, 'jobs.view_cost');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'visit_id', visit.id,
        'visit_date', visit.visit_date,
        'completed', visit.completed_at is not null,
        'revision', visit.revision,
        'has_override', exists (
          select 1
          from public.job_visit_line_items as override
          where override.organization_id = target_organization_id
            and override.visit_id = visit.id
        ),
        'locked', visit.completed_at is not null or claimed.invoiced,
        'lock_reason', case
          when claimed.invoiced then 'invoiced'
          when visit.completed_at is not null then 'completed'
          else null
        end,
        'subtotal_minor', case when can_price then coalesce(effective.subtotal_minor, 0) else null end,
        'lines', coalesce(effective.lines, '[]'::jsonb)
      )
      order by visit.visit_date nulls last, visit.position, visit.id
    ),
    '[]'::jsonb
  ) into answer
  from public.job_visits as visit
  cross join lateral (
    select exists (
      select 1
      from public.invoice_sources as claim
      where claim.organization_id = target_organization_id
        and claim.visit_id = visit.id
        and claim.source_kind = 'visit'
    ) as invoiced
  ) as claimed
  cross join lateral (
    select
      sum(line.line_total_minor) filter (where line.line_kind = 'priced') as subtotal_minor,
      jsonb_agg(
        jsonb_build_object(
          'id', line.id,
          'is_override', line.is_override,
          'source_job_line_item_id', line.source_job_line_item_id,
          'catalog_item_id', line.source_catalog_item_id,
          'line_kind', line.line_kind,
          'category', line.category,
          'is_labor', line.is_labor,
          'name', line.name,
          'description', line.description,
          'unit_label', line.unit_label,
          'quantity', line.quantity,
          'is_taxable', line.is_taxable,
          'image_file_id', line.image_file_id
        )
        || (case when can_price then jsonb_build_object(
              'unit_price_minor', line.unit_price_minor,
              'line_total_minor', line.line_total_minor
            ) else '{}'::jsonb end)
        || (case when can_cost then jsonb_build_object(
              'unit_cost_minor', line.unit_cost_minor
            ) else '{}'::jsonb end)
        order by line.position, line.id
      ) as lines
    from private.job_visit_effective_lines(target_organization_id, target_job_id, visit.id) as line
  ) as effective
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = any(wanted);

  return jsonb_build_object('visits', answer);
end;
$$;

-- 7c. quote_customer_document: line photos and files deleted after sending show as removed
CREATE OR REPLACE FUNCTION "private"."quote_customer_document"("quote_row" "public"."quotes", "version_row" "public"."quote_versions", "recipient_name" "text", "recipient_email" "text", "include_money" boolean) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  select jsonb_build_object(
    'quote', jsonb_build_object(
      'quote_number', quote_row.quote_number,
      'status', quote_row.status,
      'sent_at', quote_row.sent_at,
      'decision', quote_row.decision,
      'decided_at', quote_row.decided_at
    ),
    'recipient', jsonb_build_object(
      'name', recipient_name,
      'email', recipient_email
    ),
    'business', jsonb_build_object(
      'name', version_row.organization_name,
      'brand_color', version_row.brand_color,
      'has_logo', version_row.logo_object_key is not null
    ),
    'document', jsonb_build_object(
      'version_number', version_row.version_number,
      'published_at', version_row.published_at,
      'currency_code', version_row.currency_code,
      'client_display_name', version_row.client_display_name,
      'service_address_line1', version_row.service_address_line1,
      'service_address_line2', version_row.service_address_line2,
      'service_city', version_row.service_city,
      'service_state_region', version_row.service_state_region,
      'service_postal_code', version_row.service_postal_code,
      'service_country', version_row.service_country,
      'introduction', version_row.introduction,
      'client_message', version_row.client_message,
      'contract_disclaimer', version_row.contract_disclaimer,
      'show_quantities', version_row.show_quantities,
      'show_unit_prices', version_row.show_unit_prices and include_money,
      'show_line_totals', version_row.show_line_totals and include_money,
      'show_totals', version_row.show_totals and include_money
    ),
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', line.id, 'position', line.position, 'line_kind', line.line_kind,
            'selection_kind', line.selection_kind,
            'is_recommended', line.is_recommended, 'category', line.category,
            'name', line.name, 'description', line.description, 'unit_label', line.unit_label,
            -- Only a checked, live photo is shown. One deleted after sending leaves a visible gap
            -- ("Photo removed") rather than silently changing what the customer received.
            'image_file_id', (
              select file.id from public.files file
              where file.organization_id = line.organization_id
                and file.id = line.image_file_id
                and file.trashed_at is null
                and file.processing_state = 'available'
            ),
            'image_removed', coalesce((
              select file.trashed_at is not null from public.files file
              where file.organization_id = line.organization_id
                and file.id = line.image_file_id
            ), false)
          )
          || case when version_row.show_quantities
               then jsonb_build_object('quantity', line.quantity) else '{}'::jsonb end
          || case when version_row.show_unit_prices and include_money
               then jsonb_build_object('unit_price_minor', line.unit_price_minor) else '{}'::jsonb end
          || case when version_row.show_line_totals and include_money
               then jsonb_build_object('line_total_minor', line.line_total_minor) else '{}'::jsonb end
          order by line.position, line.id
        )
        from public.quote_version_lines as line
        where line.organization_id = version_row.organization_id
          and line.quote_id = version_row.quote_id
          and line.quote_version_id = version_row.id
      ),
      '[]'::jsonb
    ),
    'attachments', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', case when file.trashed_at is null then version_attachment.file_id end,
            'name', case when file.trashed_at is null then version_attachment.display_name end,
            'mime_type', case when file.trashed_at is null then file.mime_type end,
            'size_bytes', case when file.trashed_at is null then file.size_bytes end,
            'removed', file.trashed_at is not null
          )
          order by version_attachment.position, version_attachment.id
        )
        from public.quote_version_attachments as version_attachment
        join public.files as file on file.id = version_attachment.file_id
        where version_attachment.organization_id = version_row.organization_id
          and version_attachment.quote_id = version_row.quote_id
          and version_attachment.quote_version_id = version_row.id
          and version_attachment.customer_visible
      ),
      '[]'::jsonb
    ),
    'totals', case when version_row.show_totals and include_money then jsonb_build_object(
      'subtotal_minor', version_row.subtotal_minor,
      'discount_name', version_row.discount_name,
      'discount_minor', version_row.discount_minor,
      'tax_name', version_row.tax_name,
      'tax_rate_basis_points', version_row.tax_rate_basis_points,
      'tax_minor', version_row.tax_minor,
      'total_minor', version_row.total_minor
    ) else null end,
    'deposit', case
      when include_money and version_row.deposit_type is not null and version_row.deposit_required_minor > 0
      then jsonb_build_object(
        'required_minor', version_row.deposit_required_minor,
        'satisfied', exists (
          select 1 from public.quote_deposit_events received
          where received.organization_id = version_row.organization_id
            and received.quote_id = version_row.quote_id
            and received.quote_version_id = version_row.id
            and received.event_type = 'received'
            and not exists (
              select 1 from public.quote_deposit_events reversal
              where reversal.organization_id = received.organization_id
                and reversal.reversed_event_id = received.id
            )
        )
      )
      else null
    end
  );
$$;

-- 7d. replace_quote_version_attachments: protection now also counts line photos
CREATE OR REPLACE FUNCTION "public"."replace_quote_version_attachments"("target_quote_id" "uuid", "expected_revision" integer, "new_attachments" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  draft_row public.quote_versions;
  attachment jsonb;
  attachment_index integer := 0;
  clean_file_id uuid;
  clean_display_name text;
  seen_ids uuid[] := '{}'::uuid[];
begin
  if new_attachments is null or jsonb_typeof(new_attachments) <> 'array' then
    raise exception 'Files must be sent as a list.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(new_attachments) > 50 then
    raise exception 'A quote can show up to 50 files.' using errcode = 'check_violation';
  end if;

  draft_row := private.lock_quote_draft(target_quote_id, expected_revision);

  delete from public.quote_version_attachments
  where organization_id = draft_row.organization_id
    and quote_version_id = draft_row.id;

  for attachment in select * from jsonb_array_elements(new_attachments)
  loop
    clean_file_id := nullif(attachment ->> 'file_id', '')::uuid;
    clean_display_name := nullif(trim(coalesce(attachment ->> 'display_name', '')), '');

    if clean_file_id is null then
      raise exception 'File % is missing.', attachment_index + 1 using errcode = 'check_violation';
    end if;
    if clean_file_id = any(seen_ids) then
      raise exception 'The same file was listed twice.' using errcode = 'check_violation';
    end if;
    seen_ids := seen_ids || clean_file_id;

    if not exists (
      select 1
      from public.file_links link
      join public.files file on file.id = link.file_id and file.organization_id = link.organization_id
      where link.organization_id = draft_row.organization_id
        and link.entity_type = 'quote'
        and link.entity_id = target_quote_id
        and link.file_id = clean_file_id
        and file.processing_state = 'available'
        and file.trashed_at is null
    ) then
      raise exception 'File % was not uploaded to this quote.', attachment_index + 1
        using errcode = 'check_violation';
    end if;

    if clean_display_name is null or char_length(clean_display_name) > 255 then
      raise exception 'File % needs a name under 255 characters.', attachment_index + 1
        using errcode = 'check_violation';
    end if;

    insert into public.quote_version_attachments (
      organization_id, quote_id, quote_version_id, file_id, position, customer_visible, display_name
    ) values (
      draft_row.organization_id, draft_row.quote_id, draft_row.id, clean_file_id, attachment_index,
      coalesce((attachment ->> 'customer_visible')::boolean, false), clean_display_name
    );

    attachment_index := attachment_index + 1;
  end loop;

  perform private.refresh_quote_file_protection(draft_row.organization_id, draft_row.quote_id);

  return private.bump_quote_draft(draft_row.id);
end;
$$;

-- 8a. register_pending_file gains target_origin_role, so the signature changes.
drop function public.register_pending_file(uuid, uuid, text, text, bigint, text, text, uuid, uuid);

CREATE OR REPLACE FUNCTION "public"."register_pending_file"("target_organization_id" "uuid", "target_uploaded_by" "uuid", "target_display_name" "text", "target_mime_type" "text", "target_size_bytes" bigint, "target_object_key" "text", "target_origin_type" "text", "target_origin_id" "uuid" DEFAULT NULL::"uuid", "target_folder_id" "uuid" DEFAULT NULL::"uuid", "target_origin_role" "text" DEFAULT 'attachment'::"text") RETURNS "public"."files"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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
    origin_type, origin_id, origin_role, processing_state, uploaded_by
  )
  values (
    target_organization_id, target_folder_id, target_display_name, target_mime_type, target_size_bytes,
    target_object_key, target_origin_type, target_origin_id,
    coalesce(target_origin_role, 'attachment'), 'pending', target_uploaded_by
  )
  returning * into created;

  return created;
end;
$$;

revoke all on function public.register_pending_file(uuid, uuid, text, text, bigint, text, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.register_pending_file(uuid, uuid, text, text, bigint, text, text, uuid, uuid, text) to service_role;
comment on function public.register_pending_file(uuid, uuid, text, text, bigint, text, text, uuid, uuid, text) is
  'Creates the pending File an upload writes into, remembering the role it will be linked to its origin record with. Service role only: the calling route checks files.manage and the origin record first, and this re-checks tenant, membership and key prefix.';

-- 8b. finalize_file_processing links with the upload's own role, and never a File already in Trash
CREATE OR REPLACE FUNCTION "public"."finalize_file_processing"("target_file_id" "uuid", "target_claim_token" "uuid", "target_state" "text", "target_checksum_sha256" "text" DEFAULT NULL::"text", "target_error" "text" DEFAULT NULL::"text", "target_thumbnail_object_key" "text" DEFAULT NULL::"text") RETURNS "public"."files"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  claimed public.files;
  finalized public.files;
begin
  if target_state not in ('available', 'failed', 'quarantined') then
    raise exception 'A file can only finish processing as available, failed or quarantined.'
      using errcode = 'check_violation';
  end if;

  if target_state = 'available' and target_checksum_sha256 is null then
    raise exception 'A file cannot be made available without the checksum from its verification pass.'
      using errcode = 'check_violation';
  end if;

  select * into claimed
  from public.files
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending'
  for update;

  if claimed.id is null then
    raise exception 'That file processing claim is no longer current.'
      using errcode = 'no_data_found';
  end if;

  if target_thumbnail_object_key is not null
     and target_thumbnail_object_key is distinct from claimed.object_key || '.thumb.jpg' then
    raise exception 'That preview does not belong to this file.'
      using errcode = 'check_violation';
  end if;

  if target_state <> 'available' and target_thumbnail_object_key is not null then
    raise exception 'Only an available file can carry a preview.'
      using errcode = 'check_violation';
  end if;

  update public.files
  set processing_state = target_state,
      checksum_sha256 = coalesce(target_checksum_sha256, checksum_sha256),
      thumbnail_object_key = coalesce(target_thumbnail_object_key, thumbnail_object_key),
      scanned_at = case when target_state = 'available' then now() else scanned_at end,
      processing_error = case when target_state = 'available' then null else target_error end,
      claimed_at = null,
      claim_token = null
  where id = claimed.id
  returning * into finalized;

  if finalized.processing_state = 'available'
    and finalized.trashed_at is null
    and finalized.origin_id is not null
    and finalized.origin_type = any (
      array['client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice']
    )
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    values (
      finalized.organization_id, finalized.id, finalized.origin_type, finalized.origin_id,
      finalized.origin_role, finalized.uploaded_by
    )
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  return finalized;
end;
$$;

-- 8c. list_files: a line photo is not one of the record's own files
CREATE OR REPLACE FUNCTION "public"."list_files"("target_organization_id" "uuid", "target_view" "text" DEFAULT 'all'::"text", "target_folder_id" "uuid" DEFAULT NULL::"uuid", "target_search" "text" DEFAULT NULL::"text", "target_limit" integer DEFAULT 40, "cursor_created_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_id" "uuid" DEFAULT NULL::"uuid", "target_entity_type" "text" DEFAULT NULL::"text", "target_entity_id" "uuid" DEFAULT NULL::"uuid", "only_attachable" boolean DEFAULT false) RETURNS TABLE("id" "uuid", "display_name" "text", "mime_type" "text", "kind" "text", "size_bytes" bigint, "has_thumbnail" boolean, "folder_id" "uuid", "folder_name" "text", "origin_type" "text", "origin_id" "uuid", "processing_state" "text", "uploaded_by" "uuid", "uploaded_by_name" "text", "created_at" timestamp with time zone, "trashed_at" timestamp with time zone, "usage_count" integer)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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
            and link.role <> 'line_photo'
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

-- 8d. file_usage gains customer_received, so the return type changes.
drop function public.file_usage(uuid, uuid, integer, timestamptz, uuid);

CREATE OR REPLACE FUNCTION "public"."file_usage"("target_organization_id" "uuid", "target_file_id" "uuid", "target_limit" integer DEFAULT 10, "cursor_created_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "entity_type" "text", "entity_id" "uuid", "role" "text", "protected" boolean, "customer_received" boolean, "title" "text", "context" "text", "status" "text", "link_type" "text", "link_id" "uuid", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
  select
    link.id,
    link.entity_type,
    link.entity_id,
    link.role,
    link.protected,
    -- The hardest warning level in the Trash dialog: a published quote version still shows the File.
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
    ) as customer_received,
    case link.entity_type
      when 'client' then client_record.display_name
      when 'property' then coalesce(nullif(btrim(property_record.label), ''), property_record.address_line1)
      when 'request' then request_record.title
      when 'quote' then 'Quote #' || quote_record.quote_number
      when 'invoice' then 'Invoice #' || invoice_record.invoice_number
      when 'job' then 'Job #' || job_record.job_number
      when 'visit' then coalesce(nullif(btrim(visit_record.title), ''), 'Visit')
      when 'job_expense' then expense_record.name
    end as title,
    case link.entity_type
      when 'property' then nullif(btrim(concat_ws(', ', property_record.address_line1, property_record.city)), '')
      when 'quote' then nullif(btrim(quote_record.title), '')
      when 'invoice' then nullif(btrim(invoice_record.subject), '')
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

revoke all on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) from public, anon;
grant execute on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) to authenticated, service_role;
comment on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) is
  'The "Used in" list for one File, resolved to the record titles the details panel shows, with whether a customer already received it there. Security invoker, so a record the reader may not view produces no row at all.';

-- ---------------------------------------------------------------------------------------------------------
-- 9. Trash: any File can go; a customer's copy needs an acknowledgement and shows the File as removed
-- ---------------------------------------------------------------------------------------------------------

drop trigger files_protected_use_blocks_trash on public.files;
drop function private.files_protected_use_blocks_trash();

drop function public.trash_file(uuid, uuid, uuid);

create function public.trash_file(
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
  -- on a published quote: their copy is about to change, so the contractor must have said so explicitly.
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

  -- Everything still being edited lets go of the File now. Published quote versions keep pointing at it:
  -- that frozen reference is what shows the customer the gap, and what Restore brings back.
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

  perform private.refresh_quote_file_protection(target_organization_id, quote_id)
  from unnest(affected_quote_ids) as quote_id;

  -- Every ordinary use is detached, as the dialog said. A use a published quote still holds stays linked,
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

revoke all on function public.trash_file(uuid, uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.trash_file(uuid, uuid, uuid, boolean) to service_role;

comment on function public.trash_file(uuid, uuid, uuid, boolean) is
  'Moves one File to Trash. Any File can go. One a customer already received on a published quote needs acknowledge_customer_copies (SQLSTATE P0412 otherwise); the published copy then shows it as removed. Drafts, request pricing and job/visit lines let go of it; ordinary links are detached and protected ones kept for Restore. Service role only.';
