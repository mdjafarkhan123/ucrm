-- Jobs, Part 11a: pricing a job after it exists — scope lines, price basis, invoicing timing, discount, tax.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as one
-- transaction that is rolled back at the end, the same convention jobs_update_details_command.sql documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and `set_config`
-- do not survive that.
--
-- Every expected_revision below is read back inline rather than counted by hand, so adding a case in the
-- middle cannot silently break the ones after it. The one exception is the stale-revision guard, which sends
-- a number that is deliberately wrong.
begin;

create extension if not exists pgtap with schema extensions;

select plan(46);

-- 1. Privileges --------------------------------------------------------------------------------------------

select is(has_function_privilege('anon', 'public.replace_job_line_items(uuid, uuid, integer, jsonb)', 'execute'),
  false, 'signed-out callers cannot rewrite a job scope');
select is(has_function_privilege('authenticated', 'public.replace_job_line_items(uuid, uuid, integer, jsonb)', 'execute'),
  true, 'members reach the scope command');
select is(has_function_privilege('anon', 'public.set_job_billing(uuid, uuid, integer, text, text)', 'execute'),
  false, 'signed-out callers cannot change how a job is billed');
select is(has_function_privilege('authenticated', 'public.set_job_billing(uuid, uuid, integer, text, text)', 'execute'),
  true, 'members reach the billing command');
select is(has_function_privilege('anon', 'public.set_job_discount(uuid, uuid, integer, text, text, bigint)', 'execute'),
  false, 'signed-out callers cannot discount a job');
select is(has_function_privilege('authenticated', 'public.set_job_discount(uuid, uuid, integer, text, text, bigint)', 'execute'),
  true, 'members reach the discount command');
select is(has_function_privilege('anon', 'public.set_job_tax(uuid, uuid, integer, text, uuid, text, integer, boolean)', 'execute'),
  false, 'signed-out callers cannot tax a job');
select is(has_function_privilege('authenticated', 'public.set_job_tax(uuid, uuid, integer, text, uuid, text, integer, boolean)', 'execute'),
  true, 'members reach the tax command');

-- The shared lock helper is an implementation detail of those four, not a fifth endpoint.
select is(has_function_privilege('authenticated', 'private.lock_job_for_edit(uuid, uuid, integer)', 'execute'),
  false, 'the shared lock helper is not callable by members directly');
select is(has_function_privilege('anon', 'private.lock_job_for_edit(uuid, uuid, integer)', 'execute'),
  false, 'the shared lock helper is not callable signed out');

-- 2. Fixtures ----------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-price-office@example.test', 'test', now(), now(), now()),
  ('c1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'job-price-field@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c2000000-0000-0000-0000-000000000001', 'Price Org A', 'price-org-a', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'office'),
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'field');

insert into public.clients (id, organization_id, display_name)
values ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'Price Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city, state_region, postal_code)
values ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', '1 Price Way', 'Testville', 'TX', '78741');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- One one-off job and one recurring job, both built by the real creation command so each starts at revision 0
-- with the price basis its type allows.
select public.create_job_with_visits(
  'c2000000-0000-0000-0000-000000000001',
  'c3000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000001',
  'Priced one-off job', null, true, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null)),
  'idem-price-0001', 'hash-price-0001'
);

select public.create_job_with_visits(
  'c2000000-0000-0000-0000-000000000001',
  'c3000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000001',
  'Priced recurring job', null, true, '[]'::jsonb,
  '[]'::jsonb,
  'idem-price-0002', 'hash-price-0002',
  'recurring', false,
  '{"frequency":"weekly","interval_count":1,"weekdays":[1],"start_date":"2026-09-07","end_mode":"after","duration_count":2,"duration_unit":"month"}'::jsonb
);

create temporary view target_job as
  select id, revision from public.jobs
  where organization_id = 'c2000000-0000-0000-0000-000000000001' and job_type = 'one_off';
create temporary view repeat_job as
  select id, revision from public.jobs
  where organization_id = 'c2000000-0000-0000-0000-000000000001' and job_type = 'recurring';

-- 3. Replacing the scope ------------------------------------------------------------------------------------

select is(
  (public.replace_job_line_items(
    'c2000000-0000-0000-0000-000000000001',
    (select id from target_job),
    (select revision from target_job),
    jsonb_build_array(
      jsonb_build_object('position', 1, 'name', 'Gutter clearing', 'category', 'service',
        'quantity', 2, 'unit_price_minor', 5000, 'unit_cost_minor', 1000, 'is_taxable', true),
      jsonb_build_object('position', 0, 'name', 'Downpipe bracket', 'category', 'product',
        'quantity', 1, 'unit_price_minor', 2000, 'unit_cost_minor', 800, 'is_taxable', true)
    )
  ))->>'line_count',
  '2', 'the scope command reports the two lines it wrote'
);

select is(
  (select count(*)::int from public.job_line_items where job_id = (select id from target_job)),
  2, 'the job now carries exactly those two lines'
);

-- Position is renumbered from the order the payload asked for, not the order the rows arrived in.
select is(
  (select array_agg(name order by position) from public.job_line_items
    where job_id = (select id from target_job)),
  array['Downpipe bracket', 'Gutter clearing'],
  'the lines are stored in the order the payload numbered them'
);

select is((select revision from target_job), 1, 'rewriting the scope bumps the job revision to 1');

select is(
  (select count(*)::int from public.job_events
    where job_id = (select id from target_job) and event_type = 'scope_updated'),
  1, 'the rewrite emitted one scope_updated event'
);

-- Money is recalculated by the database, never by the caller. 2 x 5000 + 1 x 2000 = 12000.
set local role postgres;
select is((select subtotal_minor from public.jobs where id = (select id from target_job)),
  12000::bigint, 'the subtotal was recalculated from the new lines');
select is((select cost_minor from public.jobs where id = (select id from target_job)),
  2800::bigint, 'the internal cost was recalculated too');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 4. Guards on the scope command -----------------------------------------------------------------------------

select throws_ok(
  $$ select public.replace_job_line_items(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job), 0, '[]'::jsonb) $$,
  'P0409', null, 'a stale revision is refused rather than wiping a newer scope'
);

select throws_ok(
  $$ select public.replace_job_line_items(
    'c2000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000099', 0, '[]'::jsonb) $$,
  'P0404', null, 'pricing a job that is not in this organization is a not-found'
);

select throws_ok(
  $$ select public.replace_job_line_items(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), '{}'::jsonb) $$,
  '23514', null, 'a scope that is not a list of lines is refused'
);

-- The 100-line cap is the table's own statement trigger, so it holds no matter which command inserts.
select throws_ok(
  $$ select public.replace_job_line_items(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job), (select revision from target_job),
    (select jsonb_agg(jsonb_build_object(
      'position', n, 'name', 'Line ' || n, 'category', 'service',
      'quantity', 1, 'unit_price_minor', 100, 'unit_cost_minor', 0, 'is_taxable', true))
     from generate_series(1, 101) as n)) $$,
  '54000', null, 'a job cannot be given more than 100 lines'
);

select is((select count(*)::int from public.job_line_items where job_id = (select id from target_job)),
  2, 'a refused rewrite leaves the previous scope untouched');

-- A field member holds no jobs.edit, so none of the four commands open for them.
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$ select public.replace_job_line_items(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), '[]'::jsonb) $$,
  '42501', null, 'a member without jobs.edit cannot reprice a job'
);
select throws_ok(
  $$ select public.set_job_billing(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'job_total', 'manual') $$,
  '42501', null, 'a member without jobs.edit cannot change the billing setup'
);
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 5. Price basis and invoicing timing -------------------------------------------------------------------------

select throws_ok(
  $$ select public.set_job_billing(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'per_visit', 'manual') $$,
  '23514', null, 'a one-off job cannot be priced per visit'
);

select throws_ok(
  $$ select public.set_job_billing(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'job_total', 'whenever') $$,
  '23514', null, 'an invoicing timing that is not one of the five is refused'
);

select is(
  (public.set_job_billing(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'job_total', 'manual'))->>'billing_timing',
  'manual', 'the one-off job switches to manual invoicing'
);

select is((select billing_timing from public.jobs where id = (select id from target_job)),
  'manual', 'the new timing is stored');

select is(
  (select metadata->'changed' from public.job_events
    where job_id = (select id from target_job) and event_type = 'billing_updated'),
  '["billing_timing"]'::jsonb,
  'the history names only the decision that actually moved'
);

-- Repeating work gets the other two bases, and is refused the one-off's.
select is(
  (public.set_job_billing(
    'c2000000-0000-0000-0000-000000000001', (select id from repeat_job),
    (select revision from repeat_job), 'per_visit', 'per_completed_visit'))->>'price_basis',
  'per_visit', 'a recurring job can be priced per visit'
);
select throws_ok(
  $$ select public.set_job_billing(
    'c2000000-0000-0000-0000-000000000001', (select id from repeat_job),
    (select revision from repeat_job), 'job_total', 'month_end') $$,
  '23514', null, 'a recurring job cannot be priced as one whole job'
);

-- 6. Discount ---------------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.set_job_discount(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'Too much', 'percentage', 12000) $$,
  '23514', null, 'a percentage discount above 100 percent is refused'
);

select throws_ok(
  $$ select public.set_job_discount(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), null, 'percentage', 1000) $$,
  '23514', null, 'a discount must carry the name the customer will read'
);

select lives_ok(
  $$ select public.set_job_discount(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'Spring offer', 'percentage', 1000) $$,
  'a named ten percent discount is accepted'
);

set local role postgres;
select is((select discount_minor from public.jobs where id = (select id from target_job)),
  1200::bigint, 'ten percent of the 12000 subtotal is taken off');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 7. Tax --------------------------------------------------------------------------------------------------

select throws_ok(
  $$ select public.set_job_tax(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'custom', null, null, 825) $$,
  '23514', null, 'a custom tax must be named'
);

select throws_ok(
  $$ select public.set_job_tax(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'saved_rate', 'c8000000-0000-0000-0000-000000000099') $$,
  '23514', null, 'a saved rate that does not exist here is refused'
);

-- Saving a one-off rate into the shared list is a settings permission this office member does not hold.
select throws_ok(
  $$ select public.set_job_tax(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'custom', null, 'City tax', 825, true) $$,
  '42501', null, 'saving a custom rate for reuse needs settings.taxes.manage'
);

select lives_ok(
  $$ select public.set_job_tax(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'custom', null, 'City tax', 825) $$,
  'a one-off custom rate is accepted without touching the shared list'
);

set local role postgres;
-- Tax follows the shared quote rule: the discount is allocated across the lines in proportion, each line is
-- taxed on its own discounted share, and those are summed. 9000 and 1800 at 8.25 percent give 743 and 149,
-- which is 892 -- one more minor unit than taxing the 10800 total in a single stroke would produce. The job
-- and the quote it came from must agree to the cent, so the job is not allowed its own shortcut here.
select is(
  (select tax_minor from public.jobs where id = (select id from target_job)),
  892::bigint, 'tax is charged per line on its discounted share, then summed'
);
select is(
  (select total_minor = subtotal_minor - discount_minor + tax_minor
     from public.jobs where id = (select id from target_job)),
  true, 'the stored total reconciles with its own parts'
);
select is(
  (select tax_rate_id from public.jobs where id = (select id from target_job)),
  null, 'a custom rate is not linked to the shared list'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$ select public.set_job_tax(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), 'no_tax') $$,
  'a job can be marked as not taxed'
);

set local role postgres;
select is((select tax_minor from public.jobs where id = (select id from target_job)),
  0::bigint, 'no tax means no tax in the stored money');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1000000-0000-0000-0000-000000000001', true);

-- 8. Removing the discount ---------------------------------------------------------------------------------

select lives_ok(
  $$ select public.set_job_discount(
    'c2000000-0000-0000-0000-000000000001', (select id from target_job),
    (select revision from target_job), null, null, null) $$,
  'sending no discount type removes the discount'
);

set local role postgres;
select is((select discount_minor from public.jobs where id = (select id from target_job)),
  0::bigint, 'the money goes back to the undiscounted subtotal');
set local role authenticated;

select * from finish();
rollback;
