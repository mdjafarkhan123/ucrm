-- Files and Media, Part 5A: the promises a record's own file area makes in the database itself.
--
--   1. Detaching is tenant-locked -- an actor from another organization is refused, and another
--      organization's link cannot be removed even by a caller holding the service role.
--   2. Detaching removes one use and nothing else -- the File, its stored object, and its other uses stay.
--   3. Detaching something already gone is not an error; it answers false.
--   4. A use the customer already received cannot be detached.
--   5. An upload that started on a record joins that record the moment the worker publishes it, with the
--      person who uploaded it recorded as the one who put it there.
--   6. A library upload joins nothing, and neither does a failed or quarantined record upload.
--   7. Publishing a file somebody has already linked by hand leaves one use, not two.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'adopt-a@example.test', 'test', now(), now(), now()),
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'adopt-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f2000000-0000-0000-0000-000000000001', 'Adopt Co A', 'adopt-co-a', 'active'),
  ('f2000000-0000-0000-0000-000000000002', 'Adopt Co B', 'adopt-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002', 'admin', 'active');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values
  ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Dee Dawson', 'customer'),
  ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'Eve Elm', 'customer');

-- One published library file to attach and detach by hand.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, origin_id, processing_state, uploaded_by, scanned_at, checksum_sha256)
values
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'manual.pdf',
   'application/pdf', 4096, 'f2000000-0000-0000-0000-000000000001/files/manual.pdf',
   'file_manager', null, 'available', 'f1000000-0000-0000-0000-000000000001', now(), repeat('a', 64));

-- Four uploads waiting for the worker: one started on a client, one started in the library, one that is
-- going to fail its checks, and one somebody has already linked to the client by hand.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, origin_id, processing_state, uploaded_by, claimed_at, claim_token)
values
  ('f4000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'from-client.jpg',
   'image/jpeg', 2048, 'f2000000-0000-0000-0000-000000000001/files/from-client.jpg',
   'client', 'f3000000-0000-0000-0000-000000000001', 'pending', 'f1000000-0000-0000-0000-000000000001',
   now(), 'f5000000-0000-0000-0000-000000000002'),
  ('f4000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000001', 'from-library.jpg',
   'image/jpeg', 2048, 'f2000000-0000-0000-0000-000000000001/files/from-library.jpg',
   'file_manager', null, 'pending', 'f1000000-0000-0000-0000-000000000001',
   now(), 'f5000000-0000-0000-0000-000000000003'),
  ('f4000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-000000000001', 'infected.jpg',
   'image/jpeg', 2048, 'f2000000-0000-0000-0000-000000000001/files/infected.jpg',
   'client', 'f3000000-0000-0000-0000-000000000001', 'pending', 'f1000000-0000-0000-0000-000000000001',
   now(), 'f5000000-0000-0000-0000-000000000004'),
  ('f4000000-0000-0000-0000-000000000005', 'f2000000-0000-0000-0000-000000000001', 'raced.jpg',
   'image/jpeg', 2048, 'f2000000-0000-0000-0000-000000000001/files/raced.jpg',
   'client', 'f3000000-0000-0000-0000-000000000002', 'pending', 'f1000000-0000-0000-0000-000000000001',
   now(), 'f5000000-0000-0000-0000-000000000005');

-- The library file, on both clients. One of those uses is then frozen the way an issued document freezes it.
-- Setup runs inside a DO block rather than as bare selects, because a select here prints a row that the TAP
-- parser counts as an extra test.
do $$
begin
  perform public.attach_file_to_record(
    'f2000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
    'f1000000-0000-0000-0000-000000000001'::uuid, 'client', 'f3000000-0000-0000-0000-000000000001'::uuid);
  perform public.attach_file_to_record(
    'f2000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
    'f1000000-0000-0000-0000-000000000001'::uuid, 'client', 'f3000000-0000-0000-0000-000000000002'::uuid);
end
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 1. Tenant-locked
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.detach_file_from_record(
      'f2000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
      'f1000000-0000-0000-0000-000000000002'::uuid, 'client',
      'f3000000-0000-0000-0000-000000000001'::uuid)$$,
  '23514',
  'That person is not a member of this organization.',
  'a detach by somebody from another organization is refused'
);

select is(
  public.detach_file_from_record(
    'f2000000-0000-0000-0000-000000000002'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
    'f1000000-0000-0000-0000-000000000002'::uuid, 'client',
    'f3000000-0000-0000-0000-000000000001'::uuid),
  false,
  'another organization cannot remove this organization''s use of a file'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000001'),
  2,
  'and that attempt left both uses in place'
);

-- ---------------------------------------------------------------------------------------------------------
-- 2 and 3. One use off, and nothing else
-- ---------------------------------------------------------------------------------------------------------

select is(
  public.detach_file_from_record(
    'f2000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
    'f1000000-0000-0000-0000-000000000001'::uuid, 'client',
    'f3000000-0000-0000-0000-000000000001'::uuid),
  true,
  'taking a file off one client reports that it was removed'
);

select is(
  (select array_agg(entity_id) from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000001'),
  array['f3000000-0000-0000-0000-000000000002'::uuid],
  'the other client keeps its use of the same file'
);

select is(
  (select count(*)::integer from public.files
   where id = 'f4000000-0000-0000-0000-000000000001' and trashed_at is null),
  1,
  'detaching never touches the File itself'
);

select is(
  public.detach_file_from_record(
    'f2000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
    'f1000000-0000-0000-0000-000000000001'::uuid, 'client',
    'f3000000-0000-0000-0000-000000000001'::uuid),
  false,
  'removing a use that has already gone answers false rather than failing'
);

-- ---------------------------------------------------------------------------------------------------------
-- 4. Protected history
-- ---------------------------------------------------------------------------------------------------------

update public.file_links set protected = true
where file_id = 'f4000000-0000-0000-0000-000000000001'
  and entity_id = 'f3000000-0000-0000-0000-000000000002';

select throws_ok(
  $$select public.detach_file_from_record(
      'f2000000-0000-0000-0000-000000000001'::uuid, 'f4000000-0000-0000-0000-000000000001'::uuid,
      'f1000000-0000-0000-0000-000000000001'::uuid, 'client',
      'f3000000-0000-0000-0000-000000000002'::uuid)$$,
  '23503',
  'This file is part of a document the customer already received and cannot be removed from it.',
  'a use the customer already received cannot be taken off the record'
);

-- ---------------------------------------------------------------------------------------------------------
-- 5, 6 and 7. Publishing an upload that started on a record
-- ---------------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.finalize_file_processing(
      'f4000000-0000-0000-0000-000000000002'::uuid, 'f5000000-0000-0000-0000-000000000002'::uuid,
      'available', repeat('b', 64))$$,
  'the worker publishes a file uploaded from a client'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000002'
     and entity_type = 'client'
     and entity_id = 'f3000000-0000-0000-0000-000000000001'),
  1,
  'and it is on that client, without anybody attaching it'
);

select is(
  (select created_by from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000002'),
  'f1000000-0000-0000-0000-000000000001'::uuid,
  'the use records the person who uploaded it, not the worker'
);

select is(
  (select role from public.file_links where file_id = 'f4000000-0000-0000-0000-000000000002'),
  'attachment',
  'a record upload lands as an ordinary attachment'
);

select is(
  (select protected from public.file_links where file_id = 'f4000000-0000-0000-0000-000000000002'),
  false,
  'and not as protected history'
);

select lives_ok(
  $$select public.finalize_file_processing(
      'f4000000-0000-0000-0000-000000000003'::uuid, 'f5000000-0000-0000-0000-000000000003'::uuid,
      'available', repeat('c', 64))$$,
  'the worker publishes a file uploaded straight to the library'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000003'),
  0,
  'a library upload is attached to nothing, as the contract says'
);

do $$
begin
  perform public.finalize_file_processing(
    'f4000000-0000-0000-0000-000000000004'::uuid, 'f5000000-0000-0000-0000-000000000004'::uuid,
    'quarantined', null, 'The scanner flagged this file.');
end
$$;

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000004'),
  0,
  'a record upload the scanner flags never reaches the record'
);

-- Somebody linked this one by hand while it was still being checked. Publishing must not double it.
insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, created_by)
values ('f2000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000005', 'client',
        'f3000000-0000-0000-0000-000000000002', 'attachment', 'f1000000-0000-0000-0000-000000000001');

do $$
begin
  perform public.finalize_file_processing(
    'f4000000-0000-0000-0000-000000000005'::uuid, 'f5000000-0000-0000-0000-000000000005'::uuid,
    'available', repeat('d', 64));
end
$$;

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'f4000000-0000-0000-0000-000000000005'),
  1,
  'publishing a file that is already on its record leaves one use, not two'
);

select * from finish();

rollback;
