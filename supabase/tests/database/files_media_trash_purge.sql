-- Files and Media, Part 8A: the promises the trash-purge sweep makes in the database itself.
--
--   1. Only a File trashed 30+ days ago is touched; one trashed more recently is left alone.
--   2. Purge clears object_key and thumbnail_object_key and stamps purged_at, but never deletes the row --
--      proved directly against a File a published quote version still names (the RESTRICT foreign key that
--      would reject a real DELETE), which keeps pointing at the same file_id, unchanged, afterward.
--   3. Every purge is logged once, with the key that was deleted and who trashed the File.
--   4. The sweep is a no-op the second time nothing is left to purge, and it refuses out-of-range arguments.
--   5. A purged File drops out of the Trash list, and Restore refuses it.
--   6. The purge log is readable only by files.trash holders, scoped to their own organization.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'purge-admin@example.test', 'test', now(), now(), now()),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'purge-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('a2000000-0000-0000-0000-000000000001', 'Purge Co', 'purge-co', 'active'),
  ('a2000000-0000-0000-0000-000000000002', 'Purge Co Two', 'purge-co-two', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'field', 'active');

insert into public.clients (id, organization_id, display_name, lifecycle_status)
values ('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Purge Client', 'customer');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', '1 Purge Street', 'Testville');

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values ('a3000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 1, 'Purge Quote', 'awaiting_response', 'USD');

-- Inserted as a draft first: the child-table trigger that freezes a published version's attachments would
-- reject this insert outright once the version itself says 'published'.
insert into public.quote_versions (id, organization_id, quote_id, version_number, status, currency_code, client_display_name, organization_name, total_minor)
values ('a3000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 0, 'draft', 'USD', 'Purge Client', 'Purge Co', 5000);

-- Four Files: one due for purge, one trashed too recently, one still named by a published quote version
-- (the RESTRICT case), and one in a second organization.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          thumbnail_object_key, origin_type, processing_state, uploaded_by, scanned_at,
                          checksum_sha256, trashed_at, trashed_by)
values
  ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'old-trashed.jpg',
   'image/jpeg', 2048, 'a2000000-0000-0000-0000-000000000001/files/old.jpg',
   'a2000000-0000-0000-0000-000000000001/files/old.jpg.thumb.jpg', 'file_manager', 'available',
   'a1000000-0000-0000-0000-000000000001', now(), repeat('a', 64),
   now() - interval '40 days', 'a1000000-0000-0000-0000-000000000001'),
  ('a4000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 'recent-trashed.jpg',
   'image/jpeg', 2048, 'a2000000-0000-0000-0000-000000000001/files/recent.jpg',
   null, 'file_manager', 'available', 'a1000000-0000-0000-0000-000000000001', now(), repeat('b', 64),
   now() - interval '10 days', 'a1000000-0000-0000-0000-000000000001'),
  ('a4000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001', 'quote-photo.jpg',
   'image/jpeg', 2048, 'a2000000-0000-0000-0000-000000000001/files/quote-photo.jpg',
   null, 'file_manager', 'available', 'a1000000-0000-0000-0000-000000000001', now(), repeat('c', 64),
   now() - interval '40 days', 'a1000000-0000-0000-0000-000000000001'),
  ('a4000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000002', 'other-org.jpg',
   'image/jpeg', 2048, 'a2000000-0000-0000-0000-000000000002/files/other-org.jpg',
   null, 'file_manager', 'available', null, now(), repeat('d', 64),
   now() - interval '40 days', null);

insert into public.quote_version_attachments (organization_id, quote_id, quote_version_id, file_id, position, customer_visible, display_name)
values ('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000003', 0, true, 'quote-photo.jpg');

-- Now publish it -- the file the attachment names becomes a customer-received, frozen reference.
update public.quote_versions
set status = 'published', version_number = 1, published_at = now(), document_hash = repeat('a', 64)
where id = 'a3000000-0000-0000-0000-000000000004';

update public.quotes set current_published_version_id = 'a3000000-0000-0000-0000-000000000004', sent_at = now()
where id = 'a3000000-0000-0000-0000-000000000003';

-- ---------------------------------------------------------------------------------------------------------
-- 1-2. The sweep: only what's due, cleared not deleted, the RESTRICT case survives
-- ---------------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.purge_expired_trashed_files()$$,
  'the sweep runs across every organization without raising a foreign key violation'
);

select is(
  (select object_key from public.files where id = 'a4000000-0000-0000-0000-000000000002'),
  'a2000000-0000-0000-0000-000000000001/files/recent.jpg',
  'a file trashed only 10 days ago is left untouched'
);

select is(
  (select object_key from public.files where id = 'a4000000-0000-0000-0000-000000000001'),
  null,
  'a file trashed 40 days ago has its object_key cleared'
);

select is(
  (select thumbnail_object_key from public.files where id = 'a4000000-0000-0000-0000-000000000001'),
  null,
  'its thumbnail key is cleared too'
);

select ok(
  (select purged_at from public.files where id = 'a4000000-0000-0000-0000-000000000001') is not null,
  'purged_at is stamped'
);

select is(
  (select count(*)::integer from public.files where id = 'a4000000-0000-0000-0000-000000000001'),
  1,
  'the row itself is never deleted'
);

select is(
  (select object_key from public.files where id = 'a4000000-0000-0000-0000-000000000003'),
  null,
  'a File a published quote version still names is purged too -- the RESTRICT foreign key is never tested'
);

select is(
  (select file_id from public.quote_version_attachments
   where quote_version_id = 'a3000000-0000-0000-0000-000000000004'),
  'a4000000-0000-0000-0000-000000000003',
  'the published quote version keeps pointing at the same file_id, unchanged -- "Photo removed" keeps working'
);

select is(
  (select object_key from public.files where id = 'a4000000-0000-0000-0000-000000000004'),
  null,
  'a second organization''s due file is purged in the same sweep'
);

-- ---------------------------------------------------------------------------------------------------------
-- 3. The purge log
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select count(*)::integer from public.file_purge_log),
  3,
  'one log row per purged file -- the untouched recent file logs nothing'
);

select is(
  (select object_key from public.file_purge_log where file_id = 'a4000000-0000-0000-0000-000000000001'),
  'a2000000-0000-0000-0000-000000000001/files/old.jpg',
  'the log keeps the key that was actually deleted'
);

select is(
  (select had_thumbnail from public.file_purge_log where file_id = 'a4000000-0000-0000-0000-000000000001'),
  true,
  'the log remembers whether a thumbnail existed'
);

select is(
  (select organization_id from public.file_purge_log where file_id = 'a4000000-0000-0000-0000-000000000004'),
  'a2000000-0000-0000-0000-000000000002'::uuid,
  'the second organization''s purge is logged against its own organization'
);

-- ---------------------------------------------------------------------------------------------------------
-- 4. Idempotent, and bounded
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select count(*)::integer from public.purge_expired_trashed_files()),
  0,
  'nothing is left to purge on a second run'
);

select throws_ok(
  $$select public.purge_expired_trashed_files(0, 100)$$,
  '23514',
  'The trash purge sweep is outside its safe bounds.',
  'older_than_days below one is refused'
);

select throws_ok(
  $$select public.purge_expired_trashed_files(30, 1001)$$,
  '23514',
  'The trash purge sweep is outside its safe bounds.',
  'a batch_size above the bound is refused'
);

-- ---------------------------------------------------------------------------------------------------------
-- 5. A purged File leaves Trash, and Restore refuses it
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.list_files('a2000000-0000-0000-0000-000000000001'::uuid, 'trash')),
  1,
  'the Trash list shows only the file that has not been purged yet'
);

select is(
  (select id from public.list_files('a2000000-0000-0000-0000-000000000001'::uuid, 'trash')),
  'a4000000-0000-0000-0000-000000000002'::uuid,
  'and it is the still-recoverable one'
);

reset role;

select throws_ok(
  $$select public.restore_file(
      'a2000000-0000-0000-0000-000000000001'::uuid, 'a4000000-0000-0000-0000-000000000001'::uuid,
      'a1000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0002',
  'That file is not in Trash.',
  'restoring a purged file is refused'
);

-- ---------------------------------------------------------------------------------------------------------
-- 6. The purge log is readable only by files.trash holders, scoped to their own organization
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::integer from public.file_purge_log),
  2,
  'an admin (files.trash) sees only their own organization''s purge log rows'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::integer from public.file_purge_log),
  0,
  'a field member, who holds no files.trash, sees none of it'
);

reset role;

select * from finish();

rollback;
