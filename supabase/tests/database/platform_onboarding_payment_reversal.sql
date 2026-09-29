-- Part 5c-i: payment reversal RPC/table.
begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

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

-- Fixtures: one application on the private test package's published edition.
insert into public.platform_onboarding_applications (
  id, stage, business_name, main_contact_name, main_contact_email, main_contact_phone,
  trade, city_country, time_zone, package_edition_id, billing_interval, package_snapshot, possible_duplicate
)
select
  '70000000-0000-0000-0000-000000000010', 'new', 'Reversal Test Co', 'Alex Reversal',
  'alex@payment-reversal-test.example', '555-0400', 'Roofing', 'Austin, USA', 'America/Chicago',
  e.id, 'month',
  jsonb_build_object('display_name', e.name, 'price_usd_cents', e.monthly_price_usd_cents, 'currency', 'USD'),
  false
from public.package_editions e
join public.packages p on p.id = e.package_id
where p.slug = 'test-package' and e.status = 'published';

select throws_ok(
  $$select public.reverse_onboarding_application_payment('70000000-0000-0000-0000-000000000010', 'owner@example.test', 'Trying to reverse before any payment.')$$,
  '23514',
  null,
  'reversing an application that was never paid is refused'
);

-- Payment confirmation is rebuilt in package-builder P10; until then the confirmed state is placed
-- directly, the way the old confirm command left it.
insert into public.platform_onboarding_application_payment_confirmations (
  application_id, actor_owner_email, amount_usd_cents, private_reference
) values (
  '70000000-0000-0000-0000-000000000010', 'owner@example.test', 12345, 'ref-payment-reversal-test'
);
update public.platform_onboarding_applications set stage = 'payment_confirmed'
where id = '70000000-0000-0000-0000-000000000010';

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
