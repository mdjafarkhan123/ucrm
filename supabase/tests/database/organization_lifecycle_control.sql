-- Part 6D: categorized, eligibility-checked lifecycle suspend/reactivate control on top of the 6A
-- commercial seam. The free access commands this file also covered are rebuilt in package-builder P5,
-- which brings their coverage back; here a free access grant is placed directly.
begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- Privileges -------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.apply_organization_lifecycle_change(uuid, text, text, text, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot change lifecycle status'
);
select is(
  has_function_privilege('authenticated', 'public.apply_organization_lifecycle_change(uuid, text, text, text, text, text, timestamptz)', 'execute'),
  false, 'contractors cannot change lifecycle status'
);
select is(
  has_function_privilege('service_role', 'public.apply_organization_lifecycle_change(uuid, text, text, text, text, text, timestamptz)', 'execute'),
  true, 'the owner service role can change lifecycle status'
);

-- Fixtures -----------------------------------------------------------------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('90000000-1111-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6d-owner@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6d-owner-2@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6d-owner-3@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000000d3', '6D Nonpayment Free Access Test', '6d-nonpayment-free-access-test', 'active'),
  ('90000000-0000-0000-0000-0000000000d4', '6D Nonpayment Paid Through Test', '6d-nonpayment-paid-through-test', 'active'),
  ('90000000-0000-0000-0000-0000000000d5', '6D Noncommercial Suspension Test', '6d-noncommercial-suspension-test', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('90000000-0000-0000-0000-0000000000d3', '90000000-1111-0000-0000-000000000001', 'owner'),
  ('90000000-0000-0000-0000-0000000000d4', '90000000-1111-0000-0000-000000000002', 'owner'),
  ('90000000-0000-0000-0000-0000000000d5', '90000000-1111-0000-0000-000000000003', 'owner');

-- Lifecycle: category and reason validation, idempotency (d3) --------------------

select throws_ok(
  $$select public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'suspended', 'not-a-category',
    '6d-lc-d3-bad-category-1', 'Invalid category.', 'owner@example.test'
  )$$,
  '23514', null, 'suspension requires a valid category'
);
select throws_ok(
  $$select public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'suspended', 'nonpayment',
    '6d-lc-d3-no-reason-1', '', 'owner@example.test'
  )$$,
  '23514', null, 'suspension requires a non-empty reason'
);
select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'suspended', 'nonpayment',
    '6d-lc-d3-suspend-1', 'Invoice past due.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'a categorized nonpayment suspension applies'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-0000000000d3'),
  'suspended', 'the organization is suspended'
);
select is(
  (select suspension_category from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000d3' and event_kind = 'organization_suspended'),
  'nonpayment', 'the suspension category is recorded on the private event'
);
select is(
  (select safe_payload from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000d3' and safe_kind = 'account_suspended'),
  jsonb_build_object('access_status', 'suspended'), 'the suspension safe event carries only the access status, no category or reason'
);
select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'suspended', 'nonpayment',
    '6d-lc-d3-suspend-1', 'Replay.', 'owner@example.test'
  ) ->> 'applied'),
  'false', 'replaying the same suspension idempotency key does not reapply the command'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000d3' and event_kind = 'organization_suspended'),
  1, 'the idempotent replay created no duplicate suspension event'
);

-- Lifecycle: nonpayment reactivation is gated on eligibility (d3) ----------------

select throws_ok(
  $$select public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'active', null,
    '6d-lc-d3-reactivate-blocked-1', 'Trying before eligibility is restored.', 'owner@example.test'
  )$$,
  '23514', null, 'reactivation after nonpayment suspension is blocked without restored eligibility'
);
insert into public.organization_free_access_events (
  organization_id, action, starts_at, access_until_date, reason, actor_owner_email
) values (
  '90000000-0000-0000-0000-0000000000d3', 'grant', current_date, current_date + 30,
  'Grant free access to restore eligibility.', 'owner@example.test'
);
select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'active', null,
    '6d-lc-d3-reactivate-1', 'Active free access restores eligibility.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'reactivation succeeds once an active free access grant covers today'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-0000000000d3'),
  'active', 'the organization is reactivated'
);
select throws_ok(
  $$select public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d3', 'active', null,
    '6d-lc-d3-already-active-1', 'Already active.', 'owner@example.test'
  )$$,
  '23514', null, 'reactivating an already-active organization is rejected'
);

-- Lifecycle: nonpayment reactivation via restored paid-through date (d4) ---------

select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d4', 'suspended', 'nonpayment',
    '6d-lc-d4-suspend-1', 'Invoice past due.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'a second organization can be suspended for nonpayment'
);
select throws_ok(
  $$select public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d4', 'active', null,
    '6d-lc-d4-reactivate-blocked-1', 'Still not paid.', 'owner@example.test'
  )$$,
  '23514', null, 'reactivation is blocked before the paid-through date is restored'
);
select public.apply_organization_commercial_command(
  target_organization_id => '90000000-0000-0000-0000-0000000000d4',
  actor_owner_email => 'owner@example.test',
  event_kind => 'initial_payment_confirmed',
  idempotency_key => '6d-lc-d4-payment-1',
  summary => 'Payment recorded to restore eligibility.',
  paid_through_effect => 'set',
  paid_through_date => current_date + 30,
  amount_usd_cents => 9900,
  safe_kind => 'payment_recorded'
);
select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d4', 'active', null,
    '6d-lc-d4-reactivate-1', 'Paid-through date restored.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'reactivation succeeds once the paid-through date is restored'
);

-- Lifecycle: noncommercial suspension needs only a resolution reason (d5) -------

select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d5', 'suspended', 'security',
    '6d-lc-d5-suspend-1', 'Suspicious login activity under review.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'a security-category suspension applies'
);
select throws_ok(
  $$select public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d5', 'active', 'security',
    '6d-lc-d5-bad-reactivate-1', 'Cannot include a category on reactivation.', 'owner@example.test'
  )$$,
  '23514', null, 'reactivation cannot include a suspension category'
);
select is(
  (public.apply_organization_lifecycle_change(
    '90000000-0000-0000-0000-0000000000d5', 'active', null,
    '6d-lc-d5-reactivate-1', 'Security review cleared the account.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'reactivation after a security suspension succeeds with only a resolution reason, no payment eligibility required'
);
select is(
  (select paid_through_before is not distinct from paid_through_after from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000d5' and event_kind = 'organization_reactivated'),
  true, 'the noncommercial reactivation never fabricates a paid-through change'
);

select * from finish();
rollback;
