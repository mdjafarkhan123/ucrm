-- Invoices Part 5c-5: a visit's own quantities -- the read, the write, and the bill that follows from them.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- throws_ok's three-argument form takes (query, errcode, errmsg) in this pgTAP build, so an error code is
-- checked with the four-argument form and a null message.

-- 1. Who may call what ----------------------------------------------------------------------------------------

select is(
  has_function_privilege('authenticated', 'public.job_visit_lines(uuid, uuid, uuid[])', 'execute'),
  true, 'members read a visit''s lines through the gated reader'
);
select is(
  has_function_privilege('anon', 'public.job_visit_lines(uuid, uuid, uuid[])', 'execute'),
  false, 'anonymous callers cannot read a visit''s lines'
);
select is(
  has_function_privilege(
    'authenticated', 'private.job_visit_effective_lines(uuid, uuid, uuid)', 'execute'
  ),
  false, 'members cannot ask the raw effective-line helper themselves'
);
select is(
  has_function_privilege(
    'authenticated', 'public.replace_job_visit_line_items(uuid, uuid, uuid, integer, jsonb)', 'execute'
  ),
  true, 'members price a visit through the command'
);
select is(
  has_function_privilege(
    'anon', 'public.replace_job_visit_line_items(uuid, uuid, uuid, integer, jsonb)', 'execute'
  ),
  false, 'anonymous callers cannot price a visit'
);

-- 2. Fixtures -------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('d5000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'visit5c5-admin-a@example.test', 'test', now(), now(), now()),
  ('d5000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'visit5c5-field-a@example.test', 'test', now(), now(), now()),
  ('d5000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'visit5c5-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('d5100000-0000-0000-0000-000000000001', 'Visit 5c5 Org A', 'visit-5c5-org-a', 'active'),
  ('d5100000-0000-0000-0000-000000000002', 'Visit 5c5 Org B', 'visit-5c5-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('d5100000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001', 'admin'),
  ('d5100000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002', 'field'),
  ('d5100000-0000-0000-0000-000000000002', 'd5000000-0000-0000-0000-000000000003', 'admin');

insert into public.clients (id, organization_id, display_name)
values
  ('d5200000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000001', 'Visit 5c5 Client A'),
  ('d5200000-0000-0000-0000-000000000002', 'd5100000-0000-0000-0000-000000000002', 'Visit 5c5 Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('d5300000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000001', 'd5200000-0000-0000-0000-000000000001', '7 Visit Way', 'Testville'),
  ('d5300000-0000-0000-0000-000000000002', 'd5100000-0000-0000-0000-000000000002', 'd5200000-0000-0000-0000-000000000002', '8 Other Way', 'Otherville');

-- Job 1: the lawn round -- recurring, billed per visit, two lines worth 9000 a visit.
-- Job 2: a one-off, which may never price its visits separately.
-- Job 3: the other organization's round, for the isolation checks.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
)
values
  ('d5400000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000001', 'd5200000-0000-0000-0000-000000000001', 'd5300000-0000-0000-0000-000000000001', 9501, 'Lawn round', 'recurring', 'per_visit', 'USD'),
  ('d5400000-0000-0000-0000-000000000002', 'd5100000-0000-0000-0000-000000000001', 'd5200000-0000-0000-0000-000000000001', 'd5300000-0000-0000-0000-000000000001', 9502, 'One-off patio', 'one_off', 'job_total', 'USD'),
  ('d5400000-0000-0000-0000-000000000003', 'd5100000-0000-0000-0000-000000000002', 'd5200000-0000-0000-0000-000000000002', 'd5300000-0000-0000-0000-000000000002', 9503, 'Other org round', 'recurring', 'per_visit', 'USD');

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
)
values
  ('d5500000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Mow the lawn', 1, 5000, 2000, false),
  ('d5500000-0000-0000-0000-000000000002', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', 1, 'priced', 'service', 'Edging', 2, 2000, 800, false),
  ('d5500000-0000-0000-0000-000000000003', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Lay the patio', 1, 80000, 30000, false),
  ('d5500000-0000-0000-0000-000000000004', 'd5100000-0000-0000-0000-000000000002', 'd5400000-0000-0000-0000-000000000003', 0, 'priced', 'service', 'Other mowing', 1, 4000, 1000, false);

do $$ begin
  perform private.store_job_money('d5400000-0000-0000-0000-000000000001');
  perform private.store_job_money('d5400000-0000-0000-0000-000000000002');
  perform private.store_job_money('d5400000-0000-0000-0000-000000000003');
end $$;

-- V1 open, V2 finished, V3 already billed, V4 the one that gets customised and then finished.
insert into public.job_visits (id, organization_id, job_id, position, visit_date, completed_at, completed_by)
values
  ('d5600000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', 0, current_date, null, null),
  ('d5600000-0000-0000-0000-000000000002', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', 1, current_date - 7, now(), 'd5000000-0000-0000-0000-000000000001'),
  ('d5600000-0000-0000-0000-000000000003', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', 2, current_date - 14, null, null),
  ('d5600000-0000-0000-0000-000000000004', 'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', 3, current_date - 21, null, null),
  ('d5600000-0000-0000-0000-000000000005', 'd5100000-0000-0000-0000-000000000002', 'd5400000-0000-0000-0000-000000000003', 0, current_date, null, null);

insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, issue_date, due_date,
  due_date_source, root_invoice_id
)
values (
  'd5700000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000001',
  'd5200000-0000-0000-0000-000000000001', 9501, 'Billed visit', 'USD', current_date,
  current_date + 30, 'custom', 'd5700000-0000-0000-0000-000000000001'
);

insert into public.invoice_sources (
  organization_id, root_invoice_id, client_id, source_kind, job_id, visit_id
)
values (
  'd5100000-0000-0000-0000-000000000001', 'd5700000-0000-0000-0000-000000000001',
  'd5200000-0000-0000-0000-000000000001', 'visit', 'd5400000-0000-0000-0000-000000000001',
  'd5600000-0000-0000-0000-000000000003'
);

-- 3. A visit with no set of its own bills the job's lines --------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd5000000-0000-0000-0000-000000000001', true);

select is(
  jsonb_array_length(
    public.job_visit_lines(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      array['d5600000-0000-0000-0000-000000000001']::uuid[]
    ) -> 'visits' -> 0 -> 'lines'
  ),
  2, 'a visit nobody has customised shows the job''s two lines'
);
select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0) ->> 'subtotal_minor')::bigint,
  9000::bigint, 'and it is worth exactly what one visit of the job is worth'
);
select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0) ->> 'has_override')::boolean,
  false, 'showing the job''s lines is not the same as carrying its own'
);
select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000003']::uuid[]
  ) -> 'visits' -> 0) ->> 'lock_reason'),
  'invoiced', 'a billed visit says why its pricing is closed'
);

-- 4. Customising one visit ---------------------------------------------------------------------------------------

select is(
  (public.replace_job_visit_line_items(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    'd5600000-0000-0000-0000-000000000001',
    (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000001'),
    '[{"position": 0, "source_job_line_item_id": "d5500000-0000-0000-0000-000000000001",
       "line_kind": "priced", "category": "service", "name": "Mow the lawn", "quantity": 3,
       "unit_price_minor": 5000, "unit_cost_minor": 2000, "is_taxable": false},
      {"position": 1, "line_kind": "priced", "category": "service", "name": "Leaf clearing",
       "quantity": 1, "unit_price_minor": 1500, "unit_cost_minor": 500, "is_taxable": false}]'::jsonb
  ) ->> 'line_count')::integer,
  2, 'a visit can keep one of the job''s lines, drop the other and add one of its own'
);
select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0) ->> 'subtotal_minor')::bigint,
  16500::bigint, 'three mows and a leaf clearing is what that visit is now worth'
);
select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0) ->> 'has_override')::boolean,
  true, 'the visit now carries its own set'
);
select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0 -> 'lines' -> 1) ->> 'source_job_line_item_id'),
  null, 'a line only this visit has names no job line'
);

-- Changing the job afterwards must not reach into a visit that was already priced.
set local role postgres;
update public.job_line_items set unit_price_minor = 9999
where id = 'd5500000-0000-0000-0000-000000000001';
do $$ begin perform private.store_job_money('d5400000-0000-0000-0000-000000000001'); end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd5000000-0000-0000-0000-000000000001', true);

select is(
  ((public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0) ->> 'subtotal_minor')::bigint,
  16500::bigint, 'repricing the job does not rewrite a visit that already had its own numbers'
);

set local role postgres;
update public.job_line_items set unit_price_minor = 5000
where id = 'd5500000-0000-0000-0000-000000000001';
do $$ begin perform private.store_job_money('d5400000-0000-0000-0000-000000000001'); end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd5000000-0000-0000-0000-000000000001', true);

-- 5. Going back to the job's lines --------------------------------------------------------------------------------

select is(
  (public.replace_job_visit_line_items(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    'd5600000-0000-0000-0000-000000000001',
    (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000001'),
    '[]'::jsonb
  ) ->> 'has_override')::boolean,
  false, 'an empty list is not "bill nothing", it is "back to the job''s lines"'
);
select is(
  jsonb_array_length(
    public.job_visit_lines(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      array['d5600000-0000-0000-0000-000000000001']::uuid[]
    ) -> 'visits' -> 0 -> 'lines'
  ),
  2, 'and the job''s two lines are what it shows again'
);

-- 6. What the command refuses -------------------------------------------------------------------------------------

select throws_ok(
  $$select public.replace_job_visit_line_items(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      'd5600000-0000-0000-0000-000000000001', 0,
      '[{"position": 0, "line_kind": "priced", "category": "service", "name": "Stale write",
         "quantity": 1, "unit_price_minor": 100, "unit_cost_minor": 0, "is_taxable": false}]'::jsonb)$$,
  'P0409', null, 'an edit against a revision somebody else has moved on from is refused'
);
select throws_ok(
  $$select public.replace_job_visit_line_items(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      'd5600000-0000-0000-0000-000000000002',
      (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000002'),
      '[{"position": 0, "line_kind": "priced", "category": "service", "name": "Too late",
         "quantity": 1, "unit_price_minor": 100, "unit_cost_minor": 0, "is_taxable": false}]'::jsonb)$$,
  'P0410', null, 'a finished visit''s pricing is a record of work done, not a draft'
);
select throws_ok(
  $$select public.replace_job_visit_line_items(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      'd5600000-0000-0000-0000-000000000003',
      (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000003'),
      '[{"position": 0, "line_kind": "priced", "category": "service", "name": "Too late",
         "quantity": 1, "unit_price_minor": 100, "unit_cost_minor": 0, "is_taxable": false}]'::jsonb)$$,
  'P0410', null, 'a visit a customer has already been billed for cannot be repriced'
);
select throws_ok(
  $$select public.replace_job_visit_line_items(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000002',
      'd5600000-0000-0000-0000-000000000001',
      (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000001'),
      '[]'::jsonb)$$,
  '23514', null, 'a one-off job bills as a whole, so its visits are never priced separately'
);
select throws_ok(
  $$select public.replace_job_visit_line_items(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      'd5600000-0000-0000-0000-000000000001',
      (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000001'),
      '[{"position": 0, "source_job_line_item_id": "d5500000-0000-0000-0000-000000000003",
         "line_kind": "priced", "category": "service", "name": "Another job''s line",
         "quantity": 1, "unit_price_minor": 100, "unit_cost_minor": 0, "is_taxable": false}]'::jsonb)$$,
  '23514', null, 'a visit cannot change a line that belongs to a different job'
);

-- 7. Who may price a visit, and who may see what it costs -----------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd5000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.replace_job_visit_line_items(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      'd5600000-0000-0000-0000-000000000001', 0, '[]'::jsonb)$$,
  '42501', null, 'a crew member who may not edit the job may not price its visits'
);
select is(
  (public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0) ->> 'subtotal_minor',
  null, 'a reader without jobs.view_price is told no total at all'
);
select is(
  (public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0 -> 'lines' -> 0) ? 'unit_price_minor',
  false, 'and no line price rides along either'
);
select is(
  (public.job_visit_lines(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    array['d5600000-0000-0000-0000-000000000001']::uuid[]
  ) -> 'visits' -> 0 -> 'lines' -> 0) ->> 'name',
  'Mow the lawn', 'what the work is stays readable without price access'
);

select set_config('request.jwt.claim.sub', 'd5000000-0000-0000-0000-000000000003', true);

select throws_ok(
  $$select public.job_visit_lines(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
      array['d5600000-0000-0000-0000-000000000001']::uuid[])$$,
  '42501', null, 'an admin in another organization cannot read this job''s visits at all'
);

-- 8. Two lines from the same job line ---------------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'd5000000-0000-0000-0000-000000000001', true);

select is(
  (public.replace_job_visit_line_items(
    'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001',
    'd5600000-0000-0000-0000-000000000004',
    (select revision from public.job_visits where id = 'd5600000-0000-0000-0000-000000000004'),
    '[{"position": 0, "source_job_line_item_id": "d5500000-0000-0000-0000-000000000001",
       "line_kind": "priced", "category": "service", "name": "Mow the lawn", "quantity": 3,
       "unit_price_minor": 5000, "unit_cost_minor": 2000, "is_taxable": false},
      {"position": 1, "source_job_line_item_id": "d5500000-0000-0000-0000-000000000001",
       "line_kind": "priced", "category": "service", "name": "Mow the back lawn too", "quantity": 1,
       "unit_price_minor": 5000, "unit_cost_minor": 2000, "is_taxable": false}]'::jsonb
  ) ->> 'line_count')::integer,
  2, 'duplicating one of the job''s lines saves both rows'
);
select is(
  (select count(*)::integer from public.job_visit_line_items
   where visit_id = 'd5600000-0000-0000-0000-000000000004'
     and source_job_line_item_id is not null),
  1, 'and only the first of them keeps the job line''s identity'
);

-- 9. The bill that follows ----------------------------------------------------------------------------------------

set local role postgres;
update public.job_visits
set completed_at = now(), completed_by = 'd5000000-0000-0000-0000-000000000001'
where id = 'd5600000-0000-0000-0000-000000000004';

select is(
  jsonb_array_length(
    private.job_batch_billing_payload(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', current_date
    ) -> 'lines'
  ),
  4, 'the batch bills the finished visits: two job lines for the plain one, two of its own for the other'
);
select is(
  (select count(*)::integer
   from jsonb_array_elements(
     private.job_batch_billing_payload(
       'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', current_date
     ) -> 'lines'
   ) as line
   where (line ->> 'quantity')::numeric = 3),
  1, 'the customised visit is billed for the three mows it actually did'
);
select is(
  jsonb_array_length(
    private.job_batch_billing_payload(
      'd5100000-0000-0000-0000-000000000001', 'd5400000-0000-0000-0000-000000000001', current_date
    ) -> 'sources'
  ),
  2, 'and each finished visit is claimed exactly once'
);

select * from finish();
rollback;
