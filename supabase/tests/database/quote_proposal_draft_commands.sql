-- Quotes, Part 4B: the checked draft commands behind the proposal editor.
-- Run as one transaction against the linked development project; every fixture rolls back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(58);

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

select has_function('public', 'set_quote_draft_discount', 'the discount command exists');
select has_function('public', 'set_quote_draft_tax', 'the tax command exists');
select has_function('public', 'set_quote_draft_visibility', 'the client visibility command exists');
select has_function('public', 'set_quote_draft_copy', 'the proposal copy command exists');
select has_function('public', 'replace_quote_version_attachments', 'the customer file command exists');
select has_function('public', 'preview_quote_version_totals', 'staff can price a scenario without recording it');
select is(has_function_privilege('authenticated', 'public.set_quote_draft_discount(uuid,integer,text,text,bigint)', 'execute'),
  true, 'staff reach the discount through its command');
select is(has_function_privilege('authenticated', 'private.lock_quote_draft(uuid,integer)', 'execute'),
  false, 'the shared preamble is not callable from outside');
select is(has_function_privilege('authenticated', 'private.refresh_quote_draft_totals(uuid)', 'execute'),
  false, 'nothing outside the database recalculates a quote');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('b0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'draft-commands-admin@example.test', 'test', now(), now(), now()),
  ('b0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'draft-commands-outsider@example.test', 'test', now(), now(), now()),
  ('b0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'draft-commands-sales@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status) values
  ('b1000000-0000-0000-0000-000000000001', 'Draft Commands Org A', 'draft-commands-org-a', 'active'),
  ('b1000000-0000-0000-0000-000000000002', 'Draft Commands Org B', 'draft-commands-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role) values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'admin'),
  ('b1000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000002', 'admin'),
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'sales');

insert into public.clients (id, organization_id, display_name) values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Draft Commands Client');

insert into public.properties (id, organization_id, client_id, address_line1, city) values
  ('b3000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001', '9 Command Road', 'Testville');

-- Three shorthands so every call below reads as what it is doing rather than as a pile of subqueries.
-- These look the fixture up rather than take row level security's word for it, so the outsider tests can
-- still name the quote they are not allowed to touch.
create function pg_temp.qid() returns uuid language sql stable security definer as
  'select id from public.quotes where title = ''Draft commands quote''';
create function pg_temp.vid() returns uuid language sql stable security definer as
  'select draft_version_id from public.quotes where title = ''Draft commands quote''';
create function pg_temp.rev() returns integer language sql stable security definer as
  'select revision from public.quote_versions where id = pg_temp.vid()';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.create_quote('b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001', 'Draft commands quote', null)$$,
  'a draft to edit'
);

set local role postgres;
insert into public.attachments (
  id, organization_id, entity_type, entity_id, file_name, mime_type, size_bytes, object_key
) values
  ('b4000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'quote',
    (select id from public.quotes where title = 'Draft commands quote'),
    'site-plan.pdf', 'application/pdf', 2048, 'test/quotes/site-plan.pdf'),
  ('b4000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'client',
    'b2000000-0000-0000-0000-000000000001',
    'client-file.pdf', 'application/pdf', 1024, 'test/clients/file.pdf');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

-- 3. Lines learn about choices ------------------------------------------------------------------------------

select lives_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('name', 'Permit', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 1000, 'unit_cost_minor', 300, 'is_taxable', false),
      jsonb_build_object('name', 'Core work', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 2000, 'unit_cost_minor', 500, 'is_taxable', true),
      jsonb_build_object('name', 'Supplied materials', 'category', 'product', 'quantity', 1,
        'unit_price_minor', 5000, 'unit_cost_minor', 2000, 'is_taxable', true),
      jsonb_build_object('name', 'Recommended add-on', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 1000, 'unit_cost_minor', 400, 'is_taxable', true,
        'selection_kind', 'optional', 'is_recommended', true),
      jsonb_build_object('name', 'Other add-on', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 500, 'unit_cost_minor', 100, 'is_taxable', false,
        'selection_kind', 'optional'),
      jsonb_build_object('name', 'Project note', 'line_kind', 'text',
        'description', 'What the customer should know.')
    ))$$,
  'required work, add-ons, and a note save together'
);
select is((select count(*)::integer from public.quote_version_lines where quote_version_id = pg_temp.vid()),
  6, 'every line is stored');
select is((select quantity from public.quote_version_lines where quote_version_id = pg_temp.vid() and line_kind = 'text'),
  null, 'a note carries no quantity');
select is(pg_temp.money($m$select unit_price_minor from public.quote_version_lines where quote_version_id = pg_temp.vid() and line_kind = 'text'$m$),
  null, 'a note carries no money');

-- The default selection is the one freezing would use: the required work and the recommended add-on.
select is(pg_temp.money($m$select subtotal_minor from public.quote_versions where id = pg_temp.vid()$m$), 9000::bigint,
  'the subtotal is the recommended selection, not every line added up');
select is(pg_temp.money($m$select cost_minor from public.quote_versions where id = pg_temp.vid()$m$), 3200::bigint,
  'cost follows the same selection');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 9000::bigint,
  'with no discount and no tax the total is the subtotal');

select is(
  ((select public.set_quote_draft_visibility(pg_temp.qid(), pg_temp.rev(), true, false, true, true))
    -> 'totals') ? 'cost_minor',
  false, 'a command answer never carries cost, which is a different permission');
select is((select show_unit_prices from public.quote_versions where id = pg_temp.vid()), false,
  'the customer copy can hide unit prices');

-- 5. Tax, then discount, then both --------------------------------------------------------------------------

select lives_ok(
  $$select public.set_quote_draft_tax(pg_temp.qid(), pg_temp.rev(), 'Sales tax', 1000)$$,
  'one named rate is set'
);
select is(pg_temp.money($m$select tax_minor from public.quote_versions where id = pg_temp.vid()$m$), 800::bigint,
  'tax is charged on the taxable lines only');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 9800::bigint,
  'the total picks the tax up');

select lives_ok(
  $$select public.set_quote_draft_discount(pg_temp.qid(), pg_temp.rev(), 'Spring deal', 'fixed', 900)$$,
  'a fixed discount is named and set'
);
select is(pg_temp.money($m$select discount_minor from public.quote_versions where id = pg_temp.vid()$m$), 900::bigint,
  'the discount is what was asked for');
select is(pg_temp.money($m$select tax_minor from public.quote_versions where id = pg_temp.vid()$m$), 800::bigint,
  'a discount that fits inside the non-taxable work leaves the tax alone');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 8900::bigint,
  'the total comes down by the discount');

select lives_ok(
  $$select public.set_quote_draft_discount(pg_temp.qid(), pg_temp.rev(), 'Spring deal', 'percentage', 2000)$$,
  'the same discount becomes a percentage'
);
select is(pg_temp.money($m$select discount_minor from public.quote_versions where id = pg_temp.vid()$m$), 1800::bigint,
  'twenty percent of the selected work');
select is(pg_temp.money($m$select tax_minor from public.quote_versions where id = pg_temp.vid()$m$), 720::bigint,
  'what spills past the non-taxable work reduces the tax with it');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 7920::bigint,
  'discount first, tax after');

select lives_ok(
  $$select public.set_quote_draft_discount(pg_temp.qid(), pg_temp.rev(), 'Everything off', 'fixed', 100000)$$,
  'a discount larger than the work is accepted'
);
select is(pg_temp.money($m$select discount_minor from public.quote_versions where id = pg_temp.vid()$m$), 9000::bigint,
  'and capped at what the work costs');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 0::bigint,
  'nothing left to pay and nothing left to tax');

select lives_ok(
  $$select public.set_quote_draft_discount(pg_temp.qid(), pg_temp.rev(), null, null, null)$$,
  'the discount is removed'
);
select is((select discount_name from public.quote_versions where id = pg_temp.vid()), null,
  'its name goes with it');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 9800::bigint,
  'the total goes back to work plus tax');

select lives_ok(
  $$select public.set_quote_draft_tax(pg_temp.qid(), pg_temp.rev(), 'Sales tax', 0)$$,
  'No tax is chosen'
);
select is((select tax_name from public.quote_versions where id = pg_temp.vid()), null,
  'No tax has no name to show');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 9000::bigint,
  'and the total is the work again');

-- 6. The words on the page ----------------------------------------------------------------------------------

select lives_ok(
  $$select public.set_quote_draft_copy(pg_temp.qid(), pg_temp.rev(), '  Thanks for having us out.  ', 'Call any time.')$$,
  'the introduction and client message save'
);
select is((select introduction from public.quote_versions where id = pg_temp.vid()), 'Thanks for having us out.',
  'stray spaces are trimmed off');
select is((select client_message from public.quote_versions where id = pg_temp.vid()), 'Call any time.',
  'the client message is stored as typed');

-- 7. Pricing a scenario without recording it ------------------------------------------------------------------

select is(
  (public.preview_quote_version_totals(pg_temp.qid(), '{}'::uuid[]) ->> 'subtotal_minor')::bigint,
  8000::bigint, 'taking no add-ons prices only the work the customer has to have');
select is(
  public.preview_quote_version_totals(pg_temp.qid(), '{}'::uuid[]) ? 'cost_minor',
  true, 'someone allowed to see cost sees it');
select is(pg_temp.money($m$select total_minor from public.quote_versions where id = pg_temp.vid()$m$), 9000::bigint,
  'a preview records nothing');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
select is(
  public.preview_quote_version_totals(pg_temp.qid(), '{}'::uuid[]) ? 'cost_minor',
  false, 'someone without the cost permission never receives it');

-- Seeing the quote and seeing what the client pays are two different grants. The whole answer here is
-- money, so with the price permission taken away the preview refuses instead of returning a blank one.
set local role postgres;
insert into public.organization_member_permission_overrides
  (organization_id, user_id, permission_key, override_state)
values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003',
   'quotes.view_price', 'deny');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.preview_quote_version_totals(pg_temp.qid(), '{}'::uuid[])$$,
  '42501', null, 'someone without the price permission cannot price a scenario'
);

set local role postgres;
delete from public.organization_member_permission_overrides
where organization_id = 'b1000000-0000-0000-0000-000000000001'
  and user_id = 'b0000000-0000-0000-0000-000000000003'
  and permission_key = 'quotes.view_price';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000001', true);

-- 8. What the commands refuse ----------------------------------------------------------------------------------

select throws_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('name', 'Already in', 'category', 'service', 'quantity', 1,
        'unit_price_minor', 100, 'unit_cost_minor', 0, 'is_recommended', true)
    ))$$,
  '23514', null, 'required work cannot also be recommended'
);
select throws_ok(
  $$select public.set_quote_draft_discount(pg_temp.qid(), pg_temp.rev(), '  ', 'fixed', 500)$$,
  '23514', null, 'a discount the customer reads needs a name'
);
select throws_ok(
  $$select public.set_quote_draft_tax(pg_temp.qid(), pg_temp.rev(), null, 1000)$$,
  '23514', null, 'a tax the customer pays needs a name'
);
select throws_ok(
  $$select public.set_quote_draft_discount(pg_temp.qid(), pg_temp.rev() - 1, 'Late', 'fixed', 100)$$,
  'P0409', null, 'a rail dialog cannot overwrite a line save it never saw'
);
select throws_ok(
  $$select public.replace_quote_version_lines(pg_temp.qid(), pg_temp.rev() - 1, '[]'::jsonb)$$,
  'P0409', null, 'and a line save cannot overwrite a rail dialog either'
);

-- 9. Customer-visible files ------------------------------------------------------------------------------------

select lives_ok(
  $$select public.replace_quote_version_attachments(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('attachment_id', 'b4000000-0000-0000-0000-000000000001',
        'display_name', 'Site plan', 'customer_visible', true)
    ))$$,
  'a file uploaded to this quote can be shown to the customer'
);
select is((select count(*)::integer from public.quote_version_attachments
    where quote_version_id = pg_temp.vid() and customer_visible), 1,
  'the reference is recorded, not a copy of the file');
select throws_ok(
  $$select public.replace_quote_version_attachments(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('attachment_id', 'b4000000-0000-0000-0000-000000000002', 'display_name', 'Client file')
    ))$$,
  '23514', null, 'a file from elsewhere in the tenant cannot be pulled into this quote'
);
select throws_ok(
  $$select public.replace_quote_version_attachments(pg_temp.qid(), pg_temp.rev(), jsonb_build_array(
      jsonb_build_object('attachment_id', 'b4000000-0000-0000-0000-000000000001', 'display_name', 'Site plan'),
      jsonb_build_object('attachment_id', 'b4000000-0000-0000-0000-000000000001', 'display_name', 'Site plan again')
    ))$$,
  '23514', null, 'the same file cannot be listed twice'
);

-- 10. Somebody else's quote ------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-000000000002', true);

select throws_ok(
  format($$select public.set_quote_draft_discount(%L::uuid, 1, 'Theirs', 'fixed', 100)$$, pg_temp.qid()),
  '42501', null, 'another organization cannot discount a quote it cannot see'
);
select is((select count(*)::integer from public.quote_version_lines), 0,
  'and sees none of its lines at all');

select * from finish();
rollback;
