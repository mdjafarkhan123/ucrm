-- Files and Media, Part 6B: Quotes join the File Manager.
--
-- quote_version_attachments -- the frozen-at-send customer document -- pointed at legacy public.attachments,
-- whose FK RESTRICT was the entire mechanism protecting a sent quote's files. New Quote uploads via
-- RecordFilesCard/PendingFilesCard never create an attachments row (files/file_links only), so leaving the
-- table as-is would silently break that protection the moment Quote's Svelte adopts the catalog. This
-- migration repoints the table at public.files directly and reuses the File Manager's own file_links.protected
-- lock in its place. Decision confirmed with Jafar; see Memory/campaigns/files-media/parts/6B.md.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Re-sync safety net, matches Part 5's pattern
-- ---------------------------------------------------------------------------------------------------------

select private.backfill_files_from_attachments();

-- ---------------------------------------------------------------------------------------------------------
-- 2. quote_version_attachments moves from attachment_id to file_id
-- ---------------------------------------------------------------------------------------------------------

alter table public.quote_version_attachments
  add column file_id uuid;

-- This backfill must also reach rows belonging to already-published quote versions (that's exactly the
-- protected history we're migrating), so the immutability trigger is suspended for this one statement only.
alter table public.quote_version_attachments disable trigger quote_version_attachments_reject_published_change;

update public.quote_version_attachments version_attachment
set file_id = attachment.file_id
from public.attachments attachment
where attachment.id = version_attachment.attachment_id
  and attachment.organization_id = version_attachment.organization_id;

alter table public.quote_version_attachments enable trigger quote_version_attachments_reject_published_change;

do $$
declare
  unresolved integer;
begin
  select count(*) into unresolved from public.quote_version_attachments where file_id is null;
  if unresolved > 0 then
    raise exception 'quote_version_attachments has % row(s) whose attachment never resolved to a File.',
      unresolved;
  end if;
end;
$$;

alter table public.quote_version_attachments
  alter column file_id set not null;

alter table public.quote_version_attachments
  drop constraint quote_version_attachments_attachment_fk;

alter table public.quote_version_attachments
  drop constraint quote_version_attachments_version_unique;

drop index if exists public.quote_version_attachments_attachment_idx;

alter table public.quote_version_attachments
  drop column attachment_id;

alter table public.quote_version_attachments
  add constraint quote_version_attachments_file_fk
    foreign key (organization_id, file_id) references public.files (organization_id, id);

alter table public.quote_version_attachments
  add constraint quote_version_attachments_version_unique
    unique (organization_id, quote_version_id, file_id);

create index quote_version_attachments_file_idx
  on public.quote_version_attachments (organization_id, file_id);

-- ---------------------------------------------------------------------------------------------------------
-- 3. replace_quote_version_attachments: validate and write against file_links/files, then keep `protected`
--    true for exactly as long as a file is part of this quote's customer document, draft or long-sent.
-- ---------------------------------------------------------------------------------------------------------

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

  -- Monotonic per file, exactly like the old RESTRICT: true the instant a file is part of any current or
  -- historical quote_version_attachments row for this quote, cleared only once no row (draft or long-sent)
  -- references it any more. A sent version's rows are never deleted, so a file that was ever sent stays
  -- protected forever.
  update public.file_links link
  set protected = exists (
    select 1 from public.quote_version_attachments version_attachment
    where version_attachment.organization_id = link.organization_id
      and version_attachment.quote_id = draft_row.quote_id
      and version_attachment.file_id = link.file_id
  )
  where link.organization_id = draft_row.organization_id
    and link.entity_type = 'quote'
    and link.entity_id = draft_row.quote_id;

  return private.bump_quote_draft(draft_row.id);
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 4. clone_quote_version_to_draft ("Revise"): same body as the tax-source fix, attachment_id -> file_id.
--    Copies rows already covered by an existing protected link, so no file_links work is needed here.
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.clone_quote_version_to_draft(target_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    image_attachment_id, line_kind, selection_kind, is_recommended
  ) select line.organization_id, line.quote_id, new_draft.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id, line.line_kind, line.selection_kind, line.is_recommended
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
$function$;

-- ---------------------------------------------------------------------------------------------------------
-- 5. create_similar_quote: copies onto a *new* quote_id, so it also creates a fresh file_link on the new
--    quote before writing the frozen copy -- attach_file_to_record is idempotent and raises if not available.
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_similar_quote(target_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    image_attachment_id, line_kind, selection_kind, is_recommended
  )
  select line.organization_id, new_quote.id, new_version.id, line.position,
    line.source_catalog_item_id, line.category, line.is_labor, line.name, line.description,
    line.unit_label, line.quantity, line.unit_price_minor, line.unit_cost_minor, line.is_taxable,
    line.image_attachment_id, line.line_kind, line.selection_kind, line.is_recommended
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

  perform private.refresh_quote_draft_totals(new_version.id);

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (
    new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title
  );

  return jsonb_build_object('quote_id', new_quote.id, 'quote_number', new_quote.quote_number);
end;
$function$;

-- ---------------------------------------------------------------------------------------------------------
-- 6. private.quote_customer_document: only the 'attachments' block changes -- attachment_id -> file_id,
--    joined against public.files instead of public.attachments. The 'lines' block's image_attachment_id
--    stays untouched; line-item photos are Part 6C.
-- ---------------------------------------------------------------------------------------------------------

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
            'image_attachment_id', line.image_attachment_id
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
            'id', version_attachment.file_id,
            'name', version_attachment.display_name,
            'mime_type', file.mime_type,
            'size_bytes', file.size_bytes
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

-- ---------------------------------------------------------------------------------------------------------
-- 7. backfill_files_from_attachments: its "already sent" protected check read quote_version_attachments by
--    attachment_id. That column no longer exists, so a future re-sync (Part 6C/6D onward reruns this same
--    function) must read the equivalent by file_id instead. Only this one exists-clause changes.
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
    or exists (
      select 1 from public.job_report_photos as report_photo
      where report_photo.organization_id = attachment.organization_id
        and report_photo.attachment_id = attachment.id
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
