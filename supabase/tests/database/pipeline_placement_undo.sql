-- Sales Pipeline, part D1: Undo for a custom-stage placement.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `pipeline_move_undo.sql` follows.
-- Everything in one transaction shares one `now()`, so every card here is given an older
-- `stage_entered_at`: that keeps its creating event behind the placement under test.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- Privileges --------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.pipeline_undo_placement(uuid, uuid)', 'execute'),
  false, 'anonymous callers cannot undo a placement'
);
select is(
  has_function_privilege('authenticated', 'public.pipeline_undo_placement(uuid, uuid)', 'execute'),
  true, 'authenticated members can ask to undo a placement'
);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('b6000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1p-admin-a@example.test', 'test', now(), now(), now()),
  ('b6000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1p-admin-a2@example.test', 'test', now(), now(), now()),
  ('b6000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd1p-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('b7000000-0000-0000-0000-000000000001', 'D1 Placement Org A', 'd1-placement-org-a', 'active'),
  ('b7000000-0000-0000-0000-000000000002', 'D1 Placement Org B', 'd1-placement-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('b7000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 'admin'),
  ('b7000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000002', 'admin'),
  ('b7000000-0000-0000-0000-000000000002', 'b6000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('b8000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'D1 Placement Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('b9000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', '1 Placement Street', 'Testville');

-- R1 placed then undone. R2 taken out of a custom stage then undone. R3 moved by somebody else.
-- R4 too long ago. R5 a real move happened last.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
select
  ('ba000000-0000-0000-0000-00000000000' || n)::uuid,
  'b7000000-0000-0000-0000-000000000001',
  'b8000000-0000-0000-0000-000000000001',
  'b9000000-0000-0000-0000-000000000001',
  'D1 Placement Request R' || n,
  'new'
from generate_series(1, 5) as n;

-- The cards the Request trigger made are replaced by ones that have been waiting ten days, with no real
-- progress for eight.
delete from public.opportunities where organization_id = 'b7000000-0000-0000-0000-000000000001';

insert into public.opportunities (
  organization_id, client_id, property_id, request_id, title, stage_entered_at, progress_at
)
select
  organization_id, client_id, property_id, id, title,
  now() - interval '10 days', now() - interval '8 days'
from public.requests
where organization_id = 'b7000000-0000-0000-0000-000000000001';

insert into public.pipeline_custom_stages (id, organization_id, section, name, after_stage, position)
values ('bb000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'request', 'D1 Call back', 'new_request', 0);

-- R2 has been sitting in the custom stage for five days. The card's trigger owns `stage_entered_at` and
-- stamps a placement with now(), so the fixture hands it the older time the only way it accepts one.
select set_config(
  'pipeline.undo_opportunity_id',
  (select id::text from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000002'),
  true
);
select set_config('pipeline.undo_stage_entered_at', (now() - interval '5 days')::text, true);
update public.opportunities
set custom_stage_id = 'bb000000-0000-0000-0000-000000000001'
where request_id = 'ba000000-0000-0000-0000-000000000002';
select set_config('pipeline.undo_opportunity_id', '', true);
update public.opportunity_stage_events
set occurred_at = now() - interval '5 days'
where to_custom_stage_id = 'bb000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000001', true);

-- 1. Placed in a custom stage, then Undo -------------------------------------------------------------

select is(
  (
    (select public.pipeline_place_opportunity(
      (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000001'),
      'bb000000-0000-0000-0000-000000000001'
    ))->>'applied'
  ),
  'true', 'the card is placed in the custom stage'
);
select is(
  (select stage_entered_at from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000001'),
  now(), 'and its time in stage starts again there'
);
select is(
  (
    select public.pipeline_undo_placement(
      (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000001'),
      'bb000000-0000-0000-0000-000000000001'
    )
  ),
  jsonb_build_object('stage', 'new_request', 'custom_stage_id', null),
  'Undo puts the card back in its real stage'
);
select is(
  (select stage_entered_at from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000001'),
  now() - interval '10 days', 'with the ten days it had already spent there'
);
select is(
  (select progress_at from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000001'),
  now() - interval '8 days', 'and the inactivity clock, which a placement never touches, unchanged'
);
select throws_ok(
  format(
    $$select public.pipeline_undo_placement(%L, 'bb000000-0000-0000-0000-000000000001')$$,
    (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000001')
  ),
  '23514', null, 'the same Undo cannot run twice'
);

-- 2. Taken out of a custom stage, then Undo ----------------------------------------------------------

select is(
  (
    (select public.pipeline_place_opportunity(
      (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000002'),
      null
    ))->>'applied'
  ),
  'true', 'the card is put back in its real stage'
);
select is(
  (
    select public.pipeline_undo_placement(
      (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000002'),
      null
    )
  ),
  jsonb_build_object('stage', 'new_request', 'custom_stage_id', 'bb000000-0000-0000-0000-000000000001'),
  'Undo returns it to the custom stage'
);
select is(
  (select stage_entered_at from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000002'),
  now() - interval '5 days', 'with the five days it had already spent in that stage'
);

-- 3. Refusals ---------------------------------------------------------------------------------------------

select public.pipeline_place_opportunity(
  (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000003'),
  'bb000000-0000-0000-0000-000000000001'
);
select public.pipeline_place_opportunity(
  (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000004'),
  'bb000000-0000-0000-0000-000000000001'
);

select throws_ok(
  format(
    $$select public.pipeline_undo_placement(%L, null)$$,
    (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000003')
  ),
  '23514', null, 'naming a placement that is not where the card is now is refused'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $$select public.pipeline_undo_placement(%L, 'bb000000-0000-0000-0000-000000000001')$$,
    (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000003')
  ),
  '23514', null, 'a teammate cannot undo a placement somebody else made'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000003', true);
select throws_ok(
  format(
    $$select public.pipeline_undo_placement(%L, 'bb000000-0000-0000-0000-000000000001')$$,
    (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000003')
  ),
  '42501', null, 'an admin from another organization cannot undo org A''s placement'
);

set local role postgres;
update public.opportunity_stage_events
set occurred_at = now() - interval '3 minutes'
where to_custom_stage_id = 'bb000000-0000-0000-0000-000000000001'
  and opportunity_id = (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000004');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000001', true);

select throws_ok(
  format(
    $$select public.pipeline_undo_placement(%L, 'bb000000-0000-0000-0000-000000000001')$$,
    (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000004')
  ),
  '23514', null, 'a placement made more than two minutes ago can no longer be undone'
);
select is(
  (select custom_stage_id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000004'),
  'bb000000-0000-0000-0000-000000000001'::uuid, 'a refused Undo changes nothing'
);

-- A real move was the last thing that happened to R5, so there is no placement to undo.
insert into public.assessments (organization_id, request_id)
values ('b7000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000005');

select throws_ok(
  format(
    $$select public.pipeline_undo_placement(%L, null)$$,
    (select id from public.opportunities where request_id = 'ba000000-0000-0000-0000-000000000005')
  ),
  '23514', null, 'a real move cannot be undone as if it were a placement'
);

select * from finish();
rollback;
