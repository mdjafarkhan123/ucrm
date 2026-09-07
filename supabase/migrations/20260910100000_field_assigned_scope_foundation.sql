-- Jobs, Part 15a-2: narrow the Field role to assigned work only.
--
-- Jobber's field crew sees their own schedule, not the company's job list. Ours has seen every job in the
-- tenant since jobs.view shipped, because jobs.view has only ever meant "all or nothing". This turns on the
-- scope machinery 20260822055549 built and then deliberately left dormant: a permission may declare a
-- scope_model, and a role may hold that permission at a narrower access_scope. jobs.view is the first
-- permission to declare one, and Field is the first role to hold one.
--
-- Jafar was told plainly, and approved, that existing field users lose the company job list.
--
-- Every shipped jobs.view gate has to end up swept, because a single unswept read is a hole that shows a
-- field worker a job they are not on. The sweep runs across four migrations applied in order, rather than
-- one unreviewable wall of SQL, and the order is chosen so that no intermediate state is ever MORE
-- permissive than the state before this part began. Each step only ever takes visibility away:
--
--   1. This file. The assignment carries its job, jobs.view declares a scope_model, Field holds it at
--      'assigned', and private.can_view_job learns the assigned test. Field records -- notes, tags,
--      attachments and their activity rows -- narrow immediately and for free, because 15a-1 made their
--      visibility derive from can_view_job. That was the entire point of splitting 15a. Nothing else has
--      moved yet: the job tables and the read models are still as open as they were yesterday.
--   2. ..._policies. Eleven table SELECT policies. The list views (job_list_rows, the status counts, the
--      invoice reminder views) are security_invoker = true, so fixing the underlying table policy fixes
--      them too; they are deliberately NOT rewritten.
--   3. ..._read_models. Ten SECURITY DEFINER readers that check the permission themselves and so never
--      consult RLS. schedule_calendar_context is deliberately excluded: it returns the tenant's calendar
--      configuration, not any job, and the visits drawn on that calendar are filtered by the job_visits
--      policy.
--   4. ..._commands. Eight write commands. Narrowing what a Field member can see opens a write hole: they
--      still hold jobs.complete, time.track_own and expenses.record, and those commands only ever checked
--      the write key. Without a visibility precondition a field worker could complete a visit, or log time
--      and expenses, on a job they can no longer see.
--
-- Read together they are one change; applied in this order they are four safe ones.


-- 1. A job on the assignment ---------------------------------------------------------------------------

-- job_visit_assignments has only ever carried visit_id, so "is this person on this job" meant walking every
-- visit of the job. A two-year weekly recurring job has about a hundred, and that question is now asked on
-- every job row of every list read. The performance gate's verdict was to denormalize the job onto the
-- assignment.
--
-- Denormalized data drifts, so this one is not allowed to. A trigger derives job_id from the visit on every
-- write -- callers never supply it, and cannot get it wrong -- and the composite foreign key makes a
-- mismatched pair unrepresentable rather than merely unlikely.
alter table public.job_visit_assignments add column job_id uuid;

update public.job_visit_assignments as assignment
set job_id = visit.job_id
from public.job_visits as visit
where visit.id = assignment.visit_id
  and visit.organization_id = assignment.organization_id;

alter table public.job_visit_assignments alter column job_id set not null;

create or replace function private.job_visit_assignment_job()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  select visit.job_id into new.job_id
  from public.job_visits as visit
  where visit.id = new.visit_id
    and visit.organization_id = new.organization_id;

  if new.job_id is null then
    raise exception 'That visit does not belong to this organization.'
      using errcode = 'foreign_key_violation';
  end if;

  return new;
end;
$$;

create trigger job_visit_assignment_job
before insert or update on public.job_visit_assignments
for each row execute function private.job_visit_assignment_job();

-- Replaces, rather than joins, the narrower (organization_id, visit_id) key. Two foreign keys from this
-- table to job_visits would make PostgREST's assignments embed ambiguous, and the name is kept so the
-- generated types keep resolving it.
alter table public.job_visit_assignments
  drop constraint job_visit_assignments_visit_organization_fk;

alter table public.job_visit_assignments
  add constraint job_visit_assignments_visit_organization_fk
  foreign key (organization_id, job_id, visit_id)
  references public.job_visits (organization_id, job_id, id) on delete cascade;

-- The index the whole narrowing rests on: "is this caller on this job" as one probe.
create index job_visit_assignments_member_job_idx
  on public.job_visit_assignments (organization_id, user_id, job_id);

-- 2. Turn the dormant scope machinery on -----------------------------------------------------------------

-- private.assert_scope_is_supported refuses to store a narrower access_scope until the permission declares
-- it can be enforced. jobs.view declares it first; the trigger then allows the row below.
update public.permissions set scope_model = 'assigned_or_all' where key = 'jobs.view';

update public.role_permissions
set access_scope = 'assigned'
where role = 'field' and permission_key = 'jobs.view';

-- 3. The visibility seam ---------------------------------------------------------------------------------

-- permission_scope answers for the caller. The SECURITY DEFINER read models below know their caller as a
-- parameter instead, exactly as member_has_permission mirrors has_permission, so the scope question needs
-- the same pair. Overrides win over the role, and a denied override is 'none', not a scope.
create or replace function private.member_permission_scope(
  target_organization_id uuid,
  target_user_id uuid,
  target_permission_key text
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (
      select case
        when override.override_state = 'deny' then 'none'
        else override.access_scope
      end
      from public.organization_member_permission_overrides as override
      join public.organization_members as membership
        on membership.organization_id = override.organization_id
       and membership.user_id = override.user_id
      where override.organization_id = target_organization_id
        and override.user_id = target_user_id
        and override.permission_key = target_permission_key
        and membership.status = 'active'
    ),
    (
      select role_permission.access_scope
      from public.organization_members as membership
      join public.role_permissions as role_permission
        on role_permission.role = membership.role
      where membership.organization_id = target_organization_id
        and membership.user_id = target_user_id
        and membership.status = 'active'
        and role_permission.permission_key = target_permission_key
    ),
    'none'
  );
$$;

revoke all on function private.member_permission_scope(uuid, uuid, text) from public;
grant execute on function private.member_permission_scope(uuid, uuid, text) to authenticated;

-- The one rule, written once. Anything other than 'assigned' -- 'all' today, and any scope a later part
-- adds -- keeps the unnarrowed answer, so a role that never opted in cannot be narrowed by accident.
create or replace function private.member_job_is_visible(
  target_organization_id uuid,
  target_user_id uuid,
  target_job_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.member_has_permission(target_organization_id, target_user_id, 'jobs.view')
    and (
      private.member_permission_scope(target_organization_id, target_user_id, 'jobs.view') <> 'assigned'
      or exists (
        select 1
        from public.job_visit_assignments as assignment
        where assignment.organization_id = target_organization_id
          and assignment.user_id = target_user_id
          and assignment.job_id = target_job_id
      )
    );
$$;

revoke all on function private.member_job_is_visible(uuid, uuid, uuid) from public;
grant execute on function private.member_job_is_visible(uuid, uuid, uuid) to authenticated;

-- 20260816110139 left this returning `select false;`, and 20260824135801 recorded why: it was always meant
-- to key off Visit assignment once Scheduling existed. It does now. This widens client visibility -- a
-- Field member holds no customers.view, so before this they saw no client at all, and a job whose customer
-- is blank is not a job you can do. can_view_client ORs it with customers.view, so nobody loses anything.
create or replace function private.client_is_assigned_to_current_user(
  target_organization_id uuid,
  target_client_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.job_visit_assignments as assignment
    join public.jobs as job
      on job.organization_id = assignment.organization_id
     and job.id = assignment.job_id
    where assignment.organization_id = target_organization_id
      and assignment.user_id = (select auth.uid())
      and job.client_id = target_client_id
  );
$$;

