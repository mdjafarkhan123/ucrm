-- Part 6D: scheduled free access (one active + one non-overlapping future grant) and categorized,
-- eligibility-checked lifecycle suspend/reactivate control on top of the 6A commercial seam.
begin;

create extension if not exists pgtap with schema extensions;

select plan(46);

-- Privileges -------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.apply_organization_free_access_change(uuid, text, uuid, date, date, text, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot change free access'
);
select is(
  has_function_privilege('authenticated', 'public.apply_organization_free_access_change(uuid, text, uuid, date, date, text, text, text, timestamptz)', 'execute'),
  false, 'contractors cannot change free access'
);
select is(
  has_function_privilege('service_role', 'public.apply_organization_free_access_change(uuid, text, uuid, date, date, text, text, text, timestamptz)', 'execute'),
  true, 'the owner service role can change free access'
);
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
values ('90000000-1111-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6d-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000000d1', '6D Free Access Test', '6d-free-access-test', 'active'),
  ('90000000-0000-0000-0000-0000000000d2', '6D Free Access Lifecycle Test', '6d-free-access-lifecycle-test', 'active'),
  ('90000000-0000-0000-0000-0000000000d3', '6D Nonpayment Free Access Test', '6d-nonpayment-free-access-test', 'active'),
  ('90000000-0000-0000-0000-0000000000d4', '6D Nonpayment Paid Through Test', '6d-nonpayment-paid-through-test', 'active'),
  ('90000000-0000-0000-0000-0000000000d5', '6D Noncommercial Suspension Test', '6d-noncommercial-suspension-test', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('90000000-0000-0000-0000-0000000000d3', '90000000-1111-0000-0000-000000000001', 'owner'),
  ('90000000-0000-0000-0000-0000000000d4', '90000000-1111-0000-0000-000000000001', 'owner'),
  ('90000000-0000-0000-0000-0000000000d5', '90000000-1111-0000-0000-000000000001', 'owner');

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select org_id, version_id, now() - interval '2 minutes', 'provisioning', '6D test baseline assignment'
from (values
  ('90000000-0000-0000-0000-0000000000d1'::uuid),
  ('90000000-0000-0000-0000-0000000000d2'::uuid),
  ('90000000-0000-0000-0000-0000000000d3'::uuid)
) as orgs(org_id)
cross join lateral (
  select id as version_id from public.platform_package_versions
  where status = 'published'
  order by version_number, id
  limit 1
) as version;

-- Free access: grant, extend, and scheduled-future overlap enforcement (d1) ------

select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'grant', null, current_date, current_date + 60,
    '6d-fa-d1-grant-1', 'Pilot free access.', 'owner@example.test', now() - interval '19 minutes'
  ) ->> 'applied'),
  'true', 'a free access grant with an end date applies'
);
select is(
  (select action from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and target_grant_id is null),
  'grant', 'the grant event is its own root'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and event_kind = 'free_access_granted'),
  1, 'the grant creates one private commercial event'
);
select is(
  (select safe_payload - 'access_status' - 'free_access_until_date' - 'effective_at' from public.organization_safe_events
   where organization_id = '90000000-0000-0000-0000-0000000000d1' and safe_kind = 'free_access_updated'
   order by occurred_at desc limit 1),
  '{}'::jsonb, 'the free access safe event carries only the allowlisted keys, no private reason or actor email'
);

select throws_ok(
  $$select public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'grant', null, current_date, null,
    '6d-fa-d1-grant-2b', 'A second active grant attempt.', 'owner@example.test', now() - interval '18 minutes'
  )$$,
  '23514', null, 'a second active grant is rejected with a check violation'
);
select is(
  (select count(*)::int from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1'),
  1, 'the rejected second grant created no new event'
);

select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'extend',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and target_grant_id is null),
    null, current_date + 90, '6d-fa-d1-extend-1', 'Extend the pilot.', 'owner@example.test', now() - interval '17 minutes'
  ) ->> 'applied'),
  'true', 'extending the active grant to a later end date applies'
);
select is(
  (select target_grant_id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and action = 'extend'),
  (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and target_grant_id is null),
  'the extend event references the root grant'
);
select throws_ok(
  $$select public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'extend',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and target_grant_id is null),
    null, current_date + 90, '6d-fa-d1-extend-2', 'Not actually later.', 'owner@example.test', now() - interval '16 minutes'
  )$$,
  '23514', null, 'extending to the same end date is rejected'
);

select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'grant', null, current_date + 120, null,
    '6d-fa-d1-future-1', 'Schedule the next grant.', 'owner@example.test', now() - interval '15 minutes'
  ) ->> 'applied'),
  'true', 'a non-overlapping future grant can be scheduled while the active grant is in effect'
);
select throws_ok(
  $$select public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'grant', null, current_date + 150, null,
    '6d-fa-d1-future-2', 'A second scheduled grant attempt.', 'owner@example.test', now() - interval '14 minutes'
  )$$,
  '23514', null, 'a second scheduled future grant is rejected'
);
select throws_ok(
  $$select public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'extend',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and target_grant_id is null and starts_at = current_date),
    null, current_date + 130, '6d-fa-d1-extend-overlap-1', 'Would swallow the scheduled grant.', 'owner@example.test', now() - interval '13 minutes'
  )$$,
  '23514', null, 'extending the active grant past the scheduled future grant''s start date is rejected'
);

select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'extend',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and target_grant_id is null and starts_at = current_date),
    null, current_date + 90, '6d-fa-d1-extend-1', 'Replay of the earlier extend.', 'owner@example.test', now() - interval '12 minutes'
  ) ->> 'applied'),
  'false', 'replaying the same idempotency key does not reapply the command'
);
select is(
  (select count(*)::int from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d1' and action = 'extend'),
  1, 'the idempotent replay created no duplicate event'
);

select throws_ok(
  $$select public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d1', 'end', '00000000-0000-0000-0000-000000000999',
    null, null, '6d-fa-d1-end-missing-1', 'Acting on a grant that does not exist.', 'owner@example.test', now() - interval '11 minutes'
  )$$,
  '23514', null, 'acting on a nonexistent grant id is rejected'
);

-- Free access: convert to forever, then end (d2) ---------------------------------

select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d2', 'grant', null, current_date, current_date + 30,
    '6d-fa-d2-grant-1', 'Time-boxed pilot.', 'owner@example.test', now() - interval '9 minutes'
  ) ->> 'applied'),
  'true', 'a time-boxed grant applies on a second organization'
);
select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d2', 'convert_to_forever',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d2' and target_grant_id is null),
    null, null, '6d-fa-d2-convert-1', 'Make it permanent.', 'owner@example.test', now() - interval '8 minutes'
  ) ->> 'access_until_date'),
  null, 'converting to forever removes the end date'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000d2' and event_kind = 'free_access_converted_forever'),
  1, 'the conversion creates one private event'
);
select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d2', 'end',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d2' and target_grant_id is null),
    null, null, '6d-fa-d2-end-1', 'Pilot is over.', 'owner@example.test', now() - interval '7 minutes'
  ) ->> 'applied'),
  'true', 'ending the now-forever grant applies'
);
select throws_ok(
  $$select public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d2', 'extend',
    (select id from public.organization_free_access_events where organization_id = '90000000-0000-0000-0000-0000000000d2' and target_grant_id is null),
    null, current_date + 400, '6d-fa-d2-extend-after-end-1', 'Cannot revive an ended grant.', 'owner@example.test', now() - interval '6 minutes'
  )$$,
  '23514', null, 'acting on an already-ended grant is rejected'
);

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
select is(
  (public.apply_organization_free_access_change(
    '90000000-0000-0000-0000-0000000000d3', 'grant', null, current_date, null,
    '6d-fa-d3-grant-1', 'Grant free access to restore eligibility.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'free access can be granted to a suspended organization'
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
