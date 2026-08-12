begin;
select plan(18);

select has_table('public', 'platform_onboarding_applications', 'onboarding applications table exists');
select has_table('public', 'platform_onboarding_application_submissions', 'original submission table exists');
select has_table('public', 'platform_onboarding_application_corrections', 'corrections table exists');
select has_index('public', 'platform_onboarding_applications', 'platform_onboarding_applications_stage_idx', 'stage index exists');
select has_index('public', 'platform_onboarding_applications', 'platform_onboarding_applications_contact_email_idx', 'contact email index exists');
select has_index('public', 'platform_onboarding_applications', 'platform_onboarding_applications_admin_email_idx', 'administrator email index exists');
select has_index('public', 'platform_onboarding_application_corrections', 'platform_onboarding_application_corrections_application_idx', 'correction history index exists');

select is((select relrowsecurity from pg_class where oid = 'public.platform_onboarding_applications'::regclass), true, 'application RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.platform_onboarding_application_submissions'::regclass), true, 'submission RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.platform_onboarding_application_corrections'::regclass), true, 'correction RLS is enabled');
select is(has_table_privilege('anon', 'public.platform_onboarding_applications', 'select'), false, 'anonymous callers cannot read applications');
select is(has_table_privilege('authenticated', 'public.platform_onboarding_applications', 'select'), false, 'contractors cannot read applications');
select is(has_table_privilege('anon', 'public.platform_onboarding_application_submissions', 'select'), false, 'anonymous callers cannot read original submissions');
select is(has_table_privilege('authenticated', 'public.platform_onboarding_application_corrections', 'select'), false, 'contractors cannot read corrections');
select is(has_table_privilege('service_role', 'public.platform_onboarding_applications', 'select'), true, 'owner service role can read applications');
select is(has_table_privilege('service_role', 'public.platform_onboarding_application_submissions', 'select'), true, 'owner service role can read original submissions');
select is(has_function_privilege('anon', 'private.prevent_platform_onboarding_history_mutation()', 'execute'), false, 'anonymous callers cannot execute history trigger function');
select is(has_function_privilege('authenticated', 'private.prevent_platform_onboarding_history_mutation()', 'execute'), false, 'contractors cannot execute history trigger function');

select * from finish();
rollback;
