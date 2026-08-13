-- Part 5c-i: payment reversal RPC/table.
begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- Schema / RLS / privileges.
select has_table('public', 'platform_onboarding_application_payment_reversals', 'payment reversals table exists');
select has_index('public', 'platform_onboarding_application_payment_reversals', 'platform_onboarding_application_payment_reversals_app_idx', 'reversal history index exists');
select is((select relrowsecurity from pg_class where oid = 'public.platform_onboarding_application_payment_reversals'::regclass), true, 'reversal RLS is enabled');
select is(has_table_privilege('anon', 'public.platform_onboarding_application_payment_reversals', 'select'), false, 'anonymous callers cannot read reversals');
select is(has_table_privilege('authenticated', 'public.platform_onboarding_application_payment_reversals', 'select'), false, 'contractors cannot read reversals');
select is(has_table_privilege('anon', 'public.platform_onboarding_application_payment_reversals', 'insert'), false, 'anonymous callers cannot write reversals');
select is(has_table_privilege('authenticated', 'public.platform_onboarding_application_payment_reversals', 'insert'), false, 'contractors cannot write reversals');
select is(has_table_privilege('service_role', 'public.platform_onboarding_application_payment_reversals', 'select'), true, 'owner service role can read reversals');
select is(has_table_privilege('service_role', 'public.platform_onboarding_application_payment_reversals', 'insert'), true, 'owner service role can insert reversals');

select is(has_function_privilege('anon', 'public.reverse_onboarding_application_payment(uuid, text, text)', 'execute'), false, 'anonymous callers cannot reverse a payment');
select is(has_function_privilege('authenticated', 'public.reverse_onboarding_application_payment(uuid, text, text)', 'execute'), false, 'contractors cannot reverse a payment');
select is(has_function_privilege('service_role', 'public.reverse_onboarding_application_payment(uuid, text, text)', 'execute'), true, 'the owner service role can reverse a payment');

-- Fixtures: reuse whichever package version is currently published (only one published
-- version per package is allowed, so this test must not insert a competing one) and one
-- paid application against it.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_version_id, package_snapshot, possible_duplicate
)
select
  '70000000-0000-0000-0000-000000000010', 'new', 'Reversal Test Co', 'Alex Reversal',
  'alex@payment-reversal-test.example', '555-0400', 'Roofing', 'Austin, USA', 'America/Chicago',
  v.id,
  jsonb_build_object('display_name', v.display_name, 'price_usd_cents', v.price_usd_cents, 'currency', v.currency),
  false
from public.platform_package_versions v
where v.status = 'published'
limit 1;

select throws_ok(
  $$select public.reverse_onboarding_application_payment('70000000-0000-0000-0000-000000000010', 'owner@example.test', 'Trying to reverse before any payment.')$$,
  '23514',
  null,
  'reversing an application that was never paid is refused'
);

select public.confirm_onboarding_application_payment(
  '70000000-0000-0000-0000-000000000010', 'owner@example.test', 12345, 'ref-payment-reversal-test', null
);

select is(
  (select stage from public.platform_onboarding_applications where id = '70000000-0000-0000-0000-000000000010'),
  'payment_confirmed',
  'confirming payment moves the application to payment_confirmed'
);

select lives_ok(
  $$select public.reverse_onboarding_application_payment('70000000-0000-0000-0000-000000000010', 'owner@example.test', 'Bank confirmed the transfer was reversed by the sender.')$$,
  'reversing a confirmed payment succeeds'
);
select is(
  (select stage from public.platform_onboarding_applications where id = '70000000-0000-0000-0000-000000000010'),
  'needs_attention',
  'the application moves to needs_attention after reversal'
);
select is(
  (select payment_reversed_at is not null from public.platform_onboarding_applications where id = '70000000-0000-0000-0000-000000000010'),
  true,
  'payment_reversed_at is stamped'
);
select is(
  (select count(*)::int from public.platform_onboarding_application_payment_reversals
   where application_id = '70000000-0000-0000-0000-000000000010'),
  1,
  'the reversal is recorded in its own history table'
);
select is(
  (select reversed_amount_usd_cents from public.platform_onboarding_application_payment_reversals
   where application_id = '70000000-0000-0000-0000-000000000010'),
  12345,
  'the reversal carries the confirmed amount'
);
select is(
  (select count(*)::int from public.platform_owner_audit_events
   where event_type = 'onboarding_application.payment_reversed'
     and target_key = '70000000-0000-0000-0000-000000000010'),
  1,
  'the reversal leaves a matching audit event'
);

select throws_ok(
  $$select public.reverse_onboarding_application_payment('70000000-0000-0000-0000-000000000010', 'owner@example.test', 'Trying to reverse the same payment twice.')$$,
  '23514',
  null,
  'reversing an already-reversed payment is refused'
);

select throws_ok(
  $$select public.provision_organization_from_application(
      '70000000-0000-0000-0000-000000000010', '70000000-0000-0000-0000-000000000020',
      'Reversal Test Co', 'reversal-test-co', '70000000-0000-0000-0000-000000000030', 'owner', 'owner@example.test'
    )$$,
  '23514',
  null,
  'provisioning is blocked while the payment stays reversed'
);

select lives_ok(
  $$select public.confirm_onboarding_application_payment('70000000-0000-0000-0000-000000000010', 'owner@example.test', 12345, 'ref-payment-reversal-retry', null)$$,
  're-confirming payment after a reversal succeeds'
);
select is(
  (select payment_reversed_at is null from public.platform_onboarding_applications where id = '70000000-0000-0000-0000-000000000010'),
  true,
  're-confirming payment clears payment_reversed_at'
);
select is(
  (select stage from public.platform_onboarding_applications where id = '70000000-0000-0000-0000-000000000010'),
  'payment_confirmed',
  're-confirming payment moves the application back to payment_confirmed'
);
select is(
  (select count(*)::int from public.platform_onboarding_application_payment_confirmations
   where application_id = '70000000-0000-0000-0000-000000000010'),
  2,
  'a second confirmation after a reversal is allowed, not blocked by a singleton constraint'
);

select throws_ok(
  $$update public.platform_onboarding_application_payment_reversals
    set reason = 'tampering with history'
    where application_id = '70000000-0000-0000-0000-000000000010'$$,
  '23514',
  null,
  'a reversal history row cannot be edited'
);
select throws_ok(
  $$delete from public.platform_onboarding_application_payment_reversals
    where application_id = '70000000-0000-0000-0000-000000000010'$$,
  '23514',
  null,
  'a reversal history row cannot be deleted'
);

select throws_ok(
  $$select public.reverse_onboarding_application_payment('70000000-0000-0000-0000-000000000099', 'owner@example.test', 'Testing a missing application.')$$,
  '23503',
  null,
  'a missing application is refused'
);

select * from finish();
rollback;
