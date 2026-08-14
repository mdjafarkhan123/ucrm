-- Part 6B: coverage for the payments/reactivation additions on top of the 6A commercial seam.
-- 6A's own acceptance coverage lives in organization_commercial_control.sql; this file only
-- covers what 6B added: the original_confirmation_id repoint and the combined late-renewal-
-- reactivation function.
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- Privileges -------------------------------------------------------------------

select is(
  has_function_privilege(
    'anon',
    'public.apply_organization_late_renewal_reactivation(uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb)',
    'execute'
  ),
  false,
  'anonymous callers cannot run the late-renewal-reactivation command'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.apply_organization_late_renewal_reactivation(uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb)',
    'execute'
  ),
  false,
  'contractors cannot run the late-renewal-reactivation command'
);
select is(
  has_function_privilege(
    'service_role',
    'public.apply_organization_late_renewal_reactivation(uuid, text, text, text, date, text, timestamptz, text, text, integer, uuid, boolean, text, jsonb)',
    'execute'
  ),
  true,
  'the owner service role can run the late-renewal-reactivation command'
);

-- Fixtures -----------------------------------------------------------------------

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000000b1', '6B Renewal Test', '6b-renewal-test', 'active'),
  ('90000000-0000-0000-0000-0000000000b2', '6B Reactivation Test', '6b-reactivation-test', 'suspended'),
  ('90000000-0000-0000-0000-0000000000b3', '6B Not-Suspended Reactivation Test', '6b-not-suspended-reactivation-test', 'active');

-- original_confirmation_id now points at the commercial-events ledger --------------

select is(
  (select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000b1',
    event_kind => 'initial_payment_confirmed',
    idempotency_key => '6b-test-initial-1',
    summary => 'Initial payment confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-01-01',
    amount_usd_cents => 9900,
    safe_kind => 'payment_recorded'
  ) ->> 'applied'),
  'true',
  'seed initial payment for the refund-reference test'
);

select lives_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000b1',
    event_kind => 'refund_recorded',
    idempotency_key => '6b-test-refund-valid-reference',
    summary => 'Refund recorded',
    paid_through_effect => 'unchanged',
    private_reason => 'Customer refunded in full',
    amount_usd_cents => 9900,
    original_confirmation_id => (
      select id from public.organization_commercial_events
      where organization_id = '90000000-0000-0000-0000-0000000000b1'
        and event_kind = 'initial_payment_confirmed'
    )
  )$$,
  'a refund can reference the initial-payment commercial event as its original confirmation'
);

-- A plain renewal never touches lifecycle_status ----------------------------------

select is(
  (select public.apply_organization_late_renewal_reactivation(
    target_organization_id => '90000000-0000-0000-0000-0000000000b1',
    idempotency_key => '6b-test-renewal-only',
    summary => 'Renewal confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-02-01',
    reactivate => false
  ) ->> 'reactivated'),
  'false',
  'a plain renewal reports reactivated = false'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-0000000000b1'),
  'active',
  'a plain renewal never changes an already-active organization''s lifecycle status'
);

-- Renewal with reactivation on a suspended organization ---------------------------

select is(
  (select public.apply_organization_late_renewal_reactivation(
    target_organization_id => '90000000-0000-0000-0000-0000000000b2',
    idempotency_key => '6b-test-renewal-reactivate',
    summary => 'Late renewal confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-02-01',
    actor_owner_email => 'owner@example.test',
    private_reason => 'Paid after nonpayment suspension',
    reactivate => true
  ) ->> 'reactivated'),
  'true',
  'a renewal with reactivate = true on a suspended organization reports reactivated = true'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-0000000000b2'),
  'active',
  'the suspended organization is reactivated in the same call'
);
select is(
  (select count(*)::int from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000b2' and event_kind = 'renewal_confirmed'),
  1,
  'the renewal event was recorded'
);
select is(
  (select count(*)::int from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000b2' and event_kind = 'organization_reactivated'),
  1,
  'a distinct reactivation event was recorded, not folded into the renewal event'
);
select is(
  (select source_event_id from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000b2' and event_kind = 'organization_reactivated'),
  (select id from public.organization_commercial_events
   where organization_id = '90000000-0000-0000-0000-0000000000b2' and event_kind = 'renewal_confirmed'),
  'the reactivation event chains back to the renewal that triggered it'
);
select is(
  (select count(*)::int from public.access_audit_events
   where organization_id = '90000000-0000-0000-0000-0000000000b2' and event_type = 'organization.lifecycle_changed'),
  1,
  'the lifecycle change was recorded in the owner audit trail'
);

-- Reactivation requires an acting owner email (the audit trail row is not-null) --

select throws_ok(
  $$select public.apply_organization_late_renewal_reactivation(
    target_organization_id => '90000000-0000-0000-0000-0000000000b2',
    idempotency_key => '6b-test-reactivate-no-actor-email',
    summary => 'Late renewal confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-03-01',
    private_reason => 'Missing actor email',
    reactivate => true
  )$$,
  '23514',
  null,
  'reactivation without an acting owner email is refused before any write happens'
);

-- Reactivation is refused, atomically, on a non-suspended organization -----------

select throws_ok(
  $$select public.apply_organization_late_renewal_reactivation(
    target_organization_id => '90000000-0000-0000-0000-0000000000b3',
    idempotency_key => '6b-test-reactivate-not-suspended',
    summary => 'Late renewal confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-02-01',
    actor_owner_email => 'owner@example.test',
    private_reason => 'Should be refused',
    reactivate => true
  )$$,
  '23514',
  null,
  'reactivating an organization that is not suspended is refused'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000b3'),
  0,
  'the refused reactivation left no renewal event behind -- the whole call rolled back'
);

select * from finish();
rollback;
