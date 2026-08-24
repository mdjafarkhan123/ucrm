begin;

create extension if not exists pgtap with schema extensions;

select plan(33);

-- Fixtures are rolled back at the end of this file. Fixed IDs keep the assertions readable.
--
-- Written for `supabase test db`, which runs the file as one session. Development currently uses the
-- remote Supabase project with no local stack, so these assertions are verified there instead by running
-- the file inside a single transaction that is rolled back. Do not run it through a runner that executes
-- each statement separately: `set local role` does not survive that.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'settings-admin@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'settings-viewer@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'settings-outsider@example.test', 'test', now(), now(), now());

-- A stale save has to name a person, so the editor needs a readable name.
update public.profiles set full_name = 'Dana Admin' where id = 'c1000000-0000-0000-0000-000000000001';

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c2000000-0000-0000-0000-000000000001', 'Settings Test Co', 'settings-test-co', 'active'),
  ('c2000000-0000-0000-0000-000000000002', 'Other Co', 'settings-other-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'admin'),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'field'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Settings Test Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
   'c3000000-0000-0000-0000-000000000001', '1 Settings Way', 'Testville');

-- 1. A new organization has no hours and no opinion about them -----------------------------------------

select is(
  (select hours_mode from public.organization_settings
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  'not_configured',
  'a new organization starts with business hours unconfigured'
);

select is(
  (select count(*)::integer from public.organization_business_hours
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  0,
  'nothing seeds a working week on the organization behalf'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 2. Business Profile ------------------------------------------------------------------------------------

select is(
  public.save_organization_business_profile(
    'c2000000-0000-0000-0000-000000000001', 1, 'Settings Test Co', null, null, null, null,
    null, null, null, null, null, null, false, 'UTC', 'USD', true, true
  ) ->> 'status',
  'saved',
  'a profile with only a name plus confirmed timezone and currency saves'
);

select is(
  (select profile_revision from public.organization_settings
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  2,
  'only the profile counter moved'
);

select is(
  (select branding_revision || '/' || hours_revision from public.organization_settings
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  '1/1',
  'saving the profile leaves branding and hours untouched'
);

select is(
  (select timezone_confirmed_at is not null and currency_confirmed_at is not null
   from public.organization_settings where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  true,
  'confirming timezone and currency is recorded, not assumed'
);

select is(
  (select count(*)::integer from public.organization_settings_audit
   where organization_id = 'c2000000-0000-0000-0000-000000000001' and section = 'profile'),
  1,
  'confirming the timezone and currency is recorded as a change'
);

-- A second save from a page that still believes revision 1 is not a failure, and not an overwrite.
select is(
  public.save_organization_business_profile(
    'c2000000-0000-0000-0000-000000000001', 1, 'Renamed By The Stale Tab', null, null, null, null,
    null, null, null, null, null, null, false, 'UTC', 'USD', false, false
  ) ->> 'editor_name',
  'Dana Admin',
  'a stale save names the person who saved first instead of overwriting them'
);

select is(
  (select name from public.organizations where id = 'c2000000-0000-0000-0000-000000000001'),
  'Settings Test Co',
  'the stale save changed nothing'
);

select throws_ok(
  $$select public.save_organization_business_profile(
      'c2000000-0000-0000-0000-000000000001', 2, 'Settings Test Co', null, null, null, null,
      null, null, null, null, null, null, false, 'America/New_York', 'USD', false, true)$$,
  '23514', null, 'a timezone the person did not confirm is refused, never saved quietly'
);

select throws_ok(
  $$select public.save_organization_business_profile(
      'c2000000-0000-0000-0000-000000000001', 2, 'Settings Test Co', null, null, null, null,
      null, null, null, null, null, null, false, 'Mars/Olympus', 'USD', true, true)$$,
  '23514', null, 'a timezone Postgres does not know is refused'
);

-- 3. Currency locks on a shared Quote, not on a draft ---------------------------------------------------

select lives_ok(
  $$select public.create_quote('c3000000-0000-0000-0000-000000000001',
      'c4000000-0000-0000-0000-000000000001', 'Settings lock quote', 'Draft only.')$$,
  'a draft quote exists'
);

select is(
  public.organization_currency_is_locked('c2000000-0000-0000-0000-000000000001'),
  false,
  'a draft nobody has seen does not lock the currency'
);

select is(
  public.save_organization_business_profile(
    'c2000000-0000-0000-0000-000000000001', 2, 'Settings Test Co', null, null, null, null,
    null, null, null, null, null, null, false, 'UTC', 'CAD', true, true
  ) ->> 'status',
  'saved',
  'currency is still editable while every quote is an internal draft'
);

reset role;
update public.quotes set sent_at = now()
where organization_id = 'c2000000-0000-0000-0000-000000000001';
set local role authenticated;

select is(
  public.organization_currency_is_locked('c2000000-0000-0000-0000-000000000001'),
  true,
  'sending a quote to a customer locks the currency'
);

select throws_ok(
  $$select public.save_organization_business_profile(
      'c2000000-0000-0000-0000-000000000001', 3, 'Settings Test Co', null, null, null, null,
      null, null, null, null, null, null, false, 'UTC', 'EUR', true, true)$$,
  '23514', null, 'currency cannot change once a customer has the document'
);

-- 4. Business Hours states -------------------------------------------------------------------------------

select throws_ok(
  $$select public.save_organization_business_hours(
      'c2000000-0000-0000-0000-000000000001', 1, 'not_configured', null)$$,
  '23514', null, 'unconfigured is a starting state, not something to save'
);

-- Sunday closed, Monday split into three, Tuesday running past midnight, Wednesday all day.
select is(
  public.save_organization_business_hours('c2000000-0000-0000-0000-000000000001', 1, 'weekly', $json$[
    {"weekday": 0, "period_index": 0, "is_open": false},
    {"weekday": 1, "period_index": 0, "is_open": true, "opens_at": "08:00", "closes_at": "12:00"},
    {"weekday": 1, "period_index": 1, "is_open": true, "opens_at": "13:00", "closes_at": "17:00"},
    {"weekday": 1, "period_index": 2, "is_open": true, "opens_at": "18:00", "closes_at": "20:00"},
    {"weekday": 2, "period_index": 0, "is_open": true, "opens_at": "22:00", "closes_at": "02:00"},
    {"weekday": 3, "period_index": 0, "is_open": true, "is_open_24h": true},
    {"weekday": 4, "period_index": 0, "is_open": true, "opens_at": "08:00", "closes_at": "17:00"},
    {"weekday": 5, "period_index": 0, "is_open": true, "opens_at": "08:00", "closes_at": "17:00"},
    {"weekday": 6, "period_index": 0, "is_open": false}
  ]$json$::jsonb) ->> 'status',
  'saved',
  'split shifts, an overnight period, and an all-day day all save'
);

select is(
  (select count(*)::integer from public.organization_business_hours
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  9,
  'every period is stored as its own row'
);

select throws_ok(
  $$select public.save_organization_business_hours(
      'c2000000-0000-0000-0000-000000000001', 2, 'weekly', $json$[
        {"weekday": 0, "period_index": 0, "is_open": false},
        {"weekday": 1, "period_index": 0, "is_open": true, "opens_at": "08:00", "closes_at": "13:00"},
        {"weekday": 1, "period_index": 1, "is_open": true, "opens_at": "12:00", "closes_at": "17:00"},
        {"weekday": 2, "period_index": 0, "is_open": false},
        {"weekday": 3, "period_index": 0, "is_open": false},
        {"weekday": 4, "period_index": 0, "is_open": false},
        {"weekday": 5, "period_index": 0, "is_open": false},
        {"weekday": 6, "period_index": 0, "is_open": false}
      ]$json$::jsonb)$$,
  '23514', null, 'two periods on one day cannot overlap'
);

select throws_ok(
  $$select public.save_organization_business_hours(
      'c2000000-0000-0000-0000-000000000001', 2, 'weekly', $json$[
        {"weekday": 0, "period_index": 0, "is_open": false},
        {"weekday": 1, "period_index": 0, "is_open": true, "opens_at": "06:00", "closes_at": "08:00"},
        {"weekday": 1, "period_index": 1, "is_open": true, "opens_at": "09:00", "closes_at": "11:00"},
        {"weekday": 1, "period_index": 2, "is_open": true, "opens_at": "12:00", "closes_at": "14:00"},
        {"weekday": 1, "period_index": 3, "is_open": true, "opens_at": "15:00", "closes_at": "17:00"},
        {"weekday": 2, "period_index": 0, "is_open": false},
        {"weekday": 3, "period_index": 0, "is_open": false},
        {"weekday": 4, "period_index": 0, "is_open": false},
        {"weekday": 5, "period_index": 0, "is_open": false},
        {"weekday": 6, "period_index": 0, "is_open": false}
      ]$json$::jsonb)$$,
  '23514', null, 'a fourth period on one day is refused'
);

select throws_ok(
  $$select public.save_organization_business_hours(
      'c2000000-0000-0000-0000-000000000001', 2, 'weekly', $json$[
        {"weekday": 0, "period_index": 0, "is_open": false},
        {"weekday": 1, "period_index": 0, "is_open": false},
        {"weekday": 2, "period_index": 0, "is_open": false},
        {"weekday": 3, "period_index": 0, "is_open": false},
        {"weekday": 4, "period_index": 0, "is_open": false},
        {"weekday": 5, "period_index": 0, "is_open": false}
      ]$json$::jsonb)$$,
  '23514', null, 'a week missing a day is refused'
);

select throws_ok(
  $$select public.save_organization_business_hours(
      'c2000000-0000-0000-0000-000000000001', 2, 'weekly', $json$[
        {"weekday": 0, "period_index": 0, "is_open": false},
        {"weekday": 0, "period_index": 1, "is_open": true, "opens_at": "08:00", "closes_at": "17:00"},
        {"weekday": 1, "period_index": 0, "is_open": false},
        {"weekday": 2, "period_index": 0, "is_open": false},
        {"weekday": 3, "period_index": 0, "is_open": false},
        {"weekday": 4, "period_index": 0, "is_open": false},
        {"weekday": 5, "period_index": 0, "is_open": false},
        {"weekday": 6, "period_index": 0, "is_open": false}
      ]$json$::jsonb)$$,
  '23514', null, 'a closed day cannot also carry working hours'
);

select throws_ok(
  $$select public.save_organization_business_hours(
      'c2000000-0000-0000-0000-000000000001', 2, 'weekly', $json$[
        {"weekday": 0, "period_index": 0, "is_open": true, "is_open_24h": true,
         "opens_at": "08:00", "closes_at": "17:00"},
        {"weekday": 1, "period_index": 0, "is_open": false},
        {"weekday": 2, "period_index": 0, "is_open": false},
        {"weekday": 3, "period_index": 0, "is_open": false},
        {"weekday": 4, "period_index": 0, "is_open": false},
        {"weekday": 5, "period_index": 0, "is_open": false},
        {"weekday": 6, "period_index": 0, "is_open": false}
      ]$json$::jsonb)$$,
  '23514', null, 'open 24 hours is its own state and cannot carry times as well'
);

select is(
  public.save_organization_business_hours(
    'c2000000-0000-0000-0000-000000000001', 2, 'appointment_only', null
  ) ->> 'hours_mode',
  'appointment_only',
  'a business that only works by appointment can say so'
);

select is(
  (select count(*)::integer from public.organization_business_hours
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  0,
  'appointment only clears the weekly grid rather than leaving stale times behind'
);

-- 5. Branding ---------------------------------------------------------------------------------------------

select is(
  public.save_organization_branding('c2000000-0000-0000-0000-000000000001', 1, '#1F6FEB')
    ->> 'branding_revision',
  '2',
  'brand color saves on its own counter'
);

select is(
  public.set_organization_logo(
    'c2000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001/logo/first.png'
  ) ->> 'branding_revision',
  '3',
  'committing a logo moves the branding counter so a cached image is replaced'
);

select is(
  public.remove_organization_logo('c2000000-0000-0000-0000-000000000001') ->> 'previous_object_key',
  'c2000000-0000-0000-0000-000000000001/logo/first.png',
  'removing the logo hands back the object to tidy up later'
);

select throws_ok(
  $$select public.set_organization_logo('c2000000-0000-0000-0000-000000000001',
      'c2000000-0000-0000-0000-000000000002/logo/stolen.png')$$,
  '23514', null, 'a key belonging to another organization is refused'
);

-- 6. Permission and isolation -------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.save_organization_business_profile(
      'c2000000-0000-0000-0000-000000000001', 4, 'Field Person Rename', null, null, null, null,
      null, null, null, null, null, null, false, 'UTC', 'CAD', true, true)$$,
  '42501', null, 'a field member can read business settings but cannot change them'
);

select ok(
  (select count(*) from public.organization_settings_audit
   where organization_id = 'c2000000-0000-0000-0000-000000000001') > 0,
  'every contractor role can read the settings history of their own organization'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::integer from public.organization_settings
   where organization_id = 'c2000000-0000-0000-0000-000000000001'),
  0,
  'another organization sees none of these settings'
);

select * from finish();
rollback;
