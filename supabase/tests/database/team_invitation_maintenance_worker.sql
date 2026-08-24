-- Contractor Settings 3B: bounded invitation maintenance and receipt-safe worker recovery.
begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

create temporary table tap_results (id serial primary key, line text);
grant insert, select on tap_results to service_role;
grant usage on sequence tap_results_id_seq to service_role;

insert into tap_results (line) select has_function(
  'public', 'expire_team_invitations_bounded', array['integer'],
  'expiry has an explicitly bounded command'
);
insert into tap_results (line) select has_function(
  'public', 'sweep_team_invitation_reservations_bounded', array['integer', 'interval'],
  'stale reservations have an explicitly bounded command'
);
insert into tap_results (line) select has_function(
  'public', 'finalize_reconciled_team_invitation', array['uuid', 'uuid'],
  'an Auth password receipt has a leased recovery command'
);
insert into tap_results (line) select has_index(
  'public', 'organization_member_invitations', 'organization_member_invitations_reserving_age_idx',
  'stale reservation batches have an age-ordered partial index'
);

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, created_at, updated_at
)
values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'worker-owner@example.test', 'test', now(), '{}'::jsonb, now(), now()),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'expired-one@example.test', 'test', now(),
   '{"team_invitation_identity_for":"c3000000-0000-0000-0000-000000000001"}'::jsonb, now(), now()),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'expired-two@example.test', 'test', now(),
   '{"team_invitation_identity_for":"c3000000-0000-0000-0000-000000000002"}'::jsonb, now(), now()),
  ('c0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'expired-three@example.test', 'test', now(),
   '{"team_invitation_identity_for":"c3000000-0000-0000-0000-000000000003"}'::jsonb, now(), now()),
  ('c0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'receipt@example.test', 'test', now(),
   '{"team_invitation_identity_for":"c3000000-0000-0000-0000-000000000006","invitation_password_set_for":"c3000000-0000-0000-0000-000000000006"}'::jsonb,
   now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c1000000-0000-0000-0000-000000000001', 'Invitation Worker', 'invitation-worker', 'active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'field', 'pending'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'field', 'pending'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'field', 'pending'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'field', 'pending');

insert into public.organization_member_invitations (
  id, organization_id, invited_email, role, state, invited_user_id, invited_by,
  expires_at, auth_attempt_started_at, identity_cleanup_state, created_at
)
values
  ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
   'expired-one@example.test', 'field', 'invited', 'c0000000-0000-0000-0000-000000000002',
   'c0000000-0000-0000-0000-000000000001', now() - interval '3 hours', now() - interval '4 hours',
   'not_required', now() - interval '4 hours'),
  ('c3000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001',
   'expired-two@example.test', 'field', 'invited', 'c0000000-0000-0000-0000-000000000003',
   'c0000000-0000-0000-0000-000000000001', now() - interval '2 hours', now() - interval '4 hours',
   'not_required', now() - interval '4 hours'),
  ('c3000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001',
   'expired-three@example.test', 'field', 'invited', 'c0000000-0000-0000-0000-000000000004',
   'c0000000-0000-0000-0000-000000000001', now() - interval '1 hour', now() - interval '4 hours',
   'not_required', now() - interval '4 hours'),
  ('c3000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000001',
   'no-auth-attempt@example.test', 'field', 'reserving', null,
   'c0000000-0000-0000-0000-000000000001', null, null, 'not_required', now() - interval '3 hours'),
  ('c3000000-0000-0000-0000-000000000005', 'c1000000-0000-0000-0000-000000000001',
   'uncertain-auth@example.test', 'field', 'reserving', null,
   'c0000000-0000-0000-0000-000000000001', null, now() - interval '3 hours', 'not_required',
   now() - interval '3 hours'),
  ('c3000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000001',
   'receipt@example.test', 'field', 'accepting', 'c0000000-0000-0000-0000-000000000005',
   'c0000000-0000-0000-0000-000000000001', now() - interval '1 hour', now() - interval '3 hours',
   'required', now() - interval '3 hours');

set local role service_role;

select public.expire_team_invitations_bounded(2);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_invitations
   where id in ('c3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002',
                'c3000000-0000-0000-0000-000000000003') and state = 'expired'),
  2, 'expiry processes no more than the requested batch'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_member_invitations
   where state = 'expired' and identity_cleanup_state = 'required'),
  2, 'expired identities enter the cleanup queue'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_members
   where user_id in ('c0000000-0000-0000-0000-000000000002',
                     'c0000000-0000-0000-0000-000000000003')),
  2, 'expiry keeps pending memberships and seats until Auth cleanup is confirmed'
);

select public.sweep_team_invitation_reservations_bounded(2, interval '1 hour');
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations
   where id = 'c3000000-0000-0000-0000-000000000004'),
  'abandoned', 'a stale reservation with no Auth attempt releases immediately'
);
insert into tap_results (line) select is(
  (select identity_cleanup_state from public.organization_member_invitations
   where id = 'c3000000-0000-0000-0000-000000000005'),
  'required', 'a stale reservation with an Auth attempt requires reconciliation'
);

update public.organization_member_invitations
set reconciliation_nonce = 'c4000000-0000-0000-0000-000000000001',
    reconciliation_lease_expires_at = now() + interval '5 minutes'
where id = 'c3000000-0000-0000-0000-000000000006';

select public.finalize_reconciled_team_invitation(
  'c3000000-0000-0000-0000-000000000006',
  'c4000000-0000-0000-0000-000000000001'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations
   where id = 'c3000000-0000-0000-0000-000000000006'),
  'accepted', 'a matching Auth password receipt finalizes the invitation'
);
insert into tap_results (line) select is(
  (select status from public.organization_members
   where user_id = 'c0000000-0000-0000-0000-000000000005'),
  'active', 'receipt recovery activates the pending membership atomically'
);

update public.organization_member_invitations
set reconciliation_nonce = 'c4000000-0000-0000-0000-000000000002',
    reconciliation_lease_expires_at = now() + interval '5 minutes'
where id = 'c3000000-0000-0000-0000-000000000001';
select public.prepare_team_invitation_identity_cleanup(
  'c3000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000002'
);
insert into tap_results (line) select is(
  (select state from public.organization_member_invitations
   where id = 'c3000000-0000-0000-0000-000000000001'),
  'expired', 'cleanup preparation preserves the terminal expired state'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_members
   where user_id = 'c0000000-0000-0000-0000-000000000002'),
  0, 'cleanup preparation removes only the pending membership'
);

insert into tap_results (line) select throws_ok(
  $$select public.expire_team_invitations_bounded(101)$$,
  '23514', 'The invitation expiry batch is outside its safe bounds.',
  'an oversized expiry batch is refused'
);

reset role;
select line from tap_results where line not like 'ok %' order by id;
select * from finish();
rollback;
