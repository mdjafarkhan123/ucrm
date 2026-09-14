begin;

create extension if not exists pgtap with schema extensions;
select plan(33);

-- Structure ------------------------------------------------------------------------------------------------------
select has_column('public', 'communication_sms_sender_identities', 'is_default_sender',
  'a sender identity records whether it is the default sending number');
select has_index('public', 'communication_sms_sender_identities',
  'communication_sms_sender_identities_one_default_idx',
  'at most one default sending number per organization is enforced by index');
select has_table('public', 'communication_sms_compliance_settings',
  'SMS compliance settings are a first-class per-organization record');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.communication_sms_compliance_settings'::regclass),
  'compliance settings keep row-level security enabled');
select table_privs_are('public', 'communication_sms_compliance_settings', 'authenticated', array[]::text[],
  'authenticated clients cannot read compliance settings directly');
select table_privs_are('public', 'communication_sms_compliance_settings', 'service_role', array['SELECT'],
  'the server may read compliance settings but writes go through the command');

-- Fixtures -------------------------------------------------------------------------------------------------------
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('c3c0ac70-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner-3c@example.test', 'test', now(), now(), now()),
  ('c3c0ac70-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'other-3c@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c3c00000-0000-4000-8000-000000000001', 'Numbers Org A', 'numbers-org-a', 'active'),
  ('c3c00000-0000-4000-8000-000000000002', 'Numbers Org B', 'numbers-org-b', 'active');

insert into public.communication_sms_sender_identities (
  id, organization_id, phone_number, display_name, lifecycle_state, capable_sms
) values
  ('c3c0be00-0000-4000-8000-000000000001', 'c3c00000-0000-4000-8000-000000000001',
   '+15125550101', 'Main line', 'ready', true),
  ('c3c0be00-0000-4000-8000-000000000002', 'c3c00000-0000-4000-8000-000000000001',
   '+15125550102', 'Backup line', 'ready', true),
  ('c3c0be00-0000-4000-8000-000000000003', 'c3c00000-0000-4000-8000-000000000001',
   '+15125550103', 'Voice only', 'ready', false),
  ('c3c0be00-0000-4000-8000-000000000004', 'c3c00000-0000-4000-8000-000000000001',
   '+15125550104', 'Not yet ready', 'pending_setup', true);

-- Rename ---------------------------------------------------------------------------------------------------------
select is(
  (public.communication_sms_rename_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000001',
    '  Front desk  ', 'c3c0ac70-0000-4000-8000-000000000001')).display_name,
  'Front desk',
  'renaming a number trims and stores its friendly label');
select is(
  (public.communication_sms_rename_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000001',
    '   ', 'c3c0ac70-0000-4000-8000-000000000001')).display_name,
  null,
  'clearing the name to blank stores null');
select throws_ok(
  $$select public.communication_sms_rename_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000001',
    'x', null)$$,
  'P0001', null, 'a rename must record who made it');
select throws_ok(
  format($$select public.communication_sms_rename_sender(%L, %L, %L, %L)$$,
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000001',
    repeat('a', 61), 'c3c0ac70-0000-4000-8000-000000000001'),
  'P0001', null, 'a name longer than 60 characters is refused');
select throws_ok(
  $$select public.communication_sms_rename_sender(
    'c3c00000-0000-4000-8000-000000000002', 'c3c0be00-0000-4000-8000-000000000001',
    'Hijack', 'c3c0ac70-0000-4000-8000-000000000002')$$,
  'P0001', null, 'another organization cannot rename a number it does not own');

-- Default sending number -----------------------------------------------------------------------------------------
select is(
  (public.communication_sms_set_default_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000001',
    'c3c0ac70-0000-4000-8000-000000000001')).is_default_sender,
  true,
  'a ready SMS-capable number can be made the default');
select is(
  (select count(*)::int from public.communication_sms_sender_identities
   where organization_id = 'c3c00000-0000-4000-8000-000000000001' and is_default_sender),
  1, 'exactly one default exists after the first choice');
-- Switching the default clears the previous one in the same transaction.
select lives_ok(
  $$select public.communication_sms_set_default_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000002',
    'c3c0ac70-0000-4000-8000-000000000001')$$,
  'the default can be moved to another ready number');
select is(
  (select count(*)::int from public.communication_sms_sender_identities
   where organization_id = 'c3c00000-0000-4000-8000-000000000001' and is_default_sender),
  1, 'switching the default leaves exactly one default');
select is(
  (select is_default_sender from public.communication_sms_sender_identities
   where id = 'c3c0be00-0000-4000-8000-000000000001'),
  false, 'the previous default is cleared when a new one is chosen');
select throws_ok(
  $$select public.communication_sms_set_default_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000003',
    'c3c0ac70-0000-4000-8000-000000000001')$$,
  'P0001', null, 'a number that cannot send SMS cannot be the default');
select throws_ok(
  $$select public.communication_sms_set_default_sender(
    'c3c00000-0000-4000-8000-000000000001', 'c3c0be00-0000-4000-8000-000000000004',
    'c3c0ac70-0000-4000-8000-000000000001')$$,
  'P0001', null, 'a number still setting up cannot be the default');
select throws_ok(
  $$select public.communication_sms_set_default_sender(
    'c3c00000-0000-4000-8000-000000000002', 'c3c0be00-0000-4000-8000-000000000002',
    'c3c0ac70-0000-4000-8000-000000000002')$$,
  'P0001', null, 'another organization cannot set a default on a number it does not own');

-- Compliance settings --------------------------------------------------------------------------------------------
select is(
  (public.communication_sms_set_compliance_settings(
    'c3c00000-0000-4000-8000-000000000001', true, '  Reply STOP to opt out  ', true, '  Acme Services  ',
    14, 'c3c0ac70-0000-4000-8000-000000000001')).periodic_reinsert_days,
  14, 'the first compliance save creates the row with the chosen interval');
select is(
  (select opt_out_text from public.communication_sms_compliance_settings
   where organization_id = 'c3c00000-0000-4000-8000-000000000001'),
  'Reply STOP to opt out', 'compliance text is trimmed on save');
select is(
  (select count(*)::int from public.communication_sms_compliance_settings
   where organization_id = 'c3c00000-0000-4000-8000-000000000001'),
  1, 'there is one compliance row per organization');
-- A second save updates the same row rather than inserting a duplicate.
select is(
  (public.communication_sms_set_compliance_settings(
    'c3c00000-0000-4000-8000-000000000001', false, null, true, 'Acme Services',
    45, 'c3c0ac70-0000-4000-8000-000000000001')).opt_out_enabled,
  false, 'a later compliance save updates the existing row');
select is(
  (select count(*)::int from public.communication_sms_compliance_settings
   where organization_id = 'c3c00000-0000-4000-8000-000000000001'),
  1, 'updating compliance settings never creates a second row');
select is(
  (select opt_out_text from public.communication_sms_compliance_settings
   where organization_id = 'c3c00000-0000-4000-8000-000000000001'),
  null, 'clearing the custom opt-out text stores null (system default is used)');
select throws_ok(
  $$select public.communication_sms_set_compliance_settings(
    'c3c00000-0000-4000-8000-000000000001', true, null, true, null, 0,
    'c3c0ac70-0000-4000-8000-000000000001')$$,
  'P0001', null, 'a re-insertion interval below 1 day is refused');
select throws_ok(
  $$select public.communication_sms_set_compliance_settings(
    'c3c00000-0000-4000-8000-000000000001', true, null, true, null, 61,
    'c3c0ac70-0000-4000-8000-000000000001')$$,
  'P0001', null, 'a re-insertion interval above 60 days is refused');
select throws_ok(
  format($$select public.communication_sms_set_compliance_settings(%L, true, %L, true, null, 30, %L)$$,
    'c3c00000-0000-4000-8000-000000000001', repeat('x', 321), 'c3c0ac70-0000-4000-8000-000000000001'),
  'P0001', null, 'opt-out wording longer than 320 characters is refused');
select throws_ok(
  $$select public.communication_sms_set_compliance_settings(
    'c3c00000-0000-4000-8000-000000000001', true, null, true, null, 30, null)$$,
  'P0001', null, 'a compliance change must record who made it');
select throws_ok(
  $$select public.communication_sms_set_compliance_settings(
    'c3c00000-0000-4000-8000-000000000001', null, null, true, null, 30,
    'c3c0ac70-0000-4000-8000-000000000001')$$,
  'P0001', null, 'the compliance toggles are required');

-- Command privileges ---------------------------------------------------------------------------------------------
select function_privs_are('public', 'communication_sms_set_default_sender', array['uuid', 'uuid', 'uuid'],
  'authenticated', array[]::text[], 'contractors cannot call the default-sender command directly');
select function_privs_are('public', 'communication_sms_set_default_sender', array['uuid', 'uuid', 'uuid'],
  'service_role', array['EXECUTE'], 'the checked API may set the default sending number');
select function_privs_are('public', 'communication_sms_set_compliance_settings',
  array['uuid', 'boolean', 'text', 'boolean', 'text', 'integer', 'uuid'],
  'service_role', array['EXECUTE'], 'the checked API may save compliance settings');

select * from finish();
rollback;
