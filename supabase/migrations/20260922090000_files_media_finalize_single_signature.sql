-- Files and Media, Part 5A fix: one `finalize_file_processing`, not two.
--
-- 20260921230000 added the record-origin auto-link by replacing `finalize_file_processing` -- but it copied
-- the five-argument body from Part 3A, while Part 3B (20260921180000) had already dropped that signature and
-- replaced it with a six-argument one that carries the thumbnail key. `create or replace` on the old
-- argument list therefore did not replace anything: it created a second overload beside the current one.
--
-- Two overloads is the exact hazard the Part 3B and 4C migrations both wrote down. The worker names its
-- arguments, so it keeps reaching the six-argument version and previews still work -- but a four-argument
-- positional call now matches both and fails as "function is not unique", and the five-argument version it
-- would otherwise reach does not save a preview at all.
--
-- This drops the accidental overload and puts the auto-link where it belongs: inside the real, current
-- function. Nothing else about it changes.

drop function if exists public.finalize_file_processing(uuid, uuid, text, text, text);

create or replace function public.finalize_file_processing(
  target_file_id uuid,
  target_claim_token uuid,
  target_state text,
  target_checksum_sha256 text default null,
  target_error text default null,
  target_thumbnail_object_key text default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  claimed public.files;
  finalized public.files;
begin
  if target_state not in ('available', 'failed', 'quarantined') then
    raise exception 'A file can only finish processing as available, failed or quarantined.'
      using errcode = 'check_violation';
  end if;

  -- Belt and braces with files_available_means_verified_check: the constraint states the rule for the
  -- table, this states it at the only call site that can reach it, with a message a developer can act on.
  if target_state = 'available' and target_checksum_sha256 is null then
    raise exception 'A file cannot be made available without the checksum from its verification pass.'
      using errcode = 'check_violation';
  end if;

  -- The row is locked here rather than updated blind, because the thumbnail key has to be checked against
  -- this File's own object key before it is trusted. A claim token that no longer matches means another
  -- worker took the File over, and that result is dropped rather than applied.
  select * into claimed
  from public.files
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending'
  for update;

  if claimed.id is null then
    raise exception 'That file processing claim is no longer current.'
      using errcode = 'no_data_found';
  end if;

  -- A derivative key is always derived from the original's, so it inherits the organization prefix
  -- `register_pending_file` already checked. Anything else would let a caller point one File's preview at
  -- another organization's object.
  if target_thumbnail_object_key is not null
     and target_thumbnail_object_key is distinct from claimed.object_key || '.thumb.jpg' then
    raise exception 'That preview does not belong to this file.'
      using errcode = 'check_violation';
  end if;

  -- Only a published File keeps a preview: a failed or quarantined one has nothing safe to show.
  if target_state <> 'available' and target_thumbnail_object_key is not null then
    raise exception 'Only an available file can carry a preview.'
      using errcode = 'check_violation';
  end if;

  update public.files
  set processing_state = target_state,
      checksum_sha256 = coalesce(target_checksum_sha256, checksum_sha256),
      thumbnail_object_key = coalesce(target_thumbnail_object_key, thumbnail_object_key),
      scanned_at = case when target_state = 'available' then now() else scanned_at end,
      processing_error = case when target_state = 'available' then null else target_error end,
      claimed_at = null,
      claim_token = null
  where id = claimed.id
  returning * into finalized;

  -- Part 5A: the upload started on a CRM record, and it has just become attachable.
  --
  -- `origin_type`/`origin_id` already record where an upload entered UCRM; for a record upload that is also
  -- an instruction, because the contract forbids attaching content that has not been checked -- so the link
  -- cannot be made when the upload starts, and this is the first moment it may exist. Doing it here rather
  -- than in the route is what makes it reliable: the browser that started the upload may be closed long
  -- before the check finishes, but this statement always runs.
  --
  -- `on conflict do nothing` covers the file somebody linked by hand while it was still being checked.
  -- A `file_manager` upload carries no origin_id (files_origin_id_matches_type_check), so the whole block is
  -- skipped for a library upload -- which is the contract's "direct uploads may be attached later".
  if finalized.processing_state = 'available'
    and finalized.origin_id is not null
    and finalized.origin_type = any (
      array['client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit']
    )
  then
    insert into public.file_links (
      organization_id, file_id, entity_type, entity_id, role, created_by
    )
    values (
      finalized.organization_id, finalized.id, finalized.origin_type, finalized.origin_id,
      'attachment', finalized.uploaded_by
    )
    on conflict (file_id, entity_type, entity_id, role) do nothing;
  end if;

  return finalized;
end;
$$;

comment on function public.finalize_file_processing(uuid, uuid, text, text, text, text) is
  'Ends one processing claim: publishes the File with its checksum and any preview the pass made, or records why it failed or was quarantined. A file uploaded from a CRM record is attached to that record in the same statement that publishes it, because that is the first moment the contract allows it to be attached. Service role only.';

revoke all on function public.finalize_file_processing(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
