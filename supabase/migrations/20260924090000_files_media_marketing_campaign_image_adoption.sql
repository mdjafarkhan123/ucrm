-- Files and Media, Part 6F: campaign image blocks get a real upload backed by the File Manager, replacing
-- the paste-a-URL field (Jafar, 2026-09-23 direction).
--
-- An image block now stores file_id (a File Manager upload) instead of a pasted url. The upload uses the
-- same origin_type/origin_id/origin_role handshake as a line photo or the business logo: the block editor
-- uploads with origin_type 'marketing_campaign', origin_id the campaign's own id, origin_role
-- 'campaign_image', and finalize_file_processing links it into file_links the moment the scan clears --
-- exactly the generic path Part 6A-6D already built, needing only a new entity type and role in its
-- vocabulary. There is no singleton swap here (unlike the logo): a campaign can hold several image blocks,
-- each with its own File, and nothing here ever deletes or unlinks one on its own -- only Trash does that,
-- through the file the same importance-warning system every other adopted record already uses.
--
-- The recipient's mail client fetches this image with no session at all, so render-email.ts resolves each
-- block's file_id to a new public, unauthenticated route (see (public)/ci/[campaignId]/[fileId]) rather than
-- the member-only /api/files/[id]/view. That route's only check is "does this file_id actually appear as an
-- image block's File on this campaign" -- two unguessable uuids stand in for the token the other public
-- file routes carry explicitly, the same trust level as any link already going out to every recipient.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Let 'marketing_campaign'/'campaign_image' through the catalog's check constraints
-- ---------------------------------------------------------------------------------------------------------

alter table public.file_links drop constraint file_links_role_check;
alter table public.file_links add constraint file_links_role_check
  check (role = any (array[
    'attachment', 'work_photo', 'report_photo', 'line_photo', 'logo', 'campaign_image'
  ]));

alter table public.files drop constraint files_origin_role_check;
alter table public.files add constraint files_origin_role_check
  check (origin_role = any (array['attachment', 'line_photo', 'logo', 'campaign_image']));

alter table public.files
  drop constraint files_origin_type_check;
alter table public.files
  add constraint files_origin_type_check
  check (origin_type = any (array[
    'file_manager', 'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice',
    'organization', 'marketing_campaign'
  ]))
  not valid;
alter table public.files
  validate constraint files_origin_type_check;

alter table public.file_links
  drop constraint file_links_entity_type_check;
alter table public.file_links
  add constraint file_links_entity_type_check
  check (entity_type = any (array[
    'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization',
    'message', 'marketing_campaign'
  ]))
  not valid;
alter table public.file_links
  validate constraint file_links_entity_type_check;

-- ---------------------------------------------------------------------------------------------------------
-- 2. linked_entity_exists, can_view_linked_entity, can_manage_linked_record gain the 'marketing_campaign'
--    branch
-- ---------------------------------------------------------------------------------------------------------

create or replace function private.linked_entity_exists(target_organization_id uuid, target_entity_type text, target_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then exists (select 1 from public.clients where id = target_entity_id and organization_id = target_organization_id)
    when 'property' then exists (select 1 from public.properties where id = target_entity_id and organization_id = target_organization_id)
    when 'request' then exists (select 1 from public.requests where id = target_entity_id and organization_id = target_organization_id)
    when 'quote' then exists (select 1 from public.quotes where id = target_entity_id and organization_id = target_organization_id)
    when 'job_expense' then exists (select 1 from public.job_expenses where id = target_entity_id and organization_id = target_organization_id)
    when 'job' then exists (select 1 from public.jobs where id = target_entity_id and organization_id = target_organization_id)
    when 'visit' then exists (select 1 from public.job_visits where id = target_entity_id and organization_id = target_organization_id)
    when 'invoice' then exists (select 1 from public.invoices where id = target_entity_id and organization_id = target_organization_id)
    when 'organization' then target_entity_id = target_organization_id
    when 'message' then exists (select 1 from public.communication_delivery_intents where id = target_entity_id and organization_id = target_organization_id)
    when 'marketing_campaign' then exists (select 1 from public.marketing_campaigns where id = target_entity_id and organization_id = target_organization_id)
    else false
  end;
$$;

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
      when 'message' then
        private.has_permission(target_organization_id, 'customers.view')
        and exists (
          select 1 from public.communication_delivery_intents intent
          where intent.id = target_entity_id and intent.organization_id = target_organization_id
        )
      when 'marketing_campaign' then
        private.has_permission(target_organization_id, 'marketing.view')
        and exists (
          select 1 from public.marketing_campaigns campaign
          where campaign.id = target_entity_id and campaign.organization_id = target_organization_id
        )
      else false
    end,
    false
  );
$$;

-- Managing a campaign image is the same marketing.draft gate that already lets someone edit the campaign
-- itself.
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
      when 'message' then false
      when 'marketing_campaign' then private.has_permission(target_organization_id, 'marketing.draft')
      else false
    end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 3. finalize_file_processing: an available campaign-image File links itself the same generic way a line
--    photo or a logo does. No singleton swap -- a campaign may hold many image blocks, each its own File.
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
      array[
        'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization',
        'marketing_campaign'
      ]
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
-- 4. file_usage: a campaign image's "Used in" row, and customer_received once the campaign has actually gone
--    out (sending/completed/needs_attention) -- a recipient may already have this image cached, the same
--    reasoning a published quote's line photo gets a stronger Trash warning for.
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
  left join public.marketing_campaigns campaign_record
    on link.entity_type = 'marketing_campaign' and campaign_record.id = link.entity_id
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
