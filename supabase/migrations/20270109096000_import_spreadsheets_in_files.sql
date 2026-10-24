-- Import spreadsheets belong to the business's File Manager (Jafar, 2026-10-24: "whatever asset they import
-- ultimately should belong to that, so they can manage it"). HubSpot keeps an import's original file in its file
-- storage and lets the account download it from import history.
--
-- Decided with Jafar the same day: the spreadsheet is an ordinary File, visible to everyone who can see Files, in an
-- "Imports" folder, and it stays until the business moves it to Trash (Trash empties itself after 30 days). A
-- permanent customer delete does not edit it, as HubSpot's delete does not reach free-form files.
--
-- This replaces the Files contract's earlier exclusion of "temporary imports". The per-row error file the import
-- writes stays on the import page.
--
-- 1. A File may now come from an import; its origin_id is the import batch.
-- 2. register_import_file files one batch's spreadsheet as a pending, upload-complete File, so the ordinary
--    processing worker checks and publishes it like any other upload.

alter table public.files drop constraint files_origin_type_check;
alter table public.files add constraint files_origin_type_check check (origin_type = any (array[
  'file_manager', 'client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit', 'invoice',
  'organization', 'marketing_campaign', 'catalog_item', 'import'
]));

-- One File per import batch.
create unique index if not exists files_import_origin_unique_idx
  on public.files (organization_id, origin_id) where origin_type = 'import';

create or replace function public.register_import_file(
  target_organization_id uuid,
  target_batch_id uuid,
  target_uploaded_by uuid,
  target_size_bytes bigint
) returns public.files
  language plpgsql security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  batch public.import_batches;
  folder_id uuid;
  filed public.files;
begin
  select * into batch
  from public.import_batches
  where organization_id = target_organization_id and id = target_batch_id;
  if batch.id is null then
    raise exception 'That import could not be found.' using errcode = 'P0002';
  end if;

  -- The spreadsheet keeps the key the import itself reads; it was minted server-side under this organization's
  -- import prefix, which is re-checked here.
  if batch.storage_object_key not like target_organization_id::text || '/client-imports/%'
    and batch.storage_object_key not like target_organization_id::text || '/opening-balance-imports/%' then
    raise exception 'That storage key was not issued for this organization''s imports.'
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from public.organization_members as member
    where member.organization_id = target_organization_id and member.user_id = target_uploaded_by
  ) then
    raise exception 'That uploader is not a member of this organization.' using errcode = 'check_violation';
  end if;

  select * into filed
  from public.files
  where organization_id = target_organization_id and origin_type = 'import' and origin_id = target_batch_id;
  if filed.id is not null then
    return filed;
  end if;

  -- The "Imports" folder is an ordinary folder: the business may rename or remove it, and the next import makes
  -- a new one.
  insert into public.file_folders (organization_id, name, created_by)
  values (target_organization_id, 'Imports', target_uploaded_by)
  on conflict (organization_id, lower(btrim(name))) do nothing;
  select folder.id into folder_id
  from public.file_folders as folder
  where folder.organization_id = target_organization_id and lower(btrim(folder.name)) = 'imports';

  insert into public.files (
    organization_id, folder_id, display_name, mime_type, size_bytes, object_key, origin_type, origin_id,
    origin_role, processing_state, uploaded_by, upload_completed_at
  ) values (
    target_organization_id, folder_id, left(btrim(batch.source_filename), 255), 'text/csv', target_size_bytes,
    batch.storage_object_key, 'import', batch.id, 'attachment', 'pending', target_uploaded_by, now()
  )
  returning * into filed;

  return filed;
end;
$$;

alter function public.register_import_file(uuid, uuid, uuid, bigint) owner to postgres;
revoke all on function public.register_import_file(uuid, uuid, uuid, bigint) from public, anon, authenticated;
grant execute on function public.register_import_file(uuid, uuid, uuid, bigint) to service_role;

comment on function public.register_import_file(uuid, uuid, uuid, bigint) is
  'Files an import batch''s uploaded spreadsheet in the File Manager''s Imports folder as a pending File for the processing worker to check. Returns the existing File on a repeat call.';
