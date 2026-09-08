-- Jobs, Part 15d-1: collected job signatures, the frozen document under them, and who may see it.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

-- throws_ok's three-argument form takes (query, errcode, errmsg) in this pgTAP build, not
-- (query, errcode, description). Checking an error code therefore uses the four-argument form with a null
-- message, or the description quietly becomes the message the assertion is looking for.

-- 1. Shape ---------------------------------------------------------------------------------------------

select has_table('public', 'job_signatures', 'a collected signature is its own record, not a note');
select has_index('public', 'job_signatures', 'job_signatures_job_idx', 'the job card reads one index');
select has_index('public', 'job_signatures', 'job_signatures_visit_idx', 'the visit key has its own index');

-- 2. Privileges ----------------------------------------------------------------------------------------

select is(
  has_table_privilege('authenticated', 'public.job_signatures', 'insert'),
  false, 'members cannot insert a signature directly'
);
select is(
  has_table_privilege('authenticated', 'public.job_signatures', 'update'),
  false, 'members cannot update a signature'
);
select is(
  has_table_privilege('authenticated', 'public.job_signatures', 'delete'),
  false, 'members cannot delete a signature'
);
select is(
  has_column_privilege('authenticated', 'public.job_signatures', 'document_snapshot', 'select'),
  false, 'the frozen document never travels on a plain grant'
);
select is(
  has_column_privilege('authenticated', 'public.job_signatures', 'signer_name', 'select'),
  true, 'the parts of a signature that are not the document stay readable'
);
select is(
  has_function_privilege(
    'anon',
    'public.collect_job_signature(uuid, uuid, text, text, text, text, text, uuid, text, integer, jsonb)',
    'execute'
  ),
  false, 'there is no customer-facing path to collecting a signature'
);
select is(
  has_function_privilege('anon', 'public.job_signatures_for_job(uuid)', 'execute'),
  false, 'anonymous callers cannot list a job''s signatures'
);
select is(
  has_function_privilege('anon', 'public.job_signature_document(uuid)', 'execute'),
  false, 'anonymous callers cannot read a signed document'
);
select is(
  has_function_privilege('authenticated', 'public.job_signatures_for_job(uuid)', 'execute'),
  true, 'members reach the list through the gated reader'
);

-- 3. Fixtures ------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('95000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sig-admin-a@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sig-admin-b@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sig-office-a@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sig-field-on@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sig-field-off@example.test', 'test', now(), now(), now()),
  ('95000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sig-finance-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('96000000-0000-0000-0000-000000000001', 'Sig Org A', 'sig-org-a', 'active'),
  ('96000000-0000-0000-0000-000000000002', 'Sig Org B', 'sig-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 'admin'),
  ('96000000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000002', 'admin'),
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000003', 'office'),
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000004', 'field'),
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000005', 'field'),
  ('96000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000006', 'finance');

insert into public.clients (id, organization_id, display_name)
values
  ('97000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001', 'Sig Client A'),
  ('97000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000002', 'Sig Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('98000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001', '6 Sig Lane', 'Testville'),
  ('98000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000002', '7 Other Lane', 'Otherville');

-- Two jobs in org A -- one the Field member is on, one they are not -- and one in org B. The ids ride in
-- transaction-local settings rather than a temp table, because the assertions below change database role
-- and a temp table created by one role is not readable by the next.
select set_config('test.assigned_job', (private.create_job(
  '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001', 'Signed job', 'one_off', 'job_total', 'USD',
  '95000000-0000-0000-0000-000000000001'
)).id::text, true);
select set_config('test.other_job', (private.create_job(
  '96000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001', 'Other job', 'one_off', 'job_total', 'USD',
  '95000000-0000-0000-0000-000000000001'
)).id::text, true);
select set_config('test.foreign_job', (private.create_job(
  '96000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000002',
  '98000000-0000-0000-0000-000000000002', 'Org B job', 'one_off', 'job_total', 'USD',
  '95000000-0000-0000-0000-000000000002'
)).id::text, true);

insert into public.job_line_items (organization_id, job_id, position, name, quantity, unit_price_minor)
values ('96000000-0000-0000-0000-000000000001', current_setting('test.assigned_job')::uuid, 0,
  'Gutter clean', 2, 15000);

-- A job's stored totals are maintained by replace_job_line_items, not by a trigger on the lines, so a
-- fixture that inserts a line directly has to say what the job now costs. The signed document reads these.
update public.jobs
set subtotal_minor = 30000, total_minor = 30000
where id = current_setting('test.assigned_job')::uuid;

insert into public.job_visits (id, organization_id, job_id, position, visit_date)
values ('99000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001',
  current_setting('test.assigned_job')::uuid, 0, current_date);

-- The other job's visit exists only so "that visit is not on this job" has something real to refuse.
insert into public.job_visits (id, organization_id, job_id, position, visit_date)
values ('99000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000001',
  current_setting('test.other_job')::uuid, 0, current_date);

insert into public.job_visit_assignments (organization_id, visit_id, job_id, user_id)
values ('96000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001',
  current_setting('test.assigned_job')::uuid, '95000000-0000-0000-0000-000000000004');

-- 4. Collecting one ------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);

select set_config('test.first_signature', public.collect_job_signature(
  '96000000-0000-0000-0000-000000000001', current_setting('test.assigned_job')::uuid,
  'work_completion', '  Dana Reed  ', 'I confirm the work is complete.', 'typed',
  'Homeowner', '99000000-0000-0000-0000-000000000001'
) ->> 'id', true);

select is(
  (select signer_name from public.job_signatures where id = current_setting('test.first_signature')::uuid),
  'Dana Reed', 'the signer''s name is stored trimmed'
);

select is(
  (select count(*)::int from public.activity_events
    where event_type = 'job.signature_collected'
      and organization_id = '96000000-0000-0000-0000-000000000001'),
  1, 'collecting a signature writes the history row the job feed reads'
);

select is(
  (select entity_type from public.activity_events
    where event_type = 'job.signature_collected'
      and organization_id = '96000000-0000-0000-0000-000000000001'),
  'visit', 'a signature collected on a visit is filed against that visit'
);

select is(
  (select public.job_signatures_for_job(current_setting('test.assigned_job')::uuid)
    -> 'signatures' -> 0 ->> 'is_stale'),
  'false', 'a signature over the job as it stands is not stale'
);

select is(
  (select public.job_signature_document(current_setting('test.first_signature')::uuid)
    -> 'document' -> 'totals' ->> 'total_minor'),
  '30000', 'the frozen document carries the total that was approved'
);

-- 5. What it refuses -----------------------------------------------------------------------------------

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000001', %L, 'work_completion', 'Dana Reed',
    'I confirm the work is complete.', 'typed', null, '99000000-0000-0000-0000-000000000002'
  )$q$, current_setting('test.assigned_job')::uuid),
  'P0404', null, 'another job''s visit is not context, it is a mistake'
);

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000001', %L, 'work_completion', 'Dana Reed',
    'I confirm the work is complete.', 'drawn'
  )$q$, current_setting('test.assigned_job')::uuid),
  'P0400', null, 'a drawn signature without a drawing is incomplete'
);

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000001', %L, 'work_completion', 'Dana Reed',
    'I confirm the work is complete.', 'typed', null, null, 'org/job-signatures/x.png', 100
  )$q$, current_setting('test.assigned_job')::uuid),
  'P0400', null, 'a typed signature with a drawing is incomplete'
);

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000001', %L, 'autograph', 'Dana Reed',
    'I confirm the work is complete.', 'typed'
  )$q$, current_setting('test.assigned_job')::uuid),
  'P0400', null, 'there are three kinds of signature and no others'
);

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000001', %L, 'work_completion', '   ',
    'I confirm the work is complete.', 'typed'
  )$q$, current_setting('test.assigned_job')::uuid),
  'P0400', null, 'a signature needs the name of the person signing'
);

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000002', %L, 'work_completion', 'Dana Reed',
    'I confirm the work is complete.', 'typed'
  )$q$, current_setting('test.foreign_job')::uuid),
  '42501', null, 'a member cannot collect against another organization''s job'
);

-- 6. Append-only ---------------------------------------------------------------------------------------

set local role postgres;

select throws_ok(
  format($q$update public.job_signatures set signer_name = 'Tampered' where id = %L$q$,
    current_setting('test.first_signature')::uuid),
  '42501', null, 'no path anywhere may rewrite a collected signature'
);

select throws_ok(
  format($q$delete from public.job_signatures where id = %L$q$, current_setting('test.first_signature')::uuid),
  '42501', null, 'a collected signature cannot be deleted'
);

select throws_ok(
  $q$truncate public.job_signatures$q$,
  '42501', null, 'collected signatures cannot be emptied'
);

-- The one exception: an organization being erased must not be blocked by its own evidence.
select set_config('app.organization_purge_in_progress', 'true', true);
delete from public.job_signatures where id = current_setting('test.first_signature')::uuid;
select set_config('app.organization_purge_in_progress', 'false', true);

select is(
  (select count(*)::int from public.job_signatures
    where id = current_setting('test.first_signature')::uuid),
  0, 'the organization purge may still delete a signature'
);

-- 7. Staleness -----------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);

select set_config('test.second_signature', public.collect_job_signature(
  '96000000-0000-0000-0000-000000000001', current_setting('test.assigned_job')::uuid,
  'work_authorization', 'Dana Reed', 'I authorize the work.', 'typed'
) ->> 'id', true);

set local role postgres;
update public.job_line_items set unit_price_minor = 20000
  where job_id = current_setting('test.assigned_job')::uuid;
update public.jobs
set subtotal_minor = 40000, total_minor = 40000
where id = current_setting('test.assigned_job')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000001', true);

select is(
  (select public.job_signatures_for_job(current_setting('test.assigned_job')::uuid)
    -> 'signatures' -> 0 ->> 'is_stale'),
  'true', 'moving the job''s price makes the signature stale'
);

select is(
  (select public.job_signature_document(current_setting('test.second_signature')::uuid)
    -> 'document' -> 'totals' ->> 'total_minor'),
  '30000', 'a later edit does not rewrite what was signed'
);

-- 8. Who sees what -------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.job_signatures),
  1, 'an admin at all scope sees the job''s signature'
);

select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000003', true);
select is((select count(*)::int from public.job_signatures), 1, 'office sees it too');

select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000006', true);
select is((select count(*)::int from public.job_signatures), 1, 'finance sees it too');

select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000004', true);
select is(
  (select count(*)::int from public.job_signatures),
  1, 'a Field member on the job sees its signatures'
);

select ok(
  (select public.job_signature_document(current_setting('test.second_signature')::uuid)
    -> 'document' -> 'totals') is null,
  'a reader without jobs.view_price sees no totals on the signed document'
);

select ok(
  (select public.job_signature_document(current_setting('test.second_signature')::uuid)
    -> 'document' -> 'lines' -> 0 -> 'unit_price_minor') is null,
  'and no line prices either'
);

select is(
  (select public.job_signature_document(current_setting('test.second_signature')::uuid)
    -> 'document' -> 'lines' -> 0 ->> 'name'),
  'Gutter clean', 'the work list itself survives the stripping'
);

select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000005', true);
select is(
  (select count(*)::int from public.job_signatures),
  0, 'a Field member who is not on the job sees none of its signatures'
);

select throws_ok(
  format($q$select public.collect_job_signature(
    '96000000-0000-0000-0000-000000000001', %L, 'work_completion', 'Dana Reed',
    'I confirm the work is complete.', 'typed'
  )$q$, current_setting('test.assigned_job')::uuid),
  '42501', null, 'and cannot collect one against it'
);

select set_config('request.jwt.claim.sub', '95000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::int from public.job_signatures),
  0, 'another organization''s admin sees nothing'
);

set local role anon;
select throws_ok(
  $q$select count(*) from public.job_signatures$q$,
  '42501', null, 'anonymous callers cannot read signatures at all'
);

set local role postgres;
select * from finish();
rollback;
