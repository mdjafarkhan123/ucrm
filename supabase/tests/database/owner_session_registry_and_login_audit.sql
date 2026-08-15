begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

select has_table('public', 'platform_owner_sessions', 'owner sessions table exists');
select has_table('public', 'platform_owner_login_attempts', 'owner login attempts table exists');

select is((select relrowsecurity from pg_class where oid = 'public.platform_owner_sessions'::regclass), true, 'owner sessions RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.platform_owner_login_attempts'::regclass), true, 'owner login attempts RLS is enabled');

select is(has_table_privilege('anon', 'public.platform_owner_sessions', 'select'), false, 'anonymous callers cannot read owner sessions');
select is(has_table_privilege('authenticated', 'public.platform_owner_sessions', 'select'), false, 'contractors cannot read owner sessions');
select is(has_table_privilege('service_role', 'public.platform_owner_sessions', 'select'), true, 'owner service role can read owner sessions');
select is(has_table_privilege('service_role', 'public.platform_owner_sessions', 'insert'), true, 'owner service role can insert owner sessions');
select is(has_table_privilege('service_role', 'public.platform_owner_sessions', 'update'), true, 'owner service role can revoke owner sessions');

select is(has_table_privilege('anon', 'public.platform_owner_login_attempts', 'select'), false, 'anonymous callers cannot read login attempts');
select is(has_table_privilege('authenticated', 'public.platform_owner_login_attempts', 'select'), false, 'contractors cannot read login attempts');
select is(has_table_privilege('service_role', 'public.platform_owner_login_attempts', 'select'), true, 'owner service role can read login attempts');
select is(has_table_privilege('service_role', 'public.platform_owner_login_attempts', 'insert'), true, 'owner service role can insert login attempts');

select hasnt_column('public', 'platform_owner_login_attempts', 'ip_address', 'no raw IP address column exists on login attempts');
select hasnt_column('public', 'platform_owner_login_attempts', 'attempted_email', 'no raw attempted-email column exists on login attempts');

set local role postgres;

select lives_ok(
  $$insert into public.platform_owner_sessions (id, owner_email, expires_at) values ('30000000-0000-0000-0000-000000000001', 'owner@example.test', now() + interval '8 hours')$$,
  'a session can be created'
);
select lives_ok(
  $$update public.platform_owner_sessions set revoked_at = now(), revoked_reason = 'logout' where id = '30000000-0000-0000-0000-000000000001'$$,
  'a session can be revoked on logout'
);
select throws_ok(
  $$update public.platform_owner_sessions set owner_email = 'someone-else@example.test' where id = '30000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'a session owner_email cannot be changed after creation'
);
select throws_ok(
  $$delete from public.platform_owner_sessions where id = '30000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'a session cannot be deleted'
);

insert into public.platform_owner_login_attempts (outcome) values ('failed');
select throws_ok(
  $$update public.platform_owner_login_attempts set outcome = 'succeeded' where outcome = 'failed'$$,
  '23514',
  null,
  'a login attempt outcome cannot be changed after creation'
);

select * from finish();
rollback;
