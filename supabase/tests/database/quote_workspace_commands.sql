-- Quotes, Part 3A: the staff workspace's commands.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `quotes_pricing_foundation.sql`
-- documents. Do not run it through a runner that executes each statement separately: `set local role`
-- and `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(54);

-- 1. Shape --------------------------------------------------------------------------------------------

select has_column('public', 'quote_versions', 'revision', 'a draft version carries a revision');
select has_column('public', 'quote_versions', 'contract_disclaimer', 'a draft version carries its terms');
select has_column('public', 'quotes', 'previous_status', 'an archived quote remembers where it came from');
select has_column('public', 'quotes', 'archived_at', 'an archived quote records when');
select has_column('public', 'quotes', 'archive_reason', 'an archived quote can record why');
select has_index('public', 'quotes', 'quotes_organization_created_idx', 'the list order index exists');
select has_index('public', 'quotes', 'quotes_organization_status_created_idx', 'the status filter index exists');
select has_function('public', 'create_quote', 'the direct create command exists');
select has_function('public', 'update_quote_draft', 'the draft edit command exists');
select has_function('public', 'replace_quote_version_lines', 'the draft line command exists');
select has_function('public', 'archive_quote', 'the archive command exists');
select has_function('public', 'restore_quote', 'the restore command exists');
select has_function('public', 'quote_status_counts', 'the overview count function exists');

-- Nobody signed out may run any of them, and nobody at all may allocate a number directly.
select is(
  (select count(*)::int from information_schema.role_routine_grants
    where routine_schema = 'public' and grantee = 'anon'
      and routine_name in ('create_quote', 'update_quote_draft', 'replace_quote_version_lines', 'archive_quote', 'restore_quote', 'quote_status_counts')),
  0, 'a signed-out caller may run none of the quote commands'
);

-- 2. Fixtures -----------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ws-admin-a@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ws-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('91000000-0000-0000-0000-000000000001', 'Workspace Org A', 'workspace-org-a', 'active'),
  ('91000000-0000-0000-0000-000000000002', 'Workspace Org B', 'workspace-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'admin'),
  ('91000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', 'admin');

-- C1 is live, C2 is archived and must not receive new work, C3 belongs to org B.
insert into public.clients (id, organization_id, display_name, archived_at)
values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'Workspace Client A', null),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001', 'Workspace Client Archived', now()),
  ('92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000002', 'Workspace Client B', null);

-- P1 belongs to C1. P2 belongs to C2. P3 belongs to org B's client.
insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '4 Workspace Way', 'Testville'),
  ('93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000002', '6 Archived Row', 'Testville'),
  ('93000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000003', '8 Other Lane', 'Otherville');

insert into public.catalog_items (id, organization_id, category, name, unit_price_minor, unit_cost_minor)
values
  ('94000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'product', 'Consumer unit', 45000, 20000);

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

-- 3. Starting a quote from nothing ----------------------------------------------------------------------

select lives_ok(
  $$select public.create_quote('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'Workspace Quote One', 'Payment due on completion.')$$,
  'an authorized member can start a quote'
);

select is(
  (select count(*)::int from public.quotes where organization_id = '91000000-0000-0000-0000-000000000001'),
  1, 'exactly one quote was made'
);

select is(
  (select status from public.quotes where title = 'Workspace Quote One'),
  'draft', 'a new quote starts as a draft'
);

select isnt(
  (select draft_version_id from public.quotes where title = 'Workspace Quote One'),
  null, 'a new quote points at its draft version'
);

select is(
  (select version.version_number from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One'),
  0, 'a mutable draft does not consume a published version number'
);

select is(
  (select version.revision from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One'),
  1, 'a fresh draft is at revision one'
);

-- The snapshot is what makes the document its own. A later rename must not reach into it.
select is(
  (select version.client_display_name from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One'),
  'Workspace Client A', 'the draft froze the client name it was made from'
);

select is(
  (select version.service_address_line1 from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One'),
  '4 Workspace Way', 'the draft froze the service address'
);

select is(
  (select version.contract_disclaimer from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One'),
  'Payment due on completion.', 'the draft kept the terms it was given'
);

select is(
  (select count(*)::int from public.opportunities
    where quote_id = (select id from public.quotes where title = 'Workspace Quote One')),
  1, 'a directly created quote gets its own pipeline card'
);

-- Numbers are allocated, never chosen, and never repeated.
select lives_ok(
  $$select public.create_quote('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'Workspace Quote Two', null)$$,
  'a second quote can be started'
);

select is(
  (select count(distinct quote_number)::int from public.quotes where organization_id = '91000000-0000-0000-0000-000000000001'),
  2, 'the second quote got its own number'
);

select throws_ok(
  $$select public.create_quote('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000003', 'Cross tenant', null)$$,
  '23514', null, 'a property from another tenant is refused'
);

select throws_ok(
  $$select public.create_quote('92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000002', 'Archived client', null)$$,
  '23514', null, 'an archived client cannot receive new work'
);

select throws_ok(
  $$select public.create_quote('92000000-0000-0000-0000-000000000003', '93000000-0000-0000-0000-000000000003', 'Other org', null)$$,
  '42501', null, 'another organization''s client is refused as a privilege matter'
);

select throws_ok(
  $$select public.create_quote('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'x', null)$$,
  '23514', null, 'a one-character title is refused'
);

-- 4. Editing the draft ------------------------------------------------------------------------------------

select lives_ok(
  $$select public.update_quote_draft(
      (select id from public.quotes where title = 'Workspace Quote One'), 1, 'Workspace Quote One Renamed', 'New terms.')$$,
  'the draft accepts a change carrying the revision it was shown'
);

select is(
  (select version.revision from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One Renamed'),
  2, 'a saved change moves the revision on'
);

select is(
  (select title from public.opportunities
    where quote_id = (select id from public.quotes where title = 'Workspace Quote One Renamed')),
  'Workspace Quote One Renamed', 'the pipeline card follows the rename'
);

select throws_ok(
  $$select public.update_quote_draft(
      (select id from public.quotes where title = 'Workspace Quote One Renamed'), 1, 'Stale write', null)$$,
  'P0409', null, 'a save carrying an old revision is refused, and not with a code anything retries'
);

-- 5. Editing the draft's lines ----------------------------------------------------------------------------

select lives_ok(
  $$select public.replace_quote_version_lines(
      (select id from public.quotes where title = 'Workspace Quote One Renamed'),
      2,
      '[{"name": "Consumer unit", "category": "product", "quantity": 2, "unit_price_minor": 45000, "unit_cost_minor": 20000, "catalog_item_id": "94000000-0000-0000-0000-000000000001"},
        {"name": "Fitting labour", "category": "service", "is_labor": true, "quantity": 3, "unit_price_minor": 8000, "unit_cost_minor": 3000}]'::jsonb)$$,
  'the whole line set can be replaced in one call'
);

select is(
  (select count(*)::int from public.quote_version_lines
    where quote_id = (select id from public.quotes where title = 'Workspace Quote One Renamed')),
  2, 'both lines were written'
);

-- The database owns the money. 2 x 45000 + 3 x 8000 = 114000.
select is(
  (select version.subtotal_minor from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One Renamed'),
  114000::bigint, 'the subtotal was recounted from the rows that were actually written'
);

select is(
  (select version.revision from public.quote_versions version
    join public.quotes quote on quote.draft_version_id = version.id
    where quote.title = 'Workspace Quote One Renamed'),
  3, 'saving lines moves the same revision the title save uses'
);

select throws_ok(
  $$select public.replace_quote_version_lines(
      (select id from public.quotes where title = 'Workspace Quote One Renamed'), 2, '[]'::jsonb)$$,
  'P0409', null, 'a stale line save is refused too'
);

select throws_ok(
  $$select public.replace_quote_version_lines(
      (select id from public.quotes where title = 'Workspace Quote One Renamed'), 3,
      '[{"name": "Ghost photo", "category": "product", "quantity": 1, "unit_price_minor": 100, "image_attachment_id": "97000000-0000-0000-0000-000000000009"}]'::jsonb)$$,
  '23514', null, 'a line cannot claim a photo that was never uploaded for this quote'
);

-- 6. Out of sight, and back again -------------------------------------------------------------------------

select lives_ok(
  $$select public.archive_quote((select id from public.quotes where title = 'Workspace Quote Two'), null)$$,
  'a draft can be archived without explaining anything'
);

select is(
  (select status from public.quotes where title = 'Workspace Quote Two'),
  'archived', 'the archived quote says so'
);

select is(
  (select previous_status from public.quotes where title = 'Workspace Quote Two'),
  'draft', 'it remembers where it came from'
);

select is(
  (select (public.archive_quote((select id from public.quotes where title = 'Workspace Quote Two'), null) ->> 'applied')::boolean),
  false, 'archiving twice is the same answer, not an error'
);

select lives_ok(
  $$select public.restore_quote((select id from public.quotes where title = 'Workspace Quote Two'))$$,
  'an archived quote can be brought back'
);

select is(
  (select status from public.quotes where title = 'Workspace Quote Two'),
  'draft', 'it came back where it was'
);

select is(
  (select archived_at from public.quotes where title = 'Workspace Quote Two'),
  null, 'nothing is left saying it is still archived'
);

-- 7. The Overview card ------------------------------------------------------------------------------------

select is(
  (select total from public.quote_status_counts('91000000-0000-0000-0000-000000000001') where status = 'draft'),
  2::bigint, 'both drafts are counted'
);

select is(
  (select count(*)::int from public.quote_status_counts('91000000-0000-0000-0000-000000000002')),
  0, 'another organization''s quotes are not countable from here'
);

-- 8. Notes and attachments may point at a quote -------------------------------------------------------------

-- The private schema is not reachable from the authenticated role, which is the point of it; these two
-- read the helpers directly, so they run as the owner.
set local role postgres;

select is(
  (select private.can_view_quote(
     '91000000-0000-0000-0000-000000000001',
     (select id from public.quotes where title = 'Workspace Quote One Renamed'))),
  true, 'a member who may see quotes may reach this one'
);

select is(
  (select private.can_manage_linked_entity(
     '91000000-0000-0000-0000-000000000001', 'quote',
     (select id from public.quotes where title = 'Workspace Quote One Renamed'))),
  true, 'editing a quote''s notes follows editing the quote'
);

select lives_ok(
  $$insert into public.attachments (organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key)
    values ('91000000-0000-0000-0000-000000000001', 'quote',
      (select id from public.quotes where title = 'Workspace Quote One Renamed'),
      'quote-photo.jpg', 'image/jpeg', 1024, 'test/quotes/ws-photo.jpg')$$,
  'a file can be attached to a quote'
);

-- Widening a polymorphic seam means three edits, not two. This is the assertion that caught the missing
-- one: the entity_type lists and the visibility helpers knew about quotes, and the existence trigger did not.
select lives_ok(
  $$insert into public.notes (id, organization_id, body)
    values ('98000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'A quote note.')$$,
  'a note can be written'
);

select lives_ok(
  $$insert into public.note_links (organization_id, note_id, entity_type, entity_id)
    values ('91000000-0000-0000-0000-000000000001', '98000000-0000-0000-0000-000000000001', 'quote',
      (select id from public.quotes where title = 'Workspace Quote One Renamed'))$$,
  'a note can be linked to a quote'
);

select * from finish();

rollback;
