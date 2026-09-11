-- Team & access, part 3E, item 1: deactivate stops leaving a person's open work stranded, and a manager can
-- see what that work is before they confirm.
--
-- Blueprint: "Deactivation unassigns the member from every incomplete assignment and names that work in the
-- confirmation beforehand... Reassignment is offered, never required. Completed work retains its original
-- attribution, and reactivation never restores old assignments." (Jobber parity, checked 2026-09-11: Jobber
-- unassigns "all incomplete items assigned to them on the calendar" -- visits, tasks, requests, reminders.)
--
-- Our schema only carries a direct assignment on three of those: assessment_assignees, job_visit_assignments,
-- and tasks.assignee_user_id. A Request has no assignment column of its own -- it is only ever "assigned"
-- through the one assessment attached to it (see private.can_view_request) -- so unassigning the assessment
-- already covers it. Reminders do not exist in this product. Completion is never a status enum for the first
-- two: assessments and visits both use "completed_at is null means not complete", so that is the incomplete
-- test here too, exactly as every other reader of those tables already treats it.

-- ---------------------------------------------------------------------------
-- 1. A new closed value kind for team history: a plain non-negative count
-- ---------------------------------------------------------------------------

create or replace function private.member_access_summary_kinds_are_known(candidate jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when jsonb_typeof(candidate) <> 'object' then false
    else not exists (
      select 1
      from jsonb_each_text(candidate) as entry(summary_key, value_kind)
      where value_kind not in (
        'role', 'member_status', 'permission_key_list', 'profile_field_list', 'id', 'assignment_count'
      )
    )
  end;
$$;

create or replace function private.member_access_summary_value_fits(value_kind text, candidate jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  case value_kind
    when 'role' then
      return jsonb_typeof(candidate) = 'string'
        and candidate #>> '{}' in ('owner', 'admin', 'office', 'sales', 'field', 'finance');
    when 'member_status' then
      return jsonb_typeof(candidate) = 'string'
        and candidate #>> '{}' in ('pending', 'active', 'deactivated', 'removed');
    when 'permission_key_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or not exists (
            select 1 from public.permissions as permission where permission.key = element.item #>> '{}'
          )
      );
    when 'profile_field_list' then
      if jsonb_typeof(candidate) <> 'array' then
        return false;
      end if;
      return not exists (
        select 1
        from jsonb_array_elements(candidate) as element(item)
        where jsonb_typeof(element.item) <> 'string'
          or element.item #>> '{}' not in ('full_name', 'work_phone', 'job_title', 'schedule_color')
      );
    when 'id' then
      return jsonb_typeof(candidate) = 'string'
        and (candidate #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    when 'assignment_count' then
      return jsonb_typeof(candidate) = 'number'
        and (candidate #>> '{}')::numeric >= 0
        and (candidate #>> '{}')::numeric = floor((candidate #>> '{}')::numeric);
    else
      -- An unknown kind is a refusal, never a pass. A future kind must be added here on purpose.
      return false;
  end case;
end;
$$;

insert into public.member_access_event_shapes (event_type, subject_kind, summary_keys, required_summary_keys)
values
  (
    'member.work_unassigned', 'member',
    jsonb_build_object(
      'unassigned_assessments', 'assignment_count',
      'unassigned_visits', 'assignment_count',
      'unassigned_tasks', 'assignment_count'
    ),
    '{}'::text[]
  );

-- ---------------------------------------------------------------------------
-- 2. Deactivate also frees the person's incomplete work
-- ---------------------------------------------------------------------------

create or replace function public.deactivate_team_member(
  target_organization_id uuid,
  actor_user_id uuid,
  target_user_id uuid
)
returns public.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  membership public.organization_members;
  previous_status text;
  unassigned_assessments integer;
  unassigned_visits integer;
  unassigned_tasks integer;
begin
  membership := private.authorize_team_member_command(
    target_organization_id, actor_user_id, target_user_id
  );

  if membership.status = 'deactivated' then
    raise exception 'That person is already deactivated.' using errcode = 'check_violation';
  end if;

  if membership.status <> 'active' then
    raise exception 'Only an active team member can be deactivated.' using errcode = 'check_violation';
  end if;

  previous_status := membership.status;

  -- Junction rows have no "unassigned" state to set, so they are deleted outright. A Task keeps existing
  -- (assignee_user_id is nullable, matching "a Task without anyone responsible is normal").
  with removed as (
    delete from public.assessment_assignees as assignee
    using public.assessments as assessment
    where assignee.assessment_id = assessment.id
      and assignee.organization_id = target_organization_id
      and assignee.user_id = target_user_id
      and assessment.completed_at is null
    returning assignee.assessment_id
  )
  select count(*) into unassigned_assessments from removed;

  with removed as (
    delete from public.job_visit_assignments as assignee
    using public.job_visits as visit
    where assignee.visit_id = visit.id
      and assignee.organization_id = target_organization_id
      and assignee.user_id = target_user_id
      and visit.completed_at is null
    returning assignee.visit_id
  )
  select count(*) into unassigned_visits from removed;

  with updated as (
    update public.tasks as task
    set assignee_user_id = null
    where task.organization_id = target_organization_id
      and task.assignee_user_id = target_user_id
      and task.status = 'open'
    returning task.id
  )
  select count(*) into unassigned_tasks from updated;

  -- The seat is freed by this write alone: private.employee_seats_used counts pending and active
  -- memberships, so nothing else has to remember to release it.
  update public.organization_members as membership_row
  set status = 'deactivated',
      deactivated_at = now(),
      status_changed_at = now(),
      status_changed_by = actor_user_id,
      access_revision = membership_row.access_revision + 1
  where membership_row.organization_id = target_organization_id
    and membership_row.user_id = target_user_id
  returning * into membership;

  insert into public.organization_member_access_events (
    organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
  )
  values (
    target_organization_id, 'member.deactivated', 'member', actor_user_id, target_user_id,
    jsonb_build_object('previous_status', previous_status)
  );

  -- A second line, only when something was actually unassigned -- same reasoning as change_team_member_role's
  -- dropped-adjustments line: one action that did two things reads as two facts in the history, not one.
  if unassigned_assessments > 0 or unassigned_visits > 0 or unassigned_tasks > 0 then
    insert into public.organization_member_access_events (
      organization_id, event_type, actor_kind, actor_user_id, subject_user_id, summary
    )
    values (
      target_organization_id, 'member.work_unassigned', 'member', actor_user_id, target_user_id,
      jsonb_build_object(
        'unassigned_assessments', unassigned_assessments,
        'unassigned_visits', unassigned_visits,
        'unassigned_tasks', unassigned_tasks
      )
    );
  end if;

  return membership;
end;
$$;

comment on function public.deactivate_team_member(uuid, uuid, uuid) is
  'Takes away a member''s access, frees their seat, and unassigns their incomplete assessments, visits and '
  'open tasks -- keeping everything they ever finished. Ending their live sessions is not needed here: every '
  'request already re-checks status=''active'' at the door. Removal only sets identity_cleanup_state.';

-- ---------------------------------------------------------------------------
-- 3. What the confirmation dialog shows before a manager confirms
-- ---------------------------------------------------------------------------

-- Read-only preview of exactly what deactivate_team_member is about to unassign, so the screen can name it
-- first. Same authority question as get_team_member_detail (an ordinary read for a signed-in team manager,
-- not a service-role command), so it is called the same way: directly, by the browser's own client.
create or replace function public.get_incomplete_assignments_for_member(
  target_organization_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  result jsonb;
begin
  if (select auth.uid()) is null or not exists (
    select 1
    from private.permitted_organizations('team.manage') as permitted(organization_id)
    where permitted.organization_id = target_organization_id
  ) then
    raise exception 'Team management is not available for this organization.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'starts_at', a.starts_at))
      from (
        select assessment.id, assessment.starts_at
        from public.assessment_assignees as assignee
        join public.assessments as assessment on assessment.id = assignee.assessment_id
        where assignee.organization_id = target_organization_id
          and assignee.user_id = target_user_id
          and assessment.completed_at is null
        order by assessment.starts_at nulls last
        limit 50
      ) as a
    ), '[]'::jsonb),
    'assessments_total', (
      select count(*)
      from public.assessment_assignees as assignee
      join public.assessments as assessment on assessment.id = assignee.assessment_id
      where assignee.organization_id = target_organization_id
        and assignee.user_id = target_user_id
        and assessment.completed_at is null
    ),
    'visits', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', v.id, 'visit_date', v.visit_date, 'start_time', v.start_time, 'title', v.title)
      )
      from (
        select visit.id, visit.visit_date, visit.start_time, visit.title
        from public.job_visit_assignments as assignee
        join public.job_visits as visit on visit.id = assignee.visit_id
        where assignee.organization_id = target_organization_id
          and assignee.user_id = target_user_id
          and visit.completed_at is null
        order by visit.visit_date nulls last, visit.start_time nulls last
        limit 50
      ) as v
    ), '[]'::jsonb),
    'visits_total', (
      select count(*)
      from public.job_visit_assignments as assignee
      join public.job_visits as visit on visit.id = assignee.visit_id
      where assignee.organization_id = target_organization_id
        and assignee.user_id = target_user_id
        and visit.completed_at is null
    ),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'due_on', t.due_on))
      from (
        select task.id, task.title, task.due_on
        from public.tasks as task
        where task.organization_id = target_organization_id
          and task.assignee_user_id = target_user_id
          and task.status = 'open'
        order by task.due_on nulls last
        limit 50
      ) as t
    ), '[]'::jsonb),
    'tasks_total', (
      select count(*)
      from public.tasks as task
      where task.organization_id = target_organization_id
        and task.assignee_user_id = target_user_id
        and task.status = 'open'
    )
  ) into result;

  return result;
end;
$$;

comment on function public.get_incomplete_assignments_for_member(uuid, uuid) is
  'What deactivate_team_member is about to unassign, for the confirmation dialog: up to 50 of each surface '
  'plus a true total. Every predicate matches deactivate_team_member exactly, so the preview and the result '
  'can never disagree.';

revoke all on function public.get_incomplete_assignments_for_member(uuid, uuid)
  from public, anon, service_role;
grant execute on function public.get_incomplete_assignments_for_member(uuid, uuid) to authenticated;
