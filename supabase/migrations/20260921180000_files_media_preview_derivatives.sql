-- Files and Media, Part 3B: the safe preview derivative.
--
-- A thumbnail is not a File. It is a small JPEG the pipeline makes from the original, stored beside it at
-- `<object key>.thumb.jpg`, so a grid of a hundred photos costs a few hundred kilobytes instead of the
-- hundreds of megabytes the originals weigh. It never gets a row of its own, never gains links, and is
-- deleted with the File it belongs to.
--
-- Only one thing changes in the database: `finalize_file_processing` can now carry the derivative's key
-- back with the rest of what the pass learned, so a File becomes available and gains its preview in the
-- same statement rather than in a second write that could fail on its own.

-- The argument list changes, so the old function is dropped rather than replaced -- `create or replace`
-- with an extra defaulted parameter would leave two overloads behind and make every call ambiguous.
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

  return finalized;
end;
$$;

comment on function public.finalize_file_processing(uuid, uuid, text, text, text, text) is
  'The only path from pending to available. Requires the current claim token and, for availability, the checksum proving the object was read and scanned. Carries the preview derivative key, which must be the one derived from this File''s own object. Service role only.';

-- Supabase grants execute on new public functions to anon and authenticated by default. This is a
-- privileged server-side command; the browser reaches it only through the worker route.
revoke all on function public.finalize_file_processing(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
