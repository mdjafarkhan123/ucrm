-- Contractor Settings Part 4B-2a: booking-rule settings foundation for assessment/job forms.
-- Proves: create_form seeds/omits a booking-rules row by outcome, update_form_booking_settings validates and
-- saves rules + bookable services together, stale-revision (P0409) rejection, the outcome guard (a 'request'
-- form never gets booking rules), the service-area-needs-location guard, bookable-service validation, least-
-- privilege grants, cross-tenant RLS isolation, the organization geocoding claim/finalize queue, and the
-- service-area-radius Business Profile command including its 'stale' (not P0409) convention.
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive, so
-- do not run this through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- 1. Structure and least-privilege grants ------------------------------------------------------------------

select has_table('public', 'form_booking_rules', 'the form_booking_rules table exists');
select has_table('public', 'form_bookable_services', 'the form_bookable_services table exists');
select is((select relrowsecurity from pg_class where oid = 'public.form_booking_rules'::regclass), true,
  'RLS is enabled on form_booking_rules');
select is((select relrowsecurity from pg_class where oid = 'public.form_bookable_services'::regclass), true,
  'RLS is enabled on form_bookable_services');
select is(has_table_privilege('authenticated', 'public.form_booking_rules', 'select'), true,
  'a signed-in session may read booking rules');
select is(has_table_privilege('authenticated', 'public.form_booking_rules', 'update'), false,
  'a signed-in session may not write booking rules directly (writes go through definer commands)');
select is(has_table_privilege('authenticated', 'public.form_bookable_services', 'insert'), false,
  'a signed-in session may not write bookable services directly');

-- 2. Fixtures -------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('fb2a0000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'booking-owner@example.test', 'test', now(), now(), now()),
  ('fb2a0000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'booking-field@example.test', 'test', now(), now(), now()),
  ('fb2a0000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'booking-other-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('fb2b0000-0000-0000-0000-000000000001', 'Booking Test Co', 'booking-test-co', 'active'),
  ('fb2b0000-0000-0000-0000-000000000002', 'Other Booking Co', 'booking-other-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('fb2b0000-0000-0000-0000-000000000001', 'fb2a0000-0000-0000-0000-000000000001', 'owner'),
  ('fb2b0000-0000-0000-0000-000000000001', 'fb2a0000-0000-0000-0000-000000000002', 'field'),
  ('fb2b0000-0000-0000-0000-000000000002', 'fb2a0000-0000-0000-0000-000000000003', 'owner');

insert into public.catalog_items (id, organization_id, category, name, is_taxable)
values
  ('fb2c0000-0000-0000-0000-000000000001', 'fb2b0000-0000-0000-0000-000000000001', 'service', 'Drain Cleaning', true),
  ('fb2c0000-0000-0000-0000-000000000002', 'fb2b0000-0000-0000-0000-000000000001', 'service', 'Pipe Inspection', true),
  ('fb2c0000-0000-0000-0000-000000000003', 'fb2b0000-0000-0000-0000-000000000002', 'service', 'Other Org Service', true);

update public.catalog_items set archived_at = now()
where id = 'fb2c0000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fb2a0000-0000-0000-0000-000000000001', true);

-- 3. create_form seeds a booking-rules row only for assessment/job -------------------------------------------

select public.create_form('fb2b0000-0000-0000-0000-000000000001', 'request', 'A Request Form', 'a-request-form', 'Tell us');
select public.create_form('fb2b0000-0000-0000-0000-000000000001', 'assessment', 'An Assessment Form', 'an-assessment-form', 'Book us');

select is(
  (select count(*) from public.form_booking_rules
   where form_id = (select id from public.forms where name = 'A Request Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  0::bigint,
  'a request form never gets a booking-rules row'
);

select is(
  (select requires_booking_approval from public.form_booking_rules
   where form_id = (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  true,
  'a new assessment form defaults to requiring booking approval, matching Jobber'
);

select is(
  (select revision from public.form_booking_rules
   where form_id = (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  1,
  'a new booking-rules row starts at revision 1'
);

-- 4. update_form_booking_settings: happy path, ordering, revision bump ----------------------------------------

select is(
  public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    1, false, false, 60, 15, 45, 120, 30,
    array['fb2c0000-0000-0000-0000-000000000001'::uuid]
  ) ->> 'revision',
  '2',
  'a valid save bumps the revision'
);

select is(
  (select array_agg(catalog_item_id order by position) from public.form_bookable_services
   where form_id = (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  array['fb2c0000-0000-0000-0000-000000000001'::uuid],
  'the chosen service is saved against the form'
);

select is(
  (select visit_duration_minutes from public.form_booking_rules
   where form_id = (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  45,
  'visit duration is saved'
);

-- 5. Guards ------------------------------------------------------------------------------------------------

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    1, false, false, 60, 15, 45, 120, 30, '{}'::uuid[]
  )$$,
  'P0409', null, 'a stale revision is rejected'
);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'A Request Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    1, false, false, 60, 15, 45, 120, 30, '{}'::uuid[]
  )$$,
  '23514', null, 'a request form is refused before any revision check -- it has no booking rules to edit'
);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, true, 60, 15, 45, 120, 30, '{}'::uuid[]
  )$$,
  '23514', null, 'turning on the service area before a business location and radius exist is refused'
);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, false, 60, 15, 45, 120, 30,
    array['fb2c0000-0000-0000-0000-000000000002'::uuid]
  )$$,
  '23514', null, 'an archived service cannot be offered on the form'
);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, false, 60, 15, 45, 120, 30,
    array['fb2c0000-0000-0000-0000-000000000003'::uuid]
  )$$,
  '23514', null, 'a service from another organization cannot be offered on the form'
);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, false, 50000, 15, 45, 120, 30, '{}'::uuid[]
  )$$,
  '23514', null, 'minimum notice above 30 days is refused'
);

-- 6. Permission enforcement ------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'fb2a0000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, false, 60, 15, 45, 120, 30, '{}'::uuid[]
  )$$,
  '42501', null, 'a field member without settings.forms.manage cannot save booking settings'
);

select is(
  (select count(*) from public.form_booking_rules
   where form_id = (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  0::bigint,
  'a field member has no settings.forms.manage, so RLS hides the booking rules row from them too'
);

-- 7. Cross-tenant isolation --------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'fb2a0000-0000-0000-0000-000000000003', true);

select is(
  (select count(*) from public.form_booking_rules
   where form_id = (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001')),
  0::bigint,
  'a member of another organization cannot see the first organization''s booking rules'
);

select throws_ok(
  $$select public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, false, 60, 15, 45, 120, 30, '{}'::uuid[]
  )$$,
  '42501', null, 'an owner of another organization cannot save booking settings on this one'
);

set local role postgres;
reset request.jwt.claim.sub;

-- 8. Organization geocoding queue ---------------------------------------------------------------------------

select is(
  (select location_geocode_status from public.organization_settings
   where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
  'pending',
  'a business with no address starts pending, same as an ungeocoded property'
);

-- This is a shared database with real, pre-existing organizations that also started 'pending' the moment
-- this migration's default landed on them. Parking them as 'succeeded' for the length of this rolled-back
-- transaction makes the claim below deterministic without touching any real data permanently.
update public.organization_settings
set location_geocode_status = 'succeeded'
where location_geocode_status = 'pending'
  and organization_id <> 'fb2b0000-0000-0000-0000-000000000001';

update public.organization_settings
set address_line1 = '1 Main St', city = 'Springfield', region = 'IL', postal_code = '62704'
where organization_id = 'fb2b0000-0000-0000-0000-000000000001';

select is(
  (select organization_id from public.claim_pending_organization_for_geocoding()),
  'fb2b0000-0000-0000-0000-000000000001',
  'the worker claims the organization with a pending address'
);

select is(
  public.finalize_organization_geocode(
    'fb2b0000-0000-0000-0000-000000000001', '1 Main St', 'Springfield', 'IL', '62704',
    'succeeded', 39.78, -89.65
  ),
  true,
  'finalize records a successful geocode'
);

select is(
  (select latitude from public.organization_settings
   where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
  39.78,
  'latitude is stored'
);
select is(
  (select longitude from public.organization_settings
   where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
  -89.65,
  'longitude is stored'
);
select is(
  (select location_geocode_status from public.organization_settings
   where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
  'succeeded',
  'geocode status is stored'
);

select is(
  public.finalize_organization_geocode(
    'fb2b0000-0000-0000-0000-000000000001', '1 Main St', 'Springfield', 'IL', '62704',
    'succeeded', 1, 1
  ),
  false,
  'finalize is a no-op once the row is no longer pending -- a stale result cannot overwrite it'
);

update public.organization_settings
set address_line2 = 'Suite 2'
where organization_id = 'fb2b0000-0000-0000-0000-000000000001';

select is(
  (select latitude from public.organization_settings
   where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
  null::numeric,
  'editing the address clears the stored latitude'
);
select is(
  (select location_geocode_status from public.organization_settings
   where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
  'pending',
  'editing the address re-queues geocoding'
);

-- 9. update_organization_service_area_radius ---------------------------------------------------------------

update public.organization_settings
set latitude = 39.78, longitude = -89.65, location_geocode_status = 'succeeded'
where organization_id = 'fb2b0000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fb2a0000-0000-0000-0000-000000000001', true);

select is(
  public.update_organization_service_area_radius(
    'fb2b0000-0000-0000-0000-000000000001',
    (select profile_revision from public.organization_settings
     where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    25
  ) ->> 'status',
  'saved',
  'a valid radius save succeeds'
);

select is(
  public.update_organization_service_area_radius('fb2b0000-0000-0000-0000-000000000001', 1, 25) ->> 'status',
  'stale',
  'a stale profile_revision returns a stale status, matching the rest of Business Profile, not a thrown P0409'
);

select throws_ok(
  $$select public.update_organization_service_area_radius(
    'fb2b0000-0000-0000-0000-000000000001',
    (select profile_revision from public.organization_settings
     where organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    600
  )$$,
  '23514', null, 'a radius above 500 miles is refused'
);

-- Now the service area can actually be turned on for the assessment form.
select is(
  public.update_form_booking_settings(
    'fb2b0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'An Assessment Form' and organization_id = 'fb2b0000-0000-0000-0000-000000000001'),
    2, false, true, 60, 15, 45, 120, 30, '{}'::uuid[]
  ) ->> 'service_area_enabled',
  'true',
  'once location and radius exist, the form can turn the service area on'
);

select set_config('request.jwt.claim.sub', 'fb2a0000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.update_organization_service_area_radius('fb2b0000-0000-0000-0000-000000000001', 2, 25)$$,
  '42501', null, 'a field member without settings.business.edit cannot change the service area radius'
);

select * from finish();
rollback;
