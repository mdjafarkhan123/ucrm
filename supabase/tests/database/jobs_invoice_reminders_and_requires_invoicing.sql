-- Jobs, Part 11b: invoice reminders and the Requires invoicing derived status.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention the other jobs tests document. Do not run it
-- through a runner that executes each statement separately: `set local role` and `set_config` do not survive
-- that. Dates are read relative to the clock (current_date / private.month_end_of) so the file does not rot,
-- except the pure derived-status matrix, which passes an explicit `today`.
begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

-- 1. Privileges --------------------------------------------------------------------------------------------

select is(has_function_privilege('anon', 'public.add_job_invoice_reminder(uuid, uuid, date, text)', 'execute'),
  false, 'signed-out callers cannot add an invoice reminder');
select is(has_function_privilege('authenticated', 'public.add_job_invoice_reminder(uuid, uuid, date, text)', 'execute'),
  true, 'members reach the add-reminder command');
select is(has_function_privilege('anon', 'public.dismiss_job_invoice_reminder(uuid, uuid)', 'execute'),
  false, 'signed-out callers cannot dismiss a reminder');
select is(has_function_privilege('authenticated', 'public.dismiss_job_invoice_reminder(uuid, uuid)', 'execute'),
  true, 'members reach the dismiss command');
select is(has_function_privilege('anon', 'public.delete_job_invoice_reminder(uuid, uuid)', 'execute'),
  false, 'signed-out callers cannot delete a reminder');
select is(has_function_privilege('authenticated', 'public.delete_job_invoice_reminder(uuid, uuid)', 'execute'),
  true, 'members reach the delete command');

-- The reminder-raising primitive and the month-end seeder are implementation details, not endpoints.
select is(has_function_privilege('authenticated',
  'private.create_invoice_reminder(uuid, uuid, text, date, uuid, uuid, text)', 'execute'),
  false, 'the create primitive is not callable by members');
select is(has_function_privilege('authenticated',
  'private.seed_next_month_end_reminder(uuid, uuid, uuid)', 'execute'),
  false, 'the month-end seeder is not callable by members');

-- 2. The derived-status precedence, tested as a pure rule -----------------------------------------------------

select is(private.job_derived_status('active', 'one_off', null, '2026-09-01'::date, true),
  'requires_invoicing', 'an active job with a due reminder requires invoicing');
select is(private.job_derived_status('active', 'one_off', null, '2026-09-01'::date, false),
  'unscheduled', 'an active job with nothing due is unscheduled');
select is(private.job_derived_status('closed', 'one_off', null, '2026-09-01'::date, true),
  'requires_invoicing', 'a closed job still owing an invoice outranks archived');
select is(private.job_derived_status('closed', 'one_off', null, '2026-09-01'::date, false),
  'archived', 'a closed job with nothing due is archived');
select is(private.job_derived_status('active', 'recurring', '2026-09-15'::date, '2026-09-01'::date, true),
  'ending_soon', 'a recurring agreement ending within 30 days beats an active due reminder');
select is(private.job_derived_status('active', 'recurring', '2026-12-31'::date, '2026-09-01'::date, true),
  'requires_invoicing', 'a far contract end does not trigger ending soon');

-- 3. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-rem-office@example.test', 'test', now(), now(), now()),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-rem-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('d2000000-0000-0000-0000-000000000001', 'Reminder Org A', 'reminder-org-a', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'office'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'field');

insert into public.clients (id, organization_id, display_name)
values ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'Reminder Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', '1 Reminder Way', 'Testville', 'TX', '78741');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select public.create_job_with_visits(
  'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001',
  'd4000000-0000-0000-0000-000000000001',
  'Reminder one-off job', null, true, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
  'idem-rem-0001', 'hash-rem-0001'
);

select public.create_job_with_visits(
  'd2000000-0000-0000-0000-000000000001',
  'd3000000-0000-0000-0000-000000000001',
  'd4000000-0000-0000-0000-000000000001',
  'Reminder recurring job', null, true, '[]'::jsonb,
  '[]'::jsonb,
  'idem-rem-0002', 'hash-rem-0002',
  'recurring', false,
  '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":6,"duration_unit":"month"}'::jsonb
);

create temporary view target_job as
  select id, revision from public.jobs
  where organization_id = 'd2000000-0000-0000-0000-000000000001' and job_type = 'one_off';
create temporary view repeat_job as
  select id, revision from public.jobs
  where organization_id = 'd2000000-0000-0000-0000-000000000001' and job_type = 'recurring';

-- 4. Table cannot be written directly, only read ------------------------------------------------------------

select throws_ok(
  $$ insert into public.job_invoice_reminders (organization_id, job_id, reminder_kind, due_on)
     values ('d2000000-0000-0000-0000-000000000001', (select id from target_job), 'custom_date', current_date) $$,
  '42501', null, 'a member cannot insert a reminder row directly'
);

select throws_ok(
  $$ update public.job_invoice_reminders set status = 'resolved' where true $$,
  '42501', null, 'a member cannot update a reminder row directly'
);

-- 5. Adding a custom-date reminder --------------------------------------------------------------------------

select isnt(
  (public.add_job_invoice_reminder(
    'd2000000-0000-0000-0000-000000000001', (select id from target_job), current_date, 'Bill the deposit'))->>'id',
  null, 'adding a custom-date reminder returns its id'
);

select is(
  (select reminder_kind || ':' || status from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date'),
  'custom_date:pending', 'the reminder is a pending custom-date reminder'
);

select is(
  (select due_on from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date'),
  current_date, 'the reminder carries the date it was given'
);

select is(
  (select count(*)::int from public.job_events
    where job_id = (select id from target_job) and event_type = 'invoice_reminder_added'),
  1, 'adding a reminder emits one invoice_reminder_added event'
);

-- Re-adding the same open date is a no-op that returns the reminder already there.
select is(
  (public.add_job_invoice_reminder(
    'd2000000-0000-0000-0000-000000000001', (select id from target_job), current_date))->>'id',
  (select id::text from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date'),
  're-adding the same date returns the existing reminder'
);

select is(
  (select count(*)::int from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date'),
  1, 'the duplicate add created no second row'
);

-- A field member holds no jobs.edit.
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.add_job_invoice_reminder(
    'd2000000-0000-0000-0000-000000000001', (select id from target_job), current_date) $$,
  '42501', null, 'a member without jobs.edit cannot add a reminder'
);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

-- 6. The list reader turns a due reminder into Requires invoicing -------------------------------------------

select is(
  (select derived_status from public.job_list_rows where id = (select id from target_job)),
  'requires_invoicing', 'a job with a reminder due today reads as Requires invoicing'
);

select is(
  (select total::int from public.job_status_counts('d2000000-0000-0000-0000-000000000001')
    where derived_status = 'requires_invoicing'),
  1, 'the overview counts that one job under Requires invoicing'
);

-- A reminder dated in the future is not yet due, so the job stays Unscheduled.
select public.add_job_invoice_reminder(
  'd2000000-0000-0000-0000-000000000001', (select id from repeat_job), current_date + 40);
select is(
  (select derived_status from public.job_list_rows where id = (select id from repeat_job)),
  'unscheduled', 'a reminder dated in the future does not yet require invoicing'
);

-- 7. Month-end billing seeds, clears, and rolls its reminder ------------------------------------------------

-- A recurring job is created billed at month end by default, so the jobs billing trigger has already seeded
-- its reminder at creation -- no billing edit is needed to make it appear.
select is(
  (select count(*)::int from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending'),
  1, 'a month-end-billed job carries its month-end reminder from creation'
);

-- Re-saving the same month-end billing is idempotent: no second reminder appears.
select public.set_job_billing(
  'd2000000-0000-0000-0000-000000000001', (select id from repeat_job),
  (select revision from repeat_job), 'fixed_per_period', 'month_end');

select is(
  (select count(*)::int from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending'),
  1, 'saving month-end billing again does not seed a duplicate reminder'
);

select is(
  (select due_on from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending'),
  (date_trunc('month', current_date) + interval '1 month' - interval '1 day')::date,
  'the month-end reminder is due on the last day of this month'
);

-- Moving off month-end clears the auto reminder that no longer reflects the policy.
select public.set_job_billing(
  'd2000000-0000-0000-0000-000000000001', (select id from repeat_job),
  (select revision from repeat_job), 'fixed_per_period', 'manual');
select is(
  (select count(*)::int from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending'),
  0, 'switching away from month-end deletes the open month-end reminder'
);

-- Back to month-end, then dismiss: the series rolls forward to next month rather than re-raising this month.
select public.set_job_billing(
  'd2000000-0000-0000-0000-000000000001', (select id from repeat_job),
  (select revision from repeat_job), 'fixed_per_period', 'month_end');
select public.dismiss_job_invoice_reminder(
  'd2000000-0000-0000-0000-000000000001',
  (select id from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending'));

select is(
  (select due_on from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending'),
  (date_trunc('month', current_date) + interval '2 month' - interval '1 day')::date,
  'dismissing a month-end reminder rolls the next one forward to next month'
);

select is(
  (select count(*)::int from public.job_invoice_reminders
    where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'resolved'),
  1, 'the dismissed month-end reminder stays as one resolved row of history'
);

-- 8. Dismissing and deleting a custom reminder -------------------------------------------------------------

select public.dismiss_job_invoice_reminder(
  'd2000000-0000-0000-0000-000000000001',
  (select id from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date' and status = 'pending'));

select is(
  (select status || ':' || resolution from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date'),
  'resolved:dismissed', 'dismissing marks the reminder resolved as dismissed'
);

select is(
  (select resolved_by from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date'),
  'd1000000-0000-0000-0000-000000000001'::uuid, 'the dismissal records who did it'
);

select is(
  (select count(*)::int from public.job_events
    where job_id = (select id from target_job) and event_type = 'invoice_reminder_dismissed'),
  1, 'dismissing emits one invoice_reminder_dismissed event'
);

-- Dismissing an already-handled reminder is a not-found rather than a silent second write.
select throws_ok(
  $$ select public.dismiss_job_invoice_reminder(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.job_invoice_reminders
      where job_id = (select id from target_job) and reminder_kind = 'custom_date')) $$,
  'P0404', null, 'a reminder that was already handled cannot be dismissed again'
);

-- Deleting a mistaken custom reminder removes it outright.
select public.add_job_invoice_reminder(
  'd2000000-0000-0000-0000-000000000001', (select id from target_job), current_date + 5, 'Typo');
select public.delete_job_invoice_reminder(
  'd2000000-0000-0000-0000-000000000001',
  (select id from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date' and status = 'pending'));
select is(
  (select count(*)::int from public.job_invoice_reminders
    where job_id = (select id from target_job) and reminder_kind = 'custom_date' and status = 'pending'),
  0, 'deleting a custom reminder removes it'
);

-- A month-end reminder is managed by its policy and cannot be deleted by hand.
select throws_ok(
  $$ select public.delete_job_invoice_reminder(
    'd2000000-0000-0000-0000-000000000001',
    (select id from public.job_invoice_reminders
      where job_id = (select id from repeat_job) and reminder_kind = 'monthly_last_day' and status = 'pending')) $$,
  '23514', null, 'only a custom-date reminder can be deleted; others must be dismissed'
);

select * from finish();
rollback;
