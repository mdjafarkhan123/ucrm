-- Data privacy Part 3: the permanent customer delete engine (private.apply_client_purge through
-- public.run_client_purge). Plan: docs/data-privacy-deletion-behavior-contract.md § Money records after any
-- delete, § "Don't contact me" survives deletion. Design: docs/data-privacy-deletion-engine.md.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention invoices_payments_ledger.sql documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and `set_config`
-- do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(66);

-- 1. Privileges ------------------------------------------------------------------------------------------------

select is(has_function_privilege('anon',
  'public.run_client_purge(uuid, uuid, text, uuid, text, text)', 'execute'),
  false, 'signed-out callers cannot permanently delete a customer');
select is(has_function_privilege('authenticated',
  'public.run_client_purge(uuid, uuid, text, uuid, text, text)', 'execute'),
  false, 'members cannot reach the server-only delete directly');
select is(has_function_privilege('service_role',
  'public.run_client_purge(uuid, uuid, text, uuid, text, text)', 'execute'),
  true, 'the server can run the scheduled and Jafar deletes');
select is(has_table_privilege('authenticated', 'public.contact_opt_out_fingerprints', 'select'),
  false, 'members cannot read the opt-out fingerprints');
select is(has_table_privilege('authenticated', 'public.client_deletion_receipts', 'select'),
  false, 'members cannot read delete receipts directly');

-- 2. Fixtures --------------------------------------------------------------------------------------------------
-- Pat is the customer who asked to be forgotten and has one of nearly everything. Bea, in the same business,
-- shares a note and a tag with Pat and must come through untouched. A second business holds Pat's phone too.

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('b7100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'purge-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b7200000-0000-0000-0000-000000000001', 'Purge Engine Co', 'purge-engine-co', 'active'),
  ('b7200000-0000-0000-0000-000000000002', 'Purge Engine Other', 'purge-engine-other', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('b7200000-0000-0000-0000-000000000001', 'b7100000-0000-0000-0000-000000000001', 'owner');

insert into public.clients (
  id, organization_id, display_name, first_name, last_name, company_name, billing_address_line1, billing_city
)
values
  ('b7300000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001', 'Pat Purgeable', 'Pat',
   'Purgeable', 'Purgeable Homes', '9 Forget Lane', 'Testville'),
  ('b7300000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001', 'Bystander Bea', 'Bea',
   'Bystander', null, null, null),
  ('b7300000-0000-0000-0000-000000000003', 'b7200000-0000-0000-0000-000000000002', 'Pat Elsewhere', null,
   null, null, null, null);

insert into public.client_contacts (id, organization_id, client_id, first_name, last_name, is_primary)
values ('b7310000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
  'b7300000-0000-0000-0000-000000000001', 'Pat', 'Purgeable', true);

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('b7320000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', 'phone', '+1 (512) 555-0199', true),
  ('b7320000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', 'email', 'Pat.Purgeable@example.test', true),
  ('b7320000-0000-0000-0000-000000000003', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000002', 'phone', '+1 (512) 555-0100', true);

insert into public.properties (
  id, organization_id, client_id, address_line1, city, state_region, postal_code, access_notes, latitude, longitude
)
values
  ('b7400000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', '9 Forget Lane', 'Testville', 'TX', '78741', 'Gate code 4321', null, null),
  ('b7400000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', '10 Forget Lane', 'Testville', 'TX', '78741', null, null, null),
  ('b7400000-0000-0000-0000-000000000003', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000002', '1 Bystander Way', 'Testville', 'TX', '78741', null, null, null);

insert into public.requests (id, organization_id, client_id, property_id, title)
values ('b7450000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
  'b7300000-0000-0000-0000-000000000001', 'b7400000-0000-0000-0000-000000000002', 'Fence quote for Pat');

-- Q1 took a $330 deposit, so it stays behind as an anonymous shell. Q2 is an ordinary quote and goes.
insert into public.quotes (id, organization_id, client_id, property_id, request_id, quote_number, title, currency_code)
values
  ('b7500000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', 'b7400000-0000-0000-0000-000000000001', null, 9701,
   'Roof for Pat Purgeable', 'USD'),
  ('b7500000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', 'b7400000-0000-0000-0000-000000000002',
   'b7450000-0000-0000-0000-000000000001', 9702, 'Fence for Pat Purgeable', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name,
  service_address_line1, service_city, client_message
)
values
  ('b7600000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
   'b7500000-0000-0000-0000-000000000001', 1, 'USD', 'Pat Purgeable', 'Purge Engine Co', '9 Forget Lane',
   'Testville', 'Hi Pat, here is your roof quote.'),
  ('b7600000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
   'b7500000-0000-0000-0000-000000000002', 1, 'USD', 'Pat Purgeable', 'Purge Engine Co', '10 Forget Lane',
   'Testville', null);

insert into public.quote_deposit_events (
  id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key
) values ('b7700000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
  'b7500000-0000-0000-0000-000000000001', 'b7600000-0000-0000-0000-000000000001',
  'received', 33000, 'stripe_card', 'purge-deposit-received');

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
  quote_id, quote_version_id
)
values
  ('b7800000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', 'b7400000-0000-0000-0000-000000000001', 9703, 'Roof job', 'one_off',
   'job_total', 'USD', 'b7500000-0000-0000-0000-000000000001', 'b7600000-0000-0000-0000-000000000001'),
  ('b7800000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000001', 'b7400000-0000-0000-0000-000000000002', 9704, 'Fence job', 'one_off',
   'job_total', 'USD', null, null);

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
) values
  ('b7820000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
   'b7800000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Roof work', 1, 120000, 0, false),
  ('b7820000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
   'b7800000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Fence work', 1, 50000, 0, false);

do $$ begin
  perform private.store_job_money('b7800000-0000-0000-0000-000000000001');
  perform private.store_job_money('b7800000-0000-0000-0000-000000000002');
end $$;

-- A Visit still to come, with the owner on it: deleting it must not tell the crew a named Visit was cancelled.
insert into public.job_visits (id, organization_id, job_id, position, visit_date)
values ('b7810000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
  'b7800000-0000-0000-0000-000000000002', 0, current_date + 7);
insert into public.job_visit_assignments (organization_id, visit_id, user_id, job_id)
values ('b7200000-0000-0000-0000-000000000001', 'b7810000-0000-0000-0000-000000000001',
  'b7100000-0000-0000-0000-000000000001', 'b7800000-0000-0000-0000-000000000002');

-- "Don't contact me": a text STOP, a marketing unsubscribe, a bounced address and Do not disturb.
insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values ('b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001',
  'b7320000-0000-0000-0000-000000000001', 'opt_out', 'client_reply', 'purge-stop', '2026-10-01 10:00+00');

insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
) values ('b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001',
  'b7320000-0000-0000-0000-000000000002', 'opt_out', 'unsubscribe', 'purge-unsubscribe', '2026-10-02 10:00+00');

insert into public.communication_email_suppressions (organization_id, recipient_email, reason, source)
values ('b7200000-0000-0000-0000-000000000001', 'pat.purgeable@example.test', 'hard_bounce', 'manual');

insert into public.client_communication_preferences (organization_id, client_id, contact_policy)
values ('b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001', 'do_not_disturb')
on conflict (organization_id, client_id) do update set contact_policy = excluded.contact_policy;

-- Messages: a text Twilio accepted that still waits for its final price (its credit is held, not yet charged),
-- an email that used its allowance and carried a library file, and a text Pat sent in with a photo.
insert into public.communication_sms_credit_accounts (organization_id, settled_balance_minor, reserved_balance_minor)
values ('b7200000-0000-0000-0000-000000000001', 10, 4);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key, recipient_phone, status,
  accepted_at, provider_message_id
) values ('b7830000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
  'b7300000-0000-0000-0000-000000000001', 'b7320000-0000-0000-0000-000000000001', 'sms', 'purge-sms-1',
  '+15125550199', 'submitted', now(), 'SMpurge00000000000000000000000001');

insert into public.communication_sms_credit_reservations (
  organization_id, delivery_intent_id, channel, source_key, amount_minor, segment_count,
  reserved_promotional_minor, reserved_purchased_minor
) values ('b7200000-0000-0000-0000-000000000001', 'b7830000-0000-0000-0000-000000000001', 'sms',
  'purge-sms-1', 4, 1, 0, 4);

insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key, recipient_email, subject,
  html_content, text_content, status, accepted_at, provider_message_id
) values ('b7830000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001',
  'b7300000-0000-0000-0000-000000000001', 'b7320000-0000-0000-0000-000000000002', 'email', 'purge-email-1',
  'pat.purgeable@example.test', 'Your roof plan, Pat', '<p>Hi Pat Purgeable</p>', 'Hi Pat Purgeable',
  'submitted', now(), 'ses-purge-1');

insert into public.communication_email_usage_events (organization_id, delivery_intent_id, recipient_count, event_kind)
values ('b7200000-0000-0000-0000-000000000001', 'b7830000-0000-0000-0000-000000000002', 1, 'provider_accepted');

insert into public.communication_outbound_attachments (
  organization_id, delivery_intent_id, file_name, mime_type, byte_size, object_key
) values ('b7200000-0000-0000-0000-000000000001', 'b7830000-0000-0000-0000-000000000002', 'roof-plan.pdf',
  'application/pdf', 1000, 'b7200000-0000-0000-0000-000000000001/outbound/roof-plan.pdf');

insert into public.communication_inbound_messages (
  id, organization_id, client_id, client_contact_method_id, provider, provider_message_id, channel, sender_phone,
  subject, text_content, attachment_count
) values ('b7840000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001',
  'b7300000-0000-0000-0000-000000000001', 'b7320000-0000-0000-0000-000000000001', 'twilio',
  'SMpurge00000000000000000000000002', 'sms', '+15125550199', '', 'Here is my gate, Pat', 1);

insert into public.communication_inbound_attachments (
  organization_id, inbound_message_id, file_name, mime_type, byte_size, object_key, status, provider
) values ('b7200000-0000-0000-0000-000000000001', 'b7840000-0000-0000-0000-000000000001', 'gate.jpg',
  'image/jpeg', 1000, 'b7200000-0000-0000-0000-000000000001/inbound/gate.jpg', 'available', 'twilio');

-- Messages never linked to anyone, waiting in review: two from Pat's own email (any case) and phone, one from a
-- stranger and one from the other customer's phone.
insert into public.communication_inbound_messages (
  id, organization_id, provider, provider_message_id, channel, sender_email, sender_phone, subject, text_content,
  review_status, review_reason
) values
  ('b7840000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001', 'ses', 'purge-unlinked-1',
   'email', ' PAT.Purgeable@Example.test', null, 'Before I was on file', 'Pat here', 'pending_review',
   'unknown_sender'),
  ('b7840000-0000-0000-0000-000000000003', 'b7200000-0000-0000-0000-000000000001', 'twilio', 'SMpurge-unlinked-2',
   'sms', null, '+15125550199', '', 'Pat again', 'pending_review', 'unknown_sender'),
  ('b7840000-0000-0000-0000-000000000004', 'b7200000-0000-0000-0000-000000000001', 'ses', 'purge-unlinked-3',
   'email', 'stranger@example.test', null, 'Hello', 'Not Pat', 'pending_review', 'unknown_sender'),
  ('b7840000-0000-0000-0000-000000000005', 'b7200000-0000-0000-0000-000000000001', 'twilio', 'SMpurge-unlinked-4',
   'sms', null, '+15125550100', '', 'The neighbour', 'pending_review', 'unknown_sender');

insert into public.communication_conversation_read_marks (organization_id, user_id, client_id, last_read_at)
values ('b7200000-0000-0000-0000-000000000001', 'b7100000-0000-0000-0000-000000000001',
  'b7300000-0000-0000-0000-000000000001', now());

-- Notes and tags: one note only about Pat, one shared with Bea.
insert into public.notes (id, organization_id, body)
values
  ('b7900000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001', 'Pat prefers mornings'),
  ('b7900000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001', 'Shared gate code 4321');
insert into public.note_links (organization_id, note_id, entity_type, entity_id)
values
  ('b7200000-0000-0000-0000-000000000001', 'b7900000-0000-0000-0000-000000000001', 'client',
   'b7300000-0000-0000-0000-000000000001'),
  ('b7200000-0000-0000-0000-000000000001', 'b7900000-0000-0000-0000-000000000001', 'job',
   'b7800000-0000-0000-0000-000000000001'),
  ('b7200000-0000-0000-0000-000000000001', 'b7900000-0000-0000-0000-000000000002', 'client',
   'b7300000-0000-0000-0000-000000000001'),
  ('b7200000-0000-0000-0000-000000000001', 'b7900000-0000-0000-0000-000000000002', 'client',
   'b7300000-0000-0000-0000-000000000002');

insert into public.tags (id, organization_id, name)
values ('b7950000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001', 'VIP');
insert into public.tag_assignments (organization_id, tag_id, entity_type, entity_id)
values
  ('b7200000-0000-0000-0000-000000000001', 'b7950000-0000-0000-0000-000000000001', 'client',
   'b7300000-0000-0000-0000-000000000001'),
  ('b7200000-0000-0000-0000-000000000001', 'b7950000-0000-0000-0000-000000000001', 'client',
   'b7300000-0000-0000-0000-000000000002');

insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary)
values ('b7200000-0000-0000-0000-000000000001', 'client', 'b7300000-0000-0000-0000-000000000001', 'call',
  'Called Pat Purgeable about the roof');

-- Files: Pat's own photo goes with them; a library price list linked to Pat, and a library file sent in the
-- email, stay in the library.
insert into public.files (
  id, organization_id, display_name, mime_type, size_bytes, object_key, origin_type, origin_id, origin_role,
  processing_state, scanned_at, checksum_sha256
)
values
  ('b7a00000-0000-0000-0000-000000000001', 'b7200000-0000-0000-0000-000000000001', 'pat-id.jpg', 'image/jpeg',
   1000, 'b7200000-0000-0000-0000-000000000001/files/pat-id.jpg', 'client',
   'b7300000-0000-0000-0000-000000000001', 'attachment', 'available', now(), repeat('a', 64)),
  ('b7a00000-0000-0000-0000-000000000002', 'b7200000-0000-0000-0000-000000000001', 'price-list.pdf',
   'application/pdf', 1000, 'b7200000-0000-0000-0000-000000000001/files/price-list.pdf', 'file_manager', null,
   'attachment', 'available', now(), repeat('b', 64)),
  ('b7a00000-0000-0000-0000-000000000003', 'b7200000-0000-0000-0000-000000000001', 'warranty.pdf',
   'application/pdf', 1000, 'b7200000-0000-0000-0000-000000000001/files/warranty.pdf', 'file_manager', null,
   'attachment', 'available', now(), repeat('c', 64));
insert into public.file_links (organization_id, file_id, entity_type, entity_id, role)
values
  ('b7200000-0000-0000-0000-000000000001', 'b7a00000-0000-0000-0000-000000000001', 'client',
   'b7300000-0000-0000-0000-000000000001', 'attachment'),
  ('b7200000-0000-0000-0000-000000000001', 'b7a00000-0000-0000-0000-000000000002', 'client',
   'b7300000-0000-0000-0000-000000000001', 'attachment'),
  ('b7200000-0000-0000-0000-000000000001', 'b7a00000-0000-0000-0000-000000000003', 'message',
   'b7830000-0000-0000-0000-000000000002', 'attachment');

-- The money: the roof bill spends the deposit and Pat pays the rest; a second bill stays a draft.
create temporary view pat_bill as
  select subject, id, revision, issued_at from public.invoices
  where organization_id = 'b7200000-0000-0000-0000-000000000001'
    and client_id = 'b7300000-0000-0000-0000-000000000001';
grant select on pat_bill to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7100000-0000-0000-0000-000000000001', true);

select public.create_invoice_from_work(
  'b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001', 'Roof',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Roof work', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 120000, 'is_taxable', false)),
  array['b7400000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-10-31'::date, '2026-10-01'::date,
  jsonb_build_array(jsonb_build_object('kind', 'job_total', 'job_id', 'b7800000-0000-0000-0000-000000000001')),
  'purge-idem-roof', 'purge-hash-roof');

select public.create_invoice_draft(
  'b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001', 'Shed',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Shed', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 20000, 'is_taxable', false)),
  array['b7400000-0000-0000-0000-000000000002']::uuid[],
  null, '2026-10-31'::date, '2026-10-01'::date, 'purge-idem-shed', 'purge-hash-shed');

select public.issue_invoice('b7200000-0000-0000-0000-000000000001',
  (select id from pat_bill where subject = 'Roof'), (select revision from pat_bill where subject = 'Roof'),
  'marked_sent', 'purge-idem-issue-roof', 'purge-hash-issue-roof');

set local role postgres;

-- 3. Open money refuses the delete -------------------------------------------------------------------------

select is(
  (select jsonb_agg(blocker ->> 'kind')
   from jsonb_array_elements(private.client_deletion_plan(
     'b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001') -> 'blockers') as blocker),
  '["invoice_unpaid"]'::jsonb, 'the roof bill still owing $870 is the one thing in the way');

select throws_ok(
  $$ select public.run_client_purge('b7200000-0000-0000-0000-000000000001',
    'b7300000-0000-0000-0000-000000000001', 'scheduled') $$,
  '23514', null, 'a customer who still owes money cannot be permanently deleted');

select throws_ok(
  $$ select public.run_client_purge('b7200000-0000-0000-0000-000000000001',
    'b7300000-0000-0000-0000-000000000001', 'whenever') $$,
  '23514', null, 'an unknown trigger kind is refused');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7100000-0000-0000-0000-000000000001', true);

select public.record_client_payment(
  'b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001',
  87000, 'bank_transfer', '2026-10-05'::date, 'Wire from Pat', null,
  jsonb_build_array(jsonb_build_object('invoice_id', (select id from pat_bill where subject = 'Roof'),
    'amount_minor', 87000)),
  'purge-idem-pay', 'purge-hash-pay');

set local role postgres;

-- 4. The plan the confirmation and the receipt share -----------------------------------------------------

create temporary table plan_before as
  select private.client_deletion_plan(
    'b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001') as plan;

select is((select plan -> 'blockers' from plan_before), '[]'::jsonb, 'once paid, nothing stands in the way');
select is((select (plan -> 'counts' ->> 'jobs')::int from plan_before), 2, 'both jobs are counted');
select is((select (plan -> 'counts' ->> 'quotes')::int from plan_before), 2, 'both quotes are counted');
select is((select (plan -> 'counts' ->> 'messages')::int from plan_before), 5,
  'two sent messages, one received and Pat''s two unlinked messages are counted');
select is((select (plan -> 'counts' ->> 'draft_invoices')::int from plan_before), 1, 'the draft bill is counted');
select is((select plan -> 'kept' from plan_before),
  '{"invoices": 1, "payments": 1, "deposits": 1, "opening_balances": 0}'::jsonb,
  'the issued bill, the payment and the deposit are named as kept');

-- What the money looks like before, to the byte.
create temporary table money_before as
  select
    (select md5(string_agg(x::text, '|' order by x.id)) from public.invoices as x
     where organization_id = 'b7200000-0000-0000-0000-000000000001' and issued_at is not null) as invoices,
    (select md5(string_agg(x::text, '|' order by x.id)) from public.invoice_lines as x
     where invoice_id = (select id from pat_bill where subject = 'Roof')) as lines,
    (select md5(string_agg(x::text, '|' order by x.id)) from public.client_payment_events as x
     where organization_id = 'b7200000-0000-0000-0000-000000000001') as payments,
    (select md5(string_agg(x::text, '|' order by x.id)) from public.invoice_payment_allocations as x
     where organization_id = 'b7200000-0000-0000-0000-000000000001') as allocations,
    (select md5(string_agg(x::text, '|' order by x.id)) from public.quote_deposit_events as x
     where organization_id = 'b7200000-0000-0000-0000-000000000001') as deposits;

-- 5. The delete ------------------------------------------------------------------------------------------------

-- The scheduled and Jafar deletes run with no signed-in member, so the owner on the Visit is someone else.
select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
create temporary table purge_result as
  select public.run_client_purge(
    'b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000001', 'platform_owner',
    null, 'owner@example.test', 'Customer emailed Uplift asking to be forgotten') as result;
set local role postgres;

select is((select (result ->> 'applied')::boolean from purge_result), true, 'the delete ran');
select is(private.client_purge_in_progress(), false, 'the history guards are back on once it returns');

create temporary view receipt as
  select * from public.client_deletion_receipts
  where id = (select (result ->> 'receipt_id')::uuid from purge_result);

select is((select status from receipt), 'in_progress', 'the receipt waits for the provider copies to go');
select is((select deleted_counts from receipt), (select plan -> 'counts' from plan_before),
  'the receipt counts what the confirmation counted');
select is((select trigger_kind || ':' || requested_by_owner_email from receipt),
  'platform_owner:owner@example.test', 'the receipt records who asked, without naming the customer');
select ok((select pending_storage_object_keys from receipt) @> array[
    'b7200000-0000-0000-0000-000000000001/files/pat-id.jpg',
    'b7200000-0000-0000-0000-000000000001/inbound/gate.jpg',
    'b7200000-0000-0000-0000-000000000001/outbound/roof-plan.pdf'],
  'Pat''s photo and both message attachments are queued for storage deletion');
select ok(not ((select pending_storage_object_keys from receipt) && array[
    'b7200000-0000-0000-0000-000000000001/files/price-list.pdf',
    'b7200000-0000-0000-0000-000000000001/files/warranty.pdf']),
  'library files that were only linked to Pat stay in storage');
select is((select component_results from receipt),
  '{"database": "succeeded", "storage_objects": "pending"}'::jsonb,
  'only stored file copies wait for cleanup; Twilio''s message log is left alone, as in HighLevel');
select ok(position('Pat' in (select r::text from receipt as r)) = 0
  and position('Forget' in (select r::text from receipt as r)) = 0,
  'the receipt holds no name and no address');

-- 6. The tombstone ---------------------------------------------------------------------------------------------

select is(
  (select row(display_name, first_name, last_name, company_name, billing_address_line1, billing_city)::text
   from public.clients where id = 'b7300000-0000-0000-0000-000000000001'),
  row('Deleted client', null::text, null::text, null::text, null::text, null::text)::text,
  'the customer row is an empty "Deleted client" shell');
select ok((select purged_at is not null and deleted_at is not null from public.clients
  where id = 'b7300000-0000-0000-0000-000000000001'), 'the shell is marked deleted and purged');

-- 7. Everything about the person is gone ----------------------------------------------------------------------

select is((select count(*)::int from public.client_contact_methods
  where client_id = 'b7300000-0000-0000-0000-000000000001'), 0, 'phones and emails are gone');
select is((select count(*)::int from public.client_contacts
  where client_id = 'b7300000-0000-0000-0000-000000000001'), 0, 'contact people are gone');
select is((select count(*)::int from public.jobs where client_id = 'b7300000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.job_visits where id = 'b7810000-0000-0000-0000-000000000001'),
  0, 'jobs and their visits are gone');
select is((select count(*)::int from public.requests where client_id = 'b7300000-0000-0000-0000-000000000001'),
  0, 'requests are gone');
select is((select array_agg(id) from public.quotes where client_id = 'b7300000-0000-0000-0000-000000000001'),
  array['b7500000-0000-0000-0000-000000000001'::uuid], 'only the deposit quote''s shell remains');
select is((select count(*)::int from public.communication_delivery_intents
  where client_id = 'b7300000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.communication_inbound_messages
     where client_id = 'b7300000-0000-0000-0000-000000000001'),
  0, 'sent and received messages are gone');
select is((select count(*)::int from public.communication_inbound_messages
  where id in ('b7840000-0000-0000-0000-000000000002', 'b7840000-0000-0000-0000-000000000003')),
  0, 'unlinked messages from Pat''s own email and phone are gone too');
select is((select array_agg(id order by id) from public.communication_inbound_messages
  where id in ('b7840000-0000-0000-0000-000000000004', 'b7840000-0000-0000-0000-000000000005')),
  array['b7840000-0000-0000-0000-000000000004', 'b7840000-0000-0000-0000-000000000005']::uuid[],
  'unlinked messages from a stranger and from another customer stay');
select is((select count(*)::int from public.communication_conversation_read_marks
  where client_id = 'b7300000-0000-0000-0000-000000000001'), 0, 'inbox read marks are gone');
select is((select count(*)::int from public.invoices
  where client_id = 'b7300000-0000-0000-0000-000000000001' and issued_at is null), 0, 'the draft bill is gone');
select is((select count(*)::int from public.communication_sms_consent_events
  where client_id = 'b7300000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.client_marketing_consent_events
     where client_id = 'b7300000-0000-0000-0000-000000000001')
  + (select count(*)::int from public.client_communication_preferences
     where client_id = 'b7300000-0000-0000-0000-000000000001'),
  0, 'consent history and preferences are gone');
select is((select count(*)::int from public.communication_email_suppressions
  where organization_id = 'b7200000-0000-0000-0000-000000000001'
    and recipient_email = 'pat.purgeable@example.test'), 0, 'the plain blocked-address row is gone');
select is((select count(*)::int from public.notes where id = 'b7900000-0000-0000-0000-000000000001'), 0,
  'a note only about Pat is gone');
select is(
  (select array_agg(entity_id) from public.note_links where note_id = 'b7900000-0000-0000-0000-000000000002'),
  array['b7300000-0000-0000-0000-000000000002'::uuid], 'a note shared with Bea stays, on Bea only');
select is(
  (select array_agg(entity_id) from public.tag_assignments where tag_id = 'b7950000-0000-0000-0000-000000000001'),
  array['b7300000-0000-0000-0000-000000000002'::uuid], 'Pat''s tag is gone and Bea''s stays');
select is((select count(*)::int from public.activity_events
  where entity_id = 'b7300000-0000-0000-0000-000000000001'), 0, 'Pat''s activity history is gone');
select is((select count(*)::int from public.team_notifications
  where subject_type = 'inbound_message' and subject_id = 'b7840000-0000-0000-0000-000000000001'), 0,
  'the bell notification about Pat''s text is gone');
-- The purge clears notifications about Pat's jobs before it deletes the Visit, so any left now were raised by
-- the delete itself.
select is((select count(*)::int from public.team_notifications
  where subject_type = 'job'
    and subject_id in ('b7800000-0000-0000-0000-000000000001', 'b7800000-0000-0000-0000-000000000002')),
  0, 'the crew gets no "Visit cancelled" alert naming a deleted person');
select is((select array_agg(id order by id) from public.files
  where organization_id = 'b7200000-0000-0000-0000-000000000001'),
  array['b7a00000-0000-0000-0000-000000000002'::uuid, 'b7a00000-0000-0000-0000-000000000003'::uuid],
  'Pat''s own file is gone and the two library files stay');
select is((select count(*)::int from public.file_links
  where organization_id = 'b7200000-0000-0000-0000-000000000001'), 0,
  'the library files are no longer linked to Pat or the deleted email');
select is(
  (select array_agg(id) from public.properties where client_id = 'b7300000-0000-0000-0000-000000000001'),
  array['b7400000-0000-0000-0000-000000000001'::uuid], 'only the property the deposit quote needs remains');
select is(
  (select row(address_line1, city, access_notes, postal_code)::text from public.properties
   where id = 'b7400000-0000-0000-0000-000000000001'),
  row('Deleted', 'Deleted', null::text, null::text)::text, 'and it is a "Deleted" shell with no address or notes');

-- 8. The deposit quote's shell ---------------------------------------------------------------------------------

select is((select row(title, request_id)::text from public.quotes where id = 'b7500000-0000-0000-0000-000000000001'),
  row('Deleted client', null::uuid)::text, 'the kept quote has no title or request');
select is(
  (select row(client_display_name, service_address_line1, service_city, client_message)::text
   from public.quote_versions where quote_id = 'b7500000-0000-0000-0000-000000000001'),
  row('Deleted client', null::text, null::text, null::text)::text,
  'its version keeps no name, address or message');

-- 9. The money did not move ------------------------------------------------------------------------------------

select is(
  (select row(
     (select md5(string_agg(x::text, '|' order by x.id)) from public.invoices as x
      where organization_id = 'b7200000-0000-0000-0000-000000000001' and issued_at is not null),
     (select md5(string_agg(x::text, '|' order by x.id)) from public.invoice_lines as x
      where invoice_id = (select id from pat_bill where subject = 'Roof')))::text),
  (select row(invoices, lines)::text from money_before),
  'the issued bill and its lines, name and address included, are exactly as issued');
select is(
  (select row(
     (select md5(string_agg(x::text, '|' order by x.id)) from public.client_payment_events as x
      where organization_id = 'b7200000-0000-0000-0000-000000000001'),
     (select md5(string_agg(x::text, '|' order by x.id)) from public.invoice_payment_allocations as x
      where organization_id = 'b7200000-0000-0000-0000-000000000001'),
     (select md5(string_agg(x::text, '|' order by x.id)) from public.quote_deposit_events as x
      where organization_id = 'b7200000-0000-0000-0000-000000000001'))::text),
  (select row(payments, allocations, deposits)::text from money_before),
  'payments, allocations and the deposit are byte-for-byte unchanged');
select is(
  (select row(count(*), sum(amount_minor), count(delivery_intent_id))::text
   from public.communication_sms_credit_reservations where organization_id = 'b7200000-0000-0000-0000-000000000001'),
  row(1::bigint, 4::numeric, 0::bigint)::text,
  'the text charge stays on the business''s bill, without a link to the deleted message');
select is(
  (select row(reservation.state, entry.amount_minor, account.settled_balance_minor, account.reserved_balance_minor)::text
   from public.communication_sms_credit_reservations as reservation
   join public.communication_sms_credit_ledger_entries as entry
     on entry.reservation_id = reservation.id and entry.entry_kind = 'charge'
   join public.communication_sms_credit_accounts as account on account.organization_id = reservation.organization_id
   where reservation.organization_id = 'b7200000-0000-0000-0000-000000000001'),
  row('settled'::text, -4::bigint, 6::bigint, 0::bigint)::text,
  'a sent text still waiting for its final price is charged at its send-time price, not given back');
select is(
  (select row(count(*), count(delivery_intent_id))::text
   from public.communication_email_usage_events where organization_id = 'b7200000-0000-0000-0000-000000000001'),
  row(1::bigint, 0::bigint)::text, 'the email allowance use stays counted');
select throws_ok(
  $$ delete from public.invoice_events where invoice_id = (select id from pat_bill where subject = 'Roof') $$,
  '23514', null, 'an issued bill''s history still cannot be deleted outside a purge');

-- 10. "Don't contact me" survives as fingerprints -------------------------------------------------------------

select is(
  (select array_agg(channel || ':' || kind order by channel, kind) from public.contact_opt_out_fingerprints
   where organization_id = 'b7200000-0000-0000-0000-000000000001'),
  array['email:do_not_disturb', 'email:email_hard_bounce', 'email:email_marketing_opt_out',
        'phone:do_not_disturb', 'phone:sms_opt_out'],
  'every opt-out is left behind as a fingerprint');
select ok(not exists (
    select 1 from public.contact_opt_out_fingerprints as f
    where f::text like '%5550199%' or f::text ilike '%purgeable%'),
  'no fingerprint holds the phone number or email in readable form');

-- 11. Running it again changes nothing -------------------------------------------------------------------------

set local role service_role;
select is(
  (select public.run_client_purge('b7200000-0000-0000-0000-000000000001',
    'b7300000-0000-0000-0000-000000000001', 'scheduled')),
  jsonb_build_object('applied', false, 'reason', 'already_purged',
    'receipt_id', (select (result ->> 'receipt_id')::uuid from purge_result)),
  'a second run finds the shell and hands back the first receipt');
set local role postgres;

-- 12. Coming back as a new customer ---------------------------------------------------------------------------

insert into public.clients (id, organization_id, display_name)
values ('b7300000-0000-0000-0000-000000000004', 'b7200000-0000-0000-0000-000000000001', 'Pat Again');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value)
values
  ('b7320000-0000-0000-0000-000000000004', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000004', 'phone', '512-555-0199'),
  ('b7320000-0000-0000-0000-000000000005', 'b7200000-0000-0000-0000-000000000001',
   'b7300000-0000-0000-0000-000000000004', 'email', 'PAT.PURGEABLE@example.test'),
  ('b7320000-0000-0000-0000-000000000006', 'b7200000-0000-0000-0000-000000000002',
   'b7300000-0000-0000-0000-000000000003', 'phone', '(512) 555-0199');

select is(public.communication_sms_consent_status(
    'b7200000-0000-0000-0000-000000000001', 'b7320000-0000-0000-0000-000000000004', 'service'),
  'opted_out', 'the same phone added again cannot be texted');
select is(
  (select array_agg(reason) from public.communication_email_suppressions
   where organization_id = 'b7200000-0000-0000-0000-000000000001'
     and recipient_email = 'pat.purgeable@example.test' and released_at is null),
  array['hard_bounce'], 'the same email added again is blocked again');
select is(
  (select state from public.client_marketing_consent_state
   where client_contact_method_id = 'b7320000-0000-0000-0000-000000000005'),
  'opted_out', 'and is unsubscribed from marketing');
select is(
  (select contact_policy from public.client_communication_preferences
   where client_id = 'b7300000-0000-0000-0000-000000000004'),
  'do_not_disturb', 'and keeps Do not disturb');
select is(public.communication_sms_consent_status(
    'b7200000-0000-0000-0000-000000000002', 'b7320000-0000-0000-0000-000000000006', 'service'),
  'unknown', 'another business with the same phone is not affected');

insert into public.communication_sms_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at,
  subjects, proof_method
) values ('b7200000-0000-0000-0000-000000000001', 'b7300000-0000-0000-0000-000000000004',
  'b7320000-0000-0000-0000-000000000004', 'opt_in', 'client_reply', 'purge-start', now(),
  array['service', 'work_updates', 'billing_updates'], 'customer_sms');

select is(public.communication_sms_consent_status(
    'b7200000-0000-0000-0000-000000000001', 'b7320000-0000-0000-0000-000000000004', 'service'),
  'opted_in', 'a later START from them wins');

-- 13. Bea and ordinary note deletes ------------------------------------------------------------------------

select is(
  (select display_name || ':' || (select count(*) from public.client_contact_methods as m
     where m.client_id = c.id) from public.clients as c where c.id = 'b7300000-0000-0000-0000-000000000002'),
  'Bystander Bea:1', 'Bea, in the same business, is untouched');

select lives_ok(
  $$ delete from public.note_links where note_id = 'b7900000-0000-0000-0000-000000000002' $$,
  'removing a note from a record works (the note-file tidy-up no longer fails)');

select * from finish();
rollback;
