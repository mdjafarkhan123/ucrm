-- Team & access, part 3A, item 7, found by the function-grant matrix before the matrix was even written.
--
-- 20260826090100 exposed effective_employee_seat_limit in public and granted EXECUTE to authenticated,
-- because the contractor path reads it through the signed-in session. But resolveOrganizationAccess is
-- also called with the service_role client by every /jafar organization route -- package, access,
-- lifecycle, free access, feature overrides, limit overrides -- and effective.ts throws on any failed
-- query in that batch. So service_role hit "permission denied for function
-- effective_employee_seat_limit" and every one of those Platform Owner reads was answering 500.
-- Confirmed live by calling it under `set local role service_role` before writing this.
--
-- The function stays security invoker. Under service_role that is not a loosening: the role already
-- bypasses RLS, so it reads exactly what the Platform Owner console is entitled to read, and a
-- contractor session still gets its own rows filtered by the same policies as before.

grant execute on function public.effective_employee_seat_limit(uuid, timestamptz) to service_role;

-- The seventh membership-seam helper is a trigger function, like enforce_member_access_event_shape and
-- prevent_member_access_event_mutation, which are already nobody's to call. This one kept the default
-- public EXECUTE. Postgres refuses to run a trigger function as a plain call anyway, so nothing changes
-- in behaviour -- it just stops being the one helper in the seam whose grant says otherwise.
--
-- The eleven older Clients and collaboration trigger functions in `private` still carry the same default
-- and are logged in Memory/deferred/INDEX.md; sweeping them belongs to that domain, not to 3A.
revoke all on function private.validate_client_owner() from public, anon, authenticated, service_role;
