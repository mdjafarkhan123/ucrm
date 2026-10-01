-- Sales Pipeline, part D1: the short Undo for a reversible board move.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `pipeline_drag_transitions.sql`
-- documents. Everything in one transaction shares one `now()`, so every card here is given an older
-- `stage_entered_at`: that keeps its creating event behind the move under test, as it always is for real.
begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- Privileges --------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.pipeline_undo_move(uuid, text, text, boolean)', 'execute'),
  false, 'anonymous callers cannot undo a move'
);
select is(
  has_function_privilege('authenticated', 'public.pipeline_undo_move(uuid, text, text, boolean)', 'execute'),
  true, 'authenticated members can ask to undo a move'
);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('a6000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1-admin-a@example.test', 'test', now(), now(), now()),
  ('a6000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1-admin-a2@example.test', 'test', now(), now(), now()),
  ('a6000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('a7000000-0000-0000-0000-000000000001', 'D1 Undo Org A', 'd1-undo-org-a', 'active'),
  ('a7000000-0000-0000-0000-000000000002', 'D1 Undo Org B', 'd1-undo-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('a7000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000001', 'admin'),
  ('a7000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000002', 'admin'),
  ('a7000000-0000-0000-0000-000000000002', 'a6000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('a8000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001', 'D1 Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('a9000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001', '1 Undo Street', 'Testville');

-- R1 require then undo. R2 schedule from New then undo. R3 book an unscheduled assessment then undo.
-- R4 complete then undo. R5 changed after the move. R6 moved by somebody else. R7 too long ago.
-- R8 dragged out of a custom stage.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
select
  ('aa000000-0000-0000-0000-00000000000' || n)::uuid,
  'a7000000-0000-0000-0000-000000000001',
  'a8000000-0000-0000-0000-000000000001',
  'a9000000-0000-0000-0000-000000000001',
  'D1 Request R' || n,
  case when n in (3, 4) then 'unscheduled' else 'new' end
from generate_series(1, 8) as n;

insert into public.assessments (organization_id, request_id, instructions)
values
  ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000003', 'Bring the long ladder'),
  ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000004', null);

-- The cards the Request trigger made are replaced by ones that have been waiting ten days, with no real
-- progress for eight.
delete from public.opportunities where organization_id = 'a7000000-0000-0000-0000-000000000001';

insert into public.opportunities (
  organization_id, client_id, property_id, request_id, title, stage_entered_at, progress_at
)
select
  organization_id, client_id, property_id, id, title,
  now() - interval '10 days', now() - interval '8 days'
from public.requests
where organization_id = 'a7000000-0000-0000-0000-000000000001';

insert into public.pipeline_custom_stages (id, organization_id, section, name, after_stage, position)
values ('ab000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001', 'request', 'D1 Waiting on customer', 'new_request', 0);

update public.opportunities
set custom_stage_id = 'ab000000-0000-0000-0000-000000000001'
where request_id = 'aa000000-0000-0000-0000-000000000008';

update public.opportunity_stage_events
set occurred_at = now() - interval '5 days'
where to_custom_stage_id = 'ab000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000001', true);

-- 1. "Assessment required", then Undo ---------------------------------------------------------------------
-- The same two writes the move route makes.

insert into public.assessments (organization_id, request_id)
values ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001');
update public.requests set status = 'unscheduled'
where id = 'aa000000-0000-0000-0000-000000000001' and status = 'new';

select is(
  (select stage from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000001'),
  'assessment_unscheduled', 'requiring an assessment moves the card to Assessment unscheduled'
);
select is(
  (
    select public.pipeline_undo_move(
      (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000001'),
      'new_request', 'assessment_unscheduled', true
    )
  ),
  jsonb_build_object('stage', 'new_request', 'custom_stage_id', null),
  'Undo puts the card back in New requests'
);
select is(
  (select count(*) from public.assessments where request_id = 'aa000000-0000-0000-0000-000000000001'),
  0::bigint, 'the assessment the move created is gone'
);
select is(
  (select status from public.requests where id = 'aa000000-0000-0000-0000-000000000001'),
  'new', 'the Request is New again'
);
select is(
  (select stage_entered_at from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000001'),
  now() - interval '10 days', 'the card keeps the ten days it had already spent in the stage'
);
select is(
  (select progress_at from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000001'),
  now() - interval '8 days', 'the inactivity clock is put back, so a warning that was showing still shows'
);
select is(
  (
    select array_agg(coalesce(from_stage, '-') || '>' || to_stage order by occurred_at)
    from public.opportunity_stage_events
    where opportunity_id = (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000001')
  ),
  array['->new_request', 'new_request>assessment_unscheduled', 'assessment_unscheduled>new_request'],
  'history keeps both the move and its Undo, in order'
);
select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'new_request', 'assessment_unscheduled', true)$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'the same Undo cannot run twice'
);

-- 2. Scheduled straight from New requests, then Undo ----------------------------------------------------

insert into public.assessments (organization_id, request_id, starts_at, ends_at)
values ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002', now() + interval '1 day', now() + interval '1 day 1 hour');

select is(
  (
    (select public.pipeline_undo_move(
      (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000002'),
      'new_request', 'assessment_scheduled', false
    ))->>'stage'
  ),
  'new_request', 'a booking made from New requests can be undone'
);
select is(
  (select count(*) from public.assessments where request_id = 'aa000000-0000-0000-0000-000000000002'),
  0::bigint, 'and its assessment is removed'
);

-- 3. Booking an assessment that already existed, then Undo --------------------------------------------

update public.assessments
set starts_at = now() + interval '1 day', ends_at = now() + interval '1 day 1 hour'
where request_id = 'aa000000-0000-0000-0000-000000000003';

select is(
  (
    (select public.pipeline_undo_move(
      (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000003'),
      'assessment_unscheduled', 'assessment_scheduled'
    ))->>'stage'
  ),
  'assessment_unscheduled', 'a booking can be undone back to Assessment unscheduled'
);
select is(
  (select starts_at is null and ends_at is null and instructions = 'Bring the long ladder'
   from public.assessments where request_id = 'aa000000-0000-0000-0000-000000000003'),
  true, 'only the time is cleared; the assessment and its instructions stay'
);
select is(
  (select progress_at from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000003'),
  now() - interval '8 days', 'booking counted as progress, and undoing it takes that back'
);

-- 4. Completing, then Undo ---------------------------------------------------------------------------------

update public.assessments set completed_at = now()
where request_id = 'aa000000-0000-0000-0000-000000000004';
update public.requests set status = 'assessment_completed'
where id = 'aa000000-0000-0000-0000-000000000004' and status in ('new', 'unscheduled');

select is(
  (
    (select public.pipeline_undo_move(
      (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000004'),
      'assessment_unscheduled', 'assessment_completed'
    ))->>'stage'
  ),
  'assessment_unscheduled', 'a completion can be undone'
);
select is(
  (select completed_at is null from public.assessments where request_id = 'aa000000-0000-0000-0000-000000000004'),
  true, 'the assessment is no longer complete'
);
select is(
  (select status from public.requests where id = 'aa000000-0000-0000-0000-000000000004'),
  'unscheduled', 'and the Request is back to Unscheduled'
);

-- 5. Refusals ---------------------------------------------------------------------------------------------

insert into public.assessments (organization_id, request_id, instructions)
values ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000005', 'Gate code 4411');

select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'new_request', 'assessment_unscheduled', true)$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000005')
  ),
  '23514', null, 'an assessment somebody has since written instructions on is not thrown away'
);
select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'assessment_unscheduled', 'assessment_scheduled')$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000005')
  ),
  '23514', null, 'naming a move that is not the last one is refused'
);
select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'quote_draft', 'quote_awaiting_response')$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000005')
  ),
  '23514', null, 'a move that is not on the reversible list is refused'
);

insert into public.assessments (organization_id, request_id)
values
  ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000006'),
  ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000007');

select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'new_request', 'assessment_unscheduled', true)$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000006')
  ),
  '23514', null, 'a teammate cannot undo a move somebody else made'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000003', true);
select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'new_request', 'assessment_unscheduled', true)$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000006')
  ),
  '42501', null, 'an admin from another organization cannot undo org A''s move'
);

set local role postgres;
update public.opportunity_stage_events
set occurred_at = now() - interval '3 minutes'
where to_stage = 'assessment_unscheduled'
  and opportunity_id = (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000007');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000001', true);

select throws_ok(
  format(
    $$select public.pipeline_undo_move(%L, 'new_request', 'assessment_unscheduled', true)$$,
    (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000007')
  ),
  '23514', null, 'a move made more than two minutes ago can no longer be undone'
);
select is(
  (select stage from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000007'),
  'assessment_unscheduled', 'a refused Undo changes nothing'
);

-- 6. A card dragged out of a custom stage goes back into it ------------------------------------------

insert into public.assessments (organization_id, request_id)
values ('a7000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000008');

select is(
  (select custom_stage_id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000008'),
  null, 'a real action takes the card out of its custom stage'
);
select is(
  (
    select public.pipeline_undo_move(
      (select id from public.opportunities where request_id = 'aa000000-0000-0000-0000-000000000008'),
      'new_request', 'assessment_unscheduled', true
    )
  ),
  jsonb_build_object('stage', 'new_request', 'custom_stage_id', 'ab000000-0000-0000-0000-000000000001'),
  'Undo returns it to the custom stage it was dragged out of'
);
select is(
  (select count(*) from public.assessments where request_id = 'aa000000-0000-0000-0000-000000000008'),
  0::bigint, 'with the assessment removed'
);

select * from finish();
rollback;
