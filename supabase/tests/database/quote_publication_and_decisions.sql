-- Quotes, Part 5A: publishing a version, revising it, and recording a decision given off the app.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(50);

-- Money left the `authenticated` grant when the quote money columns were locked down, so these
-- assertions read stored money the same way they read fixture ids: through a definer helper, rather
-- than through the privileges of whichever member the test is currently pretending to be.
create function pg_temp.money(query text) returns bigint
language plpgsql stable security definer as $money$
declare result bigint;
begin
  execute query into result;
  return result;
end;
$money$;

-- 1. Shape and privileges ---------------------------------------------------------------------------------

select has_column('public', 'quotes', 'sent_at', 'a quote remembers when it went out');
select has_column('public', 'quotes', 'decision', 'a quote carries its current decision');
select has_column('public', 'quotes', 'decided_at', 'a decision is dated');
select has_column('public', 'quotes', 'decision_method', 'a decision says how it arrived');
select has_column('public', 'quotes', 'decision_note', 'a decision may carry a note');
select has_column('public', 'quotes', 'decided_by', 'a decision names who recorded it');
select has_index('public', 'quotes', 'quotes_decided_by_idx', 'the decision author foreign key is indexed');
select has_function('public', 'publish_quote', 'the publish command exists');
select has_function('public', 'revise_quote', 'the revise command exists');
select has_function('public', 'record_quote_decision', 'the offline decision command exists');
select is(has_function_privilege('authenticated', 'public.publish_quote(uuid,integer)', 'execute'), true,
  'staff publish through the command');
select is(has_function_privilege('authenticated', 'public.freeze_quote_version(uuid,integer)', 'execute'), false,
  'the freeze underneath it stays closed');
select is(has_function_privilege('authenticated', 'public.clone_quote_version_to_draft(uuid)', 'execute'), false,
  'the clone underneath revise stays closed');
select is(has_function_privilege('anon', 'public.record_quote_decision(uuid,text,text,integer)', 'execute'), false,
  'nobody signed out answers a quote');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'publish-admin@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'publish-field@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'publish-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c1000000-0000-0000-0000-000000000001', 'Publication Org A', 'publication-org-a', 'active'),
  ('c1000000-0000-0000-0000-000000000002', 'Publication Org B', 'publication-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'admin'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'field'),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'Publication Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001', '5 Publication Street', 'Testville');

create function pg_temp.qid() returns uuid language sql stable security definer as
  'select id from public.quotes where title = ''Publication quote''';
create function pg_temp.vid() returns uuid language sql stable security definer as
  'select draft_version_id from public.quotes where title = ''Publication quote''';
create function pg_temp.rev() returns integer language sql stable security definer as
  'select revision from public.quote_versions where id = pg_temp.vid()';
create function pg_temp.qstatus() returns text language sql stable security definer as
  'select status from public.quotes where title = ''Publication quote''';
create function pg_temp.published_number() returns integer language sql stable security definer as
  'select version_number from public.quote_versions where id =
     (select current_published_version_id from public.quotes where title = ''Publication quote'')';
create function pg_temp.version_count() returns integer language sql stable security definer as
  'select count(*)::integer from public.quote_versions where quote_id = pg_temp.qid()';
create function pg_temp.events(wanted_type text) returns integer language sql stable security definer as
  'select count(*)::integer from public.activity_events
    where entity_type = ''quote'' and entity_id = pg_temp.qid() and event_type = $1';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'Publication quote', null)$$,
  'a draft to publish'
);

-- 3. What publishing refuses -------------------------------------------------------------------------------

select throws_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.rev())$$,
  '23514', null, 'an empty quote is not a proposal'
);

select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('name', 'Roof repair', 'category', 'service', 'quantity', 2,
        'unit_price_minor', 50000, 'unit_cost_minor', 20000, 'is_taxable', false)
    ))$$,
  'the quote gets something to sell'
);

select throws_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.rev() - 1)$$,
  'P0409', null, 'a stale revision cannot publish someone else''s edit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.rev())$$,
  '42501', null, 'a field member cannot send a quote'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000001', true);

-- 4. Publishing --------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.rev())$$,
  'the draft is published'
);
select is(pg_temp.qstatus(), 'awaiting_response', 'the quote is now waiting on the customer');
select is(pg_temp.published_number(), 1, 'the first publication is version one');
select is(pg_temp.version_count(), 1, 'the draft became the version rather than adding a row');
select isnt((select sent_at from public.quotes where id = pg_temp.qid()), null, 'sending is dated');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = (select current_published_version_id from public.quotes where id = pg_temp.qid())$m$),
  100000::bigint, 'the published version carries its calculated total');
select is(pg_temp.events('quote.published'), 1, 'publishing is recorded in the quote history');

-- 5. Publishing twice is one publication ---------------------------------------------------------------------

select is(
  (select public.publish_quote(pg_temp.qid(),
    (select revision from public.quote_versions where id =
      (select current_published_version_id from public.quotes where id = pg_temp.qid()))) ->> 'already_published'),
  'true', 'a second click gets the version that already exists'
);
select is(pg_temp.version_count(), 1, 'no second version was created');
select is(pg_temp.events('quote.published'), 1, 'and no second history entry');

select throws_ok(
  $$select public.publish_quote(pg_temp.qid(), 999)$$,
  '23514', null, 'a quote already sent cannot be published again under a different revision'
);

-- 6. Revising ------------------------------------------------------------------------------------------------

select lives_ok($$select public.revise_quote(pg_temp.qid())$$, 'the sent quote can be revised');
select is(pg_temp.qstatus(), 'draft', 'revising puts the quote back in the drafting state');
select is(pg_temp.version_count(), 2, 'the clone is a new row beside the published one');
select isnt((select sent_at from public.quotes where id = pg_temp.qid()), null,
  'revising does not unsend what the customer already saw');
select is(pg_temp.events('quote.revised'), 1, 'revising is recorded in the quote history');

select throws_ok(
  $$select public.revise_quote(pg_temp.qid())$$,
  '23514', null, 'a quote already being drafted cannot be revised again'
);

-- 7. Recording a decision -------------------------------------------------------------------------------------

select lives_ok(
  $$select public.record_quote_decision(pg_temp.qid(), 'approved', 'Said yes on the phone.', pg_temp.rev())$$,
  'a draft answered off the app is published and then approved'
);
select is(pg_temp.qstatus(), 'approved', 'the quote is approved');
select is(pg_temp.published_number(), 2, 'the approval sits on the version that was just sent');
select is((select decision_method from public.quotes where id = pg_temp.qid()), 'offline_verbal',
  'the method says how the answer arrived');
select is((select decision_note from public.quotes where id = pg_temp.qid()), 'Said yes on the phone.',
  'the note is kept');
select is((select decided_by from public.quotes where id = pg_temp.qid()),
  'c0000000-0000-0000-0000-000000000001'::uuid, 'the decision names who recorded it');
select is(pg_temp.events('quote.approved'), 1, 'the approval is in the quote history');

select is(
  (select public.record_quote_decision(pg_temp.qid(), 'approved', null, null) ->> 'already_decided'),
  'true', 'recording the same answer twice is the same answer'
);

select throws_ok(
  $$select public.record_quote_decision(pg_temp.qid(), 'maybe', null, null)$$,
  '23514', null, 'a decision is either approved or declined'
);

-- 8. An approved quote can still be revised, and the old answer stops being current ---------------------------

select lives_ok($$select public.revise_quote(pg_temp.qid())$$, 'an approved quote can be revised');
select is((select decision from public.quotes where id = pg_temp.qid()), null,
  'the approval no longer describes the quote on the table');
select is((select decided_at from public.quotes where id = pg_temp.qid()), null,
  'and its date goes with it');

-- 9. RLS ------------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000003', true);
select is((select count(*)::integer from public.quotes), 0, 'another organization sees no quotes');
select throws_ok(
  $$select public.publish_quote(pg_temp.qid(), 1)$$,
  '42501', null, 'and cannot publish one it cannot see'
);

select * from finish();
rollback;
