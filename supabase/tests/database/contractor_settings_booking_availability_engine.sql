-- Contractor Settings Part 4B-2b: the availability/slot-computation engine.
-- Proves: get_form_available_slots honors business hours (weekly, appointment_only, not_configured), min
-- notice, slot interval/visit duration/buffer, member weekly availability and dated exceptions, existing
-- assessment/job-visit/schedule-event occupancy, permission enforcement, cross-tenant isolation, and
-- range-size guards; and that private.form_booking_reservations' exclusion constraint plus
-- public.claim_form_booking_reservation actually stop a double-booked person.
--
-- Every date-specific assertion below reuses the one Monday (2099-01-05) that has business hours configured,
-- and each numbered section restores the shared baseline before the next section relies on it: hours_mode
-- weekly with only Monday 9:00-12:00 open, min_notice/buffer at 0, a 30-minute slot interval, a 60-minute
-- visit, two active field members (0002, 0003) with no availability restriction and no occupancy, and an
-- owner (0001) fixed to never work the field (see the fixture note below) so owner presence never silently
-- covers a scenario meant to prove nobody is free.
--
-- Single-transaction run (Supabase MCP execute_sql or `supabase test db`); `set local role` must survive, so
-- do not run this through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

-- 1. Structure and least-privilege grants ------------------------------------------------------------------

select has_function('public', 'get_form_available_slots', 'the slot-finding function exists');
select has_function('public', 'claim_form_booking_reservation', 'the reservation-claim function exists');
select has_table('private', 'form_booking_reservations', 'the reservation table exists');
select is(
  (select count(*) from pg_constraint
   where conrelid = 'private.form_booking_reservations'::regclass and contype = 'x'),
  1::bigint,
  'the reservation table carries exactly one exclusion constraint'
);
select is(has_function_privilege('authenticated', 'public.get_form_available_slots(uuid,uuid,date,date)', 'execute'),
  true, 'a signed-in session may call the slot finder');
select is(has_function_privilege('anon', 'public.get_form_available_slots(uuid,uuid,date,date)', 'execute'),
  false, 'anon may not call the slot finder yet -- Part 4C adds the public-safe path');
select is(
  has_function_privilege('authenticated', 'public.claim_form_booking_reservation(uuid,uuid,uuid,timestamptz,timestamptz)', 'execute'),
  false, 'authenticated sessions cannot claim a reservation directly -- only Part 4D''s future service-role path will');

-- 2. Fixtures -------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('4b2b0000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'slots-owner@example.test', 'test', now(), now(), now()),
  ('4b2b0000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'slots-field-a@example.test', 'test', now(), now(), now()),
  ('4b2b0000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'slots-field-b@example.test', 'test', now(), now(), now()),
  ('4b2b0000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'slots-other-owner@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('4b2c0000-0000-0000-0000-000000000001', 'Slots Test Co', 'slots-test-co', 'active'),
  ('4b2c0000-0000-0000-0000-000000000002', 'Other Slots Co', 'slots-other-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000001', 'owner'),
  ('4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000002', 'field'),
  ('4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000003', 'field'),
  ('4b2c0000-0000-0000-0000-000000000002', '4b2b0000-0000-0000-0000-000000000004', 'owner');

-- A client + property, reused by the assessment fixture (section 9) and the job-visit fixture (section 12).
insert into public.clients (id, organization_id, display_name)
values ('4b2e0000-0000-0000-0000-000000000001', '4b2c0000-0000-0000-0000-000000000001', 'A Client');
insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, country)
values ('4b2e0000-0000-0000-0000-000000000002', '4b2c0000-0000-0000-0000-000000000001',
  '4b2e0000-0000-0000-0000-000000000001', '1 Main St', 'Town', 'ST', '00000', 'US');

-- The candidate pool is every active member with no role filter (see the migration header), and the owner is
-- an active member too. Without a stated pattern they would silently count as a free resource in every
-- "nobody is free" scenario below. A fixed "office-only, never in the field" weekly pattern keeps those
-- assertions honest, and is itself a realistic real-world case.
insert into public.organization_member_availability (organization_id, user_id, weekday, is_working)
select '4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000001', weekday, false
from generate_series(0, 6) as weekday;

-- 3. create the form and run the argument/permission guards under the real owner session -----------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '4b2b0000-0000-0000-0000-000000000001', true);

select public.create_form('4b2c0000-0000-0000-0000-000000000001', 'assessment', 'Assessment Form', 'Book us');

select throws_ok(
  $$select * from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-04'
  )$$,
  '23514', null, 'an end date before the start date is refused'
);

select throws_ok(
  $$select * from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-03-31'
  )$$,
  '23514', null, 'a window over 60 days is refused'
);

select public.create_form('4b2c0000-0000-0000-0000-000000000001', 'request', 'A Request Form', 'Tell us');
select throws_ok(
  $$select * from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'A Request Form'),
    date '2099-01-05', date '2099-01-05'
  )$$,
  '23514', null, 'a form with no booking rules cannot be asked for slots'
);

-- 4. hours_mode not_configured (the fresh default) offers nothing --------------------------------------------

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  0::bigint,
  'hours_mode not_configured (the default) offers no slots at all'
);

-- 5. weekly hours, no availability set, no occupancy: the shared baseline ---------------------------------------

set local role postgres;
update public.organization_settings set hours_mode = 'weekly'
where organization_id = '4b2c0000-0000-0000-0000-000000000001';

insert into public.organization_business_hours (organization_id, weekday, period_index, is_open, opens_at, closes_at)
values ('4b2c0000-0000-0000-0000-000000000001', 1, 0, true, time '09:00', time '12:00')
on conflict (organization_id, weekday, period_index) do update
  set is_open = excluded.is_open, opens_at = excluded.opens_at, closes_at = excluded.closes_at;

set local role authenticated;

select public.update_form_booking_settings(
  '4b2c0000-0000-0000-0000-000000000001',
  (select id from public.forms where name = 'Assessment Form'),
  1, false, false, 0, 30, 60, null, 0, '{}'::uuid[]
);

select is(
  (select array_agg(start_time order by start_time) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  array[time '09:00', time '09:30', time '10:00', time '10:30', time '11:00'],
  'a 9-12 Monday with a 60-minute visit and 30-minute interval offers five start times'
);

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-04', date '2099-01-04'
  )),
  0::bigint,
  'Sunday (no configured hours) offers nothing'
);

-- 6. min_notice_minutes pushes the earliest offered start later, then is reset for later sections --------------
-- 2099-01-05 is deliberately decades away so every other section is immune to today's real date, which also
-- means min_notice_minutes (capped at 43200 -- 30 days, see form_booking_rules_min_notice_minutes_check)
-- against that date can never do anything: "now() + 30 days" is still 70-odd years before it. So this one
-- assertion queries the nearest real Monday instead, where a 30-day notice genuinely pushes past the whole day.

set local role postgres;
update public.form_booking_rules set min_notice_minutes = 43200
where form_id = (select id from public.forms where name = 'Assessment Form');
set local role authenticated;

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    (current_date + ((1 - extract(dow from current_date)::int + 7) % 7))::date,
    (current_date + ((1 - extract(dow from current_date)::int + 7) % 7))::date
  )),
  0::bigint,
  'a minimum notice at the 30-day maximum leaves the nearest real Monday entirely unbookable'
);

set local role postgres;
update public.form_booking_rules set min_notice_minutes = 0
where form_id = (select id from public.forms where name = 'Assessment Form');
set local role authenticated;

-- 7. one member's own weekly availability restricts nothing while a second, unrestricted member covers -------

set local role postgres;
insert into public.organization_member_availability (organization_id, user_id, weekday, is_working, starts_at, ends_at)
select '4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000002', weekday,
  weekday between 1 and 5, case when weekday between 1 and 5 then time '10:00' end,
  case when weekday between 1 and 5 then time '11:00' end
from generate_series(0, 6) as weekday;
set local role authenticated;

select is(
  (select array_agg(start_time order by start_time) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  array[time '09:00', time '09:30', time '10:00', time '10:30', time '11:00'],
  'a member restricted to 10-11 does not shrink the list while an unrestricted second member covers every slot'
);

set local role postgres;
delete from public.organization_member_availability
where organization_id = '4b2c0000-0000-0000-0000-000000000001'
  and user_id = '4b2b0000-0000-0000-0000-000000000002';
set local role authenticated;

-- 8. with only one member active, a dated exception removes them for that day only -----------------------------

set local role postgres;
delete from public.organization_members where organization_id = '4b2c0000-0000-0000-0000-000000000001'
  and user_id = '4b2b0000-0000-0000-0000-000000000003';
insert into public.organization_member_availability_exceptions (
  organization_id, user_id, exception_date, is_working, reason
) values (
  '4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000002', date '2099-01-05', false, 'Leave'
);
set local role authenticated;

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  0::bigint,
  'the only active member being on a dated exception day off leaves nothing bookable'
);

set local role postgres;
delete from public.organization_member_availability_exceptions
where organization_id = '4b2c0000-0000-0000-0000-000000000001';
set local role authenticated;

select is(
  (select array_agg(start_time order by start_time) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  array[time '09:00', time '09:30', time '10:00', time '10:30', time '11:00'],
  'removing the exception (nobody has said again) restores every slot -- it was dated, not permanent'
);

set local role postgres;
insert into public.organization_members (organization_id, user_id, role)
values ('4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000003', 'field');
set local role authenticated;

-- 9. an existing assessment blocks its assignee, padded by buffer, unless a second member is free -------------

set local role postgres;
update public.form_booking_rules set buffer_minutes = 30
where form_id = (select id from public.forms where name = 'Assessment Form');

insert into public.requests (id, organization_id, client_id, property_id, title, status)
values (
  '4b2d0000-0000-0000-0000-000000000002', '4b2c0000-0000-0000-0000-000000000001',
  '4b2e0000-0000-0000-0000-000000000001', '4b2e0000-0000-0000-0000-000000000002',
  'Existing booking', 'unscheduled'
);

insert into public.assessments (id, organization_id, request_id, starts_at, ends_at)
values (
  '4b2d0000-0000-0000-0000-000000000001', '4b2c0000-0000-0000-0000-000000000001',
  '4b2d0000-0000-0000-0000-000000000002', timestamptz '2099-01-05 10:00:00+00', timestamptz '2099-01-05 11:00:00+00'
);

insert into public.assessment_assignees (organization_id, assessment_id, user_id)
values ('4b2c0000-0000-0000-0000-000000000001', '4b2d0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000002');
set local role authenticated;

select is(
  (select array_agg(start_time order by start_time) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  array[time '09:00', time '09:30', time '10:00', time '10:30', time '11:00'],
  'the busy member''s own booking does not remove any slot while a second, unbooked member is free to cover it'
);

set local role postgres;
delete from public.organization_members where organization_id = '4b2c0000-0000-0000-0000-000000000001'
  and user_id = '4b2b0000-0000-0000-0000-000000000003';
set local role authenticated;

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  0::bigint,
  'with only the busy member active, the padded 9:30-11:30 buffer overlaps every 60-minute slot in the 9-12 window'
);

set local role postgres;
insert into public.organization_members (organization_id, user_id, role)
values ('4b2c0000-0000-0000-0000-000000000001', '4b2b0000-0000-0000-0000-000000000003', 'field');
set local role authenticated;

-- 10. a timed whole-team schedule event removes just its own padded window, for everybody -----------------------
-- (the busy/buffered member and the assessment from section 9 are both still in effect here)

set local role postgres;
insert into public.schedule_events (organization_id, title, event_date, start_time, end_time)
values ('4b2c0000-0000-0000-0000-000000000001', 'Team huddle', date '2099-01-05', time '09:00', time '09:30');
set local role authenticated;

select is(
  (select array_agg(start_time order by start_time) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  array[time '10:00', time '10:30', time '11:00'],
  'the padded 8:30-10:00 team huddle removes the 09:00 and 09:30 starts for everybody; the free second member still covers 10:00 onward'
);

set local role postgres;
delete from public.schedule_events where organization_id = '4b2c0000-0000-0000-0000-000000000001';

-- 11. an anytime (whole-day) team event closes the entire day, even though a member would otherwise be free ----

insert into public.schedule_events (organization_id, title, event_date, all_day)
values ('4b2c0000-0000-0000-0000-000000000001', 'Company holiday', date '2099-01-05', true);
set local role authenticated;

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  0::bigint,
  'an anytime team event closes its whole day, even though a second member is otherwise free'
);

-- Back to the shared baseline for the remaining sections.
set local role postgres;
delete from public.schedule_events where organization_id = '4b2c0000-0000-0000-0000-000000000001';
delete from public.assessment_assignees where organization_id = '4b2c0000-0000-0000-0000-000000000001';
delete from public.assessments where organization_id = '4b2c0000-0000-0000-0000-000000000001';
update public.form_booking_rules set buffer_minutes = 0
where form_id = (select id from public.forms where name = 'Assessment Form');

-- 12. an anytime (no start_time) job visit does not block a specific timed slot ---------------------------------

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, status, price_basis, currency_code
) values (
  '4b2e0000-0000-0000-0000-000000000003', '4b2c0000-0000-0000-0000-000000000001',
  '4b2e0000-0000-0000-0000-000000000001', '4b2e0000-0000-0000-0000-000000000002',
  1, 'A Job', 'one_off', 'active', 'job_total', 'USD'
);
insert into public.job_visits (id, organization_id, job_id, position, visit_date, all_day)
values (
  '4b2e0000-0000-0000-0000-000000000004', '4b2c0000-0000-0000-0000-000000000001',
  '4b2e0000-0000-0000-0000-000000000003', 0, date '2099-01-05', true
);
insert into public.job_visit_assignments (organization_id, job_id, visit_id, user_id)
values (
  '4b2c0000-0000-0000-0000-000000000001', '4b2e0000-0000-0000-0000-000000000003',
  '4b2e0000-0000-0000-0000-000000000004', '4b2b0000-0000-0000-0000-000000000002'
);
set local role authenticated;

select is(
  (select array_agg(start_time order by start_time) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )),
  array[time '09:00', time '09:30', time '10:00', time '10:30', time '11:00'],
  'an anytime job visit (no start_time) claims no specific hour, so it blocks nothing'
);

-- 13. appointment_only ignores business hours and offers far more of the day than the 9-12 band ------------------

set local role postgres;
update public.organization_settings set hours_mode = 'appointment_only'
where organization_id = '4b2c0000-0000-0000-0000-000000000001';
set local role authenticated;

select is(
  (select count(*) from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )) > 5,
  true,
  'appointment_only offers times well outside the 9-12 business-hours band'
);

set local role postgres;
update public.organization_settings set hours_mode = 'not_configured'
where organization_id = '4b2c0000-0000-0000-0000-000000000001';

-- 14. cross-tenant isolation --------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '4b2b0000-0000-0000-0000-000000000004', true);

select throws_ok(
  $$select * from public.get_form_available_slots(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    date '2099-01-05', date '2099-01-05'
  )$$,
  '42501', null, 'an owner of another organization cannot read this organization''s slots'
);

-- 15. the double-booking-safe reservation primitive ------------------------------------------------------------

set local role postgres;

select is(
  public.claim_form_booking_reservation(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    '4b2b0000-0000-0000-0000-000000000002',
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  ) is not null,
  true,
  'the first claim on a window succeeds'
);

select is(
  public.claim_form_booking_reservation(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    '4b2b0000-0000-0000-0000-000000000002',
    timestamptz '2099-01-05 09:30:00+00', timestamptz '2099-01-05 10:30:00+00'
  ),
  null,
  'a second, overlapping claim on the same person is refused with null, not an error'
);

select is(
  public.claim_form_booking_reservation(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    '4b2b0000-0000-0000-0000-000000000002',
    timestamptz '2099-01-05 10:00:00+00', timestamptz '2099-01-05 11:00:00+00'
  ) is not null,
  true,
  'a back-to-back, non-overlapping claim on the same person succeeds'
);

select is(
  public.claim_form_booking_reservation(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    '4b2b0000-0000-0000-0000-000000000003',
    timestamptz '2099-01-05 09:00:00+00', timestamptz '2099-01-05 10:00:00+00'
  ) is not null,
  true,
  'the same window overlapping a different person succeeds -- parallel work is not a conflict'
);

select throws_ok(
  $$select public.claim_form_booking_reservation(
    '4b2c0000-0000-0000-0000-000000000001',
    (select id from public.forms where name = 'Assessment Form'),
    '4b2b0000-0000-0000-0000-000000000002',
    timestamptz '2099-01-06 10:00:00+00', timestamptz '2099-01-06 09:00:00+00'
  )$$,
  '23514', null, 'a reservation that would end before it starts is refused outright'
);

select is(
  (select count(*) from private.form_booking_reservations),
  3::bigint,
  'exactly the three successful claims were persisted'
);

select * from finish();
rollback;
