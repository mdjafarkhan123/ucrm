begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- Nothing outside the server may reach the window, the opener, or the sweep.
select is(
  has_function_privilege('anon',
    'private.current_communication_allowance_window(uuid, timestamptz)', 'execute'),
  false,
  'anonymous callers cannot resolve an allowance window'
);
select is(
  has_function_privilege('authenticated',
    'private.ensure_communication_allowance_periods(uuid, timestamptz)', 'execute'),
  false,
  'signed-in members cannot open an allowance period'
);
select is(
  has_function_privilege('service_role',
    'private.open_due_communication_allowance_periods()', 'execute'),
  false,
  'even the service role cannot run the sweep directly -- it is cron-owned'
);

set local role postgres;

-- Fixtures ---------------------------------------------------------------------------------------
-- Four organizations, one per access shape. Every window assertion passes an explicit `at`, so none of
-- them depend on the day this test happens to run.

insert into public.organizations (id, name, slug, lifecycle_status, created_at)
values
  ('90000000-0000-0000-0000-0000000009a1', 'Allowance Paid', 'allowance-paid', 'active',
    '2026-01-15 04:30:00+00'),
  ('90000000-0000-0000-0000-0000000009a2', 'Allowance Free', 'allowance-free', 'active',
    '2026-01-10 09:00:00+00'),
  ('90000000-0000-0000-0000-0000000009a3', 'Allowance Suspended', 'allowance-suspended', 'suspended',
    '2026-01-15 04:30:00+00'),
  ('90000000-0000-0000-0000-0000000009a4', 'Allowance No Access', 'allowance-no-access', 'active',
    '2026-01-15 04:30:00+00');

insert into public.organization_package_assignments (
  organization_id, package_version_id, effective_at, assignment_source, reason
)
select organization.id, version.id, '2026-01-15 05:00:00+00', 'provisioning',
  'Allowance period test baseline'
from (values
  ('90000000-0000-0000-0000-0000000009a1'::uuid),
  ('90000000-0000-0000-0000-0000000009a2'::uuid),
  ('90000000-0000-0000-0000-0000000009a3'::uuid),
  ('90000000-0000-0000-0000-0000000009a4'::uuid)
) as organization(id)
cross join lateral (
  select id from public.platform_package_versions
  where status = 'published'
  order by version_number, id
  limit 1
) as version;

select private.ensure_organization_commercial_rows('90000000-0000-0000-0000-0000000009a1');
select private.ensure_organization_commercial_rows('90000000-0000-0000-0000-0000000009a2');
select private.ensure_organization_commercial_rows('90000000-0000-0000-0000-0000000009a3');
select private.ensure_organization_commercial_rows('90000000-0000-0000-0000-0000000009a4');

update public.organization_commercial_settings
set commercial_timezone = 'Asia/Dhaka'
where organization_id = '90000000-0000-0000-0000-0000000009a1';

-- Paid, well inside its window. The suspended organization is paid too, so the only thing separating
-- them in the assertions below is lifecycle_status.
update public.organization_commercial_state
set paid_through_date = '2026-12-31',
    paid_through_source = 'renewal',
    grace_ends_at = '2027-01-08 00:00:00+00',
    grace_basis_timezone = 'UTC'
where organization_id in (
  '90000000-0000-0000-0000-0000000009a1',
  '90000000-0000-0000-0000-0000000009a3'
);

-- Free access only: no paid_through at all, which is precisely the shape a payment-triggered fix
-- would have starved.
insert into public.organization_free_access_events (
  id, organization_id, package_version_id, action, starts_at, access_until_date, reason,
  actor_owner_email, occurred_at
)
select '90000000-0000-0000-0000-0000000009b1', '90000000-0000-0000-0000-0000000009a2', version.id,
  'grant', '2026-01-10', '2026-12-31', 'Allowance period test grant', 'owner@example.test',
  '2026-01-10 09:30:00+00'
from (
  select id from public.platform_package_versions
  where status = 'published'
  order by version_number, id
  limit 1
) as version;

-- The window ---------------------------------------------------------------------------------------

-- Anchored on 2026-01-15 04:30 UTC, which is 2026-01-15 10:30 in Asia/Dhaka, so the anchor date is the
-- 15th and every window runs 15th 00:00 Dhaka to 15th 00:00 Dhaka -- 18:00 the previous day in UTC.
select is(
  (select window_starts_at from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a1', '2026-08-20 12:00:00+00')),
  '2026-08-14 18:00:00+00'::timestamptz,
  'the window starts on the anniversary day at local midnight, in the commercial timezone'
);
select is(
  (select window_ends_at from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a1', '2026-08-20 12:00:00+00')),
  '2026-09-14 18:00:00+00'::timestamptz,
  'the window is exactly one month long'
);
select is(
  (select window_starts_at from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a1', '2026-08-14 17:59:00+00')),
  '2026-07-14 18:00:00+00'::timestamptz,
  'a moment one minute before the boundary still resolves to the previous window'
);
select is(
  (select w.commercial_event_id is not distinct from state.last_event_id
   from private.current_communication_allowance_window(
     '90000000-0000-0000-0000-0000000009a1', '2026-08-20 12:00:00+00') as w,
     public.organization_commercial_state as state
   where state.organization_id = '90000000-0000-0000-0000-0000000009a1'),
  true,
  'the window carries the organization latest commercial event for audit'
);
select is(
  (select count(*)::integer from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a2', '2026-08-20 12:00:00+00')),
  1,
  'a free-access organization with no paid-through still has a window'
);
select is(
  (select count(*)::integer from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a3', '2026-08-20 12:00:00+00')),
  0,
  'a suspended organization has no window even though it is paid'
);
select is(
  (select count(*)::integer from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a4', '2026-08-20 12:00:00+00')),
  0,
  'an active organization with neither paid nor free access has no window'
);
select is(
  (select count(*)::integer from private.current_communication_allowance_window(
    '90000000-0000-0000-0000-0000000009a2', '2027-06-01 12:00:00+00')),
  0,
  'a free grant that has run out closes the window'
);

-- Opening it -----------------------------------------------------------------------------------------

select private.ensure_communication_allowance_periods(
  '90000000-0000-0000-0000-0000000009a1', '2026-08-20 12:00:00+00');

select is(
  (select count(*)::integer from public.communication_email_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a1'),
  1,
  'one call opens the email period'
);
select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a1'),
  1,
  'the same call opens the Website Chat period -- both channels, one command'
);

select private.ensure_communication_allowance_periods(
  '90000000-0000-0000-0000-0000000009a1', '2026-08-20 12:00:00+00');
select private.ensure_communication_allowance_periods(
  '90000000-0000-0000-0000-0000000009a1', '2026-09-01 00:00:00+00');

select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a1'),
  1,
  'calling again inside the same window is a no-op'
);

-- A period stored with a different starts_at that still covers the moment must also suppress the
-- insert, or an owner changing the commercial timezone would open a second, overlapping window and
-- hand the organization a fresh allowance mid-month.
update public.organization_commercial_settings
set commercial_timezone = 'America/New_York'
where organization_id = '90000000-0000-0000-0000-0000000009a1';
select private.ensure_communication_allowance_periods(
  '90000000-0000-0000-0000-0000000009a1', '2026-08-20 12:00:00+00');
select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a1'),
  1,
  'a changed commercial timezone never opens a second overlapping window'
);
update public.organization_commercial_settings
set commercial_timezone = 'Asia/Dhaka'
where organization_id = '90000000-0000-0000-0000-0000000009a1';

-- Month rollover -------------------------------------------------------------------------------------

select private.ensure_communication_allowance_periods(
  '90000000-0000-0000-0000-0000000009a1', '2026-09-20 12:00:00+00');

select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a1'),
  2,
  'the next month opens the next window'
);
select is(
  (select bool_and(next_period.starts_at = previous_period.ends_at)
   from public.website_chat_allowance_periods as previous_period
   join public.website_chat_allowance_periods as next_period
     on next_period.organization_id = previous_period.organization_id
    and next_period.starts_at > previous_period.starts_at
   where previous_period.organization_id = '90000000-0000-0000-0000-0000000009a1'),
  true,
  'consecutive windows meet exactly -- no gap and no overlap'
);

-- No access, nothing opened -------------------------------------------------------------------------

select private.ensure_communication_allowance_periods(
  '90000000-0000-0000-0000-0000000009a4', '2026-08-20 12:00:00+00');
select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a4'),
  0,
  'an organization with no access opens no period, so both channels stay fail-closed'
);

-- The commercial trigger -----------------------------------------------------------------------------

-- The free-access organization has had no commercial state change yet, so it has no period. Advancing
-- its projection the way every commercial command does must open one.
select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a2'),
  0,
  'the free-access organization starts with no period'
);

update public.organization_commercial_state
set state_version = state_version + 1
where organization_id = '90000000-0000-0000-0000-0000000009a2';

select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a2'),
  1,
  'advancing commercial state opens the Website Chat period'
);
select is(
  (select count(*)::integer from public.communication_email_allowance_periods
   where organization_id = '90000000-0000-0000-0000-0000000009a2'),
  1,
  'advancing commercial state opens the email period too'
);

-- The sweep --------------------------------------------------------------------------------------------

-- Organization a4 has no access and a3 is suspended, so neither can ever be satisfied; the sweep must
-- still leave them without a period rather than looping or failing.
select ok(
  private.open_due_communication_allowance_periods() >= 0,
  'the sweep runs over every active organization without failing'
);
select is(
  (select count(*)::integer from public.website_chat_allowance_periods
   where organization_id in (
     '90000000-0000-0000-0000-0000000009a3',
     '90000000-0000-0000-0000-0000000009a4'
   )),
  0,
  'the sweep opens nothing for a suspended or unpaid organization'
);

select * from finish();

rollback;
