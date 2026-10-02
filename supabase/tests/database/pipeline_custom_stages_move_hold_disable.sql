-- Pipeline G2: custom follow-up stages -- moving a card among them (A2), switching one off (A3), and
-- on-hold stages (A4). Migrations 20261001220000, 20261001230000, 20261001234000.
-- Written for `supabase test db`; run it as one transaction rolled back at the end, the convention
-- `tenant_isolation.sql` documents. `set local role` and `set_config` do not survive a statement-by-statement runner.
begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'g2-stages-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c1100000-0000-0000-0000-000000000001', 'G2 Custom Stage Org', 'g2-custom-stage-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('c1100000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('c1200000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'G2 Stage Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('c1300000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', '1 Stage Street', 'Testville');

-- R1 moves among the stages. R2 and R3 sit in the stage that is switched off. R4 is never placed.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
select
  ('c1400000-0000-0000-0000-00000000000' || n)::uuid,
  'c1100000-0000-0000-0000-000000000001',
  'c1200000-0000-0000-0000-000000000001',
  'c1300000-0000-0000-0000-000000000001',
  'G2 Stage Request R' || n,
  'new'
from generate_series(1, 4) as n;

create temporary table g2_cards as
select right(title, 1)::int as n, id
from public.opportunities
where organization_id = 'c1100000-0000-0000-0000-000000000001';
grant select on g2_cards to authenticated;

-- Two ordinary Request stages, one on-hold Request stage, and one Quote stage.
insert into public.pipeline_custom_stages (id, organization_id, section, name, after_stage, position, requires_future_task)
values
  ('c1500000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'request', 'G2 Call back', 'new_request', 0, false),
  ('c1500000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'request', 'G2 Site photos asked', 'new_request', 1, false),
  ('c1500000-0000-0000-0000-000000000003', 'c1100000-0000-0000-0000-000000000001', 'request', 'G2 On hold', 'new_request', 2, true),
  ('c1500000-0000-0000-0000-000000000004', 'c1100000-0000-0000-0000-000000000001', 'quote', 'G2 Quote follow-up', 'quote_draft', 0, false);

-- Today by the organization's own calendar, read as the owner because members cannot call the helper.
create temporary table g2_today as
select private.organization_today('c1100000-0000-0000-0000-000000000001') as today;
grant select on g2_today to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 1. Moving among custom stages, in either direction -------------------------------------------------------

select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000001'))->>'applied',
  'true', 'a Request card goes into a Requests custom stage'
);
select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000002'))->>'applied',
  'true', 'it moves forward to the next custom stage'
);
select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000001'))->>'applied',
  'true', 'and backward again'
);
select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000001'))->>'applied',
  'false', 'placing it where it already is changes nothing'
);

set local role postgres;
select is(
  (select stage || ' / ' || outcome from public.opportunities where id = (select id from g2_cards where n = 1)),
  'new_request / open', 'a custom stage never rewrites the real stage or the outcome'
);
select is(
  (select count(*)::int from public.opportunity_stage_events
   where opportunity_id = (select id from g2_cards where n = 1) and to_custom_stage_id is not null),
  3, 'every move is one line of history'
);
set local role authenticated;

select throws_ok(
  $$select public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000004')$$,
  '23514', 'This is a request, so it can only go into a Requests stage. Convert it to a quote first.',
  'a Request card cannot cross into a Quotes stage'
);

-- 2. On hold needs a Task due after today ------------------------------------------------------------------

select throws_ok(
  $$select public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000003')$$,
  '23514', 'Cards in “G2 On hold” need a follow-up task with a future due date.',
  'a card with no Task cannot go on hold'
);

select lives_ok(
  $$select * from public.pipeline_create_opportunity_task(
      (select id from g2_cards where n = 1), 'Due today', null, null,
      (select today from g2_today))$$,
  'a Task due today is added'
);
select throws_ok(
  $$select public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000003')$$,
  '23514', 'Cards in “G2 On hold” need a follow-up task with a future due date.',
  'a Task due today is not a future Task'
);

select lives_ok(
  $$select * from public.pipeline_create_opportunity_task(
      (select id from g2_cards where n = 1), 'Due tomorrow', null, null,
      (select today + 1 from g2_today))$$,
  'a Task due tomorrow is added'
);
select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000003'))->>'applied',
  'true', 'with a Task due tomorrow the card goes on hold'
);

set local role postgres;
select is(
  (select outcome from public.opportunities where id = (select id from g2_cards where n = 1)),
  'open', 'a card on hold is still Open, never Lost'
);
set local role authenticated;

select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 1), null))->>'applied',
  'true', 'the card comes back out of on hold into its real column'
);

-- 3. A real action wins over the custom placement ----------------------------------------------------------

select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 4), 'c1500000-0000-0000-0000-000000000001'))->>'applied',
  'true', 'R4 is placed in a custom stage'
);

-- The Request now needs an assessment: the same two rows the real "assessment required" action writes.
set local role postgres;
update public.requests set status = 'unscheduled' where id = 'c1400000-0000-0000-0000-000000000004';
insert into public.assessments (organization_id, request_id, starts_at, ends_at, completed_at)
values ('c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000004', null, null, null);
select is(
  (select stage || ' / ' || coalesce(custom_stage_id::text, 'no custom stage')
   from public.opportunities where id = (select id from g2_cards where n = 4)),
  'assessment_unscheduled / no custom stage',
  'a real Request change moves the card to its protected stage and clears the placement'
);
set local role authenticated;

-- 4. Switching a stage off ---------------------------------------------------------------------------------

select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 2), 'c1500000-0000-0000-0000-000000000002'))->>'applied',
  'true', 'R2 is placed in the stage that will be switched off'
);
select is(
  (public.pipeline_place_opportunity((select id from g2_cards where n = 3), 'c1500000-0000-0000-0000-000000000002'))->>'applied',
  'true', 'R3 is placed there too'
);

select is(
  public.pipeline_custom_stage_card_count('c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002'),
  2, 'Settings is told the stage holds two cards'
);

create temporary table g2_revision as
select pipeline_revision as revision
from public.organization_settings
where organization_id = 'c1100000-0000-0000-0000-000000000001';

select is(
  public.disable_pipeline_custom_stage(
    'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002',
    (select revision from g2_revision)
  ),
  jsonb_build_object('status', 'needs_destination', 'card_count', 2),
  'a populated stage is not switched off until its cards have somewhere to go'
);

select is(
  (public.disable_pipeline_custom_stage(
    'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002',
    (select revision from g2_revision) + 7, null, true
  ))->>'status',
  'stale', 'a switch-off from an out-of-date screen is refused as stale'
);

select throws_ok(
  $$select public.disable_pipeline_custom_stage(
      'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002',
      (select revision from g2_revision), 'c1500000-0000-0000-0000-000000000004')$$,
  '23514', 'Cards can only move to a stage in the same section.',
  'the cards cannot be sent across to a Quotes stage'
);

select throws_ok(
  $$select public.disable_pipeline_custom_stage(
      'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002',
      (select revision from g2_revision), 'c1500000-0000-0000-0000-000000000003')$$,
  '23514',
  'Cards in “G2 On hold” need a follow-up task with a future due date, and some of these cards have none. Choose another place for them.',
  'the cards cannot be sent on hold when some have no future Task'
);

set local role postgres;
select is(
  (select count(*)::int from public.opportunities
   where custom_stage_id = 'c1500000-0000-0000-0000-000000000002'),
  2, 'a refused switch-off leaves both cards where they were'
);
set local role authenticated;

select is(
  public.disable_pipeline_custom_stage(
    'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002',
    (select revision from g2_revision), 'c1500000-0000-0000-0000-000000000001'
  ) - 'pipeline_revision',
  jsonb_build_object('status', 'disabled', 'moved_count', 2),
  'with a destination in the same section the stage is switched off and both cards move'
);

set local role postgres;
select is(
  (select count(*)::int from public.opportunities
   where custom_stage_id = 'c1500000-0000-0000-0000-000000000001'
     and id in (select id from g2_cards where n in (2, 3))),
  2, 'both cards now sit in the chosen stage'
);
select isnt(
  (select disabled_at from public.pipeline_custom_stages where id = 'c1500000-0000-0000-0000-000000000002'),
  null, 'the stage is kept, marked switched off, so old history still has its name'
);
select is(
  (select pipeline_revision from public.organization_settings
   where organization_id = 'c1100000-0000-0000-0000-000000000001'),
  (select revision + 1 from g2_revision),
  'the settings revision moves on by one'
);
set local role authenticated;

select throws_ok(
  $$select public.pipeline_place_opportunity((select id from g2_cards where n = 1), 'c1500000-0000-0000-0000-000000000002')$$,
  '23514', 'That stage is no longer on the board. Refresh the page and try again.',
  'no card can be placed in a switched-off stage'
);

select is(
  (public.disable_pipeline_custom_stage(
    'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000002',
    (select revision from g2_revision)
  ))->>'moved_count',
  '0', 'switching it off a second time is answered as already done'
);

-- An empty stage needs no destination.
select is(
  (public.disable_pipeline_custom_stage(
    'c1100000-0000-0000-0000-000000000001', 'c1500000-0000-0000-0000-000000000003',
    (select revision + 1 from g2_revision)
  ))->>'status',
  'disabled', 'an empty stage is switched off straight away'
);

select * from finish();
rollback;
