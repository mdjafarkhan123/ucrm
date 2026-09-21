-- Files and Media, Part 4B: the promises the manage actions make in the database itself.
--
--   1. Every command is tenant-locked -- an actor from another organization is refused, and so is a file
--      that belongs to somebody else, even from a caller holding the service role.
--   2. Renaming and moving touch nothing else -- a move changes no link, and neither command can reach a
--      file that is already in Trash.
--   3. Folders are one per name -- case and surrounding spaces do not make a second one.
--   4. Trash is the confirmed detach -- it removes the ordinary links, and it refuses outright while the
--      customer already has one of them.
--   5. Restore puts the file back where it was -- same folder, no links, and only out of Trash.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('f7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'manage-a@example.test', 'test', now(), now(), now()),
  ('f7000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'manage-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f8000000-0000-0000-0000-000000000001', 'Manage Co A', 'manage-co-a', 'active'),
  ('f8000000-0000-0000-0000-000000000002', 'Manage Co B', 'manage-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('f8000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('f8000000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000002', 'admin', 'active');

-- A client to hang the ordinary links on, and a second file to carry the protected one.
insert into public.clients (id, organization_id, display_name, lifecycle_status)
values ('f9000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001', 'Ada Ashby', 'customer');

insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, processing_state, uploaded_by, scanned_at, checksum_sha256)
values
  ('fa000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001', 'IMG_2093.jpg',
   'image/jpeg', 2048, 'f8000000-0000-0000-0000-000000000001/files/img-2093.jpg',
   'file_manager', 'available', 'f7000000-0000-0000-0000-000000000001', now(), repeat('a', 64)),
  ('fa000000-0000-0000-0000-000000000002', 'f8000000-0000-0000-0000-000000000001', 'issued.pdf',
   'application/pdf', 4096, 'f8000000-0000-0000-0000-000000000001/files/issued.pdf',
   'file_manager', 'available', 'f7000000-0000-0000-0000-000000000001', now(), repeat('b', 64));

insert into public.file_links (organization_id, file_id, entity_type, entity_id, role, protected)
values
  ('f8000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001',
   'client', 'f9000000-0000-0000-0000-000000000001', 'attachment', false),
  ('f8000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002',
   'client', 'f9000000-0000-0000-0000-000000000001', 'attachment', true);

-- ---------------------------------------------------------------------------------------------------------
-- 1. Every command is tenant-locked
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.rename_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000002'::uuid, 'Stolen')$$,
  '23514',
  'That person is not a member of this organization.',
  'a rename by somebody from another organization is refused'
);

select throws_ok(
  $$select public.rename_file(
      'f8000000-0000-0000-0000-000000000002'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000002'::uuid, 'Stolen')$$,
  'P0002',
  'That file was not found.',
  'another organization cannot rename this organization''s file'
);

select throws_ok(
  $$select public.trash_file(
      'f8000000-0000-0000-0000-000000000002'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000002'::uuid)$$,
  'P0002',
  'That file was not found.',
  'another organization cannot trash this organization''s file'
);

select is(
  (select display_name from public.files where id = 'fa000000-0000-0000-0000-000000000001'),
  'IMG_2093.jpg',
  'none of the refused commands changed anything'
);

-- ---------------------------------------------------------------------------------------------------------
-- 2. Renaming and moving touch nothing else
-- ---------------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.rename_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid, '  Boiler before.jpg  ')$$,
  'a member of the organization renames its file'
);

select is(
  (select display_name from public.files where id = 'fa000000-0000-0000-0000-000000000001'),
  'Boiler before.jpg',
  'the stored name is trimmed'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'fa000000-0000-0000-0000-000000000001'),
  1,
  'renaming changed no link'
);

select lives_ok(
  $$select public.create_file_folder(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'f7000000-0000-0000-0000-000000000001'::uuid,
      'Boiler jobs')$$,
  'a folder is created'
);

select lives_ok(
  $$select public.move_file_to_folder(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid,
      (select id from public.file_folders where organization_id = 'f8000000-0000-0000-0000-000000000001'))$$,
  'the file moves into the folder'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'fa000000-0000-0000-0000-000000000001'),
  1,
  'moving between folders changed no link'
);

select throws_ok(
  $$select public.move_file_to_folder(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid, 'fb000000-0000-0000-0000-0000000000ff'::uuid)$$,
  'P0002',
  'That folder was not found.',
  'a folder that does not exist is refused rather than quietly emptying the box'
);

select ok(
  (select folder_id is not null from public.files where id = 'fa000000-0000-0000-0000-000000000001'),
  'the refused move left the file in its folder'
);

-- ---------------------------------------------------------------------------------------------------------
-- 3. Folders are one per name
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.create_file_folder(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'f7000000-0000-0000-0000-000000000001'::uuid,
      '  boiler JOBS ')$$,
  '23505',
  'You already have a folder with that name.',
  'the same folder name in another case, with spaces, is one folder'
);

select lives_ok(
  $$select public.create_file_folder(
      'f8000000-0000-0000-0000-000000000002'::uuid, 'f7000000-0000-0000-0000-000000000002'::uuid,
      'Boiler jobs')$$,
  'another organization may have a folder of the same name'
);

-- ---------------------------------------------------------------------------------------------------------
-- 4. Trash is the confirmed detach
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.trash_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000002'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid)$$,
  '23514',
  'This file is part of a document the customer already received, so it cannot be moved to Trash yet.',
  'a file the customer already received cannot go to Trash'
);

select ok(
  (select trashed_at is null from public.files where id = 'fa000000-0000-0000-0000-000000000002'),
  'the refused file stayed out of Trash'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'fa000000-0000-0000-0000-000000000002'),
  1,
  'and kept the protected link it was refused for'
);

select lives_ok(
  $$select public.trash_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid)$$,
  'a file with only ordinary uses goes to Trash'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'fa000000-0000-0000-0000-000000000001'),
  0,
  'and is detached from every record that was using it'
);

select is(
  (select trashed_by from public.files where id = 'fa000000-0000-0000-0000-000000000001'),
  'f7000000-0000-0000-0000-000000000001'::uuid,
  'the person who trashed it is recorded'
);

select throws_ok(
  $$select public.rename_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid, 'Renamed in the bin')$$,
  'P0002',
  'That file was not found.',
  'a file in Trash cannot be renamed'
);

select throws_ok(
  $$select public.trash_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0002',
  'That file was not found.',
  'and cannot be trashed twice'
);

-- ---------------------------------------------------------------------------------------------------------
-- 5. Restore puts the file back where it was
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.restore_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000002'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0002',
  'That file is not in Trash.',
  'a file that is not in Trash cannot be restored'
);

select lives_ok(
  $$select public.restore_file(
      'f8000000-0000-0000-0000-000000000001'::uuid, 'fa000000-0000-0000-0000-000000000001'::uuid,
      'f7000000-0000-0000-0000-000000000001'::uuid)$$,
  'a file comes back out of Trash'
);

select is(
  (select folder_id from public.files where id = 'fa000000-0000-0000-0000-000000000001'),
  (select id from public.file_folders where organization_id = 'f8000000-0000-0000-0000-000000000001'),
  'into the folder it was in'
);

select ok(
  (select trashed_at is null and trashed_by is null
   from public.files where id = 'fa000000-0000-0000-0000-000000000001'),
  'with nothing left of the trashing'
);

select is(
  (select count(*)::integer from public.file_links
   where file_id = 'fa000000-0000-0000-0000-000000000001'),
  0,
  'and the links stay gone, exactly as the confirmation said'
);

select * from finish();

rollback;
