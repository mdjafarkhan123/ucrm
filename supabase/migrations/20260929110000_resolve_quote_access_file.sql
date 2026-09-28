-- /q/[token]/files/[attachmentId] authorized a file by building the whole customer document with
-- resolve_quote_access_link and checking the id against it: every line, attachment and total, once per
-- photo. This answers only "does this link's version name this file?" with the same link checks as
-- resolve_quote_access_link_logo, and the same file rules as private.quote_customer_document: a line photo
-- must be live and processed, an attachment must be marked customer-visible and live.
--
-- An expired link returns no row, so the route answers 404 rather than failing on the { expired } marker.
create or replace function public.resolve_quote_access_file(supplied_token_hash bytea, target_file_id uuid)
returns table (object_key text, thumbnail_object_key text, mime_type text, display_name text)
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
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 or target_file_id is null then
    return;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null or link_row.revoked_at is not null then
    return;
  end if;

  if link_row.expires_at is not null and link_row.expires_at <= now() then
    return;
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id;
  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return;
  end if;

  return query
  select file.object_key, file.thumbnail_object_key, file.mime_type, file.display_name
  from public.files as file
  where file.organization_id = version_row.organization_id
    and file.id = target_file_id
    and file.trashed_at is null
    and (
      exists (
        select 1 from public.quote_version_lines as line
        where line.organization_id = version_row.organization_id
          and line.quote_id = version_row.quote_id
          and line.quote_version_id = version_row.id
          and line.image_file_id = file.id
          and file.processing_state = 'available'
      )
      or exists (
        select 1 from public.quote_version_attachments as version_attachment
        where version_attachment.organization_id = version_row.organization_id
          and version_attachment.quote_id = version_row.quote_id
          and version_attachment.quote_version_id = version_row.id
          and version_attachment.file_id = file.id
          and version_attachment.customer_visible
      )
    );
end;
$$;

revoke all on function public.resolve_quote_access_file(bytea, uuid) from public, anon, authenticated;
grant execute on function public.resolve_quote_access_file(bytea, uuid) to service_role;
