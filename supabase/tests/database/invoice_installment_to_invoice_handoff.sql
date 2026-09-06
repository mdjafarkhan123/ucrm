-- Invoices Part 5c-3: the atomic command that turns one job payment-schedule stage into a Draft invoice.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention the sibling 5c-1/5c-2 files document. Do
-- not run it through a runner that executes each statement separately: `set local role` and `set_config` do
-- not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- 1. Who may call it -------------------------------------------------------------------------------------------

select is(
  has_function_privilege(
    'anon',
    'public.create_installment_invoice(uuid, uuid, uuid, text, uuid[], uuid, date, date, text, text)',
    'execute'
  ),
  false, 'a signed-out caller cannot hand a stage off to an invoice'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.create_installment_invoice(uuid, uuid, uuid, text, uuid[], uuid, date, date, text, text)',
    'execute'
  ),
  true, 'members reach the handoff through the command'
);

-- 2. Fixtures ---------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c5000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c3-owner-a@example.test', 'test', now(), now(), now()),
  ('c5000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c3-owner-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c5100000-0000-0000-0000-000000000001', 'Stage 5c3 Org A', 'stage-5c3-org-a', 'active'),
  ('c5100000-0000-0000-0000-000000000002', 'Stage 5c3 Org B', 'stage-5c3-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c5100000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', 'owner'),
  ('c5100000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000002', 'owner');

insert into public.clients (id, organization_id, display_name)
values ('c5200000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001', 'Stage 5c3 Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('c5300000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001', 'c5200000-0000-0000-0000-000000000001', '5c3 Way', 'Testville');

-- Job 1: a plain one-off, no quote behind it — its schedule invents no deposit. Two priced lines with an
-- uneven split (66667/33333 of 100000) so billing the 40000 deposit stage exercises the largest-remainder
-- allocation, not just a clean proportional split.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
) values
  ('c5400000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001', 'c5200000-0000-0000-0000-000000000001', 'c5300000-0000-0000-0000-000000000001', 9301, 'Stage 5c3 direct job', 'one_off', 'job_total', 'USD');

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor, unit_cost_minor, is_taxable
) values
  ('c5500000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Labor', 1, 66667, 20000, true),
  ('c5500000-0000-0000-0000-000000000002', 'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001', 1, 'priced', 'product', 'Materials', 1, 33333, 10000, false);

-- Job 2: converted from a Quote that took a partial cash deposit — the handoff must apply what is left of it
-- to the first stage only, capped at the stage amount rather than the full deposit or the full stage.
insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, currency_code)
values ('c5600000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001', 'c5200000-0000-0000-0000-000000000001', 'c5300000-0000-0000-0000-000000000001', 9302, 'Stage 5c3 quote', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, currency_code, client_display_name, organization_name
) values (
  'c5700000-0000-0000-0000-000000000001', 'c5100000-0000-0000-0000-000000000001', 'c5600000-0000-0000-0000-000000000001',
  1, 'USD', 'Stage 5c3 Client', 'Stage 5c3 Org A'
);

insert into public.quote_deposit_events (
  organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key
) values (
  'c5100000-0000-0000-0000-000000000001', 'c5600000-0000-0000-0000-000000000001', 'c5700000-0000-0000-0000-000000000001',
  'received', 15000, 'cash', 'stage5c3-deposit-received'
);

insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code,
  quote_id, quote_version_id
) values (
  'c5400000-0000-0000-0000-000000000002', 'c5100000-0000-0000-0000-000000000001', 'c5200000-0000-0000-0000-000000000001',
  'c5300000-0000-0000-0000-000000000001', 9303, 'Stage 5c3 quoted job', 'one_off', 'job_total', 'USD',
  'c5600000-0000-0000-0000-000000000001', 'c5700000-0000-0000-0000-000000000001'
);

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor, unit_cost_minor, is_taxable
) values
  ('c5500000-0000-0000-0000-000000000003', 'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Quoted work', 1, 50000, 0, false);

do $$ begin
  perform private.store_job_money('c5400000-0000-0000-0000-000000000001');
  perform private.store_job_money('c5400000-0000-0000-0000-000000000002');
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c5000000-0000-0000-0000-000000000001', true);

select public.set_job_payment_schedule(
  'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001', 0,
  '[{"description": "Deposit", "type": "fixed", "value": 40000},
    {"description": "Final", "type": "fixed", "value": 60000}]'::jsonb
);

select public.set_job_payment_schedule(
  'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000002', 0,
  '[{"description": "Deposit", "type": "fixed", "value": 20000},
    {"description": "Final", "type": "fixed", "value": 30000}]'::jsonb
);

-- Created as postgres: `locked_amount_minor` is a money-ish lock state withheld from `authenticated`
-- entirely, so a view exposing it must be defined (and therefore permission-checked) by a role that can
-- already see it, the same reason the sibling 5c-2 file switches role before reading this table at all.
set local role postgres;

create temporary view stage as
  select item.id, item.job_id, item.position, item.description, item.locked_amount_minor
  from public.job_payment_schedule_items as item
  where item.organization_id = 'c5100000-0000-0000-0000-000000000001';
grant select on stage to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c5000000-0000-0000-0000-000000000001', true);

-- 3. Billing the first stage locks its amount and prices its lines --------------------------------------------

select is(
  (public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0),
    'Deposit invoice', array[]::uuid[], null, null, null,
    'stage5c3-idem-deposit', 'stage5c3-hash-deposit'
  ))->>'amount_minor',
  '40000', 'billing the deposit stage prices it at what the schedule says'
);

set local role postgres;

select is(
  (select locked_amount_minor from stage
   where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0),
  40000::bigint, 'the stage''s amount is locked in on the job'
);

select is(
  (select jsonb_agg(jsonb_build_object('price', line.unit_price_minor, 'original', line.progress_original_amount_minor) order by line.position)
   from public.invoice_lines as line
   join public.invoice_sources as claim on claim.root_invoice_id = line.invoice_id
   where claim.organization_id = 'c5100000-0000-0000-0000-000000000001'
     and claim.installment_id = (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0)),
  '[{"price": 26667, "original": 66667}, {"price": 13333, "original": 33333}]'::jsonb,
  'the stage splits proportionally across the job lines, largest remainder taking the odd cent, each line keeping its full job amount beside what this bill actually charges'
);

-- Opening the stage's claim reaches a real invoice, the same join the Billing card's own reader uses.
select is(
  (select invoice.invoice_number from public.invoices as invoice
   join public.invoice_sources as claim on claim.root_invoice_id = invoice.id
   where claim.organization_id = 'c5100000-0000-0000-0000-000000000001'
     and claim.installment_id = (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0))
  is not null,
  true, 'opening the stage''s claim reaches a real invoice with its own number'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c5000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$ select public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 1),
    'Cross-tenant attempt', array[]::uuid[], null, null, null,
    'stage5c3-idem-cross', 'stage5c3-hash-cross') $$,
  '42501', null, 'a member of another organization cannot bill a stage that is not theirs'
);

select set_config('request.jwt.claim.sub', 'c5000000-0000-0000-0000-000000000001', true);

-- 4. One stage, one bill, ever --------------------------------------------------------------------------------

select throws_ok(
  $$ select public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0),
    'A second try', array[]::uuid[], null, null, null,
    'stage5c3-idem-deposit-again', 'stage5c3-hash-deposit-again') $$,
  '23505', null, 'a second, differently-keyed attempt on an already-billed stage is refused, not raced'
);

select is(
  (public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0),
    'Deposit invoice', array[]::uuid[], null, null, null,
    'stage5c3-idem-deposit', 'stage5c3-hash-deposit'
  ))->>'applied',
  'false', 'while a retry carrying the same key gets the first invoice back, not a repeat'
);

select is(
  (select count(*)::integer from public.invoice_sources
   where organization_id = 'c5100000-0000-0000-0000-000000000001'
     and installment_id = (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0)),
  1, 'exactly one claim exists on that stage after both attempts'
);

-- 5. Deleting the draft does not reopen the stage --------------------------------------------------------------

select public.delete_invoice_draft(
  'c5100000-0000-0000-0000-000000000001',
  (select claim.root_invoice_id from public.invoice_sources as claim
   where claim.organization_id = 'c5100000-0000-0000-0000-000000000001'
     and claim.installment_id = (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0)),
  (select invoice.revision from public.invoices as invoice
   join public.invoice_sources as claim on claim.root_invoice_id = invoice.id
   where claim.organization_id = 'c5100000-0000-0000-0000-000000000001'
     and claim.installment_id = (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0)),
  'stage5c3-idem-delete', 'stage5c3-hash-delete'
);

select throws_ok(
  $$ select public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 0),
    'After deletion', array[]::uuid[], null, null, null,
    'stage5c3-idem-after-delete', 'stage5c3-hash-after-delete') $$,
  '23505', null, 'and once a stage''s amount is locked, deleting its draft cannot make it billable again'
);

-- And the Billing card's own reader says so, rather than drawing a still-to-bill stage with a button that
-- could only fail: `locked` is the write command's test (`locked_amount_minor is not null`), so it outlives
-- the bill, while `status` stays 'remaining' because no live bill is left to have a status.
select is(
  (select jsonb_build_array(entry -> 'locked', entry -> 'status')
   from jsonb_array_elements(
     public.job_schedule_stages('c5400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry
   where (entry ->> 'position')::integer = 0),
  jsonb_build_array(to_jsonb(true), to_jsonb('remaining'::text)),
  'a stage whose draft was deleted still reads locked, so the card offers no second Create invoice'
);

-- 6. A stage with no Quote behind it applies no deposit ----------------------------------------------------------

select is(
  (public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000001' and position = 1),
    'Final invoice', array[]::uuid[], null, null, null,
    'stage5c3-idem-final', 'stage5c3-hash-final'
  ))->>'deposit_applied_minor',
  '0', 'a job authored without a Quote has no deposit for its final stage either'
);

-- 7. A live Quote deposit is applied to the first stage, capped at what is left of it -----------------------------

select is(
  (public.create_installment_invoice(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000002',
    (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000002' and position = 0),
    'Quoted deposit invoice', array[]::uuid[], null, null, null,
    'stage5c3-idem-quoted-deposit', 'stage5c3-hash-quoted-deposit'
  ))->>'deposit_applied_minor',
  '15000', 'the first stage gets what is left of the quote''s deposit, not the full stage amount'
);

set local role postgres;

select is(
  (select allocation.amount_minor from public.invoice_payment_allocations as allocation
   join public.invoice_sources as claim on claim.root_invoice_id = allocation.invoice_id
   where claim.organization_id = 'c5100000-0000-0000-0000-000000000001'
     and claim.installment_id = (select id from stage where job_id = 'c5400000-0000-0000-0000-000000000002' and position = 0)
     and allocation.entry_type = 'applied'),
  15000::bigint, 'and it lands as one applied allocation, not a second receipt'
);

-- 8. A scheduled job stops offering whole-job billing ------------------------------------------------------------

select is(
  (select unit_count from private.job_uninvoiced_work(
    'c5100000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-000000000001', 'job_total', 100000, 100000,
    current_date
  )),
  0, 'a one-off job with any payment schedule never offers itself as one whole-job bill again'
);

select * from finish();
rollback;
