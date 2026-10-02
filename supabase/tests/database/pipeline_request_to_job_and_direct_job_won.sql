-- Pipeline G2: a Request turned straight into a Job is Won once (B1, 20261002090000), and a Job made from
-- scratch is a closed-only Direct job counted apart from Won (B2, 20261002100000).
-- Written for `supabase test db`; run it as one transaction rolled back at the end, the convention
-- `tenant_isolation.sql` documents. `set local role` and `set_config` do not survive a statement-by-statement runner.
begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'g2-won-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c2100000-0000-0000-0000-000000000001', 'G2 Won Org', 'g2-won-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('c2100000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values
  ('c2200000-0000-0000-0000-000000000001', 'c2100000-0000-0000-0000-000000000001', 'G2 Won Client'),
  ('c2200000-0000-0000-0000-000000000002', 'c2100000-0000-0000-0000-000000000001', 'G2 Other Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values
  ('c2300000-0000-0000-0000-000000000001', 'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001', '1 Won Street', 'Testville'),
  ('c2300000-0000-0000-0000-000000000002', 'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000002', '2 Won Street', 'Testville');

-- R1 becomes a Job. R2 is archived, so it cannot. R3 belongs to the first client and is asked for by the second.
insert into public.requests (id, organization_id, client_id, property_id, title, status)
values
  ('c2400000-0000-0000-0000-000000000001', 'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001', 'c2300000-0000-0000-0000-000000000001', 'G2 Won Request R1', 'new'),
  ('c2400000-0000-0000-0000-000000000002', 'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001', 'c2300000-0000-0000-0000-000000000001', 'G2 Won Request R2', 'archived'),
  ('c2400000-0000-0000-0000-000000000003', 'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001', 'c2300000-0000-0000-0000-000000000001', 'G2 Won Request R3', 'new');

-- One priced line, untaxed, so the job total is the line total.
create temporary table g2_scope as
select
  '[{"position":0,"line_kind":"priced","category":"service","name":"Work","quantity":2,"unit_price_minor":15000,"unit_cost_minor":4000,"is_taxable":false}]'::jsonb as direct_lines,
  '[{"position":0,"line_kind":"priced","category":"service","name":"Work","quantity":1,"unit_price_minor":45000,"unit_cost_minor":4000,"is_taxable":false}]'::jsonb as request_lines,
  jsonb_build_array(jsonb_build_object('position', 0, 'visit_date', null, 'all_day', false)) as one_visit;
grant select on g2_scope to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c2000000-0000-0000-0000-000000000001', true);

-- 1. A Job made from scratch is a Direct job ---------------------------------------------------------------

select is(
  (public.create_job_with_visits(
    'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001',
    'c2300000-0000-0000-0000-000000000001', 'G2 Direct job', null, true,
    (select direct_lines from g2_scope), (select one_visit from g2_scope),
    'g2-idem-direct-1', 'g2-hash-direct-1'
  ))->>'applied',
  'true', 'a job with no Request and no Quote is created'
);

set local role postgres;
select is(
  (select count(*)::int from public.opportunities
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and job_id is not null),
  1, 'it gets exactly one Pipeline record of its own'
);
select is(
  (select outcome || ' / ' || outcome_kind || ' / ' || stage from public.opportunities
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and job_id is not null),
  'won / direct_job / request_closed',
  'the record is closed from birth, labelled Direct job, and holds no place on the board'
);
select is(
  (select estimated_value from public.opportunities
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and job_id is not null),
  300.00, 'its value is frozen from the job total'
);
select is(
  (select count(*)::int from public.opportunities
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and outcome_kind = 'won'),
  0, 'a Direct job is not counted among Won deals'
);
set local role authenticated;

-- 2. A Request turned straight into a Job is Won ----------------------------------------------------------

select is(
  (public.create_job_with_visits(
    'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001',
    'c2300000-0000-0000-0000-000000000001', 'G2 Job from request', null, true,
    (select request_lines from g2_scope), (select one_visit from g2_scope),
    'g2-idem-request-1', 'g2-hash-request-1', 'one_off', false, null,
    'c2400000-0000-0000-0000-000000000001'
  ))->>'applied',
  'true', 'the Request is converted to a Job'
);

set local role postgres;
select is(
  (select status from public.requests where id = 'c2400000-0000-0000-0000-000000000001'),
  'converted', 'the Request becomes Converted'
);
select is(
  (select outcome || ' / ' || outcome_kind || ' / ' || stage from public.opportunities
   where request_id = 'c2400000-0000-0000-0000-000000000001'),
  'won / won / request_closed', 'its card is Won and leaves the board'
);
select is(
  (select estimated_value from public.opportunities where request_id = 'c2400000-0000-0000-0000-000000000001'),
  450.00, 'the Won value is frozen from the job total'
);
select is(
  (select request_id from public.jobs
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and title = 'G2 Job from request'),
  'c2400000-0000-0000-0000-000000000001'::uuid, 'the Job remembers the Request it came from'
);
select is(
  (select count(*)::int from public.opportunities
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and job_id is not null),
  1, 'a Job made from a Request adds no Direct job record'
);
select is(
  (select count(*)::int from public.opportunity_outcome_events as event
   join public.opportunities as opportunity on opportunity.id = event.opportunity_id
   where opportunity.request_id = 'c2400000-0000-0000-0000-000000000001' and event.event_type = 'won'),
  1, 'one Won event is recorded'
);
set local role authenticated;

-- 3. It is Won once ----------------------------------------------------------------------------------------

select is(
  (public.create_job_with_visits(
    'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001',
    'c2300000-0000-0000-0000-000000000001', 'G2 Job from request', null, true,
    (select request_lines from g2_scope), (select one_visit from g2_scope),
    'g2-idem-request-1', 'g2-hash-request-1', 'one_off', false, null,
    'c2400000-0000-0000-0000-000000000001'
  ))->>'applied',
  'false', 'the same request sent again is answered as already done'
);

select throws_ok(
  $$select public.create_job_with_visits(
      'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001',
      'c2300000-0000-0000-0000-000000000001', 'G2 Second job from request', null, true,
      (select request_lines from g2_scope), (select one_visit from g2_scope),
      'g2-idem-request-2', 'g2-hash-request-2', 'one_off', false, null,
      'c2400000-0000-0000-0000-000000000001')$$,
  'P0409', 'This request has already been converted.',
  'a second Job cannot be made from the same Request'
);

set local role postgres;
select is(
  (select count(*)::int from public.opportunity_outcome_events as event
   join public.opportunities as opportunity on opportunity.id = event.opportunity_id
   where opportunity.request_id = 'c2400000-0000-0000-0000-000000000001' and event.event_type = 'won'),
  1, 'still one Won event after the retry and the refused second Job'
);
select is(
  (select count(*)::int from public.jobs
   where organization_id = 'c2100000-0000-0000-0000-000000000001' and request_id is not null),
  1, 'and still one Job for that Request'
);
set local role authenticated;

-- 4. What cannot become a Job -------------------------------------------------------------------------------

select throws_ok(
  $$select public.create_job_with_visits(
      'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000001',
      'c2300000-0000-0000-0000-000000000001', 'G2 Job from archived request', null, true,
      (select request_lines from g2_scope), (select one_visit from g2_scope),
      'g2-idem-request-3', 'g2-hash-request-3', 'one_off', false, null,
      'c2400000-0000-0000-0000-000000000002')$$,
  '23514', 'This request cannot be turned into a job right now.',
  'an archived Request cannot be turned into a Job'
);

select throws_ok(
  $$select public.create_job_with_visits(
      'c2100000-0000-0000-0000-000000000001', 'c2200000-0000-0000-0000-000000000002',
      'c2300000-0000-0000-0000-000000000002', 'G2 Job for the wrong client', null, true,
      (select request_lines from g2_scope), (select one_visit from g2_scope),
      'g2-idem-request-4', 'g2-hash-request-4', 'one_off', false, null,
      'c2400000-0000-0000-0000-000000000003')$$,
  '23514', 'A job made from a request stays with that request''s client.',
  'a Request cannot become another client''s Job'
);

set local role postgres;
select is(
  (select outcome from public.opportunities where request_id = 'c2400000-0000-0000-0000-000000000003'),
  'open', 'a refused conversion leaves the card Open'
);

select * from finish();
rollback;
