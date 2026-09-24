-- Files and Media, Part 7B-2: photo captions and labels are shown.
--
--   1. The report editor and Preview as client carry each photo's caption and label names.
--   2. An issued customer link keeps the caption and label names it was sent with, through a later caption
--      edit and a label rename.
--   3. list_files returns the caption, matches it in search, and narrows to one label.
--
-- Written for `supabase test db`, which runs the file as one session.

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('f7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'caption-admin@example.test', 'test', now(), now(), now());

-- The organization trigger seeds Before / During / After / Damage.
insert into public.organizations (id, name, slug, lifecycle_status)
values ('f8000000-0000-0000-0000-000000000001', 'Caption Co', 'caption-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values ('f8000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001', 'admin', 'active');

insert into public.clients (id, organization_id, display_name)
values ('f9000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001', 'Cara Caption');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values ('fc000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001',
        'f9000000-0000-0000-0000-000000000001', 'email', 'cara@example.test');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('fa000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001',
        'f9000000-0000-0000-0000-000000000001', '9 Caption Court', 'Testville', 'TX', '78741');

insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code)
values ('fb000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001',
        'f9000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000001',
        900, 'Fence repair', 'one_off', 'job_total', 'USD');

-- 1 a captioned, labelled photo; 2 a plain photo.
insert into public.files (id, organization_id, display_name, mime_type, size_bytes, object_key,
                          origin_type, processing_state, uploaded_by, scanned_at, checksum_sha256)
values
  ('fe000000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001', 'fence-1.jpg',
   'image/jpeg', 2048, 'f8/files/1.jpg', 'file_manager', 'available',
   'f7000000-0000-0000-0000-000000000001', now(), repeat('a', 64)),
  ('fe000000-0000-0000-0000-000000000002', 'f8000000-0000-0000-0000-000000000001', 'fence-2.jpg',
   'image/jpeg', 2048, 'f8/files/2.jpg', 'file_manager', 'available',
   'f7000000-0000-0000-0000-000000000001', now(), repeat('b', 64));

insert into public.file_links (organization_id, file_id, entity_type, entity_id, role)
values
  ('f8000000-0000-0000-0000-000000000001', 'fe000000-0000-0000-0000-000000000001', 'job', 'fb000000-0000-0000-0000-000000000001', 'attachment'),
  ('f8000000-0000-0000-0000-000000000001', 'fe000000-0000-0000-0000-000000000002', 'job', 'fb000000-0000-0000-0000-000000000001', 'attachment');

-- Caption and two labels, through the same command the details panel uses.
select public.describe_file(
  'f8000000-0000-0000-0000-000000000001', 'fe000000-0000-0000-0000-000000000001',
  'f7000000-0000-0000-0000-000000000001', true, 'Rotten post replaced',
  array(select id from public.file_labels
        where organization_id = 'f8000000-0000-0000-0000-000000000001' and name in ('After', 'Damage')));

-- ---------------------------------------------------------------------------------------------------------
-- 1. Editor and preview
-- ---------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f7000000-0000-0000-0000-000000000001', true);

select is(
  (select photo - 'mime_type' - 'has_thumbnail' - 'created_at' - 'file_name'
   from jsonb_array_elements(public.job_report_state('fb000000-0000-0000-0000-000000000001') -> 'candidates' -> 'photos') photo
   where photo ->> 'file_id' = 'fe000000-0000-0000-0000-000000000001'),
  '{"file_id": "fe000000-0000-0000-0000-000000000001", "caption": "Rotten post replaced", "labels": ["After", "Damage"]}'::jsonb,
  'the editor shows a candidate photo''s caption and labels, alphabetical');

select is(
  (select photo from jsonb_array_elements(public.job_report_state('fb000000-0000-0000-0000-000000000001') -> 'candidates' -> 'photos') photo
   where photo ->> 'file_id' = 'fe000000-0000-0000-0000-000000000002') -> 'labels',
  '[]'::jsonb, 'a plain photo has an empty label list, not null');

select public.save_job_report('fb000000-0000-0000-0000-000000000001', false, false, null, null,
  '{"top": [{"file_id": "fe000000-0000-0000-0000-000000000001"}, {"file_id": "fe000000-0000-0000-0000-000000000002"}], "sections": []}'::jsonb);

select is(
  (select photo - 'file_name' from jsonb_array_elements(
     public.job_report_customer_preview('fb000000-0000-0000-0000-000000000001') -> 'document' -> 'photos') photo
   where photo ->> 'file_id' = 'fe000000-0000-0000-0000-000000000001'),
  '{"file_id": "fe000000-0000-0000-0000-000000000001", "caption": "Rotten post replaced", "labels": ["After", "Damage"]}'::jsonb,
  'Preview as client carries the caption and label names');

-- ---------------------------------------------------------------------------------------------------------
-- 2. An issued link keeps what was sent
-- ---------------------------------------------------------------------------------------------------------

select public.issue_job_report_access_link('fb000000-0000-0000-0000-000000000001', decode(repeat('cd', 32), 'hex'));

reset role;

select public.describe_file(
  'f8000000-0000-0000-0000-000000000001', 'fe000000-0000-0000-0000-000000000001',
  'f7000000-0000-0000-0000-000000000001', true, 'Changed later', null);

select public.rename_file_label(
  'f8000000-0000-0000-0000-000000000001',
  (select id from public.file_labels where organization_id = 'f8000000-0000-0000-0000-000000000001' and name = 'After'),
  'f7000000-0000-0000-0000-000000000001', 'Finished');

select is(
  public.resolve_job_report_access_link(decode(repeat('cd', 32), 'hex')) -> 'photos' -> 0 ->> 'caption',
  'Rotten post replaced', 'the customer''s link keeps the caption it was sent with');

select is(
  public.resolve_job_report_access_link(decode(repeat('cd', 32), 'hex')) -> 'photos' -> 0 -> 'labels',
  '["After", "Damage"]'::jsonb, 'the customer''s link keeps the label names it was sent with');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f7000000-0000-0000-0000-000000000001', true);

select is(
  (select photo ->> 'caption' from jsonb_array_elements(
     public.job_report_customer_preview('fb000000-0000-0000-0000-000000000001') -> 'document' -> 'photos') photo
   where photo ->> 'file_id' = 'fe000000-0000-0000-0000-000000000001'),
  'Changed later', 'the editable report shows the new caption');

-- ---------------------------------------------------------------------------------------------------------
-- 3. The File Manager list
-- ---------------------------------------------------------------------------------------------------------

select is(
  (select caption from public.list_files('f8000000-0000-0000-0000-000000000001')
   where id = 'fe000000-0000-0000-0000-000000000001'),
  'Changed later', 'a list row carries the caption');

select is(
  (select array_agg(id) from public.list_files('f8000000-0000-0000-0000-000000000001', target_search => 'CHANGED')),
  array['fe000000-0000-0000-0000-000000000001']::uuid[], 'search matches a caption, ignoring case');

select is(
  (select array_agg(id) from public.list_files('f8000000-0000-0000-0000-000000000001', 'photos',
     target_label_id => (select id from public.file_labels
                         where organization_id = 'f8000000-0000-0000-0000-000000000001' and name = 'Damage'))),
  array['fe000000-0000-0000-0000-000000000001']::uuid[], 'the label view lists only photos carrying that label');

select is(
  (select count(*)::int from public.list_files('f8000000-0000-0000-0000-000000000001', 'photos',
     target_label_id => (select id from public.file_labels
                         where organization_id = 'f8000000-0000-0000-0000-000000000001' and name = 'During'))),
  0, 'a label no photo carries lists nothing');

select * from finish();

rollback;
