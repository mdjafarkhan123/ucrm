-- Contractor Settings 3B, item 1: invitation adjustments, global email ownership, and leased Auth cleanup.
-- Run as one transaction. The final result set contains only failures; no rows means every assertion passed.
begin;

create extension if not exists pgtap with schema extensions;

select plan(46);

create temporary table tap_results (id serial primary key, line text);
grant insert, select on tap_results to service_role;
grant usage on sequence tap_results_id_seq to service_role;

-- 1. Persisted shape, indexes, and the single command surface --------------------------------------------

insert into tap_results (line) select has_column(
  'public', 'organization_member_invitations', 'requested_permission_overrides',
  'an invitation persists its validated permission adjustments'
);
insert into tap_results (line) select has_column(
  'public', 'organization_member_invitations', 'reconciliation_nonce',
  'an invitation records its reconciliation lease nonce'
);
insert into tap_results (line) select has_column(
  'public', 'organization_member_invitations', 'reconciliation_lease_expires_at',
  'an invitation records its reconciliation lease expiry'
);
insert into tap_results (line) select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.organization_member_invitations'::regclass
      and conname = 'organization_member_invitations_requested_overrides_array_check'),
  1, 'the stored adjustments must remain a JSON array'
);
insert into tap_results (line) select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.organization_member_invitations'::regclass
      and conname = 'organization_member_invitations_reconciliation_lease_pair_check'),
  1, 'a cleanup lease always has both its nonce and expiry'
);
insert into tap_results (line) select matches(
  (select indexdef from pg_indexes where schemaname = 'public'
    and indexname = 'organization_member_invitations_pending_email_idx'),
  'UNIQUE INDEX.*lower\(invited_email\).*state = ANY.*reserving.*invited.*accepting',
  'one normalized email is globally unique while an invitation is open'
);
insert into tap_results (line) select matches(
  (select indexdef from pg_indexes where schemaname = 'public'
    and indexname = 'organization_member_invitations_cleanup_queue_idx'),
  'COALESCE\(reconciliation_lease_expires_at.*created_at.*id.*identity_cleanup_state = ''required''',
  'the cleanup queue index matches its lease and age order'
);
insert into tap_results (line) select has_index(
  'public', 'organization_member_invitations', 'organization_member_invitations_invited_by_idx',
  'Auth deletion can check the invitation creator FK without scanning every invitation'
);
insert into tap_results (line) select has_index(
  'public', 'organization_member_invitations', 'organization_member_invitations_cancelled_by_idx',
  'Auth deletion can check the invitation canceller FK without scanning every invitation'
);
insert into tap_results (line) select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'begin_team_invitation'),
  1, 'begin_team_invitation has one unambiguous signature'
);
insert into tap_results (line) select has_function(
  'public', 'claim_team_invitation_reconciliation', 'the bounded reconciliation claim exists'
);
insert into tap_results (line) select has_function(
  'public', 'prepare_team_invitation_identity_cleanup', 'pending membership cleanup has a leased preparation step'
);
insert into tap_results (line) select has_function(
  'public', 'settle_team_invitation_identity_cleanup', 'successful Auth cleanup has a final settlement step'
);
insert into tap_results (line) select has_function(
  'public', 'release_team_invitation_reconciliation', 'uncertain Auth cleanup can release its worker lease'
);
insert into tap_results (line) select has_function(
  'public', 'find_team_invitation_auth_receipt', 'reconciliation has one narrow Auth receipt lookup'
);

-- 2. Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, created_at, updated_at
)
values
  ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'manager-one@example.test', 'test', now(), '{}'::jsonb, now(), now()),
  ('b0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'manager-two@example.test', 'test', now(), '{}'::jsonb, now(), now()),
  ('b0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'worker-target@example.test', 'test', now(),
   '{"team_invitation_identity_for":"b3000000-0000-0000-0000-000000000001"}'::jsonb, now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b1000000-0000-0000-0000-000000000001', 'Invitation Orchestration One', 'invite-orchestration-one', 'active'),
  ('b1000000-0000-0000-0000-000000000002', 'Invitation Orchestration Two', 'invite-orchestration-two', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'admin'),
  ('b1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'admin');

insert into public.organization_limit_overrides
  (organization_id, limit_key, limit_value, is_unlimited, limit_state, starts_at)
values
  ('b1000000-0000-0000-0000-000000000001', 'employee_seats', null, true, 'unlimited', '2026-01-01T00:00:00Z'),
  ('b1000000-0000-0000-0000-000000000002', 'employee_seats', null, true, 'unlimited', '2026-01-01T00:00:00Z');

set local role service_role;

-- 3. Adjustment validation and the global email race ------------------------------------------------------

insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000001', 'bad-null@example.test', 'field', 'b0000000-0000-0000-0000-000000000001', null)$$,
  '23514', 'The permission adjustments must be a list.', 'null adjustments are refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000001', 'bad-admin@example.test', 'admin', 'b0000000-0000-0000-0000-000000000001', '[{"permission_key":"customers.view","override_state":"grant"}]'::jsonb)$$,
  '23514', 'Administrator invitations use standard administrator access.',
  'administrator invitations cannot smuggle personal adjustments'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000001', 'bad-scope@example.test', 'field', 'b0000000-0000-0000-0000-000000000001', '[{"permission_key":"customers.view","override_state":"grant","access_scope":"assigned"}]'::jsonb)$$,
  '23514', 'One of those permission adjustments is not available.', 'assigned scope stays refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000001', 'bad-key@example.test', 'field', 'b0000000-0000-0000-0000-000000000001', '[{"permission_key":"invented.permission","override_state":"grant"}]'::jsonb)$$,
  '23514', 'One of those permission adjustments is not available.', 'unknown permission keys are refused'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000001', 'bad-duplicate@example.test', 'field', 'b0000000-0000-0000-0000-000000000001', '[{"permission_key":"customers.view","override_state":"grant"},{"permission_key":"customers.view","override_state":"deny"}]'::jsonb)$$,
  '23514', 'The same permission was adjusted twice.', 'one permission cannot be adjusted twice'
);

insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation(
    'b1000000-0000-0000-0000-000000000001', '  Worker-Target@Example.Test  ', 'field',
    'b0000000-0000-0000-0000-000000000001',
    '[{"permission_key":"customers.view","override_state":"grant"},{"permission_key":"quotes.view_cost","override_state":"deny"}]'::jsonb
  )$$, 'a compatible adjusted invitation reserves normally'
);
insert into tap_results (line) select is(
  (select invited_email from public.organization_member_invitations where invited_email = 'worker-target@example.test'),
  'worker-target@example.test', 'begin normalizes the reserved email'
);
insert into tap_results (line) select is(
  (select jsonb_array_length(requested_permission_overrides) from public.organization_member_invitations
    where invited_email = 'worker-target@example.test'),
  2, 'begin persists both validated adjustments'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000002', 'WORKER-target@example.test', 'sales', 'b0000000-0000-0000-0000-000000000002', '[]'::jsonb)$$,
  '23505', null, 'another organization cannot reserve the same normalized open email'
);

-- 4. Atomic identity attachment and narrow Auth receipt ---------------------------------------------------

set local role postgres;
update public.organization_member_invitations
set id = 'b3000000-0000-0000-0000-000000000001'
where invited_email = 'worker-target@example.test';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    'b3000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001'
  )$$, 'the Auth attempt is stamped before identity attachment'
);
insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    'b3000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000001', 'worker-token-hash', now() + interval '7 days'
  )$$, 'identity and pending access attach in one transaction'
);
insert into tap_results (line) select is(
  (select status from public.organization_members where user_id = 'b0000000-0000-0000-0000-000000000003'),
  'pending', 'identity attachment creates a pending membership'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_permission_overrides
    where user_id = 'b0000000-0000-0000-0000-000000000003'),
  2, 'identity attachment copies every requested adjustment'
);
insert into tap_results (line) select is(
  (select string_agg(permission_key || ':' || override_state || ':' || access_scope, ',' order by permission_key)
   from public.organization_member_permission_overrides
   where user_id = 'b0000000-0000-0000-0000-000000000003'),
  'customers.view:grant:all,quotes.view_cost:deny:all',
  'copied adjustments keep only their approved key, state, and all-work scope'
);
insert into tap_results (line) select is(
  (select identity_invitation_id from public.find_team_invitation_auth_receipt('b3000000-0000-0000-0000-000000000001')),
  'b3000000-0000-0000-0000-000000000001', 'the receipt lookup returns the matching identity receipt'
);
insert into tap_results (line) select is(
  (select password_set_invitation_id from public.find_team_invitation_auth_receipt('b3000000-0000-0000-0000-000000000001')),
  null, 'the receipt lookup reports that no invitation password receipt exists yet'
);

-- 5. Leased reconciliation keeps the seat and email claimed until Auth deletion succeeds ------------------

set local role postgres;
update public.organization_member_invitations
set identity_cleanup_state = 'required', created_at = now() - interval '2 hours'
where id = 'b3000000-0000-0000-0000-000000000001';
set local role service_role;

insert into tap_results (line) select throws_ok(
  $$select * from public.claim_team_invitation_reconciliation('b5000000-0000-0000-0000-000000000001', 0, 300)$$,
  '23514', 'The reconciliation lease is outside its safe bounds.', 'zero-sized worker batches are refused'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.claim_team_invitation_reconciliation(
    'b5000000-0000-0000-0000-000000000001', 1, 300)),
  1, 'the worker claims one bounded cleanup row'
);
insert into tap_results (line) select is(
  (select reconciliation_nonce from public.organization_member_invitations
    where id = 'b3000000-0000-0000-0000-000000000001'),
  'b5000000-0000-0000-0000-000000000001'::uuid, 'the claim records the worker nonce'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.claim_team_invitation_reconciliation(
    'b5000000-0000-0000-0000-000000000002', 1, 300)),
  0, 'a live lease cannot be claimed by a second worker'
);
insert into tap_results (line) select throws_ok(
  $$select public.prepare_team_invitation_identity_cleanup(
    'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000099')$$,
  '40001', 'The invitation cleanup lease is no longer valid.', 'a foreign worker cannot prepare cleanup'
);
insert into tap_results (line) select lives_ok(
  $$select public.prepare_team_invitation_identity_cleanup(
    'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001')$$,
  'the leased worker removes the pending membership before Auth deletion'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_members
    where user_id = 'b0000000-0000-0000-0000-000000000003'),
  0, 'cleanup preparation removes the pending membership and its cascading adjustments'
);
insert into tap_results (line) select is(
  (select state || ':' || identity_cleanup_state from public.organization_member_invitations
    where id = 'b3000000-0000-0000-0000-000000000001'),
  'reserving:required', 'preparation withdraws the link but leaves the reservation open and cleanup-required'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000002', 'worker-target@example.test', 'sales', 'b0000000-0000-0000-0000-000000000002', '[]'::jsonb)$$,
  '23505', null, 'cleanup preparation keeps the email globally claimed'
);

set local role postgres;
delete from auth.users where id = 'b0000000-0000-0000-0000-000000000003';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.settle_team_invitation_identity_cleanup(
    'b3000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001')$$,
  'successful Auth deletion settles the leased invitation'
);
insert into tap_results (line) select is(
  (select state || ':' || identity_cleanup_state from public.organization_member_invitations
    where id = 'b3000000-0000-0000-0000-000000000001'),
  'abandoned:done', 'settlement releases the invitation only after Auth deletion'
);
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('b1000000-0000-0000-0000-000000000002', 'worker-target@example.test', 'sales', 'b0000000-0000-0000-0000-000000000002', '[]'::jsonb)$$,
  'a settled cleanup makes the email available for a fresh membership'
);

-- 6. An uncertain external result records only a bounded safe error and releases the lease -----------------

set local role postgres;
update public.organization_member_invitations
set identity_cleanup_state = 'required',
    reconciliation_nonce = 'b5000000-0000-0000-0000-000000000010',
    reconciliation_lease_expires_at = now() + interval '5 minutes'
where organization_id = 'b1000000-0000-0000-0000-000000000002'
  and invited_email = 'worker-target@example.test';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.release_team_invitation_reconciliation(
    (select id from public.organization_member_invitations
      where organization_id = 'b1000000-0000-0000-0000-000000000002'
        and invited_email = 'worker-target@example.test'),
    'b5000000-0000-0000-0000-000000000010', repeat('safe-', 80)
  )$$, 'an uncertain Auth result releases its live worker lease'
);
insert into tap_results (line) select is(
  (select char_length(identity_cleanup_error) from public.organization_member_invitations
    where organization_id = 'b1000000-0000-0000-0000-000000000002'
      and invited_email = 'worker-target@example.test'),
  240, 'the persisted cleanup error is bounded to 240 safe characters'
);
insert into tap_results (line) select is(
  (select reconciliation_nonce from public.organization_member_invitations
    where organization_id = 'b1000000-0000-0000-0000-000000000002'
      and invited_email = 'worker-target@example.test'),
  null, 'releasing reconciliation clears both lease fields'
);

select * from finish();
select line from tap_results where line like 'not ok%' order by id;
rollback;
