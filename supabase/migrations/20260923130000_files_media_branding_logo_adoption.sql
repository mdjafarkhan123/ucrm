-- Files and Media, Part 6D: the business logo joins the File Manager (Jafar, 2026-09-23).
--
-- The logo drops its own presign/PUT/commit pipeline (no malware scan, no thumbnail, its own
-- `{organization}/logo/...` key prefix) and becomes a File like every other adopted record: uploaded through
-- `/api/files/uploads`, scanned and thumbnailed by the same worker, linked with the new file_links role
-- 'logo' on the new pseudo-entity_type 'organization' (entity_id is the organization's own id -- there is no
-- separate row to point at). `organization_settings.logo_object_key`/`branding_revision` stay exactly as they
-- are: the moment a logo File clears processing, `finalize_file_processing` copies its object_key into that
-- same column and bumps the same counter, so every downstream reader (the sidebar, `organizationLogoUrl`,
-- `quote_preview_logo_object_key`, the quote-version freeze) needs no change at all. A replacement logo's old
-- File is unlinked, never trashed -- the same "kept, not deleted" rule the old pipeline already had, so a
-- quote already sent keeps showing the exact logo it went out with.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Let 'organization'/'logo' through the catalog's check constraints
-- ---------------------------------------------------------------------------------------------------------

alter table public.file_links drop constraint file_links_role_check;
alter table public.file_links add constraint file_links_role_check
  check (role = any (array['attachment', 'work_photo', 'report_photo', 'line_photo', 'logo']));

alter table public.files drop constraint files_origin_role_check;
alter table public.files add constraint files_origin_role_check
  check (origin_role = any (array['attachment', 'line_photo', 'logo']));

alter table public.files
  drop constraint files_origin_type_check;
alter table public.files
  add constraint files_origin_type_check
  check (origin_type = any (array[
    'file_manager', 'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice',
    'organization'
  ]))
  not valid;
alter table public.files
  validate constraint files_origin_type_check;

alter table public.file_links
  drop constraint file_links_entity_type_check;
alter table public.file_links
  add constraint file_links_entity_type_check
  check (entity_type = any (array[
    'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization'
  ]))
  not valid;
alter table public.file_links
  validate constraint file_links_entity_type_check;

-- ---------------------------------------------------------------------------------------------------------
-- 2. can_view_linked_entity / can_manage_linked_record gain the 'organization' branch
-- ---------------------------------------------------------------------------------------------------------

-- The "record" is the organization itself -- private.is_organization_member already gated every caller
-- before this runs (files RLS and file_links RLS both check it first), so any member may view it.
create or replace function private.can_view_linked_entity(target_organization_id uuid, target_entity_type text, target_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    case target_entity_type
      when 'client' then private.can_view_client(target_organization_id, target_entity_id)
      when 'property' then private.can_view_property(target_organization_id, target_entity_id)
      when 'request' then private.can_view_request(target_organization_id, target_entity_id)
      when 'quote' then private.can_view_quote(target_organization_id, target_entity_id)
      when 'job_expense' then private.can_view_job_expense(target_organization_id, target_entity_id)
      when 'job' then private.can_view_job(target_organization_id, target_entity_id)
      when 'visit' then private.can_view_visit(target_organization_id, target_entity_id)
      when 'invoice' then private.can_view_invoice(target_organization_id, target_entity_id)
      when 'organization' then target_entity_id = target_organization_id
      else false
    end,
    false
  );
$$;

-- Managing the logo is the same settings.business.edit gate its old dedicated routes already required.
create or replace function private.can_manage_linked_record(target_organization_id uuid, target_entity_type text, target_entity_id uuid, target_record_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_view_linked_entity(target_organization_id, target_entity_type, target_entity_id)
    and case target_entity_type
      when 'client' then private.has_permission(target_organization_id, 'customers.edit')
      when 'property' then private.has_permission(target_organization_id, 'property.manage')
      when 'request' then true
      when 'quote' then private.has_permission(target_organization_id, 'quotes.edit')
      when 'job_expense' then true
      when 'job' then private.field_record_write_allowed(target_organization_id, target_record_owner)
      when 'visit' then private.field_record_write_allowed(target_organization_id, target_record_owner)
      when 'invoice' then private.has_permission(target_organization_id, 'invoices.edit')
      when 'organization' then private.has_permission(target_organization_id, 'settings.business.edit')
      else false
    end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 3. finalize_file_processing: an available logo File becomes the organization's live logo
-- ---------------------------------------------------------------------------------------------------------

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
      array['client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization']
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

    -- The logo is a singleton: this File becomes the one the sidebar, quotes and invoices render from, and
    -- whatever File held that job before is unlinked (not trashed -- an already-sent quote freezes its own
    -- copy of the object_key text below, so the old File and its R2 object must survive).
    if finalized.origin_type = 'organization' and finalized.origin_role = 'logo' then
      delete from public.file_links
      where organization_id = finalized.organization_id
        and entity_type = 'organization'
        and role = 'logo'
        and file_id <> finalized.id
        and not protected;

      update public.organization_settings
      set logo_object_key = finalized.object_key,
          branding_revision = branding_revision + 1,
          branding_updated_by = finalized.uploaded_by,
          branding_updated_at = now()
      where organization_id = finalized.organization_id;

      insert into public.organization_settings_audit (
        organization_id, section, changed_fields, actor_user_id
      )
      values (finalized.organization_id, 'branding', array['logo'], finalized.uploaded_by);
    end if;
  end if;

  return finalized;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 4. remove_organization_logo also drops the now-inactive link, the same "unlink, don't trash" rule
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."remove_organization_logo"("target_organization_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  previous_object_key text;
  new_revision integer;
begin
  if not private.has_permission(target_organization_id, 'settings.business.edit') then
    raise exception 'You do not have access to change business settings.'
      using errcode = 'insufficient_privilege';
  end if;

  select logo_object_key into previous_object_key
  from public.organization_settings
  where organization_id = target_organization_id
  for update;

  update public.organization_settings
  set
    logo_object_key = null,
    branding_revision = branding_revision + 1,
    branding_updated_by = (select auth.uid()),
    branding_updated_at = now()
  where organization_id = target_organization_id
  returning branding_revision into new_revision;

  delete from public.file_links
  where organization_id = target_organization_id
    and entity_type = 'organization'
    and role = 'logo'
    and not protected;

  insert into public.organization_settings_audit (
    organization_id, section, changed_fields, actor_user_id
  )
  values (target_organization_id, 'branding', array['logo'], (select auth.uid()));

  return jsonb_build_object(
    'status', 'saved',
    'branding_revision', new_revision,
    'previous_object_key', previous_object_key
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 5. set_organization_logo: dead code now that a logo File promotes itself once it is checked
-- ---------------------------------------------------------------------------------------------------------

drop function if exists public.set_organization_logo(uuid, text);

-- ---------------------------------------------------------------------------------------------------------
-- 6. file_usage: the logo's "Used in" row, and no join needed -- there is only ever one meaning
-- ---------------------------------------------------------------------------------------------------------

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
      when 'organization' then 'Business logo'
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
