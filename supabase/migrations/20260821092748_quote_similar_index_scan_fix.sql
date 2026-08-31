-- Part 5D follow-up: create_similar_quote's line/attachment copy now matches the
-- (organization_id, quote_id, quote_version_id) prefix quote_version_lines_version_idx and
-- quote_version_attachments_version_idx already lead with, turning what was a seq scan into an index scan.

create or replace function public.create_similar_quote(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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
    discount_name, discount_type, discount_value, tax_name, tax_rate_basis_points
  ) values (
    new_quote.organization_id, new_quote.id, 1, 'draft', source_version.currency_code,
    source_version.client_display_name, coalesce(organization_display_name, source_version.organization_name),
    source_version.service_address_line1, source_version.service_address_line2, source_version.service_city,
    source_version.service_state_region, source_version.service_postal_code, source_version.service_country,
    source_version.subtotal_minor, (select auth.uid()), 1, source_version.contract_disclaimer,
    source_version.introduction, source_version.client_message, source_version.show_quantities,
    source_version.show_unit_prices, source_version.show_line_totals, source_version.show_totals,
    source_version.discount_name, source_version.discount_type, source_version.discount_value,
    source_version.tax_name, source_version.tax_rate_basis_points
  )
  returning * into new_version;

  -- Filtered on the same (organization_id, quote_id, quote_version_id) prefix the version's own indexes
  -- lead with, so this is an index scan rather than a seq scan of every organization's lines.
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

  insert into public.quote_version_attachments (
    organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
  )
  select organization_id, new_quote.id, new_version.id, attachment_id, position, customer_visible, display_name
  from public.quote_version_attachments
  where organization_id = source_version.organization_id
    and quote_id = source_version.quote_id
    and quote_version_id = source_version.id
  order by position, id;

  perform private.refresh_quote_draft_totals(new_version.id);

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (
    new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title
  );

  return jsonb_build_object('quote_id', new_quote.id, 'quote_number', new_quote.quote_number);
end;
$$;

revoke all on function public.create_similar_quote(uuid) from public;
revoke execute on function public.create_similar_quote(uuid) from anon;
grant execute on function public.create_similar_quote(uuid) to authenticated;
