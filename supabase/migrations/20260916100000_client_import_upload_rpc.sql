-- Onboarding & Data Portability, Part 1, step 2: the upload/parse write path.
--
-- The import screens read import_batches directly (org-scoped RLS SELECT), but the tables carry NO insert
-- policy on purpose (rule 12): every write lands through a SECURITY DEFINER /api RPC. This is that RPC for the
-- first screen -- it records one uploaded, already-parsed file as a draft batch.
--
-- The /api route has already: authenticated the caller, checked `customers.create`, enforced the ~2.5 MB /
-- 5,000-row caps, parsed the CSV, and written the file to R2. This function only records the result. It is
-- security definer (the table has no insert policy for it to satisfy), so it re-checks the permission itself
-- rather than trust the route -- the same backstop every other definer write uses -- and stamps created_by
-- from auth.uid() rather than from the payload, so the caller cannot claim to be someone else.

create or replace function public.create_import_batch(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid := (payload->>'organization_id')::uuid;
  created_batch public.import_batches;
begin
  if target_organization_id is null then
    raise exception 'organization_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  -- Backstop the route's permission check. Importing clients is a create action, so it rides the same
  -- `customers.create` key the single-client create path uses.
  if not private.has_permission(target_organization_id, 'customers.create') then
    raise exception 'You do not have permission to import clients here.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.import_batches (
    organization_id,
    created_by,
    entity_type,
    source_filename,
    storage_object_key,
    file_row_count
  )
  values (
    target_organization_id,
    (select auth.uid()),
    'client',
    payload->>'source_filename',
    payload->>'storage_object_key',
    (payload->>'file_row_count')::integer
  )
  returning * into created_batch;

  return created_batch;
end;
$$;

revoke all on function public.create_import_batch(jsonb) from public;
-- The database default-grants EXECUTE on new public functions to anon; the only caller is an authenticated
-- /api session, so drop the anon surface explicitly (same close-out as the nine functions in
-- 20260913120000). Signed-in members keep it, and the function guards itself with private.has_permission.
revoke execute on function public.create_import_batch(jsonb) from anon;
grant execute on function public.create_import_batch(jsonb) to authenticated;
