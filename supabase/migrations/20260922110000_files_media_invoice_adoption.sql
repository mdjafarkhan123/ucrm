-- Files and Media, Part 6A: Invoices join the File Manager.
--
-- Invoice is the one record type the original catalog design (20260921160000) left out on purpose --
-- Quotes and Invoices were always Part 6 scope. Every generic linked-entity helper below was seeded with
-- the other seven types from the very first baseline (built originally for the pre-catalog attachments/
-- notes/tags tables), so this migration only has to add the eighth branch each of them was always missing,
-- plus the two catalog-table check constraints that gate it. No table, column or RLS policy changes: the
-- shape these helpers plug into already exists and already works for every other record.

-- ---------------------------------------------------------------------------------------------------------
-- Let 'invoice' through the two catalog check constraints
-- ---------------------------------------------------------------------------------------------------------

alter table public.files
  drop constraint files_origin_type_check;
alter table public.files
  add constraint files_origin_type_check
  check (origin_type = any (array['file_manager', 'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice']))
  not valid;
alter table public.files
  validate constraint files_origin_type_check;

alter table public.file_links
  drop constraint file_links_entity_type_check;
alter table public.file_links
  add constraint file_links_entity_type_check
  check (entity_type = any (array['client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice']))
  not valid;
alter table public.file_links
  validate constraint file_links_entity_type_check;

-- ---------------------------------------------------------------------------------------------------------
-- Existence, view and manage: the three generic linked-entity helpers
-- ---------------------------------------------------------------------------------------------------------

-- Same shape as private.can_view_job_expense: exists-in-organization plus the flat permission the invoice's
-- own RLS policy already requires ("permitted members can view invoices").
create or replace function private.can_view_invoice(
  target_organization_id uuid,
  target_invoice_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.invoices as invoice
    where invoice.id = target_invoice_id
      and invoice.organization_id = target_organization_id
  )
  and private.is_organization_member(target_organization_id)
  and private.has_permission(target_organization_id, 'invoices.view');
$$;

comment on function private.can_view_invoice(uuid, uuid) is
  'Whether the caller may see this invoice: exists in the organization plus invoices.view, matching "permitted members can view invoices" on public.invoices itself. Invoices carry no per-row assigned scope.';

revoke all on function private.can_view_invoice(uuid, uuid) from public, anon;
grant execute on function private.can_view_invoice(uuid, uuid) to authenticated;

create or replace function private.linked_entity_exists(target_organization_id uuid, target_entity_type text, target_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then exists (
      select 1 from public.clients
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'property' then exists (
      select 1 from public.properties
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'request' then exists (
      select 1 from public.requests
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'quote' then exists (
      select 1 from public.quotes
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'job_expense' then exists (
      select 1 from public.job_expenses
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'job' then exists (
      select 1 from public.jobs
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'visit' then exists (
      select 1 from public.job_visits
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'invoice' then exists (
      select 1 from public.invoices
      where id = target_entity_id and organization_id = target_organization_id
    )
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
      else false
    end,
    false
  );
$$;

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
      else false
    end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- A record-origin upload joins its invoice when it is published, same as every other record type
-- ---------------------------------------------------------------------------------------------------------

create or replace function public.finalize_file_processing(
  target_file_id uuid,
  target_claim_token uuid,
  target_state text,
  target_checksum_sha256 text default null,
  target_error text default null,
  target_thumbnail_object_key text default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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
      'attachment', finalized.uploaded_by
    )
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  return finalized;
end;
$$;

comment on function public.finalize_file_processing(uuid, uuid, text, text, text, text) is
  'Ends one processing claim: publishes the File with its checksum and any preview the pass made, or records why it failed or was quarantined. A file uploaded from a CRM record is attached to that record in the same statement that publishes it, because that is the first moment the contract allows it to be attached. Service role only.';

-- ---------------------------------------------------------------------------------------------------------
-- The workspace: search by invoice number/subject, and "Used in" resolves an invoice link to its facts
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

comment on function public.list_files(uuid, text, uuid, text, integer, timestamptz, uuid, text, uuid, boolean) is
  'One page of the File Manager catalog, newest first, with the number of distinct records the reader may view. The "on_record" view is the picker''s "already on this record" section. Security invoker: the Part 2 policies decide every row, so a hidden record is absent from the list and from the count.';

create or replace function public.file_usage(
  target_organization_id uuid,
  target_file_id uuid,
  target_limit integer default 10,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns table (
  id uuid,
  entity_type text,
  entity_id uuid,
  role text,
  protected boolean,
  title text,
  context text,
  status text,
  link_type text,
  link_id uuid,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select
    link.id,
    link.entity_type,
    link.entity_id,
    link.role,
    link.protected,
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

comment on function public.file_usage(uuid, uuid, integer, timestamptz, uuid) is
  'The "Used in" list for one File, resolved to the record titles the details panel shows. Security invoker, so a record the reader may not view produces no row at all.';
