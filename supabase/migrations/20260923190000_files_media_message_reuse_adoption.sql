-- Files and Media, Part 6E: messages reuse an existing library File (Jafar, 2026-09-22 direction, 2026-09-23
-- build).
--
-- The composer's own upload/scan pipeline stays exactly as it is today -- ConversationAttachments presigns
-- straight to R2, and enqueue_conversation_reply_email/_sms write the result into
-- communication_outbound_attachments. This migration adds nothing to that path. It only lets an already
-- -available library File be picked instead of re-uploaded: the reply route resolves the File's own
-- object_key/mime_type/size_bytes (no headObject re-measure -- the Files pipeline already verified it) and
-- passes it into the same target_attachments the RPCs already accept, so the picture or document really
-- travels with the sent email or text. Once the send succeeds, the route calls the existing
-- attach_file_to_record for each picked File with the new entity_type 'message', so the File's "Used in"
-- list shows the conversation the same way every other adopted record already does.
--
-- The delivery intent (public.communication_delivery_intents) is the stable id a message gets the moment it
-- is queued, so it is what entity_id points at. A sent message is finished history, the same as an issued
-- quote or invoice: can_manage_linked_record refuses to manage it, so nothing can unlink a File from a
-- message that has already gone out.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Let 'message' through file_links' own check constraint
-- ---------------------------------------------------------------------------------------------------------

alter table public.file_links
  drop constraint file_links_entity_type_check;
alter table public.file_links
  add constraint file_links_entity_type_check
  check (entity_type = any (array[
    'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice', 'organization',
    'message'
  ]))
  not valid;
alter table public.file_links
  validate constraint file_links_entity_type_check;

-- ---------------------------------------------------------------------------------------------------------
-- 2. linked_entity_exists, can_view_linked_entity, can_manage_linked_record gain the 'message' branch
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
    else false
  end;
$$;

-- A message is read the same way its own conversation already is -- customers.view, the exact permission
-- gating the conversation context/history routes (src/routes/api/communications/conversations/[clientId]).
-- File Manager never widens that: a member who cannot read this client's conversation still cannot see a
-- File only because it once went out on one of that client's messages.
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
      else false
    end,
    false
  );
$$;

-- A sent message is history, the same as an issued quote or invoice: there is no edit affordance for it, so
-- 'message' never grants manage even though it may be viewed.
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
      else false
    end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 3. file_usage: the "Used in" row for a message, redirecting into that client's conversation
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
      when 'message' then message_client.display_name
    end as context,
    case link.entity_type
      when 'client' then client_record.lifecycle_status
      when 'request' then request_record.status
      when 'quote' then quote_record.status
      when 'job' then job_record.status
      when 'message' then message_record.status
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
  left join public.communication_delivery_intents message_record
    on link.entity_type = 'message' and message_record.id = link.entity_id
  left join public.clients message_client
    on message_client.id = message_record.client_id
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
