begin;
select plan(9);

select has_table('public', 'platform_onboarding_application_payment_confirmations', 'payment confirmations table exists');
select has_index('public', 'platform_onboarding_application_payment_confirmations', 'platform_onboarding_application_payment_confirmations_app_idx', 'application history index exists');

select is((select relrowsecurity from pg_class where oid = 'public.platform_onboarding_application_payment_confirmations'::regclass), true, 'payment confirmation RLS is enabled');
select is(has_table_privilege('anon', 'public.platform_onboarding_application_payment_confirmations', 'select'), false, 'anonymous callers cannot read payment confirmations');
select is(has_table_privilege('authenticated', 'public.platform_onboarding_application_payment_confirmations', 'select'), false, 'contractors cannot read payment confirmations');
select is(has_table_privilege('anon', 'public.platform_onboarding_application_payment_confirmations', 'insert'), false, 'anonymous callers cannot write payment confirmations');
select is(has_table_privilege('authenticated', 'public.platform_onboarding_application_payment_confirmations', 'insert'), false, 'contractors cannot write payment confirmations');
select is(has_table_privilege('service_role', 'public.platform_onboarding_application_payment_confirmations', 'select'), true, 'owner service role can read payment confirmations');
select is(has_table_privilege('service_role', 'public.platform_onboarding_application_payment_confirmations', 'insert'), true, 'owner service role can insert payment confirmations');

select * from finish();
rollback;
