-- Quotes: freeze the organization logo and brand color into each published version.
--
-- docs/quote-behavior-contract.md § "Identity, lineage, and snapshots" already commits to this: "Every
-- published version separately snapshots the client display identity, service address, organization
-- name/logo/contact details, currency, locale, tax description, and all customer-visible content. Later
-- Client, Property, catalog, branding, or settings edits never rewrite a published version." Only
-- organization_name was ever actually snapshotted -- a contractor who later replaced their logo or brand
-- color would silently rewrite every quote document already sent to a customer.
--
-- This follows the exact pattern already shipped for the Quote representative signature
-- (20260824101601_settings_quote_settings_foundation.sql): a frozen copy column on quote_versions, seeded
-- from organization_settings at create_quote time, and carried forward untouched by
-- clone_quote_version_to_draft when a sent quote is revised (the prior version's own frozen value, not
-- today's settings). freeze_quote_version needs no change: its canonical hash already covers every
-- quote_versions column it does not explicitly exclude, so these two are hashed and versioned for free.

-- 1. Frozen columns on quote_versions ----------------------------------------------------------------------

alter table public.quote_versions
  add column logo_object_key text,
  add column brand_color text check (brand_color is null or brand_color ~ '^#[0-9A-Fa-f]{6}$');

-- The named-column grant from 20260831135855_quote_money_columns_leave_the_authenticated_grant.sql does not
-- extend to new columns automatically -- that is the point of it. Neither column is money, so it joins the
-- plain grant the same way representative_* did.
grant select (logo_object_key, brand_color) on public.quote_versions to authenticated;

-- 2. A new quote starts from the organization's current branding ------------------------------------------

create or replace function public.create_quote(
  target_client_id uuid,
  target_property_id uuid,
  quote_title text,
  disclaimer text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  client_row public.clients;
  property_row public.properties;
  new_quote public.quotes;
  new_version public.quote_versions;
  allocated_number integer;
  organization_currency text;
  organization_display_name text;
  clean_title text;
  clean_disclaimer text;
  resolved_tax record;
  quote_settings public.organization_settings;
begin
  clean_title := nullif(trim(coalesce(quote_title, '')), '');
  if clean_title is null or char_length(clean_title) < 2 or char_length(clean_title) > 160 then
    raise exception 'A quote needs a title between 2 and 160 characters.' using errcode = 'check_violation';
  end if;

  clean_disclaimer := nullif(trim(coalesce(disclaimer, '')), '');
  if clean_disclaimer is not null and char_length(clean_disclaimer) > 5000 then
    raise exception 'The contract disclaimer is too long.' using errcode = 'check_violation';
  end if;

  select * into client_row from public.clients where id = target_client_id;

  -- One answer for "no such client" and "not your client": a stranger learns nothing either way.
  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'quotes.create'
     ) then
    raise exception 'You do not have access to create a quote for this client.'
      using errcode = 'insufficient_privilege';
  end if;

  if client_row.deleted_at is not null then
    raise exception 'That client is no longer available.' using errcode = 'check_violation';
  end if;
  if client_row.archived_at is not null then
    raise exception 'That client is archived. Restore them before quoting new work.'
      using errcode = 'check_violation';
  end if;

  select * into property_row
  from public.properties
  where id = target_property_id
    and organization_id = client_row.organization_id
    and client_id = client_row.id;

  if property_row.id is null
     or property_row.deleted_at is not null
     or property_row.archived_at is not null then
    raise exception 'Choose a live property belonging to this client.' using errcode = 'check_violation';
  end if;

  select * into quote_settings
  from public.organization_settings
  where organization_id = client_row.organization_id;

  organization_currency := quote_settings.currency_code;

  select organization.name into organization_display_name
  from public.organizations as organization
  where organization.id = client_row.organization_id;

  allocated_number := private.allocate_quote_number(client_row.organization_id);

  select * into resolved_tax
  from private.resolve_property_tax(client_row.organization_id, property_row.id);

  -- No disclaimer typed by the caller falls back to the Quote Settings default. An explicit disclaimer
  -- (used by conversion flows that already compose their own) always wins.
  if clean_disclaimer is null then
    clean_disclaimer := quote_settings.quote_terms;
  end if;

  insert into public.quotes (
    organization_id, client_id, property_id, quote_number, title, currency_code, created_by
  ) values (
    client_row.organization_id,
    client_row.id,
    property_row.id,
    allocated_number,
    clean_title,
    coalesce(organization_currency, 'USD'),
    (select auth.uid())
  )
  returning * into new_quote;

  insert into public.quote_versions (
    organization_id, quote_id, version_number, status, currency_code,
    client_display_name, organization_name, logo_object_key, brand_color, contract_disclaimer,
    service_address_line1, service_address_line2, service_city,
    service_state_region, service_postal_code, service_country,
    tax_source, tax_name, tax_rate_basis_points, tax_rate_id,
    representative_enabled, representative_name, representative_title, representative_signature_object_key,
    require_customer_signature,
    created_by
  ) values (
    new_quote.organization_id,
    new_quote.id,
    1,
    'draft',
    new_quote.currency_code,
    client_row.display_name,
    organization_display_name,
    quote_settings.logo_object_key,
    quote_settings.brand_color,
    clean_disclaimer,
    property_row.address_line1,
    property_row.address_line2,
    property_row.city,
    property_row.state_region,
    property_row.postal_code,
    property_row.country,
    resolved_tax.source, resolved_tax.name, resolved_tax.rate_basis_points, resolved_tax.rate_id,
    coalesce(quote_settings.quote_representative_enabled, false),
    quote_settings.quote_representative_name,
    quote_settings.quote_representative_title,
    quote_settings.quote_representative_signature_object_key,
    coalesce(quote_settings.quote_require_customer_signature, false),
    (select auth.uid())
  )
  returning * into new_version;

  update public.quotes set draft_version_id = new_version.id where id = new_quote.id;

  -- Same card the conversion command creates, for the same reason: every quote is one piece of commercial
  -- work with one identity. The stage trigger parks it off the board until the Quote columns exist.
  insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
  values (new_quote.organization_id, new_quote.client_id, new_quote.property_id, new_quote.id, new_quote.title);

  return jsonb_build_object(
    'quote_id', new_quote.id,
    'quote_number', new_quote.quote_number,
    'quote_version_id', new_version.id,
    'status', new_quote.status,
    'revision', new_version.revision
  );
end;
$$;

-- 3. Revising a sent quote keeps the branding it was actually sent with, not today's settings -------------
--
-- This rewrite also fixes a pre-existing break: 20260824101601_settings_quote_settings_foundation.sql
-- reintroduced references to public.quote_version_packages and quote_version_lines.package_id into this
-- function after 20260821072103_quotes_drop_packages_commands.sql had already dropped both. Every call to
-- revise_quote() has therefore been failing with "relation quote_version_packages does not exist" since that
-- migration shipped. This version removes the dead packages logic and adds the branding freeze.

create or replace function public.clone_quote_version_to_draft(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
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
    tax_rate_basis_points, representative_enabled, representative_name, representative_title,
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

  perform private.refresh_quote_draft_totals(new_draft.id);

  update public.quotes set draft_version_id = new_draft.id where id = quote_row.id;
  return jsonb_build_object('quote_id', quote_row.id, 'quote_version_id', new_draft.id, 'revision', 1);
end;
$$;

-- 4. The customer document exposes the frozen brand color and whether a logo exists -------------------------
--
-- The object key itself never leaves the server: the same boundary attachments already use. A public page
-- asks the token-scoped logo route below, which resolves the key server-side and streams the bytes.

create or replace function private.quote_customer_document(
  quote_row public.quotes,
  version_row public.quote_versions,
  recipient_name text,
  recipient_email text,
  include_money boolean
) returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $$
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
            'id', version_attachment.attachment_id,
            'name', version_attachment.display_name,
            'mime_type', file.mime_type,
            'size_bytes', file.size_bytes
          )
          order by version_attachment.position, version_attachment.id
        )
        from public.quote_version_attachments as version_attachment
        join public.attachments as file on file.id = version_attachment.attachment_id
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

-- 5. Serve the frozen logo through the existing token-scoped and staff-preview seams ------------------------
--
-- Same shape as resolve_quote_access_link/record_quote_link_view: every public token command re-resolves
-- the link itself rather than trusting an id carried over from a previous call.

create or replace function public.resolve_quote_access_link_logo(supplied_token_hash bytea)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null or link_row.revoked_at is not null then
    return null;
  end if;

  if link_row.expires_at is not null and link_row.expires_at <= now() then
    return null;
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  return version_row.logo_object_key;
end;
$$;

revoke all on function public.resolve_quote_access_link_logo(bytea) from public;
revoke execute on function public.resolve_quote_access_link_logo(bytea) from anon, authenticated;
grant execute on function public.resolve_quote_access_link_logo(bytea) to service_role;

-- Preview as client reads the same frozen branding a customer would see, through the same `quotes.view`
-- gate quote_customer_preview already enforces -- so the office cannot see a preview that later disagrees
-- with what the client's link actually shows.
create or replace function public.quote_preview_logo_object_key(target_quote_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
begin
  select * into quote_row from public.quotes where id = target_quote_id;

  if quote_row.id is null
     or not private.member_has_permission(
       quote_row.organization_id, (select auth.uid()), 'quotes.view'
     ) then
    raise exception 'You do not have access to this quote.' using errcode = 'insufficient_privilege';
  end if;

  select * into version_row
  from public.quote_versions
  where id = coalesce(quote_row.current_published_version_id, quote_row.draft_version_id);

  if version_row.id is null then
    return null;
  end if;

  return version_row.logo_object_key;
end;
$$;

revoke all on function public.quote_preview_logo_object_key(uuid) from public;
revoke execute on function public.quote_preview_logo_object_key(uuid) from anon;
grant execute on function public.quote_preview_logo_object_key(uuid) to authenticated;

notify pgrst, 'reload schema';
