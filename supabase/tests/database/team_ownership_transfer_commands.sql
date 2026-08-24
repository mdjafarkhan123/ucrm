-- Team & access, part 3A, item 5: ownership transfer and its three commands.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention `team_member_access_events.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` does not survive
-- that. The deferred single-active-owner trigger only fires at commit, and this transaction never commits,
-- so the moments below where an organization is deliberately left without an active owner are safe here --
-- what they are proving is that a *command* refuses, not what the trigger would do.
begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

-- Every assertion's TAP line is captured here so the whole run can be inspected in one final SELECT --
-- the query tool used to verify this file only returns the last statement's result set.
create temporary table tap_results (id serial primary key, line text);
-- Transfer ids are handed back by the commands, so they are stashed as they are created rather than
-- guessed; the later assertions look them up by label.
create temporary table transfer_ids (label text primary key, id uuid);
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
grant insert, select on transfer_ids to service_role, authenticated;

-- 1. Shape and grants --------------------------------------------------------------------------------

insert into tap_results (line) select has_table(
  'public', 'organization_ownership_transfers', 'the ownership transfer table exists'
);
insert into tap_results (line) select has_function(
  'public', 'request_ownership_transfer', 'the request command exists'
);
insert into tap_results (line) select has_function(
  'public', 'accept_ownership_transfer', 'the accept command exists'
);
insert into tap_results (line) select has_function(
  'public', 'close_ownership_transfer', 'the close command exists'
);

insert into tap_results (line) select ok(
  (select relrowsecurity from pg_class where oid = 'public.organization_ownership_transfers'::regclass),
  'row level security is on for ownership transfers'
);

insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'organization_ownership_transfers'
      and grantee in ('anon', 'authenticated')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0, 'no browser session may write an ownership transfer'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'organization_ownership_transfers'
      and grantee = 'authenticated' and privilege_type = 'SELECT'),
  1, 'a team manager may read transfers, subject to the policy'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'organization_ownership_transfers'
      and grantee = 'anon'),
  0, 'a signed-out caller holds no grant at all on ownership transfers'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and table_name = 'organization_ownership_transfers'
      and grantee = 'service_role' and privilege_type in ('DELETE', 'TRUNCATE')),
  0, 'a settled transfer is history: even the commands cannot erase one'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name in (
        'request_ownership_transfer', 'accept_ownership_transfer', 'close_ownership_transfer'
      )
      and grantee in ('anon', 'authenticated')),
  0, 'no browser session may call an ownership command directly'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name in (
        'request_ownership_transfer', 'accept_ownership_transfer', 'close_ownership_transfer'
      )
      and grantee = 'service_role' and privilege_type = 'EXECUTE'),
  3, 'all three commands are callable by the server only'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'transfer-owner@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'transfer-admin-one@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'transfer-admin-two@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'transfer-field@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'transfer-admin-off@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'other-transfer-owner@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'other-transfer-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c1000000-0000-0000-0000-000000000001', 'Transfer Test Co', 'transfer-test-co', 'active'),
  ('c1000000-0000-0000-0000-000000000002', 'Other Transfer Co', 'other-transfer-co', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'admin', 'active'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'admin', 'active'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'field', 'active'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'admin', 'deactivated'),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000006', 'owner', 'active'),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000007', 'admin', 'active');

set local role service_role;

-- 3. Who may ask, and who may be asked -------------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000002',
      'c0000000-0000-0000-0000-000000000003'
    )$$,
  '23514', null, 'an administrator cannot hand over ownership they do not hold'
);
insert into tap_results (line) select throws_ok(
  $$select public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000004'
    )$$,
  '23514', null, 'ownership cannot be handed to someone who is not an administrator'
);
insert into tap_results (line) select throws_ok(
  $$select public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000005'
    )$$,
  '23514', null, 'ownership cannot be handed to a deactivated administrator'
);
insert into tap_results (line) select throws_ok(
  $$select public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000007'
    )$$,
  '23514', null, 'ownership cannot be handed to an administrator at another company'
);
insert into tap_results (line) select throws_ok(
  $$select public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001'
    )$$,
  '23514', null, 'the owner cannot hand ownership to themselves'
);

insert into tap_results (line) select lives_ok(
  $$insert into transfer_ids (label, id)
    select 'declined', id from public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000002'
    )$$,
  'the owner may ask an active administrator to take over'
);

insert into tap_results (line) select is(
  (select state from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'declined')),
  'pending', 'the handover is waiting for an answer'
);
insert into tap_results (line) select ok(
  (select role from public.organization_members
     where organization_id = 'c1000000-0000-0000-0000-000000000001'
       and user_id = 'c0000000-0000-0000-0000-000000000001') = 'owner'
  and (select role from public.organization_members
     where organization_id = 'c1000000-0000-0000-0000-000000000001'
       and user_id = 'c0000000-0000-0000-0000-000000000002') = 'admin',
  'asking changes nobody''s role'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'ownership.transfer_requested'
      and subject_user_id = 'c0000000-0000-0000-0000-000000000002'
      and summary ->> 'transfer_id' = (select id::text from transfer_ids where label = 'declined')),
  1, 'the request is written to team history against the person asked'
);

insert into tap_results (line) select throws_ok(
  $$select public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000003'
    )$$,
  '23505', null, 'a second handover cannot be started while one is waiting'
);
insert into tap_results (line) select throws_ok(
  $$insert into public.organization_ownership_transfers (organization_id, from_user_id, to_user_id)
    values (
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000003'
    )$$,
  '23505', null, 'the index refuses a second pending handover even without the command'
);

-- 4. A browser session holds nothing -----------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);

insert into tap_results (line) select throws_ok(
  $$insert into public.organization_ownership_transfers (organization_id, from_user_id, to_user_id)
    values (
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000002'
    )$$,
  '42501', null, 'a signed-in administrator cannot write themselves a handover'
);
insert into tap_results (line) select throws_ok(
  $$update public.organization_ownership_transfers set state = 'accepted'$$,
  '42501', null, 'a signed-in administrator cannot accept a handover by editing the row'
);

set local role service_role;

-- 5. Ending a handover without accepting it ------------------------------------------------------------

insert into tap_results (line) select throws_ok(
  format(
    $$select public.close_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000003')$$,
    (select id from transfer_ids where label = 'declined')
  ),
  '23514', null, 'someone who is not part of the handover cannot end it'
);
insert into tap_results (line) select lives_ok(
  format(
    $$select public.close_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000002')$$,
    (select id from transfer_ids where label = 'declined')
  ),
  'the person asked may say no'
);
insert into tap_results (line) select ok(
  (select state from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'declined')) = 'declined'
  and (select resolved_by from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'declined'))
      = 'c0000000-0000-0000-0000-000000000002',
  'the recipient saying no is recorded as a decline, not a cancellation'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'ownership.transfer_declined'
      and summary ->> 'transfer_id' = (select id::text from transfer_ids where label = 'declined')),
  1, 'the decline is written to team history'
);
insert into tap_results (line) select throws_ok(
  format(
    $$select public.close_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000001')$$,
    (select id from transfer_ids where label = 'declined')
  ),
  '23514', null, 'a handover that has been answered cannot be answered again'
);
insert into tap_results (line) select ok(
  (select role from public.organization_members
     where organization_id = 'c1000000-0000-0000-0000-000000000001'
       and user_id = 'c0000000-0000-0000-0000-000000000001') = 'owner',
  'a decline leaves the owner exactly where they were'
);

insert into tap_results (line) select lives_ok(
  $$insert into transfer_ids (label, id)
    select 'cancelled', id from public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000002'
    )$$,
  'once the first handover is answered the owner may ask again'
);
insert into tap_results (line) select lives_ok(
  format(
    $$select public.close_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000001')$$,
    (select id from transfer_ids where label = 'cancelled')
  ),
  'the owner may change their mind while it is waiting'
);
insert into tap_results (line) select ok(
  (select state from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'cancelled')) = 'cancelled'
  and (select resolved_by from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'cancelled'))
      = 'c0000000-0000-0000-0000-000000000001',
  'the owner ending it is recorded as a cancellation, decided by the database'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'ownership.transfer_cancelled'
      and summary ->> 'transfer_id' = (select id::text from transfer_ids where label = 'cancelled')),
  1, 'the cancellation is written to team history'
);

-- 6. Accepting -------------------------------------------------------------------------------------------

insert into tap_results (line) select lives_ok(
  $$insert into transfer_ids (label, id)
    select 'accepted', id from public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000002'
    )$$,
  'the owner asks once more, this time for real'
);
insert into tap_results (line) select throws_ok(
  format(
    $$select public.accept_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000003')$$,
    (select id from transfer_ids where label = 'accepted')
  ),
  '23514', null, 'another administrator cannot accept a handover addressed to someone else'
);
insert into tap_results (line) select lives_ok(
  format(
    $$select public.accept_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000002')$$,
    (select id from transfer_ids where label = 'accepted')
  ),
  'the person asked takes over'
);
insert into tap_results (line) select is(
  (select role from public.organization_members
    where organization_id = 'c1000000-0000-0000-0000-000000000001'
      and user_id = 'c0000000-0000-0000-0000-000000000001'),
  'admin', 'the former owner is now an administrator'
);
insert into tap_results (line) select is(
  (select role from public.organization_members
    where organization_id = 'c1000000-0000-0000-0000-000000000001'
      and user_id = 'c0000000-0000-0000-0000-000000000002'),
  'owner', 'the person who accepted is now the owner'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_members
    where organization_id = 'c1000000-0000-0000-0000-000000000001'
      and role = 'owner' and status = 'active'),
  1, 'the company still has exactly one owner'
);
insert into tap_results (line) select ok(
  (select access_revision from public.organization_members
     where organization_id = 'c1000000-0000-0000-0000-000000000001'
       and user_id = 'c0000000-0000-0000-0000-000000000001') > 1
  and (select access_revision from public.organization_members
     where organization_id = 'c1000000-0000-0000-0000-000000000001'
       and user_id = 'c0000000-0000-0000-0000-000000000002') > 1,
  'both sides get a new access revision, so a stale editor conflicts'
);
insert into tap_results (line) select ok(
  (select state from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'accepted')) = 'accepted'
  and (select resolved_at from public.organization_ownership_transfers
    where id = (select id from transfer_ids where label = 'accepted')) is not null,
  'the handover is settled and stamped'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_access_events
    where event_type = 'ownership.transfer_accepted'
      and summary ->> 'transfer_id' = (select id::text from transfer_ids where label = 'accepted')),
  1, 'the handover is written to team history'
);
insert into tap_results (line) select throws_ok(
  format(
    $$select public.accept_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000002')$$,
    (select id from transfer_ids where label = 'accepted')
  ),
  '23514', null, 'a handover cannot be accepted twice'
);

-- 7. A request that has gone stale --------------------------------------------------------------------

insert into tap_results (line) select lives_ok(
  $$insert into transfer_ids (label, id)
    select 'stale', id from public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000001',
      'c0000000-0000-0000-0000-000000000002',
      'c0000000-0000-0000-0000-000000000001'
    )$$,
  'the new owner may hand it straight back'
);

set local role postgres;
update public.organization_members
set status = 'deactivated'
where organization_id = 'c1000000-0000-0000-0000-000000000001'
  and user_id = 'c0000000-0000-0000-0000-000000000001';
set local role service_role;

insert into tap_results (line) select throws_ok(
  format(
    $$select public.accept_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000001')$$,
    (select id from transfer_ids where label = 'stale')
  ),
  '23514', null, 'someone deactivated since the request was made cannot accept it'
);

set local role postgres;
update public.organization_members
set status = 'active'
where organization_id = 'c1000000-0000-0000-0000-000000000001'
  and user_id = 'c0000000-0000-0000-0000-000000000001';
update public.organization_members
set status = 'deactivated'
where organization_id = 'c1000000-0000-0000-0000-000000000001'
  and user_id = 'c0000000-0000-0000-0000-000000000002';
set local role service_role;

insert into tap_results (line) select throws_ok(
  format(
    $$select public.accept_ownership_transfer(%L, 'c0000000-0000-0000-0000-000000000001')$$,
    (select id from transfer_ids where label = 'stale')
  ),
  '23514', null, 'a handover offered by someone who is no longer the owner cannot be cashed in'
);

-- 8. Tenant isolation --------------------------------------------------------------------------------------

set local role postgres;
update public.organization_members
set status = 'active'
where organization_id = 'c1000000-0000-0000-0000-000000000001'
  and user_id = 'c0000000-0000-0000-0000-000000000002';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$insert into transfer_ids (label, id)
    select 'other-company', id from public.request_ownership_transfer(
      'c1000000-0000-0000-0000-000000000002',
      'c0000000-0000-0000-0000-000000000006',
      'c0000000-0000-0000-0000-000000000007'
    )$$,
  'another company runs its own handover'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);

insert into tap_results (line) select is(
  (select count(*)::int from public.organization_ownership_transfers),
  4, 'a team manager sees their own company''s handovers and nothing else'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_ownership_transfers
    where organization_id = 'c1000000-0000-0000-0000-000000000002'),
  0, 'another company''s handovers are invisible'
);

select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000004', true);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_ownership_transfers),
  0, 'a teammate without team management sees no handovers at all'
);

set local role postgres;

-- 9. The indexes ---------------------------------------------------------------------------------------

insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_ownership_transfers_one_pending_idx'
  ),
  'one pending handover per company is proven by an index, not only by a command'
);
insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_ownership_transfers_organization_requested_idx'
  ),
  'the company''s handover history has its index'
);
insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_ownership_transfers_to_user_idx'
  ),
  'handovers waiting for one person have their index'
);
insert into tap_results (line) select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'organization_ownership_transfers_resolved_by_idx'
  ),
  'deleting an Auth account will not scan every settled handover'
);

select * from finish();

select line from tap_results where line like 'not ok%' order by id;

rollback;
