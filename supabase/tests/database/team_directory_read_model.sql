-- Part 3C: one tenant-protected, searchable, keyset-paged Team directory.
begin;

create extension if not exists pgtap with schema extensions;
select plan(29);

create temporary table tap_results (id serial primary key, line text);
do $grant$
begin
  execute format('grant usage on schema %I to authenticated',
    (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end;
$grant$;
grant insert, select on tap_results to authenticated;
grant usage on sequence tap_results_id_seq to authenticated;

insert into tap_results (line) select has_function(
  'public', 'list_team_directory',
  array['uuid', 'text', 'text', 'integer', 'integer', 'timestamp with time zone', 'uuid'],
  'the bounded Team directory function exists'
);
insert into tap_results (line) select function_privs_are(
  'public', 'list_team_directory',
  array['uuid', 'text', 'text', 'integer', 'integer', 'timestamp with time zone', 'uuid'],
  'authenticated', array['EXECUTE'], 'only authenticated sessions receive the read grant'
);
insert into tap_results (line) select function_privs_are(
  'public', 'list_team_directory',
  array['uuid', 'text', 'text', 'integer', 'integer', 'timestamp with time zone', 'uuid'],
  'anon', array[]::text[], 'anonymous sessions cannot call the directory'
);
insert into tap_results (line) select function_privs_are(
  'public', 'list_team_directory',
  array['uuid', 'text', 'text', 'integer', 'integer', 'timestamp with time zone', 'uuid'],
  'service_role', array[]::text[], 'the service role does not bypass the signed-in read path'
);
insert into tap_results (line) select has_function(
  'public', 'get_team_member_detail', array['uuid', 'uuid'],
  'the exact Team member detail function exists'
);
insert into tap_results (line) select function_privs_are(
  'public', 'get_team_member_detail', array['uuid', 'uuid'],
  'authenticated', array['EXECUTE'], 'only authenticated sessions receive the member detail read grant'
);
insert into tap_results (line) select function_privs_are(
  'public', 'get_team_member_detail', array['uuid', 'uuid'],
  'anon', array[]::text[], 'anonymous sessions cannot call the member detail read'
);
insert into tap_results (line) select function_privs_are(
  'public', 'get_team_member_detail', array['uuid', 'uuid'],
  'service_role', array[]::text[], 'the service role does not bypass the signed-in member detail read path'
);

set local role postgres;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_user_meta_data)
values
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner-directory@example.test', 'test', now(), now(), now(),
   '{"full_name":"Olive Owner"}'::jsonb),
  ('f0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'field-directory@example.test', 'test', now(), now(), now(),
   '{"full_name":"Fiona Field"}'::jsonb),
  ('f0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pending-directory@example.test', 'test', now(), now(), now(), '{}'),
  ('f0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'off-directory@example.test', 'test', now(), now(), now(),
   '{"full_name":"Della Deactivated"}'::jsonb),
  ('f0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'other-directory@example.test', 'test', now(), now(), now(),
   '{"full_name":"Other Owner"}'::jsonb),
  ('f0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ordinary-directory@example.test', 'test', now(), now(), now(),
   '{"full_name":"Ollie Office"}'::jsonb);

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f1000000-0000-0000-0000-000000000001', 'Directory Co', 'directory-co', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'Other Directory Co', 'other-directory-co', 'active');

insert into public.organization_members
  (organization_id, user_id, role, status, job_title, work_phone, created_at)
values
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001',
   'owner', 'active', 'Owner', null, '2026-01-01T00:00:00Z'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002',
   'field', 'active', 'Crew lead', '+1 555 1000', '2026-01-02T00:00:00Z'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003',
   'sales', 'pending', null, null, '2026-01-03T00:00:00Z'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000004',
   'office', 'deactivated', null, null, '2026-01-04T00:00:00Z'),
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000006',
   'office', 'active', null, null, '2026-01-05T00:00:00Z'),
  ('f1000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000005',
   'owner', 'active', null, null, '2026-01-01T00:00:00Z');

insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values ('f1000000-0000-0000-0000-000000000001',
        'f0000000-0000-0000-0000-000000000006', 'team.manage', 'deny');

insert into public.organization_member_invitations
  (id, organization_id, invited_email, role, state, invited_user_id, invited_by, token_hash,
   last_sent_at, last_delivery_error, expires_at)
values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
   'pending-directory@example.test', 'sales', 'invited',
   'f0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000001',
   repeat('a', 64), now(), 'mail refused', now() + interval '7 days');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

insert into tap_results (line) select is(
  jsonb_array_length(public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001') -> 'members'),
  5, 'an owner sees all manageable member states in their organization'
);
insert into tap_results (line) select is(
  public.list_team_directory('f1000000-0000-0000-0000-000000000001') ->> 'seats_used',
  '4', 'pending plus active memberships consume seats'
);
insert into tap_results (line) select is(
  (public.list_team_directory('f1000000-0000-0000-0000-000000000001')
    #>> '{members,0,status}'), 'pending', 'Pending is the first directory group'
);
insert into tap_results (line) select is(
  (public.list_team_directory('f1000000-0000-0000-0000-000000000001')
    #>> '{members,0,invitation,email}'), 'pending-directory@example.test',
  'a Pending row carries only its current invitation contact'
);
insert into tap_results (line) select is(
  (public.list_team_directory('f1000000-0000-0000-0000-000000000001')
    #>> '{members,0,invitation,delivery_failed}'), 'true',
  'delivery failure is visible without exposing the provider error text'
);
insert into tap_results (line) select ok(
  position('mail refused' in
    public.list_team_directory('f1000000-0000-0000-0000-000000000001')::text) = 0,
  'the directory never returns private delivery error detail'
);
insert into tap_results (line) select is(
  jsonb_array_length(public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001', 'active') -> 'members'),
  3, 'the state filter is applied in the database'
);
insert into tap_results (line) select is(
  jsonb_array_length(public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001', null, 'crew LEAD') -> 'members'),
  1, 'search is case-insensitive across business profile fields'
);
insert into tap_results (line) select is(
  jsonb_array_length(public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001', null, 'pending-directory@') -> 'members'),
  1, 'search includes the Pending invitation email'
);
insert into tap_results (line) select is(
  jsonb_array_length(public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001', null, null, 2) -> 'members'),
  2, 'the requested page is bounded'
);
insert into tap_results (line) select isnt(
  public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001', null, null, 2) -> 'next_cursor',
  null::jsonb, 'a full page reports the exact next cursor'
);
insert into tap_results (line) select is(
  jsonb_array_length(public.list_team_directory(
    'f1000000-0000-0000-0000-000000000001', null, null, 2,
    (public.list_team_directory('f1000000-0000-0000-0000-000000000001', null, null, 2)
      #>> '{next_cursor,status_order}')::integer,
    (public.list_team_directory('f1000000-0000-0000-0000-000000000001', null, null, 2)
      #>> '{next_cursor,created_at}')::timestamptz,
    (public.list_team_directory('f1000000-0000-0000-0000-000000000001', null, null, 2)
      #>> '{next_cursor,user_id}')::uuid) -> 'members'),
  2, 'the cursor advances without OFFSET'
);
insert into tap_results (line) select is(
  public.get_team_member_detail(
    'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002'
  ) ->> 'display_name', 'Fiona Field', 'the member detail returns the person profile'
);
insert into tap_results (line) select is(
  public.get_team_member_detail(
    'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003'
  ) #>> '{invitation,email}', 'pending-directory@example.test',
  'the Pending detail returns its invitation contact'
);
insert into tap_results (line) select ok(
  position('mail refused' in public.get_team_member_detail(
    'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003'
  )::text) = 0, 'the member detail never returns private delivery error detail'
);

insert into tap_results (line) select throws_ok(
  $$select public.list_team_directory('f1000000-0000-0000-0000-000000000001', 'removed')$$,
  '22023', null, 'removed tombstones cannot become a management filter'
);
insert into tap_results (line) select throws_ok(
  $$select public.list_team_directory('f1000000-0000-0000-0000-000000000001', null, null, 51)$$,
  '22023', null, 'the database enforces the maximum page size'
);

select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-0000-0000-000000000006","role":"authenticated"}', true);
insert into tap_results (line) select throws_ok(
  $$select public.list_team_directory('f1000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a member whose Team permission is denied cannot call the directory'
);

select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-0000-0000-000000000005","role":"authenticated"}', true);
insert into tap_results (line) select throws_ok(
  $$select public.list_team_directory('f1000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'a manager from another organization cannot cross the tenant boundary'
);
insert into tap_results (line) select throws_ok(
  $$select public.get_team_member_detail(
    'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002'
  )$$,
  '42501', null, 'a manager from another organization cannot read a member detail'
);

select set_config('request.jwt.claims',
  '{"sub":"f0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
insert into tap_results (line) select throws_ok(
  $$select public.get_team_member_detail(
    'f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000005'
  )$$,
  'P0002', null, 'a member from another organization is not exposed as a detail record'
);

select * from finish();
select line from tap_results order by id;
rollback;
