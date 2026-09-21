-- Files and Media, Part 3A: the promises the upload pipeline makes in the database itself.
--
--   1. Registration is tenant-locked -- a storage key or an uploader that does not belong to the
--      organization is refused even by a caller holding the service role.
--   2. Only a finished upload is work -- the worker claims completed uploads, exactly once each, and a
--      file that never finished uploading is never checked.
--   3. Availability is earned -- 'available' is reachable only through finalize, only with the current
--      claim, and only with the checksum that proves the object was read and scanned. The table refuses it
--      otherwise, independently of the function. A preview derivative may travel with it, but only one
--      derived from this File's own object, and only onto a File that is being published (Part 3B).
--   4. An outage is not a failure -- a released claim goes back to the queue without spending an attempt,
--      while a file that genuinely cannot be processed stops after five.
--   5. The sweep is narrow -- it collects uploads that never arrived and nothing else.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('f5000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'pipeline-a@example.test', 'test', now(), now(), now()),
  ('f5000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'pipeline-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f6000000-0000-0000-0000-000000000001', 'Pipeline Co A', 'pipeline-co-a', 'active'),
  ('f6000000-0000-0000-0000-000000000002', 'Pipeline Co B', 'pipeline-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('f6000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('f6000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000002', 'admin', 'active');

-- ---------------------------------------------------------------------------------------------------------
-- 1. Registration is tenant-locked
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.register_pending_file(
      'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000001'::uuid,
      'roof.jpg', 'image/jpeg', 1024,
      'f6000000-0000-0000-0000-000000000002/files/stolen-roof.jpg', 'file_manager')$$,
  '23514',
  'That storage key was not issued for this organization.',
  'a storage key under another organization''s prefix is refused'
);

select throws_ok(
  $$select public.register_pending_file(
      'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000002'::uuid,
      'roof.jpg', 'image/jpeg', 1024,
      'f6000000-0000-0000-0000-000000000001/files/roof.jpg', 'file_manager')$$,
  '23514',
  'That uploader is not a member of this organization.',
  'an uploader from another organization is refused'
);

select lives_ok(
  $$select public.register_pending_file(
      'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000001'::uuid,
      'roof.jpg', 'image/jpeg', 1024,
      'f6000000-0000-0000-0000-000000000001/files/roof.jpg', 'file_manager')$$,
  'a library upload for this organization registers'
);

select is(
  (select processing_state from public.files where object_key = 'f6000000-0000-0000-0000-000000000001/files/roof.jpg'),
  'pending',
  'a newly registered file is pending, never available'
);

select ok(
  (select upload_completed_at is null from public.files
   where object_key = 'f6000000-0000-0000-0000-000000000001/files/roof.jpg'),
  'a newly registered file has no completed upload yet'
);

-- The approved ceiling, proved at both ends.
select lives_ok(
  $$select public.register_pending_file(
      'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000001'::uuid,
      'big.pdf', 'application/pdf', 104857600,
      'f6000000-0000-0000-0000-000000000001/files/big.pdf', 'file_manager')$$,
  'a file of exactly 100 MB is accepted'
);

select throws_ok(
  $$select public.register_pending_file(
      'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000001'::uuid,
      'huge.pdf', 'application/pdf', 104857601,
      'f6000000-0000-0000-0000-000000000001/files/huge.pdf', 'file_manager')$$,
  '23514',
  null,
  'a file over 100 MB is refused by the table'
);

-- ---------------------------------------------------------------------------------------------------------
-- 2. Only a finished upload is work
-- ---------------------------------------------------------------------------------------------------------

-- Nothing has reported its bytes yet, so there is nothing to check.
select is(
  (select count(*)::integer from public.claim_file_processing_jobs(10)),
  0,
  'an upload whose bytes never arrived is never claimed'
);

select throws_ok(
  $$select public.complete_file_upload(
      (select id from public.files where object_key = 'f6000000-0000-0000-0000-000000000001/files/roof.jpg'),
      'f6000000-0000-0000-0000-000000000001'::uuid,
      'f5000000-0000-0000-0000-000000000002'::uuid)$$,
  'P0002',
  'That upload is not waiting to be finished.',
  'another member cannot finish someone else''s upload'
);

select lives_ok(
  $$select public.complete_file_upload(
      (select id from public.files where object_key = 'f6000000-0000-0000-0000-000000000001/files/roof.jpg'),
      'f6000000-0000-0000-0000-000000000001'::uuid,
      'f5000000-0000-0000-0000-000000000001'::uuid)$$,
  'the uploader can report that the bytes arrived'
);

select throws_ok(
  $$select public.complete_file_upload(
      (select id from public.files where object_key = 'f6000000-0000-0000-0000-000000000001/files/roof.jpg'),
      'f6000000-0000-0000-0000-000000000001'::uuid,
      'f5000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0002',
  'That upload is not waiting to be finished.',
  'reporting the same upload twice is refused'
);

-- ---------------------------------------------------------------------------------------------------------
-- 3. Claiming is exclusive, and availability is earned
-- ---------------------------------------------------------------------------------------------------------

create temporary table claimed_file as
select id, claim_token from public.claim_file_processing_jobs(10);

select is(
  (select count(*)::integer from claimed_file),
  1,
  'the completed upload is the one thing claimed'
);

select is(
  (select count(*)::integer from public.claim_file_processing_jobs(10)),
  0,
  'a second claim finds nothing -- a claimed file is not handed out twice'
);

select is(
  (select processing_attempts from public.files where id = (select id from claimed_file)),
  1::smallint,
  'claiming counts an attempt'
);

select throws_ok(
  $$select public.finalize_file_processing(
      (select id from claimed_file), gen_random_uuid(), 'available',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$,
  'P0002',
  'That file processing claim is no longer current.',
  'a stale claim token cannot finalize a file'
);

select throws_ok(
  $$select public.finalize_file_processing(
      (select id from claimed_file), (select claim_token from claimed_file), 'available')$$,
  '23514',
  'A file cannot be made available without the checksum from its verification pass.',
  'a file cannot be published without the checksum proving it was read'
);

select throws_ok(
  $$select public.finalize_file_processing(
      (select id from claimed_file), (select claim_token from claimed_file), 'deleted')$$,
  '23514',
  'A file can only finish processing as available, failed or quarantined.',
  'processing cannot end in a state the contract does not define'
);

-- The table's own rule, independent of the function: this is the update a bug or a stray service-role
-- script would attempt, and it is refused because the row has no scan behind it.
select throws_ok(
  $$update public.files set processing_state = 'available'
    where id = (select id from claimed_file)$$,
  '23514',
  null,
  'a file cannot be flipped to available without a scan time and a checksum'
);

-- Part 3B: the preview derivative travels back with the rest of the pass, and only if it really belongs
-- to this File's own object.
select throws_ok(
  $$select public.finalize_file_processing(
      (select id from claimed_file), (select claim_token from claimed_file), 'available',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', null,
      'f6000000-0000-0000-0000-000000000002/files/someone-else.jpg.thumb.jpg')$$,
  '23514',
  'That preview does not belong to this file.',
  'a preview key that is not derived from this file''s object is refused'
);

select throws_ok(
  $$select public.finalize_file_processing(
      (select id from claimed_file), (select claim_token from claimed_file), 'quarantined',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'blocked',
      'f6000000-0000-0000-0000-000000000001/files/roof.jpg.thumb.jpg')$$,
  '23514',
  'Only an available file can carry a preview.',
  'a blocked file cannot carry a preview'
);

select lives_ok(
  $$select public.finalize_file_processing(
      (select id from claimed_file), (select claim_token from claimed_file), 'available',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', null,
      'f6000000-0000-0000-0000-000000000001/files/roof.jpg.thumb.jpg')$$,
  'a scanned, checksummed file becomes available'
);

select is(
  (select thumbnail_object_key from public.files where id = (select id from claimed_file)),
  'f6000000-0000-0000-0000-000000000001/files/roof.jpg.thumb.jpg',
  'the published file records where its preview lives'
);

select is(
  (select processing_state from public.files where id = (select id from claimed_file)),
  'available',
  'the file is now available'
);

select ok(
  (select scanned_at is not null from public.files where id = (select id from claimed_file)),
  'availability records when the scan happened'
);

select ok(
  (select claim_token is null from public.files where id = (select id from claimed_file)),
  'finishing releases the claim'
);

-- ---------------------------------------------------------------------------------------------------------
-- 4. An outage is not the file's fault
-- ---------------------------------------------------------------------------------------------------------

select public.register_pending_file(
  'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000001'::uuid,
  'outage.pdf', 'application/pdf', 2048,
  'f6000000-0000-0000-0000-000000000001/files/outage.pdf', 'file_manager');

select public.complete_file_upload(
  (select id from public.files where object_key = 'f6000000-0000-0000-0000-000000000001/files/outage.pdf'),
  'f6000000-0000-0000-0000-000000000001'::uuid,
  'f5000000-0000-0000-0000-000000000001'::uuid);

create temporary table outage_file as
select id, claim_token from public.claim_file_processing_jobs(10);

select public.release_file_processing_claim(
  (select id from outage_file), (select claim_token from outage_file));

select is(
  (select processing_attempts from public.files where id = (select id from outage_file)),
  0::smallint,
  'releasing a claim gives the attempt back, so an outage cannot fail a good file'
);

select is(
  (select processing_state from public.files where id = (select id from outage_file)),
  'pending',
  'a released file is still pending, never published'
);

select is(
  (select count(*)::integer from public.claim_file_processing_jobs(10)),
  1,
  'a released file is immediately claimable again'
);

-- Five spent attempts is a file that will not process. It stops, with something the contractor can read.
update public.files
set processing_attempts = 5, claimed_at = null, claim_token = null
where id = (select id from outage_file);

select is(
  (select count(*)::integer from public.claim_file_processing_jobs(10)),
  0,
  'a file that has failed five passes is not claimed again'
);

select is(
  (select processing_state from public.files where id = (select id from outage_file)),
  'failed',
  'it is retired as failed rather than retried forever'
);

select ok(
  (select processing_error is not null from public.files where id = (select id from outage_file)),
  'and it carries a reason the contractor can read'
);

-- ---------------------------------------------------------------------------------------------------------
-- 5. The abandoned sweep is narrow
-- ---------------------------------------------------------------------------------------------------------

-- Three candidates: one genuinely abandoned, one abandoned but linked to a record, one that did finish.
select public.register_pending_file(
  'f6000000-0000-0000-0000-000000000001'::uuid, 'f5000000-0000-0000-0000-000000000001'::uuid,
  'ghost.pdf', 'application/pdf', 2048,
  'f6000000-0000-0000-0000-000000000001/files/ghost.pdf', 'file_manager');

update public.files set created_at = now() - interval '48 hours'
where object_key = 'f6000000-0000-0000-0000-000000000001/files/ghost.pdf';

-- The 100 MB file from earlier never completed either, but it is young, so it must survive.
create temporary table swept as
select id, object_key from public.sweep_abandoned_file_uploads(24, 100);

select is(
  (select count(*)::integer from swept),
  1,
  'only the upload that never arrived is swept'
);

select is(
  (select object_key from swept),
  'f6000000-0000-0000-0000-000000000001/files/ghost.pdf',
  'and it hands back the storage key so the object behind it can be deleted'
);

select is(
  (select count(*)::integer from public.files
   where object_key = 'f6000000-0000-0000-0000-000000000001/files/big.pdf'),
  1,
  'an unfinished upload inside the grace window is left alone'
);

select is(
  (select processing_state from public.files where id = (select id from claimed_file)),
  'available',
  'the sweep never touches a finished file'
);

-- ---------------------------------------------------------------------------------------------------------
-- 6. None of this is reachable from the browser
-- ---------------------------------------------------------------------------------------------------------

select ok(
  not has_function_privilege('authenticated',
    'public.register_pending_file(uuid,uuid,text,text,bigint,text,text,uuid,uuid)', 'execute'),
  'a signed-in user cannot register a file directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.finalize_file_processing(uuid,uuid,text,text,text,text)', 'execute'),
  'a signed-in user cannot publish a file directly'
);

select ok(
  not has_function_privilege('authenticated', 'public.claim_file_processing_jobs(integer)', 'execute'),
  'a signed-in user cannot claim processing work'
);

select ok(
  not has_function_privilege('anon', 'public.sweep_abandoned_file_uploads(integer,integer)', 'execute'),
  'an anonymous caller cannot run the sweep'
);

select * from finish();
rollback;
