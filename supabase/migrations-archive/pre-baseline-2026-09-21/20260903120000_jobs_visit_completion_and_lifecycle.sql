-- Jobs Part 13a: Visit completion and the Job lifecycle primitives it depends on.
--
-- Nothing before this part could mark a Visit done. The "Completed" badge has been drawing off
-- job_visits.completed_at since Part 9, but no command ever wrote it. This part is that write, plus the two
-- narrow consequences the contract already approved:
--   * Completing a Visit fires that job's per-visit invoice reminder when it is billed per_completed_visit.
--   * Completing the last incomplete Visit of a one-off job asks one question -- Finish job, Add a return
--     visit, or Keep open -- matching Jobber's "Final visit completed" dialog exactly (Design/Jobber Jobs,
--     2026-08-31, screenshot 35).
--
-- Deliberately NOT here, because Schedule Part 5 does not need it and the roadmap gate does not ask for it:
--   * The standalone "Close Job" button with the full incomplete-visits-removal preview (cancelling a job
--     that still has open work). close_job below only closes a job that already has zero incomplete visits --
--     exactly the state "Finish job" reaches -- and refuses otherwise, pointing at that future part.
--   * Wiring Upcoming/Today/Late/Action required into private.job_derived_status. That is a separate,
--     larger read-model change (job_list_rows, job_status_count_rows) the Jobs list still needs; it is
--     recorded as a follow-up, not silently done here.
--
-- reopen_job ships alongside close_job so "Finish job" is not a one-way door: a contractor who closes a job
-- by mistake, or whose customer calls back, can reopen it. The contract already names Reopen as jobs.close's
-- other direction (docs/jobs-behavior-contract.md, the Job lifecycle table).

-- 1. The two permissions this part brings to life -------------------------------------------------------------

-- Named in the approved contract, deliberately unseeded until their behavior existed (the same pattern
-- jobs.schedule followed in Part 9). Field gets jobs.complete only, matching the contract's proposed
-- defaults: a crew member marks their own work done but does not close or reopen the job.
insert into public.permissions (key, description)
values
  ('jobs.complete', 'Mark a job''s visits complete or incomplete'),
  ('jobs.close', 'Finish, close and reopen a job')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'jobs.complete'),
  ('owner', 'jobs.close'),

  ('admin', 'jobs.complete'),
  ('admin', 'jobs.close'),

  ('office', 'jobs.complete'),
  ('office', 'jobs.close'),

  ('sales', 'jobs.complete'),
  ('sales', 'jobs.close'),

  ('field', 'jobs.complete')
on conflict (role, permission_key) do nothing;

-- 2. Complete a visit -------------------------------------------------------------------------------------------

-- Idempotent by state, not by key: completing an already-completed visit replays the same result instead of
-- raising, so a double click or a retried request cannot fire a second reminder or a second event. The row
-- lock on job_visits, taken before the check, is what makes two concurrent completions of the same visit
-- resolve safely -- the second to arrive sees the first's committed completed_at and takes the replay path.
create or replace function public.complete_job_visit(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  current_visit public.job_visits;
  remaining_incomplete integer;
  new_reminder_id uuid;
  final_visit boolean := false;
begin
  if caller is null then
    raise exception 'You must be signed in to complete a visit.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.complete') then
    raise exception 'You do not have access to complete this visit.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    raise exception 'A closed job''s visits cannot be changed. Reopen the job first.' using errcode = 'P0410';
  end if;

  select visit.* into current_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = target_visit_id
  for update;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;

  if current_visit.completed_at is not null then
    return jsonb_build_object(
      'applied', true, 'already_completed', true, 'revision', current_visit.revision, 'final_visit', false
    );
  end if;

  update public.job_visits
  set completed_at = now(), completed_by = caller, revision = revision + 1, updated_at = now()
  where organization_id = target_organization_id and id = target_visit_id
  returning * into current_visit;

  -- Internal to-do, raised the moment the billable event happens; private.create_invoice_reminder is the
  -- one primitive every reminder is born through (Part 11b), and it is already a no-op if one is open.
  if current_job.billing_timing = 'per_completed_visit' then
    new_reminder_id := private.create_invoice_reminder(
      target_organization_id,
      target_job_id,
      'per_visit',
      private.organization_today(target_organization_id),
      caller,
      target_visit_id
    );
  end if;

  select count(*) into remaining_incomplete
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.completed_at is null;

  -- Only a one-off job asks the question. A recurring job's incomplete visits are its future occurrences,
  -- not open work to close out.
  final_visit := remaining_incomplete = 0 and current_job.job_type = 'one_off';

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visit_completed',
    caller,
    target_visit_id,
    jsonb_build_object('final_visit', final_visit)
  );

  return jsonb_build_object(
    'applied', true,
    'already_completed', false,
    'revision', current_visit.revision,
    'final_visit', final_visit,
    'reminder_id', new_reminder_id
  );
end;
$$;

comment on function public.complete_job_visit(uuid, uuid, uuid) is
  'Marks a visit complete. Checks jobs.complete, refuses on a closed job (P0410), is idempotent on an '
  'already-completed visit, fires the per_visit reminder when the job bills per completed visit, and reports '
  'final_visit when this was the last incomplete visit of a one-off job.';

-- 3. Uncomplete a visit -----------------------------------------------------------------------------------------

-- The undo. A reminder already fired by completing stays -- reminders are internal to-dos, not something a
-- toggle should silently retract -- matching how dismiss_job_invoice_reminder never touches the visit either.
create or replace function public.uncomplete_job_visit(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  current_visit public.job_visits;
begin
  if caller is null then
    raise exception 'You must be signed in to change a visit.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.complete') then
    raise exception 'You do not have access to complete this visit.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    raise exception 'A closed job''s visits cannot be changed. Reopen the job first.' using errcode = 'P0410';
  end if;

  select visit.* into current_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = target_visit_id
  for update;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;

  if current_visit.completed_at is null then
    return jsonb_build_object('applied', true, 'already_incomplete', true, 'revision', current_visit.revision);
  end if;

  update public.job_visits
  set completed_at = null, completed_by = null, revision = revision + 1, updated_at = now()
  where organization_id = target_organization_id and id = target_visit_id
  returning * into current_visit;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (target_organization_id, target_job_id, 'visit_uncompleted', caller, target_visit_id, '{}'::jsonb);

  return jsonb_build_object('applied', true, 'already_incomplete', false, 'revision', current_visit.revision);
end;
$$;

comment on function public.uncomplete_job_visit(uuid, uuid, uuid) is
  'Clears a visit''s completion. Checks jobs.complete, refuses on a closed job (P0410), is idempotent on an '
  'already-incomplete visit. Leaves any reminder the completion already raised untouched.';

-- 4. Finish a job -----------------------------------------------------------------------------------------------

-- The bounded "Finish job" primitive: closes a job that already has zero incomplete visits. It refuses,
-- rather than removing or completing work, when incomplete visits remain -- the general Close/Cancel button
-- that offers to clear them is a later, separate part. This is deliberately the same shape as
-- update_job_details: a revision guard, no idempotency-key receipt, because a close is a single-row
-- transition a row lock already makes safe to retry.
create or replace function public.close_job(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  incomplete_count integer;
  new_reminder_id uuid;
begin
  if caller is null then
    raise exception 'You must be signed in to close a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.close') then
    raise exception 'You do not have access to close this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    return jsonb_build_object('applied', true, 'already_closed', true, 'revision', current_job.revision);
  end if;
  if current_job.revision is distinct from expected_revision then
    raise exception 'Someone else changed this job. Reload to see the latest.' using errcode = 'P0409';
  end if;

  select count(*) into incomplete_count
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.completed_at is null;
  if incomplete_count > 0 then
    raise exception
      'This job still has % incomplete visit(s). Finish or remove them before closing.', incomplete_count
      using errcode = 'check_violation';
  end if;

  update public.jobs
  set status = 'closed', revision = current_job.revision + 1, updated_at = now()
  where organization_id = target_organization_id and id = target_job_id;

  if current_job.billing_timing = 'on_closure' then
    new_reminder_id := private.create_invoice_reminder(
      target_organization_id,
      target_job_id,
      'on_completion',
      private.organization_today(target_organization_id),
      caller
    );
  end if;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, new_status, metadata)
  values (target_organization_id, target_job_id, 'job_closed', caller, 'closed', '{}'::jsonb);

  return jsonb_build_object(
    'applied', true,
    'already_closed', false,
    'revision', current_job.revision + 1,
    'reminder_id', new_reminder_id
  );
end;
$$;

comment on function public.close_job(uuid, uuid, integer) is
  'Closes a job that has zero incomplete visits. Checks jobs.close, refuses a stale revision (P0409) and a '
  'job with incomplete visits still open (check_violation), is idempotent on an already-closed job, and fires '
  'the on_completion reminder when the job bills on closure.';

-- 5. Reopen a job -----------------------------------------------------------------------------------------------

-- The other direction of jobs.close. Removed visits (there are none here, since close_job only ever closes a
-- job with zero incomplete visits) do not regenerate on reopening -- scheduling more is an explicit action,
-- matching the contract's lifecycle table.
create or replace function public.reopen_job(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
begin
  if caller is null then
    raise exception 'You must be signed in to reopen a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.close') then
    raise exception 'You do not have access to reopen this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'active' then
    return jsonb_build_object('applied', true, 'already_active', true, 'revision', current_job.revision);
  end if;
  if current_job.revision is distinct from expected_revision then
    raise exception 'Someone else changed this job. Reload to see the latest.' using errcode = 'P0409';
  end if;

  update public.jobs
  set status = 'active', revision = current_job.revision + 1, updated_at = now()
  where organization_id = target_organization_id and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, new_status, metadata)
  values (target_organization_id, target_job_id, 'job_reopened', caller, 'active', '{}'::jsonb);

  return jsonb_build_object('applied', true, 'already_active', false, 'revision', current_job.revision + 1);
end;
$$;

comment on function public.reopen_job(uuid, uuid, integer) is
  'Returns a closed job to active. Checks jobs.close, refuses a stale revision (P0409), is idempotent on an '
  'already-active job. Removed visits do not regenerate; scheduling more is a separate explicit action.';

-- 6. Grants --------------------------------------------------------------------------------------------------

revoke all on function public.complete_job_visit(uuid, uuid, uuid) from public;
revoke execute on function public.complete_job_visit(uuid, uuid, uuid) from anon;
grant execute on function public.complete_job_visit(uuid, uuid, uuid) to authenticated;

revoke all on function public.uncomplete_job_visit(uuid, uuid, uuid) from public;
revoke execute on function public.uncomplete_job_visit(uuid, uuid, uuid) from anon;
grant execute on function public.uncomplete_job_visit(uuid, uuid, uuid) to authenticated;

revoke all on function public.close_job(uuid, uuid, integer) from public;
revoke execute on function public.close_job(uuid, uuid, integer) from anon;
grant execute on function public.close_job(uuid, uuid, integer) to authenticated;

revoke all on function public.reopen_job(uuid, uuid, integer) from public;
revoke execute on function public.reopen_job(uuid, uuid, integer) from anon;
grant execute on function public.reopen_job(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
