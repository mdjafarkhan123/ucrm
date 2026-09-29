-- Part 5f: real database coverage for the provisioning claim/resume and the setup-link atomic
-- consume -- Part 3's completion gate ("retries and simultaneous clicks cannot create duplicate
-- tenants/users or reuse a setup link") depends on them. Creating the organization itself is
-- rebuilt on package editions in package-builder P10, which brings its own coverage.
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- Privileges: only the owner service role may call any of these.
select is(has_function_privilege('anon', 'public.claim_onboarding_application_provision(uuid, interval)', 'execute'), false, 'anonymous callers cannot claim a provisioning attempt');
select is(has_function_privilege('authenticated', 'public.claim_onboarding_application_provision(uuid, interval)', 'execute'), false, 'contractors cannot claim a provisioning attempt');
select is(has_function_privilege('service_role', 'public.claim_onboarding_application_provision(uuid, interval)', 'execute'), true, 'the owner service role can claim a provisioning attempt');
select is(has_function_privilege('anon', 'public.consume_onboarding_application_setup_link(text, text)', 'execute'), false, 'anonymous callers cannot consume a setup link');
select is(has_function_privilege('service_role', 'public.consume_onboarding_application_setup_link(text, text)', 'execute'), true, 'the owner service role can consume a setup link');

-- Fixture: one paid application on the private test package's published edition.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_edition_id, billing_interval, package_snapshot, possible_duplicate
)
select
  '80000000-0000-0000-0000-000000000010', 'new', 'Provisioning Test Co', 'Sam Provision',
  'sam@provisioning-test.example', '555-0500', 'Plumbing', 'Denver, USA', 'America/Denver',
  e.id, 'month',
  jsonb_build_object('display_name', e.name, 'price_usd_cents', e.monthly_price_usd_cents, 'currency', 'USD'),
  false
from public.package_editions e
join public.packages p on p.id = e.package_id
where p.slug = 'test-package' and e.status = 'published';

-- Payment confirmation is rebuilt in package-builder P10; until then the confirmed state is placed
-- directly, the way the old confirm command left it.
insert into public.platform_onboarding_application_payment_confirmations (
  application_id, actor_owner_email, amount_usd_cents, private_reference
) values (
  '80000000-0000-0000-0000-000000000010', 'owner@example.test', 54321, 'ref-provisioning-test'
);
update public.platform_onboarding_applications set stage = 'payment_confirmed'
where id = '80000000-0000-0000-0000-000000000010';

-- A real auth.users row for the administrator the provisioning attempt remembers.
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

-- A placeholder organization to satisfy the provisions table's own FK on organization_id.
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

-- A second application, still unpaid, for the expired setup link below.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_edition_id, billing_interval, package_snapshot, possible_duplicate
)
select
  '80000000-0000-0000-0000-000000000011', 'new', 'Unpaid Provisioning Co', 'Jamie Unpaid',
  'jamie@provisioning-test.example', '555-0501', 'Electrical', 'Denver, USA', 'America/Denver',
  e.id, 'month',
  jsonb_build_object('display_name', e.name, 'price_usd_cents', e.monthly_price_usd_cents, 'currency', 'USD'),
  false
from public.package_editions e
join public.packages p on p.id = e.package_id
where p.slug = 'test-package' and e.status = 'published';

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
