-- Jobs, Part 5: job-owned scope lines, job arithmetic, and the quote-to-job handoff.
-- Written for `supabase test db`; verified against the remote dev project by running this whole file as
-- one transaction that is rolled back at the end, the same convention `tenant_isolation.sql` documents.
-- Do not run it through a runner that executes each statement separately: `set local role` and
-- `set_config` do not survive that.
begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

-- throws_ok's three-argument form takes (query, errcode, errmsg) in this pgTAP build, so an error code is
-- checked with the four-argument form and a null message, and a message is checked with a text second
-- argument.

-- 1. Shape and privileges -----------------------------------------------------------------------------------

select has_table('public', 'job_line_items', 'a job owns its own scope lines');
select has_index('public', 'job_line_items', 'job_line_items_job_idx', 'the ordered scope read has an index');

select is(
  has_table_privilege('authenticated', 'public.job_line_items', 'insert'),
  false, 'members cannot insert a job line'
);
select is(
  has_table_privilege('authenticated', 'public.job_line_items', 'update'),
  false, 'members cannot update a job line'
);
select is(
  has_table_privilege('authenticated', 'public.job_line_items', 'delete'),
  false, 'members cannot delete a job line'
);

select is(
  has_column_privilege('authenticated', 'public.job_line_items', 'unit_price_minor', 'select'),
  false, 'a line price is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.job_line_items', 'line_total_minor', 'select'),
  false, 'a line total is not readable straight off the table'
);
select is(
  has_column_privilege('authenticated', 'public.job_line_items', 'name', 'select'),
  true, 'what the work is stays readable'
);

select is(
  has_function_privilege(
    'anon',
    'public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text)',
    'execute'
  ),
  false, 'anonymous callers cannot convert a quote'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.convert_quote_to_job(uuid, text, text, text, text, text, text, boolean, text)',
    'execute'
  ),
  true, 'members reach conversion through its own checked command'
);
select is(
  has_function_privilege('authenticated', 'private.calculate_job(uuid)', 'execute'),
  false, 'members cannot run job arithmetic themselves'
);
select is(
  has_function_privilege('authenticated', 'private.store_job_money(uuid)', 'execute'),
  false, 'members cannot write job money themselves'
);
select is(
  has_function_privilege('anon', 'public.job_line_money(uuid)', 'execute'),
  false, 'anonymous callers cannot read job line money'
);
select is(
  has_function_privilege('authenticated', 'public.job_line_money(uuid)', 'execute'),
  true, 'members reach line money through the gated reader'
);

-- 2. Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'convert-admin-a@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'convert-admin-b@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'convert-office-a@example.test', 'test', now(), now(), now()),
  ('90000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'convert-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('91000000-0000-0000-0000-000000000001', 'Convert Org A', 'convert-org-a', 'active'),
  ('91000000-0000-0000-0000-000000000002', 'Convert Org B', 'convert-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'admin'),
  ('91000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000002', 'admin'),
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000003', 'office'),
  ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000004', 'field');

insert into public.clients (id, organization_id, display_name)
values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'Convert Client A'),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Convert Client B');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '7 Convert Lane', 'Testville'),
  ('93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000002', '7 Other Lane', 'Otherville');

-- Quote 1: the interesting one. A discount, a tax, a required line of each taxability, a text line, one
-- add-on the customer took and one they did not.
insert into public.quotes (
  id, organization_id, client_id, property_id, quote_number, title, status, currency_code
) values (
  '94000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001',
  1, 'Roof and gutters', 'draft', 'USD'
);

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, status, currency_code,
  client_display_name, organization_name,
  discount_name, discount_type, discount_value, tax_source, tax_name, tax_rate_basis_points
) values (
  '95000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001', 1, 'draft', 'USD',
  'Convert Client A', 'Convert Org A',
  'Spring offer', 'percentage', 1000, 'custom', 'GST', 500
);

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, line_kind, selection_kind, category,
  name, quantity, unit_price_minor, unit_cost_minor, is_taxable
) values
  ('96000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001',
   '94000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 0,
   'priced', 'required', 'service', 'Roof repair', 2, 10000, 4000, true),
  ('96000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001',
   '94000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 1,
   'priced', 'required', 'product', 'Permit', 1, 5000, 2000, false),
  ('96000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000001',
   '94000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 2,
   'priced', 'optional', 'product', 'Downspout upgrade', 1, 4000, 1000, true),
  ('96000000-0000-0000-0000-000000000005', '91000000-0000-0000-0000-000000000001',
   '94000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 4,
   'priced', 'optional', 'product', 'Gutter guards', 1, 9000, 3000, true);

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, line_kind, selection_kind,
  name, is_taxable
) values (
  '96000000-0000-0000-0000-000000000004', '91000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001', '95000000-0000-0000-0000-000000000001', 3,
  'text', 'required', 'Access through the side gate', false
);

-- The version freezes what the calculator says about the customer's selection, exactly as publishing does.
with calculated as (
  select private.calculate_quote_version(
    '95000000-0000-0000-0000-000000000001',
    array['96000000-0000-0000-0000-000000000003']::uuid[]
  ) as answer
)
update public.quote_versions as version
set subtotal_minor = (calculated.answer->>'subtotal_minor')::bigint,
    discount_minor = (calculated.answer->>'discount_minor')::bigint,
    tax_minor = (calculated.answer->>'tax_minor')::bigint,
    total_minor = (calculated.answer->>'total_minor')::bigint,
    cost_minor = (calculated.answer->>'cost_minor')::bigint,
    profit_minor = (calculated.answer->>'profit_minor')::bigint,
    calculation = calculated.answer
from calculated
where version.id = '95000000-0000-0000-0000-000000000001';

update public.quote_versions
set status = 'published', version_number = 1, published_at = now(), document_hash = repeat('a', 64)
where id = '95000000-0000-0000-0000-000000000001';

update public.quotes
set status = 'approved', decision = 'approved', decided_at = now(), decision_method = 'offline_verbal', sent_at = now(),
    current_published_version_id = '95000000-0000-0000-0000-000000000001'
where id = '94000000-0000-0000-0000-000000000001';

-- Quote 2: a plain approved quote, for the second job number.
insert into public.quotes (
  id, organization_id, client_id, property_id, quote_number, title, status, currency_code
) values (
  '94000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001',
  2, 'Monthly maintenance', 'draft', 'USD'
);

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, status, currency_code,
  client_display_name, organization_name
) values (
  '95000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002', 1, 'draft', 'USD', 'Convert Client A', 'Convert Org A'
);

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, line_kind, selection_kind, category,
  name, quantity, unit_price_minor, unit_cost_minor, is_taxable
) values (
  '96000000-0000-0000-0000-000000000011', '91000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002', '95000000-0000-0000-0000-000000000002', 0,
  'priced', 'required', 'service', 'Monthly visit', 1, 12000, 5000, true
);

with calculated as (
  select private.calculate_quote_version('95000000-0000-0000-0000-000000000002') as answer
)
update public.quote_versions as version
set subtotal_minor = (calculated.answer->>'subtotal_minor')::bigint,
    total_minor = (calculated.answer->>'total_minor')::bigint,
    cost_minor = (calculated.answer->>'cost_minor')::bigint,
    profit_minor = (calculated.answer->>'profit_minor')::bigint,
    calculation = calculated.answer
from calculated
where version.id = '95000000-0000-0000-0000-000000000002';

update public.quote_versions
set status = 'published', version_number = 1, published_at = now(), document_hash = repeat('b', 64)
where id = '95000000-0000-0000-0000-000000000002';

update public.quotes
set status = 'approved', decision = 'approved', decided_at = now(), decision_method = 'offline_verbal', sent_at = now(),
    current_published_version_id = '95000000-0000-0000-0000-000000000002'
where id = '94000000-0000-0000-0000-000000000002';

-- Quote 3: still a draft, so it has nothing to hand over.
insert into public.quotes (
  id, organization_id, client_id, property_id, quote_number, title, status, currency_code
) values (
  '94000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001',
  3, 'Not answered yet', 'draft', 'USD'
);

-- Quote 4: approved, but the deposit it asked for has never arrived.
insert into public.quotes (
  id, organization_id, client_id, property_id, quote_number, title, status, currency_code
) values (
  '94000000-0000-0000-0000-000000000004', '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001',
  4, 'Deposit first', 'draft', 'USD'
);

insert into public.quote_versions (
  id, organization_id, quote_id, version_number, status, currency_code,
  client_display_name, organization_name, deposit_type
) values (
  '95000000-0000-0000-0000-000000000004', '91000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000004', 1, 'draft', 'USD',
  'Convert Client A', 'Convert Org A', 'deposit_only'
);

insert into public.quote_version_lines (
  id, organization_id, quote_id, quote_version_id, position, line_kind, selection_kind, category,
  name, quantity, unit_price_minor, unit_cost_minor, is_taxable
) values (
  '96000000-0000-0000-0000-000000000021', '91000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000004', '95000000-0000-0000-0000-000000000004', 0,
  'priced', 'required', 'service', 'Deck build', 1, 20000, 9000, false
);

insert into public.quote_version_schedule_items (
  organization_id, quote_id, quote_version_id, position, description, value_type, value, is_deposit
) values (
  '91000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000004',
  '95000000-0000-0000-0000-000000000004', 0, 'Deposit', 'percentage', 2000, true
);

with calculated as (
  select private.calculate_quote_version('95000000-0000-0000-0000-000000000004') as answer
)
update public.quote_versions as version
set subtotal_minor = (calculated.answer->>'subtotal_minor')::bigint,
    total_minor = (calculated.answer->>'total_minor')::bigint,
    cost_minor = (calculated.answer->>'cost_minor')::bigint,
    profit_minor = (calculated.answer->>'profit_minor')::bigint,
    deposit_required_minor = (calculated.answer->>'deposit_required_minor')::bigint,
    calculation = calculated.answer
from calculated
where version.id = '95000000-0000-0000-0000-000000000004';

update public.quote_versions
set status = 'published', version_number = 1, published_at = now(), document_hash = repeat('c', 64)
where id = '95000000-0000-0000-0000-000000000004';

update public.quotes
set status = 'approved', decision = 'approved', decided_at = now(), decision_method = 'offline_verbal', sent_at = now(),
    current_published_version_id = '95000000-0000-0000-0000-000000000004'
where id = '94000000-0000-0000-0000-000000000004';

-- 3. The handoff ----------------------------------------------------------------------------------------------

-- The answer is kept in a table so three assertions can read one conversion. The table belongs to
-- postgres; the call that fills it is made by a member, which is the part under test.
create temp table conversion (answer jsonb);
grant select, insert on conversion to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

insert into conversion
select public.convert_quote_to_job(
  '94000000-0000-0000-0000-000000000001', 'idem-key-one-0001', 'hash-one'
);

select is(
  (select (answer->>'applied')::boolean from conversion),
  true, 'converting an approved quote creates the job'
);

select is(
  (select (answer->>'job_number')::int from conversion),
  1, 'the job takes the organization''s first job number'
);

select is(
  (select (answer->>'line_count')::int from conversion),
  4, 'the required lines, the text line and the chosen add-on travel; the unchosen one does not'
);

set local role postgres;

create temp table job_ref as
  select id from public.jobs where quote_id = '94000000-0000-0000-0000-000000000001';
grant select on job_ref to authenticated;

select is(
  (select job.total_minor from public.jobs as job where job.id = (select id from job_ref)),
  (select version.total_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  'a converted job opens on the approved quote total'
);

select is(
  (select job.subtotal_minor from public.jobs as job where job.id = (select id from job_ref)),
  (select version.subtotal_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  'the subtotal matches too'
);

select is(
  (select job.tax_minor from public.jobs as job where job.id = (select id from job_ref)),
  (select version.tax_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  'the tax matches too'
);

select is(
  (select job.discount_minor from public.jobs as job where job.id = (select id from job_ref)),
  (select version.discount_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  'the discount matches too'
);

select is(
  (select job.cost_minor from public.jobs as job where job.id = (select id from job_ref)),
  (select version.cost_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  'internal cost comes across as well'
);

select is(
  (select array_agg(item.position order by item.position)
   from public.job_line_items as item where item.job_id = (select id from job_ref)),
  array[0, 1, 2, 3], 'the copied lines are renumbered from zero with no gaps'
);

select is(
  (select count(*)::int from public.job_line_items as item
    where item.job_id = (select id from job_ref) and item.name = 'Gutter guards'),
  0, 'an add-on the customer did not take is not part of the job'
);

select is(
  (select count(*)::int from public.job_line_items as item
    where item.job_id = (select id from job_ref) and item.name = 'Downspout upgrade'),
  1, 'an add-on the customer did take is part of the job'
);

select is(
  (select status from public.quotes where id = '94000000-0000-0000-0000-000000000001'),
  'converted', 'the quote is terminally converted in the same transaction'
);

select is(
  (select (job.quote_id::text || '/' || job.quote_version_id::text) from public.jobs as job
    where job.id = (select id from job_ref)),
  '94000000-0000-0000-0000-000000000001/95000000-0000-0000-0000-000000000001',
  'the job keeps the quote and the exact version it came from'
);

select is(
  (select count(*)::int from public.job_events
    where job_id = (select id from job_ref) and event_type = 'job_converted_from_quote'),
  1, 'the conversion is recorded in the job''s history'
);

select is(
  (select count(*)::int from public.activity_events
    where entity_type = 'quote' and entity_id = '94000000-0000-0000-0000-000000000001'
      and event_type = 'quote.converted'),
  1, 'the conversion is recorded on the quote''s timeline'
);

-- 4. Doing it twice --------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select is(
  (select public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000001', 'idem-key-one-0001', 'hash-one'
  )->>'job_id'),
  (select id::text from job_ref),
  'a retry carrying the same key gets the first job back rather than making a second one'
);

select is(
  (select (public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000001', 'idem-key-one-0001', 'hash-one'
  )->>'applied')::boolean),
  false, 'and it says plainly that it changed nothing'
);

select throws_ok(
  $q$select public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000001', 'idem-key-two-0002', 'hash-two'
  )$q$,
  'P0409'::char(5),
  null::text,
  'a different attempt on a quote that already has a job is a conflict'
);

-- 5. Copies, not references ------------------------------------------------------------------------------------

set local role postgres;

update public.job_line_items
set name = 'Roof repair, revised', unit_price_minor = 12000
where job_id = (select id from job_ref) and name = 'Roof repair';

select is(
  (select line.name from public.quote_version_lines as line
    where line.id = '96000000-0000-0000-0000-000000000001'),
  'Roof repair', 'editing the job''s scope does not touch what the customer approved'
);

select is(
  (select version.total_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  (select (calculation->>'total_minor')::bigint from public.quote_versions
    where id = '95000000-0000-0000-0000-000000000001'),
  'and the approved document''s own total is unchanged'
);

select isnt(
  (select (private.store_job_money((select id from job_ref))->>'total_minor')::bigint),
  (select version.total_minor from public.quote_versions as version
    where version.id = '95000000-0000-0000-0000-000000000001'),
  'a later scope change is a job fact: the job total moves and the quote total does not'
);

-- 6. The second quote, and the ones that cannot go ------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select is(
  (select (public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000002', 'idem-key-three-0003', 'hash-three',
    'recurring', 'per_visit'
  )->>'job_number')::int),
  2, 'the next conversion in the same organization takes the next job number'
);

select throws_ok(
  $q$select public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000003', 'idem-key-four-0004', 'hash-four'
  )$q$,
  'Only an approved quote can become a job.',
  'a quote the customer has not answered cannot become a job'
);

select throws_ok(
  $q$select public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000004', 'idem-key-five-0005', 'hash-five'
  )$q$,
  'This quote is not ready for a job yet.',
  'an approved quote whose deposit has not arrived is not ready'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);

select throws_ok(
  $q$select public.convert_quote_to_job(
    '94000000-0000-0000-0000-000000000004', 'idem-key-six-00006', 'hash-six'
  )$q$,
  'You do not have access to turn this quote into a job.',
  'a field member cannot turn a quote into a job'
);

-- 7. What a scope line refuses ---------------------------------------------------------------------------------

set local role postgres;

select throws_ok(
  $q$insert into public.job_line_items (
    organization_id, job_id, position, line_kind, name, is_taxable, unit_price_minor
  ) values (
    '91000000-0000-0000-0000-000000000001', (select id from job_ref), 90, 'text', 'A note', false, 500
  )$q$,
  '23514'::char(5),
  null::text,
  'a text line cannot carry a price'
);

select throws_ok(
  $q$insert into public.job_line_items (
    organization_id, job_id, position, line_kind, category, name, quantity,
    unit_price_minor, unit_cost_minor
  ) values (
    '91000000-0000-0000-0000-000000000002', (select id from job_ref), 91, 'priced', 'product',
    'Cross tenant line', 1, 100, 50
  )$q$,
  '23503'::char(5),
  null::text,
  'a line cannot be attached to another organization''s job'
);

select throws_ok(
  $q$insert into public.job_line_items (
    organization_id, job_id, position, line_kind, category, name, quantity,
    unit_price_minor, unit_cost_minor
  )
  select '91000000-0000-0000-0000-000000000001', (select id from job_ref), 100 + step,
    'priced', 'product', 'Bulk line', 1, 100, 50
  from generate_series(1, 101) as step$q$,
  '54000'::char(5),
  null::text,
  'a job stops at a hundred lines'
);

-- 8. Who may read what ------------------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select is(
  (select count(*)::int from public.job_line_items),
  5, 'an admin sees their own organization''s job scope'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000002', true);

select is(
  (select count(*)::int from public.job_line_items),
  0, 'another organization''s job scope is invisible'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);

select isnt(
  (public.job_line_money((select id from job_ref))
    -> (select item.id::text from public.job_line_items as item
        where item.job_id = (select id from job_ref) and item.name = 'Permit')
    ->> 'unit_price_minor'),
  null::text, 'an admin reads line prices through the gated reader'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);

select is(
  (public.job_line_money((select id from job_ref))
    -> (select item.id::text from public.job_line_items as item
        where item.job_id = (select id from job_ref) and item.name = 'Permit')
    ->> 'unit_cost_minor'),
  null, 'an office member is not given internal cost on a line'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);

select is(
  public.job_line_money((select id from job_ref)),
  '{}'::jsonb, 'a field member holding neither money permission gets nothing back'
);

select * from finish();
rollback;
