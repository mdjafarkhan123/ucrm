-- Communications A2 / Stage 2C (part 3): SMS readiness and registration. The effective SMS mode is the chosen
-- mode capped by the package ceiling unless Jafar overrides it; a registration moves waiting_for_info ->
-- under_review -> approved | action_needed with an immutable history; the plain readiness state is computed from
-- the mode, the registration and whether a live SMS-capable number is attached.
begin;

create extension if not exists pgtap with schema extensions;
select plan(53);

-- Shape and access boundary: registrations.
select has_table('public', 'communication_sms_registrations',
  'registrations are a first-class record');
select col_is_pk('public', 'communication_sms_registrations', 'id',
  'each registration has a stable identity');
select has_index('public', 'communication_sms_registrations',
  'communication_sms_registrations_org_idx',
  'a bounded index backs one organization''s registrations');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_registrations'::regclass),
  'registrations keep row-level security enabled');
select table_privs_are('public', 'communication_sms_registrations', 'authenticated', array[]::text[],
  'authenticated clients have no direct registration privileges');
select table_privs_are('public', 'communication_sms_registrations', 'anon', array[]::text[],
  'anonymous clients have no direct registration privileges');
select table_privs_are('public', 'communication_sms_registrations', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE'],
  'the server role reads/writes registrations directly but never deletes');

-- Shape and access boundary: registration history is append-only.
select has_table('public', 'communication_sms_registration_events',
  'registration history is a first-class record');
select has_index('public', 'communication_sms_registration_events',
  'communication_sms_registration_events_history_idx',
  'a bounded ordered index backs one registration''s history');
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.communication_sms_registration_events'::regclass),
  'registration history keeps row-level security enabled');
select table_privs_are('public', 'communication_sms_registration_events', 'service_role',
  array['SELECT', 'INSERT'],
  'registration history is append-only: the server role may read and insert but never update or delete');

-- Shape and access boundary: org modes.
select has_table('public', 'communication_sms_org_modes',
  'org SMS modes are a first-class record');
select col_is_pk('public', 'communication_sms_org_modes', 'organization_id',
  'each organization has at most one SMS mode row');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.communication_sms_org_modes'::regclass),
  'org SMS modes keep row-level security enabled');
select table_privs_are('public', 'communication_sms_org_modes', 'service_role',
  array['SELECT', 'INSERT', 'UPDATE'],
  'the server role reads/writes org SMS modes directly but never deletes');

-- Capabilities live on the sender identity record.
select has_column('public', 'communication_sms_sender_identities', 'capable_sms',
  'supported sender capabilities are stored on the sender identity');
select has_column('public', 'communication_sms_sender_identities', 'registration_id',
  'a sender identity records the registration it belongs to');

-- Fixtures: two isolated organizations and a stable actor id.
insert into public.organizations (id, name, slug, lifecycle_status) values
  ('b2c30000-0000-4000-8000-000000000001', 'Ready Org A', 'ready-org-a', 'active'),
  ('b2c30000-0000-4000-8000-000000000002', 'Ready Org B', 'ready-org-b', 'active');

-- Effective mode: no configured row means SMS is off (not included).
select is(
  public.communication_sms_effective_mode('b2c30000-0000-4000-8000-000000000001'),
  'off',
  'an organization with no configured mode has SMS off');
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'not_included',
  'readiness is not_included while the effective mode is off');

-- Enabling the mode: chosen operational within an operational package resolves to operational.
select is(
  (public.communication_sms_set_org_mode(
    'b2c30000-0000-4000-8000-000000000001', 'b2c3ac70-0000-4000-8000-000000000001',
    'operational', 'operational')).chosen_mode,
  'operational',
  'setting the org mode records the chosen mode');
select is(
  public.communication_sms_effective_mode('b2c30000-0000-4000-8000-000000000001'),
  'operational',
  'chosen operational within an operational package is effective operational');

-- A chosen mode above the package ceiling is refused.
select throws_ok(
  $$select public.communication_sms_set_org_mode(
    'b2c30000-0000-4000-8000-000000000002', null, 'off', 'operational')$$,
  'P0001', null,
  'a chosen mode above the package ceiling is refused');

-- The Jafar override takes precedence over the package/chosen result, up or down.
select is(
  (public.communication_sms_set_org_mode(
    'b2c30000-0000-4000-8000-000000000002', null, 'off', 'off')).package_max_mode,
  'off',
  'org B is configured with an off package and off choice');
select is(
  public.communication_sms_effective_mode('b2c30000-0000-4000-8000-000000000002'),
  'off',
  'org B with off package/choice is effectively off');
select is(
  (public.communication_sms_set_org_mode(
    'b2c30000-0000-4000-8000-000000000002', null, null, null, 'operational', 'reasoned exception')).override_mode,
  'operational',
  'an override can be recorded above the package ceiling');
select is(
  public.communication_sms_effective_mode('b2c30000-0000-4000-8000-000000000002'),
  'operational',
  'the override takes precedence over the off package/choice');
select is(
  (public.communication_sms_set_org_mode(
    'b2c30000-0000-4000-8000-000000000002', null, null, null, null, null, true)).override_mode,
  null,
  'clearing the override removes it');
select is(
  public.communication_sms_effective_mode('b2c30000-0000-4000-8000-000000000002'),
  'off',
  'with the override cleared the effective mode drops back to the off package result');

-- Registration lifecycle for org A. With the mode on but no registration, readiness needs setup.
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'needs_setup',
  'readiness is needs_setup when the mode is on but no registration exists');

select is(
  (public.communication_sms_start_registration(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care',
    'b2c3ac70-0000-4000-8000-000000000001')).status,
  'waiting_for_info',
  'starting a registration opens it waiting for information');

-- Starting again reuses the same row and keeps the history (started + info_updated = two events).
select is(
  (public.communication_sms_start_registration(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).status,
  'waiting_for_info',
  'starting an existing registration reuses the current row');
select is(
  (select count(*)::int from public.communication_sms_registration_events e
   join public.communication_sms_registrations r on r.id = e.registration_id
   where r.organization_id = 'b2c30000-0000-4000-8000-000000000001'),
  2,
  'both the start and the repeat are recorded in the immutable history');

select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'waiting_for_info',
  'readiness reflects a registration still waiting for information');

-- Submit for review.
select is(
  (public.communication_sms_submit_registration(
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
    'b2c3ac70-0000-4000-8000-000000000001', 'BN1234567890abcdef')).status,
  'under_review',
  'attesting and submitting moves the registration under review');
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'under_review',
  'readiness reflects a registration under review');

-- A registration under review cannot be submitted again.
select throws_ok(
  format($$select public.communication_sms_submit_registration(%L, %L)$$,
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
    'b2c3ac70-0000-4000-8000-000000000001'),
  'P0001', null,
  'a registration under review cannot be submitted again');

-- A safe rejection: action_needed with the required fixes.
select is(
  (public.communication_sms_record_registration_outcome(
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
    'action_needed', 'b2c3ac70-0000-4000-8000-000000000001', null, 'Add a valid opt-in sample message')).status,
  'action_needed',
  'a rejected registration comes back as action_needed with the fixes');
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'action_needed',
  'readiness reflects a registration needing correction');

-- Correcting and resubmitting clears the fixes and returns it to review.
select is(
  (public.communication_sms_submit_registration(
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
    'b2c3ac70-0000-4000-8000-000000000001')).required_fixes,
  null,
  'resubmitting a corrected registration clears the required fixes');

-- Approval requires a provider outcome.
select throws_ok(
  format($$select public.communication_sms_record_registration_outcome(%L, 'approved', null, null)$$,
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001')),
  'P0001', null,
  'an approved registration must record a provider outcome');

select is(
  (public.communication_sms_record_registration_outcome(
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
    'approved', 'b2c3ac70-0000-4000-8000-000000000001', 'Carrier approved use case')).status,
  'approved',
  'a registration with a provider outcome is approved');

-- Approved with no live sender is finishing setup, not ready.
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'finishing_setup',
  'an approved registration with no live number is still finishing setup');

-- Attaching a live SMS-capable number makes it ready.
insert into public.communication_sms_sender_identities (id, organization_id, phone_number)
values ('b2c35e10-0000-4000-8000-000000000001', 'b2c30000-0000-4000-8000-000000000001', '+14155550111');
select is(
  (public.communication_sms_set_sender_capabilities(
    'b2c35e10-0000-4000-8000-000000000001', 'US', 'long_code', true, false, false,
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'))).capable_sms,
  true,
  'recording capabilities marks the number SMS-capable');
update public.communication_sms_sender_identities
  set lifecycle_state = 'ready'
  where id = 'b2c35e10-0000-4000-8000-000000000001';
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).readiness_state,
  'ready',
  'an approved registration with a live SMS-capable number is ready');
select is(
  (public.communication_sms_readiness(
    'b2c30000-0000-4000-8000-000000000001', 'US', 'long_code', 'customer_care')).live_sender_count,
  1,
  'readiness counts the live SMS-capable numbers on the registration');

-- A pending outcome can only be decided from under_review.
select throws_ok(
  format($$select public.communication_sms_record_registration_outcome(%L, 'approved',
    null, 'again')$$,
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001')),
  'P0001', null,
  'an already-approved registration has no pending review to decide');

-- Recording a readiness check logs history without changing status.
select is(
  (public.communication_sms_record_registration_check(
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
    'b2c3ac70-0000-4000-8000-000000000001')).status,
  'approved',
  'a readiness check leaves the registration status unchanged');
select is(
  (select count(*)::int from public.communication_sms_registration_events e
   where e.event_type = 'readiness_checked'
     and e.organization_id = 'b2c30000-0000-4000-8000-000000000001'),
  1,
  'the readiness check is recorded in history');

-- Cross-tenant safety: a number cannot be linked to another organization's registration.
insert into public.communication_sms_sender_identities (id, organization_id, phone_number)
values ('b2c35e10-0000-4000-8000-000000000002', 'b2c30000-0000-4000-8000-000000000002', '+14155550222');
select throws_ok(
  format($$select public.communication_sms_set_sender_capabilities(
    'b2c35e10-0000-4000-8000-000000000002', 'US', 'long_code', true, false, false, %L)$$,
    (select id from public.communication_sms_registrations
     where organization_id = 'b2c30000-0000-4000-8000-000000000001')),
  '23503', null,
  'a number cannot be linked to another organization''s registration');

-- Value guards.
select throws_ok(
  $$insert into public.communication_sms_registrations
    (organization_id, country_code, sender_type, use_case, status)
    values ('b2c30000-0000-4000-8000-000000000002', 'US', 'long_code', 'care', 'under_review')$$,
  '23514', null,
  'an under_review registration must carry its submission evidence');
select throws_ok(
  $$insert into public.communication_sms_registrations
    (organization_id, country_code, sender_type, use_case)
    values ('b2c30000-0000-4000-8000-000000000002', 'usa', 'long_code', 'care')$$,
  '23514', null,
  'a registration country must be a two-letter uppercase code');
select throws_ok(
  $$insert into public.communication_sms_registrations
    (organization_id, country_code, sender_type, use_case)
    values ('b2c30000-0000-4000-8000-000000000002', 'US', 'pigeon', 'care')$$,
  '23514', null,
  'a registration sender type must be a supported sender kind');
select throws_ok(
  $$insert into public.communication_sms_registration_events
    (registration_id, organization_id, event_type)
    values (
      (select id from public.communication_sms_registrations
       where organization_id = 'b2c30000-0000-4000-8000-000000000001'),
      'b2c30000-0000-4000-8000-000000000001', 'exploded')$$,
  '23514', null,
  'a history event must be a supported event type');

select * from finish();
rollback;
