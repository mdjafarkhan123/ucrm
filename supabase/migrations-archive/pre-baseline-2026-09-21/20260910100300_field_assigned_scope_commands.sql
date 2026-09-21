-- Jobs, Part 15a-2: narrow the Field role to assigned work only.
-- Step 4 of 4. The order and the reasoning are in 20260910100000_field_assigned_scope_foundation.sql.

-- 6. The eight write commands ----------------------------------------------------------------------------

-- The write hole this narrowing opens. A Field member keeps jobs.complete, time.track_own and
-- expenses.record, and every one of these commands checked only that write key, so without this a field
-- worker could complete a visit, or log time and expenses, against a job they can no longer open. The
-- precondition goes immediately after the signed-in check, before anything is read or locked.

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
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
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
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
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

  if exists (
    select 1
    from public.invoice_sources as claim
    where claim.organization_id = target_organization_id
      and claim.visit_id = target_visit_id
      and claim.source_kind = 'visit'
  ) then
    raise exception 'This visit is already on an invoice, so it cannot be reopened.' using errcode = 'P0410',
      hint = 'Correct the invoice instead if the work was different from what was billed.';
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

create or replace function public.add_job_time_entry(
  target_organization_id uuid,
  target_job_id uuid,
  target_user_id uuid,
  started_at timestamptz,
  minutes integer,
  target_visit_id uuid default null,
  notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  job_closed boolean;
  recorded_rate bigint;
  new_entry public.job_time_entries;
begin
  if caller is null then
    raise exception 'You must be signed in to record hours.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  -- No row lock. Hours are appended to a job, never derived from it, so two people recording time at once
  -- have nothing to fight over -- and locking the job here would make every timesheet entry queue behind
  -- whatever else is editing the job.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  job_closed := current_job.status <> 'active';

  if not private.can_write_job_time(target_organization_id, caller, target_user_id, job_closed) then
    if job_closed then
      raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to record these hours.' using errcode = 'insufficient_privilege';
  end if;

  -- Hours belong to someone who works here. The foreign key would refuse a stranger anyway; this refuses a
  -- person who has left with a sentence instead of a constraint name.
  if not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = target_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That person is not on this team.' using errcode = 'P0404';
  end if;

  if target_visit_id is not null and not exists (
    select 1
    from public.job_visits as visit
    where visit.organization_id = target_organization_id
      and visit.job_id = target_job_id
      and visit.id = target_visit_id
  ) then
    raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
  end if;

  -- The one and only read of the rate profile in this file. Null is kept as null: nobody has said what this
  -- person costs, and unrated hours are reported as unrated rather than valued at nothing.
  select profile.cost_per_hour_minor into recorded_rate
  from public.organization_member_cost_profiles as profile
  where profile.organization_id = target_organization_id
    and profile.user_id = target_user_id;

  insert into public.job_time_entries (
    organization_id, job_id, visit_id, user_id, started_at, minutes, notes, cost_per_hour_minor, created_by
  )
  values (
    target_organization_id, target_job_id, target_visit_id, target_user_id,
    add_job_time_entry.started_at, add_job_time_entry.minutes,
    nullif(trim(coalesce(add_job_time_entry.notes, '')), ''), recorded_rate, caller
  )
  returning * into new_entry;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close, new_values
  )
  values (
    target_organization_id, target_job_id, 'time_entry_added', 'time_entry', new_entry.id, caller, job_closed,
    jsonb_build_object(
      'user_id', new_entry.user_id,
      'visit_id', new_entry.visit_id,
      'started_at', new_entry.started_at,
      'minutes', new_entry.minutes,
      'cost_per_hour_minor', new_entry.cost_per_hour_minor,
      'cost_total_minor', new_entry.cost_total_minor
    )
  );

  return jsonb_build_object('id', new_entry.id, 'after_close', job_closed);
end;
$$;

create or replace function public.update_job_time_entry(
  target_organization_id uuid,
  target_job_id uuid,
  target_entry_id uuid,
  started_at timestamptz,
  minutes integer,
  target_visit_id uuid default null,
  notes text default null,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_time_entries;
  updated public.job_time_entries;
begin
  if caller is null then
    raise exception 'You must be signed in to change hours.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- The entry is locked, not the job: two corrections to the same entry queue, and corrections to different
  -- entries on the same job do not wait for each other.
  select entry.* into existing
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and entry.id = target_entry_id
  for update;
  if not found then
    raise exception 'Those hours could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_time(target_organization_id, caller, existing.user_id, job_closed) then
    if job_closed then
      raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to change these hours.' using errcode = 'insufficient_privilege';
  end if;

  if target_visit_id is not null and not exists (
    select 1
    from public.job_visits as visit
    where visit.organization_id = target_organization_id
      and visit.job_id = target_job_id
      and visit.id = target_visit_id
  ) then
    raise exception 'That visit could not be found on this job.' using errcode = 'P0404';
  end if;

  -- cost_per_hour_minor is absent on purpose. The rate stays as recorded; only the duration it applies to can
  -- change, and the generated cost column follows it.
  update public.job_time_entries as entry
  set visit_id = target_visit_id,
      started_at = update_job_time_entry.started_at,
      minutes = update_job_time_entry.minutes,
      notes = nullif(trim(coalesce(update_job_time_entry.notes, '')), '')
  where entry.organization_id = target_organization_id
    and entry.id = target_entry_id
  returning * into updated;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values, new_values
  )
  values (
    target_organization_id, target_job_id, 'time_entry_updated', 'time_entry', target_entry_id, caller,
    job_closed,
    nullif(trim(coalesce(update_job_time_entry.reason, '')), ''),
    jsonb_build_object(
      'visit_id', existing.visit_id,
      'started_at', existing.started_at,
      'minutes', existing.minutes,
      'cost_total_minor', existing.cost_total_minor
    ),
    jsonb_build_object(
      'visit_id', updated.visit_id,
      'started_at', updated.started_at,
      'minutes', updated.minutes,
      'cost_total_minor', updated.cost_total_minor
    )
  );

  return jsonb_build_object('id', updated.id, 'after_close', job_closed);
end;
$$;

create or replace function public.delete_job_time_entry(
  target_organization_id uuid,
  target_job_id uuid,
  target_entry_id uuid,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_time_entries;
begin
  if caller is null then
    raise exception 'You must be signed in to remove hours.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  select entry.* into existing
  from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.job_id = target_job_id
    and entry.id = target_entry_id
  for update;
  if not found then
    raise exception 'Those hours could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_time(target_organization_id, caller, existing.user_id, job_closed) then
    if job_closed then
      raise exception 'A closed job''s hours can only be changed by someone who manages the team''s time.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to remove these hours.' using errcode = 'insufficient_privilege';
  end if;

  -- The trail is written first and keeps the whole row. job_costing_events holds subject_id as a plain id
  -- precisely so the evidence outlives the entry it describes.
  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values
  )
  values (
    target_organization_id, target_job_id, 'time_entry_deleted', 'time_entry', target_entry_id, caller,
    job_closed,
    nullif(trim(coalesce(delete_job_time_entry.reason, '')), ''),
    jsonb_build_object(
      'user_id', existing.user_id,
      'visit_id', existing.visit_id,
      'started_at', existing.started_at,
      'minutes', existing.minutes,
      'cost_per_hour_minor', existing.cost_per_hour_minor,
      'cost_total_minor', existing.cost_total_minor
    )
  );

  delete from public.job_time_entries as entry
  where entry.organization_id = target_organization_id
    and entry.id = target_entry_id;

  return jsonb_build_object('id', target_entry_id, 'after_close', job_closed);
end;
$$;

create or replace function public.add_job_expense(
  target_organization_id uuid,
  target_job_id uuid,
  name text,
  expense_date date,
  total_minor bigint,
  accounting_code text default null,
  description text default null,
  reimburse_to_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_job public.jobs;
  job_closed boolean;
  new_expense public.job_expenses;
begin
  if caller is null then
    raise exception 'You must be signed in to record an expense.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  -- No row lock. An expense is appended to a job, never derived from it, so two people recording an expense
  -- at once have nothing to fight over -- and locking the job here would make every expense queue behind
  -- whatever else is editing the job.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  job_closed := current_job.status <> 'active';

  -- The person recording it is the person who owns it, so the own/team gate is asked about the caller.
  if not private.can_write_job_expense(target_organization_id, caller, caller, job_closed) then
    if job_closed then
      raise exception 'A closed job''s expenses can only be changed by someone who manages the team''s expenses.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to record this expense.' using errcode = 'insufficient_privilege';
  end if;

  -- Someone to pay back has to work here. The foreign key would refuse a stranger anyway; this refuses a
  -- person who has left with a sentence instead of a constraint name. Null is fine -- the business paid it.
  if reimburse_to_user_id is not null and not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = reimburse_to_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That person is not on this team.' using errcode = 'P0404';
  end if;

  insert into public.job_expenses (
    organization_id, job_id, name, accounting_code, description, expense_date, total_minor,
    reimburse_to_user_id, created_by
  )
  values (
    target_organization_id, target_job_id,
    trim(add_job_expense.name),
    nullif(trim(coalesce(add_job_expense.accounting_code, '')), ''),
    nullif(trim(coalesce(add_job_expense.description, '')), ''),
    add_job_expense.expense_date, add_job_expense.total_minor,
    add_job_expense.reimburse_to_user_id, caller
  )
  returning * into new_expense;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close, new_values
  )
  values (
    target_organization_id, target_job_id, 'expense_added', 'expense', new_expense.id, caller, job_closed,
    jsonb_build_object(
      'name', new_expense.name,
      'accounting_code', new_expense.accounting_code,
      'expense_date', new_expense.expense_date,
      'total_minor', new_expense.total_minor,
      'reimburse_to_user_id', new_expense.reimburse_to_user_id
    )
  );

  return jsonb_build_object('id', new_expense.id, 'after_close', job_closed);
end;
$$;

create or replace function public.update_job_expense(
  target_organization_id uuid,
  target_job_id uuid,
  target_expense_id uuid,
  name text,
  expense_date date,
  total_minor bigint,
  accounting_code text default null,
  description text default null,
  reimburse_to_user_id uuid default null,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_expenses;
  updated public.job_expenses;
begin
  if caller is null then
    raise exception 'You must be signed in to change an expense.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  -- The expense is locked, not the job: two corrections to the same expense queue, and corrections to
  -- different expenses on the same job do not wait for each other.
  select expense.* into existing
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and expense.id = target_expense_id
  for update;
  if not found then
    raise exception 'That expense could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_expense(target_organization_id, caller, existing.created_by, job_closed) then
    if job_closed then
      raise exception 'A closed job''s expenses can only be changed by someone who manages the team''s expenses.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to change this expense.' using errcode = 'insufficient_privilege';
  end if;

  if reimburse_to_user_id is not null and not exists (
    select 1
    from public.organization_members as member
    where member.organization_id = target_organization_id
      and member.user_id = reimburse_to_user_id
      and member.status <> 'removed'
  ) then
    raise exception 'That person is not on this team.' using errcode = 'P0404';
  end if;

  -- created_by is absent on purpose: the expense keeps the person who recorded it.
  update public.job_expenses as expense
  set name = trim(update_job_expense.name),
      accounting_code = nullif(trim(coalesce(update_job_expense.accounting_code, '')), ''),
      description = nullif(trim(coalesce(update_job_expense.description, '')), ''),
      expense_date = update_job_expense.expense_date,
      total_minor = update_job_expense.total_minor,
      reimburse_to_user_id = update_job_expense.reimburse_to_user_id
  where expense.organization_id = target_organization_id
    and expense.id = target_expense_id
  returning * into updated;

  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values, new_values
  )
  values (
    target_organization_id, target_job_id, 'expense_updated', 'expense', target_expense_id, caller,
    job_closed,
    nullif(trim(coalesce(update_job_expense.reason, '')), ''),
    jsonb_build_object(
      'name', existing.name,
      'accounting_code', existing.accounting_code,
      'expense_date', existing.expense_date,
      'total_minor', existing.total_minor,
      'reimburse_to_user_id', existing.reimburse_to_user_id
    ),
    jsonb_build_object(
      'name', updated.name,
      'accounting_code', updated.accounting_code,
      'expense_date', updated.expense_date,
      'total_minor', updated.total_minor,
      'reimburse_to_user_id', updated.reimburse_to_user_id
    )
  );

  return jsonb_build_object('id', updated.id, 'after_close', job_closed);
end;
$$;

create or replace function public.delete_job_expense(
  target_organization_id uuid,
  target_job_id uuid,
  target_expense_id uuid,
  reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  job_closed boolean;
  existing public.job_expenses;
begin
  if caller is null then
    raise exception 'You must be signed in to remove an expense.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_job_is_visible(target_organization_id, caller, target_job_id) then
    raise exception 'You do not have access to this job.' using errcode = 'insufficient_privilege';
  end if;

  select job.status <> 'active' into job_closed
  from public.jobs as job
  where job.organization_id = target_organization_id and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  select expense.* into existing
  from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.job_id = target_job_id
    and expense.id = target_expense_id
  for update;
  if not found then
    raise exception 'That expense could not be found.' using errcode = 'P0404';
  end if;

  if not private.can_write_job_expense(target_organization_id, caller, existing.created_by, job_closed) then
    if job_closed then
      raise exception 'A closed job''s expenses can only be changed by someone who manages the team''s expenses.'
        using errcode = 'P0410';
    end if;
    raise exception 'You do not have access to remove this expense.' using errcode = 'insufficient_privilege';
  end if;

  -- The trail is written first and keeps the whole row. job_costing_events holds subject_id as a plain id
  -- precisely so the evidence outlives the expense it describes. The receipt files are cleaned up by the
  -- browser through the attachment route before this command runs, because R2 is reachable only from there.
  insert into public.job_costing_events (
    organization_id, job_id, event_type, subject_kind, subject_id, actor_id, after_close,
    reason, prior_values
  )
  values (
    target_organization_id, target_job_id, 'expense_deleted', 'expense', target_expense_id, caller,
    job_closed,
    nullif(trim(coalesce(delete_job_expense.reason, '')), ''),
    jsonb_build_object(
      'name', existing.name,
      'accounting_code', existing.accounting_code,
      'expense_date', existing.expense_date,
      'total_minor', existing.total_minor,
      'reimburse_to_user_id', existing.reimburse_to_user_id
    )
  );

  delete from public.job_expenses as expense
  where expense.organization_id = target_organization_id
    and expense.id = target_expense_id;

  return jsonb_build_object('id', target_expense_id, 'after_close', job_closed);
end;
$$;


