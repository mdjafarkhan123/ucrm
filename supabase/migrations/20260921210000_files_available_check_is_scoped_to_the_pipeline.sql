-- Files and Media: scope `files_available_means_verified_check` to the pipeline's own objects.
--
-- Part 3A added this constraint `not valid`, to exempt the months of existing attachments the Part 2
-- backfill marked available without a scan they never had. `not valid` does less than it reads like: it
-- skips the one-off scan of existing rows, but Postgres still enforces the constraint on every later INSERT
-- *and UPDATE*. So every one of those legacy files became un-editable the moment it was added -- renaming,
-- moving, trashing or restoring one re-checks the whole row and is refused.
--
-- That was recorded as a defect blocking the Part 5 backfill, and Jafar chose on 2026-09-21 to fix it by
-- scoping the constraint to the pipeline's own `<organization>/files/` prefix. It turns out to block the
-- Part 4 manage actions too, on every file a contractor has today, so the approved fix lands here instead.
--
-- Scoping by object key is the honest line rather than a convenient one. The key prefix is minted
-- server-side from the organization id and re-checked inside `register_pending_file`, so "was this object
-- created by the verification pipeline" is a fact about the row and not a flag anybody can set. Files under
-- that prefix must still carry a scan time and a checksum to be available -- and because the exemption is
-- now precise, the constraint can be validated instead of left permanently unproven.

alter table public.files
  drop constraint if exists files_available_means_verified_check;

alter table public.files
  add constraint files_available_means_verified_check
  check (
    processing_state <> 'available'
    or object_key not like organization_id::text || '/files/%'
    or (scanned_at is not null and checksum_sha256 is not null)
  )
  not valid;

-- Separate from the ADD so the table is not held under an ACCESS EXCLUSIVE lock for the scan. Nothing in
-- the catalog violates it today: every file is a legacy object, and no pipeline upload has ever reached
-- 'available' without both proofs.
alter table public.files
  validate constraint files_available_means_verified_check;

comment on constraint files_available_means_verified_check on public.files is
  'An available file created by the upload pipeline (key under <organization>/files/) has been scanned and checksummed. Objects the Part 2 backfill adopted from `attachments` predate the pipeline and are outside it.';
