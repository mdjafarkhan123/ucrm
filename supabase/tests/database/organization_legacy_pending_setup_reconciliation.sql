-- Part 6E: legacy pending_setup organization reconciliation.
begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- Privileges -------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.organization_legacy_readiness(uuid)', 'execute'),
  false, 'anonymous callers cannot read legacy readiness'
);
select is(
  has_function_privilege('authenticated', 'public.organization_legacy_readiness(uuid)', 'execute'),
  false, 'contractors cannot read legacy readiness'
);
select is(
  has_function_privilege('service_role', 'public.organization_legacy_readiness(uuid)', 'execute'),
  true, 'the owner service role can read legacy readiness'
);
select is(
  has_function_privilege('anon', 'public.apply_organization_pending_setup_reconciliation(uuid, text, text, text, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot reconcile a legacy organization'
);
select is(
  has_function_privilege('authenticated', 'public.apply_organization_pending_setup_reconciliation(uuid, text, text, text, text, text, timestamptz)', 'execute'),
  false, 'contractors cannot reconcile a legacy organization'
);
select is(
  has_function_privilege('service_role', 'public.apply_organization_pending_setup_reconciliation(uuid, text, text, text, text, text, timestamptz)', 'execute'),
  true, 'the owner service role can reconcile a legacy organization'
);

-- Fixtures -----------------------------------------------------------------------

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('90000000-1111-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6e-owner-ready@example.test', 'test', now(), now(), now()),
  ('90000000-1111-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '6e-owner-not-ready@example.test', null, null, now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000000e1', '6E Legacy Empty Test', '6e-legacy-empty-test', 'pending_setup'),
  ('90000000-0000-0000-0000-0000000000e2', '6E Legacy Ready Test', '6e-legacy-ready-test', 'pending_setup'),
  ('90000000-0000-0000-0000-0000000000e3', '6E Legacy Login Not Ready Test', '6e-legacy-login-not-ready-test', 'pending_setup'),
  ('90000000-0000-0000-0000-0000000000e4', '6E Legacy No Billing Test', '6e-legacy-no-billing-test', 'pending_setup'),
  ('90000000-0000-0000-0000-0000000000e5', '6E Legacy Suspend Test', '6e-legacy-suspend-test', 'pending_setup'),
  ('90000000-0000-0000-0000-0000000000e6', '6E Already Active Test', '6e-already-active-test', 'active'),
  ('90000000-0000-0000-0000-0000000000e7', '6E Legacy Idempotency Test', '6e-legacy-idempotency-test', 'pending_setup');

insert into public.organization_members (organization_id, user_id, role)
values
  ('90000000-0000-0000-0000-0000000000e2', '90000000-1111-0000-0000-0000000000e1', 'owner'),
  ('90000000-0000-0000-0000-0000000000e3', '90000000-1111-0000-0000-0000000000e2', 'admin'),
  ('90000000-0000-0000-0000-0000000000e4', '90000000-1111-0000-0000-0000000000e1', 'owner'),
  ('90000000-0000-0000-0000-0000000000e7', '90000000-1111-0000-0000-0000000000e1', 'owner');

insert into public.organization_package_assignments (organization_id, package_version_id, effective_at, assignment_source, reason)
select org_id, version_id, now() - interval '2 minutes', 'legacy_owner_action', '6E test baseline assignment'
from (values
  ('90000000-0000-0000-0000-0000000000e2'::uuid),
  ('90000000-0000-0000-0000-0000000000e3'::uuid),
  ('90000000-0000-0000-0000-0000000000e4'::uuid),
  ('90000000-0000-0000-0000-0000000000e7'::uuid)
) as orgs(org_id)
cross join lateral (
  select id as version_id from public.platform_package_versions
  where status = 'published'
  order by version_number, id
  limit 1
) as version;

-- e2 and e7 get a paid-through baseline so they are activation-eligible.
select public.apply_organization_commercial_command(
  target_organization_id => '90000000-0000-0000-0000-0000000000e2',
  event_kind => 'paid_through_adjusted',
  idempotency_key => '6e-e2-baseline',
  summary => 'Legacy paid-through baseline recorded.',
  paid_through_effect => 'set',
  paid_through_date => current_date + 30,
  private_reason => '6E test baseline.',
  is_legacy_import => true,
  safe_kind => 'access_period_updated',
  safe_payload => jsonb_build_object('paid_through_date', current_date + 30)
);
select public.apply_organization_commercial_command(
  target_organization_id => '90000000-0000-0000-0000-0000000000e7',
  event_kind => 'paid_through_adjusted',
  idempotency_key => '6e-e7-baseline',
  summary => 'Legacy paid-through baseline recorded.',
  paid_through_effect => 'set',
  paid_through_date => current_date + 30,
  private_reason => '6E test baseline.',
  is_legacy_import => true,
  safe_kind => 'access_period_updated',
  safe_payload => jsonb_build_object('paid_through_date', current_date + 30)
);
-- e3 also gets a paid-through baseline; its only blocker is the admin's login readiness.
select public.apply_organization_commercial_command(
  target_organization_id => '90000000-0000-0000-0000-0000000000e3',
  event_kind => 'paid_through_adjusted',
  idempotency_key => '6e-e3-baseline',
  summary => 'Legacy paid-through baseline recorded.',
  paid_through_effect => 'set',
  paid_through_date => current_date + 30,
  private_reason => '6E test baseline.',
  is_legacy_import => true,
  safe_kind => 'access_period_updated',
  safe_payload => jsonb_build_object('paid_through_date', current_date + 30)
);

-- Readiness checklist -------------------------------------------------------------

select is(
  public.organization_legacy_readiness('90000000-0000-0000-0000-0000000000e1'),
  jsonb_build_object(
    'package_assigned', false, 'administrator_exists', false, 'administrator_login_ready', false,
    'paid_through_eligible', false, 'free_access_active', false
  ),
  'an empty legacy organization has no readiness signal true'
);
select is(
  public.organization_legacy_readiness('90000000-0000-0000-0000-0000000000e2'),
  jsonb_build_object(
    'package_assigned', true, 'administrator_exists', true, 'administrator_login_ready', true,
    'paid_through_eligible', true, 'free_access_active', false
  ),
  'a fully ready legacy organization reports every check true'
);
select is(
  (public.organization_legacy_readiness('90000000-0000-0000-0000-0000000000e3') ->> 'administrator_exists')::boolean,
  true, 'an admin-role member counts as an administrator, not only owner'
);
select is(
  (public.organization_legacy_readiness('90000000-0000-0000-0000-0000000000e3') ->> 'administrator_login_ready')::boolean,
  false, 'an administrator without a password set is not login-ready'
);

-- Activation is blocked on each missing readiness signal --------------------------

select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e1', 'active', null,
    '6e-e1-activate', 'Reviewed, looks fine.', 'owner@example.test', now() - interval '20 minutes'
  )$$,
  '%package version%', 'activation without a package assignment is rejected'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e4', 'active', null,
    '6e-e4-activate', 'Reviewed, no billing yet.', 'owner@example.test', now() - interval '19 minutes'
  )$$,
  '%paid-through date or active free access%', 'activation without paid-through or free access is rejected'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e3', 'active', null,
    '6e-e3-activate', 'Reviewed, admin not set up.', 'owner@example.test', now() - interval '18 minutes'
  )$$,
  '%login setup%', 'activation is rejected while the administrator has not completed login setup'
);

-- Suspending a legacy organization needs no eligibility, only category + reason ---

select is(
  (public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e5', 'suspended', 'other',
    '6e-e5-suspend', 'Not proceeding with this legacy account.', 'owner@example.test', now() - interval '17 minutes'
  ) ->> 'applied'),
  'true', 'suspending an admin-less legacy organization applies without readiness checks'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-0000000000e5'),
  'suspended', 'the organization moves out of pending_setup into suspended'
);
select is(
  (select event_kind from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000e5'),
  'pending_setup_resolved', 'the reconciliation writes a pending_setup_resolved private event'
);
select is(
  (select safe_payload from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000e5'),
  jsonb_build_object('access_status', 'suspended'),
  'the contractor-safe event carries only the resulting access status'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e5', 'suspended', 'invalid_category',
    '6e-e5-suspend-bad-cat', 'Retrying with a bad category.', 'owner@example.test', now() - interval '16 minutes'
  )$$,
  '%valid category%', 'an unrecognised suspension category is rejected'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e5', 'suspended', 'other',
    '6e-e5-no-reason', '   ', 'owner@example.test', now() - interval '15 minutes'
  )$$,
  '%reconciliation reason%', 'a blank reason is rejected'
);

-- Activation happy path ------------------------------------------------------------

select is(
  (public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e2', 'active', null,
    '6e-e2-activate', 'Reviewed: paid, administrator ready.', 'owner@example.test', now() - interval '14 minutes'
  ) ->> 'applied'),
  'true', 'activating a fully ready legacy organization applies'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-0000000000e2'),
  'active', 'the organization moves out of pending_setup into active'
);
select is(
  (select suspension_category from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000e2' and event_kind = 'pending_setup_resolved'),
  null, 'an activation event carries no suspension category'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e2', 'suspended', 'other',
    '6e-e2-double', 'Trying to reconcile again.', 'owner@example.test', now() - interval '13 minutes'
  )$$,
  '%pending%', 'an organization already resolved out of pending_setup cannot be reconciled again here'
);

-- Guard: only pending_setup organizations can be reconciled here -------------------

select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e6', 'suspended', 'other',
    '6e-e6-reconcile', 'Should not apply to an already-active organization.', 'owner@example.test', now() - interval '12 minutes'
  )$$,
  '%pending%', 'an already-active organization cannot be reconciled through this command'
);

-- Idempotency -----------------------------------------------------------------------

select is(
  (public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e7', 'active', null,
    '6e-e7-activate', 'First reconciliation.', 'owner@example.test', now() - interval '11 minutes'
  ) ->> 'applied'),
  'true', 'the first idempotent call applies'
);
select is(
  (public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e7', 'active', null,
    '6e-e7-activate', 'First reconciliation.', 'owner@example.test', now() - interval '11 minutes'
  ) ->> 'applied'),
  'false', 'retrying the same idempotency key does not apply again'
);
select is(
  (select count(*)::int from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000e7' and event_kind = 'pending_setup_resolved'),
  1, 'retrying the same idempotency key creates no second event'
);

-- Validation ---------------------------------------------------------------------

select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e1', 'closed', null,
    '6e-e1-bad-status', 'Bad status.', 'owner@example.test', now() - interval '10 minutes'
  )$$,
  '%status is invalid%', 'an unrecognised target status is rejected'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e1', 'active', 'nonpayment',
    '6e-e1-bad-combo', 'Activation with a category.', 'owner@example.test', now() - interval '9 minutes'
  )$$,
  '%cannot include a suspension category%', 'activation cannot include a suspension category'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e1', 'suspended', 'other',
    'short', 'Too short a key.', 'owner@example.test', now() - interval '8 minutes'
  )$$,
  '%idempotency key%', 'a short idempotency key is rejected'
);
select throws_like(
  $$select public.apply_organization_pending_setup_reconciliation(
    '90000000-0000-0000-0000-0000000000e1', 'suspended', 'other',
    '6e-e1-no-actor', 'Missing actor email.', '', now() - interval '7 minutes'
  )$$,
  '%acting owner email%', 'a missing actor email is rejected'
);

select * from finish();
rollback;
