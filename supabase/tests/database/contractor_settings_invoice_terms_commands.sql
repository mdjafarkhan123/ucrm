begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

-- Contractor Settings Part 5A: the three invoice-terms commands built earlier under the Invoices campaign
-- (`20260904170000_invoice_terms_billing_seam_and_permissions.sql`) had no pgTAP coverage of their own before
-- a Settings screen was built on top of them. This file is that coverage: save_invoice_payment_term (create
-- + edit + protected-term rules), remove_invoice_payment_term (archive + default fallback + client fallback),
-- set_organization_invoice_defaults (both defaults required, must be live terms), stale-revision P0409,
-- permission enforcement, and cross-tenant isolation.
--
-- Written for `supabase test db`, which runs the file as one session. Development currently uses the remote
-- Supabase project with no local stack, so this is verified there instead by running the file inside a single
-- transaction that is rolled back. Do not run it through a runner that executes each statement separately:
-- `set local role` does not survive that.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'invterms-admin@example.test', 'test', now(), now(), now()),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'invterms-field@example.test', 'test', now(), now(), now()),
  ('d1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'invterms-outsider@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('d2000000-0000-0000-0000-000000000001', 'Invoice Terms Test Co', 'invterms-test-co', 'active'),
  ('d2000000-0000-0000-0000-000000000002', 'Invoice Terms Other Co', 'invterms-other-co', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'admin'),
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'field'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003', 'admin');

-- 1. Every organization is seeded with the eight standard terms, defaults pointed at "Due on receipt" ------

select is(
  (select count(*)::integer from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001'),
  8,
  'a new organization is seeded with the eight standard payment terms'
);

select is(
  (select receipt_term.name
   from public.organization_settings as settings
   join public.invoice_payment_terms as receipt_term
     on receipt_term.organization_id = settings.organization_id
    and receipt_term.id = settings.invoice_default_term_residential_id
   where settings.organization_id = 'd2000000-0000-0000-0000-000000000001'),
  'Due on receipt',
  'the residential default starts on the protected receipt term'
);

select is(
  (select receipt_term.name
   from public.organization_settings as settings
   join public.invoice_payment_terms as receipt_term
     on receipt_term.organization_id = settings.organization_id
    and receipt_term.id = settings.invoice_default_term_commercial_id
   where settings.organization_id = 'd2000000-0000-0000-0000-000000000001'),
  'Due on receipt',
  'the commercial default starts on the protected receipt term too'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

-- 2. save_invoice_payment_term: create ----------------------------------------------------------------------

select is(
  (public.save_invoice_payment_term(
    'd2000000-0000-0000-0000-000000000001', 0, null, 'Net 21', 'net_days', 21
  ) ->> 'invoice_settings_revision')::integer,
  1,
  'creating a custom term bumps the invoice settings revision'
);

select is(
  (select rule || '/' || net_days from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21'),
  'net_days/21',
  'the new term stored its rule and net-day count'
);

select is(
  (select count(*)::integer from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001'),
  9,
  'the organization now has nine terms'
);

select throws_ok(
  $$select public.save_invoice_payment_term(
      'd2000000-0000-0000-0000-000000000001', 1, null, 'Net 21', 'net_days', 45)$$,
  '23505', null, 'a second live term cannot share a name with one already live'
);

select throws_ok(
  $$select public.save_invoice_payment_term(
      'd2000000-0000-0000-0000-000000000001', 1, null, 'Bad Term', 'net_days', 400)$$,
  '23514', null, 'a net term needs a day count of 365 or fewer'
);

select throws_ok(
  $$select public.save_invoice_payment_term(
      'd2000000-0000-0000-0000-000000000001', 1, null, 'x', 'net_days', 30)$$,
  '23514', null, 'a one-character name is refused'
);

-- 3. save_invoice_payment_term: edit + protected-term rules --------------------------------------------------

-- The "expected" side deliberately looks the term up by what does NOT change in this call (its pre-rename
-- name / its protected rule identity), not by the new name the same statement is giving it -- a subquery
-- keyed on the new name races the rename's own side effect within one statement and reads back NULL.

select is(
  public.save_invoice_payment_term(
    'd2000000-0000-0000-0000-000000000001', 1,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21'),
    'Net 21 (renamed)', 'net_days', 25
  ) ->> 'term_id',
  (select id::text from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21'),
  'editing a term by id renames it and updates its day count'
);

select is(
  public.save_invoice_payment_term(
    'd2000000-0000-0000-0000-000000000001', 2,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and rule = 'on_receipt' and is_protected),
    'Due right away', 'on_receipt', null
  ) ->> 'term_id',
  (select id::text from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001' and rule = 'on_receipt' and is_protected),
  'a protected term may be renamed'
);

select throws_ok(
  format(
    $$select public.save_invoice_payment_term(
        'd2000000-0000-0000-0000-000000000001', 3, %L, 'Not receipt anymore', 'net_days', 10)$$,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and rule = 'on_receipt' and is_protected)
  ),
  '23514', null, 'a protected term''s timing rule cannot be changed'
);

select throws_ok(
  $$select public.save_invoice_payment_term(
      'd2000000-0000-0000-0000-000000000001', 9, null, 'Stale Create', 'net_days', 14)$$,
  'P0409', null, 'a save against the wrong expected revision is refused'
);

-- 4. set_organization_invoice_defaults -----------------------------------------------------------------------

select is(
  (public.set_organization_invoice_defaults(
    'd2000000-0000-0000-0000-000000000001', 3,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21 (renamed)'),
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 30')
  ) ->> 'invoice_settings_revision')::integer,
  4,
  'setting both defaults to live terms succeeds and bumps the revision'
);

select is(
  (select residential.name || '/' || commercial.name
   from public.organization_settings as settings
   join public.invoice_payment_terms as residential
     on residential.organization_id = settings.organization_id
    and residential.id = settings.invoice_default_term_residential_id
   join public.invoice_payment_terms as commercial
     on commercial.organization_id = settings.organization_id
    and commercial.id = settings.invoice_default_term_commercial_id
   where settings.organization_id = 'd2000000-0000-0000-0000-000000000001'),
  'Net 21 (renamed)/Net 30',
  'the residential and commercial defaults are independently stored'
);

select throws_ok(
  $$select public.set_organization_invoice_defaults(
      'd2000000-0000-0000-0000-000000000001', 4,
      null,
      (select id from public.invoice_payment_terms
       where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 30'))$$,
  '23514', null, 'both defaults are required -- neither may be left blank'
);

select throws_ok(
  format(
    $$select public.set_organization_invoice_defaults(
        'd2000000-0000-0000-0000-000000000001', 4, %L, %L)$$,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000002' limit 1),
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 30')
  ),
  '23514', null, 'a term id belonging to another organization is not a valid default'
);

-- 5. remove_invoice_payment_term: archive + fallback -----------------------------------------------------------

select is(
  public.remove_invoice_payment_term(
    'd2000000-0000-0000-0000-000000000001', 4,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21 (renamed)')
  ) ->> 'term_id',
  (select id::text from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21 (renamed)'),
  'removing the term currently used as the residential default is accepted'
);

select is(
  (select archived_at is not null from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Net 21 (renamed)'),
  true,
  'removal archives the row rather than deleting it'
);

select is(
  (select receipt_term.name
   from public.organization_settings as settings
   join public.invoice_payment_terms as receipt_term
     on receipt_term.organization_id = settings.organization_id
    and receipt_term.id = settings.invoice_default_term_residential_id
   where settings.organization_id = 'd2000000-0000-0000-0000-000000000001'),
  'Due right away',
  'the orphaned residential default falls back to the protected receipt term'
);

select throws_ok(
  format(
    $$select public.remove_invoice_payment_term(
        'd2000000-0000-0000-0000-000000000001', 5, %L)$$,
    (select id from public.invoice_payment_terms
     where organization_id = 'd2000000-0000-0000-0000-000000000001' and name = 'Due right away')
  ),
  '23514', null, 'a protected term cannot be removed'
);

-- 6. Permission and isolation -------------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000002', true);

select throws_ok(
  $$select public.save_invoice_payment_term(
      'd2000000-0000-0000-0000-000000000001', 5, null, 'Field Attempt', 'net_days', 10)$$,
  '42501', null, 'a field member can read payment terms but cannot change them'
);

select ok(
  (select count(*) from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001') > 0,
  'every contractor role can read their own organization''s payment terms'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000003', true);

select is(
  (select count(*)::integer from public.invoice_payment_terms
   where organization_id = 'd2000000-0000-0000-0000-000000000001'),
  0,
  'another organization sees none of these payment terms'
);

select throws_ok(
  $$select public.save_invoice_payment_term(
      'd2000000-0000-0000-0000-000000000001', 5, null, 'Outsider Attempt', 'net_days', 10)$$,
  '42501', null, 'an outsider with no membership cannot change another organization''s terms'
);

select * from finish();
