-- Jobs part 10b: editing a recurring job's schedule after the job exists.
--
-- Three pieces, in the order they depend on each other:
--   1. The database itself refuses to rewrite or drop a completed visit, under every write path.
--   2. `reschedule_job_visits` replaces the repeat rule and rebuilds the job's incomplete visits.
--   3. `apply_visit_to_future` copies one visit's time of day and crew onto the job's later visits.
--
-- Scope approved by Jafar on 2026-09-01 and recorded in docs/jobs-behavior-contract.md. Deliberately absent,
-- and deferred there rather than forgotten: preserving a customised visit across a regeneration, converting a
-- job between as-needed and scheduled, collision handling when a regenerated date already carries a visit,
-- seasonal pause and resume, and propagating line items (which wait for part 11 to give a visit its own).

-- 1. Completed visits are protected by the database, not only by the screens -----------------------------------

-- Jobber, Housecall Pro and ServiceTitan all draw the same line: a completed visit is the record that the work
-- happened, so a schedule change never rewrites it. Every command here already scopes its writes to
-- `completed_at is null`, but the commands are not the only thing that could ever hold the pen. This trigger is
-- the floor under all of them, so a future command cannot quietly erase history by forgetting a where clause.
create or replace function private.job_visits_protect_completed()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' then
    -- A completed visit still goes when the thing that owns it goes: deleting the job removes all of its
    -- visits, and deleting the organization removes everything. Those arrive here as cascades, which Postgres
    -- runs through internal triggers, so they are nested and `pg_trigger_depth()` is above one. A person
    -- deleting this one visit by itself arrives at depth one, and that is the case we refuse.
    if old.completed_at is not null and pg_trigger_depth() = 1 then
      raise exception 'A completed visit cannot be deleted. It is the record that the work happened.'
        using errcode = 'P0410';
    end if;
    return old;
  end if;

  -- Completing a visit, or undoing that, is not a reschedule: only the schedule fields are frozen, and only
  -- once the visit is already complete.
  if old.completed_at is not null and (
    new.visit_date is distinct from old.visit_date
    or new.start_time is distinct from old.start_time
    or new.end_time is distinct from old.end_time
    or new.all_day is distinct from old.all_day
  ) then
    raise exception 'A completed visit cannot be rescheduled. It is the record that the work happened.'
      using errcode = 'P0410';
  end if;

  return new;
end;
$$;

comment on function private.job_visits_protect_completed() is
  'Refuses to move a completed visit or to delete one on its own, while still letting the job''s or the '
  'organization''s own deletion cascade through it.';

drop trigger if exists job_visits_protect_completed_update on public.job_visits;
create trigger job_visits_protect_completed_update
  before update on public.job_visits
  for each row execute function private.job_visits_protect_completed();

drop trigger if exists job_visits_protect_completed_delete on public.job_visits;
create trigger job_visits_protect_completed_delete
  before delete on public.job_visits
  for each row execute function private.job_visits_protect_completed();

-- 2. Replace a recurring job's schedule ------------------------------------------------------------------------

-- "Edit all visits". The rule is replaced and every incomplete visit of the job is cleared and rebuilt from it
-- -- past-dated incomplete visits included, which is what Jobber does and says: "rescheduling will delete all
-- incomplete visits and recreate them using the visit details above." Custom details on those visits are lost,
-- and the screen says so before this runs. Completed visits are never in scope, and the trigger above means
-- that is true even if this function is one day edited carelessly.
create or replace function public.reschedule_job_visits(
  target_organization_id uuid,
  target_job_id uuid,
  expected_revision integer,
  new_recurrence jsonb,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  removed_count integer;
  created_count integer;
  completed_kept integer;
  next_position integer;
  window_first date;
  window_last date;
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  if new_recurrence is null or jsonb_typeof(new_recurrence) is distinct from 'object' then
    raise exception 'A repeating job needs a repeat schedule.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- Lock the job so the revision checked is the revision written against, exactly as update_job_details does.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id
  for update;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- The three shapes this refuses, each in the words of what the person is looking at. Turning an as-needed
  -- job into a scheduled one is a deferred product decision, not an oversight: `is_as_needed` is immutable by
  -- the job's own trigger, so allowing it means loosening a guard on job identity.
  if current_job.job_type <> 'recurring' then
    raise exception 'Only a recurring job has a repeating schedule to edit.' using errcode = 'check_violation';
  end if;
  if current_job.is_as_needed then
    raise exception 'An as-needed job is dispatched when work comes up and has no repeating schedule.'
      using errcode = 'check_violation';
  end if;
  if current_job.status <> 'active' then
    raise exception 'A closed job cannot be rescheduled. Reopen it first.' using errcode = 'check_violation';
  end if;

  -- The receipt is consulted before the revision, and the order matters. A retry of a request that already
  -- committed carries the revision it read *before* that first attempt, which this command has since moved on
  -- by one. Checking the revision first would answer a plain network retry with "someone else changed this
  -- job", which is both wrong and alarming. Reading the receipt first lets a true replay return the original
  -- result, while an editor working from a genuinely stale page still arrives with a fresh key and is refused
  -- below.
  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'reschedule_job_visits', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'reschedule_job_visits'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'This job was already rescheduled differently.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  if current_job.revision is distinct from expected_revision then
    raise exception 'Someone else changed this job. Reload to see the latest.' using errcode = 'P0409';
  end if;

  -- Out with the incomplete ones. Assignments hang off the visit and cascade with it.
  delete from public.job_visits
  where organization_id = target_organization_id
    and job_id = target_job_id
    and completed_at is null;
  get diagnostics removed_count = row_count;

  select count(*), coalesce(max(position), -1) + 1
  into completed_kept, next_position
  from public.job_visits
  where organization_id = target_organization_id
    and job_id = target_job_id;

  -- And in with the new, numbered after the completed visits that stayed. This raises, and takes the delete
  -- above down with it, if the new rule lands on no days at all or on more than the ceiling.
  created_count := private.write_job_recurrence(
    target_organization_id, target_job_id, new_recurrence, next_position
  );

  -- Everything incomplete was just replaced, so the incomplete rows are exactly the new ones.
  select min(visit.visit_date), max(visit.visit_date)
  into window_first, window_last
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.completed_at is null;

  update public.jobs
  set revision = current_job.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id
    and id = target_job_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'schedule_replaced',
    caller,
    jsonb_build_object(
      'removed_count', removed_count,
      'created_count', created_count,
      'completed_kept', completed_kept
    )
  );

  final_result := jsonb_build_object(
    'applied', true,
    'removed_count', removed_count,
    'created_count', created_count,
    'completed_kept', completed_kept,
    'first_date', window_first,
    'last_date', window_last,
    'revision', current_job.revision + 1
  );
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

comment on function public.reschedule_job_visits(uuid, uuid, integer, jsonb, text, text) is
  'Replaces a scheduled recurring job''s repeat rule and rebuilds every incomplete visit from it, keeping '
  'completed visits. Checks jobs.schedule, refuses a one-off, an as-needed or a closed job, refuses a stale '
  'revision (P0409), is idempotent by key, and appends a schedule_replaced history row.';

revoke all on function public.reschedule_job_visits(uuid, uuid, integer, jsonb, text, text) from public;
revoke execute on function public.reschedule_job_visits(uuid, uuid, integer, jsonb, text, text) from anon;
grant execute on function public.reschedule_job_visits(uuid, uuid, integer, jsonb, text, text) to authenticated;

-- 3. Push one visit's time of day and crew onto the job's later visits ------------------------------------------

-- Jobber's "Save and... Update Future Visits". Its own dialog offers four boxes; ours offers the two that act
-- on something we have. Line items wait for part 11 to give a visit its own, the repeating schedule belongs to
-- the guarded rebuild above rather than to a quiet checkbox, and a lasting instruction belongs on the job,
-- where every visit already reads it, including visits made later.
create or replace function public.apply_visit_to_future(
  target_organization_id uuid,
  target_job_id uuid,
  source_visit_id uuid,
  copy_time_of_day boolean,
  copy_assigned_team boolean,
  new_idempotency_key text,
  new_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  source_visit public.job_visits;
  receipt_id uuid;
  existing_receipt public.job_command_receipts;
  target_ids uuid[];
  updated_count integer;
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  if not coalesce(copy_time_of_day, false) and not coalesce(copy_assigned_team, false) then
    raise exception 'Choose at least one setting to apply to the later visits.'
      using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  select visit.* into source_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = source_visit_id;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;
  -- "Later" is measured from this visit's day, so a backlog visit with no date has no later visits to name.
  if source_visit.visit_date is null then
    raise exception 'Give this visit a date before applying it to later visits.'
      using errcode = 'check_violation';
  end if;

  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'apply_visit_to_future', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'apply_visit_to_future'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'These settings were already applied differently.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  -- Settle the target set once, so both halves act on the same visits and the reported count means both.
  -- Completed visits and the backlog are out; so is the source visit, which already carries these values.
  select coalesce(array_agg(visit.id order by visit.visit_date, visit.position), array[]::uuid[])
  into target_ids
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id <> source_visit_id
    and visit.completed_at is null
    and visit.visit_date is not null
    and visit.visit_date > source_visit.visit_date;

  updated_count := coalesce(array_length(target_ids, 1), 0);

  if updated_count > 0 then
    if coalesce(copy_time_of_day, false) then
      -- The three clock fields travel together. Sending them one at a time could pass through a state the
      -- table's own constraints reject, such as an all-day visit still holding a start time.
      update public.job_visits
      set start_time = source_visit.start_time,
          end_time = source_visit.end_time,
          all_day = source_visit.all_day,
          revision = revision + 1,
          updated_at = now()
      where organization_id = target_organization_id
        and id = any(target_ids);
    end if;

    if coalesce(copy_assigned_team, false) then
      delete from public.job_visit_assignments
      where organization_id = target_organization_id
        and visit_id = any(target_ids);

      insert into public.job_visit_assignments (organization_id, visit_id, user_id)
      select target_organization_id, target_visit, assignment.user_id
      from unnest(target_ids) as target_visit
      cross join public.job_visit_assignments as assignment
      where assignment.organization_id = target_organization_id
        and assignment.visit_id = source_visit_id
      on conflict do nothing;

      -- The crew is not a column on the visit, so a crew-only change still has to move the row's revision or
      -- an open editor would never learn that what it is showing is out of date.
      if not coalesce(copy_time_of_day, false) then
        update public.job_visits
        set revision = revision + 1,
            updated_at = now()
        where organization_id = target_organization_id
          and id = any(target_ids);
      end if;
    end if;
  end if;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visits_updated_forward',
    caller,
    source_visit_id,
    jsonb_build_object(
      'count', updated_count,
      'time_of_day', coalesce(copy_time_of_day, false),
      'assigned_team', coalesce(copy_assigned_team, false)
    )
  );

  final_result := jsonb_build_object('applied', true, 'updated_count', updated_count);
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

comment on function public.apply_visit_to_future(uuid, uuid, uuid, boolean, boolean, text, text) is
  'Copies one visit''s time of day and/or assigned crew onto the same job''s later dated, incomplete visits. '
  'Checks jobs.schedule, skips completed and undated visits, is idempotent by key, and appends a '
  'visits_updated_forward history row with the count.';

revoke all on function public.apply_visit_to_future(uuid, uuid, uuid, boolean, boolean, text, text) from public;
revoke execute on function public.apply_visit_to_future(uuid, uuid, uuid, boolean, boolean, text, text) from anon;
grant execute on function public.apply_visit_to_future(uuid, uuid, uuid, boolean, boolean, text, text)
  to authenticated;
