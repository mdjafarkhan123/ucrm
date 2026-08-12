begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

select has_table('public', 'platform_owner_settings', 'owner settings table exists');
select is((select relrowsecurity from pg_class where oid = 'public.platform_owner_settings'::regclass), true, 'owner settings RLS is enabled');

select is(has_table_privilege('anon', 'public.platform_owner_settings', 'select'), false, 'anonymous callers cannot read owner settings');
select is(has_table_privilege('authenticated', 'public.platform_owner_settings', 'select'), false, 'contractors cannot read owner settings');
select is(has_table_privilege('anon', 'public.platform_owner_settings', 'insert'), false, 'anonymous callers cannot write owner settings');
select is(has_table_privilege('authenticated', 'public.platform_owner_settings', 'update'), false, 'contractors cannot write owner settings');
select is(has_table_privilege('service_role', 'public.platform_owner_settings', 'select'), true, 'owner service role can read owner settings');
select is(has_table_privilege('service_role', 'public.platform_owner_settings', 'insert'), true, 'owner service role can insert owner settings');
select is(has_table_privilege('service_role', 'public.platform_owner_settings', 'update'), true, 'owner service role can update owner settings');

set local role postgres;

-- The boolean primary key defaulting to true and checked as true is the whole singleton
-- guarantee: only one row can ever exist, and only with id = true.
select throws_ok(
  $$insert into public.platform_owner_settings (id) values (false)$$,
  '23514',
  null,
  'a settings row cannot be created with id = false'
);
select lives_ok(
  $$insert into public.platform_owner_settings (id) values (true)$$,
  'the singleton settings row can be created once'
);
select throws_ok(
  $$insert into public.platform_owner_settings (id) values (true)$$,
  '23505',
  null,
  'a second settings row cannot be created'
);

set local role service_role;

select lives_ok(
  $$select public.update_owner_settings(
    'owner@example.test', 'https://example.test/privacy', 'v2', 'Pay by bank transfer.',
    'UpliftContractor', 'hello@example.test', array['owner@example.test', 'alerts@example.test']::text[]
  )$$,
  'the owner can update settings through the atomic function'
);
select is(
  (select privacy_policy_version from public.platform_owner_settings where id = true),
  'v2',
  'the update is applied to the singleton row'
);
select is(
  (select count(*)::integer from public.platform_owner_audit_events where target_type = 'platform_owner_settings' and event_type = 'owner_settings.updated'),
  1,
  'the settings update creates a matching private audit event'
);

select * from finish();
rollback;
