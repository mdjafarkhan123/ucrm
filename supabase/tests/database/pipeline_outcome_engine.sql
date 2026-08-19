-- Sales Pipeline, Part 4A: atomic outcome engine.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(49);

-- Privileges --------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.pipeline_mark_opportunity_lost(uuid, text, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot mark an opportunity lost'
);
select is(
  has_function_privilege('authenticated', 'public.pipeline_mark_opportunity_lost(uuid, text, text, text, timestamptz)', 'execute'),
  true, 'authenticated members can call mark-lost'
);
select is(
  has_function_privilege('anon', 'public.pipeline_reopen_opportunity(uuid, text, text, timestamptz)', 'execute'),
  false, 'anonymous callers cannot reopen an opportunity'
);
select is(
  has_function_privilege('authenticated', 'public.pipeline_reopen_opportunity(uuid, text, text, timestamptz)', 'execute'),
  true, 'authenticated members can call reopen'
);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('70000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outcome-admin-a@example.test', 'test', now(), now(), now()),
  ('70000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outcome-admin-b@example.test', 'test', now(), now(), now()),
  ('70000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outcome-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('71000000-0000-0000-0000-000000000001', '4A Outcome Org A', '4a-outcome-org-a', 'active'),
  ('71000000-0000-0000-0000-000000000002', '4A Outcome Org B', '4a-outcome-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('71000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'admin'),
  ('71000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000002', 'admin'),
  ('71000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000003', 'field');

insert into public.clients (id, organization_id, display_name)
values ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '4A Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '1 Outcome Street', 'Testville');

-- Request R1 carries five open Tasks (the cap) and one already-completed Task, so Lost has to complete
-- exactly the five open ones and must never touch the one a human already finished. Request R2 is the
-- optional-reason case. Request R3 starts already converted, so it is never eligible. Request R4 is a plain
-- fixture Lost never reaches, used only for the cross-tenant/permission checks.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
values
  ('74000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '4A Request R1', 'new'),
  ('74000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '4A Request R2', 'unscheduled'),
  ('74000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '4A Request R3', 'converted'),
  ('74000000-0000-0000-0000-000000000004', '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '4A Request R4', 'new');

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

-- The Request trigger creates one Opportunity per Request automatically (Part 1).
select is(
  (select count(*)::int from public.opportunities where request_id in (
    '74000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000002',
    '74000000-0000-0000-0000-000000000003', '74000000-0000-0000-0000-000000000004'
  )),
  4, 'each fixture request already has exactly one opportunity'
);

set local role postgres;

insert into public.tasks (id, organization_id, opportunity_id, title, status, completed_at, completed_by)
select
  ('75000000-0000-0000-0000-00000000000' || n)::uuid,
  '71000000-0000-0000-0000-000000000001',
  (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'R1 open task ' || n,
  'open', null, null
from generate_series(1, 5) as n;

insert into public.tasks (id, organization_id, opportunity_id, title, status, completed_at, completed_by)
values (
  '75000000-0000-0000-0000-000000000006', '71000000-0000-0000-0000-000000000001',
  (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'R1 already completed by a person', 'completed', now(), '70000000-0000-0000-0000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

-- Direct writes stay refused ------------------------------------------------------------------------------

select throws_ok(
  $$update public.requests set status = 'archived' where id = '74000000-0000-0000-0000-000000000004'$$,
  '42501', null, 'a member cannot archive a request directly, even one they can otherwise edit'
);
select throws_ok(
  $$update public.opportunities set outcome = 'lost' where id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004')$$,
  '42501', null, 'a member cannot write opportunities.outcome directly'
);
select throws_ok(
  $$insert into public.opportunity_outcome_events (organization_id, opportunity_id, event_type, prior_request_status, idempotency_key) values ('71000000-0000-0000-0000-000000000001', (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004'), 'lost', 'new', 'direct-insert-attempt')$$,
  '42501', null, 'a member cannot insert an outcome event directly'
);

-- Permission and tenant isolation --------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000003', true);
select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'field-worker-attempt-1')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004')
  ),
  '42501', null, 'a field-role member without pipeline.edit cannot mark an opportunity lost'
);

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'cross-tenant-attempt-1')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004')
  ),
  '42501', null, 'an admin in another organization cannot mark this opportunity lost'
);

select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

-- Validation before any write ------------------------------------------------------------------------------

select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'short')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004')
  ),
  '23514', null, 'an idempotency key under 8 characters is rejected'
);
select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'r4-bogus-reason-1', 'not_a_real_reason')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004')
  ),
  '23514', null, 'an unrecognised lost reason is rejected'
);
select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'r4-other-no-note-1', 'other')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004')
  ),
  '23514', null, '"Other" without a note is rejected'
);

set local role postgres;
select is(
  (select outcome from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004'),
  'open', 'the rejected attempts on R4 left its opportunity open'
);
select is(
  (select status from public.requests where id = '74000000-0000-0000-0000-000000000004'),
  'new', 'the rejected attempts on R4 left its request untouched'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

-- Terminal converted request -------------------------------------------------------------------------------

select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'r3-converted-attempt-1')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000003')
  ),
  '23514', null, 'a converted request cannot be marked lost'
);

-- Valid Lost transition on R1: five open tasks, one human-completed task --------------------------------

select is(
  (public.pipeline_mark_opportunity_lost(
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
    'r1-lost-attempt-1', 'price_too_high', 'Went with a competitor.'
  ) ->> 'applied'),
  'true', 'marking R1''s opportunity lost applies'
);
select is(
  (select outcome from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'lost', 'R1''s opportunity now reads lost'
);
select is(
  (select outcome_at is not null from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  true, 'R1''s opportunity records when it was lost'
);
select is(
  (select status from public.requests where id = '74000000-0000-0000-0000-000000000001'),
  'archived', 'R1 itself is archived'
);
select is(
  (select stage from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'request_closed', 'R1''s card left the active board stages'
);
select is(
  (select count(*)::int from public.tasks where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001') and status = 'completed'),
  6, 'all six of R1''s tasks now read completed (five auto, one human)'
);
select is(
  (select count(*)::int from public.tasks where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001') and completed_by_outcome_event_id is not null),
  5, 'exactly the five previously-open tasks carry the lost event''s provenance'
);
select is(
  (select completed_by_outcome_event_id from public.tasks where id = '75000000-0000-0000-0000-000000000006'),
  null, 'the task a person completed by hand still carries no outcome-event provenance'
);
select is(
  (select completed_by from public.tasks where id = '75000000-0000-0000-0000-000000000006'),
  '70000000-0000-0000-0000-000000000001', 'the task a person completed by hand keeps its human completed_by'
);
select is(
  (select reason from public.opportunity_outcome_events where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')),
  'price_too_high', 'the lost event stored the chosen reason'
);
select is(
  (select prior_request_status from public.opportunity_outcome_events where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')),
  'new', 'the lost event captured the request''s status before it was archived'
);

-- Duplicate retry: same idempotency key, no second event, no double-completion ----------------------------

select is(
  (public.pipeline_mark_opportunity_lost(
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
    'r1-lost-attempt-1', 'price_too_high', 'Went with a competitor.'
  ) ->> 'applied'),
  'false', 'retrying the same lost command with the same key is recognised as a repeat'
);
select is(
  (select count(*)::int from public.opportunity_outcome_events where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001') and event_type = 'lost'),
  1, 'the retry did not create a second lost event'
);

-- A conflicting (non-retry) command against an already-lost opportunity is refused -------------------------

select throws_ok(
  format(
    $$select public.pipeline_mark_opportunity_lost(%L, 'r1-lost-attempt-2-different-key')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'marking an already-lost opportunity lost again under a new key is refused'
);

-- Reopen: round trip restores the request and exactly the auto-completed tasks -----------------------------

select throws_ok(
  format(
    $$select public.pipeline_reopen_opportunity(%L, 'r1-reopen-attempt-1', '')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'reopening without an explanation is rejected'
);

select is(
  (public.pipeline_reopen_opportunity(
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
    'r1-reopen-attempt-2', 'Client came back after all.'
  ) ->> 'applied'),
  'true', 'reopening R1''s opportunity applies'
);
select is(
  (select outcome from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'open', 'R1''s opportunity is open again'
);
select is(
  (select outcome_at from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  null, 'R1''s opportunity has no current outcome date once reopened'
);
select is(
  (select status from public.requests where id = '74000000-0000-0000-0000-000000000001'),
  'new', 'R1 is restored to its exact prior status, not a generic default'
);
select is(
  (select count(*)::int from public.tasks where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001') and status = 'open'),
  5, 'the five auto-completed tasks are open again'
);
select is(
  (select status from public.tasks where id = '75000000-0000-0000-0000-000000000006'),
  'completed', 'the task a person completed by hand is still completed after reopen'
);
select is(
  (select count(*)::int from public.opportunity_outcome_events where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')),
  2, 'both the lost and the reopened event remain in immutable history'
);

-- Reopen retry is idempotent too -----------------------------------------------------------------------

select is(
  (public.pipeline_reopen_opportunity(
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
    'r1-reopen-attempt-2', 'Client came back after all.'
  ) ->> 'applied'),
  'false', 'retrying the same reopen command with the same key is recognised as a repeat'
);

select throws_ok(
  format(
    $$select public.pipeline_reopen_opportunity(%L, 'r1-reopen-attempt-3-different-key', 'Trying again.')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'reopening an opportunity that is not currently lost is refused'
);

-- Optional reason: R2 can be lost with no reason at all ------------------------------------------------

select is(
  (public.pipeline_mark_opportunity_lost(
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000002'),
    'r2-lost-attempt-1'
  ) ->> 'applied'),
  'true', 'a lost reason is optional'
);
select is(
  (select reason from public.opportunity_outcome_events where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000002')),
  null, 'R2''s lost event stored no reason'
);

-- Five-open-task limit is respected on reopen, atomically -------------------------------------------------

-- R1 is open again with zero open tasks. Lose it a second time (a fresh cycle), then let a Task be created
-- while it is closed -- the write path does not block that today -- so the coming reopen has to refuse.
select is(
  (public.pipeline_mark_opportunity_lost(
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
    'r1-lost-attempt-3'
  ) ->> 'applied'),
  'true', 'R1 can be lost again for a second cycle'
);

select (public.pipeline_create_opportunity_task(
  (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'Opened while the card was closed'
));

select throws_ok(
  format(
    $$select public.pipeline_reopen_opportunity(%L, 'r1-reopen-attempt-4', 'Would exceed the open task limit.')$$,
    (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'reopening is refused when it would leave more than five open tasks'
);

set local role postgres;
select is(
  (select outcome from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001'),
  'lost', 'the refused reopen left R1''s opportunity lost, with no partial change'
);
select is(
  (select count(*)::int from public.tasks where opportunity_id = (select id from public.opportunities where request_id = '74000000-0000-0000-0000-000000000001') and status = 'open'),
  1, 'the refused reopen left only the one task opened after closure as open'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);

-- Index-backed report access ---------------------------------------------------------------------------

set local role postgres;
select has_index('public', 'opportunities', 'opportunities_outcome_idx', 'the outcome/date index exists for the tiles and report');
select has_index('public', 'opportunity_outcome_events', 'opportunity_outcome_events_opportunity_idx', 'the per-opportunity history index exists');
select is(
  (select outcome_at from public.opportunities where request_id = '74000000-0000-0000-0000-000000000004'),
  null, 'an opportunity that was never lost has no outcome date'
);

select * from finish();
rollback;
