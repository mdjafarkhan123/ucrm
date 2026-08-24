-- Sales Pipeline, Part 5B: the forward-only drag gate.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `pipeline_outcome_engine.sql` and
-- `pipeline_quote_stage_and_outcome_automation.sql` document. `pipeline_drag_opportunity` performs no
-- write, so the same fixture row can be asked about more than one target stage without mutating it between
-- assertions -- only the read (current stage, permission, tenant) changes from call to call.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- Privileges --------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.pipeline_drag_opportunity(uuid, text)', 'execute'),
  false, 'anonymous callers cannot ask for a drag'
);
select is(
  has_function_privilege('authenticated', 'public.pipeline_drag_opportunity(uuid, text)', 'execute'),
  true, 'authenticated members can ask for a drag'
);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('96000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5b-admin-a@example.test', 'test', now(), now(), now()),
  ('96000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5b-admin-b@example.test', 'test', now(), now(), now()),
  ('96000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5b-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('97000000-0000-0000-0000-000000000001', '5B Drag Org A', '5b-drag-org-a', 'active'),
  ('97000000-0000-0000-0000-000000000002', '5B Drag Org B', '5b-drag-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('97000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000001', 'admin'),
  ('97000000-0000-0000-0000-000000000002', '96000000-0000-0000-0000-000000000002', 'admin'),
  ('97000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000003', 'field');

insert into public.clients (id, organization_id, display_name)
values
  ('98000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001', '5B Client A'),
  ('98000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000002', '5B Client B (other org)');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('99000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '1 Drag Street', 'Testville'),
  ('99000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000002', '98000000-0000-0000-0000-000000000002', '1 Other Org Street', 'Testville');

-- R1 new_request, R2 assessment_unscheduled, R3 assessment_scheduled, R4 assessment_completed. R5 lives in
-- org B, used only for the cross-tenant check.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
values
  ('9a000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', '5B Request R1', 'new'),
  ('9a000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', '5B Request R2', 'unscheduled'),
  ('9a000000-0000-0000-0000-000000000003', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', '5B Request R3', 'unscheduled'),
  ('9a000000-0000-0000-0000-000000000004', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', '5B Request R4', 'assessment_completed'),
  ('9a000000-0000-0000-0000-000000000005', '97000000-0000-0000-0000-000000000002', '98000000-0000-0000-0000-000000000002', '99000000-0000-0000-0000-000000000002', '5B Request R5 (other org)', 'new');

insert into public.assessments (organization_id, request_id, starts_at, ends_at, completed_at)
values
  ('97000000-0000-0000-0000-000000000001', '9a000000-0000-0000-0000-000000000002', null, null, null),
  ('97000000-0000-0000-0000-000000000001', '9a000000-0000-0000-0000-000000000003', now() + interval '1 day', now() + interval '1 day 1 hour', null),
  ('97000000-0000-0000-0000-000000000001', '9a000000-0000-0000-0000-000000000004', now() - interval '1 day', now() - interval '1 day' + interval '1 hour', now());

-- Quotes never go through create_quote here, so their opportunities are inserted by hand, exactly like
-- Part 5A's own fixtures do. Q1 draft, Q2 awaiting_response, Q3 changes_requested.
insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values
  ('9b000000-0000-0000-0000-000000000001', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', 1, '5B Quote Q1', 'draft', 'USD'),
  ('9b000000-0000-0000-0000-000000000002', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', 2, '5B Quote Q2', 'awaiting_response', 'USD'),
  ('9b000000-0000-0000-0000-000000000003', '97000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-000000000001', 3, '5B Quote Q3', 'changes_requested', 'USD');

insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
select organization_id, client_id, property_id, id, title from public.quotes
where id in (
  '9b000000-0000-0000-0000-000000000001', '9b000000-0000-0000-0000-000000000002', '9b000000-0000-0000-0000-000000000003'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '96000000-0000-0000-0000-000000000001', true);

-- 1. New requests -----------------------------------------------------------------------------------------

select is(
  (
    select public.pipeline_drag_opportunity(
      (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000001'),
      'assessment_unscheduled'
    )
  ),
  jsonb_build_object(
    'organization_id', '97000000-0000-0000-0000-000000000001',
    'request_id', '9a000000-0000-0000-0000-000000000001',
    'quote_id', null,
    'from_stage', 'new_request'
  ),
  'a fresh request can be dragged onto Assessment unscheduled'
);

select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'assessment_completed')$$,
    (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'New requests cannot be dragged straight onto Assessment completed -- that needs two commands'
);

-- 2. Assessment unscheduled ---------------------------------------------------------------------------------

select is(
  (
    (select public.pipeline_drag_opportunity(
      (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000002'),
      'assessment_scheduled'
    ))->>'from_stage'
  ),
  'assessment_unscheduled', 'an unscheduled assessment can be dragged onto Assessment scheduled'
);
select is(
  (
    (select public.pipeline_drag_opportunity(
      (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000002'),
      'assessment_completed'
    ))->>'from_stage'
  ),
  'assessment_unscheduled', 'an unscheduled assessment can also be dragged straight onto Assessment completed'
);

-- 3. Assessment scheduled -----------------------------------------------------------------------------------

select is(
  (
    (select public.pipeline_drag_opportunity(
      (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000003'),
      'assessment_completed'
    ))->>'from_stage'
  ),
  'assessment_scheduled', 'a scheduled assessment can be dragged onto Assessment completed'
);
select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'assessment_unscheduled')$$,
    (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000003')
  ),
  '23514', null, 'a scheduled assessment cannot be dragged backward onto Assessment unscheduled'
);

-- 4. Assessment completed has no forward drag target ----------------------------------------------------------

select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'assessment_scheduled')$$,
    (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000004')
  ),
  '23514', null, 'Assessment completed is not a source for any further drag'
);

-- 5. Quotes -----------------------------------------------------------------------------------------------

select is(
  (
    select public.pipeline_drag_opportunity(
      (select id from public.opportunities where quote_id = '9b000000-0000-0000-0000-000000000001'),
      'quote_awaiting_response'
    )
  ),
  jsonb_build_object(
    'organization_id', '97000000-0000-0000-0000-000000000001',
    'request_id', null,
    'quote_id', '9b000000-0000-0000-0000-000000000001',
    'from_stage', 'quote_draft'
  ),
  'a draft quote can be dragged onto Awaiting response'
);
select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'quote_changes_requested')$$,
    (select id from public.opportunities where quote_id = '9b000000-0000-0000-0000-000000000002')
  ),
  '23514', null, 'staff cannot drag Awaiting response onto Changes requested -- only the client can request changes'
);
select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'quote_draft')$$,
    (select id from public.opportunities where quote_id = '9b000000-0000-0000-0000-000000000003')
  ),
  '23514', null, 'Changes requested cannot be dragged onto Draft -- Revise stays a Quote-page action'
);
select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'quote_awaiting_response')$$,
    (select id from public.opportunities where quote_id = '9b000000-0000-0000-0000-000000000003')
  ),
  '23514', null, 'Changes requested cannot be dragged onto Awaiting response -- Republish stays a Quote-page action'
);

-- 6. Direct writes still refused, and this function performs none itself --------------------------------------

select is(
  (select stage from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000001'),
  'new_request', 'asking about a drag never actually moves the card'
);

-- 7. Permission and tenant isolation --------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '96000000-0000-0000-0000-000000000003', true);
select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'assessment_unscheduled')$$,
    (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000001')
  ),
  '42501', null, 'a field-role member without pipeline.edit cannot ask for a drag'
);

select set_config('request.jwt.claim.sub', '96000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $$select public.pipeline_drag_opportunity(%L, 'assessment_unscheduled')$$,
    (select id from public.opportunities where request_id = '9a000000-0000-0000-0000-000000000001')
  ),
  '42501', null, 'an admin from another organization cannot drag org A''s card'
);
select throws_ok(
  $$select public.pipeline_drag_opportunity('00000000-0000-0000-0000-000000000000', 'assessment_unscheduled')$$,
  '42501', null, 'an opportunity id that does not exist is refused the same way as one with no access'
);

select * from finish();
rollback;
