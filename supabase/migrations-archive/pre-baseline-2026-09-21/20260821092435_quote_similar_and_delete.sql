-- Quotes Part 5D: Create Similar Quote and safe deletion of eligible unused drafts.
--
-- Two new doors, both gated on quotes.edit like the archive/restore commands already built. Neither one
-- reuses another command's SQL by calling it -- clone_quote_version_to_draft targets an existing quote's
-- own draft slot, and this needs a brand-new quote row and a brand-new Opportunity, so the copy is written
-- once here mirroring both create_quote's inserts and clone_quote_version_to_draft's column list.

-- 1. A brand-new quote that starts full ------------------------------------------------------------------

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

  -- Staff read the draft while one exists and the published version otherwise, so the copy starts from
  -- whichever one a person looking at this quote would actually see on screen.
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
  select att.organization_id, new_quote.id, new_version.id, att.attachment_id, att.position,
    att.customer_visible, att.display_name
  from public.quote_version_attachments att
  where att.organization_id = source_version.organization_id
    and att.quote_id = source_version.quote_id
    and att.quote_version_id = source_version.id
  order by att.position, att.id;

  perform private.refresh_quote_draft_totals(new_version.id);

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- Every quote gets its own parked card, exactly like create_quote and convert_request_to_quote already
  -- give one. This is a brand-new quote with no request lineage, so quote_id is the only link set here --
  -- the stage trigger takes it off the board on its own.
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

-- 2. Removing a draft nobody has ever seen -----------------------------------------------------------------

create or replace function public.delete_quote(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  touched_version_count integer;
begin
  select * into quote_row from public.quotes where id = target_quote_id for update;
  if quote_row.id is null or not private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.edit'
  ) then
    raise exception 'You do not have access to delete this quote.' using errcode = 'insufficient_privilege';
  end if;

  if quote_row.request_id is not null then
    raise exception 'A quote made from a request cannot be deleted. Archive it instead.'
      using errcode = 'check_violation';
  end if;
  if quote_row.status <> 'draft' then
    raise exception 'Only a draft that has never been sent can be deleted. Archive it instead.'
      using errcode = 'check_violation';
  end if;

  -- Never published, ever -- not just "not published right now". A quote revised back to draft after
  -- being published, declined, or archived still carries that history in a sibling version row.
  select count(*) into touched_version_count
  from public.quote_versions
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and status <> 'draft';
  if touched_version_count > 0 then
    raise exception 'This quote has already been sent. Archive it instead.' using errcode = 'check_violation';
  end if;

  -- quote_versions, quote_version_lines, quote_version_attachments, and opportunities.quote_id all cascade
  -- from this one delete. The remaining version is still `draft`, so the published-row guard triggers never
  -- fire.
  delete from public.quotes where id = quote_row.id;

  return jsonb_build_object('quote_id', quote_row.id, 'quote_number', quote_row.quote_number);
end;
$$;

revoke all on function public.delete_quote(uuid) from public;
revoke execute on function public.delete_quote(uuid) from anon;
grant execute on function public.delete_quote(uuid) to authenticated;
