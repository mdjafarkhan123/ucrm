-- Quotes, Part 5B1: the recipient snapshot, the customer link, and the one function the public page calls.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(53);

-- 1. Shape and privileges ---------------------------------------------------------------------------------

select has_table('public', 'quote_recipients', 'a quote knows who it is addressed to');
select has_table('public', 'quote_access_links', 'a customer link is a row of its own');
select has_column('public', 'quote_access_links', 'token_hash', 'the link stores a hash');
select col_type_is('public', 'quote_access_links', 'token_hash', 'bytea',
  'the hash is raw bytes, not text');
select has_index('public', 'quote_access_links', 'quote_access_links_token_hash_unique',
  'the whole public read is one unique-index lookup');
select has_index('public', 'quote_access_links', 'quote_access_links_recipient_idx',
  'the recipient foreign key is indexed');
select has_index('public', 'quote_access_links', 'quote_access_links_version_idx',
  'the version foreign key is indexed');

select is(has_function_privilege('authenticated', 'public.issue_quote_access_link(uuid,bytea)', 'execute'),
  true, 'staff create links through the command');
select is(has_function_privilege('anon', 'public.issue_quote_access_link(uuid,bytea)', 'execute'),
  false, 'nobody signed out creates a link');
select is(has_function_privilege('anon', 'public.resolve_quote_access_link(bytea)', 'execute'),
  false, 'anon cannot resolve a token');
select is(has_function_privilege('authenticated', 'public.resolve_quote_access_link(bytea)', 'execute'),
  false, 'not even a signed-in member calls the public seam directly');
select is(has_function_privilege('service_role', 'public.resolve_quote_access_link(bytea)', 'execute'),
  true, 'only our own server resolves tokens');

select is(has_table_privilege('anon', 'public.quote_recipients', 'select'), false,
  'anon reads no recipients');
select is(has_table_privilege('anon', 'public.quote_access_links', 'select'), false,
  'anon reads no links');
select is(has_table_privilege('authenticated', 'public.quote_access_links', 'select'), false,
  'members never select a token hash, not even their own');
select is(has_table_privilege('authenticated', 'public.quote_access_links', 'insert'), false,
  'links are written by the command or not at all');
select is(has_table_privilege('authenticated', 'public.quote_recipients', 'insert'), false,
  'recipients are written by the command or not at all');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('d0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'link-admin@example.test', 'test', now(), now(), now()),
  ('d0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'link-field@example.test', 'test', now(), now(), now()),
  ('d0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'link-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('d1000000-0000-0000-0000-000000000001', 'Link Org A', 'link-org-a', 'active'),
  ('d1000000-0000-0000-0000-000000000002', 'Link Org B', 'link-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('d1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'admin'),
  ('d1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'field'),
  ('d1000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'Link Client'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', 'Other Org Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001', '9 Link Street', 'Testville'),
  ('d3000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000002', '1 Other Road', 'Elsewhere');

create function pg_temp.qid() returns uuid language sql stable security definer as
  'select id from public.quotes where title = ''Link quote''';
create function pg_temp.rev() returns integer language sql stable security definer as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Link quote'')';
create function pg_temp.link_id() returns uuid language sql stable security definer as
  'select id from public.quote_access_links where quote_id = pg_temp.qid() and revoked_at is null
    order by issued_at desc limit 1';
create function pg_temp.latest_link_id() returns uuid language sql stable security definer as
  'select id from public.quote_access_links where quote_id = pg_temp.qid() order by issued_at desc limit 1';
create function pg_temp.token_in_history(fragment text) returns integer language sql stable security definer as
  'select count(*)::integer from public.activity_events
    where entity_id = pg_temp.qid() and metadata::text like ''%'' || $1 || ''%''';
create function pg_temp.link_count() returns integer language sql stable security definer as
  'select count(*)::integer from public.quote_access_links where quote_id = pg_temp.qid()';
create function pg_temp.active_link_count() returns integer language sql stable security definer as
  'select count(*)::integer from public.quote_access_links
    where quote_id = pg_temp.qid() and revoked_at is null';
create function pg_temp.recipient_count() returns integer language sql stable security definer as
  'select count(*)::integer from public.quote_recipients where quote_id = pg_temp.qid()';
create function pg_temp.recipient_email() returns text language sql stable security definer as
  'select email from public.quote_recipients where quote_id = pg_temp.qid() limit 1';
create function pg_temp.hash(raw text) returns bytea language sql immutable as
  'select extensions.digest($1, ''sha256'')';
create function pg_temp.resolve(raw text) returns jsonb language sql stable security definer as
  'select public.resolve_quote_access_link(pg_temp.hash($1))';
-- Members hold no grant on the resolver, which is the point - so even the test reaches it the way our
-- server does, through something that already has the right to call it.
create function pg_temp.resolve_raw(raw bytea) returns jsonb language sql stable security definer as
  'select public.resolve_quote_access_link($1)';
create function pg_temp.events(wanted_type text) returns integer language sql stable security definer as
  'select count(*)::integer from public.activity_events
    where entity_type = ''quote'' and entity_id = pg_temp.qid() and event_type = $1';

insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary) values
  ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001',
    'email', 'Owner@Example.Test', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('d2000000-0000-0000-0000-000000000001', 'd3000000-0000-0000-0000-000000000001', 'Link quote', null)$$,
  'a quote to share'
);
select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('name', 'Gutter clean', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 40000, 'unit_cost_minor', 15000, 'is_taxable', false)
    ))$$,
  'the quote has something to sell'
);

-- 3. A link needs a sent quote and the right permission ----------------------------------------------------

select throws_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('too-early'))$$,
  '23514', null, 'a draft has nothing frozen to show a customer'
);

select lives_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.rev())$$,
  'the quote goes out'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('field-try'))$$,
  '42501', null, 'a field member cannot hand the quote to a customer'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('outsider-try'))$$,
  '42501', null, 'another organization cannot share this quote'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd0000000-0000-0000-0000-000000000001', true);

-- 4. Issuing ------------------------------------------------------------------------------------------------

select lives_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('first-token'))$$,
  'the customer link is created'
);
select is(pg_temp.recipient_count(), 1, 'one recipient, taken from the client');
select is(pg_temp.recipient_email(), 'owner@example.test', 'the address is stored lowercased');
select is(pg_temp.events('quote.link_issued'), 1, 'creating a link is in the quote history');
select is(pg_temp.token_in_history('first-token'), 0, 'no raw token reaches the history');

-- 5. Resolving ------------------------------------------------------------------------------------------------

select isnt(pg_temp.resolve('first-token'), null, 'the real token opens the document');
select is(pg_temp.resolve('first-token') -> 'quote' ->> 'status', 'awaiting_response',
  'the customer sees where the quote stands');
select is(pg_temp.resolve('first-token') -> 'totals' ->> 'total_minor', '40000',
  'the customer sees the price they were quoted');
select is(pg_temp.resolve('first-token')::text like '%15000%', false,
  'what the work costs us is not in the payload');
select is(pg_temp.resolve('first-token')::text like '%unit_cost%', false, 'no cost column is named');
select is(pg_temp.resolve('first-token')::text like '%margin%', false, 'no margin is named');
select is(pg_temp.resolve('first-token')::text like '%source_catalog_item_id%', false,
  'the price book is not exposed');

select is(pg_temp.resolve('a-token-nobody-issued'), null, 'a random token opens nothing');
select is(public.resolve_quote_access_link('\x00'::bytea), null, 'a malformed token opens nothing');
select is(pg_temp.resolve_raw(null::bytea), null, 'no token opens nothing');

-- 6. Rotation, revocation, and a version that moved on ----------------------------------------------------------

select lives_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('second-token'))$$,
  'issuing again rotates the link'
);
select is(pg_temp.link_count(), 2, 'the old link is kept as history');
select is(pg_temp.active_link_count(), 1, 'only one link is live');
select is(pg_temp.recipient_count(), 1, 'the same person is not added twice');
select is(pg_temp.resolve('first-token'), null, 'the forwarded old URL stops working');
select isnt(pg_temp.resolve('second-token'), null, 'the new URL works');

select lives_ok($$select public.revise_quote(pg_temp.qid())$$, 'staff start a new version');
-- Starting a revision does not take the document away from the customer: the version they were sent is
-- still the published one, exactly as it is in Jobber, until a new one goes out.
select isnt(pg_temp.resolve('second-token'), null,
  'while staff revise, the customer still sees the version they were sent');

select lives_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.rev())$$,
  'the new version goes out'
);
select lives_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('third-token'))$$,
  'a link for the new version'
);
select is(pg_temp.resolve('second-token'), null,
  'once the next version goes out, the old link is outdated and shows nothing');
select is(pg_temp.resolve('third-token') -> 'document' ->> 'version_number', '2',
  'the customer gets the version that is current');

select lives_ok(
  $$select public.revoke_quote_access_link(pg_temp.link_id())$$,
  'staff can turn a link off'
);
select is(pg_temp.resolve('third-token'), null, 'a revoked link opens nothing');
select is(
  (select public.revoke_quote_access_link(pg_temp.latest_link_id()) ->> 'already_revoked'),
  'true', 'revoking twice is the same click arriving twice');

select * from finish();
rollback;
