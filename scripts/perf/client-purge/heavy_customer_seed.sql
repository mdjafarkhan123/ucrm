-- Heavy customer for the purge performance check. Included by perf_run.sql inside a rolled-back transaction.
set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('c0f10000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'perf-owner@example.test', 'test', now(), now(), now());
insert into public.organizations (id, name, slug, lifecycle_status)
values ('c0f20000-0000-0000-0000-000000000001', 'Perf Purge Co', 'perf-purge-co', 'active');
insert into public.organization_members (organization_id, user_id, role)
values ('c0f20000-0000-0000-0000-000000000001', 'c0f10000-0000-0000-0000-000000000001', 'owner');
insert into public.clients (id, organization_id, display_name, first_name, last_name)
values ('c0f30000-0000-0000-0000-000000000001', 'c0f20000-0000-0000-0000-000000000001', 'Heavy Harriet', 'Harriet', 'Heavy'),
       ('c0f30000-0000-0000-0000-000000000002', 'c0f20000-0000-0000-0000-000000000001', 'Other Otto', 'Otto', 'Other');
insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values ('c0f32000-0000-0000-0000-000000000001', 'c0f20000-0000-0000-0000-000000000001',
        'c0f30000-0000-0000-0000-000000000001', 'phone', '+1 (512) 555-0177', true),
       ('c0f32000-0000-0000-0000-000000000002', 'c0f20000-0000-0000-0000-000000000001',
        'c0f30000-0000-0000-0000-000000000001', 'email', 'harriet@example.test', true);
insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('c0f40000-0000-0000-0000-000000000001', 'c0f20000-0000-0000-0000-000000000001',
        'c0f30000-0000-0000-0000-000000000001', '1 Heavy Way', 'Testville', 'TX', '78741');

-- 5,000 texts with 2 events and 1 provider callback each; 1,000 texts in.
insert into public.communication_delivery_intents (
  id, organization_id, client_id, client_contact_method_id, channel, logical_send_key, recipient_phone, status,
  accepted_at, provider_message_id)
select ('c0f50000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'c0f20000-0000-0000-0000-000000000001',
  'c0f30000-0000-0000-0000-000000000001', 'c0f32000-0000-0000-0000-000000000001', 'sms', 'perf-sms-' || g,
  '+15125550177', 'submitted', now(), 'SMperf' || lpad(g::text, 26, '0')
from generate_series(1, 5000) as g;

insert into public.communication_message_events (organization_id, delivery_intent_id, event_kind)
select 'c0f20000-0000-0000-0000-000000000001', ('c0f50000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, k
from generate_series(1, 5000) as g cross join (values ('queued'), ('sent')) as e(k);

insert into public.communication_provider_callback_events (
  organization_id, delivery_intent_id, channel, provider, provider_event_key, event_kind, normalized_kind, payload)
select 'c0f20000-0000-0000-0000-000000000001', ('c0f50000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  'sms', 'twilio', 'perf-cb-' || g, 'delivered', 'sms_delivered', '{"To": "+15125550177"}'::jsonb
from generate_series(1, 5000) as g;

insert into public.communication_inbound_messages (
  organization_id, client_id, client_contact_method_id, provider, provider_message_id, channel, sender_phone,
  subject, text_content)
select 'c0f20000-0000-0000-0000-000000000001', 'c0f30000-0000-0000-0000-000000000001',
  'c0f32000-0000-0000-0000-000000000001', 'twilio', 'SMperfin' || lpad(g::text, 24, '0'), 'sms', '+15125550177',
  '', 'Reply number ' || g
from generate_series(1, 1000) as g;

-- 300 jobs with 10 visits each, every visit assigned.
insert into public.jobs (id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code)
select ('c0f60000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'c0f20000-0000-0000-0000-000000000001',
  'c0f30000-0000-0000-0000-000000000001', 'c0f40000-0000-0000-0000-000000000001', 880000 + g, 'Job ' || g,
  'one_off', 'job_total', 'USD'
from generate_series(1, 300) as g;

insert into public.job_visits (id, organization_id, job_id, position, visit_date)
select ('c0f70000-0000-0000-' || lpad(j::text, 4, '0') || '-' || lpad(v::text, 12, '0'))::uuid,
  'c0f20000-0000-0000-0000-000000000001', ('c0f60000-0000-0000-0000-' || lpad(j::text, 12, '0'))::uuid, v,
  current_date - 400 + j
from generate_series(1, 300) as j cross join generate_series(0, 9) as v;

insert into public.job_visit_assignments (organization_id, visit_id, user_id, job_id)
select 'c0f20000-0000-0000-0000-000000000001', visit.id, 'c0f10000-0000-0000-0000-000000000001', visit.job_id
from public.job_visits as visit where visit.organization_id = 'c0f20000-0000-0000-0000-000000000001';

-- 1,000 files, 500 notes and 2,000 activity rows on the customer.
insert into public.files (
  id, organization_id, display_name, mime_type, size_bytes, object_key, origin_type, origin_id, origin_role,
  processing_state, scanned_at, checksum_sha256)
select ('c0f80000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'c0f20000-0000-0000-0000-000000000001',
  'photo-' || g || '.jpg', 'image/jpeg', 1000, 'c0f20000-0000-0000-0000-000000000001/files/photo-' || g || '.jpg',
  'client', 'c0f30000-0000-0000-0000-000000000001', 'attachment', 'available', now(), repeat('d', 64)
from generate_series(1, 1000) as g;
insert into public.file_links (organization_id, file_id, entity_type, entity_id, role)
select 'c0f20000-0000-0000-0000-000000000001', ('c0f80000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  'client', 'c0f30000-0000-0000-0000-000000000001', 'attachment'
from generate_series(1, 1000) as g;

insert into public.notes (id, organization_id, body)
select ('c0f90000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'c0f20000-0000-0000-0000-000000000001', 'Note ' || g
from generate_series(1, 500) as g;
insert into public.note_links (organization_id, note_id, entity_type, entity_id)
select 'c0f20000-0000-0000-0000-000000000001', ('c0f90000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
  'client', 'c0f30000-0000-0000-0000-000000000001'
from generate_series(1, 500) as g;

insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary)
select 'c0f20000-0000-0000-0000-000000000001', 'client', 'c0f30000-0000-0000-0000-000000000001', 'call', 'Call ' || g
from generate_series(1, 2000) as g;
