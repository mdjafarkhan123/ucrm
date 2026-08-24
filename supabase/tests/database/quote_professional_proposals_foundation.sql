-- Quotes, Part 4A: professional proposal money, choices, and immutable versions.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(50);

-- 1. Shape and privileges ---------------------------------------------------------------------------------

select has_table('public', 'quote_version_attachments', 'customer-visible files have version references');
select has_column('public', 'quotes', 'current_published_version_id', 'a quote points at its current publication');
select has_column('public', 'quote_versions', 'document_hash', 'a published version carries its document hash');
select has_column('public', 'quote_versions', 'discount_value', 'discount configuration is versioned');
select has_column('public', 'quote_versions', 'tax_rate_basis_points', 'tax configuration is versioned');
select has_column('public', 'quote_version_lines', 'selection_kind', 'line choice behavior is versioned');
select has_index('public', 'quote_version_attachments', 'quote_version_attachments_version_idx', 'visible file reads follow version order');
select has_index('public', 'quotes', 'quotes_current_published_version_idx', 'the current published pointer is indexed');
select has_function('public', 'freeze_quote_version', 'the freeze foundation exists');
select has_function('public', 'clone_quote_version_to_draft', 'the revision clone foundation exists');
select is(has_function_privilege('authenticated', 'public.freeze_quote_version(uuid,integer)', 'execute'), false,
  'Part 4 does not expose publication to staff early');
select is(has_function_privilege('authenticated', 'public.clone_quote_version_to_draft(uuid)', 'execute'), false,
  'Part 4 does not expose revision lifecycle controls early');
select is(has_table_privilege('authenticated', 'public.quote_version_attachments', 'update'), false,
  'members cannot rewrite version attachments directly');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'proposal-admin-a@example.test', 'test', now(), now(), now()),
  ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'proposal-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('a1000000-0000-0000-0000-000000000001', 'Proposal Org A', 'proposal-org-a', 'active'),
  ('a1000000-0000-0000-0000-000000000002', 'Proposal Org B', 'proposal-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'admin'),
  ('a1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Proposal Client A'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'Proposal Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('a3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', '1 Proposal Way', 'Testville'),
  ('a3000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', '2 Proposal Way', 'Otherville');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('a2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'Professional proposal', 'Approved scope only.')$$,
  'existing direct creation still creates a Part 4 draft'
);
select is(
  (select version_number from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  0, 'a new draft is normalized to version zero'
);

set local role postgres;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);

insert into public.attachments (
  id, organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key
) values (
  'a4000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'quote',
  (select id from public.quotes where title = 'Professional proposal'),
  'proposal-photo.jpg', 'image/jpeg', 1024, 'test/proposals/photo.jpg'
);

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, category, name, quantity,
  unit_price_minor, unit_cost_minor, is_taxable, line_kind, selection_kind, is_recommended
) values
  ('a6000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Professional proposal'),
    (select draft_version_id from public.quotes where title = 'Professional proposal'), 0, 'service',
    'Permit', 1, 1000, 300, false, 'priced', 'required', false),
  ('a6000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Professional proposal'),
    (select draft_version_id from public.quotes where title = 'Professional proposal'), 1, 'service',
    'Core work', 1, 2000, 500, true, 'priced', 'required', false),
  ('a6000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Professional proposal'),
    (select draft_version_id from public.quotes where title = 'Professional proposal'), 3, 'product',
    'Supplied materials', 1, 5000, 2000, true, 'priced', 'required', false),
  ('a6000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Professional proposal'),
    (select draft_version_id from public.quotes where title = 'Professional proposal'), 4, 'service',
    'Recommended add-on', 1, 1000, 400, true, 'priced', 'optional', true),
  ('a6000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Professional proposal'),
    (select draft_version_id from public.quotes where title = 'Professional proposal'), 5, 'service',
    'Other add-on', 1, 500, 100, false, 'priced', 'optional', false);

insert into public.quote_version_lines (
  organization_id, quote_id, quote_version_id, position, category, name, description, quantity,
  unit_price_minor, unit_cost_minor, is_taxable, line_kind, selection_kind
) values (
  'a1000000-0000-0000-0000-000000000001',
  (select id from public.quotes where title = 'Professional proposal'),
  (select draft_version_id from public.quotes where title = 'Professional proposal'),
  6, null, 'Project note', 'Customer-visible scope note.', null, null, null, false, 'text', 'required'
);

insert into public.quote_version_attachments (
  organization_id, quote_id, quote_version_id, attachment_id, position, customer_visible, display_name
) values (
  'a1000000-0000-0000-0000-000000000001',
  (select id from public.quotes where title = 'Professional proposal'),
  (select draft_version_id from public.quotes where title = 'Professional proposal'),
  'a4000000-0000-0000-0000-000000000001', 0, true, 'Proposal photo'
);

update public.quote_versions set
  discount_name = 'Summer discount', discount_type = 'percentage', discount_value = 1000,
  tax_name = 'Sales tax', tax_rate_basis_points = 1000,
  introduction = 'Your project options', client_message = 'Choose what suits you.'
where quote_id = (select id from public.quotes where title = 'Professional proposal');

-- 3. Choice and money invariants ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.quote_version_lines (
      organization_id, quote_id, quote_version_id, position, name, is_taxable, line_kind, selection_kind)
    values ('a1000000-0000-0000-0000-000000000001',
      (select id from public.quotes where title = 'Professional proposal'),
      (select draft_version_id from public.quotes where title = 'Professional proposal'),
      9, 'Broken text', true, 'text', 'required')$$,
  '23514', null, 'text rows cannot carry taxable or priced shape'
);

select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Professional proposal'),
    array['a6000000-0000-0000-0000-000000000005'::uuid]
  ) ->> 'subtotal_minor')::bigint,
  9000::bigint, 'required lines and selected add-ons form the subtotal'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Professional proposal'),
    array['a6000000-0000-0000-0000-000000000005'::uuid]
  ) ->> 'discount_minor')::bigint,
  900::bigint, 'a percentage discount rounds once from selected subtotal'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Professional proposal'),
    array['a6000000-0000-0000-0000-000000000005'::uuid]
  ) ->> 'tax_minor')::bigint,
  800::bigint, 'discount reduces non-taxable value first and tax applies per taxable net line'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Professional proposal'),
    array['a6000000-0000-0000-0000-000000000005'::uuid]
  ) ->> 'total_minor')::bigint,
  8900::bigint, 'the database returns exact grand total'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Professional proposal'),
    array['a6000000-0000-0000-0000-000000000005'::uuid]
  ) ->> 'margin_basis_points')::bigint,
  6049::bigint, 'internal margin follows pre-tax post-discount revenue'
);

update public.quote_versions set discount_type = 'fixed', discount_value = 1001
where quote_id = (select id from public.quotes where title = 'Professional proposal');
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Professional proposal'),
    array['a6000000-0000-0000-0000-000000000005'::uuid]
  ) ->> 'total_minor')::bigint,
  8799::bigint, 'a fixed discount is capped and allocated with stable leftover order before tax'
);
update public.quote_versions set discount_type = 'percentage', discount_value = 1000
where quote_id = (select id from public.quotes where title = 'Professional proposal');

select throws_ok(
  $$select private.calculate_quote_version(
      (select draft_version_id from public.quotes where title = 'Professional proposal'),
      array['a6000000-0000-0000-0000-000000000002'::uuid])$$,
  '23514', null, 'a required line cannot be smuggled in as an add-on choice'
);

-- 4. Freeze, immutability, and clone -----------------------------------------------------------------------

select throws_ok(
  $$select public.freeze_quote_version(
      (select id from public.quotes where title = 'Professional proposal'), 99)$$,
  'P0409', null, 'freeze rejects a stale shared draft revision'
);

select is(
  (public.freeze_quote_version(
    (select id from public.quotes where title = 'Professional proposal'), 1
  ) ->> 'version_number')::integer,
  1, 'the first frozen proposal becomes published version one'
);
select is(
  (select status from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  'published', 'freeze makes the snapshot published'
);
select is(
  (select document_hash ~ '^[0-9a-f]{64}$' from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  true, 'freeze stores a canonical SHA-256 document hash'
);
select is(
  (select total_minor from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  8900::bigint, 'freeze stores the database calculation used by the document'
);
select is(
  (select draft_version_id is null and current_published_version_id is not null
    from public.quotes where title = 'Professional proposal'),
  true, 'the Quote swaps its draft pointer for the current published pointer'
);

select throws_ok(
  $$update public.quote_versions set introduction = 'Rewritten history'
    where quote_id = (select id from public.quotes where title = 'Professional proposal')$$,
  'P0409', null, 'even a privileged update cannot rewrite a published version'
);
select throws_ok(
  $$delete from public.quote_version_lines where id = 'a6000000-0000-0000-0000-000000000001'$$,
  'P0409', null, 'even a privileged delete cannot remove a published line'
);
select throws_ok(
  $$delete from public.quote_version_attachments where attachment_id = 'a4000000-0000-0000-0000-000000000001'$$,
  'P0409', null, 'even a privileged delete cannot remove a published visible file reference'
);
select throws_ok(
  $$delete from public.attachments where id = 'a4000000-0000-0000-0000-000000000001'$$,
  '23503', null, 'the underlying customer-visible file cannot disappear from a published version'
);

select lives_ok(
  $$select public.clone_quote_version_to_draft(
      (select id from public.quotes where title = 'Professional proposal'))$$,
  'a published proposal can be cloned into one new mutable draft'
);
select is(
  (select version_number from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Professional proposal')),
  0, 'the cloned draft returns to version zero'
);
select is(
  (select count(*)::integer from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  2, 'clone preserves the published version beside the new draft'
);
select is(
  (select count(*)::integer from public.quote_version_lines where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Professional proposal')),
  6, 'clone copies every line with new child identities'
);
select is(
  (select count(*)::integer from public.quote_versions where status = 'published' and quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  1, 'cloning never changes published history'
);
select is(
  (select total_minor from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Professional proposal')),
  8900::bigint, 'a cloned draft opens with the money its published version showed'
);
select is(
  (select margin_basis_points from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Professional proposal')),
  6049::bigint, 'the clone is calculated, not copied with empty internal numbers'
);

-- 4b. A second publication cycle keeps the first one -------------------------------------------------------

select is(
  (public.freeze_quote_version(
    (select id from public.quotes where title = 'Professional proposal'), 1
  ) ->> 'version_number')::integer,
  2, 'the second publication becomes version two'
);
select is(
  (select count(*)::integer from public.quote_versions
    where status = 'published' and quote_id =
      (select id from public.quotes where title = 'Professional proposal')),
  2, 'both publications survive the second freeze'
);
select is(
  (select version_number from public.quote_versions where id =
    (select current_published_version_id from public.quotes where title = 'Professional proposal')),
  2, 'the quote now points at its newest publication'
);
select is(
  (select count(*)::integer from public.quote_versions
    where status = 'published' and version_number = 1 and document_hash is not null and quote_id =
      (select id from public.quotes where title = 'Professional proposal')),
  1, 'version one is still published with its own document hash'
);
select is(
  (select draft_version_id from public.quotes where title = 'Professional proposal'),
  null, 'a freeze leaves no draft behind'
);

select throws_ok(
  $$select public.freeze_quote_version(
      (select id from public.quotes where title = 'Professional proposal'), 1)$$,
  '23514', null, 'a quote with no draft cannot be published again'
);
select throws_ok(
  $$select public.set_quote_draft_copy(
      (select id from public.quotes where title = 'Professional proposal'), 1,
      'Rewritten introduction', null)$$,
  '23514', null, 'a draft command refuses a quote that has no draft'
);

select is(
  (select count(*)::integer from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Professional proposal')),
  2, 'the freeze published the clone in place rather than adding a row'
);

-- 5. RLS ---------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);
select is((select count(*)::integer from public.quote_version_attachments), 0,
  'another organization sees no proposal file references');
select is((select count(*)::integer from public.quote_versions), 0,
  'another organization sees no proposal versions');

select * from finish();
rollback;
