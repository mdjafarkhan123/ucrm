-- Part 9: recoverable closure and strict purge -- the purge RPC.
begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

-- Privileges -----------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.apply_organization_purge(uuid, text, text)', 'execute'),
  false, 'anonymous callers cannot purge an organization'
);
select is(
  has_function_privilege('authenticated', 'public.apply_organization_purge(uuid, text, text)', 'execute'),
  false, 'contractors cannot purge an organization'
);
select is(
  has_function_privilege('service_role', 'public.apply_organization_purge(uuid, text, text)', 'execute'),
  true, 'the owner service role can purge an organization'
);

-- Fixtures ---------------------------------------------------------------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('90000000-1111-0000-0000-000000000910', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '9-purge-p1-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-000000000910', '9 Purge P1 Test', '9-purge-p1-test', 'active'),
  ('90000000-0000-0000-0000-000000000911', '9 Purge P2 Test', '9-purge-p2-test', 'active'),
  ('90000000-0000-0000-0000-000000000912', '9 Purge P3 Never Closed Test', '9-purge-p3-test', 'active'),
  ('90000000-0000-0000-0000-000000000913', '9 Purge P4 Provider Test', '9-purge-p4-test', 'active');

-- P4 carries live Brevo resources: one sending domain and one sender, each with an opaque provider
-- id. It deliberately has no members, so its purge isolates the provider-cleanup leg.
insert into public.communication_email_domains (id, organization_id, purpose, domain_name, provider_domain_id)
values (
  '90000000-3333-0000-0000-000000000913', '90000000-0000-0000-0000-000000000913',
  'sending', 'mail.p4example.test', 'brevo-dom-p4'
);

insert into public.communication_email_senders (
  organization_id, domain_id, email_address, display_name, provider_sender_id
)
values (
  '90000000-0000-0000-0000-000000000913', '90000000-3333-0000-0000-000000000913',
  'p4-sender@mail.p4example.test', 'P4 Sender', 7788
);

insert into public.organization_members (organization_id, user_id, role)
values ('90000000-0000-0000-0000-000000000910', '90000000-1111-0000-0000-000000000910', 'owner');

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select '90000000-0000-0000-0000-000000000910', id, now() - interval '2 minutes', 'provisioning', '9 purge test baseline assignment'
from public.platform_package_versions where status = 'published' limit 1;

insert into public.organization_free_access_events (organization_id, package_version_id, action, access_until_date, starts_at, reason)
select '90000000-0000-0000-0000-000000000910', id, 'grant', current_date + 30, current_date, '9 purge test free access grant'
from public.platform_package_versions where status = 'published' limit 1;

insert into public.organization_payment_confirmations (organization_id, payment_kind, amount_usd_cents, private_reference, confirmed_at, paid_through_date)
values ('90000000-0000-0000-0000-000000000910', 'initial', 9900, '9-purge-test-ref', now(), current_date + 30);

select public.apply_organization_commercial_command(
  '90000000-0000-0000-0000-000000000910', 'initial_payment_confirmed', '9-purge-p1-commercial-1',
  'Initial payment confirmed for purge test fixture.', 'set', current_date + 30,
  'owner@example.test', now(), null, null, null, null, null, null, null, false, false,
  'payment_recorded', '{}'::jsonb
);

insert into public.platform_onboarding_applications (
  id, business_name, main_contact_name, main_contact_email, main_contact_phone, trade, city_country,
  time_zone, package_version_id, package_snapshot
)
select
  '90000000-2222-0000-0000-000000000910', '9 Purge P1 Test', 'Test Contact', '9-purge-p1-contact@example.test',
  '+10000000000', 'plumbing', 'Testville, US', 'America/New_York', id, '{}'::jsonb
from public.platform_package_versions where status = 'published' limit 1;

insert into public.platform_onboarding_application_provisions (application_id, status, organization_id, administrator_user_id)
values (
  '90000000-2222-0000-0000-000000000910', 'succeeded', '90000000-0000-0000-0000-000000000910',
  '90000000-1111-0000-0000-000000000910'
);

select public.apply_organization_closure_start(
  '90000000-0000-0000-0000-000000000910', '9-purge-p1-close-1',
  'Closing before purge test.', 'owner@example.test'
);
select public.apply_organization_closure_start(
  '90000000-0000-0000-0000-000000000911', '9-purge-p2-close-1',
  'Closing before purge test.', 'owner@example.test'
);
select public.apply_organization_closure_start(
  '90000000-0000-0000-0000-000000000913', '9-purge-p4-close-1',
  'Closing before purge test.', 'owner@example.test'
);

-- Rejections -------------------------------------------------------------------

select throws_ok(
  $$select public.apply_organization_purge('90000000-0000-0000-0000-000000000910', 'not_a_real_trigger_kind', null)$$,
  '23514', null, 'purge is rejected for an invalid trigger kind'
);
select throws_ok(
  $$select public.apply_organization_purge('90000000-0000-0000-0000-000000000912', 'early_manual', null)$$,
  '23514', null, 'an early manual purge is rejected without an acting owner email'
);
select throws_ok(
  $$select public.apply_organization_purge('90000000-0000-0000-0000-000000000912', 'scheduled', null)$$,
  '23514', null, 'purge is rejected for an organization with no open closure window'
);

-- Immutability still blocks direct mutation outside a purge ---------------------

select throws_ok(
  $$update public.organization_commercial_events set summary = 'tampered' where organization_id = '90000000-0000-0000-0000-000000000910'$$,
  '23514', null, 'commercial events cannot be updated directly, even before a purge'
);
select throws_ok(
  $$delete from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-000000000910'$$,
  '23514', null, 'commercial events cannot be deleted directly outside a purge'
);
select throws_ok(
  $$update public.organization_safe_events set safe_kind = 'account_suspended' where organization_id = '90000000-0000-0000-0000-000000000910'$$,
  '23514', null, 'safe events cannot be updated directly, even before a purge'
);

-- Purging P1: full cascade across every organization-scoped table ---------------
-- The receipt table is deliberately not scoped to an organization (no identifying FK), and this
-- environment may already carry receipts from unrelated real runs, so every receipt assertion below
-- keys off the operation id this specific call returns rather than table-wide counts or bare LIMIT 1.

select set_config(
  'test.p1_purge_result',
  public.apply_organization_purge('90000000-0000-0000-0000-000000000910', 'scheduled', null)::text,
  true
);
select is(
  (current_setting('test.p1_purge_result', true)::jsonb ->> 'applied'),
  'true', 'purge applies for an organization past its closure deadline window'
);
select ok(
  coalesce(current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id', '') <> '',
  'purging P1 returns a real operation id'
);
select is(
  (select count(*)::int from public.organizations where id = '90000000-0000-0000-0000-000000000910'),
  0, 'the organization row itself is gone after purge'
);
select is(
  (select count(*)::int from public.organization_closure_records where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'the closure record is gone after purge'
);
select is(
  (select count(*)::int from public.organization_package_assignments where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'package assignment history is gone after purge'
);
select is(
  (select count(*)::int from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'free access history is gone after purge'
);
select is(
  (select count(*)::int from public.organization_payment_confirmations where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'payment confirmations are gone after purge'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'commercial events are gone after purge'
);
select is(
  (select count(*)::int from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'contractor-safe events are gone after purge'
);
select is(
  (select count(*)::int from public.organization_members where organization_id = '90000000-0000-0000-0000-000000000910'),
  0, 'memberships are gone after purge'
);
select is(
  (select count(*)::int from public.platform_onboarding_application_provisions where application_id = '90000000-2222-0000-0000-000000000910'),
  1, 'the onboarding provisioning row survives the purge'
);
select is(
  (select organization_id from public.platform_onboarding_application_provisions where application_id = '90000000-2222-0000-0000-000000000910'),
  null, 'the onboarding provisioning row is unlinked, not deleted'
);
select is(
  (select component_results ->> 'auth_users' from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'pending', 'the receipt records Auth-user deletion as pending for the caller to finish'
);
select ok(
  (select
    component_results ->> 'organization_data' = 'succeeded'
    and component_results ->> 'package_assignments' = 'succeeded'
    and component_results ->> 'free_access_history' = 'succeeded'
    and component_results ->> 'onboarding_provision_unlinked' = 'succeeded'
    and component_results ->> 'provider_resources' = 'not_applicable'
   from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'the receipt honestly records every component outcome; P1 has no Brevo resources so provider_resources is not_applicable'
);
-- With the Auth leg still pending, the whole receipt is not complete yet: the unified state model
-- keeps it in_progress with no completion timestamp until every external leg finishes.
select is(
  (select status from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'in_progress', 'a receipt with a pending Auth leg stays in_progress, not completed'
);
select ok(
  (select completed_at is null from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'an in_progress receipt carries no completion timestamp'
);
select ok(
  (select component_results ?& array['organization_data', 'package_assignments', 'free_access_history', 'onboarding_provision_unlinked', 'provider_resources', 'auth_users']
   from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'the receipt contains every expected component key'
);
select is(
  (select count(*)::int
   from public.organization_deletion_receipts, jsonb_object_keys(component_results)
   where operation_id = (current_setting('test.p1_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  6, 'the receipt has exactly six component keys, nothing organization-identifying or extra'
);

-- Purge is safely re-runnable once the organization is already gone -------------

select is(
  (public.apply_organization_purge('90000000-0000-0000-0000-000000000910', 'scheduled', null) ->> 'applied'),
  'false', 'retrying purge after success is a harmless no-op'
);
select is(
  (public.apply_organization_purge('90000000-0000-0000-0000-000000000910', 'scheduled', null) ->> 'reason'),
  'already_purged', 'the no-op retry reports already_purged rather than raising'
);

-- Early manual purge on a minimal organization with no onboarding provision -----

select set_config(
  'test.p2_purge_result',
  public.apply_organization_purge('90000000-0000-0000-0000-000000000911', 'early_manual', 'owner@example.test')::text,
  true
);
select is(
  (current_setting('test.p2_purge_result', true)::jsonb ->> 'applied'),
  'true', 'an early manual purge applies with an acting owner email'
);
select is(
  (select count(*)::int from public.organizations where id = '90000000-0000-0000-0000-000000000911'),
  0, 'the early-manual-purged organization is gone'
);
select is(
  (select component_results ->> 'onboarding_provision_unlinked' from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p2_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'not_applicable', 'an organization with no onboarding provision records that component as not_applicable, not a fake success'
);

-- Purging P4: provider (Brevo) cleanup is parked as a retryable leg -------------
-- P4 has no members, so the Auth leg is not applicable and the receipt's only outstanding leg is the
-- provider cleanup: exactly the state that must stay retryable, never reported complete.

select set_config(
  'test.p4_purge_result',
  public.apply_organization_purge('90000000-0000-0000-0000-000000000913', 'scheduled', null)::text,
  true
);
select is(
  (current_setting('test.p4_purge_result', true)::jsonb ->> 'applied'),
  'true', 'purge applies for the provider-bearing organization'
);
select is(
  (select component_results ->> 'provider_resources' from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'pending', 'the receipt records provider cleanup as pending, not a premature success'
);
select is(
  (select component_results ->> 'auth_users' from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'not_applicable', 'an organization with no members records the Auth leg as not_applicable'
);
select is(
  (select status from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'in_progress', 'a receipt awaiting provider cleanup stays in_progress rather than complete'
);
select ok(
  (select completed_at is null from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'the provider-pending receipt carries no completion timestamp'
);
select is(
  (select jsonb_array_length(pending_provider_resources) from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  2, 'the retry anchor holds both provider resources read out before the cascade'
);
select ok(
  (select
     pending_provider_resources @> '[{"kind":"domain","provider_id":"brevo-dom-p4"}]'::jsonb
     and pending_provider_resources @> '[{"kind":"sender","provider_id":"7788"}]'::jsonb
   from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'the anchor carries the opaque domain and sender provider ids Brevo needs to delete them'
);
select ok(
  (select bool_and(
     element ?& array['kind', 'provider_id']
     and (select count(*)::int from jsonb_object_keys(element)) = 2
   )
   from public.organization_deletion_receipts,
        jsonb_array_elements(pending_provider_resources) as element
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'every anchor element carries only the opaque kind and provider id, nothing more'
);
select ok(
  (select
     position('mail.p4example.test' in pending_provider_resources::text) = 0
     and position('p4-sender' in pending_provider_resources::text) = 0
   from public.organization_deletion_receipts
   where operation_id = (current_setting('test.p4_purge_result', true)::jsonb ->> 'operation_id')::uuid),
  'the receipt holds no domain name or sender address -- only opaque provider identifiers'
);

select * from finish();
rollback;
