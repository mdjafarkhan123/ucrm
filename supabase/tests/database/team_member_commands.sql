-- Team & access, part 3A, item 6: the seven commands that change one team member's standing.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention team_ownership_transfer_commands.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` does
-- not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(109);

-- Every assertion's TAP line is captured here so the whole run can be inspected in one final SELECT -- the
-- query tool used to verify this file only returns the last statement's result set.
create temporary table tap_results (id serial primary key, line text);
-- Seat counts are compared before and after, so they are stashed as they are taken.
create temporary table seat_counts (label text primary key, value integer);

do $grant$
begin
  execute format(
    'grant usage on schema %I to service_role, authenticated',
    (select nspname from pg_namespace where oid = pg_my_temp_schema())
  );
end;
$grant$;
grant insert, select on tap_results to service_role, authenticated;
grant usage on sequence tap_results_id_seq to service_role, authenticated;
grant insert, select on seat_counts to service_role, authenticated;

-- 1. The commands exist, and only the server may call them ------------------------------------------------

insert into tap_results (line) select has_function(
  'public', 'change_team_member_role', 'the role command exists'
);
insert into tap_results (line) select has_function(
  'public', 'save_team_member_permissions', 'the permissions command exists'
);
insert into tap_results (line) select has_function(
  'public', 'update_team_member_profile', 'the member details command exists'
);
insert into tap_results (line) select has_function(
  'public', 'deactivate_team_member', 'the deactivate command exists'
);
insert into tap_results (line) select has_function(
  'public', 'restore_team_member', 'the restore command exists'
);
insert into tap_results (line) select has_function(
  'public', 'remove_team_member', 'the permanent removal command exists'
);
insert into tap_results (line) select has_function(
  'public', 'mark_member_identity_revoked', 'the identity cleanup ledger command exists'
);

insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name in (
        'change_team_member_role', 'save_team_member_permissions', 'update_team_member_profile',
        'deactivate_team_member', 'restore_team_member', 'remove_team_member',
        'mark_member_identity_revoked'
      )
      and grantee in ('anon', 'authenticated')),
  0, 'no browser session may call a team member command directly'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name in (
        'change_team_member_role', 'save_team_member_permissions', 'update_team_member_profile',
        'deactivate_team_member', 'restore_team_member', 'remove_team_member',
        'mark_member_identity_revoked'
      )
      and grantee = 'service_role' and privilege_type = 'EXECUTE'),
  7, 'all seven commands are callable by the server only'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'private'
      and routine_name in ('authorize_team_member_command', 'assert_membership_is_editable')
      and grantee in ('anon', 'authenticated', 'service_role')),
  0, 'the shared authorization helpers are nobody''s to call'
);

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at,
  raw_user_meta_data
)
values
  ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-owner@example.test', 'test', now(), now(), now(),
   '{"full_name": "Olive Owner"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-admin@example.test', 'test', now(), now(), now(),
   '{"full_name": "Ada Admin"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-admin-two@example.test', 'test', now(), now(), now(),
   '{"full_name": "Bruno Admin"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-office@example.test', 'test', now(), now(), now(),
   '{"full_name": "Ollie Office"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-field@example.test', 'test', now(), now(), now(),
   '{"full_name": "Fiona Field"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-pending@example.test', 'test', now(), now(), now(),
   '{"full_name": "Pat Pending"}'::jsonb),
  -- Deliberately nameless: permanent removal has to produce a label for this person too.
  ('e0000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-nameless@example.test', 'test', now(), now(), now(), '{}'::jsonb),
  ('e0000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'other-member-owner@example.test', 'test', now(), now(), now(),
   '{"full_name": "Otto Other"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'other-member-office@example.test', 'test', now(), now(), now(),
   '{"full_name": "Oona Other"}'::jsonb),
  ('e0000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'member-admin-off@example.test', 'test', now(), now(), now(),
   '{"full_name": "Del Deactivated"}'::jsonb);

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('e1000000-0000-0000-0000-000000000001', 'Member Test Co', 'member-test-co', 'active'),
  ('e1000000-0000-0000-0000-000000000002', 'Other Member Co', 'other-member-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000003', 'admin', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000004', 'office', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000005', 'field', 'active'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000006', 'office', 'pending'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000007', 'office', 'deactivated'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000010', 'admin', 'deactivated'),
  ('e1000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000008', 'owner', 'active'),
  ('e1000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000009', 'office', 'deactivated');

-- The first company has room to spare; the second has exactly one seat, already taken by its owner, so a
-- restore there has nowhere to go.
insert into public.organization_limit_overrides
  (organization_id, limit_key, limit_value, is_unlimited, limit_state, starts_at)
values
  ('e1000000-0000-0000-0000-000000000001', 'employee_seats', null, true, 'unlimited',
   '2026-01-01T00:00:00Z'),
  ('e1000000-0000-0000-0000-000000000002', 'employee_seats', 1, false, 'numeric', '2026-01-01T00:00:00Z');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  -- Ollie Office keeps two adjustments that a role change with keep_adjustments off should sweep away.
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000004', 'team.manage', 'grant'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000004',
   'quotes.view_price', 'deny'),
  -- Fiona Field's four are one of each kind, so keeping the compatible ones can be told apart from keeping
  -- everything: finance already includes customers.view and never had catalog.edit, so those two say
  -- nothing under the new role; the other two still do.
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000005',
   'customers.view', 'grant'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000005', 'catalog.edit', 'deny'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000005', 'quotes.send', 'grant'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000005',
   'quotes.view_cost', 'deny');

set local role service_role;

-- 3. The authority every command shares --------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000002',
      'office', false, 1
    )$$,
  '23514', null, 'nobody changes their own access'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'e0000000-0000-0000-0000-000000000004',
      'sales', false, 1
    )$$,
  '23514', null, 'an ordinary member cannot change anyone''s role'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000010',
      'e0000000-0000-0000-0000-000000000004',
      'sales', false, 1
    )$$,
  '23514', null, 'a deactivated administrator has no authority left'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000008',
      'e0000000-0000-0000-0000-000000000004',
      'sales', false, 1
    )$$,
  '23514', null, 'an owner at another company has no authority here'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000003',
      'office', false, 1
    )$$,
  '23514', null, 'an administrator cannot manage another administrator'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000001',
      'office', false, 1
    )$$,
  '23514', null, 'the owner is never a target'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000009',
      'sales', false, 1
    )$$,
  'P0002', null, 'somebody at another company is not a team member here'
);
insert into tap_results (line) select throws_ok(
  $$select public.deactivate_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'the owner cannot be deactivated by an administrator'
);
insert into tap_results (line) select throws_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'the owner cannot be permanently removed either'
);

-- 4. Role ---------------------------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'sales', false, 7
    )$$,
  '40001', null, 'a stale editor is refused instead of overwriting'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'owner', false, 1
    )$$,
  '23514', null, 'ownership cannot be handed out as a role'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'wizard', false, 1
    )$$,
  '23514', null, 'a made-up role is refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000004',
      'admin', false, 1
    )$$,
  '23514', null, 'only the owner makes somebody an administrator'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'office', false, 1
    )$$,
  '23514', null, 'a role change that changes nothing is refused'
);

insert into tap_results (line) select lives_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'sales', false, 1
    )$$,
  'the owner moves an office member to sales'
);
insert into tap_results (line) select is(
  (select role from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  'sales', 'the new role is stored'
);
insert into tap_results (line) select is(
  (select access_revision from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  2, 'the access revision moved, so an open editor elsewhere is now stale'
);
insert into tap_results (line) select is(
  (select summary from public.organization_member_access_events
    where event_type = 'member.role_changed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  '{"new_role": "sales", "previous_role": "office"}'::jsonb,
  'the history says what the role was and what it became'
);
insert into tap_results (line) select is(
  (select summary -> 'removed_permissions' from public.organization_member_access_events
    where event_type = 'member.permissions_changed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  '["quotes.view_price", "team.manage"]'::jsonb,
  'dropping the adjustments is its own line in the history'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_permission_overrides
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  0, 'standard access means the individual adjustments are gone'
);

insert into tap_results (line) select lives_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'finance', true, 1
    )$$,
  'a role change may keep the adjustments that still mean something'
);
insert into tap_results (line) select is(
  (select array_agg(permission_key order by permission_key)
    from public.organization_member_permission_overrides
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000005'),
  array['quotes.send', 'quotes.view_cost'],
  'only the adjustments the new role does not already settle survive'
);
insert into tap_results (line) select is(
  (select summary -> 'removed_permissions' from public.organization_member_access_events
    where event_type = 'member.permissions_changed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000005'),
  '["catalog.edit", "customers.view"]'::jsonb,
  'the history names the adjustments that were dropped as meaningless'
);

insert into tap_results (line) select lives_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000006',
      'sales', false, 1
    )$$,
  'a pending invitee''s role can be changed without reinviting them'
);
insert into tap_results (line) select lives_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000006',
      'admin', false, 2
    )$$,
  'the owner may make somebody an administrator'
);

-- 5. Permission adjustments ----------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[]'::jsonb, 1
    )$$,
  '40001', null, 'a stale permissions editor is refused too'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '{"quotes.view": "grant"}'::jsonb, 2
    )$$,
  '23514', null, 'the adjustments have to arrive as a list'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.invent", "override_state": "grant"}]'::jsonb, 2
    )$$,
  '23514', null, 'a permission nobody has heard of is refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.view", "override_state": "maybe"}]'::jsonb, 2
    )$$,
  '23514', null, 'an adjustment is either a grant or a deny'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.view", "override_state": "grant", "access_scope": "assigned"}]'::jsonb, 2
    )$$,
  '23514', null, 'assigned-only access is refused, because no domain enforces it yet'
);
insert into tap_results (line) select throws_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.view", "override_state": "grant"},
        {"permission_key": "quotes.view", "override_state": "deny"}]'::jsonb, 2
    )$$,
  '23514', null, 'the same permission cannot be adjusted twice in one save'
);

insert into tap_results (line) select lives_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.view_cost", "override_state": "grant"},
        {"permission_key": "quotes.send", "override_state": "deny"}]'::jsonb, 2
    )$$,
  'an administrator may adjust one member''s access'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_permission_overrides
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'
      and access_scope = 'all'),
  2, 'both adjustments are stored, at full scope'
);
-- Every line in this transaction shares one created_at, because now() does not move inside a transaction.
-- So the assertions below name the line they mean by its contents rather than by being the newest.
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.permissions_changed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'
      and summary = '{"added_permissions": ["quotes.send", "quotes.view_cost"]}'::jsonb),
  1, 'one save is one history line naming what was added'
);
insert into tap_results (line) select is(
  (select access_revision from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  3, 'an adjustment save moves the access revision'
);

insert into tap_results (line) select lives_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.view_cost", "override_state": "grant"},
        {"permission_key": "quotes.send", "override_state": "deny"}]'::jsonb, 3
    )$$,
  'saving the same adjustments again is allowed'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.permissions_changed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  2, 'a save that changed nothing writes no history line'
);
insert into tap_results (line) select is(
  (select access_revision from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  3, 'and it does not invalidate anybody else''s open editor'
);

insert into tap_results (line) select lives_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[{"permission_key": "quotes.view_cost", "override_state": "grant"},
        {"permission_key": "quotes.send", "override_state": "grant"}]'::jsonb, 3
    )$$,
  'an adjustment may be flipped from a deny to a grant'
);
insert into tap_results (line) select is(
  (select override_state from public.organization_member_permission_overrides
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'
      and permission_key = 'quotes.send'),
  'grant', 'the flipped adjustment is stored the new way round'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.permissions_changed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'
      and summary = '{"added_permissions": ["quotes.send"], "removed_permissions": ["quotes.send"]}'::jsonb),
  1, 'a flip reads as one adjustment leaving and another arriving'
);

insert into tap_results (line) select lives_ok(
  $$select public.save_team_member_permissions(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      '[]'::jsonb, 4
    )$$,
  'an empty save puts the member back on standard access'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_permission_overrides
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  0, 'every adjustment is gone'
);

-- 6. Member details ---------------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.update_team_member_profile(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'Ollie Renamed', '0400 000 000', 'Estimator', '#3366FF', 9
    )$$,
  '40001', null, 'member details have their own conflict protection'
);
insert into tap_results (line) select throws_ok(
  $$select public.update_team_member_profile(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      null, null, null, 'blue', 1
    )$$,
  '23514', null, 'a colour that is not a colour is refused'
);

insert into tap_results (line) select lives_ok(
  $$select public.update_team_member_profile(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'Ollie Renamed', '0400 000 000', 'Estimator', '#3366FF', 1
    )$$,
  'an administrator may save another member''s business details'
);
insert into tap_results (line) select ok(
  (select work_phone = '0400 000 000' and job_title = 'Estimator' and schedule_color = '#3366FF'
    from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  'the details this business keeps are stored on the membership'
);
insert into tap_results (line) select is(
  (select full_name from public.profiles where id = 'e0000000-0000-0000-0000-000000000004'),
  'Ollie Renamed', 'the name is saved on the person, where it belongs'
);
insert into tap_results (line) select is(
  (select summary -> 'changed_fields' from public.organization_member_access_events
    where event_type = 'member.profile_updated'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  '["full_name", "work_phone", "job_title", "schedule_color"]'::jsonb,
  'the history names the fields that changed, never their values'
);
insert into tap_results (line) select is(
  (select profile_revision from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  2, 'details and access carry separate revisions'
);
insert into tap_results (line) select is(
  (select access_revision from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  5, 'saving details does not disturb an open access editor'
);

insert into tap_results (line) select lives_ok(
  $$select public.update_team_member_profile(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'Ollie Renamed', '0400 000 000', 'Estimator', '#3366FF', 2
    )$$,
  'saving the same details again is allowed'
);
insert into tap_results (line) select is(
  (select profile_revision from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  2, 'a details save that changed nothing changes nothing'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.profile_updated'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  1, 'and writes no second history line'
);

insert into tap_results (line) select lives_ok(
  $$select public.update_team_member_profile(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      null, null, 'Estimator', '#3366FF', 2
    )$$,
  'a work phone can be cleared'
);
insert into tap_results (line) select is(
  (select full_name from public.profiles where id = 'e0000000-0000-0000-0000-000000000004'),
  'Ollie Renamed', 'leaving the name out leaves the name alone, everywhere that person appears'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.profile_updated'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'
      and summary -> 'changed_fields' = '["work_phone"]'::jsonb),
  1, 'only the field that moved is recorded'
);

-- 7. Deactivation and restoration ----------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.deactivate_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000006'
    )$$,
  '23514', null, 'a pending invitee is cancelled, not deactivated'
);

-- private.employee_seats_used is locked down to nobody, service_role included, so the seat readings below
-- are taken as postgres. What is being checked is the seat arithmetic, not who may ask.
set local role postgres;
insert into seat_counts (label, value)
select 'before_deactivation', private.employee_seats_used('e1000000-0000-0000-0000-000000000001');
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.deactivate_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  'an active member can be deactivated'
);
insert into tap_results (line) select ok(
  (select status = 'deactivated' and deactivated_at is not null
      and status_changed_by = 'e0000000-0000-0000-0000-000000000001'
      and access_revision = 6
    from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  'deactivation is recorded on the membership, and revokes the open session''s authority'
);
insert into tap_results (line) select is(
  (select summary from public.organization_member_access_events
    where event_type = 'member.deactivated'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  '{"previous_status": "active"}'::jsonb, 'the history remembers what they were before'
);
set local role postgres;
insert into tap_results (line) select is(
  private.employee_seats_used('e1000000-0000-0000-0000-000000000001'),
  (select value - 1 from seat_counts where label = 'before_deactivation'),
  'the seat is free again'
);
set local role service_role;
insert into tap_results (line) select throws_ok(
  $$select public.deactivate_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  '23514', null, 'deactivating somebody twice is refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'office', false, 6
    )$$,
  '23514', null, 'a deactivated member''s access is not edited in place'
);
insert into tap_results (line) select throws_ok(
  $$select public.update_team_member_profile(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      null, null, 'Estimator', '#3366FF', 3
    )$$,
  '23514', null, 'and neither are their details'
);

insert into tap_results (line) select lives_ok(
  $$select public.restore_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  'a deactivated member can be brought back'
);
insert into tap_results (line) select ok(
  (select status = 'active' and deactivated_at is null
    from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000004'),
  'they are active again'
);
insert into tap_results (line) select is(
  (select summary from public.organization_member_access_events
    where event_type = 'member.restored'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000004'),
  '{"restored_role": "sales"}'::jsonb, 'they come back on the role they had'
);
set local role postgres;
insert into tap_results (line) select is(
  private.employee_seats_used('e1000000-0000-0000-0000-000000000001'),
  (select value from seat_counts where label = 'before_deactivation'),
  'and their seat is taken again'
);
set local role service_role;
insert into tap_results (line) select throws_ok(
  $$select public.restore_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  '23514', null, 'restoring somebody who is already active is refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.restore_team_member(
      'e1000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000008',
      'e0000000-0000-0000-0000-000000000009'
    )$$,
  '23514', null, 'a restore cannot push a company past its seat limit'
);

-- 8. Permanent removal ----------------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000007'
    )$$,
  '23514', null, 'only the owner may permanently remove somebody'
);
insert into tap_results (line) select throws_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  '23514', null, 'removal only follows deactivation'
);
insert into tap_results (line) select throws_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000010'
    )$$,
  '23514', null, 'an administrator is demoted before they are removed'
);

insert into tap_results (line) select lives_ok(
  $$select public.deactivate_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005'
    )$$,
  'the person to be removed is deactivated first'
);
insert into tap_results (line) select lives_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005'
    )$$,
  'the owner permanently removes a deactivated member'
);
insert into tap_results (line) select ok(
  (select status = 'removed' and removed_at is not null and identity_cleanup_state = 'required'
    from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000005'),
  'the membership becomes a tombstone with the Auth cleanup still to do'
);
insert into tap_results (line) select is(
  (select display_name_at_removal from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000005'),
  'Fiona Field', 'the name is kept, so their old work still says who did it'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_permission_overrides
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000005'),
  0, 'their individual adjustments go with their access'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.removed'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000005'),
  1, 'the removal is in the team history'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where subject_user_id = 'e0000000-0000-0000-0000-000000000005'
      and event_type = 'member.role_changed'),
  1, 'and everything that happened before it is still there'
);

insert into tap_results (line) select lives_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000007'
    )$$,
  'somebody with no name on their profile can still be removed'
);
insert into tap_results (line) select is(
  (select display_name_at_removal from public.organization_members
    where organization_id = 'e1000000-0000-0000-0000-000000000001'
      and user_id = 'e0000000-0000-0000-0000-000000000007'),
  'Removed team member', 'and they get a plain label rather than a blank one'
);

insert into tap_results (line) select throws_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005'
    )$$,
  '23514', null, 'removing the same person twice is refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.restore_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005'
    )$$,
  '23514', null, 'a removed person is invited again, never restored'
);
insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'office', false, 4
    )$$,
  '23514', null, 'and their access cannot be edited afterwards'
);

-- 9. The identity cleanup ledger --------------------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004',
      'ban_applied'
    )$$,
  '23514', null, 'somebody still on the team has no identity cleanup to record'
);
insert into tap_results (line) select throws_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'required'
    )$$,
  '23514', null, 'the worker records steps it finished, not the one it was given'
);
insert into tap_results (line) select throws_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'nearly_done'
    )$$,
  '23514', null, 'an invented cleanup step is refused'
);

insert into tap_results (line) select lives_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'email_released'
    )$$,
  'the worker records how far it got'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.identity_revoked'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000005'),
  0, 'a half-finished cleanup is not history yet'
);
insert into tap_results (line) select throws_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'ban_applied'
    )$$,
  '23514', null, 'the ledger only ever moves forwards'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'done'
    )$$,
  'the cleanup finishes'
);
insert into tap_results (line) select ok(
  (select actor_kind = 'system' and actor_user_id is null
    from public.organization_member_access_events
    where event_type = 'member.identity_revoked'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000005'),
  'nobody did it: the cleanup is the system''s own work'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_member_identity_revoked(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000005',
      'done'
    )$$,
  'a worker that retries the last step is not an error'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'member.identity_revoked'
      and subject_user_id = 'e0000000-0000-0000-0000-000000000005'),
  1, 'and the history says it happened once'
);

-- 10. A browser session holds none of this ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000002', true);

insert into tap_results (line) select throws_ok(
  $$select public.change_team_member_role(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000004',
      'office', false, 5
    )$$,
  '42501', null, 'a signed-in administrator cannot call the role command from the browser'
);
insert into tap_results (line) select throws_ok(
  $$select public.remove_team_member(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  '42501', null, 'nor the removal command'
);
insert into tap_results (line) select throws_ok(
  $$select private.authorize_team_member_command(
      'e1000000-0000-0000-0000-000000000001',
      'e0000000-0000-0000-0000-000000000002',
      'e0000000-0000-0000-0000-000000000004'
    )$$,
  '42501', null, 'and cannot reach the helper that decides who may act on whom'
);

set local role postgres;

select * from finish();

select line from tap_results where line like 'not ok%' order by id;

rollback;
