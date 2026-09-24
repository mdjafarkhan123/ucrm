-- Every trigger function in the private schema is closed to PUBLIC, anon and authenticated.
--
-- The rule lives in one place: a new trigger function that forgets its `revoke all` fails here, the same way
-- the team grant matrix fails a command that does. has_function_privilege is used rather than
-- information_schema.role_routine_grants because it also accounts for a grant inherited from PUBLIC.
--
-- Written for `supabase test db`; runs in one transaction that is rolled back at the end.
begin;

create extension if not exists pgtap with schema extensions;

select plan(2);

select is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.prorettype = 'trigger'::regtype
  ) > 0,
  true,
  'the private schema has trigger functions to check'
);

select is(
  (
    select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.proname), '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.prorettype = 'trigger'::regtype
      and (
        has_function_privilege('public', p.oid, 'execute')
        or has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute')
      )
  ),
  '',
  'no private trigger function is executable by PUBLIC, anon or authenticated'
);

select * from finish();

rollback;
