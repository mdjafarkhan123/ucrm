-- Files and Media, Part 4C: the promises attaching an existing File makes in the database itself.
--
--   1. Attaching is tenant-locked -- an actor from another organization is refused, and so is a file that
--      belongs to somebody else, even from a caller holding the service role.
--   2. Attaching is reuse, not copying -- one more link, the same stored object, and the same File row.
--   3. Attaching twice is attaching once -- the second call returns the first link instead of failing.
--   4. Only a checked file may go on a record -- pending, failed and quarantined are all refused.
--   5. A file in Trash cannot be attached at all.
--   6. The picker's list questions answer truthfully -- "already on this record" is exactly the linked
--      files, and "attachable only" hides everything that has not passed its checks.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('e7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'attach-a@example.test', 'test', now(), now(), now()),
  ('e7000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'attach-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('e8000000-0000-0000-0000-000000000001', 'Attach Co A', 'attach-co-a', 'active'),
  ('e8000000-0000-0000-0000-000000000002', 'Attach Co B', 'attach-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('e8000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('e8000000-0000-0000-0000-000000000002', 'e7000000-0000-0000-0000-000000000002', 'admin', 'active');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values
  ('e9000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'Bea Bright', 'customer'),
  ('e9000000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', 'Cal Corner', 'customer');

-- One checked photo, one still being checked, one quarantined, and one already in Trash.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, processing_state, uploaded_by, scanned_at, checksum_sha256, trashed_at)
values
  ('ea000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'boiler-before.jpg',
   'image/jpeg', 2048, 'e8000000-0000-0000-0000-000000000001/files/boiler-before.jpg',
   'file_manager', 'available', 'e7000000-0000-0000-0000-000000000001', now(), repeat('c', 64), null),
  ('ea000000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', 'still-checking.pdf',
   'application/pdf', 4096, 'e8000000-0000-0000-0000-000000000001/files/still-checking.pdf',
   'file_manager', 'pending', 'e7000000-0000-0000-0000-000000000001', null, null, null),
  ('ea000000-0000-0000-0000-000000000003', 'e8000000-0000-0000-0000-000000000001', 'flagged.docx',
   'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 4096,
   'e8000000-0000-0000-0000-000000000001/files/flagged.docx',
   'file_manager', 'quarantined', 'e7000000-0000-0000-0000-000000000001', now(), repeat('d', 64), null),
  ('ea000000-0000-0000-0000-000000000004', 'e8000000-0000-0000-0000-000000000001', 'binned.jpg',
   'image/jpeg', 2048, 'e8000000-0000-0000-0000-000000000001/files/binned.jpg',
   'file_manager', 'available', 'e7000000-0000-0000-0000-000000000001', now(), repeat('e', 64), now());

-- ---------------------------------------------------------------------------------------------------------
-- 1. Tenant-locked
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000001'::uuid,
      'e7000000-0000-0000-0000-000000000002'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  '23514',
  'That person is not a member of this organization.',
  'an attach by somebody from another organization is refused'
);

select throws_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000002'::uuid, 'ea000000-0000-0000-0000-000000000001'::uuid,
      'e7000000-0000-0000-0000-000000000002'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0002',
  'That file was not found.',
  'another organization cannot attach this organization''s file'
);

-- ---------------------------------------------------------------------------------------------------------
-- 2. Attaching is reuse, not copying
-- ---------------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000001'::uuid,
      'e7000000-0000-0000-0000-000000000001'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  'a checked file attaches to a client'
);

select is(
  (select count(*)::integer from public.files
   where organization_id = 'e8000000-0000-0000-0000-000000000001'),
  4,
  'attaching creates no second File'
);

select is(
  (select count(*)::integer from public.files
   where object_key = 'e8000000-0000-0000-0000-000000000001/files/boiler-before.jpg'),
  1,
  'attaching creates no second stored object'
);

select is(
  (select created_by from public.file_links
   where file_id = 'ea000000-0000-0000-0000-000000000001'
     and entity_id = 'e9000000-0000-0000-0000-000000000001'),
  'e7000000-0000-0000-0000-000000000001'::uuid,
  'the link records who attached it'
);

select is(
  (select protected from public.file_links
   where file_id = 'ea000000-0000-0000-0000-000000000001'
     and entity_id = 'e9000000-0000-0000-0000-000000000001'),
  false,
  'an ordinary attach is not protected history'
);

-- The same file on a second record is a second use of the same File, which is the whole point.
select lives_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000001'::uuid,
      'e7000000-0000-0000-0000-000000000001'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000002'::uuid)$$,
  'the same file attaches to a second record'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'ea000000-0000-0000-0000-000000000001'),
  2,
  'two uses of one File are two links'
);

-- ---------------------------------------------------------------------------------------------------------
-- 3. Attaching twice is attaching once
-- ---------------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000001'::uuid,
      'e7000000-0000-0000-0000-000000000001'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  'attaching a file that is already there does not fail'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'ea000000-0000-0000-0000-000000000001'
     and entity_id = 'e9000000-0000-0000-0000-000000000001'),
  1,
  'and it does not add a duplicate use'
);

-- ---------------------------------------------------------------------------------------------------------
-- 4 and 5. Only a checked, live file may go on a record
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000002'::uuid,
      'e7000000-0000-0000-0000-000000000001'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  '23514',
  'That file is still being checked, so it cannot be attached yet.',
  'a pending file cannot be attached'
);

select throws_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000003'::uuid,
      'e7000000-0000-0000-0000-000000000001'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  '23514',
  'That file is still being checked, so it cannot be attached yet.',
  'a quarantined file cannot be attached'
);

select throws_ok(
  $$select public.attach_file_to_record(
      'e8000000-0000-0000-0000-000000000001'::uuid, 'ea000000-0000-0000-0000-000000000004'::uuid,
      'e7000000-0000-0000-0000-000000000001'::uuid, 'client',
      'e9000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0002',
  'That file was not found.',
  'a file in Trash cannot be attached'
);

-- ---------------------------------------------------------------------------------------------------------
-- 6. The picker's list questions
-- ---------------------------------------------------------------------------------------------------------

-- Read as the organization's own member, because list_files is security invoker and answers under the
-- reader's policies rather than the service role's reach.
-- Set inside a DO block rather than a bare select, because a select here prints a row that the TAP parser
-- counts as an eighteenth test.
do $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"e7000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
end
$$;
set local role authenticated;

select is(
  (select array_agg(id order by id) from public.list_files(
     'e8000000-0000-0000-0000-000000000001'::uuid, 'on_record', null, null, 40, null, null,
     'client', 'e9000000-0000-0000-0000-000000000002'::uuid, true)),
  array['ea000000-0000-0000-0000-000000000001'::uuid],
  '"already on this record" is exactly the files linked to it'
);

select is(
  (select count(*)::integer from public.list_files(
     'e8000000-0000-0000-0000-000000000001'::uuid, 'all', null, null, 40, null, null,
     null, null, true)),
  1,
  'asking for attachable files only hides the pending and quarantined ones'
);

select is(
  (select count(*)::integer from public.list_files(
     'e8000000-0000-0000-0000-000000000001'::uuid, 'on_record', null, null, 40, null, null,
     null, null, true)),
  0,
  'the "on this record" view with no record named is empty, not the whole library'
);

select * from finish();

rollback;
