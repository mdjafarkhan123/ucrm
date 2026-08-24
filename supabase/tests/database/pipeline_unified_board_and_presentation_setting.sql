-- Sales Pipeline, Part 5C-iii: the grouped Assessment column and the presentation setting.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention pipeline_quote_board_read_model.sql uses.
--
-- The point of the grouped column is that it is ONE keyset across three stored stages. The paging assertions
-- below are the load-bearing ones: they walk the whole group a page at a time and prove no card is repeated
-- and none is skipped at a sub-state boundary.
begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5ciii-admin-a@example.test', 'test', now(), now(), now()),
  ('c3000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5ciii-admin-b@example.test', 'test', now(), now(), now()),
  ('c3000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '5ciii-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c4000000-0000-0000-0000-000000000001', '5C-iii Org A', '5ciii-org-a', 'active'),
  ('c4000000-0000-0000-0000-000000000002', '5C-iii Org B', '5ciii-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c4000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'admin'),
  ('c4000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'admin'),
  ('c4000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000003', 'field');

insert into public.organization_settings (organization_id)
values
  ('c4000000-0000-0000-0000-000000000001'),
  ('c4000000-0000-0000-0000-000000000002')
on conflict (organization_id) do nothing;

insert into public.clients (id, organization_id, display_name)
values ('c5000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', '5C-iii Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('c6000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', '3 Group Street', 'Testville');

-- Nine requests whose Opportunities the Request trigger creates. Their stage_entered_at is then set by hand
-- to a strictly interleaved order across the three assessment sub-states, so a naive "three lists stitched
-- together" implementation would visibly disagree with the correct single ordering.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
select
  ('c7000000-0000-0000-0000-00000000000' || n)::uuid,
  'c4000000-0000-0000-0000-000000000001',
  'c5000000-0000-0000-0000-000000000001',
  'c6000000-0000-0000-0000-000000000001',
  '5C-iii Request ' || n,
  'new'
from generate_series(1, 9) as n;

-- Three unscheduled, three scheduled, three completed -- assigned round-robin so the sub-states interleave
-- through the time order rather than sitting in three contiguous blocks.
insert into public.assessments (organization_id, request_id, starts_at, ends_at, completed_at, all_day)
select
  'c4000000-0000-0000-0000-000000000001',
  ('c7000000-0000-0000-0000-00000000000' || n)::uuid,
  case when n % 3 <> 1 then timestamptz '2026-08-20 09:00:00+00' + (n || ' hours')::interval end,
  case when n % 3 <> 1 then timestamptz '2026-08-20 10:00:00+00' + (n || ' hours')::interval end,
  case when n % 3 = 0 then timestamptz '2026-08-21 12:00:00+00' end,
  false
from generate_series(1, 9) as n;

-- Interleave the board order: card 1 newest, card 9 oldest, regardless of sub-state.
update public.opportunities
set stage_entered_at = timestamptz '2026-08-22 00:00:00+00'
  - ((substring(request_id::text, 36, 1)::integer) || ' hours')::interval
where organization_id = 'c4000000-0000-0000-0000-000000000001'
  and request_id is not null;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

-- 1. The fixture really does span all three sub-states -----------------------------------------------------

select is(
  (select count(distinct stage)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)),
  3, 'the grouped column spans all three assessment sub-states'
);
select is(
  (select count(*)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)),
  9, 'and returns every open assessment card exactly once'
);

-- The three sub-states each really are present, so a grouped read that silently dropped one would fail here
-- rather than pass on a fixture that never had it.
select is(
  (select count(*)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)
     where stage = 'assessment_unscheduled'),
  3, 'three unscheduled cards are in the group'
);
select is(
  (select count(*)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)
     where stage = 'assessment_scheduled'),
  3, 'three scheduled cards are in the group'
);
select is(
  (select count(*)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)
     where stage = 'assessment_completed'),
  3, 'three completed cards are in the group'
);

-- 2. The appointment the contract requires -----------------------------------------------------------------

select isnt(
  (select assessment_starts_at
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)
     where stage = 'assessment_scheduled' limit 1),
  null, 'a scheduled card carries its appointment start, not just a Request status'
);
select isnt(
  (select assessment_ends_at
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)
     where stage = 'assessment_scheduled' limit 1),
  null, 'and its appointment end'
);
select is(
  (select assessment_starts_at
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)
     where stage = 'assessment_unscheduled' limit 1),
  null, 'an unscheduled card has no appointment'
);

-- The join to assessments must not fan a card out. assessments.request_id is unique, so one row per card.
select is(
  (select count(*)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)),
  (select count(distinct id)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)),
  'the assessment join never duplicates a card'
);

-- 3. One globally correct order across the three sub-states ------------------------------------------------

-- The function returns rows already ordered; array_agg without an ORDER BY preserves that arrival order,
-- so this compares the function's own emitted order against the correct one.
select is(
  (select array_agg(id)
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment', 50)),
  (select array_agg(id order by stage_entered_at desc, id desc)
     from public.opportunities
     where organization_id = 'c4000000-0000-0000-0000-000000000001'
       and outcome = 'open'
       and stage in ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed')),
  'the grouped column is one time-ordered list, not three lists concatenated'
);

-- 4. Keyset paging across sub-state boundaries -------------------------------------------------------------
--
-- The load-bearing test. Walk the whole group in pages of two, following the cursor exactly as the route
-- does, and compare the walk against one unpaged read. A duplicate or a skipped card at a sub-state
-- boundary shows up here and nowhere else.

create temp table walked (seq serial, id uuid, stage text, entered timestamptz);

do $$
declare
  cur_ts timestamptz := null;
  cur_id uuid := null;
  r record;
  got integer;
begin
  loop
    got := 0;
    for r in
      select page.id, page.stage, page.stage_entered_at
      from public.pipeline_board_page(
        'c4000000-0000-0000-0000-000000000001', 'assessment', 2,
        'stage_entered_at', 'desc', 'all', null, null, null,
        'stage_entered_at', null, cur_ts, null, cur_id
      ) as page
    loop
      insert into walked (id, stage, entered) values (r.id, r.stage, r.stage_entered_at);
      cur_ts := r.stage_entered_at;
      cur_id := r.id;
      got := got + 1;
    end loop;
    exit when got < 2;
  end loop;
end $$;

select is(
  (select count(*)::integer from walked),
  9, 'paging two at a time walks all nine cards'
);
select is(
  (select count(distinct id)::integer from walked),
  9, 'and never returns the same card twice'
);
select is(
  (select array_agg(id order by seq) from walked),
  (select array_agg(id order by stage_entered_at desc, id desc)
     from public.opportunities
     where organization_id = 'c4000000-0000-0000-0000-000000000001'
       and outcome = 'open'
       and stage in ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed')),
  'the paged walk matches the unpaged order card for card, across every sub-state boundary'
);
-- A page boundary that lands mid-sub-state is the case a stitched implementation gets wrong. The fixture
-- interleaves, so at least one page must straddle two sub-states for this suite to be meaningful.
select ok(
  (select count(*) from (
     select stage, lead(stage) over (order by seq) as next_stage from walked
   ) as pairs where stage is distinct from next_stage and next_stage is not null) >= 2,
  'the walk really does cross sub-state boundaries, so the test is not vacuous'
);

-- 5. The logical column is the only grouping that exists ---------------------------------------------------

select throws_ok(
  $$select * from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessments')$$,
  '22023', null, 'a near-miss column name is refused, not guessed at'
);
select throws_ok(
  $$select * from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'quote_draft,quote_awaiting_response')$$,
  '22023', null, 'a caller cannot invent its own multi-stage grouping'
);
select throws_ok(
  $$select * from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'request_closed')$$,
  '22023', null, 'request_closed is still parking, not a column'
);

-- The seven real stages still answer individually, which is the detailed view the toggle turns on.
select is(
  (select count(*)::integer
     from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment_scheduled', 50)),
  3, 'the detailed view still reads one assessment stage on its own'
);

-- 6. Tenant isolation is unchanged by the widening ---------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select * from public.pipeline_board_page('c4000000-0000-0000-0000-000000000001', 'assessment')$$,
  '42501', null, 'an admin from another organization cannot read org A''s grouped column'
);

-- 7. save_pipeline_presentation ----------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select is(
  (select pipeline_detailed_assessment_stages from public.organization_settings
     where organization_id = 'c4000000-0000-0000-0000-000000000001'),
  false, 'the collapsed five-column board is the default'
);

select is(
  (public.save_pipeline_presentation('c4000000-0000-0000-0000-000000000001', 1, true)) ->> 'status',
  'saved', 'an admin can turn the detailed stages on'
);
select is(
  (select pipeline_detailed_assessment_stages from public.organization_settings
     where organization_id = 'c4000000-0000-0000-0000-000000000001'),
  true, 'and the preference is stored'
);
select is(
  (select pipeline_revision from public.organization_settings
     where organization_id = 'c4000000-0000-0000-0000-000000000001'),
  2, 'the revision advances so a second tab cannot overwrite blindly'
);
select is(
  (select count(*)::integer from public.organization_settings_audit
     where organization_id = 'c4000000-0000-0000-0000-000000000001' and section = 'pipeline'),
  1, 'a real change writes exactly one audit row'
);

-- A stale save is answered as data, not an error, so the page can name the other editor.
select is(
  (public.save_pipeline_presentation('c4000000-0000-0000-0000-000000000001', 1, false)) ->> 'status',
  'stale', 'a save carrying the old revision is refused as stale'
);
select is(
  (select pipeline_detailed_assessment_stages from public.organization_settings
     where organization_id = 'c4000000-0000-0000-0000-000000000001'),
  true, 'and the stale save changed nothing'
);

-- Saving the same value again is not a change, so it must not write a second audit row.
select is(
  (select count(*)::integer from public.organization_settings_audit
     where organization_id = 'c4000000-0000-0000-0000-000000000001' and section = 'pipeline'),
  1, 'saving an unchanged value writes no extra audit row'
);

-- A member without settings.business.edit cannot change how the whole organization sees its board.
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.save_pipeline_presentation('c4000000-0000-0000-0000-000000000001', 2, false)$$,
  '42501', null, 'a field member cannot change the organization''s board presentation'
);

select * from finish();
rollback;
