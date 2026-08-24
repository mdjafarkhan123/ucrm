-- Team & access, part 3A, layer 6: the invitations table's service_role primitives.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention `quotes_pricing_foundation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` does not survive
-- that. The deferred single-active-owner trigger never fires here because the transaction always rolls back
-- before commit, so fixtures skip creating an 'owner' member -- same as `contractor_settings_business.sql`.
begin;

create extension if not exists pgtap with schema extensions;

select plan(94);

-- Every assertion's TAP line is captured here so the whole run can be inspected in one final SELECT --
-- the query tool used to verify this file only returns the last statement's result set.
create temporary table tap_results (id serial primary key, line text);
grant insert, select on tap_results to service_role;
grant usage on sequence tap_results_id_seq to service_role;

-- 1. Shape and grants --------------------------------------------------------------------------------

insert into tap_results (line) select has_column(
  'public', 'organization_member_invitations', 'auth_attempt_nonce',
  'the invitations table tracks which Auth attempt is in flight'
);
insert into tap_results (line) select has_column(
  'public', 'organization_member_invitations', 'password_set_at',
  'the invitations table records the password-set receipt'
);

insert into tap_results (line) select has_function('public', 'begin_team_invitation', 'the reservation primitive exists');
insert into tap_results (line) select has_function('public', 'mark_team_invitation_auth_attempt_started', 'the Auth-attempt marker exists');
insert into tap_results (line) select has_function('public', 'attach_team_invitation_identity', 'the identity-attach primitive exists');
insert into tap_results (line) select has_function('public', 'record_team_invitation_delivery', 'the delivery-record primitive exists');
insert into tap_results (line) select has_function('public', 'claim_team_invitation', 'the claim primitive exists');
insert into tap_results (line) select has_function('public', 'record_invitation_password_set', 'the password-set primitive exists');
insert into tap_results (line) select has_function('public', 'finalize_team_invitation', 'the finalize primitive exists');
insert into tap_results (line) select has_function('public', 'resend_team_invitation', 'the resend primitive exists');
insert into tap_results (line) select has_function('public', 'cancel_team_invitation', 'the cancel primitive exists');
insert into tap_results (line) select has_function('public', 'expire_team_invitations', 'the batch expiry primitive exists');
insert into tap_results (line) select has_function('public', 'sweep_team_invitation_reservations', 'the reservation sweep primitive exists');

insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public' and grantee = 'anon'
      and routine_name in (
        'begin_team_invitation', 'mark_team_invitation_auth_attempt_started',
        'attach_team_invitation_identity', 'record_team_invitation_delivery', 'claim_team_invitation',
        'record_invitation_password_set', 'finalize_team_invitation', 'resend_team_invitation',
        'cancel_team_invitation', 'expire_team_invitations', 'sweep_team_invitation_reservations'
      )),
  0, 'a signed-out caller may run none of the invitation primitives'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public' and grantee = 'authenticated'
      and routine_name in (
        'begin_team_invitation', 'mark_team_invitation_auth_attempt_started',
        'attach_team_invitation_identity', 'record_team_invitation_delivery', 'claim_team_invitation',
        'record_invitation_password_set', 'finalize_team_invitation', 'resend_team_invitation',
        'cancel_team_invitation', 'expire_team_invitations', 'sweep_team_invitation_reservations'
      )),
  0, 'a logged-in staff member may run none of the invitation primitives directly'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public' and grantee = 'service_role'
      and routine_name in (
        'begin_team_invitation', 'mark_team_invitation_auth_attempt_started',
        'attach_team_invitation_identity', 'record_team_invitation_delivery', 'claim_team_invitation',
        'record_invitation_password_set', 'finalize_team_invitation', 'resend_team_invitation',
        'cancel_team_invitation', 'expire_team_invitations', 'sweep_team_invitation_reservations'
      )),
  11, 'service_role holds execute on every invitation primitive'
);
insert into tap_results (line) select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'private' and grantee in ('anon', 'authenticated', 'service_role')
      and routine_name in ('finalize_accepted_invitation', 'settle_expired_acceptance')),
  0, 'the shared settlement helpers are unreachable by every client-facing role'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'invite-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('a1000000-0000-0000-0000-000000000001', 'Invitation Test Co', 'invitation-test-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'admin');

insert into public.organization_limit_overrides
  (organization_id, limit_key, limit_value, is_unlimited, limit_state, starts_at)
values ('a1000000-0000-0000-0000-000000000001', 'employee_seats', null, true, 'unlimited', '2026-01-01T00:00:00Z');

set local role service_role;

-- 3. Happy path: reservation through acceptance, proving the seat handoff never double-counts or gaps ----

insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'alex@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'begin_team_invitation reserves a seat'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'alex@example.test'),
  'reserving', 'a fresh reservation starts as reserving'
);
insert into tap_results (line) select is(
  (select auth_attempt_started_at from public.organization_member_invitations where invited_email = 'alex@example.test'),
  null, 'begin_ does not stamp an Auth attempt -- mark_ does that separately'
);

set local role postgres;
-- 2 = the fixture admin's own active membership + alex's reserving invitation.
insert into tap_results (line) select is(
  private.employee_seats_used('a1000000-0000-0000-0000-000000000001'), 2,
  'a reserving invitation consumes a seat'
);
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test'),
    '11111111-0000-0000-0000-000000000001'
  )$$,
  'mark_ records that an Auth attempt is about to happen'
);
insert into tap_results (line) select isnt(
  (select auth_attempt_started_at from public.organization_member_invitations where invited_email = 'alex@example.test'),
  null, 'the Auth-attempt timestamp is now stamped'
);

insert into tap_results (line) select throws_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test'),
    'a0000000-0000-0000-0000-000000000099', '22222222-0000-0000-0000-000000000002',
    'hash-alex', now() + interval '7 days'
  )$$,
  '23514', null, 'attach_ rejects a nonce that does not match the marked attempt'
);

set local role postgres;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'alex@example.test', 'test', now(), now(), now());
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test'),
    'a0000000-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001',
    'hash-alex', now() + interval '7 days'
  )$$,
  'attach_ succeeds with the matching attempt nonce'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'alex@example.test'),
  'invited', 'the invitation is now invited'
);
insert into tap_results (line) select is(
  (select status from public.organization_members
    where organization_id = 'a1000000-0000-0000-0000-000000000001'
      and user_id = 'a0000000-0000-0000-0000-000000000002'),
  'pending', 'attach_ created the pending membership row'
);

set local role postgres;
-- Still 2 (fixture admin + alex): the handoff moved alex from a reserving invitation to a pending
-- membership without changing the total.
insert into tap_results (line) select is(
  private.employee_seats_used('a1000000-0000-0000-0000-000000000001'), 2,
  'the seat handoff from reserving to pending membership never double-counts'
);
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.record_team_invitation_delivery(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test'), true, null
  )$$,
  'record_ marks a successful delivery'
);
insert into tap_results (line) select isnt(
  (select last_sent_at from public.organization_member_invitations where invited_email = 'alex@example.test'),
  null, 'the delivery timestamp is stamped'
);

insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('wrong-hash', 'alex@example.test', '33333333-0000-0000-0000-000000000003', 900)),
  false, 'claim_ rejects a token that does not match'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-alex', 'alex@example.test', '33333333-0000-0000-0000-000000000003', 900)),
  true, 'claim_ succeeds with the right token and email'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'alex@example.test'),
  'accepting', 'a successful claim moves the invitation into accepting'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-alex', 'alex@example.test', '44444444-0000-0000-0000-000000000004', 900)),
  false, 'a second claim cannot take over a lease that is still open'
);

insert into tap_results (line) select throws_ok(
  $$select public.record_invitation_password_set(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test'),
    '99999999-0000-0000-0000-000000000099'
  )$$,
  '23514', null, 'record_password_set rejects a lease nonce that does not match'
);
insert into tap_results (line) select lives_ok(
  $$select public.record_invitation_password_set(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test'),
    '33333333-0000-0000-0000-000000000003'
  )$$,
  'record_password_set succeeds with the held lease'
);
insert into tap_results (line) select isnt(
  (select password_set_at from public.organization_member_invitations where invited_email = 'alex@example.test'),
  null, 'the password-set receipt is stamped'
);

insert into tap_results (line) select lives_ok(
  $$select public.finalize_team_invitation(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test')
  )$$,
  'finalize_ accepts the invitation'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'alex@example.test'),
  'accepted', 'the invitation is now accepted'
);
insert into tap_results (line) select is(
  (select status from public.organization_members
    where organization_id = 'a1000000-0000-0000-0000-000000000001'
      and user_id = 'a0000000-0000-0000-0000-000000000002'),
  'active', 'the membership was activated in the same transaction'
);

insert into tap_results (line) select lives_ok(
  $$select public.finalize_team_invitation(
    (select id from public.organization_member_invitations where invited_email = 'alex@example.test')
  )$$,
  'finalize_ is safe to retry after a crash'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'alex@example.test'),
  'accepted', 'a retried finalize_ stays accepted and does not error'
);

set local role postgres;
-- Still 2 (fixture admin + alex, now an active member).
insert into tap_results (line) select is(
  private.employee_seats_used('a1000000-0000-0000-0000-000000000001'), 2,
  'an accepted invitation still consumes exactly one seat, via the active membership'
);
set local role service_role;

-- 4. Cancel must not race an open acceptance lease -------------------------------------------------------

insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'blair@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'a second reservation is made for the cancel scenarios'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'blair@example.test'),
    '55555555-0000-0000-0000-000000000005'
  )$$, 'the second reservation marks its Auth attempt'
);

set local role postgres;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'blair@example.test', 'test', now(), now(), now());
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'blair@example.test'),
    'a0000000-0000-0000-0000-000000000003', '55555555-0000-0000-0000-000000000005',
    'hash-blair', now() + interval '7 days'
  )$$, 'the second reservation attaches its identity'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-blair', 'blair@example.test', '66666666-0000-0000-0000-000000000006', 900)),
  true, 'the second invitation is claimed, opening a lease'
);

insert into tap_results (line) select throws_ok(
  $$select public.cancel_team_invitation(
    (select id from public.organization_member_invitations where invited_email = 'blair@example.test'),
    'a0000000-0000-0000-0000-000000000001'
  )$$,
  '23514', null, 'cancel_ is rejected while the acceptance lease is still open'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'blair@example.test'),
  'accepting', 'the rejected cancel left the invitation exactly where it was'
);

-- Simulate the lease lapsing with no recorded outcome: the Auth call's result is unknown.
set local role postgres;
update public.organization_member_invitations
set lease_expires_at = now() - interval '1 minute'
where invited_email = 'blair@example.test';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.cancel_team_invitation(
    (select id from public.organization_member_invitations where invited_email = 'blair@example.test'),
    'a0000000-0000-0000-0000-000000000001'
  )$$, 'cancel_ resolves an expired-lease acceptance instead of erroring'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'blair@example.test'),
  'accepting', 'an ambiguous outcome is never silently cancelled'
);
insert into tap_results (line) select is(
  (select identity_cleanup_state from public.organization_member_invitations where invited_email = 'blair@example.test'),
  'required', 'an ambiguous outcome is flagged for reconciliation'
);
insert into tap_results (line) select is(
  (select status from public.organization_members
    where organization_id = 'a1000000-0000-0000-0000-000000000001'
      and user_id = 'a0000000-0000-0000-0000-000000000003'),
  'pending', 'the seat is not released while the outcome is ambiguous'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-blair', 'blair@example.test', '77777777-0000-0000-0000-000000000007', 900)),
  false, 'a flagged-for-reconciliation token can never be reclaimed'
);

-- 5. Cancel on an expired lease with a completed password receipt finalizes instead ----------------------

insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'casey@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'a third reservation is made for the finalize-on-cancel scenario'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'casey@example.test'),
    '88888888-0000-0000-0000-000000000008'
  )$$, 'the third reservation marks its Auth attempt'
);

set local role postgres;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'casey@example.test', 'test', now(), now(), now());
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'casey@example.test'),
    'a0000000-0000-0000-0000-000000000004', '88888888-0000-0000-0000-000000000008',
    'hash-casey', now() + interval '7 days'
  )$$, 'the third reservation attaches its identity'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-casey', 'casey@example.test', '99999999-0000-0000-0000-000000000010', 900)),
  true, 'the third invitation is claimed'
);
insert into tap_results (line) select lives_ok(
  $$select public.record_invitation_password_set(
    (select id from public.organization_member_invitations where invited_email = 'casey@example.test'),
    '99999999-0000-0000-0000-000000000010'
  )$$, 'the password-set receipt is recorded before the lease lapses'
);

set local role postgres;
update public.organization_member_invitations
set lease_expires_at = now() - interval '1 minute'
where invited_email = 'casey@example.test';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.cancel_team_invitation(
    (select id from public.organization_member_invitations where invited_email = 'casey@example.test'),
    'a0000000-0000-0000-0000-000000000001'
  )$$, 'cancel_ on a completed, lapsed lease finalizes instead of cancelling'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'casey@example.test'),
  'accepted', 'a completed signup is never undone by a late cancel'
);
insert into tap_results (line) select is(
  (select status from public.organization_members
    where organization_id = 'a1000000-0000-0000-0000-000000000001'
      and user_id = 'a0000000-0000-0000-0000-000000000004'),
  'active', 'the membership was activated by the finalize-on-cancel path'
);

-- 6. Batch expiry respects an open lease and defers to the same settlement rules --------------------------

-- Row D: invited, never claimed, past its own expiry -- the ordinary expiry path.
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'drew@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'a fourth reservation is made for the ordinary-expiry scenario'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'drew@example.test'),
    'aaaaaaaa-0000-0000-0000-00000000000a'
  )$$, 'the fourth reservation marks its Auth attempt'
);

set local role postgres;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'drew@example.test', 'test', now(), now(), now());
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'drew@example.test'),
    'a0000000-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a',
    'hash-drew', now() - interval '1 minute'
  )$$, 'the fourth invitation is attached already past its own expiry'
);

-- Row E: claimed, lease still open, invitation-level expiry has also passed -- must be skipped entirely.
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'ezra@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'a fifth reservation is made for the active-lease-skip scenario'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'ezra@example.test'),
    'bbbbbbbb-0000-0000-0000-00000000000b'
  )$$, 'the fifth reservation marks its Auth attempt'
);

set local role postgres;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'ezra@example.test', 'test', now(), now(), now());
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'ezra@example.test'),
    'a0000000-0000-0000-0000-000000000006', 'bbbbbbbb-0000-0000-0000-00000000000b',
    'hash-ezra', now() + interval '7 days'
  )$$, 'the fifth invitation is attached'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-ezra', 'ezra@example.test', 'cccccccc-0000-0000-0000-00000000000c', 900)),
  true, 'the fifth invitation is claimed, opening a still-open lease'
);

set local role postgres;
update public.organization_member_invitations
set expires_at = now() - interval '1 minute'
where invited_email = 'ezra@example.test';
set local role service_role;

-- Row D resolves in the same sweep: invited and past expiry. Both rows are checked against a single call --
-- a second call would find nothing left to do, so splitting them would prove nothing about Row E.
insert into tap_results (line) select is(
  (select coalesce(array_agg(expired.invited_email order by expired.invited_email), array[]::text[])
     from public.expire_team_invitations() as expired
    where expired.invited_email in ('drew@example.test', 'ezra@example.test')),
  array['drew@example.test'],
  'one sweep expires the ordinary row and leaves the still-open lease alone'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'ezra@example.test'),
  'accepting', 'a claim made before expiry keeps its lease window'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'drew@example.test'),
  'expired', 'the ordinary row is now expired'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_members
    where organization_id = 'a1000000-0000-0000-0000-000000000001'
      and user_id = 'a0000000-0000-0000-0000-000000000005'),
  0, 'expiring an invited invitation deletes its pending membership row'
);

-- Row E's lease now also lapses with no recorded outcome -- the next sweep must reconcile, not expire.
set local role postgres;
update public.organization_member_invitations
set lease_expires_at = now() - interval '1 minute'
where invited_email = 'ezra@example.test';
set local role service_role;

insert into tap_results (line) select is(
  (select count(*)::int from public.expire_team_invitations() as expired where expired.invited_email = 'ezra@example.test'),
  1, 'expire_ settles the now-lapsed lease on its next pass'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'ezra@example.test'),
  'accepting', 'an unresolved outcome is never marked expired'
);
insert into tap_results (line) select is(
  (select identity_cleanup_state from public.organization_member_invitations where invited_email = 'ezra@example.test'),
  'required', 'the lapsed, unresolved lease is flagged for reconciliation'
);

-- Row F: password confirmed before the lease and the invitation both lapse -- expire_ must finalize it.
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'faye@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'a sixth reservation is made for the finalize-on-expire scenario'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'faye@example.test'),
    'dddddddd-0000-0000-0000-00000000000d'
  )$$, 'the sixth reservation marks its Auth attempt'
);

set local role postgres;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a0000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'faye@example.test', 'test', now(), now(), now());
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    (select id from public.organization_member_invitations where invited_email = 'faye@example.test'),
    'a0000000-0000-0000-0000-000000000007', 'dddddddd-0000-0000-0000-00000000000d',
    'hash-faye', now() + interval '7 days'
  )$$, 'the sixth invitation is attached'
);
insert into tap_results (line) select is(
  (select claimed from public.claim_team_invitation('hash-faye', 'faye@example.test', 'eeeeeeee-0000-0000-0000-00000000000e', 900)),
  true, 'the sixth invitation is claimed'
);
insert into tap_results (line) select lives_ok(
  $$select public.record_invitation_password_set(
    (select id from public.organization_member_invitations where invited_email = 'faye@example.test'),
    'eeeeeeee-0000-0000-0000-00000000000e'
  )$$, 'the sixth invitation records a completed password-set receipt'
);

set local role postgres;
update public.organization_member_invitations
set expires_at = now() - interval '1 minute', lease_expires_at = now() - interval '1 minute'
where invited_email = 'faye@example.test';
set local role service_role;

insert into tap_results (line) select is(
  (select count(*)::int from public.expire_team_invitations() as expired where expired.invited_email = 'faye@example.test'),
  1, 'expire_ settles the sixth invitation'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'faye@example.test'),
  'accepted', 'a completed password receipt finalizes rather than expiring'
);
insert into tap_results (line) select is(
  (select status from public.organization_members
    where organization_id = 'a1000000-0000-0000-0000-000000000001'
      and user_id = 'a0000000-0000-0000-0000-000000000007'),
  'active', 'the membership is active via the finalize-on-expire path'
);

-- 7. Reservation sweep: the Orphan Rule's own two branches -------------------------------------------------

-- Row G: reserved, no Auth attempt ever marked, gone stale -- safe to abandon and release the seat.
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'gale@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'a seventh reservation is made for the clean-abandon scenario'
);

set local role postgres;
update public.organization_member_invitations
set created_at = now() - interval '2 hours'
where invited_email = 'gale@example.test';
set local role service_role;

insert into tap_results (line) select is(
  (select count(*)::int from public.sweep_team_invitation_reservations(interval '1 hour') as swept where swept.invited_email = 'gale@example.test'),
  1, 'the sweep picks up the stale, never-attempted reservation'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'gale@example.test'),
  'abandoned', 'a crash before the Auth-attempt marker is safe to abandon directly'
);

set local role postgres;
insert into tap_results (line) select is(
  private.employee_seats_used('a1000000-0000-0000-0000-000000000001'), 6,
  'abandoning a never-attempted reservation releases its seat'
);
set local role service_role;

-- Row H: reserved, an Auth attempt was marked, gone stale -- must hold the seat and ask for cleanup.
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('a1000000-0000-0000-0000-000000000001', 'hana@example.test', 'field', 'a0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'an eighth reservation is made for the marked-attempt scenario'
);
insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started(
    (select id from public.organization_member_invitations where invited_email = 'hana@example.test'),
    'ffffffff-0000-0000-0000-00000000000f'
  )$$, 'the eighth reservation marks its Auth attempt just before the simulated crash'
);

set local role postgres;
update public.organization_member_invitations
set created_at = now() - interval '2 hours'
where invited_email = 'hana@example.test';
set local role service_role;

insert into tap_results (line) select is(
  (select count(*)::int from public.sweep_team_invitation_reservations(interval '1 hour') as swept where swept.invited_email = 'hana@example.test'),
  1, 'the sweep also reports the marked, stale reservation'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations where invited_email = 'hana@example.test'),
  'reserving', 'a marked attempt is never abandoned automatically -- the outcome is unknown'
);
insert into tap_results (line) select is(
  (select identity_cleanup_state from public.organization_member_invitations where invited_email = 'hana@example.test'),
  'required', 'a marked, stale reservation is flagged for cleanup'
);

set local role postgres;
insert into tap_results (line) select is(
  private.employee_seats_used('a1000000-0000-0000-0000-000000000001'), 7,
  'a marked reservation keeps holding its seat until 3B resolves it'
);
set local role service_role;

select * from finish();
select line from tap_results order by id;
rollback;
