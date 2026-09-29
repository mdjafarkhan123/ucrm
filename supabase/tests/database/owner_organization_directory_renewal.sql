-- Package builder P4b: the directory's renewal_due and payment_overdue flags read the paid-through date.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

set local role postgres;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
select ('90000000-2222-0000-0000-00000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', 'p4b-renewal-owner-' || n || '@example.test', 'test', now(), now(), now()
from generate_series(1, 6) as n;

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('90000000-0000-0000-2222-000000000001', 'P4b Renewal Soon', 'p4b-renewal-soon', 'active'),
  ('90000000-0000-0000-2222-000000000002', 'P4b Renewal Today', 'p4b-renewal-today', 'active'),
  ('90000000-0000-0000-2222-000000000003', 'P4b Renewal Week Away', 'p4b-renewal-week-away', 'active'),
  ('90000000-0000-0000-2222-000000000004', 'P4b Renewal In Grace', 'p4b-renewal-in-grace', 'active'),
  ('90000000-0000-0000-2222-000000000005', 'P4b Renewal Grace Ended', 'p4b-renewal-grace-ended', 'active'),
  ('90000000-0000-0000-2222-000000000006', 'P4b Renewal Free Access', 'p4b-renewal-free-access', 'active');

insert into public.organization_members (organization_id, user_id, role)
select ('90000000-0000-0000-2222-00000000000' || n)::uuid, ('90000000-2222-0000-0000-00000000000' || n)::uuid, 'owner'
from generate_series(1, 6) as n;

-- Grace ends seven days after paid-through, as the ledger sets it.
insert into public.organization_commercial_state
  (organization_id, paid_through_date, paid_through_source, grace_ends_at, grace_basis_timezone)
values
  ('90000000-0000-0000-2222-000000000001', current_date + 3, 'renewal', now() + interval '10 days', 'UTC'),
  ('90000000-0000-0000-2222-000000000002', current_date, 'renewal', now() + interval '7 days', 'UTC'),
  ('90000000-0000-0000-2222-000000000003', current_date + 7, 'renewal', now() + interval '14 days', 'UTC'),
  ('90000000-0000-0000-2222-000000000004', current_date - 2, 'renewal', now() + interval '5 days', 'UTC'),
  ('90000000-0000-0000-2222-000000000005', current_date - 10, 'renewal', now() - interval '3 days', 'UTC'),
  ('90000000-0000-0000-2222-000000000006', current_date + 3, 'renewal', now() + interval '10 days', 'UTC');

insert into public.organization_free_access_events (organization_id, action, starts_at, access_until_date, reason)
values ('90000000-0000-0000-2222-000000000006', 'grant', current_date - 5, null, 'P4b test fixture: open-ended grant');

reset role;

create temporary table fixture_directory as
select public.owner_organization_directory('p4b-renewal', null, null, null, 50) as result;

create function pg_temp.reasons(org_id text) returns jsonb language sql as $$
  select org -> 'attention_reasons'
  from fixture_directory, jsonb_array_elements(result -> 'organizations') as org
  where org ->> 'id' = org_id
$$;

select is(pg_temp.reasons('90000000-0000-0000-2222-000000000001'), '["renewal_due"]'::jsonb,
  'paid through three days from now is renewal_due');
select is(pg_temp.reasons('90000000-0000-0000-2222-000000000002'), '["renewal_due"]'::jsonb,
  'paid through today (renews tomorrow) is renewal_due');
select is(pg_temp.reasons('90000000-0000-0000-2222-000000000003'), '[]'::jsonb,
  'paid through seven days from now is not yet flagged');
select is(pg_temp.reasons('90000000-0000-0000-2222-000000000004'), '["payment_overdue"]'::jsonb,
  'paid-through passed but still inside the grace week is payment_overdue, not access_overdue');
select is(pg_temp.reasons('90000000-0000-0000-2222-000000000005'), '["access_overdue"]'::jsonb,
  'once grace ends unpaid the organization is access_overdue only');
select is(pg_temp.reasons('90000000-0000-0000-2222-000000000006'), '[]'::jsonb,
  'an organization on free access is not asked to renew');

select is((select (result -> 'totals' -> 'attention' ->> 'renewal_due')::int from fixture_directory) >= 2, true,
  'the renewal_due total counts the flagged organizations');
select is(
  (select (public.owner_organization_directory('p4b-renewal', 'renewal_due', null, null, 50) -> 'totals' ->> 'matching')::int),
  2, 'filtering by renewal_due returns only those organizations');
select is(
  (select (public.owner_organization_directory('p4b-renewal', 'payment_overdue', null, null, 50) -> 'totals' ->> 'matching')::int),
  1, 'filtering by payment_overdue returns only the organization in its grace week');

select * from finish();
rollback;
