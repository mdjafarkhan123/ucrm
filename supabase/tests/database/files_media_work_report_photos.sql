-- Files and Media, Part 7A: a job's work report picks its photos from the File Manager.
--
--   1. The editor offers exactly the checked, un-trashed photos linked to the job or its visits, and saving
--      refuses anything else.
--   2. A chosen photo gets a 'report_photo' link on the job, kept off the job's own Files card.
--   3. Issuing a customer link protects those links; "Used in" says the customer received the photo.
--   4. Trash needs the acknowledgement, lets go of the editable selection, and the customer's frozen copy
--      shows the photo as removed until Restore brings it back.
--   5. Turning the link off releases the protection.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('e7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'report-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('e8000000-0000-0000-0000-000000000001', 'Report Co', 'report-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values ('e8000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 'admin', 'active');

insert into public.clients (id, organization_id, display_name)
values ('e9000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'Rita Report');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('ec000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001',
        'e9000000-0000-0000-0000-000000000001', 'email', 'rita@example.test');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('ea000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001',
        'e9000000-0000-0000-0000-000000000001', '7 Report Road', 'Testville', 'TX', '78741');

insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code)
values
  ('eb000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001',
   700, 'Deck repair', 'one_off', 'job_total', 'USD'),
  ('eb000000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001',
   'e9000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000001',
   701, 'Another job', 'one_off', 'job_total', 'USD');

insert into public.job_visits (id, organization_id, job_id, position, visit_date)
values ('ed000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001',
        'eb000000-0000-0000-0000-000000000001', 0, current_date);

-- 1 job photo, 2 visit photo, 3 a PDF on the job, 4 a photo still being checked, 5 a photo in Trash,
-- 6 another job's photo, 7 a line photo on the job.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, processing_state, uploaded_by, scanned_at, checksum_sha256, trashed_at)
values
  ('ee000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'deck-before.jpg',
   'image/jpeg', 2048, 'e8/files/1.jpg', 'file_manager', 'available',
   'e7000000-0000-0000-0000-000000000001', now(), repeat('a', 64), null),
  ('ee000000-0000-0000-0000-000000000002', 'e8000000-0000-0000-0000-000000000001', 'deck-after.jpg',
   'image/jpeg', 2048, 'e8/files/2.jpg', 'file_manager', 'available',
   'e7000000-0000-0000-0000-000000000001', now(), repeat('b', 64), null),
  ('ee000000-0000-0000-0000-000000000003', 'e8000000-0000-0000-0000-000000000001', 'permit.pdf',
   'application/pdf', 2048, 'e8/files/3.pdf', 'file_manager', 'available',
   'e7000000-0000-0000-0000-000000000001', now(), repeat('c', 64), null),
  ('ee000000-0000-0000-0000-000000000004', 'e8000000-0000-0000-0000-000000000001', 'checking.jpg',
   'image/jpeg', 2048, 'e8/files/4.jpg', 'file_manager', 'pending',
   'e7000000-0000-0000-0000-000000000001', null, null, null),
  ('ee000000-0000-0000-0000-000000000005', 'e8000000-0000-0000-0000-000000000001', 'binned.jpg',
   'image/jpeg', 2048, 'e8/files/5.jpg', 'file_manager', 'available',
   'e7000000-0000-0000-0000-000000000001', now(), repeat('d', 64), now()),
  ('ee000000-0000-0000-0000-000000000006', 'e8000000-0000-0000-0000-000000000001', 'elsewhere.jpg',
   'image/jpeg', 2048, 'e8/files/6.jpg', 'file_manager', 'available',
   'e7000000-0000-0000-0000-000000000001', now(), repeat('e', 64), null),
  ('ee000000-0000-0000-0000-000000000007', 'e8000000-0000-0000-0000-000000000001', 'line.jpg',
   'image/jpeg', 2048, 'e8/files/7.jpg', 'file_manager', 'available',
   'e7000000-0000-0000-0000-000000000001', now(), repeat('f', 64), null);

insert into public.file_links (organization_id, file_id, entity_type, entity_id, role)
values
  ('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000001', 'job', 'eb000000-0000-0000-0000-000000000001', 'attachment'),
  ('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000002', 'visit', 'ed000000-0000-0000-0000-000000000001', 'attachment'),
  ('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000003', 'job', 'eb000000-0000-0000-0000-000000000001', 'attachment'),
  ('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000004', 'job', 'eb000000-0000-0000-0000-000000000001', 'attachment'),
  ('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000006', 'job', 'eb000000-0000-0000-0000-000000000002', 'attachment'),
  ('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000007', 'job', 'eb000000-0000-0000-0000-000000000001', 'line_photo');

-- ---------------------------------------------------------------------------------------------------------
-- 1. What the editor offers, and what saving accepts
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7000000-0000-0000-0000-000000000001', true);

select is(
  (select jsonb_agg(photo ->> 'file_id' order by photo ->> 'file_id')
   from jsonb_array_elements(public.job_report_state('eb000000-0000-0000-0000-000000000001') -> 'candidates' -> 'photos') photo),
  '["ee000000-0000-0000-0000-000000000001", "ee000000-0000-0000-0000-000000000002"]'::jsonb,
  'the editor offers the job''s and its visit''s checked photos -- no PDF, pending, trashed, other-job or line photo');

select throws_ok(
  $$select public.save_job_report('eb000000-0000-0000-0000-000000000001', false, false, null, null,
      array['ee000000-0000-0000-0000-000000000006']::uuid[])$$,
  'P0400', null, 'another job''s photo is refused');

select throws_ok(
  $$select public.save_job_report('eb000000-0000-0000-0000-000000000001', false, false, null, null,
      array['ee000000-0000-0000-0000-000000000003']::uuid[])$$,
  'P0400', null, 'a PDF is refused');

select throws_ok(
  $$select public.save_job_report('eb000000-0000-0000-0000-000000000001', false, false, null, null,
      array['ee000000-0000-0000-0000-000000000005']::uuid[])$$,
  'P0400', null, 'a photo in Trash is refused');

select is(
  public.save_job_report('eb000000-0000-0000-0000-000000000001', false, false, null, null,
    array['ee000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000002']::uuid[]) ->> 'has_content',
  'true', 'the job and visit photos are saved onto the report');

select is(
  public.job_report_state('eb000000-0000-0000-0000-000000000001') -> 'report' -> 'photo_ids',
  '["ee000000-0000-0000-0000-000000000001", "ee000000-0000-0000-0000-000000000002"]'::jsonb,
  'the saved selection reads back as File ids');

select is(
  (select count(*)::int from public.list_files('e8000000-0000-0000-0000-000000000001', 'on_record',
     target_entity_type => 'job', target_entity_id => 'eb000000-0000-0000-0000-000000000001')
   where id = 'ee000000-0000-0000-0000-000000000002'),
  0, 'a visit photo on the report does not appear on the job''s own Files card');

select is(
  jsonb_array_length(public.job_report_customer_preview('eb000000-0000-0000-0000-000000000001') -> 'document' -> 'photos'),
  2, 'Preview as client shows both photos');

reset role;

-- ---------------------------------------------------------------------------------------------------------
-- 2. The 'report_photo' links
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.file_links
   where entity_type = 'job' and entity_id = 'eb000000-0000-0000-0000-000000000001'
     and role = 'report_photo' and not protected),
  2, 'each chosen photo gets an unprotected report_photo link on the job');

-- ---------------------------------------------------------------------------------------------------------
-- 3. Sharing protects them
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7000000-0000-0000-0000-000000000001', true);

select ok(
  public.issue_job_report_access_link('eb000000-0000-0000-0000-000000000001', decode(repeat('ab', 32), 'hex'))
    ? 'job_report_access_link_id',
  'a customer link is issued');

select is(
  (select customer_received from public.file_usage('e8000000-0000-0000-0000-000000000001',
     'ee000000-0000-0000-0000-000000000001') where role = 'report_photo'),
  true, '"Used in" says the customer received the photo on the work report');

reset role;

select is(
  (select count(*)::int from public.file_links
   where entity_type = 'job' and entity_id = 'eb000000-0000-0000-0000-000000000001'
     and role = 'report_photo' and protected),
  2, 'both report_photo links are protected while the customer link is live');

select is(
  (select jsonb_agg(photo ->> 'file_id') from jsonb_array_elements(
     public.resolve_job_report_access_link(decode(repeat('ab', 32), 'hex')) -> 'photos') photo),
  '["ee000000-0000-0000-0000-000000000001", "ee000000-0000-0000-0000-000000000002"]'::jsonb,
  'the customer''s copy names both photos by File id');

-- ---------------------------------------------------------------------------------------------------------
-- 4. Trash and Restore
-- ---------------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.trash_file('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000001',
      'e7000000-0000-0000-0000-000000000001')$$,
  'P0412', null, 'trashing a photo the customer received needs the acknowledgement');

select lives_ok(
  $$select public.trash_file('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000001',
      'e7000000-0000-0000-0000-000000000001', true)$$,
  'with the acknowledgement it goes to Trash');

select is(
  (select count(*)::int from public.job_report_photos where file_id = 'ee000000-0000-0000-0000-000000000001'),
  0, 'the editable report selection lets go of it');

select is(
  (select protected from public.file_links
   where file_id = 'ee000000-0000-0000-0000-000000000001' and role = 'report_photo'),
  true, 'its protected report_photo link stays, so Restore can put it back');

select is(
  public.resolve_job_report_access_link(decode(repeat('ab', 32), 'hex')) -> 'photos' -> 0,
  '{"file_id": null, "file_name": null, "caption": null, "labels": [], "removed": true}'::jsonb,
  'the customer''s copy shows it as removed, with no name or words left (7B-2)');

select is(
  public.resolve_job_report_access_link(decode(repeat('ab', 32), 'hex')) -> 'photos' -> 1 ->> 'removed',
  'false', 'the other photo is untouched');

select lives_ok(
  $$select public.restore_file('e8000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000001',
      'e7000000-0000-0000-0000-000000000001')$$,
  'the photo is restored');

select is(
  public.resolve_job_report_access_link(decode(repeat('ab', 32), 'hex')) -> 'photos' -> 0 ->> 'file_id',
  'ee000000-0000-0000-0000-000000000001', 'after Restore the customer sees the photo again');

-- ---------------------------------------------------------------------------------------------------------
-- 5. Turning the link off releases the protection
-- ---------------------------------------------------------------------------------------------------------

-- The command reads the caller from the JWT claim, which is still the admin's.
select public.revoke_job_report_access_link(
  (select id from public.job_report_access_links where job_id = 'eb000000-0000-0000-0000-000000000001'));

select is(
  (select jsonb_object_agg(file_id, protected) from public.file_links
   where entity_type = 'job' and entity_id = 'eb000000-0000-0000-0000-000000000001' and role = 'report_photo'),
  '{"ee000000-0000-0000-0000-000000000002": false}'::jsonb,
  'the restored photo, no longer on the report or a live link, loses its report link; the other is unprotected');

select * from finish();

rollback;
