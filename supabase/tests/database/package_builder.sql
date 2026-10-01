-- Package builder P15: the builder's own commands on a fresh database (feasibility review scenarios).
-- Create and copy, whole-draft saves, two tabs saving at once, a save that fails part-way, publish checks,
-- a new edition leaving existing customers on theirs, archive and restore, and deleting drafts.

begin;

create extension if not exists pgtap with schema extensions;
select plan(44);

set local role postgres;

create temporary table ids (name text primary key, id uuid);
create temporary table step (name text primary key, result jsonb);

-- 1. Only Jafar's service role runs the builder. -------------------------------------------------------

select ok(not has_function_privilege('authenticated', 'public.create_package_draft(text, text, text, text, uuid)', 'execute'),
  'a contractor session cannot create packages');
select ok(not has_function_privilege('authenticated', 'public.save_package_draft(uuid, uuid, integer, jsonb, text)', 'execute'),
  'a contractor session cannot save drafts');
select ok(not has_function_privilege('authenticated', 'public.publish_package_draft(uuid, uuid, integer, text)', 'execute'),
  'a contractor session cannot publish');
select ok(not has_function_privilege('anon', 'public.set_package_archived(uuid, boolean, text)', 'execute'),
  'a visitor cannot archive');

-- 2. Create: a new package starts as a private draft with the core features and every allowance row. ----

insert into step values ('create', public.create_package_draft('p15-pro', 'Pro', 'owner@example.test', 'p15-create'));
insert into ids select 'pro', (result ->> 'package_id')::uuid from step where name = 'create';
insert into ids select 'pro_draft', e.id from public.package_editions e
where e.package_id = (select id from ids where name = 'pro') and e.status = 'draft';

select is((select result ->> 'applied' from step where name = 'create'), 'true', 'a package is created');
select is(
  public.create_package_draft('p15-pro', 'Pro', 'owner@example.test', 'p15-create') ->> 'package_id',
  (select id::text from ids where name = 'pro'), 'a retried create returns the same package');
select is((select visibility from public.packages where id = (select id from ids where name = 'pro')), 'private',
  'a new package is private until Jafar lists it');
select is(
  (select count(*)::integer from public.package_edition_capabilities where edition_id = (select id from ids where name = 'pro_draft')),
  (select count(*)::integer from public.package_capabilities where kind = 'core'),
  'a new draft carries exactly the core features');
select is(
  (select count(*)::integer from public.package_edition_allowances where edition_id = (select id from ids where name = 'pro_draft')),
  (select count(*)::integer from public.package_allowances), 'and one row per allowance');
select throws_ok(
  $$select public.create_package_draft('p15-pro', 'Another', 'owner@example.test', 'p15-create-dup')$$,
  '23505', 'Another package already uses the web address "p15-pro".', 'a second package cannot take the same web address');

-- 3. Save: the whole draft in one go, naming the revision that was loaded. -------------------------------

create temporary table pro_terms as select jsonb_build_object(
  'name', 'Pro', 'promise', 'Everything a growing crew needs', 'highlights', '["Never miss a lead"]'::jsonb,
  'monthly_price_usd_cents', 19900, 'yearly_price_usd_cents', 199000,
  'capabilities', '["communications.inbox", "website_chat"]'::jsonb,
  'allowances', '[{"key": "employee_seats", "state": "numeric", "value": 10},
    {"key": "operational_email_recipients", "state": "numeric", "value": 2000},
    {"key": "website_chat_widgets", "state": "numeric", "value": 2},
    {"key": "website_chat_accepted_conversations", "state": "unlimited"},
    {"key": "marketing_email_recipients", "state": "numeric", "value": 500}]'::jsonb
) as terms;

insert into step values ('save1', public.save_package_draft((select id from ids where name = 'pro'),
  (select id from ids where name = 'pro_draft'), 1, (select terms from pro_terms), 'owner@example.test'));

select is((select result ->> 'saved' from step where name = 'save1'), 'true', 'the whole draft saves');
select is((select (result -> 'draft' ->> 'revision')::integer from step where name = 'save1'), 2, 'the revision moves on');
select is((select (result -> 'draft' ->> 'yearly_price_usd_cents')::integer from step where name = 'save1'), 199000,
  'a yearly price is saved beside the monthly one');
select is(
  (select allowance_state from public.package_edition_allowances
   where edition_id = (select id from ids where name = 'pro_draft') and allowance_key = 'marketing_email_recipients'),
  'not_included', 'an allowance for a feature left out is stored as not included');

-- Two tabs: the second one still holds revision 1, so nothing it sends is written.
insert into step values ('stale', public.save_package_draft((select id from ids where name = 'pro'),
  (select id from ids where name = 'pro_draft'), 1,
  (select terms || '{"name": "Old tab", "monthly_price_usd_cents": 100}'::jsonb from pro_terms), 'owner@example.test'));
select is((select result ->> 'reason' from step where name = 'stale'), 'stale', 'an older tab is told the draft moved on');
select is((select result -> 'draft' ->> 'name' from step where name = 'stale'), 'Pro',
  'and gets the newer draft back to compare');
select is((select name from public.package_editions where id = (select id from ids where name = 'pro_draft')), 'Pro',
  'the older tab overwrote nothing');

-- A save that fails part-way leaves the draft exactly as it was.
select throws_ok(
  $$select public.save_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft'), 2,
    (select terms || '{"name": "Half saved", "capabilities": ["no.such.feature"]}'::jsonb from pro_terms), 'owner@example.test')$$,
  '23514', 'The capability no.such.feature does not exist.', 'a save with a bad feature is refused');
select results_eq(
  $$select name, revision from public.package_editions where id = (select id from ids where name = 'pro_draft')$$,
  $$values ('Pro'::text, 2)$$, 'the refused save changed neither the name nor the revision');
select is(
  (select count(*)::integer from public.package_edition_capabilities
   where edition_id = (select id from ids where name = 'pro_draft') and capability_key = 'website_chat'),
  1, 'and kept the features already saved');

-- 4. Publish: only the exact saved draft, and only when it can be sold. -----------------------------------

select is(
  public.publish_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft'), 1,
    'owner@example.test') ->> 'reason',
  'stale', 'publishing a revision older than the saved one is refused');

select ok(public.save_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft'), 2,
  (select terms || '{"capabilities": ["website_chat", "reporting.advanced"]}'::jsonb from pro_terms), 'owner@example.test') ->> 'saved' = 'true',
  'a draft may hold an unready feature and a missing requirement');
insert into step values ('not_ready', public.publish_package_draft((select id from ids where name = 'pro'),
  (select id from ids where name = 'pro_draft'), 3, 'owner@example.test'));
select is((select result ->> 'reason' from step where name = 'not_ready'), 'not_ready', 'but it cannot be published');
select is(
  (select jsonb_agg(p ->> 'code' order by p ->> 'code') from step, jsonb_array_elements(result -> 'problems') p where name = 'not_ready'),
  '["missing_requirement", "not_sellable"]'::jsonb, 'the problems say which feature is unready and which one is missing');

select ok(public.save_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft'), 3,
  (select terms from pro_terms), 'owner@example.test') ->> 'saved' = 'true', 'the draft is put right');
insert into step values ('publish1', public.publish_package_draft((select id from ids where name = 'pro'),
  (select id from ids where name = 'pro_draft'), 4, 'owner@example.test'));
select is((select (result ->> 'edition_number')::integer from step where name = 'publish1'), 1, 'edition 1 is published');
select is(
  public.publish_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft'), 4,
    'owner@example.test') ->> 'applied',
  'false', 'a retried publish does nothing');
select throws_ok(
  $$select public.save_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft'), 4,
    (select terms from pro_terms), 'owner@example.test')$$,
  'P0002', NULL, 'a published edition can no longer be saved as a draft');

-- 5. A customer on edition 1 keeps it when edition 2 is published. --------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status)
values ('15000000-0000-0000-0000-000000000001', 'P15 Customer', 'p15-customer', 'active');
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, source, reason
) values ('15000000-0000-0000-0000-000000000001', (select id from ids where name = 'pro_draft'), 'month', 19900,
  now() - interval '1 day', 'test_reset', 'Package builder test');

insert into step values ('reopen', public.open_package_draft((select id from ids where name = 'pro'), 'owner@example.test'));
insert into ids select 'pro_draft2', e.id from public.package_editions e
where e.package_id = (select id from ids where name = 'pro') and e.status = 'draft';
select isnt((select id from ids where name = 'pro_draft2'), (select id from ids where name = 'pro_draft'),
  'revising a published package opens a new draft');
select ok(public.save_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft2'),
  (select revision from public.package_editions where id = (select id from ids where name = 'pro_draft2')),
  (select terms || '{"monthly_price_usd_cents": 24900, "capabilities": ["communications.inbox"],
    "allowances": [{"key": "employee_seats", "state": "numeric", "value": 3},
      {"key": "operational_email_recipients", "state": "numeric", "value": 1000}]}'::jsonb from pro_terms),
  'owner@example.test') ->> 'saved' = 'true', 'edition 2 drops website chat, cuts seats, and costs more');
select is(
  (public.publish_package_draft((select id from ids where name = 'pro'), (select id from ids where name = 'pro_draft2'),
    (select revision from public.package_editions where id = (select id from ids where name = 'pro_draft2')),
    'owner@example.test') ->> 'edition_number')::integer,
  2, 'edition 2 is published');
select is((select status from public.package_editions where id = (select id from ids where name = 'pro_draft')), 'superseded',
  'edition 1 is retired for new customers');
select is((select value from public.organization_allowance('15000000-0000-0000-0000-000000000001', 'employee_seats')), 10,
  'the existing customer keeps edition 1''s ten seats');
select ok(private.organization_has_capability('15000000-0000-0000-0000-000000000001', 'website_chat', now()),
  'and keeps website chat');

-- 6. Archive and restore change the catalog, never a customer's edition. --------------------------------

select is(public.set_package_archived((select id from ids where name = 'pro'), true, 'owner@example.test') ->> 'applied', 'true',
  'the package is archived');
select ok(private.organization_has_capability('15000000-0000-0000-0000-000000000001', 'website_chat', now()),
  'an archived package''s customers keep their access');
select is(public.set_package_archived((select id from ids where name = 'pro'), false, 'owner@example.test') ->> 'applied', 'true',
  'and it can be restored');

-- 7. Delete: only drafts, and a never-published package goes with its draft. ---------------------------

insert into step values ('copy', public.create_package_draft('p15-pro-copy', 'Pro copy', 'owner@example.test', 'p15-copy',
  (select id from ids where name = 'pro')));
insert into ids select 'copy', (result ->> 'package_id')::uuid from step where name = 'copy';
select is(
  (select monthly_price_usd_cents from public.package_editions
   where package_id = (select id from ids where name = 'copy') and status = 'draft'),
  24900, 'a copy starts from the latest terms of the package it copies');
select throws_ok(
  $$select public.set_package_archived((select id from ids where name = 'copy'), true, 'owner@example.test')$$,
  '23514', NULL, 'a never-published package cannot be archived');
select lives_ok(
  $$select public.delete_package_draft((select id from ids where name = 'copy'),
    (select e.id from public.package_editions e where e.package_id = (select id from ids where name = 'copy')), 1, 'owner@example.test')$$,
  'its draft can be deleted');
select is((select count(*)::integer from public.packages where id = (select id from ids where name = 'copy')), 0,
  'and the never-published package goes with it');

-- 8. Monthly allowances restart monthly on yearly packages too, on the service start day (the last day of
-- a shorter month), and a cancelled change never moves that day. -------------------------------------

insert into public.organizations (id, name, slug, lifecycle_status)
values ('15000000-0000-0000-0000-000000000002', 'P15 Yearly', 'p15-yearly', 'active');
select private.ensure_organization_commercial_rows('15000000-0000-0000-0000-000000000002');
insert into public.organization_free_access_events (
  id, organization_id, action, starts_at, access_until_date, reason, actor_owner_email, occurred_at
) values ('15000000-0000-0000-0000-0000000000f1', '15000000-0000-0000-0000-000000000002', 'grant', '2026-01-01',
  '2026-12-31', 'Package builder test grant', 'owner@example.test', '2026-01-01 00:00:00+00');
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, service_anchor_date, source, reason
) values ('15000000-0000-0000-0000-000000000002', (select id from ids where name = 'pro_draft2'), 'year', 249000,
  '2026-01-31 00:00:00+00', '2026-01-31', 'test_reset', 'Package builder test');
insert into public.organization_package_agreements (
  organization_id, edition_id, billing_interval, agreed_price_usd_cents, effective_from, service_anchor_date, source,
  reason, cancelled_at, cancel_reason, cancelled_by_email, cancel_idempotency_key
) values ('15000000-0000-0000-0000-000000000002',
  (select e.id from public.package_editions e join public.packages p on p.id = e.package_id
   where p.slug = 'test-package' and e.status = 'published'), 'month', 0,
  '2026-03-01 00:00:00+00', '2026-03-10', 'test_reset', 'A change Jafar cancelled', '2026-02-01 00:00:00+00',
  'Changed their mind', 'owner@example.test', 'p15-cancelled-change');

select results_eq(
  $$select window_starts_at, window_ends_at from private.current_communication_allowance_window(
    '15000000-0000-0000-0000-000000000002', '2026-02-20 12:00:00+00')$$,
  $$values ('2026-01-31 00:00:00+00'::timestamptz, '2026-02-28 00:00:00+00'::timestamptz)$$,
  'a yearly package''s allowance month ends on the last day of February');
select results_eq(
  $$select window_starts_at, window_ends_at from private.current_communication_allowance_window(
    '15000000-0000-0000-0000-000000000002', '2026-03-15 12:00:00+00')$$,
  $$values ('2026-02-28 00:00:00+00'::timestamptz, '2026-03-31 00:00:00+00'::timestamptz)$$,
  'and the next one returns to the 31st; the cancelled change did not move it to the 10th');
select is((select value from public.organization_allowance('15000000-0000-0000-0000-000000000002', 'employee_seats',
  '2026-03-15 12:00:00+00')), 3, 'the cancelled change''s seats never apply');

select * from finish();
rollback;
