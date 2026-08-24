-- Contractor Settings 3B: cancellation holds the seat and normalized email until Auth cleanup succeeds.
-- Run as one transaction. The final result set contains only failures; no rows means every assertion passed.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

create temporary table tap_results (id serial primary key, line text);
grant insert, select on tap_results to service_role;
grant usage on sequence tap_results_id_seq to service_role;

insert into tap_results (line) select matches(
  (select indexdef from pg_indexes where schemaname = 'public'
    and indexname = 'organization_member_invitations_pending_email_idx'),
  'UNIQUE INDEX.*lower\(invited_email\).*identity_cleanup_state = ''required''',
  'cleanup-required invitations keep the normalized email globally claimed'
);

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, created_at, updated_at
)
values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cancel-manager-one@example.test', 'test', now(), '{}'::jsonb, now(), now()),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cancel-manager-two@example.test', 'test', now(), '{}'::jsonb, now(), now()),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cancel-target@example.test', 'test', now(),
   '{"team_invitation_identity_for":"c3000000-0000-0000-0000-000000000001"}'::jsonb, now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c1000000-0000-0000-0000-000000000001', 'Cancel One', 'cancel-one', 'active'),
  ('c1000000-0000-0000-0000-000000000002', 'Cancel Two', 'cancel-two', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'admin'),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 'admin');

insert into public.organization_limit_overrides
  (organization_id, limit_key, limit_value, is_unlimited, limit_state, starts_at)
values
  ('c1000000-0000-0000-0000-000000000001', 'employee_seats', null, true, 'unlimited', '2026-01-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-000000000002', 'employee_seats', null, true, 'unlimited', '2026-01-01T00:00:00Z');

set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('c1000000-0000-0000-0000-000000000001', 'cancel-target@example.test', 'field', 'c0000000-0000-0000-0000-000000000001', '[]'::jsonb)$$,
  'the invitation reserves normally'
);

set local role postgres;
update public.organization_member_invitations
set id = 'c3000000-0000-0000-0000-000000000001'
where invited_email = 'cancel-target@example.test';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.mark_team_invitation_auth_attempt_started('c3000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001')$$,
  'the Auth attempt is stamped'
);
insert into tap_results (line) select lives_ok(
  $$select public.attach_team_invitation_identity(
    'c3000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003',
    'c4000000-0000-0000-0000-000000000001', 'cancel-token-hash', now() + interval '7 days'
  )$$, 'the invitation-owned identity attaches'
);
insert into tap_results (line) select lives_ok(
  $$select public.cancel_team_invitation('c3000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001')$$,
  'a manager can cancel an invited identity'
);
insert into tap_results (line) select is(
  (select state || ':' || identity_cleanup_state from public.organization_member_invitations
    where id = 'c3000000-0000-0000-0000-000000000001'),
  'cancelled:required', 'cancellation is terminal and queues Auth cleanup'
);
insert into tap_results (line) select is(
  (select token_hash from public.organization_member_invitations
    where id = 'c3000000-0000-0000-0000-000000000001'),
  null, 'cancellation withdraws the acceptance token immediately'
);
insert into tap_results (line) select is(
  (select status from public.organization_members where user_id = 'c0000000-0000-0000-0000-000000000003'),
  'pending', 'the pending membership keeps the seat held before Auth deletion'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('c1000000-0000-0000-0000-000000000002', 'CANCEL-TARGET@example.test', 'sales', 'c0000000-0000-0000-0000-000000000002', '[]'::jsonb)$$,
  '23505', null, 'another organization cannot claim the email while cleanup is pending'
);
insert into tap_results (line) select throws_ok(
  $$select public.claim_cancelled_team_invitation_cleanup(
    'c1000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000001',
    'c5000000-0000-0000-0000-000000000002', 300
  )$$,
  '40001', null, 'another organization cannot lease the cancelled identity'
);
insert into tap_results (line) select lives_ok(
  $$select public.claim_cancelled_team_invitation_cleanup(
    'c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c5000000-0000-0000-0000-000000000001', 300
  )$$,
  'the owning organization can lease its cancelled identity directly'
);
insert into tap_results (line) select is(
  (select reconciliation_nonce::text from public.organization_member_invitations
    where id = 'c3000000-0000-0000-0000-000000000001'),
  'c5000000-0000-0000-0000-000000000001', 'the targeted lease records its nonce'
);
insert into tap_results (line) select throws_ok(
  $$select public.claim_cancelled_team_invitation_cleanup(
    'c1000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001',
    'c5000000-0000-0000-0000-000000000002', 300
  )$$,
  '40001', null, 'a live targeted lease cannot be stolen'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.claim_team_invitation_reconciliation('c5000000-0000-0000-0000-000000000002', 1, 300)),
  0, 'the general worker skips a live targeted lease'
);
insert into tap_results (line) select lives_ok(
  $$select public.prepare_team_invitation_identity_cleanup('c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001')$$,
  'the worker prepares cancelled identity cleanup'
);
insert into tap_results (line) select is(
  (select state || ':' || identity_cleanup_state from public.organization_member_invitations
    where id = 'c3000000-0000-0000-0000-000000000001'),
  'cancelled:required', 'cleanup preparation preserves the manager-visible cancellation'
);
insert into tap_results (line) select is(
  (select invited_user_id from public.organization_member_invitations
    where id = 'c3000000-0000-0000-0000-000000000001'),
  null, 'cleanup preparation atomically detaches the Auth identity'
);
insert into tap_results (line) select is(
  (select count(*)::int from public.organization_members where user_id = 'c0000000-0000-0000-0000-000000000003'),
  0, 'cleanup preparation removes only the pending membership'
);
insert into tap_results (line) select throws_ok(
  $$select public.begin_team_invitation('c1000000-0000-0000-0000-000000000002', 'cancel-target@example.test', 'sales', 'c0000000-0000-0000-0000-000000000002', '[]'::jsonb)$$,
  '23505', null, 'detaching the identity still keeps the email claimed until deletion settles'
);

set local role postgres;
delete from auth.users where id = 'c0000000-0000-0000-0000-000000000003';
set local role service_role;

insert into tap_results (line) select lives_ok(
  $$select public.settle_team_invitation_identity_cleanup('c3000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001')$$,
  'confirmed Auth deletion settles the cancelled invitation'
);
insert into tap_results (line) select is(
  (select state || ':' || identity_cleanup_state from public.organization_member_invitations
    where id = 'c3000000-0000-0000-0000-000000000001'),
  'cancelled:done', 'settlement preserves cancellation and releases cleanup claims'
);
insert into tap_results (line) select lives_ok(
  $$select public.begin_team_invitation('c1000000-0000-0000-0000-000000000002', 'cancel-target@example.test', 'sales', 'c0000000-0000-0000-0000-000000000002', '[]'::jsonb)$$,
  'the email becomes reusable only after confirmed Auth deletion'
);

set local role postgres;

select * from tap_results where line not like 'ok %' order by id;
select * from finish();

rollback;
