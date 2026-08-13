begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

-- Structure ------------------------------------------------------------------

select has_table('public', 'organization_commercial_settings', 'commercial settings table exists');
select has_table('public', 'organization_commercial_events', 'private commercial events table exists');
select has_table('public', 'organization_commercial_state', 'current commercial projection table exists');
select has_table('public', 'organization_safe_events', 'contractor-safe events table exists');

select is((select relrowsecurity from pg_class where oid = 'public.organization_commercial_settings'::regclass), true, 'commercial settings RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.organization_commercial_events'::regclass), true, 'commercial events RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.organization_commercial_state'::regclass), true, 'commercial state RLS is enabled');
select is((select relrowsecurity from pg_class where oid = 'public.organization_safe_events'::regclass), true, 'safe events RLS is enabled');

select is(has_table_privilege('anon', 'public.organization_commercial_events', 'select'), false, 'anonymous callers cannot read private commercial events');
select is(has_table_privilege('authenticated', 'public.organization_commercial_events', 'select'), false, 'contractors cannot read private commercial events');
select is(has_table_privilege('authenticated', 'public.organization_commercial_state', 'select'), false, 'contractors cannot read the commercial projection');
select is(has_table_privilege('authenticated', 'public.organization_commercial_settings', 'select'), false, 'contractors cannot read the commercial timezone');
select is(has_table_privilege('authenticated', 'public.organization_safe_events', 'select'), true, 'contractors can read safe events subject to RLS');
select is(has_table_privilege('authenticated', 'public.organization_safe_events', 'insert'), false, 'contractors cannot write safe events');
select is(has_table_privilege('service_role', 'public.organization_commercial_events', 'insert'), true, 'the owner service role can append commercial events');
select is(
  has_function_privilege('authenticated', 'public.apply_organization_commercial_command(uuid, text, text, text, text, date, text, timestamptz, text, text, integer, uuid, uuid, text, text, boolean, boolean, text, jsonb)', 'execute'),
  false,
  'contractors cannot run commercial commands'
);

select has_index('public', 'organization_commercial_events', 'organization_commercial_events_history_idx', 'commercial history has an organization history index');
select has_index('public', 'organization_commercial_state', 'organization_commercial_state_attention_idx', 'the projection has a grace attention index');
select has_index('public', 'organization_commercial_events', 'organization_commercial_events_idempotency_unique', 'commercial events are unique per organization idempotency key');
select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'organization_safe_events'),
  1,
  'safe events expose exactly one member read policy'
);

-- Fixtures -------------------------------------------------------------------

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-0000-0000000000a1', 'Commercial Foundation Test', 'commercial-foundation-test', 'active'),
  ('90000000-0000-0000-0000-0000000000a2', 'Commercial Foundation DST Test', 'commercial-foundation-dst-test', 'active');

update public.organization_settings
set timezone = 'America/New_York'
where organization_id in (
  '90000000-0000-0000-0000-0000000000a1',
  '90000000-0000-0000-0000-0000000000a2'
);

-- One command writes the private event, the projection, and the safe event -----

select is(
  (select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'initial_payment_confirmed',
    idempotency_key => 'commercial-test-initial-1',
    summary => 'Initial payment confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-01-01',
    actor_owner_email => 'owner@example.test',
    private_reference => 'bank-ref-001',
    amount_usd_cents => 9900,
    safe_kind => 'payment_recorded',
    safe_payload => jsonb_build_object('paid_through_date', '2026-01-01')
  ) ->> 'applied'),
  'true',
  'the first commercial command is applied'
);

select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  1,
  'the command wrote exactly one private event'
);
select is(
  (select count(*)::int from public.organization_safe_events where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  1,
  'the command wrote exactly one contractor-safe event'
);
select is(
  (select paid_through_date from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  date '2026-01-01',
  'the projection carries the confirmed paid-through date'
);
select is(
  (select grace_ends_at from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  timestamptz '2026-01-09 05:00:00+00',
  'grace ends seven calendar days later at the commercial timezone day boundary'
);
select is(
  (select state_version from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  1::bigint,
  'the projection advanced one version'
);
select is(
  (select commercial_timezone from public.organization_commercial_settings where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  'America/New_York',
  'the commercial timezone baseline was imported from the operational timezone'
);

-- Retrying the same command cannot duplicate or reapply ----------------------

select is(
  (select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'initial_payment_confirmed',
    idempotency_key => 'commercial-test-initial-1',
    summary => 'Initial payment confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-01-01',
    actor_owner_email => 'owner@example.test',
    private_reference => 'bank-ref-001',
    amount_usd_cents => 9900,
    safe_kind => 'payment_recorded'
  ) ->> 'applied'),
  'false',
  'retrying the same command reports that nothing was applied'
);
select is(
  (select count(*)::int from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  1,
  'retrying the same command cannot duplicate the private event'
);
select is(
  (select state_version from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  1::bigint,
  'retrying the same command cannot apply the projection twice'
);

-- Commercial timezone changes -------------------------------------------------

select lives_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'commercial_timezone_changed',
    idempotency_key => 'commercial-test-timezone-1',
    summary => 'Commercial timezone moved to Dhaka',
    paid_through_effect => 'unchanged',
    private_reason => 'Billing is administered from Dhaka',
    commercial_timezone => 'Asia/Dhaka'
  )$$,
  'a commercial timezone change is recorded'
);
select is(
  (select grace_ends_at from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  timestamptz '2026-01-09 05:00:00+00',
  'a timezone change preserves the existing deadline by default'
);
select is(
  (select commercial_timezone from public.organization_commercial_settings where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  'Asia/Dhaka',
  'the commercial timezone is now owner controlled'
);
select is(
  (select timezone_source from public.organization_commercial_settings where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  'owner_set',
  'the commercial timezone records that the owner set it'
);
select is(
  (select imported_operational_timezone from public.organization_commercial_settings where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  'America/New_York',
  'the imported baseline stays traceable after an owner change'
);

select lives_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'commercial_timezone_changed',
    idempotency_key => 'commercial-test-timezone-2',
    summary => 'Commercial timezone moved to UTC with recalculation',
    paid_through_effect => 'unchanged',
    private_reason => 'Standardising the commercial calendar',
    commercial_timezone => 'UTC',
    recalculate_deadline => true
  )$$,
  'a confirmed recalculation is recorded'
);
select is(
  (select grace_ends_at from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  timestamptz '2026-01-09 00:00:00+00',
  'an explicitly confirmed recalculation moves the deadline'
);

-- Operational timezone changes never move the commercial timezone -------------

update public.organization_settings
set timezone = 'Europe/London'
where organization_id = '90000000-0000-0000-0000-0000000000a1';

select is(
  (select commercial_timezone from public.organization_commercial_settings where organization_id = '90000000-0000-0000-0000-0000000000a1'),
  'UTC',
  'a later operational timezone change does not move the commercial timezone'
);

-- Grace across a DST transition -----------------------------------------------

select lives_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a2',
    event_kind => 'initial_payment_confirmed',
    idempotency_key => 'commercial-test-dst-1',
    summary => 'Initial payment confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2026-03-01',
    safe_kind => 'payment_recorded'
  )$$,
  'a paid-through date whose grace window crosses a DST change is accepted'
);
select is(
  (select grace_ends_at from public.organization_commercial_state where organization_id = '90000000-0000-0000-0000-0000000000a2'),
  timestamptz '2026-03-09 04:00:00+00',
  'grace ends at the local day boundary after the DST transition'
);

-- Append-only history ---------------------------------------------------------

select throws_ok(
  $$update public.organization_commercial_events set summary = 'rewritten' where organization_id = '90000000-0000-0000-0000-0000000000a1'$$,
  '23514',
  null,
  'a private commercial event cannot be changed after it is written'
);
select throws_ok(
  $$delete from public.organization_commercial_events where organization_id = '90000000-0000-0000-0000-0000000000a1'$$,
  '23514',
  null,
  'a private commercial event cannot be deleted'
);
select throws_ok(
  $$update public.organization_safe_events set safe_kind = 'account_suspended' where organization_id = '90000000-0000-0000-0000-0000000000a1'$$,
  '23514',
  null,
  'a contractor-safe event cannot be changed after it is written'
);

-- Guarded command inputs ------------------------------------------------------

select throws_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'renewal_confirmed',
    idempotency_key => 'commercial-test-unsafe-payload',
    summary => 'Renewal confirmed',
    paid_through_effect => 'set',
    paid_through_date => date '2027-01-01',
    safe_kind => 'renewal_recorded',
    safe_payload => jsonb_build_object('private_reference', 'bank-ref-002')
  )$$,
  '23514',
  null,
  'a contractor-safe event cannot carry a field outside the safe allowlist'
);
select throws_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'refund_recorded',
    idempotency_key => 'commercial-test-orphan-refund',
    summary => 'Refund recorded',
    paid_through_effect => 'unchanged',
    private_reason => 'Customer refunded in full'
  )$$,
  '23514',
  null,
  'a refund must reference the original confirmation it corrects'
);
select throws_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'organization_suspended',
    idempotency_key => 'commercial-test-reasonless-suspension',
    summary => 'Suspended',
    paid_through_effect => 'unchanged',
    suspension_category => 'nonpayment'
  )$$,
  '23514',
  null,
  'a suspension requires a private reason'
);
select throws_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'organization_suspended',
    idempotency_key => 'commercial-test-uncategorised-suspension',
    summary => 'Suspended',
    paid_through_effect => 'unchanged',
    private_reason => 'Nonpayment after grace',
    suspension_category => 'unknown_category'
  )$$,
  '23514',
  null,
  'a suspension category must come from the approved list'
);
select throws_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'renewal_confirmed',
    idempotency_key => 'commercial-test-missing-paid-through',
    summary => 'Renewal confirmed',
    paid_through_effect => 'set'
  )$$,
  '23514',
  null,
  'a confirmed paid-through change requires the resulting date'
);
select throws_ok(
  $$select public.apply_organization_commercial_command(
    target_organization_id => '90000000-0000-0000-0000-0000000000a1',
    event_kind => 'commercial_timezone_changed',
    idempotency_key => 'commercial-test-bad-timezone',
    summary => 'Commercial timezone changed',
    paid_through_effect => 'unchanged',
    private_reason => 'Testing an invalid zone',
    commercial_timezone => 'Mars/Olympus'
  )$$,
  '23514',
  null,
  'an unrecognised commercial timezone is rejected'
);

select * from finish();
rollback;
