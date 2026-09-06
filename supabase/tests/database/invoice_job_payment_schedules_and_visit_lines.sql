-- Invoices Part 5c-1: job-owned payment stages, visit-owned lines, and the money rules that govern them.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(50);

-- throws_ok's three-argument form takes (query, errcode, errmsg) in this pgTAP build, so an error code is
-- checked with the four-argument form and a null message.

-- 1. Shape and privileges -----------------------------------------------------------------------------------

select has_table('public', 'job_payment_schedule_items', 'a one-off job owns its payment stages');
select has_table('public', 'job_visit_line_items', 'a visit owns its own effective lines');
select has_column('public', 'invoice_sources', 'installment_id', 'an invoice claim points at a real stage');
select has_index('public', 'job_payment_schedule_items', 'job_payment_schedule_items_job_idx',
  'the ordered stage read has an index');
select has_index('public', 'job_visit_line_items', 'job_visit_line_items_visit_idx',
  'the ordered visit line read has an index');

select is(
  has_table_privilege('authenticated', 'public.job_payment_schedule_items', 'insert'),
  false, 'members cannot insert a payment stage directly'
);
select is(
  has_table_privilege('authenticated', 'public.job_payment_schedule_items', 'update'),
  false, 'members cannot update a payment stage directly'
);
select is(
  has_table_privilege('authenticated', 'public.job_payment_schedule_items', 'delete'),
  false, 'members cannot delete a payment stage directly'
);
select is(
  has_column_privilege('authenticated', 'public.job_payment_schedule_items', 'value', 'select'),
  false, 'a stage value is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.job_payment_schedule_items', 'locked_amount_minor', 'select'),
  false, 'a billed stage amount is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.job_payment_schedule_items', 'description', 'select'),
  true, 'what the stage is stays readable'
);
select is(
  has_table_privilege('authenticated', 'public.job_visit_line_items', 'insert'),
  false, 'members cannot insert a visit line directly'
);
select is(
  has_column_privilege('authenticated', 'public.job_visit_line_items', 'unit_price_minor', 'select'),
  false, 'a visit line price is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.job_visit_line_items', 'name', 'select'),
  true, 'what the visit covers stays readable'
);
select is(
  has_function_privilege('anon', 'public.job_schedule_money(uuid)', 'execute'),
  false, 'anonymous callers cannot read stage money'
);
select is(
  has_function_privilege('authenticated', 'public.job_schedule_money(uuid)', 'execute'),
  true, 'members reach stage money through the gated reader'
);
select is(
  has_function_privilege('authenticated', 'private.price_job_payment_schedule(uuid, jsonb)', 'execute'),
  false, 'members cannot run schedule arithmetic themselves'
);
select is(
  has_function_privilege('anon', 'public.visit_line_money(uuid)', 'execute'),
  false, 'anonymous callers cannot read visit line money'
);
select is(
  has_function_privilege('authenticated', 'public.visit_line_money(uuid)', 'execute'),
  true, 'members reach visit line money through the gated reader'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c1-admin-a@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c1-field-a@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c1-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c1100000-0000-0000-0000-000000000001', 'Stage 5c1 Org A', 'stage-5c1-org-a', 'active'),
  ('c1100000-0000-0000-0000-000000000002', 'Stage 5c1 Org B', 'stage-5c1-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c1100000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'admin'),
  ('c1100000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'field'),
  ('c1100000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name)
values
  ('c1200000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'Stage 5c1 Client A'),
  ('c1200000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000002', 'Stage 5c1 Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('c1300000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', '5 Stage Way', 'Testville'),
  ('c1300000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000002', 'c1200000-0000-0000-0000-000000000002', '6 Other Way', 'Otherville');

-- Job 1: the round one -- 100000 with no discount and no tax, so a fixed schedule is easy to read.
-- Job 2: 1000, small enough that three equal percentage stages leave a residual cent to place.
-- Job 3: recurring per-visit, which may never carry a schedule but may carry visit lines.
-- Job 4: one-off in the other organization. Job 5: one-off with nothing priced yet.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
)
values
  ('c1400000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001', 9001, 'Stage fixed job', 'one_off', 'job_total', 'USD'),
  ('c1400000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001', 9002, 'Stage percentage job', 'one_off', 'job_total', 'USD'),
  ('c1400000-0000-0000-0000-000000000003', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001', 9003, 'Stage recurring job', 'recurring', 'per_visit', 'USD'),
  ('c1400000-0000-0000-0000-000000000004', 'c1100000-0000-0000-0000-000000000002', 'c1200000-0000-0000-0000-000000000002', 'c1300000-0000-0000-0000-000000000002', 9004, 'Other org job', 'one_off', 'job_total', 'USD'),
  ('c1400000-0000-0000-0000-000000000005', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001', 9005, 'Stage empty job', 'one_off', 'job_total', 'USD');

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
)
values
  ('c1500000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Full renovation', 1, 100000, 40000, false),
  ('c1500000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Small job', 1, 1000, 400, false),
  ('c1500000-0000-0000-0000-000000000003', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000003', 0, 'priced', 'service', 'Monthly visit', 1, 5000, 2000, false);

do $$ begin
  perform private.store_job_money('c1400000-0000-0000-0000-000000000001');
  perform private.store_job_money('c1400000-0000-0000-0000-000000000002');
  perform private.store_job_money('c1400000-0000-0000-0000-000000000003');
end $$;

insert into public.job_visits (id, organization_id, job_id, position, visit_date)
values
  ('c2200000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000003', 0, current_date),
  ('c2200000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000001', 0, current_date);

-- 3. What a schedule is allowed to be --------------------------------------------------------------------------

select is(
  (private.price_job_payment_schedule(
    'c1400000-0000-0000-0000-000000000001',
    '[{"description": "Deposit", "type": "fixed", "value": 60000},
      {"description": "On completion", "type": "fixed", "value": 40000}]'::jsonb
  ) ->> 'total_minor')::bigint,
  100000::bigint, 'a fixed schedule that adds up to the job total prices to exactly that total'
);
select is(
  private.price_job_payment_schedule(
    'c1400000-0000-0000-0000-000000000001',
    '[{"description": "Deposit", "type": "fixed", "value": 60000},
      {"description": "On completion", "type": "fixed", "value": 40000}]'::jsonb
  ) ->> 'mode',
  'fixed', 'the schedule knows it is a fixed one'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000001',
      '[{"description": "Deposit", "type": "fixed", "value": 60000},
        {"description": "On completion", "type": "fixed", "value": 30000}]'::jsonb)$$,
  '23514', null, 'a fixed schedule that misses the job total is refused, not silently rounded'
);

-- 3333 + 3333 + 3334 basis points of 1000 leaves one cent to place, and it lands on the largest remainder.
select is(
  (select jsonb_agg(entry ->> 'amount_minor' order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     private.price_job_payment_schedule(
       'c1400000-0000-0000-0000-000000000002',
       '[{"description": "First", "type": "percentage", "value": 3333},
         {"description": "Second", "type": "percentage", "value": 3333},
         {"description": "Third", "type": "percentage", "value": 3334}]'::jsonb
     ) -> 'items'
   ) as entry),
  '["333", "333", "334"]'::jsonb,
  'the residual cent lands on the largest remainder, not on whoever happens to be last'
);
select is(
  (private.price_job_payment_schedule(
    'c1400000-0000-0000-0000-000000000002',
    '[{"description": "First", "type": "percentage", "value": 3333},
      {"description": "Second", "type": "percentage", "value": 3333},
      {"description": "Third", "type": "percentage", "value": 3334}]'::jsonb
  ) ->> 'total_minor')::bigint,
  1000::bigint, 'a percentage schedule still adds back to the whole job total'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000002',
      '[{"description": "First", "type": "percentage", "value": 4000},
        {"description": "Second", "type": "percentage", "value": 5000}]'::jsonb)$$,
  '23514', null, 'percentage stages that do not add up to 100% are refused'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000001',
      '[{"description": "Deposit", "type": "fixed", "value": 40000},
        {"description": "On completion", "type": "percentage", "value": 6000}]'::jsonb)$$,
  '23514', null, 'a schedule cannot mix a fixed stage with a percentage one'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000001',
      '[{"description": "Everything", "type": "fixed", "value": 100000}]'::jsonb)$$,
  '23514', null, 'one stage is not a schedule'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000001',
      (select jsonb_agg(jsonb_build_object(
         'description', 'Stage ' || generated, 'type', 'fixed', 'value', 1000
       )) from generate_series(1, 13) as generated))$$,
  '23514', null, 'thirteen stages is more than a schedule may hold'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000003',
      '[{"description": "Deposit", "type": "fixed", "value": 2500},
        {"description": "Balance", "type": "fixed", "value": 2500}]'::jsonb)$$,
  '23514', null, 'a recurring job cannot carry a payment schedule at all'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000005',
      '[{"description": "Deposit", "type": "fixed", "value": 1},
        {"description": "Balance", "type": "fixed", "value": 1}]'::jsonb)$$,
  '23514', null, 'a job with nothing priced has no total to divide'
);

-- 4. A stage that has been invoiced stops being a plan ----------------------------------------------------------

insert into public.job_payment_schedule_items (
  id, organization_id, job_id, position, description, value_type, value, is_deposit
)
values
  ('c1600000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000001', 0, 'Deposit', 'fixed', 60000, false),
  ('c1600000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000001', 1, 'On completion', 'fixed', 40000, false);

select is(
  (private.price_job_payment_schedule('c1400000-0000-0000-0000-000000000001') ->> 'total_minor')::bigint,
  100000::bigint, 'the stages a job already has price without being handed back to the function'
);

insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, issue_date, due_date,
  due_date_source, root_invoice_id
)
values (
  'c2000000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001',
  'c1200000-0000-0000-0000-000000000001', 9001, 'Deposit stage', 'USD', current_date,
  current_date + 30, 'custom', 'c2000000-0000-0000-0000-000000000001'
);

update public.job_payment_schedule_items
set locked_amount_minor = 60000
where id = 'c1600000-0000-0000-0000-000000000001';

insert into public.invoice_sources (
  id, organization_id, root_invoice_id, client_id, source_kind, job_id, installment_number, installment_id
)
values (
  'c2100000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'installment',
  'c1400000-0000-0000-0000-000000000001', 1, 'c1600000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$update public.job_payment_schedule_items set value = 70000
    where id = 'c1600000-0000-0000-0000-000000000001'$$,
  '23514', null, 'a stage that already has an invoice cannot be re-priced'
);
select throws_ok(
  $$delete from public.job_payment_schedule_items
    where id = 'c1600000-0000-0000-0000-000000000001'$$,
  '23503', null, 'a stage that already has an invoice cannot be deleted out from under it'
);
select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000001',
      '[{"id": "c1600000-0000-0000-0000-000000000001", "description": "Deposit",
         "type": "fixed", "value": 50000},
        {"id": "c1600000-0000-0000-0000-000000000002", "description": "On completion",
         "type": "fixed", "value": 50000}]'::jsonb)$$,
  '23514', null, 'an edit that changes an already-invoiced stage is refused'
);
select is(
  (private.price_job_payment_schedule(
    'c1400000-0000-0000-0000-000000000001',
    '[{"id": "c1600000-0000-0000-0000-000000000001", "description": "Deposit",
       "type": "fixed", "value": 60000},
      {"id": "c1600000-0000-0000-0000-000000000002", "description": "Second half",
       "type": "fixed", "value": 25000},
      {"description": "Final", "type": "fixed", "value": 15000}]'::jsonb
  ) ->> 'total_minor')::bigint,
  100000::bigint, 'the stages that are still a plan can be split and renamed around a locked one'
);

update public.job_line_items set unit_price_minor = 50000
where id = 'c1500000-0000-0000-0000-000000000001';
do $$ begin perform private.store_job_money('c1400000-0000-0000-0000-000000000001'); end $$;

select throws_ok(
  $$select private.price_job_payment_schedule(
      'c1400000-0000-0000-0000-000000000001',
      '[{"id": "c1600000-0000-0000-0000-000000000001", "description": "Deposit",
         "type": "fixed", "value": 60000},
        {"id": "c1600000-0000-0000-0000-000000000002", "description": "On completion",
         "type": "fixed", "value": 40000}]'::jsonb)$$,
  '23514', null, 'a job total that no longer covers what was already invoiced refuses the whole save'
);

update public.job_line_items set unit_price_minor = 100000
where id = 'c1500000-0000-0000-0000-000000000001';
do $$ begin perform private.store_job_money('c1400000-0000-0000-0000-000000000001'); end $$;

-- 5. Nothing reaches across an organization ---------------------------------------------------------------------

select throws_ok(
  $$insert into public.job_payment_schedule_items (
      organization_id, job_id, position, description, value_type, value
    ) values (
      'c1100000-0000-0000-0000-000000000002', 'c1400000-0000-0000-0000-000000000001', 5,
      'Borrowed job', 'fixed', 1000
    )$$,
  '23503', null, 'a stage cannot borrow a job from another organization'
);
select throws_ok(
  $$insert into public.job_visit_line_items (
      organization_id, job_id, visit_id, position, line_kind, category, name, quantity,
      unit_price_minor, unit_cost_minor
    ) values (
      'c1100000-0000-0000-0000-000000000001', 'c1400000-0000-0000-0000-000000000003',
      'c2200000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Borrowed visit', 1, 100, 50
    )$$,
  '23503', null, 'a visit line cannot attach a visit to a job it does not belong to'
);
select throws_ok(
  $$insert into public.invoice_sources (
      organization_id, root_invoice_id, client_id, source_kind, job_id, installment_number, installment_id
    ) values (
      'c1100000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001',
      'c1200000-0000-0000-0000-000000000002', 'installment', 'c1400000-0000-0000-0000-000000000004',
      1, 'c1600000-0000-0000-0000-000000000002'
    )$$,
  '23503', null, 'an invoice in one organization cannot claim another organization''s stage'
);
select throws_ok(
  $$insert into public.invoice_sources (
      organization_id, root_invoice_id, client_id, source_kind, job_id, installment_number
    ) values (
      'c1100000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
      'c1200000-0000-0000-0000-000000000001', 'installment', 'c1400000-0000-0000-0000-000000000001', 2
    )$$,
  '23514', null, 'an installment claim without a stage reference is refused'
);
select throws_ok(
  $$insert into public.invoice_sources (
      organization_id, root_invoice_id, client_id, source_kind, job_id, installment_id
    ) values (
      'c1100000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
      'c1200000-0000-0000-0000-000000000001', 'job_total', 'c1400000-0000-0000-0000-000000000002',
      'c1600000-0000-0000-0000-000000000002'
    )$$,
  '23514', null, 'a whole-job claim cannot carry a stage reference'
);
select throws_ok(
  $$insert into public.invoice_sources (
      organization_id, root_invoice_id, client_id, source_kind, job_id, installment_number, installment_id
    ) values (
      'c1100000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
      'c1200000-0000-0000-0000-000000000001', 'installment', 'c1400000-0000-0000-0000-000000000001',
      1, 'c1600000-0000-0000-0000-000000000001'
    )$$,
  '23505', null, 'one stage bills once -- a second claim on it is refused'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::integer from public.job_payment_schedule_items
   where job_id = 'c1400000-0000-0000-0000-000000000001'),
  0, 'an admin in the other organization sees none of these stages'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);

select is(
  public.job_schedule_money('c1400000-0000-0000-0000-000000000001'),
  '{}'::jsonb, 'a member without jobs.view_price gets no stage money at all'
);

select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

select is(
  jsonb_array_length(public.job_schedule_money('c1400000-0000-0000-0000-000000000001') -> 'stages'),
  2, 'a member with jobs.view_price reads both stages'
);

-- 6. A converted quote brings its schedule with it ---------------------------------------------------------------

set local role postgres;

insert into public.quotes (
  id, organization_id, client_id, property_id, quote_number, title, status, currency_code
)
values
  ('c1700000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001', 9101, 'Schedule quote', 'draft', 'USD'),
  ('c1700000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1200000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001', 9102, 'Deposit only quote', 'draft', 'USD');

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, status, currency_code,
  client_display_name, organization_name, deposit_type
)
values
  ('c1800000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001', 1, 'draft', 'USD', 'Stage 5c1 Client A', 'Stage 5c1 Org A', 'schedule'),
  ('c1800000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000002', 1, 'draft', 'USD', 'Stage 5c1 Client A', 'Stage 5c1 Org A', 'deposit_only');

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, line_kind, selection_kind, category,
  name, quantity, unit_price_minor, unit_cost_minor, is_taxable
)
values
  ('c1900000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001', 'c1800000-0000-0000-0000-000000000001', 0, 'priced', 'required', 'service', 'Approved work', 1, 10000, 4000, false),
  ('c1900000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000002', 'c1800000-0000-0000-0000-000000000002', 0, 'priced', 'required', 'service', 'Approved work', 1, 10000, 4000, false);

insert into public.quote_version_schedule_items (
  organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
)
values
  ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001', 'c1800000-0000-0000-0000-000000000001', 0, 'Deposit', 'fixed', 4000, true),
  ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001', 'c1800000-0000-0000-0000-000000000001', 1, 'On completion', 'fixed', 6000, false),
  ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000002', 'c1800000-0000-0000-0000-000000000002', 0, 'Deposit', 'fixed', 2000, true);

do $$ begin
  perform private.refresh_quote_draft_totals('c1800000-0000-0000-0000-000000000001');
  perform private.refresh_quote_draft_totals('c1800000-0000-0000-0000-000000000002');
end $$;

update public.quote_versions
set status = 'published', version_number = 1, published_at = now(), document_hash = repeat('c', 64)
where id in ('c1800000-0000-0000-0000-000000000001', 'c1800000-0000-0000-0000-000000000002');

update public.quotes
set status = 'approved', decision = 'approved', decided_at = now(), decision_method = 'offline_verbal',
    sent_at = now(), current_published_version_id = 'c1800000-0000-0000-0000-000000000001'
where id = 'c1700000-0000-0000-0000-000000000001';

update public.quotes
set status = 'approved', decision = 'approved', decided_at = now(), decision_method = 'offline_verbal',
    sent_at = now(), current_published_version_id = 'c1800000-0000-0000-0000-000000000002'
where id = 'c1700000-0000-0000-0000-000000000002';

insert into public.quote_deposit_events (
  organization_id, quote_id, quote_version_id, event_type, amount_minor, method, idempotency_key
)
values
  ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000001', 'c1800000-0000-0000-0000-000000000001', 'received', 4000, 'cash', 'stage5c1-deposit-1'),
  ('c1100000-0000-0000-0000-000000000001', 'c1700000-0000-0000-0000-000000000002', 'c1800000-0000-0000-0000-000000000002', 'received', 2000, 'cash', 'stage5c1-deposit-2');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

select is(
  (public.convert_quote_to_job(
    'c1700000-0000-0000-0000-000000000001', 'stage5c1-convert-key-1', 'stage5c1-hash-1'
  ) ->> 'payment_stage_count')::integer,
  2, 'conversion copies the approved schedule into the job'
);
select is(
  (select count(*)::integer from public.job_payment_schedule_items as stage
   join public.jobs as job on job.id = stage.job_id
   where job.quote_id = 'c1700000-0000-0000-0000-000000000001'),
  2, 'both stages are job-owned rows now'
);
select is(
  (select stage.is_deposit from public.job_payment_schedule_items as stage
   join public.jobs as job on job.id = stage.job_id
   where job.quote_id = 'c1700000-0000-0000-0000-000000000001' and stage.position = 0),
  true, 'the first stage keeps the deposit identity the customer paid against'
);
select is(
  (select jsonb_agg(entry ->> 'amount_minor' order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     public.job_schedule_money(
       (select id from public.jobs where quote_id = 'c1700000-0000-0000-0000-000000000001')
     ) -> 'stages'
   ) as entry),
  '["4000", "6000"]'::jsonb, 'the copied stages price to the approved amounts'
);

select is(
  (public.convert_quote_to_job(
    'c1700000-0000-0000-0000-000000000002', 'stage5c1-convert-key-2', 'stage5c1-hash-2'
  ) ->> 'payment_stage_count')::integer,
  0, 'a required deposit on its own is not a schedule and stays on the quote'
);

select * from finish();
rollback;
