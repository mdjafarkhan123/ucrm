-- Team & access, part 3A, item 4: the team history table and its shape allow-list.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention `quotes_pricing_foundation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` does not survive
-- that. The deferred single-active-owner trigger never fires here because the transaction always rolls back
-- before commit, so fixtures skip creating an 'owner' member -- same as `contractor_settings_business.sql`.
begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

-- Every assertion's TAP line is captured here so the whole run can be inspected in one final SELECT --
-- the query tool used to verify this file only returns the last statement's result set.
create temporary table tap_results (id serial primary key, line text);
-- The temp schema's real name is per-session, so the grant has to be built at run time. Without it a
-- non-owner role cannot record its own TAP lines.
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

-- 1. Shape and grants --------------------------------------------------------------------------------

insert into tap_results (line) select has_table(
  'public', 'member_access_event_shapes', 'the event shape allow-list exists'
);
insert into tap_results (line) select has_table(
  'public', 'organization_member_access_events', 'the team history table exists'
);
insert into tap_results (line) select has_function(
  'private', 'enforce_member_access_event_shape', 'the allow-list trigger function exists'
);
insert into tap_results (line) select has_function(
  'private', 'member_access_summary_value_fits', 'the value-kind checker exists'
);
insert into tap_results (line) select has_function(
  'private', 'prevent_member_access_event_mutation', 'the immutability guard exists'
);

insert into tap_results (line) select ok(
  (select relrowsecurity from pg_class where oid = 'public.organization_member_access_events'::regclass),
  'row level security is on for team history'
);
insert into tap_results (line) select ok(
  (select relrowsecurity from pg_class where oid = 'public.member_access_event_shapes'::regclass),
  'row level security is on for the allow-list'
);

insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('organization_member_access_events', 'member_access_event_shapes')
      and grantee in ('anon', 'authenticated')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0, 'no browser session may write team history or its allow-list'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'organization_member_access_events'
      and grantee = 'authenticated' and privilege_type = 'SELECT'),
  1, 'a signed-in teammate may read team history, subject to the policy'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'organization_member_access_events'
      and grantee = 'anon'),
  0, 'a signed-out caller holds no grant at all on team history'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'private'
      and grantee in ('anon', 'authenticated', 'service_role')
      and routine_name in (
        'enforce_member_access_event_shape', 'member_access_summary_value_fits',
        'prevent_member_access_event_mutation', 'member_access_summary_kinds_are_known',
        'member_access_required_keys_are_allowed'
      )),
  0, 'every allow-list helper is unreachable by client-facing roles'
);

-- The seeded vocabulary is the deliverable, so its size is asserted rather than assumed.
insert into tap_results (line) select is(
  (select count(*)::int from public.member_access_event_shapes), 16,
  'the full Part 3 event vocabulary is seeded'
);
insert into tap_results (line) select is(
  (select subject_kind from public.member_access_event_shapes where event_type = 'member.role_changed'),
  'member', 'a role change is about a member'
);
insert into tap_results (line) select is(
  (select subject_kind from public.member_access_event_shapes where event_type = 'invitation.sent'),
  'invitation', 'a sent invitation is about an invitation'
);

-- No shape may declare a free-text value kind. This is the rule the whole item exists to enforce, so it is
-- asserted over the seeded data as well as over the constraint.
insert into tap_results (line) select is(
  (select count(*)::int
    from public.member_access_event_shapes as shape,
         lateral jsonb_each_text(shape.summary_keys) as entry(summary_key, value_kind)
    where entry.value_kind not in (
      'role', 'member_status', 'permission_key_list', 'profile_field_list', 'id'
    )),
  0, 'no seeded shape allows a value kind outside the five closed vocabularies'
);

set local role postgres;
insert into tap_results (line) select throws_ok(
  $$insert into public.member_access_event_shapes (event_type, subject_kind, summary_keys)
    values ('member.note_added', 'member', '{"note": "text"}'::jsonb)$$,
  '23514', null, 'a shape cannot invent a free-text value kind'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.member_access_event_shapes (event_type, subject_kind, summary_keys, required_summary_keys)
    values ('member.odd', 'member', '{"role": "role"}'::jsonb, array['reason'])$$,
  '23514', null, 'a shape cannot require a key it does not allow'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.member_access_event_shapes (event_type, subject_kind)
    values ('Member Removed', 'member')$$,
  '23514', null, 'an event type must be a lowercase dotted name'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'history-admin@example.test', 'test', now(), now(), now()),
  ('b0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'history-field@example.test', 'test', now(), now(), now()),
  ('b0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'other-org-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b1000000-0000-0000-0000-000000000001', 'History Test Co', 'history-test-co', 'active'),
  ('b1000000-0000-0000-0000-000000000002', 'Other History Co', 'other-history-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'admin'),
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'field'),
  ('b1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000003', 'admin');

insert into public.organization_member_invitations (id, organization_id, invited_email, role, state)
values (
  'b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
  'newcomer@example.test', 'office', 'reserving'
);

set local role service_role;

-- 3. What the allow-list accepts ------------------------------------------------------------------------

insert into tap_results (line) select lives_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.role_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"previous_role": "field", "new_role": "office"}'::jsonb
    )$$,
  'a role change with both roles is recorded'
);
insert into tap_results (line) select lives_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'invitation.sent', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
      '{"role": "office"}'::jsonb
    )$$,
  'a sent invitation is recorded against the invitation row'
);
insert into tap_results (line) select lives_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, subject_invitation_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'invitation.expired', 'system',
      'b2000000-0000-0000-0000-000000000001'
    )$$,
  'an automatic sweep records an event with no actor'
);
insert into tap_results (line) select lives_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.permissions_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"added_permissions": ["quotes.view", "quotes.edit"], "removed_permissions": []}'::jsonb
    )$$,
  'a permission change records real permission keys'
);
insert into tap_results (line) select lives_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.profile_updated', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"changed_fields": ["job_title", "work_phone"]}'::jsonb
    )$$,
  'a profile update records which fields changed, not their values'
);
insert into tap_results (line) select lives_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.removed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002'
    )$$,
  'a permanent removal is recorded with no summary at all'
);

-- 4. What the allow-list refuses -- the point of the whole item ------------------------------------------

insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.removed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"email": "sam@example.test"}'::jsonb
    )$$,
  '23514', null, 'an email cannot be smuggled into team history'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.removed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"full_name": "Sam Taylor"}'::jsonb
    )$$,
  '23514', null, 'a person''s name cannot be smuggled into team history'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.role_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"previous_role": "field", "new_role": "Sam Taylor"}'::jsonb
    )$$,
  '23514', null, 'an allowed key still refuses a value outside its vocabulary'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.role_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"previous_role": "field"}'::jsonb
    )$$,
  '23514', null, 'a required key cannot be left out'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.permissions_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"added_permissions": ["quotes.view", "made.up.key"]}'::jsonb
    )$$,
  '23514', null, 'a permission list cannot name a permission that does not exist'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.profile_updated', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"changed_fields": ["salary"]}'::jsonb
    )$$,
  '23514', null, 'a changed-field list cannot name a field the profile does not have'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.permissions_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"added_permissions": "quotes.view"}'::jsonb
    )$$,
  '23514', null, 'a list-valued key refuses a bare string'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.invented', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002'
    )$$,
  '23514', null, 'an event type with no shape is refused before the foreign key even runs'
);

-- 5. Subject and actor must match the shape --------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.role_changed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
      '{"previous_role": "field", "new_role": "office"}'::jsonb
    )$$,
  '23514', null, 'a member event cannot point at an invitation instead'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary)
    values (
      'b1000000-0000-0000-0000-000000000001', 'invitation.sent', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      '{"role": "office"}'::jsonb
    )$$,
  '23514', null, 'an invitation event cannot point at a member instead'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.removed', 'member', null,
      'b0000000-0000-0000-0000-000000000002'
    )$$,
  '23514', null, 'a member-made change must name the teammate who made it'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_invitation_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'invitation.expired', 'system',
      'b0000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'a system event cannot claim a human actor'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id, subject_invitation_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.removed', 'member',
      'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002',
      'b2000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'an event cannot be about two things at once'
);

-- 6. History is written once ------------------------------------------------------------------------------

-- Not even the commands that write history may edit it: service_role holds insert and select only, so the
-- grant refuses first. Running the next two as the owner is what puts the trigger itself on trial.
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('organization_member_access_events', 'member_access_event_shapes')
      and grantee = 'service_role' and privilege_type in ('UPDATE', 'DELETE', 'TRUNCATE')),
  0, 'the commands that write history hold no grant to change it'
);

set local role postgres;

insert into tap_results (line) select throws_ok(
  $$update public.organization_member_access_events
    set summary = '{"previous_role": "office", "new_role": "field"}'::jsonb
    where event_type = 'member.role_changed'$$,
  '23514', null, 'a recorded history line cannot be edited afterwards'
);
insert into tap_results (line) select throws_ok(
  $$delete from public.organization_member_access_events where event_type = 'member.role_changed'$$,
  '23514', null, 'a recorded history line cannot be deleted afterwards'
);

-- 7. Tenant isolation --------------------------------------------------------------------------------------

insert into public.organization_member_access_events
  (organization_id, event_type, actor_kind, actor_user_id, subject_user_id)
values (
  'b1000000-0000-0000-0000-000000000002', 'member.removed', 'member',
  'b0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000003'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events),
  6, 'a team manager sees their own organization''s history and nothing else'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where organization_id = 'b1000000-0000-0000-0000-000000000002'),
  0, 'another organization''s history is invisible'
);
insert into tap_results (line) select ok(
  (select count(*) from public.member_access_event_shapes) = 16,
  'the allow-list itself is readable by any signed-in user'
);

select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events),
  0, 'a teammate without team.manage sees no history at all'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_member_access_events
    (organization_id, event_type, actor_kind, actor_user_id, subject_user_id)
    values (
      'b1000000-0000-0000-0000-000000000001', 'member.removed', 'member',
      'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001'
    )$$,
  '42501', null, 'a browser session cannot write its own history line'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.member_access_event_shapes (event_type, subject_kind)
    values ('member.smuggled', 'member')$$,
  '42501', null, 'a browser session cannot add its own event shape'
);

set local role postgres;

-- 8. The indexes the history screens need -----------------------------------------------------------------

insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_member_access_events_organization_created_idx'
  ),
  'the organization history list has its index'
);
insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_member_access_events_subject_user_idx'
  ),
  'one member''s history has its index'
);
-- Both auth.users foreign keys stay index-backed, so deleting an Auth account never scans this table. The
-- subject index above leads with subject_user_id for the same reason -- see 20260828090200's comments.
insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_member_access_events_actor_user_idx'
  ),
  'the actor foreign key has its index'
);

select * from finish();
select line from tap_results where line like 'not ok%' order by id;
rollback;
