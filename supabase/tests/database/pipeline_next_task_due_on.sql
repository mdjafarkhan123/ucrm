-- Pipeline G2: a card's `next_task_due_on` always equals its earliest open Task's due date (C1,
-- 20261002170000). The board sorts and pages on that column, so it must follow every Task change.
-- Written for `supabase test db`; run it as one transaction rolled back at the end, the convention
-- `tenant_isolation.sql` documents. `set local role` and `set_config` do not survive a statement-by-statement runner.
begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- Fixtures ------------------------------------------------------------------------------------------------

set local role postgres;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
)
values
  ('c3000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'g2-next-task-admin@example.test', 'test', now(), now(), now());

insert into public.organizations (id, name, slug, lifecycle_status)
values ('c3100000-0000-0000-0000-000000000001', 'G2 Next Task Org', 'g2-next-task-org', 'active');

insert into public.organization_members (organization_id, user_id, role)
values ('c3100000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'admin');

insert into public.clients (id, organization_id, display_name)
values ('c3200000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'G2 Next Task Client');

insert into public.properties (id, organization_id, client_id, address_line1, city)
values ('c3300000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'c3200000-0000-0000-0000-000000000001', '1 Task Street', 'Testville');

insert into public.requests (id, organization_id, client_id, property_id, title, status)
values ('c3400000-0000-0000-0000-000000000001', 'c3100000-0000-0000-0000-000000000001', 'c3200000-0000-0000-0000-000000000001', 'c3300000-0000-0000-0000-000000000001', 'G2 Next Task Request', 'new');

create temporary table g2_card as
select id, private.organization_today(organization_id) as today
from public.opportunities
where request_id = 'c3400000-0000-0000-0000-000000000001';
grant select on g2_card to authenticated;

create temporary table g2_tasks (name text primary key, id uuid);
grant all on g2_tasks to authenticated;

-- Members cannot read every column of a card directly, so the column is read through the table's owner.
create function pg_temp.next_due() returns date
language sql security definer
as $$ select next_task_due_on from public.opportunities where id = (select id from g2_card) $$;
grant execute on function pg_temp.next_due() to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-0000-0000-000000000001', true);

-- The date follows every Task change ----------------------------------------------------------------------

select is(pg_temp.next_due(), null, 'a card with no Task has no next Task date');

insert into g2_tasks
select 'undated', id from public.pipeline_create_opportunity_task((select id from g2_card), 'No date');
select is(pg_temp.next_due(), null, 'a Task with no date leaves it empty');

insert into g2_tasks
select 'five', id from public.pipeline_create_opportunity_task(
  (select id from g2_card), 'In five days', null, null, (select today + 5 from g2_card));
select is(pg_temp.next_due(), (select today + 5 from g2_card), 'the first dated Task sets it');

insert into g2_tasks
select 'two', id from public.pipeline_create_opportunity_task(
  (select id from g2_card), 'In two days', null, null, (select today + 2 from g2_card));
select is(pg_temp.next_due(), (select today + 2 from g2_card), 'an earlier Task takes it over');

select lives_ok(
  $$select * from public.pipeline_update_opportunity_task(
      (select id from g2_tasks where name = 'two'), 'In nine days', null, null, (select today + 9 from g2_card))$$,
  'the earliest Task is pushed out to nine days'
);
select is(pg_temp.next_due(), (select today + 5 from g2_card), 'the date falls back to the next earliest Task');

select public.pipeline_set_task_completed((select id from g2_tasks where name = 'five'), true);
select is(pg_temp.next_due(), (select today + 9 from g2_card), 'a completed Task no longer counts');

select public.pipeline_set_task_completed((select id from g2_tasks where name = 'five'), false);
select is(pg_temp.next_due(), (select today + 5 from g2_card), 'reopening it brings its date back');

select public.pipeline_delete_task((select id from g2_tasks where name = 'five'));
select is(pg_temp.next_due(), (select today + 9 from g2_card), 'a deleted Task no longer counts');

select public.pipeline_set_task_completed((select id from g2_tasks where name = 'two'), true);
select is(pg_temp.next_due(), null, 'with only an undated Task left open the date is empty again');

select * from finish();
rollback;
