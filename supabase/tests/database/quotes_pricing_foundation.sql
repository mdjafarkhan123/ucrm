-- Quotes, Part 2: pricing foundation and Request carry-forward.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(105);

-- 1. Shape --------------------------------------------------------------------------------------------

select has_table('public', 'organization_quote_counters', 'the quote number counter table exists');
select has_table('public', 'catalog_items', 'the pricing catalog table exists');
select has_table('public', 'request_pricing_lines', 'requests own their pricing rows');
select has_table('public', 'quotes', 'the quote identity table exists');
select has_table('public', 'quote_versions', 'the quote version header table exists');
select has_table('public', 'quote_version_lines', 'quote versions own their copied pricing rows');

select has_index('public', 'catalog_items', 'catalog_items_active_idx', 'the active catalog list index exists');
select has_index('public', 'request_pricing_lines', 'request_pricing_lines_request_idx', 'the request pricing order index exists');
select has_index('public', 'quotes', 'quotes_request_lineage_idx', 'the one-quote-per-request index exists');
select has_index('public', 'quote_versions', 'quote_versions_one_draft_idx', 'the one-draft-per-quote index exists');
select has_index('public', 'quote_version_lines', 'quote_version_lines_version_idx', 'the version line order index exists');

-- The line photo is a live reference on the request and a frozen one on the quote. That difference is the
-- whole point of the column, so it is asserted rather than assumed.
select has_column('public', 'request_pricing_lines', 'image_attachment_id', 'a request pricing line can carry a photo');
select has_column('public', 'quote_version_lines', 'image_attachment_id', 'a copied quote line carries the photo it was given');
select has_index('public', 'request_pricing_lines', 'request_pricing_lines_image_idx', 'the request line photo index exists');
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.request_pricing_lines'::regclass
      and conname = 'request_pricing_lines_image_organization_fk'),
  1, 'the request side photo reference is a real foreign key'
);
-- A composite `set null` with no column list nulls the whole key, organization and all, and the delete
-- then fails on the not-null column. This is the assertion that caught it.
select is(
  (select pg_get_constraintdef(oid) like '%SET NULL (image\_attachment\_id)' from pg_constraint
    where conrelid = 'public.request_pricing_lines'::regclass
      and conname = 'request_pricing_lines_image_organization_fk'),
  true, 'deleting a photo clears only the photo, never the line organization'
);
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.quote_version_lines'::regclass
      and contype = 'f'
      and (select attnum from pg_attribute
            where attrelid = 'public.quote_version_lines'::regclass
              and attname = 'image_attachment_id') = any (conkey)),
  1, 'the quote line photo reference is tenant-safe'
);

-- 2. Privileges ---------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.replace_request_pricing_lines(uuid, integer, jsonb)', 'execute'),
  false, 'anonymous callers cannot replace request pricing'
);
select is(
  has_function_privilege('authenticated', 'public.replace_request_pricing_lines(uuid, integer, jsonb)', 'execute'),
  true, 'authenticated members can replace request pricing'
);
select is(
  has_function_privilege('anon', 'public.convert_request_to_quote(uuid, text, text)', 'execute'),
  false, 'anonymous callers cannot convert a request'
);
select is(
  has_function_privilege('authenticated', 'public.convert_request_to_quote(uuid, text, text)', 'execute'),
  true, 'authenticated members can convert a request'
);
select is(
  has_table_privilege('authenticated', 'public.quotes', 'insert'),
  false, 'members cannot insert a quote directly'
);
select is(
  has_table_privilege('authenticated', 'public.quote_version_lines', 'update'),
  false, 'members cannot rewrite a copied quote line directly'
);
select is(
  has_table_privilege('authenticated', 'public.request_pricing_lines', 'insert'),
  false, 'members cannot insert a request pricing row outside the replace command'
);
select is(
  has_table_privilege('authenticated', 'public.organization_quote_counters', 'select'),
  false, 'the quote number counter is never readable by members'
);

-- 3. One rounding rule ----------------------------------------------------------------------------------

select is(public.pricing_line_total_minor(1.5, 333), 500::bigint, 'half a minor unit rounds away from zero');
select is(public.pricing_line_total_minor(2.5, 5), 13::bigint, 'twelve and a half cents rounds up to thirteen');
select is(public.pricing_line_total_minor(0.005, 100), 1::bigint, 'a fractional quantity still lands on a whole minor unit');
select is(public.pricing_line_total_minor(3, 1999), 5997::bigint, 'a whole quantity multiplies exactly');
select is(public.pricing_line_total_minor(0.333, 1000), 333::bigint, 'a three decimal quantity does not drift');
select is(public.pricing_line_total_minor(1, 0), 0::bigint, 'a zero price line totals zero');

-- 4. Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quote-admin-a@example.test', 'test', now(), now(), now()),
  ('80000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quote-admin-b@example.test', 'test', now(), now(), now()),
  ('80000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'quote-finance-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('81000000-0000-0000-0000-000000000001', 'Quote Org A', 'quote-org-a', 'active'),
  ('81000000-0000-0000-0000-000000000002', 'Quote Org B', 'quote-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', 'admin'),
  ('81000000-0000-0000-0000-000000000002', '80000000-0000-0000-0000-000000000002', 'admin'),
  ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000003', 'finance');

insert into public.clients (id, organization_id, display_name)
values
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'Quote Client A'),
  ('82000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000002', 'Quote Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '9 Quote Lane', 'Testville'),
  ('83000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000002', '9 Other Lane', 'Otherville');

-- R1 converts. R2 is already completed and must be refused. R3 belongs to org B. R4 stays unpriced and
-- proves an empty request still converts to an honest zero-subtotal draft.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
values
  ('84000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 'Quote Request R1', 'assessment_completed'),
  ('84000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 'Quote Request R2', 'completed'),
  ('84000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000002', '83000000-0000-0000-0000-000000000002', 'Quote Request R3', 'new'),
  ('84000000-0000-0000-0000-000000000004', '81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 'Quote Request R4', 'new');

-- Three uploads: one taken for R1, one taken for a different request in the same organization, and one
-- belonging to org B. Only the first is a photo an R1 line may claim.
insert into public.attachments (id, organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key)
values
  ('87000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'request', '84000000-0000-0000-0000-000000000001', 'r1-line.jpg', 'image/jpeg', 1024, 'test/quotes/r1-line.jpg'),
  ('87000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000001', 'request', '84000000-0000-0000-0000-000000000002', 'r2-line.jpg', 'image/jpeg', 1024, 'test/quotes/r2-line.jpg'),
  ('87000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000002', 'request', '84000000-0000-0000-0000-000000000003', 'r3-line.jpg', 'image/jpeg', 1024, 'test/quotes/r3-line.jpg');

-- One task a person already finished and two still open. Only the open pair may move.
insert into public.tasks (id, organization_id, opportunity_id, title, status, completed_at, completed_by)
values
  ('85000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', (select id from public.opportunities where request_id = '84000000-0000-0000-0000-000000000001'), 'R1 open task one', 'open', null, null),
  ('85000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000001', (select id from public.opportunities where request_id = '84000000-0000-0000-0000-000000000001'), 'R1 open task two', 'open', null, null),
  ('85000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000001', (select id from public.opportunities where request_id = '84000000-0000-0000-0000-000000000001'), 'R1 finished task', 'completed', now(), '80000000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

-- 5. Catalog ------------------------------------------------------------------------------------------

select lives_ok(
  $q$insert into public.catalog_items (id, organization_id, category, name, unit_label, unit_price_minor, unit_cost_minor, is_taxable)
    values ('86000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'product', 'Cedar board', 'each', 4599, 2100, true)$q$,
  'an admin with catalog.edit can add a catalog item'
);
select lives_ok(
  $q$insert into public.catalog_items (id, organization_id, category, name, is_labor, unit_price_minor, unit_cost_minor, is_taxable)
    values ('86000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000001', 'service', 'Install crew hour', true, 8500, 4000, false)$q$,
  'labor is a service with a labor role, not a second pricing engine'
);
select throws_ok(
  $q$insert into public.catalog_items (organization_id, category, name, is_labor)
    values ('81000000-0000-0000-0000-000000000001', 'product', 'Bad labor product', true)$q$,
  '23514', null, 'a product cannot be marked as labor'
);
select throws_ok(
  $q$insert into public.catalog_items (organization_id, category, name, unit_price_minor)
    values ('81000000-0000-0000-0000-000000000001', 'product', 'Negative price', -1)$q$,
  '23514', null, 'a catalog price cannot be negative'
);
select throws_ok(
  $q$insert into public.catalog_items (organization_id, category, name)
    values ('81000000-0000-0000-0000-000000000002', 'product', 'Cross tenant item')$q$,
  '42501', null, 'an admin cannot add a catalog item to another organization'
);

insert into public.catalog_items (id, organization_id, category, name, unit_price_minor, archived_at)
values ('86000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000001', 'product', 'Discontinued panel', 1000, now());

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $q$insert into public.catalog_items (organization_id, category, name)
    values ('81000000-0000-0000-0000-000000000001', 'product', 'Finance item')$q$,
  '42501', null, 'finance may read the catalog but not change it'
);
select is(
  (select count(*)::int from public.catalog_items where organization_id = '81000000-0000-0000-0000-000000000001'),
  3, 'finance can read its own catalog'
);

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', true);
select is(
  (select count(*)::int from public.catalog_items),
  0, 'the other organization sees no catalog items at all'
);

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

-- 6. Request pricing --------------------------------------------------------------------------------------

select is(
  (select pricing_revision from public.requests where id = '84000000-0000-0000-0000-000000000001'),
  0, 'a request starts at pricing revision zero'
);

select is(
  public.replace_request_pricing_lines(
    '84000000-0000-0000-0000-000000000001',
    0,
    '[
      {"catalog_item_id": "86000000-0000-0000-0000-000000000001", "image_attachment_id": "87000000-0000-0000-0000-000000000001", "category": "product", "name": "Cedar board", "unit_label": "each", "quantity": 12, "unit_price_minor": 4599, "unit_cost_minor": 2100, "is_taxable": true},
      {"category": "service", "name": "Install crew", "is_labor": true, "quantity": 6.5, "unit_price_minor": 8500, "unit_cost_minor": 4000, "is_taxable": false},
      {"category": "service", "name": "Site cleanup", "quantity": 1.5, "unit_price_minor": 333, "unit_cost_minor": 0, "is_taxable": true}
    ]'::jsonb
  ),
  jsonb_build_object('revision', 1, 'line_count', 3, 'subtotal_minor', 110938),
  'replacing pricing returns the new revision, line count, and exact subtotal'
);

select is(
  (select line_total_minor from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001' and position = 2),
  500::bigint, 'the half cent line rounds away from zero in the stored row'
);
select is(
  (select line_cost_total_minor from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001' and position = 0),
  25200::bigint, 'internal cost totals with the same rule'
);
select is(
  (select pricing_subtotal_minor from public.requests where id = '84000000-0000-0000-0000-000000000001'),
  110938::bigint, 'the request carries the same subtotal the command returned'
);
select is(
  (select array_agg(name order by position) from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001'),
  array['Cedar board', 'Install crew', 'Site cleanup'], 'lines keep the order they were sent in'
);
select is(
  (select image_attachment_id from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001' and position = 0),
  '87000000-0000-0000-0000-000000000001'::uuid, 'a line keeps the photo it was saved with'
);

select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000001', 0, '[]'::jsonb)$q$,
  'P0409', null, 'a stale revision is refused instead of overwriting someone else'
);
select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000001', 1,
    '[{"category": "product", "name": "Zero quantity", "quantity": 0, "unit_price_minor": 100}]'::jsonb)$q$,
  '23514', null, 'a priced line needs a positive quantity'
);
select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000001', 1,
    '[{"category": "product", "name": "X", "quantity": 1, "unit_price_minor": -5}]'::jsonb)$q$,
  '23514', null, 'a line price cannot be negative'
);
select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000001', 1,
    '[{"category": "product", "name": "A", "quantity": 1, "unit_price_minor": 100, "catalog_item_id": "86000000-0000-0000-0000-000000000003"}]'::jsonb)$q$,
  '23514', null, 'an archived catalog item cannot be added to a request'
);
select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000001', 1,
    '[{"category": "product", "name": "Wrong photo", "quantity": 1, "unit_price_minor": 100, "image_attachment_id": "87000000-0000-0000-0000-000000000002"}]'::jsonb)$q$,
  '23514', null, 'a line cannot claim a photo uploaded for a different request'
);
select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000001', 1,
    '[{"category": "product", "name": "Stolen photo", "quantity": 1, "unit_price_minor": 100, "image_attachment_id": "87000000-0000-0000-0000-000000000003"}]'::jsonb)$q$,
  '23514', null, 'a line cannot claim another organization photo'
);
select throws_ok(
  $q$select public.replace_request_pricing_lines('84000000-0000-0000-0000-000000000003', 0, '[]'::jsonb)$q$,
  '42501', null, 'a member cannot price another organization request'
);
select is(
  (select pricing_revision from public.requests where id = '84000000-0000-0000-0000-000000000001'),
  1, 'a refused replace leaves the revision alone'
);
select is(
  (select count(*)::int from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001'),
  3, 'a refused replace leaves the existing lines alone'
);

select throws_ok(
  $q$insert into public.request_pricing_lines (organization_id, request_id, position, category, name, quantity, unit_price_minor)
    values ('81000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', 9, 'product', 'Smuggled row', 1, 100)$q$,
  '42501', null, 'nothing may add a request pricing row outside the replace command'
);

-- 7. Conversion ------------------------------------------------------------------------------------------

select throws_ok(
  $q$select public.convert_request_to_quote('84000000-0000-0000-0000-000000000002', 'convert-key-r2-0001', 'hash-r2')$q$,
  '23514', null, 'a completed request is not convertible'
);
select throws_ok(
  $q$select public.convert_request_to_quote('84000000-0000-0000-0000-000000000003', 'convert-key-r3-0001', 'hash-r3')$q$,
  '42501', null, 'a member cannot convert another organization request'
);
select throws_ok(
  $q$select public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'short', 'hash-r1')$q$,
  '23514', null, 'conversion needs a real idempotency key'
);

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $q$select public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'convert-key-fin-0001', 'hash-r1')$q$,
  '42501', null, 'finance has no quotes.create permission and cannot convert'
);
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

select is(
  (public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'convert-key-r1-0001', 'hash-r1') ->> 'applied')::boolean,
  true, 'converting an assessment completed request applies'
);

select is(
  (select count(*)::int from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'),
  1, 'exactly one quote exists for the converted request'
);
select is(
  (select quote_number from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'),
  1, 'the first quote in an organization is number one'
);
select is(
  (select status from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'),
  'draft', 'a converted request produces a draft quote'
);
select is(
  (select currency_code from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'),
  'USD', 'the quote freezes the organization currency'
);
select is(
  (select count(*)::int from public.quote_versions where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  1, 'the quote has exactly one version'
);
select is(
  (select version_number from public.quote_versions where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  0, 'a mutable draft does not consume a published version number'
);
select is(
  (select status from public.quote_versions where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  'draft', 'the copied version is a mutable draft'
);
select is(
  (select subtotal_minor from public.quote_versions where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  110938::bigint, 'the draft version carries the same exact subtotal as the request'
);
select is(
  (select client_display_name from public.quote_versions where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  'Quote Client A', 'the draft version snapshots the client name'
);
select is(
  (select service_address_line1 from public.quote_versions where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  '9 Quote Lane', 'the draft version snapshots the service address'
);
select is(
  (select count(*)::int from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  3, 'every request pricing row was copied'
);
select is(
  (select array_agg(name order by position) from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  array['Cedar board', 'Install crew', 'Site cleanup'], 'copied lines keep their order'
);
select is(
  (select sum(line_total_minor)::bigint from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  110938::bigint, 'the copied line totals add up to the same money'
);
select is(
  (select image_attachment_id from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001') and position = 0),
  '87000000-0000-0000-0000-000000000001'::uuid, 'conversion carries the line photo onto the quote copy'
);
select is(
  (select status from public.requests where id = '84000000-0000-0000-0000-000000000001'),
  'converted', 'the request is marked converted'
);

-- Pipeline identity ---------------------------------------------------------------------------------------

select is(
  (select stage from public.opportunities where request_id = '84000000-0000-0000-0000-000000000001'),
  'request_closed', 'the original request card leaves the board'
);
select is(
  (select count(*)::int from public.opportunities where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  1, 'the quote gets exactly one opportunity of its own'
);
select is(
  (select stage from public.opportunities where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  'request_closed', 'the new quote card is parked off the board until the quote parts land'
);
select is(
  (select outcome from public.opportunities where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001')),
  'open', 'the quote opportunity is still open work'
);

-- Tasks -----------------------------------------------------------------------------------------------------

select is(
  (select count(*)::int from public.tasks
    where opportunity_id = (select id from public.opportunities where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'))),
  2, 'both open tasks moved to the quote card'
);
select is(
  (select count(*)::int from public.tasks
    where opportunity_id = (select id from public.opportunities where request_id = '84000000-0000-0000-0000-000000000001')),
  1, 'the finished task stayed on the request as history'
);
select is(
  (select status from public.tasks where id = '85000000-0000-0000-0000-000000000003'),
  'completed', 'the finished task was not reopened or moved'
);

-- Replay ------------------------------------------------------------------------------------------------------

select is(
  (public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'convert-key-r1-0001', 'hash-r1') ->> 'applied')::boolean,
  false, 'an identical retry does not convert a second time'
);
select is(
  (public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'convert-key-r1-0001', 'hash-r1') ->> 'quote_id')::uuid,
  (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'),
  'an identical retry returns the quote that already exists'
);
select throws_ok(
  $q$select public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'convert-key-r1-0001', 'hash-changed')$q$,
  'P0409', null, 'the same key with a changed payload conflicts'
);
select throws_ok(
  $q$select public.convert_request_to_quote('84000000-0000-0000-0000-000000000001', 'convert-key-r1-0002', 'hash-r1')$q$,
  'P0409', null, 'a fresh key on an already converted request conflicts'
);
select is(
  (select count(*)::int from public.quotes),
  1, 'no retry ever created a second quote'
);
select is(
  (select count(*)::int from public.tasks
    where opportunity_id = (select id from public.opportunities where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001'))),
  2, 'no retry moved the tasks twice'
);

set local role postgres;
select throws_ok(
  $q$insert into public.quotes (organization_id, client_id, property_id, request_id, quote_number, title, currency_code)
    values ('81000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001', 99, 'Second quote', 'USD')$q$,
  '23505', null, 'the database itself refuses a second quote for one request, even to a privileged writer'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

-- 8. Snapshots are owned by the quote ----------------------------------------------------------------------

update public.catalog_items set name = 'Cedar board v2', unit_price_minor = 9999
where id = '86000000-0000-0000-0000-000000000001';

select is(
  (select name from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001') and position = 0),
  'Cedar board', 'editing the catalog never rewrites a copied quote line'
);
select is(
  (select unit_price_minor from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001') and position = 0),
  4599::bigint, 'the copied price is the price at conversion time'
);
select is(
  (select unit_price_minor from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001' and position = 0),
  4599::bigint, 'editing the catalog never rewrites the request row either'
);

-- Both documents still hold mutable drafts here. Deleting the upload clears their live reference; once a Quote
-- version is published, Part 4's immutability guard prevents the attachment delete from rewriting history.
set local role postgres;
delete from public.attachments where id = '87000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', true);

select is(
  (select image_attachment_id from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001' and position = 0),
  null::uuid, 'deleting the photo clears it from the request line'
);
select is(
  (select organization_id from public.request_pricing_lines where request_id = '84000000-0000-0000-0000-000000000001' and position = 0),
  '81000000-0000-0000-0000-000000000001'::uuid, 'the line itself survives the delete with its organization intact'
);
select is(
  (select image_attachment_id from public.quote_version_lines where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000001') and position = 0),
  null::uuid, 'deleting the photo clears it from the still-mutable quote draft'
);

-- 9. An unpriced request still converts honestly -------------------------------------------------------------

select is(
  (public.convert_request_to_quote('84000000-0000-0000-0000-000000000004', 'convert-key-r4-0001', 'hash-r4') ->> 'applied')::boolean,
  true, 'a request with no pricing still converts'
);
select is(
  (select quote_number from public.quotes where request_id = '84000000-0000-0000-0000-000000000004'),
  2, 'the second quote in the organization is number two'
);
select is(
  (select count(*)::int from public.quote_version_lines
    where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000004')),
  0, 'an empty request does not invent line items'
);
select is(
  (select subtotal_minor from public.quote_versions
    where quote_id = (select id from public.quotes where request_id = '84000000-0000-0000-0000-000000000004')),
  0::bigint, 'an empty request converts to an explicit zero subtotal'
);

-- 10. Tenant isolation of the finished quote -------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', true);
select is((select count(*)::int from public.quotes), 0, 'the other organization sees no quotes');
select is((select count(*)::int from public.quote_versions), 0, 'the other organization sees no quote versions');
select is((select count(*)::int from public.quote_version_lines), 0, 'the other organization sees no quote lines');
select is((select count(*)::int from public.request_pricing_lines), 0, 'the other organization sees no request pricing');

select is(
  (public.convert_request_to_quote('84000000-0000-0000-0000-000000000003', 'convert-key-orgb-0001', 'hash-r3') ->> 'quote_number')::int,
  1, 'each organization numbers its quotes from one'
);

select * from finish();
rollback;
