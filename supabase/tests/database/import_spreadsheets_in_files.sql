-- Import spreadsheets belong to the File Manager: public.register_import_file files an import batch's spreadsheet
-- as a pending File with origin "import" in the business's Imports folder. Migration
-- 20270109096000_import_spreadsheets_in_files.sql.
--
-- Run as one transaction that is rolled back at the end, the same convention client_permanent_delete.sql uses.
begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('b9200000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'import-files-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b9210000-0000-0000-0000-000000000001', 'Import Files Co', 'import-files-co', 'active'),
  ('b9210000-0000-0000-0000-000000000002', 'Import Files Other', 'import-files-other', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('b9210000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001', 'owner');

insert into public.import_batches (id, organization_id, entity_type, created_by, source_filename, storage_object_key,
  file_row_count)
values
  ('b9220000-0000-0000-0000-000000000001', 'b9210000-0000-0000-0000-000000000001', 'client',
   'b9200000-0000-0000-0000-000000000001', 'customers.csv',
   'b9210000-0000-0000-0000-000000000001/client-imports/abc-customers.csv', 3),
  ('b9220000-0000-0000-0000-000000000002', 'b9210000-0000-0000-0000-000000000001', 'opening_balance',
   'b9200000-0000-0000-0000-000000000001', 'balances.csv',
   'b9210000-0000-0000-0000-000000000001/opening-balance-imports/def-balances.csv', 2),
  ('b9220000-0000-0000-0000-000000000003', 'b9210000-0000-0000-0000-000000000001', 'client',
   'b9200000-0000-0000-0000-000000000001', 'stray.csv',
   'b9210000-0000-0000-0000-000000000002/client-imports/stray.csv', 1);

create temporary table filed as
select * from public.register_import_file('b9210000-0000-0000-0000-000000000001',
  'b9220000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001', 151);

select is((select row(display_name, mime_type, size_bytes, origin_type, origin_id, processing_state)::text from filed),
  row('customers.csv', 'text/csv', 151::bigint, 'import', 'b9220000-0000-0000-0000-000000000001'::uuid,
      'pending')::text,
  'the spreadsheet becomes a pending File that came from the import');
select ok((select upload_completed_at is not null from filed),
  'it is ready for the processing worker to check, so the abandoned-upload sweep never takes it');
select is((select object_key from filed), 'b9210000-0000-0000-0000-000000000001/client-imports/abc-customers.csv',
  'the File keeps the key the import reads');
select is((select folder.name from public.file_folders as folder join filed on filed.folder_id = folder.id),
  'Imports', 'it lands in an Imports folder');

select is((select id from public.register_import_file('b9210000-0000-0000-0000-000000000001',
  'b9220000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001', 151)),
  (select id from filed), 'filing the same import twice returns the same File');

select is((select folder_id from public.register_import_file('b9210000-0000-0000-0000-000000000001',
  'b9220000-0000-0000-0000-000000000002', 'b9200000-0000-0000-0000-000000000001', 90)),
  (select folder_id from filed), 'an opening-balance import goes into the same Imports folder');

select throws_ok($$select public.register_import_file('b9210000-0000-0000-0000-000000000001',
  'b9220000-0000-0000-0000-000000000003', 'b9200000-0000-0000-0000-000000000001', 10)$$,
  '23514', null, 'a key under another business''s prefix is refused');

select ok(not has_function_privilege('authenticated',
  'public.register_import_file(uuid, uuid, uuid, bigint)', 'execute'),
  'only the server can file an import spreadsheet');

select * from finish();
rollback;
