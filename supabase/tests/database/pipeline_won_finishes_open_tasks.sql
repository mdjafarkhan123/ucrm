-- Pipeline G2: winning a card finishes its open Tasks, and reopening the win brings them back (20261006140000).
-- Written for `supabase test db`; run it as one transaction rolled back at the end, the convention
-- `tenant_isolation.sql` documents. `set local role` and `set_config` do not survive a statement-by-statement runner.
begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('93000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'g2-won-tasks@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('93100000-0000-0000-0000-000000000001', 'G2 Won Tasks Org', 'g2-won-tasks-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('93100000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('93200000-0000-0000-0000-000000000001', '93100000-0000-0000-0000-000000000001', 'G2 Won Tasks Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('93300000-0000-0000-0000-000000000001', '93100000-0000-0000-0000-000000000001', '93200000-0000-0000-0000-000000000001', '1 Won Street', 'Testville');

insert into public.quotes (id, organization_id, client_id, property_id, quote_number, title, status, currency_code)
values ('93400000-0000-0000-0000-000000000001', '93100000-0000-0000-0000-000000000001', '93200000-0000-0000-0000-000000000001', '93300000-0000-0000-0000-000000000001', 1, 'G2 Won Tasks Quote', 'awaiting_response', 'USD');

-- create_quote inserts this inline; the fixture does the same by hand since that command does not run here.
insert into public.opportunities (organization_id, client_id, property_id, quote_id, title)
select organization_id, client_id, property_id, id, title from public.quotes
where id = '93400000-0000-0000-0000-000000000001';

create temporary table g2_won_card as
select id from public.opportunities where quote_id = '93400000-0000-0000-0000-000000000001';
grant select on g2_won_card to authenticated;

create temporary table g2_won_made (kind text, id uuid);
grant all on g2_won_made to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '93000000-0000-0000-0000-000000000001', true);

-- While the card is open: a dated Task and an undated one left open, and one a person finished.
do $do$
declare
  dated_task uuid;
  undated_task uuid;
  done_task uuid;
begin
  select id into dated_task
  from public.pipeline_create_opportunity_task(
    (select id from g2_won_card), 'Call on Friday', null, null, '2026-10-09'
  );
  select id into undated_task
  from public.pipeline_create_opportunity_task((select id from g2_won_card), 'Send brochure');
  select id into done_task
  from public.pipeline_create_opportunity_task((select id from g2_won_card), 'Finished by hand');
  perform public.pipeline_set_task_completed(done_task, true);

  insert into g2_won_made values ('dated', dated_task), ('undated', undated_task), ('done', done_task);
end
$do$;

set local role postgres;

-- 1. Winning finishes what was left open ---------------------------------------------------------------------

update public.quotes set status = 'approved' where id = '93400000-0000-0000-0000-000000000001';

select is(
  (select outcome from public.opportunities where id = (select id from g2_won_card)),
  'won', 'approving the quote wins its card'
);
select is(
  (select count(*)::int from public.tasks
   where opportunity_id = (select id from g2_won_card) and status = 'open'),
  0, 'no Task is left open on the Won card, dated or undated'
);
select is(
  (select count(*)::int from public.tasks
   where id in (select id from g2_won_made where kind in ('dated', 'undated'))
     and completed_by is null
     and completed_at is not null
     and completed_by_outcome_event_id = (
       select current_outcome_event_id from public.opportunities where id = (select id from g2_won_card)
     )),
  2, 'both are stamped with the Won event and no person''s name'
);
select is(
  (select completed_by::text || ' / ' || coalesce(completed_by_outcome_event_id::text, 'none')
   from public.tasks where id = (select id from g2_won_made where kind = 'done')),
  '93000000-0000-0000-0000-000000000001 / none',
  'the Task a person finished keeps their name and no event'
);
select is(
  (select next_task_due_on from public.opportunities where id = (select id from g2_won_card)),
  null, 'the Won card no longer says a Task is due'
);

-- 2. A Won card takes no new Task, so nothing can pile up behind the win ---------------------------------------

set local role authenticated;
select throws_ok(
  $$select * from public.pipeline_create_opportunity_task((select id from g2_won_card), 'Too late')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Won card takes no new Task'
);
set local role postgres;

-- 3. Reopening the win brings back only what the win finished ---------------------------------------------------

update public.quotes set status = 'draft' where id = '93400000-0000-0000-0000-000000000001';

select is(
  (select outcome from public.opportunities where id = (select id from g2_won_card)),
  'open', 'revising the approved quote reopens its card'
);
select is(
  (select count(*)::int from public.tasks
   where id in (select id from g2_won_made where kind in ('dated', 'undated'))
     and status = 'open'
     and completed_at is null
     and completed_by_outcome_event_id is null),
  2, 'the two Tasks the win finished are open again'
);
select is(
  (select status from public.tasks where id = (select id from g2_won_made where kind = 'done')),
  'completed', 'the Task a person finished stays finished'
);
select is(
  (select next_task_due_on from public.opportunities where id = (select id from g2_won_card)),
  '2026-10-09'::date, 'the card shows its dated Task as due again'
);

-- 4. Winning a second time finishes them again -----------------------------------------------------------------

update public.quotes set status = 'awaiting_response' where id = '93400000-0000-0000-0000-000000000001';
update public.quotes set status = 'approved' where id = '93400000-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.tasks
   where opportunity_id = (select id from g2_won_card) and status = 'open'),
  0, 'a second win finishes the open Tasks again'
);

select * from finish();
rollback;
