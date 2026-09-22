-- Files and Media, Part 5A: a record's own files come from the catalog.
--
-- Part 4 gave the library its workspace and gave every record a way to reuse what is already stored. This
-- part turns the relationship the other way round: a CRM record's file area stops being its own little pile
-- of `attachments` rows and becomes a view of the catalog, filtered to that record's links.
--
-- Two commands are missing for that to work, and this migration adds both.
--
--   1. Taking a file off a record. Attaching has existed since Part 4C; detaching has not, because the
--      workspace's own Trash detaches everything at once. A record needs the single, narrow version: remove
--      this one use, leave the File and every other use alone.
--   2. Linking an upload that started on a record. When the office drags a photo onto a client, the upload
--      records that client as its origin, but nothing puts it on the client -- the file is pending at that
--      moment and the contract forbids attaching pending content. The link therefore has to be made at the
--      one moment the file becomes attachable: when the worker publishes it.
--
-- No table, column, constraint, policy or table grant is touched. Rolling back means dropping
-- `detach_file_from_record` and restoring the previous `finalize_file_processing` body from 20260921170000.

-- ---------------------------------------------------------------------------------------------------------
-- Detach
-- ---------------------------------------------------------------------------------------------------------

-- One use off one record. The calling route has already checked that this person may write to the record --
-- taking a document off a quote is an edit of the quote, the same gate attaching uses -- so what is checked
-- here is what the route cannot take on trust: that the actor belongs to the organization, and that the link
-- being removed is this organization's.
--
-- A protected link is refused by `file_links_protect_history` rather than by a test here, on purpose: that
-- trigger is the one place that rule lives, so a caller written later cannot route around it. Its message is
-- already a sentence written for the contractor.
--
-- Detaching something that is not there is not an error. The record's file area can only ask to remove a row
-- it has just drawn, so "it is already gone" -- a colleague got there first, a double-click -- is the state
-- the caller asked for, and `false` says so without making the contractor read a failure.
create or replace function public.detach_file_from_record(
  target_organization_id uuid,
  target_file_id uuid,
  target_actor_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_role text default 'attachment'
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  removed_id uuid;
begin
  perform private.assert_file_actor(target_organization_id, target_actor_id);

  delete from public.file_links link
  where link.organization_id = target_organization_id
    and link.file_id = target_file_id
    and link.entity_type = target_entity_type
    and link.entity_id = target_entity_id
    and link.role = target_role
  returning link.id into removed_id;

  return removed_id is not null;
end;
$$;

comment on function public.detach_file_from_record(uuid, uuid, uuid, text, uuid, text) is
  'Removes one use of a File from one CRM record. The File itself, its stored object, and every other use are untouched. Returns false when the link was already gone. A use the customer has already received is refused by file_links_protect_history. Service role only: the calling route checks the caller may write to that record first.';

-- Same posture as every other Files command: the service role calls it from a route that has already checked
-- the permission, and a signed-in user cannot reach it directly.
revoke all on function public.detach_file_from_record(uuid, uuid, uuid, text, uuid, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- A record-origin upload joins its record when it is published
-- ---------------------------------------------------------------------------------------------------------

-- Unchanged from 20260921170000 except for the final block. `origin_type`/`origin_id` already record where an
-- upload entered UCRM; until now that was only a label on the File. For an upload that started on a record it
-- is also an instruction: put this file on that record as soon as it is safe to.
--
-- Doing it here rather than in the route is what makes it true. The browser that started the upload may be
-- closed, the tab may have moved on, and the check may take a minute; the one moment that always happens, for
-- every upload, is this statement. `on conflict do nothing` keeps a re-publish -- or a contractor who attached
-- it by hand from the picker while it was still being checked -- from being an error.
--
-- `file_manager` origins carry no `origin_id` (files_origin_id_matches_type_check), so the whole block is
-- skipped for a library upload, which is exactly the contract's "direct uploads may be attached later".
create or replace function public.finalize_file_processing(
  target_file_id uuid,
  target_claim_token uuid,
  target_state text,
  target_checksum_sha256 text default null,
  target_error text default null
)
returns public.files
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
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

  update public.files
  set processing_state = target_state,
      checksum_sha256 = coalesce(target_checksum_sha256, checksum_sha256),
      scanned_at = case when target_state = 'available' then now() else scanned_at end,
      processing_error = case when target_state = 'available' then null else target_error end,
      claimed_at = null,
      claim_token = null
  where id = target_file_id
    and claim_token = target_claim_token
    and processing_state = 'pending'
  returning * into finalized;

  if finalized.id is null then
    raise exception 'That file processing claim is no longer current.'
      using errcode = 'no_data_found';
  end if;

  -- The upload started on a record, and it has just become attachable. `created_by` is the person who
  -- uploaded it, because they are the one who put it there -- the worker is only the moment it became safe.
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

comment on function public.finalize_file_processing(uuid, uuid, text, text, text) is
  'Ends one processing claim: publishes the File with its checksum, or records why it failed or was quarantined. A file uploaded from a CRM record is attached to that record in the same statement that publishes it, because that is the first moment the contract allows it to be attached. Service role only.';

revoke all on function public.finalize_file_processing(uuid, uuid, text, text, text)
  from public, anon, authenticated;
