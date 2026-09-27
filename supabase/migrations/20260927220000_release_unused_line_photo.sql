-- Letting go of a line photo a save just dropped.
--
-- A line photo is one File that several records point at: a quote copies its request's photo, a job its
-- quote's, a visit or an invoice its job's. So "this line no longer shows the photo" does not mean "nobody
-- does". Moving it straight to Trash (what the editor used to do) also stripped it from every other record
-- still showing it -- a request's photo vanished from the draft quote made from it.
--
-- This moves the File to Trash only when it is truly an orphan: an upload made as a line photo, never filed
-- into a library folder, and used by nothing at all -- no line, no customer file, no report photo, no link,
-- no share. Anything else is left exactly as it is and the call answers false. Reference-counted cleanup,
-- the same rule Active Storage and similar libraries use before purging a shared blob.

create or replace function public.release_line_photo(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  file_row public.files;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  -- Locked so a save claiming the photo again cannot slip between the check and the Trash.
  select * into file_row
  from public.files file
  where file.id = target_file_id
    and file.organization_id = target_organization_id
  for update;

  if file_row.id is null
     or file_row.trashed_at is not null
     or file_row.origin_role is distinct from 'line_photo'
     or file_row.folder_id is not null then
    return false;
  end if;

  if exists (select 1 from public.file_links where organization_id = target_organization_id and file_id = target_file_id)
     or exists (select 1 from public.request_pricing_lines where organization_id = target_organization_id and image_file_id = target_file_id)
     or exists (select 1 from public.quote_version_lines where organization_id = target_organization_id and image_file_id = target_file_id)
     or exists (select 1 from public.job_line_items where organization_id = target_organization_id and image_file_id = target_file_id)
     or exists (select 1 from public.job_visit_line_items where organization_id = target_organization_id and image_file_id = target_file_id)
     or exists (select 1 from public.quote_version_attachments where organization_id = target_organization_id and file_id = target_file_id)
     or exists (select 1 from public.job_report_photos where organization_id = target_organization_id and file_id = target_file_id)
     or exists (select 1 from public.attachments where organization_id = target_organization_id and file_id = target_file_id)
     or exists (select 1 from public.file_share_items where organization_id = target_organization_id and file_id = target_file_id)
  then
    return false;
  end if;

  update public.files
  set trashed_at = now(),
      trashed_by = target_actor_id
  where id = target_file_id
    and organization_id = target_organization_id;

  return true;
end;
$$;

revoke all on function public.release_line_photo(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.release_line_photo(uuid, uuid, uuid) to service_role;
