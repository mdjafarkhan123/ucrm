-- Sales Pipeline, Part 3A: the Task foundation.
-- A Task is an internal follow-up item: a title, optional instructions, one assignee, one due date, and
-- an open or completed state. It is not a Job, a Visit, or an Event, and it sends nothing to a client.
--
-- The table is deliberately not called an opportunity task. Everything Schedule will later need -- who it
-- belongs to, when it is due, whether it is done -- lives on the row itself, so Schedule reads this same
-- table rather than a Pipeline-shaped copy of it. The only Pipeline-specific thing here is which record a
-- Task currently hangs off, and that is one column, so Part 5 can move a Task from a Request card to its
-- Quote card with a single update.
--
-- Two rules must survive concurrent requests and retries, so both live here rather than in an API route:
-- an Opportunity may hold at most five open and five completed Tasks, and only a real teammate who can
-- see the Pipeline may be given one.

-- 1. Table -----------------------------------------------------------------------------------------------

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_id uuid not null,
  title text not null check (char_length(trim(title)) between 2 and 160),
  instructions text check (instructions is null or char_length(instructions) <= 2000),
  -- Optional on purpose: Jobber lets a Task exist before anyone has been made responsible for it.
  -- Points at the user rather than the membership row, so a Task keeps its history when someone leaves.
  assignee_user_id uuid references auth.users(id) on delete set null,
  -- Also optional. The card-priority rule below has a "no due dates at all" case, which only exists
  -- because a Task without a due date is normal.
  due_on date check (due_on is null or due_on between date '2000-01-01' and date '2100-01-01'),
  status text not null default 'open' check (status in ('open', 'completed')),
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Keeps a future child table tenant-safe the same way opportunities does.
  constraint tasks_organization_id_unique unique (organization_id, id),
  -- Tenant-safe parent: a Task can never point at another organization's Opportunity, and it goes when
  -- the Opportunity goes.
  constraint tasks_opportunity_organization_fk foreign key (organization_id, opportunity_id)
    references public.opportunities(organization_id, id) on delete cascade,
  -- An open Task has no completion evidence and a completed one always has a time. The person is allowed
  -- to be null only because a deleted account clears it.
  constraint tasks_completion_consistent check (
    (status = 'open' and completed_at is null and completed_by is null)
    or (status = 'completed' and completed_at is not null)
  )
);

comment on table public.tasks is
  'Internal follow-up items. Members may read this table, never write it: every write goes through the '
  'pipeline_*_task security definer functions, which check the caller''s pipeline.edit permission and '
  'enforce the five-open and five-completed limits under a lock on the parent opportunity. A Task is not '
  'a Job, Visit, or Event, and the Schedule domain is expected to read this same table.';

-- 2. Indexes ---------------------------------------------------------------------------------------------

-- The Brief's open list and the card's single Task are the same question asked twice, so one index answers
-- both. The column order is Jobber's priority rule, written down once: earliest due date first, undated
-- Tasks last, ties broken by creation order. An ascending index puts nulls last, which is exactly the
-- "order by due_on nulls last, created_at, id" the readers use.
create index tasks_opportunity_open_idx
  on public.tasks(organization_id, opportunity_id, due_on, created_at, id)
  where status = 'open';

-- The Brief's COMPLETED section, most recently finished first.
create index tasks_opportunity_completed_idx
  on public.tasks(organization_id, opportunity_id, completed_at desc)
  where status = 'completed';

-- Two jobs, same as the Opportunity owner index: finding one person's Tasks, and the lookup Postgres needs
-- when an auth user is deleted and every assigned row has to be found. Partial, because an unassigned Task
-- is never the answer to either.
create index tasks_assignee_idx
  on public.tasks(assignee_user_id)
  where assignee_user_id is not null;

create trigger tasks_set_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

-- 3. Only a real teammate can be given a Task ------------------------------------------------------------

-- The same rule as Opportunity ownership: being assignable means being able to see the Pipeline. Fires
-- only when the assignee actually changes, so a Task held by someone who has since left is never
-- re-checked and never quietly cleared.
create or replace function private.task_validate_assignee()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if not private.member_has_permission(new.organization_id, new.assignee_user_id, 'pipeline.view') then
    raise exception 'That person cannot be given work on the sales pipeline.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger tasks_validate_assignee
before insert or update of assignee_user_id on public.tasks
for each row
when (new.assignee_user_id is not null)
execute function private.task_validate_assignee();

revoke all on function private.task_validate_assignee() from public;
revoke execute on function private.task_validate_assignee() from anon, authenticated;

-- 4. The shared guard every write goes through -----------------------------------------------------------

-- Resolves the Opportunity, checks the caller, and holds the row until the transaction ends. The lock is
-- what makes the five-Task limit real: two requests arriving together for the same Opportunity are
-- serialised here, so neither can count four and then both insert a fifth. It is the only lock these
-- functions take, so there is no ordering left to get wrong.
create or replace function private.pipeline_lock_task_parent(target_opportunity_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid;
begin
  select opportunity.organization_id
  into target_organization_id
  from public.opportunities as opportunity
  where opportunity.id = target_opportunity_id
  for update;

  -- One answer for "no such card" and "not your card": a stranger learns nothing either way.
  if target_organization_id is null
     or not private.member_has_permission(
       target_organization_id, (select auth.uid()), 'pipeline.edit'
     ) then
    raise exception 'You do not have access to change tasks on this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  return target_organization_id;
end;
$$;

revoke all on function private.pipeline_lock_task_parent(uuid) from public;
revoke execute on function private.pipeline_lock_task_parent(uuid) from anon, authenticated;

-- Counted with the parent already locked, so the number cannot change between the count and the write.
create or replace function private.assert_task_limit(
  target_opportunity_id uuid,
  target_status text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  existing integer;
begin
  select count(*)
  into existing
  from public.tasks as task
  where task.opportunity_id = target_opportunity_id
    and task.status = target_status;

  if existing >= 5 then
    raise exception '%',
      case target_status
        when 'open' then 'This opportunity already has five open tasks. Finish one first.'
        else 'This opportunity already has five completed tasks. Delete one first.'
      end
      using errcode = 'program_limit_exceeded';
  end if;
end;
$$;

revoke all on function private.assert_task_limit(uuid, text) from public;
revoke execute on function private.assert_task_limit(uuid, text) from anon, authenticated;

-- 5. The write boundary ----------------------------------------------------------------------------------

create or replace function public.pipeline_create_opportunity_task(
  target_opportunity_id uuid,
  new_title text,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
)
returns table (
  id uuid,
  opportunity_id uuid,
  title text,
  instructions text,
  assignee_user_id uuid,
  due_on date,
  status text,
  completed_at timestamptz,
  completed_by uuid,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid := private.pipeline_lock_task_parent(target_opportunity_id);
begin
  perform private.assert_task_limit(target_opportunity_id, 'open');

  return query
  insert into public.tasks as task (
    organization_id, opportunity_id, title, instructions, assignee_user_id, due_on, created_by
  )
  values (
    target_organization_id,
    target_opportunity_id,
    new_title,
    nullif(trim(coalesce(new_instructions, '')), ''),
    new_assignee_user_id,
    new_due_on,
    (select auth.uid())
  )
  returning
    task.id, task.opportunity_id, task.title, task.instructions, task.assignee_user_id, task.due_on,
    task.status, task.completed_at, task.completed_by, task.created_by, task.created_at, task.updated_at;
end;
$$;

-- The Brief's edit form sends all four fields together, so this replaces all four. There is no money on a
-- Task, so nothing here needs the "leave it alone" flags the Opportunity write path uses.
create or replace function public.pipeline_update_opportunity_task(
  target_task_id uuid,
  new_title text,
  new_instructions text default null,
  new_assignee_user_id uuid default null,
  new_due_on date default null
)
returns table (
  id uuid,
  opportunity_id uuid,
  title text,
  instructions text,
  assignee_user_id uuid,
  due_on date,
  status text,
  completed_at timestamptz,
  completed_by uuid,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  parent_id uuid;
begin
  select task.opportunity_id into parent_id from public.tasks as task where task.id = target_task_id;
  if parent_id is null then
    raise exception 'You do not have access to change this task.' using errcode = 'insufficient_privilege';
  end if;

  perform private.pipeline_lock_task_parent(parent_id);

  return query
  update public.tasks as task
  set
    title = new_title,
    instructions = nullif(trim(coalesce(new_instructions, '')), ''),
    assignee_user_id = new_assignee_user_id,
    due_on = new_due_on
  where task.id = target_task_id
  returning
    task.id, task.opportunity_id, task.title, task.instructions, task.assignee_user_id, task.due_on,
    task.status, task.completed_at, task.completed_by, task.created_by, task.created_at, task.updated_at;
end;
$$;

-- Complete and reopen are the same decision seen from two sides, so they share one path and one limit
-- check. Reopening is the direction that can breach the open limit, and completing the completed one.
create or replace function public.pipeline_set_task_completed(
  target_task_id uuid,
  is_completed boolean
)
returns table (
  id uuid,
  opportunity_id uuid,
  title text,
  instructions text,
  assignee_user_id uuid,
  due_on date,
  status text,
  completed_at timestamptz,
  completed_by uuid,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  parent_id uuid;
  current_status text;
  wanted_status text := case when is_completed then 'completed' else 'open' end;
begin
  select task.opportunity_id, task.status
  into parent_id, current_status
  from public.tasks as task
  where task.id = target_task_id;

  if parent_id is null then
    raise exception 'You do not have access to change this task.' using errcode = 'insufficient_privilege';
  end if;

  perform private.pipeline_lock_task_parent(parent_id);

  -- Asking for the state it is already in is not an error. A retried request, or two clicks on the same
  -- button, must not spend one of the five slots or move the completion time.
  if current_status = wanted_status then
    return query
    select
      task.id, task.opportunity_id, task.title, task.instructions, task.assignee_user_id, task.due_on,
      task.status, task.completed_at, task.completed_by, task.created_by, task.created_at, task.updated_at
    from public.tasks as task
    where task.id = target_task_id;
    return;
  end if;

  perform private.assert_task_limit(parent_id, wanted_status);

  return query
  update public.tasks as task
  set
    status = wanted_status,
    completed_at = case when is_completed then now() end,
    completed_by = case when is_completed then (select auth.uid()) end
  where task.id = target_task_id
  returning
    task.id, task.opportunity_id, task.title, task.instructions, task.assignee_user_id, task.due_on,
    task.status, task.completed_at, task.completed_by, task.created_by, task.created_at, task.updated_at;
end;
$$;

create or replace function public.pipeline_delete_task(target_task_id uuid)
returns table (id uuid, opportunity_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  parent_id uuid;
begin
  select task.opportunity_id into parent_id from public.tasks as task where task.id = target_task_id;
  if parent_id is null then
    raise exception 'You do not have access to change this task.' using errcode = 'insufficient_privilege';
  end if;

  perform private.pipeline_lock_task_parent(parent_id);

  return query
  delete from public.tasks as task
  where task.id = target_task_id
  returning task.id, task.opportunity_id;
end;
$$;

revoke all on function public.pipeline_create_opportunity_task(uuid, text, text, uuid, date) from public;
revoke all on function public.pipeline_update_opportunity_task(uuid, text, text, uuid, date) from public;
revoke all on function public.pipeline_set_task_completed(uuid, boolean) from public;
revoke all on function public.pipeline_delete_task(uuid) from public;

revoke execute on function public.pipeline_create_opportunity_task(uuid, text, text, uuid, date) from anon;
revoke execute on function public.pipeline_update_opportunity_task(uuid, text, text, uuid, date) from anon;
revoke execute on function public.pipeline_set_task_completed(uuid, boolean) from anon;
revoke execute on function public.pipeline_delete_task(uuid) from anon;

grant execute on function public.pipeline_create_opportunity_task(uuid, text, text, uuid, date)
  to authenticated;
grant execute on function public.pipeline_update_opportunity_task(uuid, text, text, uuid, date)
  to authenticated;
grant execute on function public.pipeline_set_task_completed(uuid, boolean) to authenticated;
grant execute on function public.pipeline_delete_task(uuid) to authenticated;

-- 6. Row level security ----------------------------------------------------------------------------------

alter table public.tasks enable row level security;

create policy "permitted members can view tasks"
on public.tasks for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.view')
);

-- No insert, update, or delete policy, and no write grant. Members read this table and nothing more; the
-- definer functions above are the only way anything changes, and they check pipeline.edit themselves.
revoke all on public.tasks from anon;
revoke all on public.tasks from authenticated;

grant select on public.tasks to authenticated;
