-- Marketing M2: the customer-group rule compiler and the exact recipient preview.
--
-- Verified against the remote dev project by running this whole file as one transaction that is rolled
-- back at the end, the same convention client_spendable_credit_reader.sql documents. Do not run it
-- through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- Nobody but the service role reaches the preview. -----------------------------------------------------
select is(has_function_privilege('anon', 'public.marketing_preview_counts(uuid, jsonb)', 'execute'),
  false, 'signed-out callers cannot count marketing recipients');
select is(has_function_privilege('authenticated', 'public.marketing_preview_counts(uuid, jsonb)', 'execute'),
  false, 'members cannot count marketing recipients directly; server code does it after the permission check');
select is(has_function_privilege('authenticated',
  'public.marketing_preview_recipients(uuid, jsonb, text, text, uuid, integer)', 'execute'),
  false, 'members cannot list marketing recipients directly');
select is((select relrowsecurity from pg_class where oid = 'public.marketing_customer_groups'::regclass),
  true, 'saved customer groups have row level security enabled');

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values ('fa100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'group-owner-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('fa200000-0000-0000-0000-000000000001', 'Group Org A', 'group-org-a', 'active'),
  ('fa200000-0000-0000-0000-000000000002', 'Group Org B', 'group-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('fa200000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000001', 'owner');

-- Org A customers, one per outcome the preview has to explain. -----------------------------------------
insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status, lead_source, archived_at)
values
  ('fa300000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'A Ready Customer', 'person', 'customer', 'referral', null),
  ('fa300000-0000-0000-0000-000000000002', 'fa200000-0000-0000-0000-000000000001', 'B No Consent', 'person', 'customer', 'referral', null),
  ('fa300000-0000-0000-0000-000000000003', 'fa200000-0000-0000-0000-000000000001', 'C Unsubscribed', 'person', 'customer', 'website', null),
  ('fa300000-0000-0000-0000-000000000004', 'fa200000-0000-0000-0000-000000000001', 'D No Email', 'person', 'customer', 'website', null),
  ('fa300000-0000-0000-0000-000000000005', 'fa200000-0000-0000-0000-000000000001', 'E Archived', 'person', 'customer', 'website', now()),
  ('fa300000-0000-0000-0000-000000000006', 'fa200000-0000-0000-0000-000000000001', 'F Do Not Disturb', 'person', 'customer', 'website', null),
  ('fa300000-0000-0000-0000-000000000007', 'fa200000-0000-0000-0000-000000000001', 'G Bounced', 'person', 'lead', 'website', null);

-- Org B keeps its own ready customer, so tenant isolation is provable.
insert into public.clients (id, organization_id, display_name, client_type, lifecycle_status)
values ('fa300000-0000-0000-0000-0000000000b1', 'fa200000-0000-0000-0000-000000000002', 'Other Org Customer', 'person', 'customer');

insert into public.client_contact_methods (id, organization_id, client_id, kind, value, is_primary)
values
  ('fa400000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000001', 'email', 'ready@example.test', true),
  ('fa400000-0000-0000-0000-000000000002', 'fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000002', 'email', 'noconsent@example.test', true),
  ('fa400000-0000-0000-0000-000000000003', 'fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000003', 'email', 'unsub@example.test', true),
  ('fa400000-0000-0000-0000-000000000005', 'fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000005', 'email', 'archived@example.test', true),
  ('fa400000-0000-0000-0000-000000000006', 'fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000006', 'email', 'dnd@example.test', true),
  ('fa400000-0000-0000-0000-000000000007', 'fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000007', 'email', 'bounced@example.test', true),
  ('fa400000-0000-0000-0000-0000000000b1', 'fa200000-0000-0000-0000-000000000002', 'fa300000-0000-0000-0000-0000000000b1', 'email', 'otherorg@example.test', true);

-- Consent: opted in for the ready, archived, do-not-disturb and bounced customers, opted out for C.
insert into public.client_marketing_consent_events (
  organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key, occurred_at
)
values
  ('fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'opt_in', 'staff', 'test-ready', now()),
  ('fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000005', 'fa400000-0000-0000-0000-000000000005', 'opt_in', 'staff', 'test-archived', now()),
  ('fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000006', 'fa400000-0000-0000-0000-000000000006', 'opt_in', 'staff', 'test-dnd', now()),
  ('fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000007', 'fa400000-0000-0000-0000-000000000007', 'opt_in', 'staff', 'test-bounced', now()),
  ('fa200000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000003', 'fa400000-0000-0000-0000-000000000003', 'opt_out', 'unsubscribe', 'test-unsub', now()),
  ('fa200000-0000-0000-0000-000000000002', 'fa300000-0000-0000-0000-0000000000b1', 'fa400000-0000-0000-0000-0000000000b1', 'opt_in', 'staff', 'test-other-org', now());

-- Creating a Customer already creates its communication preferences row, so this changes that row.
update public.client_communication_preferences
set contact_policy = 'do_not_disturb'
where organization_id = 'fa200000-0000-0000-0000-000000000001'
  and client_id = 'fa300000-0000-0000-0000-000000000006';

insert into public.communication_email_suppressions (organization_id, recipient_email, reason, source)
values ('fa200000-0000-0000-0000-000000000001', 'bounced@example.test', 'hard_bounce', 'manual');

-- Every exclusion reason is reported, and only the ready customer is reachable. -------------------------
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))->>'matches',
  '7', 'every live customer in the organization matches an empty rule set');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))->>'eligible',
  '1', 'only the consented, unsuppressed, contactable customer is reachable');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))
    #>>'{excluded_by_reason,no_consent}',
  '1', 'a customer with no recorded consent is excluded for that reason');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))
    #>>'{excluded_by_reason,unsubscribed}',
  '1', 'an unsubscribed customer is excluded as unsubscribed');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))
    #>>'{excluded_by_reason,missing_email}',
  '1', 'a customer with no email address is excluded as missing an email');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))
    #>>'{excluded_by_reason,inactive_customer}',
  '1', 'an archived customer is excluded even though consent is on record');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))
    #>>'{excluded_by_reason,do_not_disturb}',
  '1', 'Do not disturb beats a recorded opt-in');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001', '{"version":"1"}'::jsonb))
    #>>'{excluded_by_reason,hard_bounce}',
  '1', 'a hard-bounced address is excluded');

-- Filters and tenant isolation. ------------------------------------------------------------------------
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001',
    '{"version":"1","lifecycle":["lead"]}'::jsonb))->>'matches',
  '1', 'the lead/customer state filter narrows the match');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001',
    '{"version":"1","lead_sources":["referral"]}'::jsonb))->>'matches',
  '2', 'the original lead source filter narrows the match');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001',
    '{"version":"1","lifecycle":["lead"],"include_client_ids":["fa300000-0000-0000-0000-000000000001"],"exclude_client_ids":["fa300000-0000-0000-0000-000000000007"]}'::jsonb))->>'matches',
  '1', 'an explicitly added customer joins and an explicitly removed customer leaves');
select is(
  (public.marketing_preview_counts('fa200000-0000-0000-0000-000000000002', '{"version":"1"}'::jsonb))->>'eligible',
  '1', 'another organization sees only its own reachable customer');

-- A rule the whitelist does not know never reaches SQL. -------------------------------------------------
select throws_ok(
  $$select public.marketing_preview_counts('fa200000-0000-0000-0000-000000000001',
      '{"version":"1","clients; drop table public.clients":"x"}'::jsonb)$$,
  '22023',
  null,
  'an unknown filter key is refused instead of being compiled');

select * from finish();
rollback;
