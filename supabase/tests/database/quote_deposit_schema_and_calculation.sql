-- Quotes Part 6A: deposit and payment-schedule foundation -- schema and calculation only.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(35);

-- 1. Shape and privileges -----------------------------------------------------------------------------------

select has_table('public', 'quote_version_schedule_items', 'a version has its own ordered installments');
select has_column('public', 'quote_version_schedule_items', 'value_type', 'an installment is fixed or percentage');
select has_column('public', 'quote_version_schedule_items', 'is_deposit', 'one installment may be the deposit');
select has_column('public', 'quote_versions', 'deposit_type', 'a version knows its own deposit shape');
select has_column('public', 'quote_versions', 'deposit_required_minor', 'the deposit answer is database-owned');
select has_index('public', 'quote_version_schedule_items', 'quote_version_schedule_items_version_idx',
  'installment reads follow version order');
select has_index('public', 'quote_version_schedule_items', 'quote_version_schedule_items_one_deposit_idx',
  'at most one installment per version may be the deposit');
select is(has_table_privilege('authenticated', 'public.quote_version_schedule_items', 'insert'), false,
  'Part 6A gives no direct write access; a command comes in Part 6B');
select is(has_table_privilege('authenticated', 'public.quote_version_schedule_items', 'select'), true,
  'members may read schedule items the same way they read lines');

-- 2. Fixtures -------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('c9000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit-admin-a@example.test', 'test', now(), now(), now()),
  ('c9000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deposit-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('c9100000-0000-0000-0000-000000000001', 'Deposit Org A', 'deposit-org-a', 'active'),
  ('c9100000-0000-0000-0000-000000000002', 'Deposit Org B', 'deposit-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('c9100000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001', 'admin'),
  ('c9100000-0000-0000-0000-000000000002', 'c9000000-0000-0000-0000-000000000002', 'admin');

insert into public.clients (id, organization_id, display_name) values
  ('c9200000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001', 'Deposit Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('c9300000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001', 'c9200000-0000-0000-0000-000000000001', '1 Deposit Way', 'Testville');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c9000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('c9200000-0000-0000-0000-000000000001', 'c9300000-0000-0000-0000-000000000001', 'Deposit quote', 'Approved scope only.')$$,
  'a Part 6A fixture quote gets a draft the same way every other quote does'
);

set local role postgres;
select set_config('request.jwt.claim.sub', 'c9000000-0000-0000-0000-000000000001', true);

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, category, name, quantity,
  unit_price_minor, unit_cost_minor, is_taxable, line_kind, selection_kind, is_recommended
) values
  ('c9400000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Deposit quote'),
    (select draft_version_id from public.quotes where title = 'Deposit quote'), 0, 'service',
    'Required work', 1, 10000, 4000, false, 'priced', 'required', false),
  ('c9400000-0000-0000-0000-000000000002', 'c9100000-0000-0000-0000-000000000001',
    (select id from public.quotes where title = 'Deposit quote'),
    (select draft_version_id from public.quotes where title = 'Deposit quote'), 1, 'service',
    'Optional add-on', 1, 5000, 2000, false, 'priced', 'optional', false);

-- 3. No deposit prices as zero, exactly like no discount --------------------------------------------------------

select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'), '{}'::uuid[]
  ) ->> 'deposit_required_minor')::bigint,
  0::bigint, 'a quote with no deposit_type prices no deposit'
);

-- 4. Deposit-only, fixed --------------------------------------------------------------------------------------

update public.quote_versions set deposit_type = 'deposit_only'
where quote_id = (select id from public.quotes where title = 'Deposit quote');

insert into public.quote_version_schedule_items (
  id, organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
) values (
  'c9500000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  (select id from public.quotes where title = 'Deposit quote'),
  (select draft_version_id from public.quotes where title = 'Deposit quote'),
  0, 'Deposit', 'fixed', 2500, true
);

select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'), '{}'::uuid[]
  ) ->> 'deposit_required_minor')::bigint,
  2500::bigint, 'a fixed deposit prices its exact amount against a $100 selection'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'),
    array['c9400000-0000-0000-0000-000000000002'::uuid]
  ) ->> 'deposit_required_minor')::bigint,
  2500::bigint, 'a fixed deposit does not move when the add-on selection changes the total'
);

-- 5. Deposit-only, percentage: it moves with the customer's current selection, like tax --------------------------

update public.quote_version_schedule_items set value_type = 'percentage', value = 1000
where id = 'c9500000-0000-0000-0000-000000000001';

select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'), '{}'::uuid[]
  ) ->> 'deposit_required_minor')::bigint,
  1000::bigint, '10 percent of a $100 required-only selection is $10.00'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'),
    array['c9400000-0000-0000-0000-000000000002'::uuid]
  ) ->> 'deposit_required_minor')::bigint,
  1500::bigint, '10 percent recalculates to $15.00 once the $50 add-on is selected, same as Jobber''s live total'
);

-- 6. A fixed deposit larger than the total is capped, exactly like a fixed discount ------------------------------

update public.quote_version_schedule_items set value_type = 'fixed', value = 999999999
where id = 'c9500000-0000-0000-0000-000000000001';

select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'), '{}'::uuid[]
  ) ->> 'deposit_required_minor')::bigint,
  10000::bigint, 'a deposit larger than the selected total is capped at the total'
);
select is(
  (private.calculate_quote_version(
    (select draft_version_id from public.quotes where title = 'Deposit quote'), '{}'::uuid[]
  ) ->> 'total_minor')::bigint,
  10000::bigint, 'the total itself is unaffected by the deposit'
);

update public.quote_version_schedule_items set value_type = 'percentage', value = 1000
where id = 'c9500000-0000-0000-0000-000000000001';

-- 7. A configured deposit with no installment row is a data problem, not a silent zero --------------------------

delete from public.quote_version_schedule_items where id = 'c9500000-0000-0000-0000-000000000001';

select throws_ok(
  $$select private.calculate_quote_version(
      (select draft_version_id from public.quotes where title = 'Deposit quote'), '{}'::uuid[])$$,
  '23514', null, 'deposit_type set with no is_deposit row refuses rather than pricing a phantom deposit'
);

insert into public.quote_version_schedule_items (
  id, organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
) values (
  'c9500000-0000-0000-0000-000000000001', 'c9100000-0000-0000-0000-000000000001',
  (select id from public.quotes where title = 'Deposit quote'),
  (select draft_version_id from public.quotes where title = 'Deposit quote'),
  0, 'Deposit', 'percentage', 1000, true
);

-- 8. Schema guards ----------------------------------------------------------------------------------------------

select throws_ok(
  $$insert into public.quote_version_schedule_items (
      organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit)
    values ('c9100000-0000-0000-0000-000000000001',
      (select id from public.quotes where title = 'Deposit quote'),
      (select draft_version_id from public.quotes where title = 'Deposit quote'),
      1, 'Second deposit', 'fixed', 1000, true)$$,
  '23505', null, 'only one installment per version may be the deposit'
);
select throws_ok(
  $$insert into public.quote_version_schedule_items (
      organization_id, quote_id, quote_version_id, position, description, value_type, value)
    values ('c9100000-0000-0000-0000-000000000001',
      (select id from public.quotes where title = 'Deposit quote'),
      (select draft_version_id from public.quotes where title = 'Deposit quote'),
      2, 'Too much', 'percentage', 10001)$$,
  '23514', null, 'a percentage installment cannot exceed 100 percent'
);
select throws_ok(
  $$update public.quote_versions set deposit_required_minor = total_minor + 1
    where quote_id = (select id from public.quotes where title = 'Deposit quote')$$,
  '23514', null, 'a version cannot require more deposit than its own total'
);

-- 9. Refresh, freeze, and clone persist the deposit the same way they persist tax --------------------------------

select is(
  (private.refresh_quote_draft_totals(
    (select draft_version_id from public.quotes where title = 'Deposit quote')
  ) ->> 'deposit_required_minor')::bigint,
  1000::bigint, 'refresh recalculates against the draft''s default (no add-ons recommended) selection'
);
select is(
  (select deposit_required_minor from public.quote_versions where quote_id =
    (select id from public.quotes where title = 'Deposit quote')),
  1000::bigint, 'refresh persists the deposit onto the version row'
);

select is(
  (public.publish_quote(
    (select id from public.quotes where title = 'Deposit quote'), 1
  ) ->> 'version_number')::integer,
  1, 'the deposit quote publishes its first version'
);
select is(
  (select deposit_type from public.quote_versions where id =
    (select current_published_version_id from public.quotes where title = 'Deposit quote')),
  'deposit_only', 'the frozen version keeps its deposit shape'
);
select is(
  (select deposit_required_minor from public.quote_versions where id =
    (select current_published_version_id from public.quotes where title = 'Deposit quote')),
  1000::bigint, 'freeze stores the deposit calculation used by the document'
);

select lives_ok(
  $$select public.clone_quote_version_to_draft(
      (select id from public.quotes where title = 'Deposit quote'))$$,
  'a published deposit quote can still be revised into one new draft'
);
select is(
  (select deposit_type from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Deposit quote')),
  'deposit_only', 'the revised draft keeps the deposit type'
);
select is(
  (select count(*)::integer from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit quote')),
  1, 'the revised draft has its own copy of the one deposit installment'
);
select is(
  (select is_deposit from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit quote')),
  true, 'the copied installment is still marked as the deposit'
);
select is(
  (select deposit_required_minor from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Deposit quote')),
  1000::bigint, 'the revised draft opens already priced, not with a stale or empty deposit'
);

-- 10. Create Similar copies the deposit shape into a brand-new quote ----------------------------------------------

select lives_ok(
  $$select public.create_similar_quote((select id from public.quotes where title = 'Deposit quote'))$$,
  'creating a similar quote from a deposit quote succeeds'
);
select is(
  (select deposit_type from public.quote_versions where id =
    (select draft_version_id from public.quotes where title = 'Deposit quote (copy)')),
  'deposit_only', 'the similar quote is its own copy, priced the same deposit way'
);
select is(
  (select count(*)::integer from public.quote_version_schedule_items where quote_version_id =
    (select draft_version_id from public.quotes where title = 'Deposit quote (copy)')),
  1, 'the similar quote copies its own deposit installment row'
);

-- 11. RLS -----------------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c9000000-0000-0000-0000-000000000002', true);
select is((select count(*)::integer from public.quote_version_schedule_items), 0,
  'another organization sees no deposit installments');

select * from finish();
rollback;
