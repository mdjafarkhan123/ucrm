-- Files and Media, Part 6E fix: the "Used in" list works again for every File.
--
-- 20260923190000 joined public.communication_delivery_intents straight into public.file_usage. file_usage runs
-- as the caller, and authenticated has no SELECT on that table (delivery state is server-only by design), so
-- Postgres refused the whole query -- for every File, not only ones sent in a message -- and every File's
-- details panel failed to load.
--
-- The message fields file_usage needs now come from public.file_link_message, a security-definer lookup that
-- returns only a message's channel, subject, status and client, and only when the caller may view that
-- message (the same can_view_linked_entity rule file_links' own policy uses). No table grant is widened. It
-- lives in public, not private, because file_usage runs as the caller and authenticated has no USAGE on the
-- private schema; called directly as an RPC it reveals nothing the caller's own "Used in" list does not.
--
-- A message link also now counts as customer_received: a File in a sent email or text has already reached the
-- customer, so the Trash warning treats it the same as a File on a published quote.

create or replace function public.file_link_message(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
) returns table (channel text, subject text, status text, client_id uuid, client_name text)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
  select intent.channel, intent.subject, intent.status, intent.client_id, client.display_name
  from public.communication_delivery_intents intent
  left join public.clients client
    on client.organization_id = intent.organization_id and client.id = intent.client_id
  where target_entity_type = 'message'
    and intent.id = target_entity_id
    and intent.organization_id = target_organization_id
    and private.can_view_linked_entity(target_organization_id, 'message', target_entity_id);
$$;

revoke all on function public.file_link_message(uuid, text, uuid) from public, anon;
grant execute on function public.file_link_message(uuid, text, uuid) to authenticated;

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
    ) or link.entity_type = 'message' as customer_received,
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
      when 'message' then message_record.client_name
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
