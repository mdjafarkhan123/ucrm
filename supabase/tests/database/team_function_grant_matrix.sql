-- Team & access, part 3A, items 7 and 8: who may execute what, and who may write what.
--
-- Every other test in this part proves what a command does. This one proves who can reach it at all. It
-- names all 49 functions the part ships or depends on, and for each one asserts a yes or no for anon,
-- authenticated and service_role -- 147 answers, no gaps. A new command that forgets its closing
-- `revoke all` fails here, and so does a policy helper that loses the EXECUTE its policies need.
--
-- The four groups and why each is what it is:
--   service_role only    every command that changes a membership, an invitation or an ownership handover.
--                        A browser session must never call one directly; it goes through an API route
--                        that has already checked who is asking.
--   authenticated too    effective_employee_seat_limit is a plain read the display path calls through the
--                        signed-in session, and the /jafar console calls the same one as service_role.
--   authenticated only   the six helpers that appear inside RLS policy expressions. Policies evaluate as
--                        the querying user, so revoking these breaks every read they guard.
--   nobody               the command-support helpers and the trigger functions. Nothing outside the
--                        database has any business calling them.
--
-- Sections 6 and 7 came with item 8, when the last two direct write paths closed. A command is only the
-- single way in if the table underneath it cannot be written any other way, so the table grants belong in
-- the same file as the function grants -- half the answer on its own proves nothing.
--
-- has_function_privilege is used rather than information_schema.role_routine_grants because it also
-- accounts for a grant inherited from PUBLIC -- the exact hole a bare `grant execute` leaves behind.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention the sibling files document.
begin;

create extension if not exists pgtap with schema extensions;

select plan(167);

create temporary table tap_results (id serial primary key, line text);

-- 1. The expected matrix -----------------------------------------------------------------------------------

create temporary table expected_execute (
  schema_name text not null,
  function_name text not null,
  role_name text not null,
  allowed boolean not null,
  primary key (schema_name, function_name, role_name)
);

-- Every function, with the roles that may execute it. The three-role fan-out happens below, so a name
-- listed here is automatically denied to the two roles it does not name.
insert into expected_execute (schema_name, function_name, role_name, allowed)
select f.schema_name, f.function_name, r.role_name, r.role_name = any (f.allowed_roles)
from (
  values
    -- Commands: the server only.
    ('public', 'accept_ownership_transfer', array['service_role']),
    ('public', 'apply_organization_member_profile_correction', array['service_role']),
    ('public', 'attach_team_invitation_identity', array['service_role']),
    ('public', 'begin_team_invitation', array['service_role']),
    ('public', 'cancel_team_invitation', array['service_role']),
    ('public', 'change_team_member_role', array['service_role']),
    ('public', 'claim_cancelled_team_invitation_cleanup', array['service_role']),
    ('public', 'claim_team_invitation', array['service_role']),
    ('public', 'claim_team_invitation_reconciliation', array['service_role']),
    ('public', 'close_ownership_transfer', array['service_role']),
    ('public', 'deactivate_team_member', array['service_role']),
    ('public', 'expire_team_invitations', array['service_role']),
    ('public', 'finalize_team_invitation', array['service_role']),
    ('public', 'find_team_invitation_auth_receipt', array['service_role']),
    ('public', 'mark_member_identity_revoked', array['service_role']),
    ('public', 'mark_team_invitation_auth_attempt_started', array['service_role']),
    ('public', 'prepare_team_invitation_identity_cleanup', array['service_role']),
    ('public', 'record_invitation_password_set', array['service_role']),
    ('public', 'record_team_invitation_delivery', array['service_role']),
    ('public', 'release_team_invitation_reconciliation', array['service_role']),
    ('public', 'remove_team_member', array['service_role']),
    ('public', 'request_ownership_transfer', array['service_role']),
    ('public', 'resend_team_invitation', array['service_role']),
    ('public', 'restore_team_member', array['service_role']),
    ('public', 'save_team_member_permissions', array['service_role']),
    ('public', 'settle_team_invitation_identity_cleanup', array['service_role']),
    ('public', 'sweep_team_invitation_reservations', array['service_role']),
    ('public', 'update_team_member_profile', array['service_role']),
    -- A read both sides make: the contractor's own settings page, and the Platform Owner console.
    ('public', 'effective_employee_seat_limit', array['authenticated', 'service_role']),
    -- Policy helpers: evaluated as the querying user, so they must stay callable by that user.
    ('private', 'has_permission', array['authenticated']),
    ('private', 'is_organization_admin', array['authenticated']),
    ('private', 'is_organization_member', array['authenticated']),
    ('private', 'member_organizations', array['authenticated']),
    ('private', 'permission_scope', array['authenticated']),
    ('private', 'permitted_organizations', array['authenticated']),
    -- Command support and trigger functions: nobody's to call.
    ('private', 'assert_employee_seat_available', array[]::text[]),
    ('private', 'assert_team_invitation_overrides', array[]::text[]),
    ('private', 'assert_membership_is_editable', array[]::text[]),
    ('private', 'authorize_team_member_command', array[]::text[]),
    ('private', 'employee_seats_used', array[]::text[]),
    ('private', 'enforce_member_access_event_shape', array[]::text[]),
    ('private', 'finalize_accepted_invitation', array[]::text[]),
    ('private', 'member_access_required_keys_are_allowed', array[]::text[]),
    ('private', 'member_access_summary_kinds_are_known', array[]::text[]),
    ('private', 'member_access_summary_value_fits', array[]::text[]),
    ('private', 'member_has_permission', array[]::text[]),
    ('private', 'member_permission_scope', array[]::text[]),
    ('private', 'prevent_member_access_event_mutation', array[]::text[]),
    ('private', 'validate_client_owner', array[]::text[])
) as f (schema_name, function_name, allowed_roles)
cross join (values ('anon'), ('authenticated'), ('service_role')) as r (role_name);

-- 2. Every listed function exists, exactly once ------------------------------------------------------------
--
-- An overload would make the matrix ambiguous -- two functions of the same name could carry different
-- grants and the join below would silently test both under one description. None of these are overloaded,
-- and this assertion is what keeps that true.

insert into tap_results (line) select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname, p.proname) in (
      select distinct schema_name, function_name from expected_execute)),
  49, 'all 49 named functions exist, and none of them is overloaded'
);

-- 3. Nothing on the exposed surface escaped the matrix -----------------------------------------------------
--
-- public is what PostgREST exposes, so a new team command that nobody added here would otherwise be
-- unguarded by this file. Names are matched the way the part names things.

insert into tap_results (line) select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like '%team_%' or p.proname like '%ownership_transfer%'
        or p.proname like '%invitation%' or p.proname like '%member%')
      and p.proname not in (select function_name from expected_execute)),
  '', 'no exposed team function is missing from this matrix'
);

-- 4. The matrix itself, 49 functions by three roles --------------------------------------------------------

insert into tap_results (line)
select is(
  has_function_privilege(e.role_name, p.oid, 'EXECUTE'),
  e.allowed,
  format('%s.%s: %s %s execute it',
    e.schema_name, e.function_name, e.role_name,
    case when e.allowed then 'may' else 'may not' end)
)
from expected_execute e
join pg_namespace n on n.nspname = e.schema_name
join pg_proc p on p.pronamespace = n.oid and p.proname = e.function_name
order by e.schema_name, e.function_name, e.role_name;

-- 5. Locking a trigger function does not unhook its trigger ------------------------------------------------
--
-- Postgres checks EXECUTE on a trigger function when the trigger is created, not every time it fires, so
-- taking the grant away in 20260831090100 leaves the trigger working. This asserts the trigger is still
-- attached and still enabled, which is the half a grant change could plausibly have broken.

insert into tap_results (line) select is(
  (select count(*)::int
     from pg_trigger t
     join pg_proc p on p.oid = t.tgfoid
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'validate_client_owner'
      and not t.tgisinternal
      and t.tgenabled = 'O'),
  1, 'the client owner trigger is still attached and still fires'
);

-- 6. No browser session may write any of the eight tables ---------------------------------------------------
--
-- Item 7 cleared six of these and item 8 cleared the last two. Every write to all eight now goes through a
-- SECURITY DEFINER command, so a surviving grant would be a way around the authority checks inside those
-- commands -- refused by RLS today, but refused by one layer instead of two. SELECT is deliberately not
-- asserted here: the team and settings screens read these tables as the signed-in user.

create temporary table write_grant_tables (table_name text primary key);
insert into write_grant_tables (table_name) values
  ('organization_members'),
  ('organization_member_invitations'),
  ('organization_member_permission_overrides'),
  ('organization_settings'),
  ('organization_settings_audit'),
  ('organization_business_hours'),
  ('permissions'),
  ('role_permissions');

insert into tap_results (line)
select is(
  (select coalesce(string_agg(privilege, ', ' order by privilege), '')
     from unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) as privilege
    where has_table_privilege(role_name, format('public.%I', t.table_name), privilege)),
  '',
  format('public.%s: %s may not write it', t.table_name, role_name)
)
from write_grant_tables t
cross join unnest(array['anon', 'authenticated']) as role_name
order by t.table_name, role_name;

-- 7. The spare overrides index stayed dropped ---------------------------------------------------------------
--
-- (organization_id, user_id) is a strict prefix of that table's primary key, so it served no lookup the key
-- did not already serve, while costing a second index write on every row a permission save touches. A
-- later migration recreating it would be re-adding that cost for nothing.

insert into tap_results (line) select is(
  (select count(*)::int from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_member_permission_overrides_user_idx'),
  0, 'the overrides table carries no index that only repeats its primary key'
);

select * from finish();

select line from tap_results where line like 'not ok%' order by id;

rollback;
