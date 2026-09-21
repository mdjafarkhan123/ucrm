-- Onboarding & Data Portability, Part 1, step 3: the "Map columns" write path.
--
-- After the file is uploaded and parsed (step 2), the office matches each of their columns to one of our
-- fields and picks what to do with people we already have (skip or update). This RPC is the save button for
-- that screen: it records the column mapping + match action onto the batch and moves it uploaded -> mapped.
-- Nothing is imported here -- the per-row dedupe dry-run is step 4, which re-reads the file from R2.
--
-- Same shape as create_import_batch: import_batches has no update policy (rule 12), so every write lands in a
-- SECURITY DEFINER /api RPC. The route has already authenticated the caller and Zod-validated the mapping
-- (targets, match_action, no duplicate targets); this function re-checks the permission itself as the same
-- backstop every definer write uses, and derives the org from the batch rather than trusting the payload so
-- the caller cannot map a batch that is not theirs.

create or replace function public.set_import_batch_mapping(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid := (payload->>'batch_id')::uuid;
  target_batch public.import_batches;
begin
  if target_batch_id is null then
    raise exception 'batch_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  select * into target_batch from public.import_batches where id = target_batch_id;
  if not found then
    raise exception 'That import was not found.' using errcode = 'no_data_found';
  end if;

  -- Backstop the route's permission check against the batch's own organization -- never the payload -- so a
  -- member can only map an import that belongs to an org where they may create clients.
  if not private.has_permission(target_batch.organization_id, 'customers.create') then
    raise exception 'You do not have permission to change this import.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Only an un-run batch can be (re)mapped -- the office can step back from Map and change it. Once the worker
  -- has started (importing) or the batch is finished, its mapping is frozen.
  if target_batch.status not in ('uploaded', 'mapped') then
    raise exception 'This import can no longer be changed.'
      using errcode = 'invalid_parameter_value';
  end if;

  update public.import_batches
  set column_mapping = coalesce(payload->'column_mapping', '{}'::jsonb),
      match_action = payload->>'match_action',
      status = 'mapped'
  where id = target_batch_id
  returning * into target_batch;

  return target_batch;
end;
$$;

revoke all on function public.set_import_batch_mapping(jsonb) from public;
-- The database default-grants EXECUTE on new public functions to anon; the only caller is an authenticated
-- /api session, so drop the anon surface explicitly (same close-out as create_import_batch). Signed-in
-- members keep it, and the function guards itself with private.has_permission.
revoke execute on function public.set_import_batch_mapping(jsonb) from anon;
grant execute on function public.set_import_batch_mapping(jsonb) to authenticated;
