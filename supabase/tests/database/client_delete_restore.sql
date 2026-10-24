-- Data privacy Part 6: delete a customer to Recently Deleted and restore them. Plan:
-- docs/data-privacy-deletion-behavior-contract.md § Deleting a customer. Design:
-- docs/data-privacy-client-delete-restore.md.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end (see client_permanent_delete.sql).
begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

-- 1. Privileges ------------------------------------------------------------------------------------------------

select is(has_function_privilege('anon', 'public.delete_clients(uuid[])', 'execute'), false,
  'signed-out callers cannot delete clients');
select is(has_function_privilege('anon', 'public.restore_client_deletions(uuid[], text)', 'execute'), false,
  'signed-out callers cannot restore clients');
select is(has_table_privilege('authenticated', 'public.client_deletions', 'select'), false,
  'members read delete records only through the Recently Deleted function');

-- 2. Fixtures --------------------------------------------------------------------------------------------------
-- Ann has work, a conversation and a draft invoice and can go. Bob has a text mid-send and cannot. Olive is
-- an office member without customers.delete.

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at,
  updated_at)
values
  ('c6100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'delete-owner@example.test', 'test', now(), now(), now()),
  ('c6100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'delete-office@example.test', 'test', now(), now(), now());

insert into public.profiles (id, full_name)
values ('c6100000-0000-0000-0000-000000000001', 'Owen Owner')
on conflict (id) do update set full_name = excluded.full_name;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c6200000-0000-0000-0000-000000000001', 'Delete Restore Co', 'delete-restore-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c6200000-0000-0000-0000-000000000001', 'c6100000-0000-0000-0000-000000000001', 'owner'),
  ('c6200000-0000-0000-0000-000000000001', 'c6100000-0000-0000-0000-000000000002', 'office');

insert into public.clients (id, organization_id, display_name)
values
  ('c6300000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001', 'Ann Deleted'),
  ('c6300000-0000-0000-0000-000000000002', 'c6200000-0000-0000-0000-000000000001', 'Bob Owes'),
  ('c6300000-0000-0000-0000-000000000003', 'c6200000-0000-0000-0000-000000000001', 'Cal Merged');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('c6320000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
   'c6300000-0000-0000-0000-000000000001', 'phone', '+1 (512) 555-0601', true),
  ('c6320000-0000-0000-0000-000000000002', 'c6200000-0000-0000-0000-000000000001',
   'c6300000-0000-0000-0000-000000000001', 'email', 'ann.deleted@example.test', true),
  ('c6320000-0000-0000-0000-000000000003', 'c6200000-0000-0000-0000-000000000001',
   'c6300000-0000-0000-0000-000000000003', 'email', 'cal@example.test', true);

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('c6400000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000001', '6 Hidden Road', 'Testville', 'TX', '78741');

insert into public.requests (id, organization_id, client_id, property_id, title)
values ('c6450000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001', 'Gutter request');

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('c6500000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001', 9601, 'Gutter quote', 'USD');

insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis,
  currency_code)
values ('c6800000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001', 9602, 'Gutter job',
  'one_off', 'job_total', 'USD');

insert into public.job_visits (id, organization_id, job_id, position, visit_date)
values ('c6810000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6800000-0000-0000-0000-000000000001', 0, current_date + 3);

insert into public.communication_inbound_messages (
  id, organization_id, client_id, client_contact_method_id, provider, provider_message_id, channel, sender_phone,
  subject, text_content, attachment_count
) values ('c6840000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000001', 'c6320000-0000-0000-0000-000000000001', 'twilio',
  'SMdelrestore000000000000000000001', 'sms', '+15125550601', '', 'Are you coming Tuesday?', 0);

-- Bob has a text going out right now, which holds the delete like open money does.
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('c6320000-0000-0000-0000-000000000004', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000002', 'phone', '+1 (512) 555-0602', true);
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key, recipient_phone, status
) values ('c6830000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000002', 'c6320000-0000-0000-0000-000000000004', 'sms', 'delrestore-sms-1',
  '+15125550602', 'claimed');

-- 3. Who may delete ------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c6100000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$ select public.delete_clients(array['c6300000-0000-0000-0000-000000000001'::uuid]) $$,
  '42501', null, 'an office member without the permission is refused by the server');
select throws_ok($$ select * from public.recently_deleted_clients() $$, '42501', null,
  'and cannot open Recently Deleted');

select set_config('request.jwt.claim.sub', 'c6100000-0000-0000-0000-000000000001', true);

-- 4. Preview and the money refusal ------------------------------------------------------------------------

create temporary table preview as
  select public.client_delete_preview(array[
    'c6300000-0000-0000-0000-000000000001'::uuid, 'c6300000-0000-0000-0000-000000000002'::uuid]) as result;

select is((select jsonb_array_length(result -> 'clients') from preview), 2, 'the preview names both clients');
select is((select (result -> 'totals' ->> 'jobs')::int from preview), 1,
  'totals count only the clients that can go');
select is((select (c -> 'counts' ->> 'messages')::int from preview, jsonb_array_elements(result -> 'clients') c
  where c ->> 'display_name' = 'Ann Deleted'), 1, 'Ann''s conversation is counted');
select is((select c -> 'blockers' -> 0 ->> 'kind' from preview, jsonb_array_elements(result -> 'clients') c
  where c ->> 'display_name' = 'Bob Owes'), 'message_sending', 'Bob''s reason is named');

create temporary table bob_only as
  select public.delete_clients(array['c6300000-0000-0000-0000-000000000002'::uuid]) as result;
select is((select jsonb_array_length(result -> 'deleted') from bob_only), 0, 'Bob is not deleted');
select is((select result -> 'left_out' -> 0 ->> 'display_name' from bob_only), 'Bob Owes',
  'and comes back as left out with his reasons');

-- 5. Delete ---------------------------------------------------------------------------------------------------

create temporary table deleted_ann as
  select public.delete_clients(array['c6300000-0000-0000-0000-000000000001'::uuid]) as result;
grant select on deleted_ann to authenticated;

select is((select jsonb_array_length(result -> 'deleted') from deleted_ann), 1, 'Ann moves to Recently Deleted');

select is((select count(*)::int from public.clients where id = 'c6300000-0000-0000-0000-000000000001'), 0,
  'Ann leaves the clients list for members');
select is((select count(*)::int from public.jobs where id = 'c6800000-0000-0000-0000-000000000001'), 0,
  'her job is hidden');
select is((select count(*)::int from public.job_visits where id = 'c6810000-0000-0000-0000-000000000001'), 0,
  'her visit leaves the schedule');
select is((select count(*)::int from public.quotes where id = 'c6500000-0000-0000-0000-000000000001'), 0,
  'her quote is hidden');
select is((select count(*)::int from public.requests where id = 'c6450000-0000-0000-0000-000000000001'), 0,
  'her request is hidden');
select is((select count(*)::int from public.properties where id = 'c6400000-0000-0000-0000-000000000001'), 0,
  'her property is hidden');
select is((select count(*)::int from public.clients where id = 'c6300000-0000-0000-0000-000000000002'), 1,
  'Bob is still there');

create temporary table bin as select * from public.recently_deleted_clients();
select is((select count(*)::int from bin where display_name = 'Ann Deleted'), 1, 'Recently Deleted lists Ann');
select is((select deleted_by_name from bin where display_name = 'Ann Deleted'), 'Owen Owner',
  'with who deleted her');
select is((select (purge_after - deleted_at) from bin where display_name = 'Ann Deleted'), interval '30 days',
  'and her day 30');
select is((select (counts ->> 'visits')::int from bin where display_name = 'Ann Deleted'), 1,
  'and what comes back, counted at delete time');

set local role postgres;
select throws_ok(
  $$ insert into public.jobs (organization_id, client_id, job_number, title, job_type, price_basis, currency_code)
     values ('c6200000-0000-0000-0000-000000000001', 'c6300000-0000-0000-0000-000000000001', 9699, 'New',
       'one_off', 'job_total', 'USD') $$,
  '55000', 'This client is in Recently Deleted. Restore them first.',
  'new work for a deleted client is refused, even by the server');
select throws_ok(
  $$ update public.job_visits set visit_date = current_date + 9 where id = 'c6810000-0000-0000-0000-000000000001' $$,
  '55000', null, 'a hidden visit cannot be moved, even by the server');

select is((select count(*)::int from public.activity_events
  where entity_id = 'c6300000-0000-0000-0000-000000000001' and event_type = 'client.deleted'), 1,
  'the history records the delete');
select is(private.marketing_recipient_blocked_reason('c6200000-0000-0000-0000-000000000001',
  'c6300000-0000-0000-0000-000000000001', 'c6320000-0000-0000-0000-000000000002', 'ann.deleted@example.test'),
  'inactive_customer', 'marketing treats a deleted client as inactive');

-- 6. They get in touch again ---------------------------------------------------------------------------------

set local role service_role;
create temporary table ann_texts as
  select * from public.record_communication_sms_inbound_message('c6200000-0000-0000-0000-000000000001',
    'SMdelrestore000000000000000000002', '+15125550601', 'Hello again', 0);
set local role postgres;

select isnt((select client_id from ann_texts), 'c6300000-0000-0000-0000-000000000001'::uuid,
  'a text from Ann''s number arrives as a new contact');
select is((select count(*)::int from public.client_contact_methods
  where organization_id = 'c6200000-0000-0000-0000-000000000001' and normalized_value = '15125550601'), 2,
  'which can hold the same phone number while Ann is deleted');

-- 7. Restore with a newer client on the same phone ----------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c6100000-0000-0000-0000-000000000001', true);

create temporary table checked as
  select public.restore_client_deletions(array[(select deletion_id from bin where display_name = 'Ann Deleted')],
    'check') as result;
select is((select jsonb_array_length(result -> 'restored') from checked), 0,
  'restore first asks about the newer client');
select is((select result -> 'matches' -> 0 ->> 'kind' from checked), 'phone', 'naming the shared phone');

create temporary table separate as
  select public.restore_client_deletions(array[(select deletion_id from bin where display_name = 'Ann Deleted')],
    'separate') as result;
select is((select jsonb_array_length(result -> 'restored') from separate), 1, 'Ann is restored as her own client');

select is((select count(*)::int from public.jobs where id = 'c6800000-0000-0000-0000-000000000001'), 1,
  'her job is back');
select is((select count(*)::int from public.job_visits where id = 'c6810000-0000-0000-0000-000000000001'), 1,
  'her visit is back on the schedule');
select is((select count(*)::int from public.properties where id = 'c6400000-0000-0000-0000-000000000001'), 1,
  'her property is back');
select is((select count(*)::int from public.client_contact_methods
  where client_id = 'c6300000-0000-0000-0000-000000000001' and kind = 'email'), 1, 'her email is back');
select is((select count(*)::int from public.client_contact_methods
  where client_id = 'c6300000-0000-0000-0000-000000000001' and kind = 'phone'), 0,
  'her phone stays with the newer client');
select is((select count(*)::int from public.recently_deleted_clients() where display_name = 'Ann Deleted'), 0,
  'she leaves Recently Deleted');

-- 8. Restore and merge ----------------------------------------------------------------------------------------

create temporary table deleted_cal as
  select public.delete_clients(array['c6300000-0000-0000-0000-000000000003'::uuid]) as result;
set local role postgres;
insert into public.clients (id, organization_id, display_name)
values ('c6300000-0000-0000-0000-000000000004', 'c6200000-0000-0000-0000-000000000001', 'Cal New');
insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
values ('c6200000-0000-0000-0000-000000000001', 'c6300000-0000-0000-0000-000000000004', 'email',
  'cal@example.test', true);
set local role authenticated;

select lives_ok($$ select public.restore_client_deletions(array[(select (result -> 'deleted' -> 0 ->> 'deletion_id')::uuid
  from deleted_cal)], 'merge') $$, 'Cal is restored and merged into the newer Cal');
select is((select count(*)::int from public.clients where id = 'c6300000-0000-0000-0000-000000000004'), 1,
  'the newer Cal remains');
select is((select count(*)::int from public.client_contact_methods
  where client_id = 'c6300000-0000-0000-0000-000000000004' and kind = 'email'), 1,
  'with one copy of the shared email');

-- 9. Day 30 hands over to the permanent delete ---------------------------------------------------------------

create temporary table deleted_again as
  select public.delete_clients(array['c6300000-0000-0000-0000-000000000001'::uuid]) as result;

set local role postgres;
update public.client_deletions set purge_after = now() - interval '1 minute'
where client_id = 'c6300000-0000-0000-0000-000000000001' and restored_at is null;

select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select is((select count(*)::int from public.claim_due_client_deletions(5)
  where client_id = 'c6300000-0000-0000-0000-000000000001'), 1, 'the hourly job finds Ann once her 30 days are up');
select is((select count(*)::int from public.claim_due_client_deletions(5)
  where client_id = 'c6300000-0000-0000-0000-000000000001'), 0, 'and a second run does not take her while she is leased');
select is(public.record_client_deletion_purge_failure((select id from public.client_deletions
  where client_id = 'c6300000-0000-0000-0000-000000000001' and restored_at is null), 'Test refusal'), false,
  'a first refusal is kept without an alert');
set local role postgres;
update public.client_deletions set purge_failed_since = now() - interval '2 days'
where client_id = 'c6300000-0000-0000-0000-000000000001' and restored_at is null;
set local role service_role;
select is(public.record_client_deletion_purge_failure((select id from public.client_deletions
  where client_id = 'c6300000-0000-0000-0000-000000000001' and restored_at is null), 'Test refusal'), true,
  'after a day of refusals one alert is due');
create temporary table purged as
  select public.run_client_purge('c6200000-0000-0000-0000-000000000001', 'c6300000-0000-0000-0000-000000000001',
    'scheduled', null, null, null) as result;
set local role postgres;

select is((select (result ->> 'applied')::boolean from purged), true, 'the permanent delete runs on a deleted client');
select isnt((select purged_at from public.client_deletions
  where client_id = 'c6300000-0000-0000-0000-000000000001' and restored_at is null), null,
  'and closes the delete record');
select is((select count(*)::int from public.jobs where id = 'c6800000-0000-0000-0000-000000000001'), 0,
  'her job is gone for good');

select * from finish();
rollback;
