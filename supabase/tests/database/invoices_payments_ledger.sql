-- Invoices, Part 3b-1: the money ledger — receipts, allocation, unapplication, movement, the three
-- balances, the payment-dependent draft rules, append-only history, isolation and replay safety.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention invoices_document_and_commands.sql
-- documents. Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(80);

-- 1. Privileges ------------------------------------------------------------------------------------------------

select is(has_function_privilege('anon',
  'public.record_client_payment(uuid, uuid, bigint, text, date, text, text, jsonb, text, text)', 'execute'),
  false, 'signed-out callers cannot record a payment');
select is(has_function_privilege('authenticated',
  'public.record_client_payment(uuid, uuid, bigint, text, date, text, text, jsonb, text, text)', 'execute'),
  true, 'members reach the record-payment command');
select is(has_function_privilege('anon',
  'public.apply_client_payment(uuid, uuid, uuid, uuid, bigint, text, text, text)', 'execute'),
  false, 'signed-out callers cannot apply a payment');
select is(has_function_privilege('anon',
  'public.unapply_client_payment(uuid, uuid, text, text, text)', 'execute'),
  false, 'signed-out callers cannot take a payment back off a bill');
select is(has_function_privilege('anon',
  'public.move_client_payment(uuid, uuid, uuid, bigint, text, text, text)', 'execute'),
  false, 'signed-out callers cannot move a payment');
select is(has_function_privilege('anon', 'public.client_account_balance(uuid[])', 'execute'),
  false, 'signed-out callers cannot read what a client owes');

-- The money seams are implementation details of the commands, not endpoints of their own.
select is(has_function_privilege('authenticated',
  'private.payment_event_available_minor(uuid, uuid)', 'execute'),
  false, 'members cannot ask the ledger directly how much of a receipt is unspent');
select is(has_function_privilege('authenticated',
  'private.apply_invoice_allocation(public.invoices, uuid, uuid, bigint, uuid, text)', 'execute'),
  false, 'members cannot write an allocation outside a command');
select is(has_function_privilege('authenticated',
  'private.lock_invoice_for_payment(uuid, uuid)', 'execute'),
  false, 'the payment lock helper is not callable by members directly');

select is(has_table_privilege('authenticated', 'public.client_payment_events', 'insert'), false,
  'members cannot write payment history directly');
select is(has_table_privilege('authenticated', 'public.invoice_payment_allocations', 'insert'), false,
  'members cannot write allocations directly');
select is(has_table_privilege('service_role', 'public.client_payment_events', 'update'), false,
  'even the service role cannot rewrite a payment');
select is(has_table_privilege('service_role', 'public.invoice_payment_allocations', 'delete'), false,
  'even the service role cannot delete an allocation');

-- 2. Fixtures --------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pay-owner-a@example.test', 'test', now(), now(), now()),
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pay-field-a@example.test', 'test', now(), now(), now()),
  ('f1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pay-owner-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('f2000000-0000-0000-0000-000000000001', 'Pay Org A', 'pay-org-a', 'active'),
  ('f2000000-0000-0000-0000-000000000002', 'Pay Org B', 'pay-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'owner'),
  ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000002', 'field'),
  ('f2000000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-000000000003', 'owner');

insert into public.clients (id, organization_id, display_name, client_type)
values
  ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'Pay Client One', 'person'),
  ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'Pay Client Two', 'person'),
  ('f3000000-0000-0000-0000-000000000003', 'f2000000-0000-0000-0000-000000000002', 'Pay Client B', 'person');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, country)
values
  ('f4000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', '9 Ledger Lane', 'Testville', 'TX', '78741', 'United States');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

-- One bill for 1000.00, no tax, a custom due date so the fixture needs no term setup.
select lives_ok(
  $$ select public.create_invoice_draft(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Roof repair',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Repair', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 100000, 'is_taxable', false)),
    array['f4000000-0000-0000-0000-000000000001']::uuid[],
    null, '2026-09-30'::date, '2026-09-10'::date, 'pay-idem-draft-1', 'pay-hash-draft-1'
  ) $$,
  'a draft bill for 1000.00 exists to receive money'
);

create temporary view roof as
  select id, revision, invoice_number, issued_at, recognized_at, document_frozen_at
  from public.invoices
  where organization_id = 'f2000000-0000-0000-0000-000000000001' and subject = 'Roof repair';

-- 3. Money on a draft: contract decision D1 ---------------------------------------------------------------------

select is(
  (public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    30000, 'cash', '2026-09-11'::date, 'Envelope', null,
    jsonb_build_array(jsonb_build_object('invoice_id', (select id from roof), 'amount_minor', 30000)),
    'pay-idem-recv-1', 'pay-hash-recv-1'))->>'credit_minor',
  '0', 'money received and fully applied leaves nothing loose'
);

select is((select issued_at from roof), null,
  'paying part of a draft does not issue it');
select is((select recognized_at from roof), null,
  'and paying part of a draft does not settle it');
select is((select document_frozen_at from roof), null,
  'the document of a part-paid draft is still editable');

select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from roof) and event_type = 'invoice.payment_applied'),
  1, 'applying the money wrote one history row');

select is(
  (select price_sensitive from public.invoice_events
    where invoice_id = (select id from roof) and event_type = 'invoice.payment_applied'),
  true, 'and that row is marked price-sensitive, so it stays out of a price-blind feed');

select is(
  (public.invoice_money(array[(select id from roof)]))->(select id::text from roof)->>'remaining_minor',
  '70000', 'the bill now shows 700.00 still owed');
select is(
  (public.invoice_money(array[(select id from roof)]))->(select id::text from roof)->>'allocated_minor',
  '30000', 'and 300.00 applied to it');

-- Until the draft is issued it is not a receivable, and its money is committed to it rather than free.
select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'outstanding_minor',
  '0', 'a draft is not yet money the client owes');
select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'available_credit_minor',
  '0', 'and the money on it is committed to that draft, not free credit');

-- 4. Replay safety ----------------------------------------------------------------------------------------------

select is(
  (public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    30000, 'cash', '2026-09-11'::date, 'Envelope', null,
    jsonb_build_array(jsonb_build_object('invoice_id', (select id from roof), 'amount_minor', 30000)),
    'pay-idem-recv-1', 'pay-hash-recv-1'))->>'applied',
  'false', 'a retry carrying the same key reports that it changed nothing');

select is(
  (select count(*)::int from public.client_payment_events
    where organization_id = 'f2000000-0000-0000-0000-000000000001'),
  1, 'and the retry did not record the money a second time');

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    50000, 'cash', '2026-09-11'::date, null, null, null, 'pay-idem-recv-1', 'pay-hash-changed') $$,
  'P0409', null, 'the same key with a different amount is a conflict, not a second receipt');

-- 5. Money that is not there ------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.apply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from roof),
    (select id from public.client_payment_events
      where organization_id = 'f2000000-0000-0000-0000-000000000001' limit 1),
    null, 1, null, 'pay-idem-over-1', 'pay-hash-over-1') $$,
  '23514', null, 'a receipt that is fully applied has nothing left to give');

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    500000, 'bank_transfer', null, null, null,
    jsonb_build_array(jsonb_build_object('invoice_id', (select id from roof), 'amount_minor', 500000)),
    'pay-idem-over-2', 'pay-hash-over-2') $$,
  '23514', null, 'a bill cannot be paid more than it asks for');

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    1000, 'cash', null, null, null,
    jsonb_build_array(jsonb_build_object('invoice_id', (select id from roof), 'amount_minor', 5000)),
    'pay-idem-over-3', 'pay-hash-over-3') $$,
  '23514', null, 'more cannot be allocated than was received');

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    1000, 'venmo', null, null, null, null, 'pay-idem-method', 'pay-hash-method') $$,
  '23514', null, 'a payment method the product does not record is refused');

-- 6. A draft holding money cannot simply be deleted -------------------------------------------------------------

select throws_ok(
  $$ select public.delete_invoice_draft(
    'f2000000-0000-0000-0000-000000000001', (select id from roof), (select revision from roof),
    'pay-idem-del-1', 'pay-hash-del-1') $$,
  '23514', null, 'a draft holding a payment cannot be deleted until that money is dealt with');

-- 7. Issuing turns it into debt ---------------------------------------------------------------------------------

select lives_ok(
  $$ select public.issue_invoice(
    'f2000000-0000-0000-0000-000000000001', (select id from roof), (select revision from roof),
    'marked_sent', 'pay-idem-issue-1', 'pay-hash-issue-1') $$,
  'the part-paid draft is issued');

select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'outstanding_minor',
  '70000', 'once issued, the unpaid remainder is what the client owes');
select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'account_balance_minor',
  '70000', 'and there is no second receipt: the 300.00 already counted');

select is((select is_effective_receivable from public.invoices where id = (select id from roof)),
  true, 'an issued, unpaid, uncancelled bill counts as money owed');

-- 8. Taking money back off ---------------------------------------------------------------------------------------

create temporary view roof_allocation as
  select id, amount_minor from public.invoice_payment_allocations
  where invoice_id = (select id from roof) and entry_type = 'applied';

select lives_ok(
  $$ select public.unapply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from roof_allocation), 'Wrong bill',
    'pay-idem-unapply-1', 'pay-hash-unapply-1') $$,
  'the payment is returned to the client''s credit');

select is(
  (public.invoice_money(array[(select id from roof)]))->(select id::text from roof)->>'remaining_minor',
  '100000', 'the bill is owed in full again');
select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'available_credit_minor',
  '30000', 'and the money is available credit again');
select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'account_balance_minor',
  '70000', 'what the client actually owes did not move');

select is(
  (select count(*)::int from public.invoice_payment_allocations
    where invoice_id = (select id from roof)),
  2, 'both the application and the entry that took it back are kept');

select throws_ok(
  $$ select public.unapply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from roof_allocation), null,
    'pay-idem-unapply-2', 'pay-hash-unapply-2') $$,
  '23514', null, 'the same application cannot be taken off twice');

-- 9. Moving money between bills -----------------------------------------------------------------------------------

select lives_ok(
  $$ select public.create_invoice_draft(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Fence panels',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Panels', 'category', 'product',
      'quantity', 4, 'unit_price_minor', 10000, 'is_taxable', false)),
    null, null, '2026-09-30'::date, '2026-09-10'::date, 'pay-idem-draft-2', 'pay-hash-draft-2'
  ) $$,
  'a second bill for 400.00 exists');

create temporary view fence as
  select id, revision, invoice_number from public.invoices
  where organization_id = 'f2000000-0000-0000-0000-000000000001' and subject = 'Fence panels';

select lives_ok(
  $$ select public.apply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from fence),
    (select id from public.client_payment_events
      where organization_id = 'f2000000-0000-0000-0000-000000000001' limit 1),
    null, 30000, null, 'pay-idem-apply-1', 'pay-hash-apply-1') $$,
  'the client''s credit is put onto the second bill');

select is(
  (public.invoice_money(array[(select id from fence)]))->(select id::text from fence)->>'remaining_minor',
  '10000', 'the second bill is nearly paid');

select lives_ok(
  $$ select public.move_client_payment(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.invoice_payment_allocations
      where invoice_id = (select id from fence) and entry_type = 'applied'),
    (select id from roof), 20000, 'Moved to the roof bill',
    'pay-idem-move-1', 'pay-hash-move-1') $$,
  'part of that money moves to the first bill');

select is(
  (public.invoice_money(array[(select id from fence)]))->(select id::text from fence)->>'remaining_minor',
  '40000', 'the second bill is owed in full again');
select is(
  (public.invoice_money(array[(select id from roof)]))->(select id::text from roof)->>'remaining_minor',
  '80000', 'the first bill took the 200.00 that moved');
select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'available_credit_minor',
  '10000', 'and the 100.00 that did not move went back to credit');

select is(
  (select count(*)::int from public.invoice_payment_allocations
    where organization_id = 'f2000000-0000-0000-0000-000000000001'),
  5, 'every one of those steps is still on the record');

-- 10. Money stays with its own client and its own tenant ---------------------------------------------------------

select lives_ok(
  $$ select public.create_invoice_draft(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000002', 'Other client bill',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Work', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 5000, 'is_taxable', false)),
    null, null, '2026-09-30'::date, '2026-09-10'::date, 'pay-idem-draft-3', 'pay-hash-draft-3'
  ) $$,
  'a second client has a bill of their own');

select throws_ok(
  $$ select public.apply_client_payment(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where subject = 'Other client bill'),
    (select id from public.client_payment_events
      where organization_id = 'f2000000-0000-0000-0000-000000000001' limit 1),
    null, 1000, null, 'pay-idem-cross-client', 'pay-hash-cross-client') $$,
  '23514', null, 'one client''s money cannot be put on another client''s bill');

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000003',
    1000, 'cash', null, null, null, null, 'pay-idem-cross-org', 'pay-hash-cross-org') $$,
  'P0404', null, 'money cannot be recorded against a client in another organization');

-- 11. Permission boundaries ---------------------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    1000, 'cash', null, null, null, null, 'pay-idem-crew-1', 'pay-hash-crew-1') $$,
  '42501', null, 'a crew member cannot record a payment');

select throws_ok(
  $$ select public.unapply_client_payment(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.invoice_payment_allocations limit 1), null,
    'pay-idem-crew-2', 'pay-hash-crew-2') $$,
  '42501', null, 'a crew member cannot correct where a payment sits');

select throws_ok(
  $$ select public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]) $$,
  '42501', null, 'a crew member cannot read what a client owes');

select is((select count(*)::int from public.client_payment_events), 0,
  'a crew member sees no payment history at all');
select is((select count(*)::int from public.invoice_payment_allocations), 0,
  'and no allocations either');

select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000003', true);

select is((select count(*)::int from public.client_payment_events), 0,
  'the other organization''s owner cannot see this organization''s payments');

select throws_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    1000, 'cash', null, null, null, null, 'pay-idem-tenant', 'pay-hash-tenant') $$,
  '42501', null, 'and cannot record a payment inside it');

-- 12. Receiving money locks the currency, in an organization with no other history --------------------------------

select lives_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000002', 'f3000000-0000-0000-0000-000000000003',
    5000, 'bank_transfer', null, null, null, null, 'pay-idem-orgb', 'pay-hash-orgb') $$,
  'the other organization records its own first payment');

set local role postgres;

select is(private.organization_currency_lock_reason('f2000000-0000-0000-0000-000000000002'),
  'money_received', 'receiving money is on its own enough to lock the currency');

select throws_ok(
  $$ update public.organization_settings set currency_code = 'EUR'
     where organization_id = 'f2000000-0000-0000-0000-000000000002' $$,
  '23514', null, 'the currency cannot change once money has come in');

-- 13. Money history cannot be rewritten, by anyone ------------------------------------------------------------------

select throws_ok(
  $$ update public.client_payment_events set amount_minor = 1 $$,
  '23514', null, 'a recorded payment cannot be edited, even by the table owner');
select throws_ok(
  $$ delete from public.client_payment_events $$,
  '23514', null, 'and it cannot be deleted');
select throws_ok(
  $$ truncate public.invoice_payment_allocations $$,
  '23514', null, 'and allocations cannot be truncated away');

-- 14. A draft paid in full becomes a settled bill: contract decision D1 -----------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$ select public.create_invoice_draft(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001', 'Small job',
    jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Callout', 'category', 'service',
      'quantity', 1, 'unit_price_minor', 5000, 'is_taxable', false)),
    null, null, '2026-09-30'::date, '2026-09-10'::date, 'pay-idem-draft-4', 'pay-hash-draft-4'
  ) $$,
  'a small draft exists');

create temporary view small as
  select id, issued_at, recognized_at, document_frozen_at from public.invoices
  where organization_id = 'f2000000-0000-0000-0000-000000000001' and subject = 'Small job';

select lives_ok(
  $$ select public.record_client_payment(
    'f2000000-0000-0000-0000-000000000001', 'f3000000-0000-0000-0000-000000000001',
    5000, 'check', null, 'Cheque 42', null,
    jsonb_build_array(jsonb_build_object('invoice_id', (select id from small), 'amount_minor', 5000)),
    'pay-idem-settle', 'pay-hash-settle') $$,
  'the small draft is paid in full');

select isnt((select recognized_at from small), null,
  'a draft paid in full becomes a settled bill');
select is((select issued_at from small), null,
  'without pretending it was ever sent');
select isnt((select document_frozen_at from small), null,
  'and its document freezes at that moment');

select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from small) and event_type = 'invoice.recognized'),
  1, 'settlement is recorded once in history');

select throws_ok(
  $$ select public.unapply_client_payment(
    'f2000000-0000-0000-0000-000000000001',
    (select id from public.invoice_payment_allocations
      where invoice_id = (select id from small) and entry_type = 'applied'),
    null, 'pay-idem-unsettle', 'pay-hash-unsettle') $$,
  '23514', null, 'and the money that settled it cannot be pulled back out from under it');

-- 15. A deposit already recorded on a quote is reused, not recorded again ---------------------------------------------

set local role postgres;

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('f5000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 1, 'Roof quote', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name)
values ('f6000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f5000000-0000-0000-0000-000000000001', 1, 'USD', 'Pay Client One', 'Pay Org A');

insert into public.quote_deposit_events (
  id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key)
values ('f7000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001',
  'f5000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000001',
  'received', 25000, 'cash', 'deposit-key-1');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);

select is(
  (public.client_account_balance(array['f3000000-0000-0000-0000-000000000001'::uuid]))
    ->'f3000000-0000-0000-0000-000000000001'->>'available_credit_minor',
  '35000', 'a quote deposit is the client''s money too, without being recorded a second time');

select lives_ok(
  $$ select public.apply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from fence),
    null, 'f7000000-0000-0000-0000-000000000001', 25000, null,
    'pay-idem-deposit-1', 'pay-hash-deposit-1') $$,
  'the deposit is applied to a bill');

select is(
  (select deposit_event_id from public.invoice_payment_allocations
    where invoice_id = (select id from fence) and entry_type = 'applied'
      and deposit_event_id is not null),
  'f7000000-0000-0000-0000-000000000001'::uuid,
  'and the allocation points at the original deposit rather than a copy of it');

select is(
  (select count(*)::int from public.client_payment_events
    where organization_id = 'f2000000-0000-0000-0000-000000000001'),
  2, 'no second receipt was created for the deposit');

select throws_ok(
  $$ select public.apply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from roof),
    null, 'f7000000-0000-0000-0000-000000000001', 1000, null,
    'pay-idem-deposit-2', 'pay-hash-deposit-2') $$,
  '23514', null, 'a deposit that is fully applied has nothing left to give');

select throws_ok(
  $$ select public.apply_client_payment(
    'f2000000-0000-0000-0000-000000000001', (select id from roof),
    (select id from public.client_payment_events limit 1),
    'f7000000-0000-0000-0000-000000000001', 1000, null,
    'pay-idem-deposit-3', 'pay-hash-deposit-3') $$,
  '23514', null, 'a single allocation cannot claim two different sources');

-- 16. A quote whose deposit is on a bill cannot be deleted out from under it -------------------------------------------

set local role postgres;

select throws_ok(
  $$ delete from public.quotes where id = 'f5000000-0000-0000-0000-000000000001' $$,
  '23503', null, 'deleting the quote would orphan money that is sitting on an invoice');

select * from finish();
rollback;
