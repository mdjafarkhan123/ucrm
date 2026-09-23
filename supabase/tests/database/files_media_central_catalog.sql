-- Files and Media, Part 2: the four promises the central File catalog makes in the schema itself.
--
--   1. Tenant isolation -- a File or a link cannot reach across organizations, and a member of one
--      organization cannot read the other's catalog.
--   2. Link truth -- one row per use, no link to a record that does not exist, and a reader only ever sees a
--      link to a record they may already view, so a hidden record cannot be inferred from a count.
--   3. Protected history -- a use the customer already received cannot be deleted, and the File behind it
--      cannot be moved to Trash until its owning domain retires that use.
--   4. Rollback-safe backfill -- every existing attachment becomes one File and one link, re-running changes
--      nothing, and no R2 object key is altered.
--
-- Written for `supabase test db`, which runs the file as one session. Do not run it through a runner that
-- executes each statement separately: `set local role` does not survive that.

begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'files-admin-a@example.test', 'test', now(), now(), now()),
  ('f0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'files-field-a@example.test', 'test', now(), now(), now()),
  ('f0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'files-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f1000000-0000-0000-0000-000000000001', 'Files Co A', 'files-co-a', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'Files Co B', 'files-co-b', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'field', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000003', 'admin', 'active');

insert into public.clients (id, organization_id, display_name)
values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'Files Client A'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002', 'Files Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values
  ('f3000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', '1 File Street', 'Testville', 'TX', '78741'),
  ('f3000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002',
   'f2000000-0000-0000-0000-000000000002', '2 Other Street', 'Otherville', 'TX', '78742');

-- One job in each organization. Nobody is assigned to either, so the field member can view neither.
insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code)
values
  ('f4000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
   900, 'Files Job A', 'one_off', 'job_total', 'USD'),
  ('f4000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002',
   'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000002',
   901, 'Files Job B', 'one_off', 'job_total', 'USD');

-- Part 3A added files_available_means_verified_check: from that migration forward, an available File must
-- carry the checksum and scan time its verification pass produced, so these fixtures carry them too.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, origin_id, processing_state, uploaded_by,
                          checksum_sha256, scanned_at)
values
  ('f5000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'Before photo.jpg', 'image/jpeg', 120000, 'f1000000-0000-0000-0000-000000000001/job/before.jpg',
   'job', 'f4000000-0000-0000-0000-000000000001', 'available', 'f0000000-0000-0000-0000-000000000001',
   repeat('a', 64), now()),
  ('f5000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000002',
   'Other org photo.jpg', 'image/jpeg', 120000, 'f1000000-0000-0000-0000-000000000002/job/other.jpg',
   'job', 'f4000000-0000-0000-0000-000000000002', 'available', 'f0000000-0000-0000-0000-000000000003',
   repeat('b', 64), now());

insert into public.file_links (id, organization_id, file_id, entity_type, entity_id, role)
values
  ('f6000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'f5000000-0000-0000-0000-000000000001', 'job', 'f4000000-0000-0000-0000-000000000001', 'attachment');

-- ---------------------------------------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select kind from public.files where id = 'f5000000-0000-0000-0000-000000000001'),
  'image', 'a JPEG files itself under Photos without anyone setting a category');

select lives_ok(
  $$insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                              origin_type, processing_state, checksum_sha256, scanned_at)
    values ('f5000000-0000-0000-0000-00000000000d', 'f1000000-0000-0000-0000-000000000001',
            'Invoice.pdf', 'application/pdf', 4000,
            'f1000000-0000-0000-0000-000000000001/file-manager/invoice.pdf', 'file_manager', 'available',
            repeat('c', 64), now())$$,
  'a direct library upload needs no originating record');

select is(
  (select kind from public.files where id = 'f5000000-0000-0000-0000-00000000000d'),
  'document', 'a PDF files itself under Documents');

select throws_ok(
  $$insert into public.files (organization_id, display_name, mime_type, size_bytes, object_key, origin_type)
    values ('f1000000-0000-0000-0000-000000000001', 'Nowhere.pdf', 'application/pdf', 10,
            'f1000000-0000-0000-0000-000000000001/nowhere.pdf', 'job')$$,
  '23514', null, 'a File claiming a record origin must name the record');

select throws_ok(
  $$insert into public.files (organization_id, display_name, mime_type, size_bytes, object_key, origin_type)
    values ('f1000000-0000-0000-0000-000000000001', 'Copy.jpg', 'image/jpeg', 10,
            'f1000000-0000-0000-0000-000000000001/job/before.jpg', 'file_manager')$$,
  '23505', null, 'two Files cannot claim the same R2 object');

-- ---------------------------------------------------------------------------------------------------------
-- 1. Tenant isolation
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.file_links (organization_id, file_id, entity_type, entity_id)
    values ('f1000000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001',
            'job', 'f4000000-0000-0000-0000-000000000002')$$,
  '23503', null, 'one organization cannot link another organization''s File');

select throws_ok(
  $$insert into public.file_links (organization_id, file_id, entity_type, entity_id)
    values ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
            'job', 'f4000000-0000-0000-0000-000000000002')$$,
  '23503', null, 'a File cannot be linked to a record in another organization');

insert into public.file_folders (id, organization_id, name)
values ('f7000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'Site photos');

select throws_ok(
  $$update public.files set folder_id = 'f7000000-0000-0000-0000-000000000001'
    where id = 'f5000000-0000-0000-0000-000000000002'$$,
  '23503', null, 'a File cannot be filed into another organization''s folder');

select throws_ok(
  $$insert into public.file_folders (organization_id, name)
    values ('f1000000-0000-0000-0000-000000000001', '  site photos  ')$$,
  '23505', null, 'folder names do not repeat within one organization');

-- ---------------------------------------------------------------------------------------------------------
-- 2. Link truth
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.file_links (organization_id, file_id, entity_type, entity_id)
    values ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
            'job', 'f4000000-0000-0000-0000-000000000001')$$,
  '23505', null, 'the same File on the same record in the same role counts once, not twice');

select lives_ok(
  $$insert into public.file_links (organization_id, file_id, entity_type, entity_id, role)
    values ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
            'job', 'f4000000-0000-0000-0000-000000000001', 'work_photo')$$,
  'the same File may serve a second purpose on the same record');

select lives_ok(
  $$insert into public.file_links (organization_id, file_id, entity_type, entity_id)
    values ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
            'client', 'f2000000-0000-0000-0000-000000000001')$$,
  'reusing a File on another record adds a link, never a second File');

select is(
  (select count(*)::int from public.files
   where object_key = 'f1000000-0000-0000-0000-000000000001/job/before.jpg'),
  1, 'three uses, still exactly one stored object');

select throws_ok(
  $$insert into public.file_links (organization_id, file_id, entity_type, entity_id)
    values ('f1000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001',
            'job', 'f4000000-0000-0000-0000-00000000dead')$$,
  '23503', null, 'a link cannot point at a record that does not exist');

-- ---------------------------------------------------------------------------------------------------------
-- 3. Protected history
-- ---------------------------------------------------------------------------------------------------------

update public.file_links set protected = true
where id = 'f6000000-0000-0000-0000-000000000001';

select throws_ok(
  $$delete from public.file_links where id = 'f6000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'a use the customer already received cannot be unlinked');

select throws_ok(
  $$update public.files set trashed_at = now() where id = 'f5000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'a File behind a received document cannot be moved to Trash');

select throws_ok(
  $$delete from public.files where id = 'f5000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'deleting the File outright does not get around the protected use either');

select lives_ok(
  $$update public.files set display_name = 'Before photo (renamed).jpg'
    where id = 'f5000000-0000-0000-0000-000000000001'$$,
  'renaming stays allowed while history is protected');

select lives_ok(
  $$update public.files set folder_id = 'f7000000-0000-0000-0000-000000000001'
    where id = 'f5000000-0000-0000-0000-000000000001'$$,
  'moving between folders stays allowed and changes no link');

select is(
  (select count(*)::int from public.file_links where file_id = 'f5000000-0000-0000-0000-000000000001'),
  3, 'moving the File into a folder left every use in place');

-- The owning domain retires the use first; only then may the link go.
update public.file_links set protected = false
where id = 'f6000000-0000-0000-0000-000000000001';

select lives_ok(
  $$delete from public.file_links where id = 'f6000000-0000-0000-0000-000000000001'$$,
  'once the owning domain retires the use, the link can be removed');

select lives_ok(
  $$update public.files set trashed_at = now(), trashed_by = 'f0000000-0000-0000-0000-000000000001'
    where id = 'f5000000-0000-0000-0000-000000000001'$$,
  'with nothing protected left, the File can go to Trash');

select lives_ok(
  $$update public.files set trashed_at = null, trashed_by = null
    where id = 'f5000000-0000-0000-0000-000000000001'$$,
  'restoring from Trash is always allowed');

select throws_ok(
  $$update public.files set trashed_by = 'f0000000-0000-0000-0000-000000000001'
    where id = 'f5000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'a File cannot record who trashed it while it is not in Trash');

-- ---------------------------------------------------------------------------------------------------------
-- Permissions and write access
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.permissions
   where key in ('files.view', 'files.manage', 'files.trash')),
  3, 'the three Files permissions exist');

select bag_eq(
  $$select role from public.role_permissions where permission_key = 'files.trash'$$,
  $$values ('owner'), ('admin'), ('office')$$,
  'only owner, admin and office may trash and restore by default');

select bag_eq(
  $$select role from public.role_permissions where permission_key = 'files.view'$$,
  $$values ('owner'), ('admin'), ('office'), ('sales'), ('finance')$$,
  'field members get no library browsing by default; they reach files through their jobs');

select table_privs_are('public', 'files', 'authenticated', array['SELECT'],
  'signed-in clients can only read files; every write goes through a server command');
select table_privs_are('public', 'file_links', 'authenticated', array['SELECT'],
  'signed-in clients can only read file links');
select table_privs_are('public', 'file_folders', 'authenticated', array['SELECT'],
  'signed-in clients can only read folders');

select table_privs_are('public', 'files', 'anon', array[]::text[],
  'a signed-out visitor has no reach into the catalog at all');
select table_privs_are('public', 'file_links', 'anon', array[]::text[],
  'nor into what uses a file');
select table_privs_are('public', 'file_folders', 'anon', array[]::text[],
  'nor into the folders');

-- ---------------------------------------------------------------------------------------------------------
-- Reading rules: no hidden record leaks through the library
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::int from public.files), 2,
  'an admin sees their own organization''s catalog');

select is(
  (select count(*)::int from public.file_links
   where file_id = 'f5000000-0000-0000-0000-000000000001'), 2,
  'the admin sees both remaining uses, because they can view both records');

-- The other organization's admin.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::int from public.files
   where organization_id = 'f1000000-0000-0000-0000-000000000001'), 0,
  'the other organization''s catalog is invisible');

select is(
  (select count(*)::int from public.file_links
   where organization_id = 'f1000000-0000-0000-0000-000000000001'), 0,
  'and so are its links');

-- The field member: no library scope, and assigned to neither job.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.files), 0,
  'a field member with no library scope and no assigned work sees no files at all');

select is(
  (select count(*)::int from public.file_links), 0,
  'and no uses, so no record is revealed');

-- Now grant that same field member the separate Files scope the contract describes.
set local role postgres;
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'files.view', 'grant');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.files), 2,
  'the granted Files scope shows the library');

select is(
  (select count(*)::int from public.file_links), 0,
  'but it reveals nothing about the records using them -- "Used in" counts zero, not a hidden total');

-- ---------------------------------------------------------------------------------------------------------
-- 4. Rollback-safe backfill
-- ---------------------------------------------------------------------------------------------------------

set local role postgres;

insert into public.attachments (id, organization_id, entity_type, entity_id, file_name, mime_type,
                                size_bytes, object_key, thumbnail_object_key, uploaded_by)
values
  ('f8000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'job', 'f4000000-0000-0000-0000-000000000001', 'Old receipt.pdf', 'application/pdf', 5000,
   'f1000000-0000-0000-0000-000000000001/job/f4000000/old-receipt.pdf', null,
   'f0000000-0000-0000-0000-000000000001'),
  ('f8000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000001',
   'job', 'f4000000-0000-0000-0000-000000000001', 'Report photo.jpg', 'image/jpeg', 90000,
   'f1000000-0000-0000-0000-000000000001/job/f4000000/report.jpg',
   'f1000000-0000-0000-0000-000000000001/job/f4000000/report.jpg.thumb.jpg',
   'f0000000-0000-0000-0000-000000000001');

-- Part 7A moved a work report's photos onto public.files, so a report can no longer name a legacy
-- attachment and the backfill no longer takes protection from one; the report protects its own
-- 'report_photo' link instead (files_media_work_report_photos.sql).

select is(private.backfill_files_from_attachments(), 2,
  'both existing attachments become Files');

select is(
  (select count(*)::int from public.attachments where file_id is null), 0,
  'every attachment now knows which File it became');

select is(
  (select object_key from public.files
   where id = (select file_id from public.attachments where id = 'f8000000-0000-0000-0000-000000000001')),
  'f1000000-0000-0000-0000-000000000001/job/f4000000/old-receipt.pdf',
  'the File reuses the attachment''s stored object -- nothing in R2 moves');

select is(
  (select protected from public.file_links
   where file_id = (select file_id from public.attachments where id = 'f8000000-0000-0000-0000-000000000002')),
  false, 'a job photo is backfilled as an ordinary, unprotected attachment link');

select is(
  (select protected from public.file_links
   where file_id = (select file_id from public.attachments where id = 'f8000000-0000-0000-0000-000000000001')),
  false, 'an ordinary attachment is backfilled unprotected and stays manageable');

-- Re-running is the rollback-safety proof: the second pass must be a no-op, not a duplicate catalog.
select is(private.backfill_files_from_attachments(), 0,
  'running the backfill again creates nothing');

select is(
  (select count(*)::int from public.files where organization_id = 'f1000000-0000-0000-0000-000000000001'),
  4, 'the catalog is unchanged by the second pass');

select is(
  (select count(*)::int from public.attachments), 2,
  'and the original attachment rows are left exactly as they were');

select * from finish();
rollback;
