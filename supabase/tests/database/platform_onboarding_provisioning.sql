-- Part 5f: real database coverage for the provisioning claim/resume, the setup-link atomic
-- consume, and provision_organization_from_application's guards -- none of these had a pgTAP
-- file before, even though Part 3's completion gate ("retries and simultaneous clicks cannot
-- create duplicate tenants/users or reuse a setup link") depends entirely on them.
begin;

create extension if not exists pgtap with schema extensions;

select plan(26);

-- Privileges: only the owner service role may call any of these.
select is(has_function_privilege('anon', 'public.claim_onboarding_application_provision(uuid, interval)', 'execute'), false, 'anonymous callers cannot claim a provisioning attempt');
select is(has_function_privilege('authenticated', 'public.claim_onboarding_application_provision(uuid, interval)', 'execute'), false, 'contractors cannot claim a provisioning attempt');
select is(has_function_privilege('service_role', 'public.claim_onboarding_application_provision(uuid, interval)', 'execute'), true, 'the owner service role can claim a provisioning attempt');
select is(has_function_privilege('anon', 'public.consume_onboarding_application_setup_link(text, text)', 'execute'), false, 'anonymous callers cannot consume a setup link');
select is(has_function_privilege('service_role', 'public.consume_onboarding_application_setup_link(text, text)', 'execute'), true, 'the owner service role can consume a setup link');

-- Fixture: one paid application against whichever package version is currently published.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_version_id, package_snapshot, possible_duplicate
)
select
  '80000000-0000-0000-0000-000000000010', 'new', 'Provisioning Test Co', 'Sam Provision',
  'sam@provisioning-test.example', '555-0500', 'Plumbing', 'Denver, USA', 'America/Denver',
  v.id,
  jsonb_build_object('display_name', v.display_name, 'price_usd_cents', v.price_usd_cents, 'currency', v.currency),
  false
from public.platform_package_versions v
where v.status = 'published'
limit 1;

select public.confirm_onboarding_application_payment(
  '80000000-0000-0000-0000-000000000010', 'owner@example.test', 54321, 'ref-provisioning-test', null
);

-- A real auth.users row for the administrator: organization_members.user_id has a hard FK to
-- auth.users, so the success-path provisioning call below (which inserts a real membership row)
-- needs a real account to point at, same as the app's own createUser() call would produce.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values (
  '80000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', 'sam-admin@provisioning-test.example', 'test', now(), now(), now()
);

-- claim_onboarding_application_provision: first claim, immediate re-claim, stale re-claim/resume, replay.
select is(
  (select claim_status from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010')),
  'claimed',
  'the first claim on a fresh application succeeds'
);
select is(
  (select claim_status from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010')),
  'in_progress',
  'an immediate second claim is rejected as in progress, not allowed to double-provision'
);
select is(
  (select claim_status from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010', interval '0 seconds')),
  'claimed',
  'a claim with a zero-second staleness window can reclaim an already-pending attempt'
);
select is(
  (select attempt_count from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010', interval '0 seconds')),
  3,
  'each successful reclaim increments attempt_count'
);

update public.platform_onboarding_application_provisions
set administrator_user_id = '80000000-0000-0000-0000-000000000099'
where application_id = '80000000-0000-0000-0000-000000000010';

select is(
  (select administrator_user_id from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010', interval '0 seconds')),
  '80000000-0000-0000-0000-000000000099',
  'a reclaim after a crash resumes with the previously created administrator account id instead of losing it'
);

-- A placeholder organization to satisfy the provisions table's own FK on organization_id
-- (the real provisioning success test further down creates its organization for real instead
-- of simulating it, so this placeholder uses a separate id and is never provisioned through).
insert into public.organizations (id, name, slug, lifecycle_status)
values ('80000000-0000-0000-0000-000000000097', 'Already Succeeded Placeholder', 'already-succeeded-placeholder', 'active');

update public.platform_onboarding_application_provisions
set status = 'succeeded', organization_id = '80000000-0000-0000-0000-000000000097'
where application_id = '80000000-0000-0000-0000-000000000010';

select is(
  (select claim_status from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010')),
  'already_succeeded',
  'claiming an already-succeeded application replays instead of reprovisioning'
);
select is(
  (select organization_id from public.claim_onboarding_application_provision('80000000-0000-0000-0000-000000000010')),
  '80000000-0000-0000-0000-000000000097',
  'the replay returns the existing organization id'
);

-- provision_organization_from_application guards.
select throws_ok(
  $$select public.provision_organization_from_application(
      '80000000-0000-0000-0000-000000000010', '80000000-0000-0000-0000-000000000020',
      'Provisioning Test Co', 'provisioning-test-co', '80000000-0000-0000-0000-000000000099', 'owner', null
    )$$,
  '23514',
  null,
  'provisioning without an acting owner email is refused'
);

insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_version_id, package_snapshot, possible_duplicate
)
select
  '80000000-0000-0000-0000-000000000011', 'new', 'Unpaid Provisioning Co', 'Jamie Unpaid',
  'jamie@provisioning-test.example', '555-0501', 'Electrical', 'Denver, USA', 'America/Denver',
  v.id,
  jsonb_build_object('display_name', v.display_name, 'price_usd_cents', v.price_usd_cents, 'currency', v.currency),
  false
from public.platform_package_versions v
where v.status = 'published'
limit 1;

select throws_ok(
  $$select public.provision_organization_from_application(
      '80000000-0000-0000-0000-000000000011', '80000000-0000-0000-0000-000000000021',
      'Unpaid Provisioning Co', 'unpaid-provisioning-co', '80000000-0000-0000-0000-000000000098', 'owner', 'owner@example.test'
    )$$,
  '23514',
  null,
  'provisioning an application still at stage new is refused'
);

select throws_ok(
  $$select public.provision_organization_from_application(
      '80000000-0000-0000-0000-000000000999', '80000000-0000-0000-0000-000000000022',
      'Missing App Co', 'missing-app-co', '80000000-0000-0000-0000-000000000099', 'owner', 'owner@example.test'
    )$$,
  '23503',
  null,
  'provisioning a missing application is refused'
);

-- Success path: this is the "login readiness" proof -- a real organization plus a real
-- organization_members row must exist afterwards, since that membership is what a freshly
-- created administrator's login depends on resolving.
select lives_ok(
  $$select public.provision_organization_from_application(
      '80000000-0000-0000-0000-000000000010', '80000000-0000-0000-0000-000000000098',
      'Provisioning Test Co', 'provisioning-test-co', '80000000-0000-0000-0000-000000000099', 'owner', 'owner@example.test'
    )$$,
  'provisioning a paid, ready application succeeds'
);
select is(
  (select stage from public.platform_onboarding_applications where id = '80000000-0000-0000-0000-000000000010'),
  'account_created',
  'a successful provision moves the application to account_created'
);
select is(
  (select count(*)::int from public.organizations where id = '80000000-0000-0000-0000-000000000098'),
  1,
  'the organization was created'
);
select is(
  (select count(*)::int from public.organization_members
   where organization_id = '80000000-0000-0000-0000-000000000098'
     and user_id = '80000000-0000-0000-0000-000000000099'
     and role = 'owner'),
  1,
  'the administrator was added as an owner member -- this is what makes their login resolve to the organization'
);
select is(
  (select count(*)::int from public.organization_settings where organization_id = '80000000-0000-0000-0000-000000000098'),
  1,
  'organization settings were created for the new organization'
);
select is(
  (select paid_through_date from public.organization_commercial_state where organization_id = '80000000-0000-0000-0000-000000000098'),
  (
    select (confirmed_at::date + interval '1 month')::date
    from public.platform_onboarding_application_payment_confirmations
    where application_id = '80000000-0000-0000-0000-000000000010'
    order by confirmed_at desc
    limit 1
  ),
  'provisioning writes the initial payment through the commercial-command seam, not the legacy billing table'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '80000000-0000-0000-0000-000000000098' and event_kind = 'initial_payment_confirmed'),
  1,
  'provisioning recorded exactly one initial-payment commercial event'
);

-- consume_onboarding_application_setup_link: single-use, recipient-bound, expiry-bound.
insert into public.platform_onboarding_application_setup_links (
  application_id, administrator_user_id, intended_email, token_hash, expires_at
) values (
  '80000000-0000-0000-0000-000000000010', '80000000-0000-0000-0000-000000000099',
  'sam@provisioning-test.example', 'test-token-hash-live', now() + interval '1 day'
);

select is(
  (select consumed from public.consume_onboarding_application_setup_link('test-token-hash-live', 'wrong@provisioning-test.example')),
  false,
  'consuming with the wrong recipient email is refused'
);
select is(
  (select consumed from public.consume_onboarding_application_setup_link('test-token-hash-live', 'sam@provisioning-test.example')),
  true,
  'consuming a valid, matching setup link succeeds'
);
select is(
  (select consumed from public.consume_onboarding_application_setup_link('test-token-hash-live', 'sam@provisioning-test.example')),
  false,
  'the same setup link cannot be consumed a second time'
);

insert into public.platform_onboarding_application_setup_links (
  application_id, administrator_user_id, intended_email, token_hash, expires_at
) values (
  '80000000-0000-0000-0000-000000000011', '80000000-0000-0000-0000-000000000098',
  'jamie@provisioning-test.example', 'test-token-hash-expired', now() - interval '1 hour'
);

select is(
  (select consumed from public.consume_onboarding_application_setup_link('test-token-hash-expired', 'jamie@provisioning-test.example')),
  false,
  'an expired setup link cannot be consumed'
);

select * from finish();
rollback;
