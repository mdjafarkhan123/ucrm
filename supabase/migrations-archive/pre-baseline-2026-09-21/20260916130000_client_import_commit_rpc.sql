-- Onboarding & Data Portability, Part 1, step 5a: the "Commit" write path.
--
-- After the office reviews the dry-run (step 4), every import_rows row sits as 'pending_review' carrying the
-- decision Review computed for it (create / update / skip / hold / error). Nothing has touched the real client
-- list yet. This RPC is the Commit button: it confirms the import in one transaction --
--
--   * refuses unless the office affirmed consent (HubSpot's own gate; import_batches.consent_affirmed_at is
--     null until then) and stamps that affirmation,
--   * settles the rows the office does NOT need a worker for immediately: skip -> 'skipped', hold -> 'held',
--     error -> 'failed' (those rows already carry their error_message from Review), and
--   * queues the rows that DO need writing: create/update -> 'ready', which the step-5b worker drains via
--     `for update skip locked` on import_rows_ready_idx. The worker must never drain a batch the office has
--     not committed -- so nothing is 'ready' until this runs.
--
-- The batch's own per-outcome counts for the Done screen are seeded here for the outcomes that are already
-- final (skipped/held/error); created_count and updated_count stay 0 for the worker to increment as it drains,
-- and the worker also adds any of its OWN failures (e.g. a row that collides with a soft-deleted client on the
-- unique index) to error_count. When a committed batch has no create/update rows at all there is nothing for
-- the worker to do, so the batch goes straight to 'completed' rather than sitting in 'importing' forever.
--
-- Same shape as set_import_batch_mapping and review_import_batch: import_rows/import_batches have no write
-- policy (rule 12), so the write lands in a SECURITY DEFINER /api RPC. The route has authenticated the caller
-- and Zod-checked consent; this function re-checks the permission itself as the same backstop every definer
-- write uses, derives the org from the batch (never the payload), and locks the batch so two commits of the
-- same import cannot interleave.

create or replace function public.commit_import_batch(payload jsonb)
returns public.import_batches
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_batch_id uuid := (payload->>'batch_id')::uuid;
  target_batch public.import_batches;
  consent_affirmed boolean := coalesce((payload->>'consent_affirmed')::boolean, false);
  skipped integer;
  held integer;
  errored integer;
  to_import integer;
begin
  if target_batch_id is null then
    raise exception 'batch_id is required.' using errcode = 'invalid_parameter_value';
  end if;

  -- Lock the batch so a second Commit of the same batch cannot interleave with ours (both would otherwise read
  -- 'reviewed', flip the rows, and double-seed the counts).
  select * into target_batch from public.import_batches where id = target_batch_id for update;
  if not found then
    raise exception 'That import was not found.' using errcode = 'no_data_found';
  end if;

  -- Backstop the route's permission check against the batch's own organization, never the payload.
  if not private.has_permission(target_batch.organization_id, 'customers.create') then
    raise exception 'You do not have permission to change this import.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Only a reviewed batch can be committed. Once committed (importing) or finished, its rows are frozen.
  if target_batch.status <> 'reviewed' then
    raise exception 'This import can no longer be committed.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Defense in depth behind the route's Zod gate: never write clients off an import the office did not
  -- explicitly affirm consent for. Distinct errcode so the route can name consent specifically.
  if not consent_affirmed then
    raise exception 'Confirm these contacts agreed to hear from you before importing.'
      using errcode = 'check_violation';
  end if;

  -- One set-based pass, scoped by batch_id (the leading column of import_rows_source_unique): move each
  -- pending_review row to its committed status. Only create/update become 'ready' for the worker.
  update public.import_rows
  set status = case planned_action
    when 'create' then 'ready'
    when 'update' then 'ready'
    when 'skip' then 'skipped'
    when 'hold' then 'held'
    when 'error' then 'failed'
    else status
  end
  where batch_id = target_batch_id
    and status = 'pending_review';

  -- Seed the Done-screen counts for the outcomes that are already final. created_count/updated_count stay 0;
  -- the worker owns those (and adds its own failures to error_count) as it drains.
  select
    count(*) filter (where planned_action = 'skip'),
    count(*) filter (where planned_action = 'hold'),
    count(*) filter (where planned_action = 'error'),
    count(*) filter (where planned_action in ('create', 'update'))
  into skipped, held, errored, to_import
  from public.import_rows
  where batch_id = target_batch_id;

  update public.import_batches
  set consent_affirmed_at = now(),
      skipped_count = skipped,
      held_count = held,
      error_count = errored,
      -- Nothing to drain -> the batch is already done; otherwise the worker finishes it.
      status = case when to_import = 0 then 'completed' else 'importing' end
  where id = target_batch_id
  returning * into target_batch;

  return target_batch;
end;
$$;

comment on function public.commit_import_batch(jsonb) is
  'Commits a reviewed client import in one transaction: refuses without an affirmed consent flag (and stamps '
  'consent_affirmed_at), settles skip/hold/error rows to their final status, queues create/update rows as '
  '''ready'' for the step-5b worker, and seeds the batch''s skipped/held/error counts. Moves the batch to '
  '''importing'', or straight to ''completed'' when there is nothing to drain. Backstops the caller permission '
  'against the batch''s own org (rule 12; SECURITY DEFINER).';

revoke all on function public.commit_import_batch(jsonb) from public;
-- The database default-grants EXECUTE on new public functions to anon; the only caller is an authenticated
-- /api session (same close-out as create_import_batch / set_import_batch_mapping). The body guards itself with
-- private.has_permission, so the authenticated_security_definer_function_executable advisor WARN is by design.
revoke execute on function public.commit_import_batch(jsonb) from anon;
grant execute on function public.commit_import_batch(jsonb) to authenticated;

notify pgrst, 'reload schema';
