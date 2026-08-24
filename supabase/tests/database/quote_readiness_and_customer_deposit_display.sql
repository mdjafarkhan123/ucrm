-- Quotes, Part 6C: the customer document's deposit fact, and that it stays money-gated like every other
-- number the customer sees. Run as one transaction against the linked development project; every fixture
-- rolls back. `ready_for_job` itself is computed in the API from data this file already proves is honest —
-- there is nothing stored for it to test here.
begin;

create extension if not exists pgtap with schema extensions;
select plan(17);

-- 1. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit-admin@example.test', 'test', now(), now(), now()),
  ('e0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('e1000000-0000-0000-0000-000000000001', 'Deposit Display Org', 'deposit-display-org', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'admin'),
  ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'field');

insert into public.clients (id, organization_id, display_name) values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'Deposit Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001', '4 Deposit Way', 'Testville');

insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary) values
  ('e1000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
    'email', 'deposit-client@example.test', true);

create function pg_temp.qid(wanted_title text) returns uuid language sql stable security definer as
  'select id from public.quotes where title = $1';
create function pg_temp.rev(wanted_title text) returns integer language sql stable security definer as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = $1)';
create function pg_temp.hash(raw text) returns bytea language sql immutable as
  'select extensions.digest($1, ''sha256'')';
create function pg_temp.resolve(raw text) returns jsonb language sql stable security definer as
  'select public.resolve_quote_access_link(pg_temp.hash($1))';
create function pg_temp.event_id(target_title text) returns uuid language sql stable security definer as
  'select id from public.quote_deposit_events
    where quote_id = pg_temp.qid($1) and event_type = ''received''
    order by created_at desc limit 1';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-000000000001', true);

-- 2. A quote with no deposit shows none ---------------------------------------------------------------------

select lives_ok(
  $$select public.create_quote('e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'No deposit quote', null)$$,
  'a quote with nothing required'
);
select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid('No deposit quote'), pg_temp.rev('No deposit quote'), jsonb_build_array(
      jsonb_build_object('name', 'Gutter clean', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 40000, 'unit_cost_minor', 15000, 'is_taxable', false)
    ))$$,
  'priced so there is something to publish'
);
select lives_ok(
  $$select public.publish_quote(pg_temp.qid('No deposit quote'), pg_temp.rev('No deposit quote'))$$,
  'sent with no deposit configured'
);
select lives_ok(
  $$select public.issue_quote_access_link(pg_temp.qid('No deposit quote'), pg_temp.hash('no-deposit-token'))$$,
  'a link to it'
);
select is(pg_temp.resolve('no-deposit-token') -> 'deposit', 'null'::jsonb,
  'the customer document names no deposit at all, not a zero one');

-- 3. A required deposit follows the customer through unpaid, paid, and reversed ------------------------------

select lives_ok(
  $$select public.create_quote('e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Deposit quote', null)$$,
  'a quote that will require a deposit'
);
select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid('Deposit quote'), pg_temp.rev('Deposit quote'), jsonb_build_array(
      jsonb_build_object('name', 'Roof repair', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 40000, 'unit_cost_minor', 15000, 'is_taxable', false)
    ))$$,
  'priced at $400'
);
select lives_ok(
  $$select public.set_quote_draft_deposit(pg_temp.qid('Deposit quote'), pg_temp.rev('Deposit quote'), 'deposit_only',
      jsonb_build_array(jsonb_build_object('description', 'Deposit', 'type', 'fixed', 'value', 10000)))$$,
  'a $100 deposit is required to start work'
);
select lives_ok(
  $$select public.publish_quote(pg_temp.qid('Deposit quote'), pg_temp.rev('Deposit quote'))$$,
  'sent with the deposit frozen onto the published version'
);
select lives_ok(
  $$select public.issue_quote_access_link(pg_temp.qid('Deposit quote'), pg_temp.hash('deposit-token'))$$,
  'a link to it'
);

select is(
  pg_temp.resolve('deposit-token') -> 'deposit',
  jsonb_build_object('required_minor', 10000, 'satisfied', false),
  'the client sees the required deposit and that it is still outstanding, arranged with the contractor -- never a payment control'
);

select lives_ok(
  $$select public.record_quote_deposit_event(pg_temp.qid('Deposit quote'), 'received-once', 'cash', null, null)$$,
  'staff record the deposit arriving offline'
);
select is(
  pg_temp.resolve('deposit-token') -> 'deposit' ->> 'satisfied', 'true',
  'once recorded, the same customer document shows the deposit as satisfied'
);

select lives_ok(
  $$select public.reverse_quote_deposit_event(
      pg_temp.qid('Deposit quote'), pg_temp.event_id('Deposit quote'), 'reversal-once', 'recorded by mistake')$$,
  'a correction reverses the receipt'
);
select is(
  pg_temp.resolve('deposit-token') -> 'deposit' ->> 'satisfied', 'false',
  'a reversed deposit is outstanding again, not silently still counted'
);

-- 4. The deposit fact stays behind the same money gate as everything else the customer document withholds --
-- Calling the builder directly, the same way `resolve_quote_access_link` and `quote_customer_preview` both
-- do, isolates exactly what this part changed from the permission plumbing that decides `include_money`,
-- which is already covered where that derivation lives.

set local role postgres;

select is(
  (select private.quote_customer_document(quote, version, 'Test', 'test@example.test', false) -> 'deposit'
   from public.quotes quote
   join public.quote_versions version on version.id = quote.current_published_version_id
   where quote.title = 'Deposit quote'),
  'null'::jsonb,
  'a viewer without price permission is shown no deposit fact at all'
);
select is(
  (select private.quote_customer_document(quote, version, 'Test', 'test@example.test', true)
     -> 'deposit' ->> 'required_minor'
   from public.quotes quote
   join public.quote_versions version on version.id = quote.current_published_version_id
   where quote.title = 'Deposit quote'),
  '10000',
  'a viewer with price permission is shown the same deposit fact the customer document exposes'
);

select * from finish();
rollback;
