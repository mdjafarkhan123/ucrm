-- Sales Pipeline, Part 5A: real Quote stages and automatic Won/Lost/Reopen.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `pipeline_outcome_engine.sql` and
-- `tenant_isolation.sql` document. Do not run it through a runner that executes each statement separately.
begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5a-admin-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('81000000-0000-0000-0000-000000000001', '5A Quote Org A', '5a-quote-org-a', 'active'),
  ('81000000-0000-0000-0000-000000000002', '5A Quote Org B', '5a-quote-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', '5A Client A'),
  ('82000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000002', '5A Client B (other org)');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '1 Quote Street', 'Testville'),
  ('83000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000002', '1 Other Org Street', 'Testville');

-- Q1 walks Approve -> Begin material revision (Won, then Won-reopen). Q2 walks Decline -> Revise/reopen
-- (Lost, then Lost-reopen). Q3 is abandoned while still a Draft, via the Quote's own archive_quote, never
-- through a Pipeline-specific RPC. Q4 starts already Approved and gets archived-then-restored without ever
-- leaving Won. Q5 lives in the other organization, used only for the tenant-isolation check.
insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values
  ('84000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 1, '5A Quote Q1', 'draft', 'USD'),
  ('84000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 2, '5A Quote Q2', 'draft', 'USD'),
  ('84000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 3, '5A Quote Q3', 'draft', 'USD'),
  ('84000000-0000-0000-0000-000000000004', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 4, '5A Quote Q4', 'approved', 'USD'),
  ('84000000-0000-0000-0000-000000000005', '81000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000002', 1, '5A Quote Q5 (other org)', 'draft', 'USD');

-- create_quote/convert_request_to_quote insert this inline; fixtures do the same by hand since neither
-- command runs here.
insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
select organization_id, client_id, property_id, id, title from public.quotes
where id in (
  '84000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000002',
  '84000000-0000-0000-0000-000000000003', '84000000-0000-0000-0000-000000000004',
  '84000000-0000-0000-0000-000000000005'
);

-- Q4 was already Approved before its Opportunity existed in this fixture set, so simulate what the 5A
-- backfill does for a pre-existing decided quote: outcome is 'won' with no event row.
update public.opportunities
set outcome = 'won', outcome_at = now()
where quote_id = '84000000-0000-0000-0000-000000000004';

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

-- 1. Stage derivation on insert ---------------------------------------------------------------------------

select is(
  (select stage from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'quote_draft', 'a draft quote''s opportunity starts at quote_draft'
);
select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'open', 'a fresh quote opportunity starts open'
);

set local role postgres;

-- 2. Ordinary stage moves touch no outcome ----------------------------------------------------------------

update public.quotes set status = 'awaiting_response' where id = '84000000-0000-0000-0000-000000000001';

select is(
  (select stage from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'quote_awaiting_response', 'sending a draft moves its opportunity to quote_awaiting_response'
);
select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'open', 'sending a draft does not touch outcome'
);
select is(
  (select count(*)::int from public.opportunity_outcome_events where opportunity_id = (
    select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'
  )),
  0, 'no outcome event exists yet for Q1'
);

-- 3. Approve -> automatic Won ------------------------------------------------------------------------------

update public.quotes set status = 'approved' where id = '84000000-0000-0000-0000-000000000001';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'won', 'approving a quote automatically wins its opportunity'
);
select is(
  (select count(*)::int from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001')
     and event_type = 'won'),
  1, 'exactly one won event was written'
);
select is(
  (select prior_quote_status from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001')
     and event_type = 'won'),
  'awaiting_response', 'the won event remembers the status just before approval'
);
select is(
  (select current_outcome_event_id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001')
  is not null,
  true, 'the opportunity points at its own won event'
);

-- 4. Begin material revision (Approved -> draft) -> Won reopens --------------------------------------------

update public.quotes set status = 'draft' where id = '84000000-0000-0000-0000-000000000001';

select is(
  (select stage from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'quote_draft', 'begin material revision returns the opportunity to the quote_draft projection'
);
select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'open', 'begin material revision reopens the won opportunity'
);
select is(
  (select current_outcome_event_id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  null, 'reopening clears the current outcome event pointer, same as the manual reopen RPC'
);
select is(
  (select restores_event_id from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001')
     and event_type = 'reopened'),
  (select id from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001')
     and event_type = 'won'),
  'the reopened event names the exact won event it reverses'
);
select is(
  (select reopen_explanation from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001')
     and event_type = 'reopened'),
  null, 'a quote-triggered reopen carries no explanation -- Jafar, 2026-08-23'
);

-- 5. Decline -> automatic Lost, then Revise/reopen ----------------------------------------------------------

update public.quotes set status = 'awaiting_response' where id = '84000000-0000-0000-0000-000000000002';
update public.quotes set status = 'declined' where id = '84000000-0000-0000-0000-000000000002';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000002'),
  'lost', 'declining a quote automatically loses its opportunity'
);
select is(
  (select prior_request_status from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000002')
     and event_type = 'lost'),
  null, 'a quote-triggered lost event carries no request status'
);

update public.quotes set status = 'draft' where id = '84000000-0000-0000-0000-000000000002';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000002'),
  'open', 'revise/reopen from Declined reopens the lost opportunity'
);
select is(
  (select stage from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000002'),
  'quote_draft', 'revise/reopen returns the opportunity to the quote_draft projection'
);

-- 6. Abandoning a stale Draft via the Quote's own archive, no separate Pipeline RPC --------------------------

update public.quotes set status = 'archived', previous_status = 'draft', archived_at = now() where id = '84000000-0000-0000-0000-000000000003';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000003'),
  'lost', 'archiving a still-open draft quote loses its opportunity, with no Pipeline-specific RPC involved'
);

-- Restoring it back to draft reopens, the same as Revise/reopen does.
update public.quotes set status = 'draft', previous_status = null, archived_at = null where id = '84000000-0000-0000-0000-000000000003';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000003'),
  'open', 'restoring an abandoned draft quote reopens its opportunity'
);

-- 7. Archiving and restoring an already-Won quote never touches outcome --------------------------------------

select is(
  (select count(*)::int from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000004')),
  0, 'Q4 was backfilled won with no event row, matching the migration''s own backfill'
);

update public.quotes set status = 'archived', previous_status = 'approved', archived_at = now() where id = '84000000-0000-0000-0000-000000000004';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000004'),
  'won', 'archiving an already-approved quote does not turn its opportunity lost'
);
select is(
  (select count(*)::int from public.opportunity_outcome_events
   where opportunity_id = (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000004')),
  0, 'no event was written for archiving an already-won quote'
);

update public.quotes set status = 'approved', previous_status = null, archived_at = null where id = '84000000-0000-0000-0000-000000000004';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000004'),
  'won', 'restoring straight back to approved leaves the opportunity won, untouched'
);
select is(
  (select stage from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000004'),
  'request_closed', 'a decided quote''s opportunity stays parked off the board'
);

-- 8. Tenant isolation: a status change in org B never touches org A's rows ------------------------------------

set local role postgres;
update public.quotes set status = 'awaiting_response' where id = '84000000-0000-0000-0000-000000000005';
update public.quotes set status = 'approved' where id = '84000000-0000-0000-0000-000000000005';

select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000005'),
  'won', 'org B''s own quote still wins its own opportunity'
);
select is(
  (select outcome from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
  'open', 'org B''s approval never touched org A''s Q1'
);

-- 9. Constraint sanity: a won event cannot carry lost/reopen fields -------------------------------------------

select throws_ok(
  $$insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, actor_user_id, reason, idempotency_key
    ) values (
      '81000000-0000-0000-0000-000000000001',
      (select id from public.opportunities where quote_id = '84000000-0000-0000-0000-000000000001'),
      'won', null, 'price_too_high', 'x0000001'
    )$$,
  '23514',
  null,
  'a won event cannot also carry a lost reason'
);

select * from finish();
rollback;
