-- Contractor Settings, Part 2B: Price Book management commands.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- 1. Shape ----------------------------------------------------------------------------------------------

select has_column('public', 'catalog_items', 'revision', 'a catalog item carries a revision');
select has_column('public', 'catalog_items', 'updated_by', 'a catalog item carries its last editor');
select has_index('public', 'catalog_items', 'catalog_items_active_name_unique', 'active names are indexed for uniqueness');
select has_index('public', 'catalog_items', 'catalog_items_active_price_idx', 'the price-sort list index exists');
select has_index('public', 'catalog_items', 'catalog_items_active_updated_idx', 'the updated-sort list index exists');

-- 2. Privileges -------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.create_catalog_item(uuid, text, text, text, text, boolean, bigint, bigint, boolean)', 'execute'),
  false, 'anonymous callers cannot create Price Book items'
);
select is(
  has_function_privilege('anon', 'public.update_catalog_item(uuid, uuid, integer, text, text, text, text, boolean, bigint, bigint, boolean)', 'execute'),
  false, 'anonymous callers cannot update Price Book items'
);
select is(
  has_function_privilege('anon', 'public.delete_catalog_item(uuid, uuid, integer)', 'execute'),
  false, 'anonymous callers cannot delete Price Book items'
);

-- 3. Fixtures ---------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('88000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'price-book-owner@example.test', 'test', now(), now(), now()),
  ('88000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'price-book-office@example.test', 'test', now(), now(), now()),
  ('88000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'price-book-orgb-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('89000000-0000-0000-0000-000000000001', 'Price Book Org A', 'price-book-org-a', 'active'),
  ('89000000-0000-0000-0000-000000000002', 'Price Book Org B', 'price-book-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('89000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000001', 'owner'),
  ('89000000-0000-0000-0000-000000000001', '88000000-0000-0000-0000-000000000002', 'office'),
  ('89000000-0000-0000-0000-000000000002', '88000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('8a000000-0000-0000-0000-000000000001', '89000000-0000-0000-0000-000000000001', 'Price Book Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('8b000000-0000-0000-0000-000000000001', '89000000-0000-0000-0000-000000000001', '8a000000-0000-0000-0000-000000000001', '1 Ledger Lane', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title, status)
values ('8c000000-0000-0000-0000-000000000001', '89000000-0000-0000-0000-000000000001', '8a000000-0000-0000-0000-000000000001', '8b000000-0000-0000-0000-000000000001', 'Price Book Request', 'new');

-- Two pre-existing items to update, rename-conflict, and delete. Inserted directly the way the picker's
-- plain RLS write already can, so the commands under test are exercised against real prior state rather
-- than state only the commands themselves could have produced.
insert into public.catalog_items (id, organization_id, category, name, unit_price_minor, unit_cost_minor, is_taxable)
values
  ('8d000000-0000-0000-0000-000000000001', '89000000-0000-0000-0000-000000000001', 'product', 'Fixture Item One', 5000, 2500, true),
  ('8d000000-0000-0000-0000-000000000002', '89000000-0000-0000-0000-000000000001', 'product', 'Fixture Item Two', 3000, 1500, true);

set local role authenticated;

-- 4. Only Owner/Administrator may manage, even though office already has catalog.edit -----------------------

select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $q$select public.create_catalog_item('89000000-0000-0000-0000-000000000001', 'product', 'Office attempt', null, null, false, 100, 0, true)$q$,
  '42501', null, 'office has catalog.edit but not the Settings management permission'
);

select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000001', true);

-- 5. Create, name rules, and case-insensitive uniqueness ----------------------------------------------------

select is(
  (public.create_catalog_item('89000000-0000-0000-0000-000000000001', 'product', 'Cedar fence panel', 'Pressure-treated', 'each', false, 4500, 2000, true) ->> 'revision')::int,
  1, 'a new item starts at revision one'
);
select throws_ok(
  $q$select public.create_catalog_item('89000000-0000-0000-0000-000000000001', 'product', 'FIXTURE ITEM ONE', null, null, false, 100, 0, true)$q$,
  '23505', null, 'an active name is unique without regard to capitalization'
);
select throws_ok(
  $q$select public.create_catalog_item('89000000-0000-0000-0000-000000000001', 'product', 'X', null, null, false, 100, 0, true)$q$,
  '23514', null, 'a one-character name is refused'
);
select throws_ok(
  $q$select public.create_catalog_item('89000000-0000-0000-0000-000000000002', 'product', 'Cross tenant create', null, null, false, 100, 0, true)$q$,
  '42501', null, 'an owner cannot create a Price Book item in another organization'
);

-- 6. Revision-protected update -----------------------------------------------------------------------------

select is(
  (public.update_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 1, 'product', 'Fixture Item One', 'Now with a description', 'each', false, 5500, 2600, true) ->> 'revision')::int,
  2, 'a valid update bumps the revision'
);
select throws_ok(
  $q$select public.update_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 1, 'product', 'Fixture Item One', null, null, false, 6000, 3000, true)$q$,
  '40001', null, 'a stale revision is refused instead of overwriting someone else'
);
select throws_ok(
  $q$select public.update_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 2, 'product', 'FIXTURE ITEM TWO', null, null, false, 5500, 2600, true)$q$,
  '23505', null, 'renaming into another active item''s name is refused the same as creating one'
);

select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $q$select public.update_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 2, 'product', 'Fixture Item One', null, null, false, 5500, 2600, true)$q$,
  '42501', null, 'office cannot update a Price Book item either'
);

select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $q$select public.update_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 2, 'product', 'Fixture Item One', null, null, false, 5500, 2600, true)$q$,
  '42501', null, 'an administrator of another organization cannot update this item'
);

select set_config('request.jwt.claim.sub', '88000000-0000-0000-0000-000000000001', true);

-- 7. Permanent delete: freed name, refused stale, refused twice --------------------------------------------

select is(
  (public.delete_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 2) ->> 'status'),
  'deleted', 'delete reports the item as deleted'
);
select is(
  (select count(*)::int from public.catalog_items where id = '8d000000-0000-0000-0000-000000000001'),
  0, 'the row is actually gone, not archived'
);
select is(
  (public.create_catalog_item('89000000-0000-0000-0000-000000000001', 'product', 'Fixture Item One', null, null, false, 100, 0, true) ->> 'revision')::int,
  1, 'deleting an item makes its exact name available again'
);
select throws_ok(
  $q$select public.delete_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000001', 2)$q$,
  '23514', null, 'an item deleted elsewhere is never silently found again'
);

-- 8. History preservation: a document line survives its catalog item's deletion -----------------------------

select is(
  (public.replace_request_pricing_lines(
    '8c000000-0000-0000-0000-000000000001', 0,
    '[{"catalog_item_id": "8d000000-0000-0000-0000-000000000002", "category": "product", "name": "Fixture Item Two", "quantity": 2, "unit_price_minor": 3000, "unit_cost_minor": 1500, "is_taxable": true}]'::jsonb
  ) ->> 'line_count')::int,
  1, 'a document line is written from the still-live catalog item'
);
select is(
  (public.delete_catalog_item('89000000-0000-0000-0000-000000000001', '8d000000-0000-0000-0000-000000000002', 1) ->> 'status'),
  'deleted', 'the linked item can still be permanently deleted'
);
select is(
  (select count(*)::int from public.request_pricing_lines where request_id = '8c000000-0000-0000-0000-000000000001'),
  1, 'the document line survives the catalog item it was copied from'
);
select is(
  (select catalog_item_id from public.request_pricing_lines where request_id = '8c000000-0000-0000-0000-000000000001'),
  null::uuid, 'the line''s provenance link is cleared, never the line itself'
);
select is(
  (select name from public.request_pricing_lines where request_id = '8c000000-0000-0000-0000-000000000001'),
  'Fixture Item Two', 'the line keeps its own copied name regardless of the catalog item''s fate'
);

select * from finish();
rollback;
