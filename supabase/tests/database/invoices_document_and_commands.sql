-- Invoices, Part 3a: the bill itself — numbering, snapshots, arithmetic, the draft and issue commands,
-- retained prior documents, append-only history, isolation and replay safety.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_pricing_and_billing_commands.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
--
-- Every expected_revision below is read back inline rather than counted by hand. The one exception is the
-- stale-revision guard, which sends a number that is deliberately wrong.
begin;

create extension if not exists pgtap with schema extensions;

select plan(72);

-- 1. Privileges ------------------------------------------------------------------------------------------------

select is(has_function_privilege('anon',
  'public.create_invoice_draft(uuid, uuid, text, jsonb, uuid[], uuid, date, date, text, text)', 'execute'),
  false, 'signed-out callers cannot create an invoice');
select is(has_function_privilege('authenticated',
  'public.create_invoice_draft(uuid, uuid, text, jsonb, uuid[], uuid, date, date, text, text)', 'execute'),
  true, 'members reach the create command');
select is(has_function_privilege('anon',
  'public.issue_invoice(uuid, uuid, integer, text, text, text)', 'execute'),
  false, 'signed-out callers cannot issue an invoice');
select is(has_function_privilege('anon',
  'public.delete_invoice_draft(uuid, uuid, integer, text, text)', 'execute'),
  false, 'signed-out callers cannot delete a draft');
select is(has_function_privilege('anon', 'public.invoice_money(uuid[])', 'execute'),
  false, 'signed-out callers cannot read invoice amounts');

-- The private seams are implementation details of those commands, not endpoints of their own.
select is(has_function_privilege('authenticated',
  'private.lock_invoice_for_edit(uuid, uuid, integer, text)', 'execute'),
  false, 'the shared lock helper is not callable by members directly');
select is(has_function_privilege('authenticated',
  'private.begin_invoice_command(uuid, text, text, text, uuid)', 'execute'),
  false, 'members cannot claim a command receipt themselves');
select is(has_function_privilege('authenticated', 'private.calculate_invoice(uuid)', 'execute'),
  false, 'members cannot run invoice arithmetic outside a command');
select is(has_function_privilege('authenticated', 'private.allocate_invoice_number(uuid)', 'execute'),
  false, 'members cannot hand themselves an invoice number');
select is(has_function_privilege('authenticated', 'private.invoice_allocated_minor(uuid, uuid)', 'execute'),
  false, 'the money seam is not a member-facing read');

-- Money is not in the table grant: it comes back through public.invoice_money, which checks view_price.
select is(has_column_privilege('authenticated', 'public.invoices', 'total_minor', 'select'),
  false, 'members cannot read invoice totals straight off the table');
select is(has_column_privilege('authenticated', 'public.invoices', 'subtotal_minor', 'select'),
  false, 'members cannot read invoice subtotals straight off the table');
select is(has_column_privilege('authenticated', 'public.invoices', 'subject', 'select'),
  true, 'members can read what the bill is for');
select is(has_table_privilege('authenticated', 'public.invoices', 'insert'), false,
  'members cannot write invoices directly');
select is(has_table_privilege('authenticated', 'public.invoice_lines', 'update'), false,
  'members cannot rewrite invoice lines directly');
select is(has_table_privilege('authenticated', 'public.invoice_events', 'insert'), false,
  'members cannot write invoice history directly');
select is(has_table_privilege('service_role', 'public.invoice_events', 'update'), false,
  'even the service role cannot rewrite invoice history');
select is(has_table_privilege('authenticated', 'public.organization_invoice_counters', 'select'), false,
  'members cannot read how many invoices an organization has');

-- 2. Fixtures --------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invoice-owner-a@example.test', 'test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invoice-field-a@example.test', 'test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invoice-owner-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('e2000000-0000-0000-0000-000000000001', 'Invoice Org A', 'invoice-org-a', 'active'),
  ('e2000000-0000-0000-0000-000000000002', 'Invoice Org B', 'invoice-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'owner'),
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 'field'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000003', 'owner');

insert into public.clients (id, organization_id, display_name, client_type)
values
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Invoice Client A', 'person'),
  ('e3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'Invoice Client B', 'person');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, country)
values
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', '3 Ledger Lane', 'Testville', 'TX', '78741', 'United States');

-- Every organization is seeded with the standard terms by the trigger in file 1.
select is(
  (select count(*)::int from public.invoice_payment_terms
    where organization_id = 'e2000000-0000-0000-0000-000000000001'),
  8, 'a new organization starts with the eight standard payment terms'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- The client bills to a designated property, chosen through the one guarded billing command, and pays on
-- Net 15 rather than the organization default.
select lives_ok(
  $$ select public.set_client_billing(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'property',
    'e4000000-0000-0000-0000-000000000001', null, null, null, null, null, null,
    (select id from public.invoice_payment_terms
      where organization_id = 'e2000000-0000-0000-0000-000000000001' and rule = 'net_days' and net_days = 15)
  ) $$,
  'the client is set to bill to a designated property on Net 15'
);

-- 3. Creating a draft ------------------------------------------------------------------------------------------

select lives_ok(
  $$ select public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
    'Autumn maintenance',
    jsonb_build_array(
      jsonb_build_object('position', 1, 'name', 'Gutter clearing', 'category', 'service',
        'quantity', 2.5, 'unit_price_minor', 4000, 'is_taxable', true),
      jsonb_build_object('position', 0, 'name', 'Downpipe bracket', 'category', 'product',
        'quantity', 1, 'unit_price_minor', 2500, 'is_taxable', false),
      jsonb_build_object('position', 2, 'line_kind', 'heading', 'name', 'Notes', 'is_taxable', false)
    ),
    array['e4000000-0000-0000-0000-000000000001']::uuid[],
    null, null, '2026-09-10'::date, 'invoice-idem-0001', 'invoice-hash-0001'
  ) $$,
  'a draft invoice is created from lines, a client and a service property'
);

create temporary view target_invoice as
  select id, revision, invoice_number, issue_date, due_date, document_frozen_at, issued_at, currency_code
  from public.invoices
  where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Autumn maintenance';

select is((select invoice_number from target_invoice), 1,
  'the first invoice in an organization is number 1');
select is((select revision from target_invoice), 0, 'a new draft starts at revision 0');

-- Net 15 from the issue date the caller chose, in the organization's own calendar.
select is((select due_date from target_invoice), '2026-09-25'::date,
  'the due date is the client term applied to the issue date');

-- Lines are renumbered from the order the payload asked for, not the order they arrived in.
select is(
  (select array_agg(name order by position) from public.invoice_lines
    where invoice_id = (select id from target_invoice)),
  array['Downpipe bracket', 'Gutter clearing', 'Notes'],
  'the lines are stored in the order the payload numbered them'
);

set local role postgres;

-- 2.5 x 4000 = 10000 taxable, plus 2500 exempt. Fractional quantity, one rounding rule, no tax configured yet.
select is((select subtotal_minor from public.invoices where id = (select id from target_invoice)),
  12500::bigint, 'the subtotal is calculated by the database from a fractional quantity');
select is((select tax_minor from public.invoices where id = (select id from target_invoice)),
  0::bigint, 'a draft with no tax configured is not taxed');

select is(
  (select billing_address_snapshot->>'source' from public.invoices where id = (select id from target_invoice)),
  'property', 'the billing address is snapshotted from the designated property');
select is(
  (select billing_address_snapshot->>'address_line1' from public.invoices
    where id = (select id from target_invoice)),
  '3 Ledger Lane', 'the address itself is copied onto the bill, not looked up later');
select is(
  (select jsonb_array_length(service_properties) from public.invoices
    where id = (select id from target_invoice)),
  1, 'the service property is frozen into the document snapshot');
select is(
  (select payment_term_snapshot->>'name' from public.invoices where id = (select id from target_invoice)),
  'Net 15', 'the term is snapshotted by name, so renaming it later cannot rewrite the bill');
select is(
  (select customer_snapshot->>'display_name' from public.invoices where id = (select id from target_invoice)),
  'Invoice Client A', 'the customer is snapshotted onto the bill');
select is((select currency_code from target_invoice), 'USD',
  'the organization currency is snapshotted onto the bill');

select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from target_invoice) and event_type = 'invoice.created'),
  1, 'creating the draft wrote one history row');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 4. Replay safety ---------------------------------------------------------------------------------------------

select is(
  (public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
    'Autumn maintenance',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Gutter clearing', 'category', 'service',
      'quantity', 2.5, 'unit_price_minor', 4000, 'is_taxable', true)),
    null, null, null, '2026-09-10'::date, 'invoice-idem-0001', 'invoice-hash-0001'
  ))->>'applied',
  'false', 'a retry carrying the same key reports that it changed nothing'
);

select is(
  (select count(*)::int from public.invoices
    where organization_id = 'e2000000-0000-0000-0000-000000000001'),
  1, 'and the retry did not create a second invoice'
);

select throws_ok(
  $$ select public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
    'Different bill',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Something else', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 1000, 'is_taxable', true)),
    null, null, null, null, 'invoice-idem-0001', 'invoice-hash-changed') $$,
  'P0409', null, 'the same key with different details is a conflict, not a silent second bill'
);

-- 5. Guards on the edit commands -------------------------------------------------------------------------------

select throws_ok(
  $$ select public.replace_invoice_lines(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice), 99, '[]'::jsonb) $$,
  'P0409', null, 'a stale revision is refused rather than wiping newer lines'
);

select throws_ok(
  $$ select public.replace_invoice_lines(
    'e2000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000099', 0, '[]'::jsonb) $$,
  'P0404', null, 'editing an invoice that is not in this organization is a not-found'
);

select throws_ok(
  $$ select public.replace_invoice_lines(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice), '[]'::jsonb) $$,
  '23514', null, 'an invoice cannot be left with no lines at all'
);

-- The 100-line cap is the table's own statement trigger, so it holds whichever command inserts.
select throws_ok(
  $$ select public.replace_invoice_lines(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice),
    (select jsonb_agg(jsonb_build_object(
      'position', n, 'name', 'Line ' || n, 'category', 'service',
      'quantity', 1, 'unit_price_minor', 100, 'is_taxable', true))
     from generate_series(1, 101) as n)) $$,
  '54000', null, 'an invoice cannot be given more than 100 lines'
);

-- 6. Tax and discount ------------------------------------------------------------------------------------------

select lives_ok(
  $$ select public.set_invoice_tax(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice), 'custom', null, 'Sales tax', 825) $$,
  'a custom tax rate is applied to the bill'
);

select lives_ok(
  $$ select public.set_invoice_discount(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice), 'Autumn offer', 'percentage', 1000) $$,
  'a percentage discount is applied to the bill'
);

set local role postgres;

-- 12500 subtotal, 10% discount = 1250 taken from the exempt group first (2500 of it), so the taxable 10000
-- is taxed in full at 8.25% = 825. Total 12500 - 1250 + 825 = 12075.
select is((select discount_minor from public.invoices where id = (select id from target_invoice)),
  1250::bigint, 'the discount is calculated from the subtotal');
select is((select tax_minor from public.invoices where id = (select id from target_invoice)),
  825::bigint, 'tax falls only on the taxable lines, after their share of the discount');
select is((select total_minor from public.invoices where id = (select id from target_invoice)),
  12075::bigint, 'the total is subtotal less discount plus tax');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 7. Permission boundaries -------------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$ select public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Crew attempt',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 1000, 'is_taxable', true)),
    null, null, null, null, 'invoice-idem-crew', 'invoice-hash-crew') $$,
  '42501', null, 'a crew member cannot create an invoice'
);

select throws_ok(
  $$ select public.issue_invoice(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice), 0, 'marked_sent',
    'invoice-idem-crew-2', 'invoice-hash-crew-2') $$,
  '42501', null, 'a crew member cannot issue an invoice'
);

select is((select count(*)::int from public.invoices), 0,
  'a crew member without invoices.view sees no invoices at all');

-- 8. Tenant isolation ------------------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000003', true);

select is((select count(*)::int from public.invoices), 0,
  'the other organization''s owner cannot see this organization''s invoices');

select throws_ok(
  $$ select public.replace_invoice_lines(
    'e2000000-0000-0000-0000-000000000001', (select id from public.invoices limit 1), 0, '[]'::jsonb) $$,
  '42501', null, 'the other organization''s owner cannot edit an invoice here'
);

select throws_ok(
  $$ select public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000001', 'Cross tenant bill',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 1000, 'is_taxable', true)),
    null, null, null, null, 'invoice-idem-cross', 'invoice-hash-cross') $$,
  'P0404', null, 'an invoice cannot be billed to a client in another organization'
);

-- Numbering is per organization, so org B's first invoice is also number 1.
select is(
  (public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', 'Org B first bill',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 1000, 'is_taxable', true)),
    null, null, null, null, 'invoice-idem-orgb', 'invoice-hash-orgb'))->>'invoice_number',
  '1', 'invoice numbers start again at 1 in another organization'
);

select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 9. Issuing and the frozen document ---------------------------------------------------------------------------

select lives_ok(
  $$ select public.issue_invoice(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice), 'marked_sent', 'invoice-idem-issue', 'invoice-hash-issue') $$,
  'the draft is issued by marking it sent'
);

select isnt((select document_frozen_at from target_invoice), null,
  'issuing freezes the document');
select isnt((select issued_at from target_invoice), null, 'and records when it was issued');

select is(
  (public.issue_invoice(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice), 'marked_sent', 'invoice-idem-issue', 'invoice-hash-issue'
  ))->>'applied',
  'false', 'issuing again with the same key changes nothing'
);

-- A permitted edit to an issued bill keeps the whole previous document in history.
select lives_ok(
  $$ select public.replace_invoice_lines(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice),
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Gutter clearing revisited',
      'category', 'service', 'quantity', 1, 'unit_price_minor', 9000, 'is_taxable', true))) $$,
  'an issued invoice may still be corrected'
);

set local role postgres;

select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from target_invoice) and prior_document_snapshot is not null),
  1, 'the correction kept one complete copy of the previous document'
);

select is(
  (select (prior_document_snapshot->'totals'->>'total_minor') from public.invoice_events
    where invoice_id = (select id from target_invoice) and prior_document_snapshot is not null),
  '12075', 'the retained copy still carries the amounts the customer was given'
);

select is(
  (select bool_and(price_sensitive) from public.invoice_events
    where invoice_id = (select id from target_invoice) and prior_document_snapshot is not null),
  true, 'a retained document is marked price sensitive, so price-blind readers never see it'
);

-- History is append-only for the table owner too, not only for members.
select throws_ok(
  $$ update public.invoice_events set event_type = 'tampered'
     where invoice_id = (select id from target_invoice) $$,
  '23514', null, 'invoice history cannot be rewritten, even as the owner'
);
select throws_ok(
  $$ delete from public.invoice_events where invoice_id = (select id from target_invoice) $$,
  '23514', null, 'invoice history cannot be deleted, even as the owner'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 10. Deleting drafts ------------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.delete_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', (select id from target_invoice),
    (select revision from target_invoice), 'invoice-idem-del', 'invoice-hash-del') $$,
  '23514', null, 'an issued invoice cannot be deleted'
);

select lives_ok(
  $$ select public.create_invoice_draft(
    'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Throwaway draft',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 1000, 'is_taxable', true)),
    null, null, null, null, 'invoice-idem-0002', 'invoice-hash-0002') $$,
  'a second draft is created'
);

select is(
  (select invoice_number from public.invoices
    where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Throwaway draft'),
  2, 'the second invoice takes the next number'
);

select lives_ok(
  $$ select public.delete_invoice_draft(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where organization_id = 'e2000000-0000-0000-0000-000000000001'
      and subject = 'Throwaway draft'),
    (select revision from public.invoices where organization_id = 'e2000000-0000-0000-0000-000000000001'
      and subject = 'Throwaway draft'),
    'invoice-idem-del-2', 'invoice-hash-del-2') $$,
  'a draft nobody has been given can be deleted'
);

set local role postgres;

select is(
  (select count(*)::int from public.invoices
    where organization_id = 'e2000000-0000-0000-0000-000000000001' and subject = 'Throwaway draft'),
  0, 'the draft is gone'
);

select is(
  (select count(*)::int from public.invoice_events
    where organization_id = 'e2000000-0000-0000-0000-000000000001' and invoice_number = 2),
  2, 'but its history survives it, carrying the number it had'
);

-- A number is never handed out twice, even after the invoice that used it was deleted.
select is(
  (select next_invoice_number from public.organization_invoice_counters
    where organization_id = 'e2000000-0000-0000-0000-000000000001'),
  3, 'the counter never goes backwards after a deletion'
);

-- 11. The currency lock ----------------------------------------------------------------------------------------

select is(private.organization_currency_lock_reason('e2000000-0000-0000-0000-000000000001'),
  'invoice_issued', 'issuing an invoice locks the organization currency');

select throws_ok(
  $$ update public.organization_settings set currency_code = 'EUR'
     where organization_id = 'e2000000-0000-0000-0000-000000000001' $$,
  '23514', null, 'the currency cannot change once a bill has been issued'
);

select * from finish();
rollback;
