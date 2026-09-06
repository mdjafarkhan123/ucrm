-- Invoices Part 5c-4: what a progress bill says on screen and on the customer's copy, and what happens when
-- one turns out to be wrong. Written for `supabase test db`; verified against the remote dev project by
-- running this whole file as one transaction that is rolled back at the end, the same convention the 5c-1,
-- 5c-2 and 5c-3 files document. Do not run it through a runner that executes each statement separately:
-- `set local role` and `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- 1. Fixtures ---------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c6000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c4-owner@example.test', 'test', now(), now(), now()),
  ('c6000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c4-nomoney@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c6100000-0000-0000-0000-000000000001', 'Stage 5c4 Org', 'stage-5c4-org', 'active');

-- record_client_payment and activate_invoice_replacement both read settings before touching an invoice.
-- A new organization already gets a settings row from its own trigger, so this only pins the currency.
update public.organization_settings set timezone = 'UTC', locale = 'en-US', currency_code = 'USD'
where organization_id = 'c6100000-0000-0000-0000-000000000001';

insert into public.organization_members (organization_id, user_id, role)
values
  ('c6100000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001', 'owner'),
  ('c6100000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000002', 'admin');

-- The price-withheld reader: an admin, who sees invoices by default, denied the one permission that decides
-- whether amounts leave the database at all. (An organization allows only one owner, hence admin here.)
insert into public.organization_member_permission_overrides (
  organization_id, user_id, permission_key, override_state
) values (
  'c6100000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000002',
  'invoices.view_price', 'deny'
);

insert into public.clients (id, organization_id, display_name)
values ('c6200000-0000-0000-0000-000000000001', 'c6100000-0000-0000-0000-000000000001', 'Stage 5c4 Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('c6300000-0000-0000-0000-000000000001', 'c6100000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001', '5c4 Way', 'Testville');

-- Two priced lines totalling 100000, split unevenly so the deposit stage's allocation is a real split.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
) values
  ('c6400000-0000-0000-0000-000000000001', 'c6100000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001', 'c6300000-0000-0000-0000-000000000001', 9401, 'Stage 5c4 job', 'one_off', 'job_total', 'USD');

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor, unit_cost_minor, is_taxable
) values
  ('c6500000-0000-0000-0000-000000000001', 'c6100000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Labor', 1, 66667, 0, false),
  ('c6500000-0000-0000-0000-000000000002', 'c6100000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001', 1, 'priced', 'product', 'Materials', 1, 33333, 0, false);

do $$ begin perform private.store_job_money('c6400000-0000-0000-0000-000000000001'); end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c6000000-0000-0000-0000-000000000001', true);

select public.set_job_payment_schedule(
  'c6100000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001', 0,
  '[{"description": "Deposit", "type": "fixed", "value": 40000},
    {"description": "Final payment", "type": "fixed", "value": 60000}]'::jsonb
);

set local role postgres;

create temporary view stage as
  select item.id, item.job_id, item.position, item.description, item.locked_amount_minor
  from public.job_payment_schedule_items as item
  where item.organization_id = 'c6100000-0000-0000-0000-000000000001';
grant select on stage to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c6000000-0000-0000-0000-000000000001', true);

-- The bill under test, and an ordinary bill beside it as the control.
select public.create_installment_invoice(
  'c6100000-0000-0000-0000-000000000001', 'c6400000-0000-0000-0000-000000000001',
  (select id from stage where position = 0),
  'Deposit invoice', array[]::uuid[], null, null, null,
  'stage5c4-idem-deposit', 'stage5c4-hash-deposit'
);

select public.create_invoice_draft(
  'c6100000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001', 'Ordinary invoice',
  '[{"position": 0, "line_kind": "priced", "category": "service", "name": "Callout", "quantity": 1,
     "unit_price_minor": 5000, "is_taxable": false}]'::jsonb,
  array[]::uuid[], null, null, null, 'stage5c4-idem-plain', 'stage5c4-hash-plain'
);

set local role postgres;

create temporary view bill as
  select
    (select claim.root_invoice_id from public.invoice_sources as claim
     where claim.organization_id = 'c6100000-0000-0000-0000-000000000001'
       and claim.installment_id = (select id from stage where position = 0)) as progress_id,
    (select invoice.id from public.invoices as invoice
     where invoice.organization_id = 'c6100000-0000-0000-0000-000000000001'
       and invoice.subject = 'Ordinary invoice') as plain_id;
grant select on bill to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c6000000-0000-0000-0000-000000000001', true);

-- 2. The staff read model names the stage and shows both amounts ------------------------------------------------

select is(
  (public.invoice_detail('c6100000-0000-0000-0000-000000000001', (select progress_id from bill)) -> 'progress')
    - 'job_id'::text - 'installment_id'::text,
  '{"installment_number": 1, "description": "Deposit", "is_deposit": false}'::jsonb,
  'the staff read names which stage of the schedule this bill is'
);

select is(
  (select jsonb_agg(jsonb_build_object(
     'item_total', line -> 'progress_original_amount_minor', 'due', line -> 'line_total_minor'))
   from jsonb_array_elements(
     public.invoice_detail('c6100000-0000-0000-0000-000000000001', (select progress_id from bill)) -> 'lines'
   ) as line),
  '[{"item_total": 66667, "due": 26667}, {"item_total": 33333, "due": 13333}]'::jsonb,
  'and carries the whole item beside the share this bill charges, for every line'
);

select is(
  public.invoice_detail('c6100000-0000-0000-0000-000000000001', (select plain_id from bill)) -> 'progress',
  'null'::jsonb,
  'an ordinary bill has no stage, which is how the screen knows to draw nothing'
);

-- 3. A price-withheld reader gets the stage and no amounts ------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c6000000-0000-0000-0000-000000000002', true);

select is(
  public.invoice_detail('c6100000-0000-0000-0000-000000000001', (select progress_id from bill)) -> 'money',
  'null'::jsonb,
  'a reader without invoices.view_price still gets no money on a progress bill'
);

select is(
  (select bool_and(line -> 'progress_original_amount_minor' = 'null'::jsonb)
   from jsonb_array_elements(
     public.invoice_detail('c6100000-0000-0000-0000-000000000001', (select progress_id from bill)) -> 'lines'
   ) as line),
  true, 'and the progress figure is withheld with it, rather than sent and then not drawn'
);

select is(
  public.invoice_detail('c6100000-0000-0000-0000-000000000001', (select progress_id from bill))
    -> 'progress' -> 'description',
  '"Deposit"'::jsonb,
  'while which stage it is stays visible -- that is a fact of the bill, not an amount'
);

select set_config('request.jwt.claim.sub', 'c6000000-0000-0000-0000-000000000001', true);

-- 4. The customer's copy ----------------------------------------------------------------------------------------

select is(
  public.invoice_customer_preview((select progress_id from bill)) -> 'document' -> 'progress',
  '{"installment_number": 1, "description": "Deposit", "is_deposit": false}'::jsonb,
  'the customer document identifies the stage and says nothing about the stages after it'
);

select is(
  (select jsonb_agg(line -> 'progress_original_amount_minor')
   from jsonb_array_elements(
     public.invoice_customer_preview((select progress_id from bill)) -> 'document' -> 'lines'
   ) as line),
  '[66667, 33333]'::jsonb,
  'and shows Item total beside Due this invoice on every line'
);

-- 5. Once issued, the document does not follow the job -----------------------------------------------------------

select public.issue_invoice(
  'c6100000-0000-0000-0000-000000000001', (select progress_id from bill),
  (select revision from public.invoices where id = (select progress_id from bill)),
  'marked_sent', 'stage5c4-idem-issue', 'stage5c4-hash-issue'
);

set local role postgres;

-- The job is re-priced afterwards. The billed stage is locked, so this leaves the *remaining* stage no longer
-- reconciling -- a real state the schedule reader reports, not an error -- and must not reach the issued bill.
update public.job_line_items set unit_price_minor = 90000
where id = 'c6500000-0000-0000-0000-000000000001';
do $$ begin perform private.store_job_money('c6400000-0000-0000-0000-000000000001'); end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c6000000-0000-0000-0000-000000000001', true);

select is(
  (select jsonb_agg(jsonb_build_object(
     'item_total', line -> 'progress_original_amount_minor', 'due', line -> 'line_total_minor'))
   from jsonb_array_elements(
     public.invoice_customer_preview((select progress_id from bill)) -> 'document' -> 'lines'
   ) as line),
  '[{"item_total": 66667, "due": 26667}, {"item_total": 33333, "due": 13333}]'::jsonb,
  'an issued progress document keeps its own numbers after the job is re-priced'
);

select is(
  public.invoice_customer_preview((select progress_id from bill)) -> 'document' -> 'progress' -> 'description',
  '"Deposit"'::jsonb,
  'and keeps naming the same stage, because a claimed stage cannot be re-described'
);

-- 6. Void refuses; correction is the way out ---------------------------------------------------------------------

select throws_ok(
  $$ select public.void_invoice(
    'c6100000-0000-0000-0000-000000000001',
    (select progress_id from bill),
    'created_in_error', null, 'stage5c4-idem-void', 'stage5c4-hash-void') $$,
  '23514', 'A progress invoice is corrected rather than voided.',
  'voiding one bill of a payment schedule is refused outright'
);

-- A part-payment, so "the correction preserves allocations" is a claim about real money.
select public.record_client_payment(
  'c6100000-0000-0000-0000-000000000001', 'c6200000-0000-0000-0000-000000000001', 10000, 'cash',
  current_date, null, null,
  jsonb_build_array(jsonb_build_object(
    'invoice_id', (select progress_id from bill), 'amount_minor', 10000)),
  'stage5c4-idem-pay', 'stage5c4-hash-pay'
);

select public.prepare_invoice_correction(
  'c6100000-0000-0000-0000-000000000001', (select progress_id from bill),
  (select revision from public.invoices where id = (select progress_id from bill)),
  'stage5c4-idem-correct', 'stage5c4-hash-correct'
);

select is(
  public.invoice_detail(
    'c6100000-0000-0000-0000-000000000001',
    (select id from public.invoices where predecessor_invoice_id = (select progress_id from bill))
  ) -> 'progress' -> 'description',
  '"Deposit"'::jsonb,
  'the replacement belongs to the same stage, because the claim sits on the chain rather than on one bill'
);

select public.activate_invoice_replacement(
  'c6100000-0000-0000-0000-000000000001',
  (select id from public.invoices where predecessor_invoice_id = (select progress_id from bill)),
  (select revision from public.invoices where predecessor_invoice_id = (select progress_id from bill)),
  0, 'marked_sent', 'stage5c4-idem-activate', 'stage5c4-hash-activate'
);

set local role postgres;

select is(
  (select jsonb_build_array(
     (select count(*) from public.invoices
      where organization_id = 'c6100000-0000-0000-0000-000000000001'
        and predecessor_invoice_id = (select progress_id from bill)),
     (select replaced_at is not null from public.invoices where id = (select progress_id from bill)),
     (select coalesce(sum(amount_minor), 0) from public.invoice_payment_allocations
      where invoice_id = (select progress_id from bill) and entry_type = 'applied'))),
  jsonb_build_array(to_jsonb(1::bigint), to_jsonb(true), to_jsonb(10000::bigint)),
  'activation retains the original, leaves exactly one replacement, and moves no money off it'
);

select is(
  (select jsonb_agg(jsonb_build_object('position', position, 'locked', locked_amount_minor)
                    order by position) from stage),
  '[{"position": 0, "locked": 40000}, {"position": 1, "locked": null}]'::jsonb,
  'and the schedule is untouched: the billed stage keeps its amount, the later stage is still unbilled'
);

select * from finish();
rollback;
