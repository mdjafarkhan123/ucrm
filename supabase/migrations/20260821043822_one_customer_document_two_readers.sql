-- Quotes Part 5B1: the staff preview reads the customer's document, not a copy of it.
--
-- `resolve_quote_access_link` already knew how to build the one thing a customer may see. Preview as
-- client needs exactly that document, for a person who is signed in and holds no token - and for a quote
-- that may not be published yet, because that is when a preview is most useful.
--
-- Writing the payload out a second time would be the whole risk of this feature: two builders drift, and
-- the day they drift is the day the customer copy shows something the preview never did. So the builder
-- moves into one private function and both readers call it. There is still exactly one place in this
-- database that decides what a customer is allowed to see.

-- 1. The one builder ---------------------------------------------------------------------------------------

-- Invoker, not definer, and private: it is only ever reached from inside a security definer function that
-- has already decided the caller is allowed to be here. It makes no access decision of its own - it is
-- handed the rows, and told whether money is included.
create or replace function private.quote_customer_document(
  quote_row public.quotes,
  version_row public.quote_versions,
  recipient_name text,
  recipient_email text,
  include_money boolean
)
returns jsonb
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
    'business', jsonb_build_object('name', version_row.organization_name),
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
    'packages', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', package.id, 'position', package.position, 'name', package.name,
            'description', package.description, 'is_recommended', package.is_recommended
          )
          order by package.position, package.id
        )
        from public.quote_version_packages as package
        where package.organization_id = version_row.organization_id
          and package.quote_id = version_row.quote_id
          and package.quote_version_id = version_row.id
      ),
      '[]'::jsonb
    ),
    -- Every child read names organization and quote as well as the version, because that is the order the
    -- existing child indexes are built in - filtering on the version alone would scan the table.
    --
    -- A hidden switch means the number never enters the payload, rather than being hidden in the browser
    -- where anyone can read it back out of the page source. `include_money` closes the price switches for
    -- a member who may open a quote but may not see its prices, and it closes them in the same place and
    -- for the same reason.
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', line.id, 'position', line.position, 'line_kind', line.line_kind,
            'selection_kind', line.selection_kind, 'package_id', line.package_id,
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
    ) else null end
  );
$$;

comment on function private.quote_customer_document(
  public.quotes, public.quote_versions, text, text, boolean
) is
  'The only definition of what a customer may see. Called by public.resolve_quote_access_link for the '
  'customer and by public.quote_customer_preview for staff. No cost, no margin, no catalog source, no '
  'private file and no second recipient may ever be added here.';

revoke all on function private.quote_customer_document(
  public.quotes, public.quote_versions, text, text, boolean
) from public, anon, authenticated, service_role;

-- 2. The customer's reader, now one copy shorter -------------------------------------------------------------

-- Unchanged in behavior: same checks, same failures, same shape. It simply no longer carries its own
-- copy of the document.
create or replace function public.resolve_quote_access_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  recipient_row public.quote_recipients;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null
     or link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
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

  select * into recipient_row from public.quote_recipients where id = link_row.recipient_id;

  return private.quote_customer_document(
    quote_row, version_row, recipient_row.display_name, recipient_row.email, true
  );
end;
$$;

-- 3. The staff preview -----------------------------------------------------------------------------------

-- Preview as client, for somebody who is signed in. It mints nothing: no recipient row, no link, no
-- token. It reads the version the customer would be looking at - the published one - and falls back to
-- the draft when there is none, because checking a quote before sending it is when a preview earns its
-- place. Jobber offers this in every status including Draft, and so do we.
--
-- Money follows the same permission as the rest of the app. A member who may open a quote but not see
-- its prices gets the document with the prices left out of the payload, not hidden in the browser.
create or replace function public.quote_customer_preview(target_quote_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  quote_row public.quotes;
  version_row public.quote_versions;
  client_name text;
  client_email text;
  can_see_price boolean;
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

  can_see_price := private.member_has_permission(
    quote_row.organization_id, (select auth.uid()), 'quotes.view_price'
  );

  -- Who the document is addressed to. A draft has not been sent to anybody yet, so it is addressed to
  -- the client on the quote - the same address issuing a link would use.
  select client.display_name,
         (
           select lower(trim(method.value))
           from public.client_contact_methods as method
           where method.organization_id = quote_row.organization_id
             and method.client_id = quote_row.client_id
             and method.kind = 'email'
           order by method.is_primary desc, method.created_at
           limit 1
         )
    into client_name, client_email
  from public.clients as client
  where client.organization_id = quote_row.organization_id
    and client.id = quote_row.client_id;

  return jsonb_build_object(
    'document', private.quote_customer_document(
      quote_row,
      version_row,
      coalesce(nullif(trim(client_name), ''), client_email, 'Your client'),
      client_email,
      can_see_price
    ),
    'preview', jsonb_build_object(
      'version_status', version_row.status,
      'version_number', version_row.version_number,
      'is_current_published', coalesce(version_row.id = quote_row.current_published_version_id, false),
      'prices_withheld', not can_see_price
    )
  );
end;
$$;

comment on function public.quote_customer_preview(uuid) is
  'Preview as client. Returns the same customer document the token page renders, for a signed-in member '
  'with quotes.view, without creating a recipient or a link. Prices are withheld from the payload unless '
  'the member holds quotes.view_price.';

revoke all on function public.quote_customer_preview(uuid) from public;
revoke execute on function public.quote_customer_preview(uuid) from anon;
grant execute on function public.quote_customer_preview(uuid) to authenticated;
