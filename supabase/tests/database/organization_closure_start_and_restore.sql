-- Part 9: recoverable closure and strict purge -- closure start and restore command seam.
begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- Privileges -----------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.apply_organization_closure_start(uuid, text, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot start closure'
);
select is(
  has_function_privilege('authenticated', 'public.apply_organization_closure_start(uuid, text, text, text, timestamptz)', 'execute'),
  false, 'contractors cannot start closure'
);
select is(
  has_function_privilege('service_role', 'public.apply_organization_closure_start(uuid, text, text, text, timestamptz)', 'execute'),
  true, 'the owner service role can start closure'
);
select is(
  has_function_privilege('anon', 'public.apply_organization_closure_restore(uuid, text, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot restore a closing organization'
);
select is(
  has_function_privilege('authenticated', 'public.apply_organization_closure_restore(uuid, text, text, text, timestamptz)', 'execute'),
  false, 'contractors cannot restore a closing organization'
);
select is(
  has_function_privilege('service_role', 'public.apply_organization_closure_restore(uuid, text, text, text, timestamptz)', 'execute'),
  true, 'the owner service role can restore a closing organization'
);

-- Fixtures ---------------------------------------------------------------------

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-000000000901', '9 Closure Active Test', '9-closure-active-test', 'active'),
  ('90000000-0000-0000-0000-000000000902', '9 Closure Suspended Test', '9-closure-suspended-test', 'suspended'),
  ('90000000-0000-0000-0000-000000000903', '9 Closure Pending Setup Test', '9-closure-pending-setup-test', 'pending_setup'),
  ('90000000-0000-0000-0000-000000000904', '9 Closure Never Closed Test', '9-closure-never-closed-test', 'active');

-- Closure start on an active organization (p1) ----------------------------------

select is(
  (public.apply_organization_closure_start(
    '90000000-0000-0000-0000-000000000901', '9-close-p1-start-1',
    'Contractor requested account closure.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'closure start on an active organization applies'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-000000000901'),
  'pending_closure', 'closure start immediately blocks the organization'
);
select is(
  (select status from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901'),
  'pending_closure', 'a pending_closure closure record is created'
);
select is(
  (select prior_lifecycle_status from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901'),
  'active', 'the closure record captures the prior lifecycle status'
);
select is(
  (select (deadline_at - started_at) = interval '30 days' from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901'),
  true, 'the recovery window is exactly 30 days'
);
select is(
  (select safe_payload - 'access_status' - 'closure_deadline_at' from public.organization_safe_events se
   join public.organization_commercial_events ce on ce.id = se.commercial_event_id
   where ce.organization_id = '90000000-0000-0000-0000-000000000901' and se.safe_kind = 'closure_started'),
  '{}'::jsonb, 'the closure-started safe event carries only the allowlisted keys, no private reason or actor email'
);

-- Idempotency: retrying the same command with the same key changes nothing further ---------------

select is(
  (public.apply_organization_closure_start(
    '90000000-0000-0000-0000-000000000901', '9-close-p1-start-1',
    'Contractor requested account closure.', 'owner@example.test'
  ) ->> 'applied'),
  'false', 'retrying closure start with the same idempotency key is a no-op'
);
select is(
  (select count(*)::int from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901'),
  1, 'the retried closure start created no second closure record'
);

-- Rejections: wrong starting state ----------------------------------------------

select throws_ok(
  $$select public.apply_organization_closure_start(
    '90000000-0000-0000-0000-000000000901', '9-close-p1-start-2',
    'Trying to close an already-closing organization.', 'owner@example.test'
  )$$,
  '23514', null, 'closure start is rejected for an organization already pending closure'
);
select throws_ok(
  $$select public.apply_organization_closure_start(
    '90000000-0000-0000-0000-000000000903', '9-close-p3-start-1',
    'Trying to close a legacy pending_setup organization.', 'owner@example.test'
  )$$,
  '23514', null, 'closure start is rejected for a legacy pending_setup organization'
);
select throws_ok(
  $$select public.apply_organization_closure_restore(
    '90000000-0000-0000-0000-000000000904', '9-close-p4-restore-1',
    'Nothing to restore.', 'owner@example.test'
  )$$,
  '23514', null, 'restore is rejected for an organization that was never closed'
);

-- Closure start on a suspended organization (p2) preserves suspended as the prior state -----------

select is(
  (public.apply_organization_closure_start(
    '90000000-0000-0000-0000-000000000902', '9-close-p2-start-1',
    'Closing a suspended organization.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'closure start on a suspended organization applies'
);
select is(
  (select prior_lifecycle_status from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000902'),
  'suspended', 'the closure record captures suspended, not active, as the prior status'
);

-- Restore returns the organization to its exact prior status ----------------------

select is(
  (public.apply_organization_closure_restore(
    '90000000-0000-0000-0000-000000000901', '9-close-p1-restore-1',
    'Verified through a trusted support channel.', 'owner@example.test'
  ) ->> 'lifecycle_status'),
  'active', 'restoring p1 returns it to active'
);
select is(
  (select lifecycle_status from public.organizations where id = '90000000-0000-0000-0000-000000000901'),
  'active', 'the organization row itself is active again'
);
select is(
  (select status from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901'
   order by started_at desc limit 1),
  'restored', 'the closure record is marked restored'
);
select is(
  (public.apply_organization_closure_restore(
    '90000000-0000-0000-0000-000000000902', '9-close-p2-restore-1',
    'Verified through a trusted support channel.', 'owner@example.test'
  ) ->> 'lifecycle_status'),
  'suspended', 'restoring p2 returns it to suspended, not active'
);

-- Restore idempotency ------------------------------------------------------------

select is(
  (public.apply_organization_closure_restore(
    '90000000-0000-0000-0000-000000000902', '9-close-p2-restore-1',
    'Verified through a trusted support channel.', 'owner@example.test'
  ) ->> 'applied'),
  'false', 'retrying restore with the same idempotency key is a no-op'
);

-- A restored organization can be closed again (a fresh closure record, old one stays restored) ----

select is(
  (public.apply_organization_closure_start(
    '90000000-0000-0000-0000-000000000901', '9-close-p1-start-3',
    'Closing again after an earlier restore.', 'owner@example.test'
  ) ->> 'applied'),
  'true', 'a previously restored organization can be closed again'
);
select is(
  (select count(*)::int from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901'),
  2, 'the organization now has two closure records: one restored, one open'
);
select is(
  (select count(*)::int from public.organization_closure_records
   where organization_id = '90000000-0000-0000-0000-000000000901' and status = 'pending_closure'),
  1, 'exactly one closure record is currently open'
);

select * from finish();
rollback;
