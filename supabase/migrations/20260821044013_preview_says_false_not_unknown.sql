-- A draft has no published version to compare against, so `is_current_published` came back as unknown
-- rather than "no". The page has to answer a yes/no question with it.
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
