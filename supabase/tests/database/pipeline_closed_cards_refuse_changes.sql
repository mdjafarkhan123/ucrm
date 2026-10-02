-- Pipeline G2: a Won or Lost card refuses the Brief's commands (20261006110000).
-- Written for `supabase test db`; run it as one transaction rolled back at the end, the convention
-- `tenant_isolation.sql` documents. `set local role` and `set_config` do not survive a statement-by-statement runner.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('92000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'g2-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('92100000-0000-0000-0000-000000000001', 'G2 Closed Card Org', 'g2-closed-card-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('92100000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('92200000-0000-0000-0000-000000000001', '92100000-0000-0000-0000-000000000001', 'G2 Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('92300000-0000-0000-0000-000000000001', '92100000-0000-0000-0000-000000000001', '92200000-0000-0000-0000-000000000001', '1 Closed Street', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title, status)
select
  ('92400000-0000-0000-0000-00000000000' || n)::uuid,
  '92100000-0000-0000-0000-000000000001',
  '92200000-0000-0000-0000-000000000001',
  '92300000-0000-0000-0000-000000000001',
  'G2 Request R' || n,
  'new'
from generate_series(1, 3) as n;

-- Card 1 stays open; card 2 is marked Lost by the real command below; card 3's Request is converted, which
-- takes its card off the board without an outcome.
delete from public.opportunities where organization_id = '92100000-0000-0000-0000-000000000001';

insert into public.opportunities (organization_id, client_id, property_id, request_id, title, estimated_value)
select organization_id, client_id, property_id, id, title, 500
from public.requests
where organization_id = '92100000-0000-0000-0000-000000000001';

create temporary table g2_cards as
select right(title, 1)::int as n, id
from public.opportunities
where organization_id = '92100000-0000-0000-0000-000000000001';
grant select on g2_cards to authenticated;

create temporary table g2_made (kind text, id uuid);
grant all on g2_made to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '92000000-0000-0000-0000-000000000001', true);

-- Work done while card 2 is still open: one Task left open, one finished by a person, and one Note.
do $do$
declare
  open_task uuid;
  done_task uuid;
  note_id uuid;
begin
  select id into open_task
  from public.pipeline_create_opportunity_task((select id from g2_cards where n = 2), 'Left open');
  select id into done_task
  from public.pipeline_create_opportunity_task((select id from g2_cards where n = 2), 'Finished by hand');
  perform public.pipeline_set_task_completed(done_task, true);
  select id into note_id
  from public.pipeline_create_opportunity_note((select id from g2_cards where n = 2), 'request', 'Written while open');

  insert into g2_made values ('open_task', open_task), ('done_task', done_task), ('note', note_id);

  perform public.pipeline_mark_opportunity_lost(
    (select id from g2_cards where n = 2), 'g2-closed-card-lost', null, null, now()
  );
end
$do$;

-- Members cannot read every column of a card directly, so the card itself is read as the table's owner.
set local role postgres;
select is(
  (select outcome from public.opportunities where id = (select id from g2_cards where n = 2)),
  'lost', 'the fixture card is Lost'
);
set local role authenticated;

-- 1. An open card still takes every change -----------------------------------------------------------------

select lives_ok(
  $$select * from public.pipeline_update_opportunity_details(
      target_opportunity_id => (select id from g2_cards where n = 1),
      set_value => true, new_estimated_value => 750)$$,
  'an open card''s value can be changed'
);
select lives_ok(
  $$select * from public.pipeline_create_opportunity_task((select id from g2_cards where n = 1), 'Call back')$$,
  'an open card takes a new Task'
);
select lives_ok(
  $$select * from public.pipeline_create_opportunity_note((select id from g2_cards where n = 1), 'request', 'Hello')$$,
  'an open card takes a new Note'
);

-- 2. A closed card refuses its details -----------------------------------------------------------------------

select throws_ok(
  $$select * from public.pipeline_update_opportunity_details(
      target_opportunity_id => (select id from g2_cards where n = 2),
      set_value => true, new_estimated_value => 1)$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Lost card''s frozen value cannot be rewritten'
);
select throws_ok(
  $$select * from public.pipeline_update_opportunity_details(
      target_opportunity_id => (select id from g2_cards where n = 2),
      set_owner => true, new_owner_user_id => '92000000-0000-0000-0000-000000000001')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Lost card cannot be given to another owner'
);
select throws_ok(
  $$select * from public.pipeline_update_opportunity_details(
      target_opportunity_id => (select id from g2_cards where n = 2),
      set_expected_close => true, new_expected_close_on => '2027-01-01')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Lost card''s expected close cannot be changed'
);
set local role postgres;
select is(
  (select estimated_value from public.opportunities where id = (select id from g2_cards where n = 2)),
  500::numeric, 'the Lost card''s value is what it was'
);
set local role authenticated;

-- 3. A closed card refuses new Task work, but leftovers can be cleared ----------------------------------------

select throws_ok(
  $$select * from public.pipeline_create_opportunity_task((select id from g2_cards where n = 2), 'New work')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Lost card takes no new Task'
);
select throws_ok(
  $$select * from public.pipeline_update_opportunity_task((select id from g2_made where kind = 'done_task'), 'Renamed')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Task on a Lost card cannot be edited'
);
select throws_ok(
  $$select * from public.pipeline_set_task_completed((select id from g2_made where kind = 'done_task'), false)$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a finished Task on a Lost card cannot be started again'
);
select lives_ok(
  $$select * from public.pipeline_set_task_completed((select id from g2_made where kind = 'open_task'), true)$$,
  'asking to finish a Task the Lost action already finished is not an error'
);
select lives_ok(
  $$select * from public.pipeline_delete_task((select id from g2_made where kind = 'open_task'))$$,
  'a Task on a Lost card can still be deleted'
);
select throws_ok(
  $$select public.pipeline_bulk_update(array[(select id from g2_cards where n = 2)], 'nonsense')$$,
  '22023', 'Unknown bulk change.',
  'the bulk command still checks its own inputs first'
);
select is(
  (select string_agg(item ->> 'status', ',' order by item ->> 'status')
   from jsonb_array_elements(public.pipeline_bulk_update(
     array[(select id from g2_cards where n = 1), (select id from g2_cards where n = 2)], 'owner'
   )) as item),
  'done,refused', 'a bulk owner change does the open card and refuses the closed one'
);

-- 4. A closed card refuses Notes through the Pipeline -----------------------------------------------------------

select throws_ok(
  $$select * from public.pipeline_create_opportunity_note((select id from g2_cards where n = 2), 'request', 'Late note')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Lost card takes no new Note from the Brief'
);
select throws_ok(
  $$select * from public.pipeline_update_opportunity_note(
      (select id from g2_made where kind = 'note'), (select id from g2_cards where n = 2), 'Rewritten')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Note on a Lost card cannot be edited from the Brief'
);
select throws_ok(
  $$select * from public.pipeline_delete_opportunity_note(
      (select id from g2_made where kind = 'note'), (select id from g2_cards where n = 2), 'request')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a Note on a Lost card cannot be deleted from the Brief'
);

-- 5. A call can still be logged; it never restarts a closed card's clock ----------------------------------------

select lives_ok(
  $$select * from public.pipeline_log_opportunity_call((select id from g2_cards where n = 2), 'connected', null)$$,
  'a call can still be logged against a Lost card'
);

-- 6. A card that left the board without an outcome is refused too ------------------------------------------------

set local role postgres;
update public.requests set status = 'converted' where id = '92400000-0000-0000-0000-000000000003';
select is(
  (select stage || '/' || outcome from public.opportunities where id = (select id from g2_cards where n = 3)),
  'request_closed/open', 'a converted Request''s card is off the board and has no outcome'
);
set local role authenticated;

select throws_ok(
  $$select * from public.pipeline_create_opportunity_task((select id from g2_cards where n = 3), 'Dangling')$$,
  '23514', 'This card has left the board, so it can no longer be changed here.',
  'a card that left the board without an outcome takes no new Task'
);

select * from finish();
rollback;
