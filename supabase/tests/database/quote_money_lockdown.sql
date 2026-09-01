-- Quotes: the money permissions are absolute, not just respected by the API routes.
-- A member may hold `quotes.view` and still be denied `quotes.view_price` or `quotes.view_cost`. This
-- proves the denial survives a reader who skips the routes entirely and talks to PostgREST directly.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(20);

-- 1. Shape and privileges ---------------------------------------------------------------------------------

select has_function('public', 'quote_version_money', 'the gated reader for version totals exists');
select has_function('public', 'quote_line_money', 'the gated reader for line money exists');
select is(has_function_privilege('authenticated', 'public.quote_version_money(uuid[])', 'execute'),
  true, 'staff reach version money through its reader');
select is(has_function_privilege('anon', 'public.quote_line_money(uuid)', 'execute'),
  false, 'a signed-out caller reaches neither');

-- The money columns are gone from the grant, so no session can select them whatever its permissions say.
select is(has_column_privilege('authenticated', 'public.quote_versions', 'total_minor', 'select'),
  false, 'the total is not a column anybody may select');
select is(has_column_privilege('authenticated', 'public.quote_versions', 'cost_minor', 'select'),
  false, 'neither is cost');
select is(has_column_privilege('authenticated', 'public.quote_versions', 'discount_value', 'select'),
  false, 'a fixed discount is the discount, so it goes with the rest of the money');
select is(has_column_privilege('authenticated', 'public.quote_version_lines', 'unit_price_minor', 'select'),
  false, 'nor a line price');
select is(has_column_privilege('authenticated', 'public.quote_version_lines', 'unit_cost_minor', 'select'),
  false, 'nor a line cost');
select is(has_column_privilege('authenticated', 'public.quote_versions', 'revision', 'select'),
  true, 'everything that is not money is still readable');
select is(has_column_privilege('authenticated', 'public.quote_version_lines', 'name', 'select'),
  true, 'a line still says what it is');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'money-lockdown-admin@example.test', 'test', now(), now(), now()),
  ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'money-lockdown-sales@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c1000000-0000-0000-0000-000000000001', 'Money Lockdown Org', 'money-lockdown-org', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'admin'),
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'sales');

insert into public.clients (id, organization_id, display_name) values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'Money Lockdown Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001', '11 Ledger Lane', 'Testville');

create function pg_temp.qid() returns uuid language sql stable security definer as
  'select id from public.quotes where title = ''Money lockdown quote''';
create function pg_temp.vid() returns uuid language sql stable security definer as
  'select draft_version_id from public.quotes where title = ''Money lockdown quote''';
create function pg_temp.rev() returns integer language sql stable security definer as
  'select revision from public.quote_versions where id = pg_temp.vid()';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'Money lockdown quote', null)$$,
  'a quote with money on it'
);
select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('name', 'Core work', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 5000, 'unit_cost_minor', 2000, 'is_taxable', false)
    ))$$,
  'and a line to price'
);

-- A payment schedule item and a deposit receipt: rows that are nothing but money.
set local role postgres;
insert into public.quote_version_schedule_items
  (organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit)
values
  ('c1000000-0000-0000-0000-000000000001', pg_temp.qid(), pg_temp.vid(), 0, 'Deposit', 'percentage', 2500, true);
insert into public.quote_deposit_events
  (organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key)
values
  ('c1000000-0000-0000-0000-000000000001', pg_temp.qid(), pg_temp.vid(), 'received', 1250, 'cash',
   'money-lockdown-1');

-- 3. What each reader is owed ------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000001', true);
select is(
  (public.quote_version_money(array[pg_temp.vid()]) -> pg_temp.vid()::text ->> 'total_minor')::bigint,
  5000::bigint, 'an admin reads the total through the reader');
select is(
  public.quote_version_money(array[pg_temp.vid()]) -> pg_temp.vid()::text ? 'cost_minor',
  true, 'and cost, which is the other permission');

-- Sales prices work every day and never sees cost. That is a normal Jobber state, not an edge case.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);
select is(
  (public.quote_version_money(array[pg_temp.vid()]) -> pg_temp.vid()::text ->> 'total_minor')::bigint,
  5000::bigint, 'sales reads the total');
select is(
  public.quote_version_money(array[pg_temp.vid()]) -> pg_temp.vid()::text ? 'cost_minor',
  false, 'and never the cost behind it');

-- 4. With the price permission taken away ------------------------------------------------------------------

set local role postgres;
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002',
   'quotes.view_price', 'deny');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000002', true);

select is(public.quote_version_money(array[pg_temp.vid()]), '{}'::jsonb,
  'the version reader hands back nothing at all');
select is(public.quote_line_money(pg_temp.vid()), '{}'::jsonb,
  'and neither does the line reader');
select is((select count(*)::integer from public.quote_version_schedule_items), 0,
  'a payment schedule is money, so its rows disappear with the permission');
select is((select count(*)::integer from public.quote_deposit_events), 0,
  'so does a deposit receipt');
select is((select count(*)::integer from public.quote_version_lines), 1,
  'the quote itself is still readable - this person may still see the work, just not its price');

select * from finish();
rollback;
