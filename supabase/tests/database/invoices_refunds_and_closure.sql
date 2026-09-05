-- Invoices, Part 3b-2: refunds, reversal of a mistaken entry, Void with its deposit release, bad debt and
-- its undo, and status-only closure and reopening.
--
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention invoices_payments_ledger.sql documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and `set_config`
-- do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(89);

-- 1. Privileges ------------------------------------------------------------------------------------------------

select is(has_function_privilege('anon',
  'public.refund_client_payment(uuid, uuid, uuid, bigint, text, date, text, text, text, text)', 'execute'),
  false, 'signed-out callers cannot refund money');
select is(has_function_privilege('authenticated',
  'public.refund_client_payment(uuid, uuid, uuid, bigint, text, date, text, text, text, text)', 'execute'),
  true, 'members reach the refund command');
select is(has_function_privilege('anon',
  'public.reverse_client_payment(uuid, uuid, text, text, text)', 'execute'),
  false, 'signed-out callers cannot correct a payment away');
select is(has_function_privilege('anon',
  'public.void_invoice(uuid, uuid, text, text, text, text)', 'execute'),
  false, 'signed-out callers cannot void a bill');
select is(has_function_privilege('authenticated',
  'public.void_invoice(uuid, uuid, text, text, text, text)', 'execute'),
  true, 'members reach the void command');
select is(has_function_privilege('anon',
  'public.write_off_invoice(uuid, uuid, text, text, text)', 'execute'),
  false, 'signed-out callers cannot write off a balance');
select is(has_function_privilege('anon',
  'public.restore_invoice_from_write_off(uuid, uuid, text, text, text)', 'execute'),
  false, 'signed-out callers cannot undo a write-off');
select is(has_function_privilege('anon',
  'public.mark_invoice_received(uuid, uuid, text, text, text)', 'execute'),
  false, 'signed-out callers cannot close a bill by hand');
select is(has_function_privilege('anon',
  'public.reopen_invoice(uuid, uuid, text, text, text)', 'execute'),
  false, 'signed-out callers cannot reopen a bill');

-- 2. Fixtures --------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ref-owner-a@example.test', 'test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ref-field-a@example.test', 'test', now(), now(), now()),
  ('e1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ref-owner-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('e2000000-0000-0000-0000-000000000001', 'Refund Org A', 'refund-org-a', 'active'),
  ('e2000000-0000-0000-0000-000000000002', 'Refund Org B', 'refund-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'owner'),
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 'field'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000003', 'owner');

insert into public.clients (id, organization_id, display_name, client_type)
values
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'Refund Client One', 'person'),
  ('e3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001', 'Refund Client Two', 'person');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code, country)
values
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', '11 Refund Row', 'Testville', 'TX', '78741', 'United States'),
  ('e4000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', '12 Refund Row', 'Testville', 'TX', '78741', 'United States');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- Five issued bills and one draft, so every rule below has a bill in the right shape to act on.
select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Roof',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Roof', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 100000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-roof', 'ref-hash-roof');

select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Gate',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Gate', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 30000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-gate', 'ref-hash-gate');

select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'Mailbox',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Mailbox', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 10000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000001']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-mailbox', 'ref-hash-mailbox');

select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'Patio',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Patio', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 60000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000002']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-patio', 'ref-hash-patio');

select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'Deck',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Deck', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 80000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000002']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-deck', 'ref-hash-deck');

select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'Path',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Path', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 30000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000002']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-path', 'ref-hash-path');

-- Shed stays a draft on purpose: the draft refusals need one.
select public.create_invoice_draft(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'Shed',
  jsonb_build_array(jsonb_build_object('position', 0, 'name', 'Shed', 'category', 'service',
    'quantity', 1, 'unit_price_minor', 20000, 'is_taxable', false)),
  array['e4000000-0000-0000-0000-000000000002']::uuid[],
  null, '2026-09-30'::date, '2026-09-10'::date, 'ref-idem-shed', 'ref-hash-shed');

create temporary view bill as
  select subject, id, revision, invoice_number, voided_at, void_reason, written_off_at,
         marked_received_at, is_effective_receivable
  from public.invoices
  where organization_id = 'e2000000-0000-0000-0000-000000000001';

select public.issue_invoice('e2000000-0000-0000-0000-000000000001',
  (select id from bill where subject = 'Roof'), (select revision from bill where subject = 'Roof'),
  'marked_sent', 'ref-idem-issue-roof', 'ref-hash-issue-roof');
select public.issue_invoice('e2000000-0000-0000-0000-000000000001',
  (select id from bill where subject = 'Gate'), (select revision from bill where subject = 'Gate'),
  'marked_sent', 'ref-idem-issue-gate', 'ref-hash-issue-gate');
select public.issue_invoice('e2000000-0000-0000-0000-000000000001',
  (select id from bill where subject = 'Mailbox'), (select revision from bill where subject = 'Mailbox'),
  'marked_sent', 'ref-idem-issue-mailbox', 'ref-hash-issue-mailbox');
select public.issue_invoice('e2000000-0000-0000-0000-000000000001',
  (select id from bill where subject = 'Patio'), (select revision from bill where subject = 'Patio'),
  'marked_sent', 'ref-idem-issue-patio', 'ref-hash-issue-patio');
select public.issue_invoice('e2000000-0000-0000-0000-000000000001',
  (select id from bill where subject = 'Deck'), (select revision from bill where subject = 'Deck'),
  'marked_sent', 'ref-idem-issue-deck', 'ref-hash-issue-deck');
select public.issue_invoice('e2000000-0000-0000-0000-000000000001',
  (select id from bill where subject = 'Path'), (select revision from bill where subject = 'Path'),
  'marked_sent', 'ref-idem-issue-path', 'ref-hash-issue-path');

create temporary view credit_one as
  select (public.client_account_balance(array['e3000000-0000-0000-0000-000000000001'::uuid]))
    ->'e3000000-0000-0000-0000-000000000001'->>'available_credit_minor' as amount;

create temporary view owed_two as
  select (public.client_account_balance(array['e3000000-0000-0000-0000-000000000002'::uuid]))
    ->'e3000000-0000-0000-0000-000000000002'->>'outstanding_minor' as amount;

-- 3. Money sent back -------------------------------------------------------------------------------------------

select public.record_client_payment(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  40000, 'bank_transfer', '2026-09-11'::date, 'Wire 900', null, null, 'ref-idem-recv-1', 'ref-hash-recv-1');

create temporary view receipt_one as
  select id from public.client_payment_events
  where organization_id = 'e2000000-0000-0000-0000-000000000001'
    and event_type = 'received' and amount_minor = 40000;

select is((select amount from credit_one), '40000', 'money with nowhere to go is the client''s credit');

select is(
  (public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one), null,
    15000, 'bank_transfer', '2026-09-12'::date, 'Wire back', 'Overpaid',
    'ref-idem-refund-1', 'ref-hash-refund-1'))->>'remaining_refundable_minor',
  '25000', 'refunding part of a receipt leaves the rest refundable');

select is((select amount from credit_one), '25000',
  'and money sent back is no longer the client''s to spend');

select is(
  (select event_type from public.client_payment_events where amount_minor = 15000),
  'refunded', 'the refund is its own row, not an edit of the receipt');
select is(
  (select original_event_id from public.client_payment_events where amount_minor = 15000),
  (select id from receipt_one), 'and it points at the receipt it came out of');
select is(
  (select amount_minor from public.client_payment_events where id = (select id from receipt_one)),
  40000::bigint, 'the original receipt still says what it always said');

select throws_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one), null,
    25001, 'cash', null, null, null, 'ref-idem-refund-over', 'ref-hash-refund-over') $$,
  '23514', null, 'a refund cannot exceed what the receipt still has left');

select is(
  (public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one), null,
    15000, 'bank_transfer', '2026-09-12'::date, 'Wire back', 'Overpaid',
    'ref-idem-refund-1', 'ref-hash-refund-1'))->>'applied',
  'false', 'a retry carrying the same key reports that it changed nothing');
select is(
  (select count(*)::int from public.client_payment_events where event_type = 'refunded'),
  1, 'and the retry did not send the money back twice');

select throws_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one), null,
    1000, 'not_a_method', null, null, null, 'ref-idem-refund-method', 'ref-hash-refund-method') $$,
  '23514', null, 'a refund has to say how the money went back');
select throws_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', null, null,
    1000, 'cash', null, null, null, 'ref-idem-refund-none', 'ref-hash-refund-none') $$,
  '23514', null, 'a refund needs something to refund');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.client_payment_events where event_type = 'received' and amount_minor = 40000),
    null, 1000, 'cash', null, null, null, 'ref-idem-refund-field', 'ref-hash-refund-field') $$,
  '42501', null, 'a field member cannot send a client''s money back');
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 4. An entry that never happened -------------------------------------------------------------------------------

create temporary view refund_one as
  select id from public.client_payment_events where event_type = 'refunded' and amount_minor = 15000;

select lives_ok(
  $$ select public.reverse_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from refund_one),
    'Refund was recorded against the wrong client', 'ref-idem-unrefund', 'ref-hash-unrefund') $$,
  'a refund recorded in error can be corrected away');

select is((select amount from credit_one), '40000',
  'and a refund that was taken back gave nothing back, so the money is the client''s again');

select throws_ok(
  $$ select public.reverse_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from refund_one),
    null, 'ref-idem-unrefund-2', 'ref-hash-unrefund-2') $$,
  '23514', null, 'the same entry cannot be corrected away twice');

select throws_ok(
  $$ select public.reverse_client_payment(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.client_payment_events where event_type = 'reversed'),
    null, 'ref-idem-unrefund-3', 'ref-hash-unrefund-3') $$,
  '23514', null, 'and a correction cannot itself be corrected away');

select public.apply_client_payment(
  'e2000000-0000-0000-0000-000000000001', (select id from bill where subject = 'Roof'),
  (select id from receipt_one), null, 40000, null, 'ref-idem-apply-roof', 'ref-hash-apply-roof');

select is((select amount from credit_one), '0', 'money put on a bill is committed, not available');

select throws_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one), null,
    1, 'cash', null, null, null, 'ref-idem-refund-applied', 'ref-hash-refund-applied') $$,
  '23514', null, 'money sitting on a bill cannot be refunded until it is taken off');

select throws_ok(
  $$ select public.reverse_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one),
    null, 'ref-idem-unrecv-applied', 'ref-hash-unrecv-applied') $$,
  '23514', null, 'and a receipt with money on a bill cannot be called never received');

select public.unapply_client_payment(
  'e2000000-0000-0000-0000-000000000001',
  (select id from public.invoice_payment_allocations
    where invoice_id = (select id from bill where subject = 'Roof') and entry_type = 'applied'),
  'Wrong bill', 'ref-idem-unapply-roof', 'ref-hash-unapply-roof');

select is((select amount from credit_one), '40000', 'taking it back off returns it to credit');

select lives_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one), null,
    40000, 'bank_transfer', null, null, null, 'ref-idem-refund-all', 'ref-hash-refund-all') $$,
  'once it is off the bill the whole receipt can be sent back');
select is((select amount from credit_one), '0', 'and the client has nothing left on account');

select throws_ok(
  $$ select public.reverse_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from receipt_one),
    null, 'ref-idem-unrecv-refunded', 'ref-hash-unrecv-refunded') $$,
  '23514', null, 'a receipt that has been refunded cannot also be called never received');

select public.record_client_payment(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001',
  5000, 'check', '2026-09-13'::date, 'Cheque 12', null, null, 'ref-idem-recv-2', 'ref-hash-recv-2');
select is((select amount from credit_one), '5000', 'a second receipt arrives');

select lives_ok(
  $$ select public.reverse_client_payment(
    'e2000000-0000-0000-0000-000000000001',
    (select id from public.client_payment_events where amount_minor = 5000 and event_type = 'received'),
    'Cheque bounced', 'ref-idem-unrecv-2', 'ref-hash-unrecv-2') $$,
  'an untouched receipt can be marked as never received');
select is((select amount from credit_one), '0', 'and money that never arrived is not credit');

select is(
  (select count(*)::int from public.client_payment_events
    where organization_id = 'e2000000-0000-0000-0000-000000000001'),
  6, 'every correction added a row and none of them removed one');

-- 5. Voiding a bill --------------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Shed'), 'created_in_error', null,
    'ref-idem-void-draft', 'ref-hash-void-draft') $$,
  '23514', null, 'a draft is deleted rather than voided');

select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Patio'), 'because', null,
    'ref-idem-void-reason', 'ref-hash-void-reason') $$,
  '23514', null, 'a void needs one of the four approved reasons');

select public.record_client_payment(
  'e2000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002',
  20000, 'cash', '2026-09-11'::date, null, null,
  jsonb_build_array(jsonb_build_object(
    'invoice_id', (select id from bill where subject = 'Patio'), 'amount_minor', 20000)),
  'ref-idem-recv-3', 'ref-hash-recv-3');

select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Patio'), 'client_request', null,
    'ref-idem-void-paid', 'ref-hash-void-paid') $$,
  '23514', null, 'decision D2: a bill with payments on it refuses to be voided');

select public.unapply_client_payment(
  'e2000000-0000-0000-0000-000000000001',
  (select id from public.invoice_payment_allocations
    where invoice_id = (select id from bill where subject = 'Patio') and entry_type = 'applied'),
  'Returning to credit before voiding', 'ref-idem-unapply-patio', 'ref-hash-unapply-patio');

select is(
  (public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Patio'), 'client_request', 'Client cancelled the job',
    'ref-idem-void-patio', 'ref-hash-void-patio'))->>'released_deposit_minor',
  '0', 'once the payment is resolved the bill voids, with no deposits to release');

select isnt((select voided_at from bill where subject = 'Patio'), null, 'the bill is voided');
select is((select void_reason from bill where subject = 'Patio'), 'client_request',
  'and it keeps the reason forever');
select is((select is_effective_receivable from bill where subject = 'Patio'), false,
  'a voided bill is not money the client owes');
select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from bill where subject = 'Patio') and event_type = 'invoice.voided'),
  1, 'the void wrote one history row');

select is(
  (public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Patio'), 'client_request', 'Client cancelled the job',
    'ref-idem-void-patio', 'ref-hash-void-patio'))->>'applied',
  'false', 'a retried void reports that it changed nothing');

select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Patio'), 'duplicate', null,
    'ref-idem-void-again', 'ref-hash-void-again') $$,
  '23514', null, 'and a voided bill cannot be voided a second time');

select throws_ok(
  $$ select public.apply_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from bill where subject = 'Patio'),
    (select id from public.client_payment_events where amount_minor = 20000), null, 1000, null,
    'ref-idem-apply-void', 'ref-hash-apply-void') $$,
  '23514', null, 'a voided bill can neither take money nor give it up');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where subject = 'Deck'), 'duplicate', null,
    'ref-idem-void-field', 'ref-hash-void-field') $$,
  '42501', null, 'a field member cannot void a bill');
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where subject = 'Deck'), 'duplicate', null,
    'ref-idem-void-other-org', 'ref-hash-void-other-org') $$,
  '42501', null, 'and another organization''s owner cannot reach these bills at all');
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

-- 6. The deposit release, which is the one thing a void resolves for you -----------------------------------------

set local role postgres;

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('e5000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 1, 'Gate quote', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name)
values ('e6000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
  'e5000000-0000-0000-0000-000000000001', 1, 'USD', 'Refund Client One', 'Refund Org A');

insert into public.quote_deposit_events (
  id, organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key)
values
  ('e7000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
   'received', 25000, 'cash', 'ref-deposit-key-1'),
  ('e7000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001',
   'e5000000-0000-0000-0000-000000000001', 'e6000000-0000-0000-0000-000000000001',
   'received', 10000, 'cash', 'ref-deposit-key-2');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

select is((select amount from credit_one), '35000', 'two quote deposits are the client''s money too');

select public.apply_client_payment(
  'e2000000-0000-0000-0000-000000000001', (select id from bill where subject = 'Gate'),
  null, 'e7000000-0000-0000-0000-000000000001', 25000, null,
  'ref-idem-apply-gate', 'ref-hash-apply-gate');
select is((select amount from credit_one), '10000', 'one of them is committed to the gate bill');

select is(
  (public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Gate'), 'created_in_error', null,
    'ref-idem-void-gate', 'ref-hash-void-gate'))->>'released_deposit_minor',
  '25000', 'voiding the bill releases the deposit that was on it');

select is((select amount from credit_one), '35000',
  'and the released deposit is the client''s to spend again');

select is(
  (select count(*)::int from public.invoice_payment_allocations
    where invoice_id = (select id from bill where subject = 'Gate') and entry_type = 'unapplied'),
  1, 'the release is a retained entry, exactly like an explicit unapply');

-- A deposit is refunded where it lives, and only while it still has something left, exactly like a receipt.
select lives_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', null, 'e7000000-0000-0000-0000-000000000001',
    5000, 'cash', null, null, 'Partial deposit returned',
    'ref-idem-refund-deposit', 'ref-hash-refund-deposit') $$,
  'a quote deposit is refunded where it lives, without being copied into a second receipt');

select is(
  (select original_deposit_event_id from public.client_payment_events
    where event_type = 'refunded' and original_deposit_event_id is not null),
  'e7000000-0000-0000-0000-000000000001'::uuid,
  'and that refund points at the deposit itself');

select is((select amount from credit_one), '30000', 'the part sent back is gone from the client''s credit');

select lives_ok(
  $$ select public.apply_client_payment(
    'e2000000-0000-0000-0000-000000000001', (select id from public.invoices where subject = 'Roof'),
    null, 'e7000000-0000-0000-0000-000000000001', 20000, null,
    'ref-idem-apply-roof-2', 'ref-hash-apply-roof-2') $$,
  'and what is left of the released deposit can be put on another bill');

select throws_ok(
  $$ select public.refund_client_payment(
    'e2000000-0000-0000-0000-000000000001', null, 'e7000000-0000-0000-0000-000000000001',
    1, 'cash', null, null, null, 'ref-idem-refund-deposit-2', 'ref-hash-refund-deposit-2') $$,
  '23514', null, 'once the rest of it is on a bill there is nothing left of the deposit to refund');

select public.apply_client_payment(
  'e2000000-0000-0000-0000-000000000001', (select id from bill where subject = 'Mailbox'),
  null, 'e7000000-0000-0000-0000-000000000002', 10000, null,
  'ref-idem-apply-mailbox', 'ref-hash-apply-mailbox');

select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where subject = 'Mailbox'), 'duplicate', null,
    'ref-idem-void-mailbox', 'ref-hash-void-mailbox') $$,
  '23514', null, 'a bill that is fully paid is not an unpaid bill to cancel');

-- 7. Bad debt ---------------------------------------------------------------------------------------------------

select is((select amount from owed_two), '110000',
  'the second client owes the deck and the path, the voided patio having dropped out');

select is(
  (public.write_off_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), 'Client went out of business',
    'ref-idem-writeoff', 'ref-hash-writeoff'))->>'written_off_minor',
  '80000', 'the whole remaining balance is what gets written off');

select is((select is_effective_receivable from bill where subject = 'Deck'), false,
  'a written-off bill stops counting as money owed');
select is((select amount from owed_two), '30000', 'so the client owes only the path');
select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from bill where subject = 'Deck')
      and event_type = 'invoice.written_off'),
  1, 'the write-off wrote one history row');

select throws_ok(
  $$ select public.write_off_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), null, 'ref-idem-writeoff-2', 'ref-hash-writeoff-2') $$,
  '23514', null, 'a balance cannot be written off twice');
select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), 'duplicate', null,
    'ref-idem-void-writeoff', 'ref-hash-void-writeoff') $$,
  '23514', null, 'and a written-off bill has to be restored before it can be voided');
select throws_ok(
  $$ select public.mark_invoice_received('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), null,
    'ref-idem-mark-writeoff', 'ref-hash-mark-writeoff') $$,
  '23514', null, 'a bill cannot say both that it was written off and that it was received');
select throws_ok(
  $$ select public.write_off_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Shed'), null,
    'ref-idem-writeoff-draft', 'ref-hash-writeoff-draft') $$,
  '23514', null, 'only a bill the client has actually been given can be written off');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.write_off_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from public.invoices where subject = 'Path'), null,
    'ref-idem-writeoff-field', 'ref-hash-writeoff-field') $$,
  '42501', null, 'a field member cannot write off a debt');
select set_config('request.jwt.claim.sub', 'e1000000-0000-0000-0000-000000000001', true);

select is(
  (public.restore_invoice_from_write_off('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), 'They paid something after all',
    'ref-idem-restore', 'ref-hash-restore'))->>'restored_minor',
  '80000', 'undoing the write-off puts the balance back');
select is((select is_effective_receivable from bill where subject = 'Deck'), true,
  'and the bill counts as owed again');
select is((select amount from owed_two), '110000', 'so the client owes both bills once more');
select is((select written_off_at from bill where subject = 'Deck'), null,
  'the write-off stamp is gone');

select throws_ok(
  $$ select public.restore_invoice_from_write_off('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), null, 'ref-idem-restore-2', 'ref-hash-restore-2') $$,
  '23514', null, 'there is nothing to restore on a bill that was never written off');

select is(
  (public.write_off_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Deck'), 'Client went out of business',
    'ref-idem-writeoff', 'ref-hash-writeoff'))->>'applied',
  'false', 'and the original write-off key still returns its first result rather than writing off again');
select is((select is_effective_receivable from bill where subject = 'Deck'), true,
  'which means the retry left the restored bill alone');

-- 8. Closing a bill without recording money ----------------------------------------------------------------------

select is(
  (public.mark_invoice_received('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Path'), 'Client says it was settled in cash long ago',
    'ref-idem-mark', 'ref-hash-mark'))->>'unsettled_minor',
  '30000', 'closing a bill by hand records how much it never actually collected');

select isnt((select marked_received_at from bill where subject = 'Path'), null, 'the bill is closed');
select is((select is_effective_receivable from bill where subject = 'Path'), true,
  'but a status-only closure extinguishes no debt at all');
select is((select amount from owed_two), '110000', 'so the client still owes exactly what they owed');
select is(
  (select count(*)::int from public.invoice_events
    where invoice_id = (select id from bill where subject = 'Path')
      and event_type = 'invoice.marked_received'),
  1, 'the closure wrote one history row');

select throws_ok(
  $$ select public.mark_invoice_received('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Path'), null, 'ref-idem-mark-2', 'ref-hash-mark-2') $$,
  '23514', null, 'a bill cannot be closed by hand twice');
select throws_ok(
  $$ select public.write_off_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Path'), null,
    'ref-idem-writeoff-marked', 'ref-hash-writeoff-marked') $$,
  '23514', null, 'and a closed bill has to be reopened before it can be written off');
select throws_ok(
  $$ select public.void_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Path'), 'duplicate', null,
    'ref-idem-void-marked', 'ref-hash-void-marked') $$,
  '23514', null, 'or before it can be voided');

select lives_ok(
  $$ select public.reopen_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Path'), 'Closed by mistake',
    'ref-idem-reopen', 'ref-hash-reopen') $$,
  'the closure can be undone');
select is((select marked_received_at from bill where subject = 'Path'), null,
  'and the bill is open again');
select throws_ok(
  $$ select public.reopen_invoice('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Path'), null, 'ref-idem-reopen-2', 'ref-hash-reopen-2') $$,
  '23514', null, 'a bill that was not closed by hand has nothing to reopen');

select throws_ok(
  $$ select public.mark_invoice_received('e2000000-0000-0000-0000-000000000001',
    (select id from bill where subject = 'Mailbox'), null,
    'ref-idem-mark-paid', 'ref-hash-mark-paid') $$,
  '23514', null, 'a bill that is already paid in full has nothing to close');

select * from finish();
rollback;
