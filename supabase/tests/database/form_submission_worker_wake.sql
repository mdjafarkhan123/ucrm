-- CRM launch readiness Part 4: a saved public form wakes the form-submission worker.
--
-- Covers: one nudge per insert statement (however many rows), no nudge when the worker updates a row, a wake
-- problem never refusing the submission, the fail-closed Cron dispatcher, the inactive one-minute schedule, and
-- the functions staying out of reach of browser roles.

begin;

create extension if not exists pgtap with schema extensions;
select plan(9);

set local role postgres;

insert into public.organizations (id, name, slug, lifecycle_status)
values ('4a200000-0000-0000-0000-000000000001', 'Form Wake Test', 'form-wake-test', 'active');

insert into public.forms (id, organization_id, outcome, name, public_slug)
values ('4a200000-0000-0000-0000-000000000003', '4a200000-0000-0000-0000-000000000001', 'request',
  'Get a quote', 'form-wake-test-form');

insert into public.form_versions (id, organization_id, form_id, version_number, title)
values ('4a200000-0000-0000-0000-000000000004', '4a200000-0000-0000-0000-000000000001',
  '4a200000-0000-0000-0000-000000000003', 1, 'Get a quote');

-- Point the wake at a recognizable test URL for this transaction only.
select vault.update_secret(id, 'https://wake-test.example/api/internal/forms/worker')
from vault.secrets where name = 'form_submission_worker_target_url';
select vault.update_secret(id, 'test-bearer')
from vault.secrets where name = 'form_submission_worker_secret';

create temporary table wake_baseline on commit drop as
select coalesce(max(id), 0) as last_id from net.http_request_queue;

create function pg_temp.wakes() returns integer language sql as $$
  select count(*)::integer from net.http_request_queue
  where url = 'https://wake-test.example/api/internal/forms/worker'
    and id > (select last_id from wake_baseline);
$$;

insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact)
values ('4a200000-0000-0000-0000-000000000020', '4a200000-0000-0000-0000-000000000001',
  '4a200000-0000-0000-0000-000000000003', '4a200000-0000-0000-0000-000000000004', 'wake-1',
  '{"name":"Test Lead","email":"lead@example.test"}'::jsonb);

select is(pg_temp.wakes(), 1, 'saving a submission nudges the worker once');

insert into private.form_submissions (id, organization_id, form_id, form_version_id, idempotency_key, contact)
values
  ('4a200000-0000-0000-0000-000000000021', '4a200000-0000-0000-0000-000000000001',
   '4a200000-0000-0000-0000-000000000003', '4a200000-0000-0000-0000-000000000004', 'wake-2',
   '{"name":"Test Lead","email":"lead@example.test"}'::jsonb),
  ('4a200000-0000-0000-0000-000000000022', '4a200000-0000-0000-0000-000000000001',
   '4a200000-0000-0000-0000-000000000003', '4a200000-0000-0000-0000-000000000004', 'wake-3',
   '{"name":"Test Lead","email":"lead@example.test"}'::jsonb);

select is(pg_temp.wakes(), 2, 'one insert statement fires one nudge however many rows it saved');

update private.form_submissions set status = 'failed'
where id = '4a200000-0000-0000-0000-000000000020';

select is(pg_temp.wakes(), 2, 'the worker updating a row never nudges again');

-- A missing secret must not refuse the customer's form.
select vault.update_secret(id, new_name => 'form_submission_worker_secret_hidden')
from vault.secrets where name = 'form_submission_worker_secret';

select lives_ok(
  $$insert into private.form_submissions (organization_id, form_id, form_version_id, idempotency_key, contact)
    values ('4a200000-0000-0000-0000-000000000001', '4a200000-0000-0000-0000-000000000003',
      '4a200000-0000-0000-0000-000000000004', 'wake-4', '{"name":"Test Lead"}'::jsonb)$$,
  'an unconfigured wake still saves the submission'
);

select throws_ok(
  'select public.dispatch_form_submission_worker_wake()',
  'P0002',
  null,
  'the Cron sweep fails closed when its secret is missing'
);

select vault.update_secret(id, new_name => 'form_submission_worker_secret')
from vault.secrets where name = 'form_submission_worker_secret_hidden';

select lives_ok('select public.dispatch_form_submission_worker_wake()', 'the Cron sweep dispatches when configured');

select ok(
  exists (select 1 from cron.job where jobname = 'form-submission-worker-wake-one-minute'
    and schedule = '* * * * *'),
  'the one-minute sweep is scheduled'
);

select ok(
  not has_function_privilege('anon', 'public.request_form_submission_worker_wake()', 'execute')
  and not has_function_privilege('authenticated', 'public.request_form_submission_worker_wake()', 'execute'),
  'browser roles cannot fire the nudge'
);

select ok(
  not has_function_privilege('anon', 'public.dispatch_form_submission_worker_wake()', 'execute')
  and not has_function_privilege('authenticated', 'public.dispatch_form_submission_worker_wake()', 'execute'),
  'browser roles cannot fire the sweep'
);

select * from finish();
rollback;
