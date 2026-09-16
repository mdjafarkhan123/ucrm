-- Quotes: a published version freezes the organization logo and brand color the same way it already
-- freezes organization_name -- closing the gap against docs/quote-behavior-contract.md's own commitment.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(30);

-- 1. Shape and grants ----------------------------------------------------------------------------------

select has_column('public', 'quote_versions', 'logo_object_key', 'a version can freeze a logo');
select has_column('public', 'quote_versions', 'brand_color', 'a version can freeze a brand color');
select is(has_column_privilege('authenticated', 'public.quote_versions', 'logo_object_key', 'select'),
  true, 'staff can read the frozen logo key');
select is(has_column_privilege('authenticated', 'public.quote_versions', 'brand_color', 'select'),
  true, 'staff can read the frozen brand color');

select is(has_function_privilege('service_role', 'public.resolve_quote_access_link_logo(bytea)', 'execute'),
  true, 'only our own server resolves a token to a logo key');
select is(has_function_privilege('anon', 'public.resolve_quote_access_link_logo(bytea)', 'execute'),
  false, 'nobody signed out resolves a logo key directly');
select is(has_function_privilege('authenticated', 'public.resolve_quote_access_link_logo(bytea)', 'execute'),
  false, 'not even a signed-in member calls the public seam directly');
select is(has_function_privilege('authenticated', 'public.quote_preview_logo_object_key(uuid)', 'execute'),
  true, 'staff can ask for the preview logo, gated inside the function');
select is(has_function_privilege('anon', 'public.quote_preview_logo_object_key(uuid)', 'execute'),
  false, 'nobody signed out reads a preview logo');

-- 2. Fixtures --------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'brand-admin@example.test', 'test', now(), now(), now()),
  ('f0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'brand-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('f1000000-0000-0000-0000-000000000001', 'Brand Org A', 'brand-org-a', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'Brand Org B', 'brand-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'admin'),
  ('f1000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000002', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'Brand Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('f3000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001', '5 Brand Way', 'Testville');

insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary) values
  ('f1000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
    'email', 'brand-client@example.test', true);

-- The org's branding as it stands the moment the quote is created. Object keys follow the real
-- `<organization_id>/logo/<uuid>-<name>` shape; the exact suffix does not matter to this test.
-- Tax is confirmed No tax so publishing is not blocked on an unrelated Settings -> Taxes gate.
update public.organization_settings
set logo_object_key = 'f1000000-0000-0000-0000-000000000001/logo/original-logo.png',
    brand_color = '#112233',
    tax_default_source = 'no_tax'
where organization_id = 'f1000000-0000-0000-0000-000000000001';

create function pg_temp.qid() returns uuid language sql stable security definer as
  'select id from public.quotes where title = ''Brand quote''';
create function pg_temp.draft_rev() returns integer language sql stable security definer as
  'select revision from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Brand quote'')';
create function pg_temp.draft_logo() returns text language sql stable security definer as
  'select logo_object_key from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Brand quote'')';
create function pg_temp.draft_color() returns text language sql stable security definer as
  'select brand_color from public.quote_versions where id =
     (select draft_version_id from public.quotes where title = ''Brand quote'')';
create function pg_temp.published_logo() returns text language sql stable security definer as
  'select logo_object_key from public.quote_versions where id =
     (select current_published_version_id from public.quotes where title = ''Brand quote'')';
create function pg_temp.published_color() returns text language sql stable security definer as
  'select brand_color from public.quote_versions where id =
     (select current_published_version_id from public.quotes where title = ''Brand quote'')';
create function pg_temp.hash(raw text) returns bytea language sql immutable as
  'select extensions.digest($1, ''sha256'')';
create function pg_temp.resolve(raw text) returns jsonb language sql stable security definer as
  'select public.resolve_quote_access_link(pg_temp.hash($1))';
create function pg_temp.resolve_logo(raw text) returns text language sql stable security definer as
  'select public.resolve_quote_access_link_logo(pg_temp.hash($1))';
create function pg_temp.resolve_logo_raw(raw bytea) returns text language sql stable security definer as
  'select public.resolve_quote_access_link_logo($1)';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);

-- 3. A new draft starts from the organization's current branding -----------------------------------------

select lives_ok(
  $$select public.create_quote('f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Brand quote', null)$$,
  'a quote to brand'
);
select is(pg_temp.draft_logo(), 'f1000000-0000-0000-0000-000000000001/logo/original-logo.png',
  'the draft copies the current logo key');
select is(pg_temp.draft_color(), '#112233', 'the draft copies the current brand color');

select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.draft_rev(), jsonb_build_array(
      jsonb_build_object('name', 'Gutter clean', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 40000, 'unit_cost_minor', 15000, 'is_taxable', false)
    ))$$,
  'the quote has something to sell'
);

-- 4. Publishing freezes it; a later settings change never rewrites it --------------------------------------

select lives_ok(
  $$select public.publish_quote(pg_temp.qid(), pg_temp.draft_rev())$$,
  'the quote goes out with today''s branding'
);

set local role postgres;
update public.organization_settings
set logo_object_key = 'f1000000-0000-0000-0000-000000000001/logo/replaced-logo.png',
    brand_color = '#445566'
where organization_id = 'f1000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);

select is(pg_temp.published_logo(), 'f1000000-0000-0000-0000-000000000001/logo/original-logo.png',
  'replacing the logo never rewrites a document already sent');
select is(pg_temp.published_color(), '#112233',
  'replacing the brand color never rewrites a document already sent');

-- 5. The customer document exposes the frozen color and a logo flag, never the object key ------------------

select lives_ok(
  $$select public.issue_quote_access_link(pg_temp.qid(), pg_temp.hash('brand-token'))$$,
  'a link to share'
);
select is(pg_temp.resolve('brand-token') -> 'business' ->> 'brand_color', '#112233',
  'the customer sees the color the quote was actually sent with');
select is(pg_temp.resolve('brand-token') -> 'business' ->> 'has_logo', 'true',
  'the customer document says a logo exists');
select is(pg_temp.resolve('brand-token')::text like '%original-logo.png%', false,
  'the object key itself never leaves the server in the document payload');

-- 6. The token-scoped logo resolver answers with the frozen key, and nothing else does ----------------------

select is(pg_temp.resolve_logo('brand-token'), 'f1000000-0000-0000-0000-000000000001/logo/original-logo.png',
  'the real token resolves to the frozen logo key');
select is(pg_temp.resolve_logo('no-such-token'), null, 'a random token resolves to nothing');
select is(pg_temp.resolve_logo_raw('\x00'::bytea), null, 'a malformed token resolves to nothing');

-- 7. Preview as client reads the same frozen value, through the same quotes.view gate ------------------------

select is(
  (select public.quote_preview_logo_object_key(pg_temp.qid())),
  'f1000000-0000-0000-0000-000000000001/logo/original-logo.png',
  'staff preview shows the same frozen logo the customer link shows'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.quote_preview_logo_object_key(pg_temp.qid())$$,
  '42501', null, 'another organization cannot preview this quote''s logo'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);

-- 8. Revising a sent quote keeps the branding it was actually sent with, not today's settings ---------------

select lives_ok($$select public.revise_quote(pg_temp.qid())$$, 'staff start a new version');

set local role postgres;
update public.organization_settings
set logo_object_key = 'f1000000-0000-0000-0000-000000000001/logo/yet-another-logo.png',
    brand_color = '#778899'
where organization_id = 'f1000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);

select is(pg_temp.draft_logo(), 'f1000000-0000-0000-0000-000000000001/logo/original-logo.png',
  'a revision keeps the branding the prior published version was actually sent with');
select is(pg_temp.draft_color(), '#112233',
  'a revision keeps the brand color the prior published version was actually sent with');

-- 9. A quote whose organization never uploaded a logo says so honestly ---------------------------------------

set local role postgres;
update public.organization_settings
set logo_object_key = null, brand_color = null
where organization_id = 'f1000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'No logo quote', null)$$,
  'a quote for an organization with no logo yet'
);
select is(
  (select logo_object_key from public.quote_versions
    where id = (select draft_version_id from public.quotes where title = 'No logo quote')),
  null, 'nothing is frozen when there is nothing to freeze'
);

select * from finish();
rollback;
