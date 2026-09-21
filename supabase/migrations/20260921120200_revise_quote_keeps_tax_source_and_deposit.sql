-- Revising a sent quote lost its tax source and its deposit.
--
-- clone_quote_version_to_draft (behind "Revise") copied the tax name and rate but not `tax_source` or `tax_rate_id`,
-- and copied neither the deposit type nor the deposit schedule rows. The new draft therefore started as "tax not
-- configured" (a quote that had tax then broke quote_versions_tax_source_consistency, and one without was refused at
-- send) and silently lost its deposit. The draft now carries all of them, and is priced from them by the refresh
-- that already ran at the end. Grants are unchanged.

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
    organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
  ) select organization_id, quote_id, new_draft.id, attachment_id, position, customer_visible, display_name
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
