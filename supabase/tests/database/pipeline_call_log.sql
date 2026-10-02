-- Pipeline E4: logging a call from a card's Brief.
-- Written for `supabase test db`; run it as one transaction rolled back at the end, the convention
-- `tenant_isolation.sql` documents. `set local role` and `set_config` do not survive a statement-by-statement runner.
begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- Privileges ----------------------------------------------------------------------------------------------

select is(
  has_function_privilege('anon', 'public.pipeline_log_opportunity_call(uuid, text, text)', 'execute'),
  false, 'anonymous callers cannot log a call'
);
select is(
  has_function_privilege('authenticated', 'public.pipeline_log_opportunity_call(uuid, text, text)', 'execute'),
  true, 'authenticated members can call the log function'
);
select is(
  has_table_privilege('authenticated', 'public.opportunity_call_logs', 'insert'),
  false, 'members cannot write the call history directly'
);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('e4000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e4-admin-a@example.test', 'test', now(), now(), now()),
  ('e4000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e4-admin-b@example.test', 'test', now(), now(), now()),
  ('e4000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'e4-field-a@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values
  ('e4100000-0000-0000-0000-000000000001', 'E4 Call Org A', 'e4-call-org-a', 'active'),
  ('e4100000-0000-0000-0000-000000000002', 'E4 Call Org B', 'e4-call-org-b', 'active');

insert into public.organization_members (organization_id, user_id, role)
values
  ('e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'admin'),
  ('e4100000-0000-0000-0000-000000000002', 'e4000000-0000-0000-0000-000000000002', 'admin'),
  ('e4100000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000003', 'field');

insert into public.clients (id, organization_id, display_name)
values ('e4200000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-000000000001', 'E4 Client A');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('e4300000-0000-0000-0000-000000000001', 'e4100000-0000-0000-0000-000000000001', 'e4200000-0000-0000-0000-000000000001', '1 Call Street', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title, status)
select
  ('e4400000-0000-0000-0000-00000000000' || n)::uuid,
  'e4100000-0000-0000-0000-000000000001',
  'e4200000-0000-0000-0000-000000000001',
  'e4300000-0000-0000-0000-000000000001',
  'E4 Request R' || n,
  'new'
from generate_series(1, 5) as n;

-- Five cards that have made no real progress for eight days.
delete from public.opportunities where organization_id = 'e4100000-0000-0000-0000-000000000001';

insert into public.opportunities (
  organization_id, client_id, property_id, request_id, title, stage_entered_at, progress_at
)
select
  organization_id, client_id, property_id, id, title,
  now() - interval '10 days', now() - interval '8 days'
from public.requests
where organization_id = 'e4100000-0000-0000-0000-000000000001';

create temporary table e4_cards as
select
  right(title, 1)::int as n,
  id
from public.opportunities
where organization_id = 'e4100000-0000-0000-0000-000000000001';
grant select on e4_cards to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e4000000-0000-0000-0000-000000000001', true);

-- The calls whose clock is read in a later statement: a statement does not see its own function's writes.
do $do$
begin
  perform public.pipeline_log_opportunity_call((select id from e4_cards where n = 2), 'left_voicemail', null);
  perform public.pipeline_log_opportunity_call((select id from e4_cards where n = 4), 'busy', null);
  perform public.pipeline_log_opportunity_call((select id from e4_cards where n = 5), 'wrong_number', null);
end
$do$;

-- 1. Calls that reached the customer restart the clock ------------------------------------------------------

select is(
  (select restarted_progress from public.pipeline_log_opportunity_call((select id from e4_cards where n = 1), 'connected', 'Booked a visit')),
  true, 'a connected call reports that it restarted the clock'
);
select is(
  (select progress_at from public.opportunities where id = (select id from e4_cards where n = 1)),
  now(), 'a connected call restarts the inactivity clock'
);
select is(
  (select progress_at from public.opportunities where id = (select id from e4_cards where n = 2)),
  now(), 'leaving a voicemail restarts the inactivity clock'
);

-- 2. Calls that did not get through do not -------------------------------------------------------------------

select is(
  (select restarted_progress from public.pipeline_log_opportunity_call((select id from e4_cards where n = 3), 'no_answer', null)),
  false, 'no answer reports that it did not restart the clock'
);
select is(
  (select progress_at from public.opportunities where id = (select id from e4_cards where n = 3)),
  now() - interval '8 days', 'no answer leaves the inactivity clock alone'
);
select is(
  (select progress_at from public.opportunities where id = (select id from e4_cards where n = 4)),
  now() - interval '8 days', 'a busy line leaves the inactivity clock alone'
);
select is(
  (select progress_at from public.opportunities where id = (select id from e4_cards where n = 5)),
  now() - interval '8 days', 'a wrong number leaves the inactivity clock alone'
);

-- 3. The history ---------------------------------------------------------------------------------------------

select is(
  (select count(*) from public.opportunity_call_logs where organization_id = 'e4100000-0000-0000-0000-000000000001'),
  5::bigint, 'every logged call is kept, including the ones that did not restart the clock'
);
select is(
  (select note from public.opportunity_call_logs where opportunity_id = (select id from e4_cards where n = 1)),
  'Booked a visit', 'the note is saved with the call'
);
select is(
  (select logged_by from public.opportunity_call_logs where opportunity_id = (select id from e4_cards where n = 1)),
  'e4000000-0000-0000-0000-000000000001'::uuid, 'the call records who logged it'
);

-- 4. What is refused -------------------------------------------------------------------------------------------

select throws_ok(
  format($f$select * from public.pipeline_log_opportunity_call(%L, 'answered', null)$f$, (select id from e4_cards where n = 1)),
  '23514', null, 'an outcome outside the five is refused'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format($f$select * from public.pipeline_log_opportunity_call(%L, 'connected', null)$f$, (select id from e4_cards where n = 1)),
  '42501', null, 'another organization cannot log a call on this card'
);
select is(
  (select count(*) from public.opportunity_call_logs),
  0::bigint, 'another organization cannot read this organization''s calls'
);

select set_config('request.jwt.claim.sub', 'e4000000-0000-0000-0000-000000000003', true);
select throws_ok(
  format($f$select * from public.pipeline_log_opportunity_call(%L, 'connected', null)$f$, (select id from e4_cards where n = 1)),
  '42501', null, 'a member without pipeline.edit cannot log a call'
);

select * from finish();
rollback;
