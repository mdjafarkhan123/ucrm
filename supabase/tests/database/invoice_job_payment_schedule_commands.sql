-- Invoices Part 5c-2: the command that writes a job's payment schedule and the reader the billing card draws.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents. Do not
-- run it through a runner that executes each statement separately: `set local role` and `set_config` do not
-- survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

-- throws_ok's three-argument form takes (query, errcode, errmsg) in this pgTAP build, so an error code is
-- checked with the four-argument form and a null message.

-- 1. Who may call what ---------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.set_job_payment_schedule(uuid, uuid, integer, jsonb)', 'execute'),
  false, 'a signed-out caller cannot write a payment schedule'
);
select is(
  has_function_privilege(
    'authenticated', 'public.set_job_payment_schedule(uuid, uuid, integer, jsonb)', 'execute'
  ),
  true, 'members reach the schedule through the command'
);
select is(
  has_function_privilege('anon', 'public.job_schedule_stages(uuid)', 'execute'),
  false, 'a signed-out caller cannot read a job''s stages'
);
select is(
  has_function_privilege('authenticated', 'public.job_schedule_stages(uuid)', 'execute'),
  true, 'members read the stages through the gated reader'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c2-admin-a@example.test', 'test', now(), now(), now()),
  ('c3000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c2-field-a@example.test', 'test', now(), now(), now()),
  ('c3000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c2-office-a@example.test', 'test', now(), now(), now()),
  ('c3000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stage5c2-admin-b@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('c3100000-0000-0000-0000-000000000001', 'Stage 5c2 Org A', 'stage-5c2-org-a', 'active'),
  ('c3100000-0000-0000-0000-000000000002', 'Stage 5c2 Org B', 'stage-5c2-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c3100000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'admin'),
  ('c3100000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000002', 'field'),
  ('c3100000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000003', 'office'),
  ('c3100000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000004', 'admin');

insert into public.clients (id, organization_id, display_name)
values
  ('c3200000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'Stage 5c2 Client A'),
  ('c3200000-0000-0000-0000-000000000002', 'c3100000-0000-0000-0000-000000000002', 'Stage 5c2 Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('c3300000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'c3200000-0000-0000-0000-000000000001', '7 Stage Way', 'Testville'),
  ('c3300000-0000-0000-0000-000000000002', 'c3100000-0000-0000-0000-000000000002', 'c3200000-0000-0000-0000-000000000002', '8 Other Way', 'Otherville');

-- Job 1: one-off worth 100000, the schedule under test. Job 2: one-off worth 1000, small enough that three
-- equal percentage stages leave a residual cent. Job 3: recurring, which may never carry a schedule.
insert into public.jobs (
  id, organization_id, client_id, property_id, job_number, title, job_type, price_basis, currency_code
)
values
  ('c3400000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'c3200000-0000-0000-0000-000000000001', 'c3300000-0000-0000-0000-000000000001', 9201, 'Command fixed job', 'one_off', 'job_total', 'USD'),
  ('c3400000-0000-0000-0000-000000000002', 'c3100000-0000-0000-0000-000000000001', 'c3200000-0000-0000-0000-000000000001', 'c3300000-0000-0000-0000-000000000001', 9202, 'Command percentage job', 'one_off', 'job_total', 'USD'),
  ('c3400000-0000-0000-0000-000000000003', 'c3100000-0000-0000-0000-000000000001', 'c3200000-0000-0000-0000-000000000001', 'c3300000-0000-0000-0000-000000000001', 9203, 'Command recurring job', 'recurring', 'per_visit', 'USD');

insert into public.job_line_items (
  id, organization_id, job_id, position, line_kind, category, name, quantity, unit_price_minor,
  unit_cost_minor, is_taxable
)
values
  ('c3500000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 0, 'priced', 'service', 'Renovation', 1, 100000, 40000, false),
  ('c3500000-0000-0000-0000-000000000002', 'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000002', 0, 'priced', 'service', 'Small job', 1, 1000, 400, false),
  ('c3500000-0000-0000-0000-000000000003', 'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000003', 0, 'priced', 'service', 'Monthly visit', 1, 5000, 2000, false);

do $$ begin
  perform private.store_job_money('c3400000-0000-0000-0000-000000000001');
  perform private.store_job_money('c3400000-0000-0000-0000-000000000002');
  perform private.store_job_money('c3400000-0000-0000-0000-000000000003');
end $$;

-- 3. Writing a schedule ---------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select is(
  (public.set_job_payment_schedule(
    'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 0,
    '[{"description": "Deposit", "type": "fixed", "value": 60000},
      {"description": "On completion", "type": "fixed", "value": 40000}]'::jsonb
  ) ->> 'revision')::integer,
  1, 'saving a schedule hands back the next revision'
);

set local role postgres;

select is(
  (select jsonb_agg(stage.description order by stage.position)
   from public.job_payment_schedule_items as stage
   where stage.job_id = 'c3400000-0000-0000-0000-000000000001'),
  '["Deposit", "On completion"]'::jsonb, 'both stages are stored in the order they were sent'
);
select is(
  (select count(*)::integer from public.job_events
   where job_id = 'c3400000-0000-0000-0000-000000000001'
     and event_type = 'payment_schedule_updated'),
  1, 'the change is on the job''s own history'
);
select is(
  (select event.metadata ->> 'mode' from public.job_events as event
   where event.job_id = 'c3400000-0000-0000-0000-000000000001'
     and event.event_type = 'payment_schedule_updated'),
  'fixed', 'the history says which kind of schedule it is, and no amounts'
);
select is(
  (select bool_or(stage.is_deposit) from public.job_payment_schedule_items as stage
   where stage.job_id = 'c3400000-0000-0000-0000-000000000001'),
  false, 'a schedule written on the job itself invents no deposit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 0,
      '[{"description": "Deposit", "type": "fixed", "value": 60000},
        {"description": "On completion", "type": "fixed", "value": 40000}]'::jsonb)$$,
  'P0409', null, 'a save against the revision someone else already moved is refused'
);
select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000003', 0,
      '[{"description": "Deposit", "type": "fixed", "value": 2500},
        {"description": "Balance", "type": "fixed", "value": 2500}]'::jsonb)$$,
  '23514', null, 'repeating work cannot be put on a payment schedule'
);
select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      '[{"description": "Deposit", "type": "fixed", "value": 60000},
        {"description": "On completion", "type": "percentage", "value": 4000}]'::jsonb)$$,
  '23514', null, 'a schedule cannot mix a fixed stage with a percentage one'
);
select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      '[{"description": "Deposit", "type": "fixed", "value": 60000},
        {"description": "On completion", "type": "fixed", "value": 30000}]'::jsonb)$$,
  '23514', null, 'stages that miss the job total refuse the whole save'
);
select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      '"not a list"'::jsonb)$$,
  '23514', null, 'a schedule that is not a list is refused before anything is written'
);

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      '[{"description": "Deposit", "type": "fixed", "value": 60000},
        {"description": "On completion", "type": "fixed", "value": 40000}]'::jsonb)$$,
  '42501', null, 'a crew member who cannot edit the job cannot rewrite its billing plan'
);

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000004', true);

select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000002', 'c3400000-0000-0000-0000-000000000001', 1,
      '[{"description": "Deposit", "type": "fixed", "value": 60000},
        {"description": "On completion", "type": "fixed", "value": 40000}]'::jsonb)$$,
  'P0404', null, 'an admin in another organization cannot find this job at all'
);

-- Percentage stages, and the residual cent that has to land somewhere deterministic.
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select is(
  (public.set_job_payment_schedule(
    'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000002', 0,
    '[{"description": "First", "type": "percentage", "value": 3333},
      {"description": "Second", "type": "percentage", "value": 3333},
      {"description": "Third", "type": "percentage", "value": 3334}]'::jsonb
  ) ->> 'mode'),
  'percentage', 'a percentage schedule saves as a percentage schedule'
);
select is(
  (select jsonb_agg(entry ->> 'amount_minor' order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000002') -> 'stages'
   ) as entry),
  '["333", "333", "334"]'::jsonb, 'the residual cent lands on the largest remainder'
);

-- 4. The reader ------------------------------------------------------------------------------------------------

select is(
  public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') ->> 'reconciles',
  'true', 'a schedule that adds up says so'
);
select is(
  (select jsonb_agg(entry ->> 'status' order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry),
  '["remaining", "remaining"]'::jsonb, 'nothing is billed yet, so every stage is still remaining'
);
select is(
  (select jsonb_agg(entry ->> 'amount_minor' order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry),
  '["60000", "40000"]'::jsonb, 'a reader with jobs.view_price sees what each stage is worth'
);

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000002', true);

select is(
  (select jsonb_agg(entry -> 'amount_minor')
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry),
  '[null, null]'::jsonb, 'a crew member sees the plan but none of its money'
);
select is(
  public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'job_total_minor',
  'null'::jsonb, 'and no job total either'
);

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000004', true);

select throws_ok(
  $$select public.job_schedule_stages('c3400000-0000-0000-0000-000000000001')$$,
  '42501', null, 'an admin in another organization cannot read these stages at all'
);

-- 5. A stage with a bill behind it --------------------------------------------------------------------------------

set local role postgres;

insert into public.invoices (
  id, organization_id, client_id, invoice_number, subject, currency_code, issue_date, due_date,
  due_date_source, root_invoice_id, total_minor
)
values (
  'c3600000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001',
  'c3200000-0000-0000-0000-000000000001', 9201, 'Deposit stage', 'USD', current_date,
  current_date + 30, 'custom', 'c3600000-0000-0000-0000-000000000001', 60000
);

update public.job_payment_schedule_items
set locked_amount_minor = 60000
where job_id = 'c3400000-0000-0000-0000-000000000001' and position = 0;

insert into public.invoice_sources (
  organization_id, root_invoice_id, client_id, source_kind, job_id, installment_number, installment_id
)
select
  'c3100000-0000-0000-0000-000000000001', 'c3600000-0000-0000-0000-000000000001',
  'c3200000-0000-0000-0000-000000000001', 'installment', 'c3400000-0000-0000-0000-000000000001',
  1, stage.id
from public.job_payment_schedule_items as stage
where stage.job_id = 'c3400000-0000-0000-0000-000000000001' and stage.position = 0;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select is(
  (select jsonb_agg(jsonb_build_array(entry ->> 'locked', entry ->> 'status')
                    order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry),
  '[["true", "draft"], ["false", "remaining"]]'::jsonb,
  'the billed stage is locked and carries its bill''s live status'
);
select is(
  (select entry -> 'invoice' ->> 'invoice_number'
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry
   where (entry ->> 'position')::integer = 0),
  '9201', 'the card can name and open the invoice the stage produced'
);
select is(
  (select entry -> 'invoice' ->> 'balance_minor'
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry
   where (entry ->> 'position')::integer = 0),
  '60000', 'and what is still owed on it'
);

-- An office member may edit jobs and see their money but holds nothing at all on invoices.
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000003', true);

select is(
  (select jsonb_agg(jsonb_build_array(entry ->> 'status', (entry -> 'invoice')::text)
                    order by (entry ->> 'position')::integer)
   from jsonb_array_elements(
     public.job_schedule_stages('c3400000-0000-0000-0000-000000000001') -> 'stages'
   ) as entry),
  '[["invoiced", "null"], ["remaining", "null"]]'::jsonb,
  'without invoices.view a stage says it has been billed and nothing more'
);

-- 6. What a billed stage does to later edits ---------------------------------------------------------------------

select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      '[]'::jsonb)$$,
  '23514', null, 'a schedule that has already produced a bill cannot be removed'
);
select throws_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      '[{"description": "Everything else", "type": "fixed", "value": 60000},
        {"description": "The rest", "type": "fixed", "value": 40000}]'::jsonb)$$,
  '23514', null, 'and a rewrite that drops the billed stage is refused too'
);

-- The remaining plan can still be split around the locked stage, as long as the whole thing reconciles.
select lives_ok(
  $$select public.set_job_payment_schedule(
      'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1,
      (select jsonb_build_array(
         jsonb_build_object('id', stage.id, 'description', 'Deposit',
                            'type', 'fixed', 'value', 60000),
         jsonb_build_object('description', 'Second half', 'type', 'fixed', 'value', 25000),
         jsonb_build_object('description', 'Final', 'type', 'fixed', 'value', 15000))
       from public.job_payment_schedule_items as stage
       where stage.job_id = 'c3400000-0000-0000-0000-000000000001' and stage.position = 0))$$,
  'the stages that are still a plan can be split around the one that is already billed'
);

set local role postgres;

select is(
  (select jsonb_agg(jsonb_build_array(stage.description, stage.value::text) order by stage.position)
   from public.job_payment_schedule_items as stage
   where stage.job_id = 'c3400000-0000-0000-0000-000000000001'),
  '[["Deposit", "60000"], ["Second half", "25000"], ["Final", "15000"]]'::jsonb,
  'the rewritten plan is stored, in order, beside the untouched billed stage'
);
select is(
  (select stage.locked_amount_minor from public.job_payment_schedule_items as stage
   where stage.job_id = 'c3400000-0000-0000-0000-000000000001' and stage.position = 0),
  60000::bigint, 'the billed stage still says what it was billed at'
);

-- 7. Putting a job back on whole-job billing -----------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

select is(
  (public.set_job_payment_schedule(
    'c3100000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000002', 1, '[]'::jsonb
  ) ->> 'stage_count')::integer,
  0, 'a schedule nothing has billed can be taken off the job'
);
select is(
  jsonb_array_length(
    public.job_schedule_stages('c3400000-0000-0000-0000-000000000002') -> 'stages'
  ),
  0, 'and the job reads as having no schedule at all afterwards'
);

select * from finish();
rollback;
