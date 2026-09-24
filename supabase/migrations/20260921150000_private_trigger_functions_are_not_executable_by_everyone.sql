-- Take EXECUTE on every trigger function in the private schema away from PUBLIC, anon and authenticated.
--
-- Older trigger functions kept Postgres's default grant to PUBLIC, while the newer ones were revoked one by one,
-- so the same kind of function had two different answers. Nothing needs the grant: a trigger runs its function
-- as part of the write regardless of who is asked to execute it, a trigger function cannot be called directly
-- ("trigger functions can only be called as triggers"), and `authenticated` and `anon` have no USAGE on the
-- private schema anyway. Least privilege: only the owner keeps it.
--
-- The loop names the functions by what they are (a trigger function in `private`) rather than by a hand-kept
-- list, so it also covers the ones added since the note that asked for this counted eleven. service_role never
-- needed the inherited PUBLIC grant either, since triggers do not check EXECUTE.

do $$
declare
  fn regprocedure;
begin
  for fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;
end
$$;
