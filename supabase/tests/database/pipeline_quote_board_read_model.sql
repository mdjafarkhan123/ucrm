-- Sales Pipeline, Part 5C-i: the board's read side learns about the Quotes group.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention pipeline_drag_transitions.sql documents.
-- Quote-backed opportunities are inserted directly with quote_id set, exactly like that file's own
-- fixtures -- opportunity_apply_stage (5A) derives quote_draft/quote_awaiting_response/quote_changes_requested
-- from quotes.status on insert, so no create_quote call is needed to get a real fixture.
begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('ac000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5c-admin-a@example.test', 'test', now(), now(), now()),
  ('ac000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5c-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('ad000000-0000-0000-0000-000000000001', '5C Board Org A', '5c-board-org-a', 'active'),
  ('ad000000-0000-0000-0000-000000000002', '5C Board Org B', '5c-board-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('ad000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'admin'),
  ('ad000000-0000-0000-0000-000000000002', 'ac000000-0000-0000-0000-000000000002', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('ae000000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000001', '5C Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('af000000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-000000000001', '1 Board Street', 'Testville');

-- R1: a Request-backed card, still in new_request. Its Opportunity is made by the Request insert trigger,
-- not by hand -- proves the widened function is unbroken for the group it already served.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
values ('b0000000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-000000000001', 'af000000-0000-0000-0000-000000000001', '5C Request R1', 'new');

-- Q1 draft (estimated), Q2 awaiting_response, Q3 changes_requested.
insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values
  ('b1000000-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-000000000001', 'af000000-0000-0000-0000-000000000001', 1, '5C Quote Q1', 'draft', 'USD'),
  ('b1000000-0000-0000-0000-000000000002', 'ad000000-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-000000000001', 'af000000-0000-0000-0000-000000000001', 2, '5C Quote Q2', 'awaiting_response', 'USD'),
  ('b1000000-0000-0000-0000-000000000003', 'ad000000-0000-0000-0000-000000000001', 'ae000000-0000-0000-0000-000000000001', 'af000000-0000-0000-0000-000000000001', 3, '5C Quote Q3', 'changes_requested', 'USD');

insert into public.opportunities (organization_id, client_id, property_id, quote_id, title, estimated_value)
select organization_id, client_id, property_id, id, title, case when quote_number = 1 then 4200 else null end
from public.quotes
where id in (
  'b1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000003'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);

-- 1. pipeline_board_page: each Quote stage returns its own card, with quote_id/quote_status filled and
--    request_id/request_status null -- the mirror image of what a Request-backed card already carries. ----

select is(
  (select quote_status from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'quote_draft') where quote_id = 'b1000000-0000-0000-0000-000000000001'),
  'draft', 'Q1 reads back in the Draft column with its own status'
);
select is(
  (select request_id from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'quote_draft') where quote_id = 'b1000000-0000-0000-0000-000000000001'),
  null, 'a quote-backed card carries no request pointer'
);
select is(
  (select estimated_value from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'quote_draft') where quote_id = 'b1000000-0000-0000-0000-000000000001'),
  4200::numeric, 'a member with pipeline.view_value still sees the estimate on a quote-backed card'
);
select is(
  (select quote_status from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'quote_awaiting_response') where quote_id = 'b1000000-0000-0000-0000-000000000002'),
  'awaiting_response', 'Q2 reads back in the Awaiting response column'
);
select is(
  (select quote_status from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'quote_changes_requested') where quote_id = 'b1000000-0000-0000-0000-000000000003'),
  'changes_requested', 'Q3 reads back in the Changes requested column'
);

-- 2. Request side is unbroken and carries no quote pointer -----------------------------------------------

select is(
  (select quote_id from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'new_request') where request_id = 'b0000000-0000-0000-0000-000000000001'),
  null, 'a request-backed card still carries no quote pointer'
);

-- 3. request_closed remains off the board -------------------------------------------------------------------

select throws_ok(
  $$select * from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'request_closed')$$,
  '22023', null, 'request_closed is parking, not a column -- still refused'
);

-- 4. Tenant isolation ---------------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select * from public.pipeline_board_page('ad000000-0000-0000-0000-000000000001', 'quote_draft')$$,
  '42501', null, 'an admin from another organization cannot read org A''s Quotes column'
);
select throws_ok(
  $$select * from public.pipeline_stage_counts('ad000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'nor its counts'
);

-- 5. pipeline_stage_counts: every Quote stage is now counted instead of silently dropped --------------------

select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);

select is(
  (select open_count from public.pipeline_stage_counts('ad000000-0000-0000-0000-000000000001') where stage_key = 'quote_draft'),
  1::bigint, 'the Draft column counts Q1'
);
select is(
  (select value_total from public.pipeline_stage_counts('ad000000-0000-0000-0000-000000000001') where stage_key = 'quote_draft'),
  4200::numeric, 'and totals its one estimate'
);
select is(
  (select value_total from public.pipeline_stage_counts('ad000000-0000-0000-0000-000000000001') where stage_key = 'quote_awaiting_response'),
  null, 'an unestimated Quote column totals null, never zero'
);

select * from finish();
rollback;
