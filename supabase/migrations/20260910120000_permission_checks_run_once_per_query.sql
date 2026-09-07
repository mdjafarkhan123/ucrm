-- Jobs, Part 15a-4: the permission rules stop running once per scanned row.
--
-- Every job-family read policy was shaped `is_organization_member(organization_id) AND
-- can_view_job(organization_id, job_id)`. Both take the row's own columns, so Postgres cannot hoist either
-- one: it re-ran the whole membership + permission + scope lookup for every row it examined. Measured on a
-- 5,000-job tenant, one week of the Schedule (871 rows scanned):
--
--   no RLS at all ................................. 2.7 ms
--   owner .......................................... 161 ms
--   field worker, org-wide read .................... 118 ms
--   field worker, with 15a-3's `mine` join .......... 216 ms
--
-- The read itself is 2.7 ms. Everything above it is the permission check, charged ~0.14-0.25 ms and ~15
-- buffers per row. That is why 15a-3's route-level narrowing could not help and why driving the read from
-- the assignment table was worse still (1,266 ms): it never reduced the number of times the rule ran.
--
-- Each rule is really two questions welded together:
--
--   1. Who is asking?  -- their organization, whether they hold the permission, and their scope. Identical
--      for every row in the statement.
--   2. Which row is this?  -- only ever asked of an 'assigned'-scope member: "am I on this job?"
--
-- This splits them. Question 1 moves into functions that take no row-dependent argument, so the policy can
-- call them as `(select ...)` -- an uncorrelated subquery, which Postgres evaluates once per statement as an
-- InitPlan. This is Supabase's documented first rule for RLS performance. Question 2 stays a per-row call,
-- but it is now a single index probe on job_visit_assignments_member_job_idx (organization_id, user_id,
-- job_id), and an 'all'-scope member never reaches it because the OR short-circuits first.
--
-- Two facts make this sound, both verified against the schema rather than assumed:
--
--   * organization_members carries UNIQUE (user_id). A user belongs to exactly one organization, so "which
--     organization am I in?" needs no argument and cannot be ambiguous.
--   * Every job-family table reaches jobs through a composite (organization_id, job_id) foreign key, either
--     directly or through job_visits. can_view_job's trailing `exists (select 1 from public.jobs ...)` was
--     therefore already guaranteed by referential integrity on every table that used it, and is dropped
--     rather than re-checked per row.
--
-- can_view_job and can_view_assessment are kept, because can_view_visit, can_view_job_expense and
-- can_view_linked_entity call can_view_job for single-entity point lookups where per-row cost is not a
-- factor. They are re-expressed on top of the new primitives, so the scope rule now exists in exactly one
-- place instead of being copied into each of them -- the duplication their own comments warned about.

-- Question 1a: which organization is the caller in? No argument, so a policy can hoist it.
-- Carries the organizations.lifecycle_status test that is_organization_member used to apply, so a closed or
-- suspended business still disappears. Returns null when the caller is not an active member of an active
-- organization, and every policy below compares a NOT NULL column to it, so null hides every row.
create or replace function private.current_organization()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select membership.organization_id
  from public.organization_members as membership
  join public.organizations as organization
    on organization.id = membership.organization_id
  where membership.user_id = (select auth.uid())
    and membership.status = 'active'
    and organization.lifecycle_status = 'active';
$$;

comment on function private.current_organization() is
  'The caller''s one active organization, or null. Argument-free on purpose: a policy calls it as '
  '(select private.current_organization()) so Postgres evaluates it once per statement instead of once per '
  'scanned row. Sound only because organization_members carries UNIQUE (user_id).';

-- Question 1b: what is the caller's scope for one permission? 'all', 'assigned' or 'none'.
--
-- The permission key is always a literal in a policy, never a column, so this stays uncorrelated and is
-- hoisted the same way. It folds together the two rules that used to be separate functions:
--
--   private.has_permission  -- a grant override wins, otherwise the role must carry the key
--   private.permission_scope -- a deny override means none, otherwise override scope, otherwise role scope
--
-- They cannot disagree. access_scope is NOT NULL and constrained to ('assigned','all') on both tables, and a
-- deny override is constrained to access_scope = 'all', so 'none' comes back exactly when has_permission was
-- false: denied, or no role row for the key. Callers therefore need only this one function.
create or replace function private.current_permission_scope(target_permission_key text)
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
      where override.organization_id = membership.organization_id
        and override.user_id = membership.user_id
        and override.permission_key = target_permission_key
    ),
    (
      select role_permission.access_scope
      from public.role_permissions as role_permission
      where role_permission.role = membership.role
        and role_permission.permission_key = target_permission_key
    ),
    'none'
  )
  from public.organization_members as membership
  where membership.user_id = (select auth.uid())
    and membership.status = 'active';
$$;

comment on function private.current_permission_scope(text) is
  'The caller''s access scope for one permission key: all, assigned or none. Argument-free with respect to '
  'the row, so a policy calls it as (select private.current_permission_scope(''key'')) and Postgres '
  'evaluates it once per statement. Replaces private.has_permission and private.permission_scope for policy '
  'use: scope <> ''none'' is exactly has_permission, because access_scope is NOT NULL on both source tables '
  'and a deny override is constrained to access_scope = ''all''.';

-- Question 2: the only genuinely per-row test, and only an 'assigned'-scope member ever reaches it.
-- Lands on job_visit_assignments_member_job_idx (organization_id, user_id, job_id): one index probe, no new
-- index. It stays SECURITY DEFINER rather than being inlined into the policy because job_visit_assignments
-- carries a policy of its own -- an inlined subquery over it would recurse through that policy.
create or replace function private.is_assigned_to_job(
  target_organization_id uuid,
  target_job_id uuid
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
    where assignment.organization_id = target_organization_id
      and assignment.user_id = (select auth.uid())
      and assignment.job_id = target_job_id
  );
$$;

comment on function private.is_assigned_to_job(uuid, uuid) is
  'Whether the caller is on any visit of this job. The one per-row half of the jobs.view rule; the scope '
  'half is hoisted by private.current_permission_scope. SECURITY DEFINER because job_visit_assignments has '
  'its own policy and an inlined subquery would recurse through it.';

create or replace function private.is_assigned_to_assessment(
  target_organization_id uuid,
  target_assessment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.assessment_assignees as assignee
    where assignee.organization_id = target_organization_id
      and assignee.assessment_id = target_assessment_id
      and assignee.user_id = (select auth.uid())
  );
$$;

comment on function private.is_assigned_to_assessment(uuid, uuid) is
  'Whether the caller is on this assessment. Lands on assessment_assignees_pkey (assessment_id, user_id). '
  'SECURITY DEFINER for the same recursion reason as private.is_assigned_to_job.';

revoke all on function private.current_organization()
  from public, anon, authenticated, service_role;
revoke all on function private.current_permission_scope(text)
  from public, anon, authenticated, service_role;
revoke all on function private.is_assigned_to_job(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.is_assigned_to_assessment(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.current_organization() to authenticated;
grant execute on function private.current_permission_scope(text) to authenticated;
grant execute on function private.is_assigned_to_job(uuid, uuid) to authenticated;
grant execute on function private.is_assigned_to_assessment(uuid, uuid) to authenticated;

-- The two entity rules, re-expressed on the primitives above. They keep their signatures and their callers --
-- can_view_visit, can_view_job_expense and can_view_linked_entity resolve one entity at a time, where a
-- per-row cost does not arise -- but they no longer carry their own copy of the scope rule.
create or replace function private.can_view_job(
  target_organization_id uuid,
  target_job_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select target_organization_id = private.current_organization()
    and (
      private.current_permission_scope('jobs.view') = 'all'
      or (
        private.current_permission_scope('jobs.view') = 'assigned'
        and private.is_assigned_to_job(target_organization_id, target_job_id)
      )
    );
$$;

comment on function private.can_view_job(uuid, uuid) is
  'Whether the caller may see this job. For single-entity lookups only -- the scanning read policies inline '
  'this same rule so the scope half can be hoisted to one evaluation per statement. The trailing jobs '
  'existence check this used to carry is gone: every caller reaches jobs through a composite '
  '(organization_id, job_id) foreign key, so referential integrity already guarantees it.';

create or replace function private.can_view_assessment(
  target_organization_id uuid,
  target_assessment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select target_organization_id = private.current_organization()
    and (
      private.current_permission_scope('jobs.view') <> 'assigned'
      or private.is_assigned_to_assessment(target_organization_id, target_assessment_id)
    );
$$;

comment on function private.can_view_assessment(uuid, uuid) is
  'Whether the caller may see this assessment. Unlike a job, an assessment is not gated on holding '
  'jobs.view -- it is visible to every member unless their scope narrows it, which is what it was before '
  'Part 15a-3. Only the ''assigned'' scope narrows it.';

-- The scanning read policies. Each one spells the rule out rather than calling can_view_job, because the
-- point is the shape: `(select private.current_permission_scope(...))` has no row-dependent argument, so
-- Postgres evaluates it once per statement as an InitPlan. Wrapped inside a SECURITY DEFINER function taking
-- the row's columns -- which is what these policies used to do -- that hoisting is impossible.
--
-- private.is_organization_member(organization_id) is replaced throughout by comparing the row's NOT NULL
-- organization_id against the hoisted (select private.current_organization()). It carries the same active
-- membership and active organization tests, and a null result hides every row.

drop policy "permitted members can view jobs" on public.jobs;
create policy "permitted members can view jobs"
on public.jobs for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, id)
    )
  )
);

drop policy "permitted members can view job visits" on public.job_visits;
create policy "permitted members can view job visits"
on public.job_visits for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

drop policy "permitted members can view job visit assignments" on public.job_visit_assignments;
create policy "permitted members can view job visit assignments"
on public.job_visit_assignments for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);


drop policy "permitted members can view visit lines" on public.job_visit_line_items;
create policy "permitted members can view visit lines"
on public.job_visit_line_items for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

drop policy "permitted members can view job lines" on public.job_line_items;
create policy "permitted members can view job lines"
on public.job_line_items for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

drop policy "permitted members can view job events" on public.job_events;
create policy "permitted members can view job events"
on public.job_events for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

drop policy "permitted members can view job invoice reminders" on public.job_invoice_reminders;
create policy "permitted members can view job invoice reminders"
on public.job_invoice_reminders for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

drop policy "permitted members can view job payment stages" on public.job_payment_schedule_items;
create policy "permitted members can view job payment stages"
on public.job_payment_schedule_items for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

drop policy "permitted members can view job recurrence rules" on public.job_recurrence_rules;
create policy "permitted members can view job recurrence rules"
on public.job_recurrence_rules for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
);

-- Expenses and time entries add a second permission on top of the job rule. Those were per-row
-- private.has_permission calls for the same reason, and they hoist the same way. scope <> 'none' is exactly
-- what has_permission returned.

drop policy "permitted members can view expenses" on public.job_expenses;
create policy "permitted members can view expenses"
on public.job_expenses for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
  and (
    (select private.current_permission_scope('expenses.manage_team')) <> 'none'
    or (
      created_by = (select auth.uid())
      and (select private.current_permission_scope('expenses.record')) <> 'none'
    )
  )
);

drop policy "permitted members can view time entries" on public.job_time_entries;
create policy "permitted members can view time entries"
on public.job_time_entries for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) = 'all'
    or (
      (select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id)
    )
  )
  and (
    (select private.current_permission_scope('time.track_team')) <> 'none'
    or (
      user_id = (select auth.uid())
      and (select private.current_permission_scope('time.track_own')) <> 'none'
    )
  )
);

-- Assessments. Part 15a-3 put these behind can_view_assessment one row at a time; the read that draws them
-- is the same Schedule window, so they take the same shape. Update and delete keep matching select, so
-- narrowing the read cannot leave a write hole -- the lesson 15a-2 paid for on visit completion. Insert is
-- untouched: who may book an assessment is a Requests question, not a Schedule one.

drop policy "members can view assessments" on public.assessments;
create policy "members can view assessments"
on public.assessments for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) <> 'assigned'
    or private.is_assigned_to_assessment(organization_id, id)
  )
);

drop policy "members can update assessments" on public.assessments;
create policy "members can update assessments"
on public.assessments for update to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) <> 'assigned'
    or private.is_assigned_to_assessment(organization_id, id)
  )
)
with check (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) <> 'assigned'
    or private.is_assigned_to_assessment(organization_id, id)
  )
);

drop policy "members can delete assessments" on public.assessments;
create policy "members can delete assessments"
on public.assessments for delete to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) <> 'assigned'
    or private.is_assigned_to_assessment(organization_id, id)
  )
);

drop policy "members can view assessment assignees" on public.assessment_assignees;
create policy "members can view assessment assignees"
on public.assessment_assignees for select to authenticated
using (
  organization_id = (select private.current_organization())
  and (
    (select private.current_permission_scope('jobs.view')) <> 'assigned'
    or private.is_assigned_to_assessment(organization_id, assessment_id)
  )
);
