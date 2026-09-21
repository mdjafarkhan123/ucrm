-- Jobs Part 9: the commands that schedule a job's visits after it exists.
--
-- Part 7 creates a one-off job with its first visits in a single transaction. Part 9 gives the job's detail
-- page the four things a dispatcher does afterwards: add more visits, edit one visit, move a batch of visits
-- by a number of days, and remove a visit. Each command mirrors the shape the earlier parts settled on: it
-- checks its own permission, does the write under the table's own shape guards, appends a redacted history
-- row, and never touches a completed visit. Add and bulk-move claim an idempotency key first so a double
-- click or a retried request cannot duplicate visits or shift their dates twice; single edit and delete carry
-- the visit's own revision so two dispatchers editing the same visit cannot silently overwrite each other,
-- while leaving the job's title-edit revision (Part 8) untouched so scheduling and detail edits never collide.

-- 1. The permission this part brings to life -----------------------------------------------------------------

-- jobs.schedule was named in the approved contract but deliberately left unseeded until scheduling existed, so
-- the Team access editor would not show a switch that turned nothing on. Part 9 is that behavior, so the key
-- and its role grants land now, mirroring who already holds jobs.edit: owner, admin, office and sales run
-- jobs; field crew still only view.
insert into public.permissions (key, description)
values ('jobs.schedule', 'Schedule a job''s visits: add, move, reschedule and remove them')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions (role, permission_key)
values
  ('owner', 'jobs.schedule'),
  ('admin', 'jobs.schedule'),
  ('office', 'jobs.schedule'),
  ('sales', 'jobs.schedule')
on conflict (role, permission_key) do nothing;

-- 2. A per-visit revision for optimistic concurrency ---------------------------------------------------------

-- The job carries a revision for its staged title/instructions edit (Part 8). A visit needs its own so that
-- rescheduling a visit does not clash with an unrelated title edit, and two people editing the same visit do
-- clash. Existing rows start at 0; every edit and every move bumps it.
alter table public.job_visits
  add column if not exists revision integer not null default 0;

-- 3. Add visits to an existing job -------------------------------------------------------------------------

-- One to twenty visits appended to a job that already exists. The create-visits dialog picks the days; each
-- visit's time, title, instructions and people are set here or edited afterwards. Manual, duplicated and
-- return visits all come through this one door — the source rides in on each element.
create or replace function public.add_job_visits(
  target_organization_id uuid,
  target_job_id uuid,
  visits jsonb,
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
  visit_count integer;
  next_position integer;
  visit_element jsonb;
  new_visit public.job_visits;
  assignee_element jsonb;
  added_ids uuid[] := array[]::uuid[];
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  visit_count := coalesce(jsonb_array_length(visits), 0);
  if visit_count < 1 or visit_count > 20 then
    raise exception 'Between 1 and 20 visits can be added at once.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  -- The job must exist in this organization and still be open. A closed job is not scheduled against; it is
  -- reopened first, which is an explicit later action. Not found and forbidden read the same to a stranger.
  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;
  if current_job.status = 'closed' then
    raise exception 'A closed job cannot be scheduled. Reopen it first.' using errcode = 'P0410';
  end if;

  -- Claim the key before any work. on conflict do nothing waits for a racing transaction to commit and then
  -- returns no row, so the loser reads the winner's committed result instead of adding a second batch.
  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'add_job_visits', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'add_job_visits'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'Those visits were already added with different details.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  -- New visits append after the job's current visits. position orders the job's own list, not the calendar.
  select coalesce(max(visit.position), -1) + 1 into next_position
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id;

  for visit_element in select value from jsonb_array_elements(visits) as v(value)
  loop
    insert into public.job_visits (
      organization_id, job_id, position, visit_date, start_time, end_time, all_day, title, instructions,
      source
    ) values (
      target_organization_id,
      target_job_id,
      next_position,
      nullif(visit_element->>'visit_date', '')::date,
      nullif(visit_element->>'start_time', '')::time,
      nullif(visit_element->>'end_time', '')::time,
      coalesce((visit_element->>'all_day')::boolean, false),
      nullif(trim(visit_element->>'title'), ''),
      nullif(trim(visit_element->>'instructions'), ''),
      coalesce(nullif(visit_element->>'source', ''), 'manual')
    )
    returning * into new_visit;

    next_position := next_position + 1;
    added_ids := array_append(added_ids, new_visit.id);

    if jsonb_typeof(visit_element->'assignee_ids') = 'array' then
      for assignee_element in select value from jsonb_array_elements(visit_element->'assignee_ids') as a(value)
      loop
        insert into public.job_visit_assignments (organization_id, visit_id, user_id)
        values (target_organization_id, new_visit.id, (assignee_element #>> '{}')::uuid)
        on conflict do nothing;
      end loop;
    end if;
  end loop;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visits_added',
    caller,
    jsonb_build_object('count', visit_count)
  );

  final_result := jsonb_build_object('applied', true, 'added_count', visit_count, 'visit_ids', to_jsonb(added_ids));
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

comment on function public.add_job_visits(uuid, uuid, jsonb, text, text) is
  'Appends 1-20 visits to an existing open job. Checks jobs.schedule, idempotent by key, appends a '
  'visits_added history row. Visit shape is guarded by the job_visits table constraints.';

-- 4. Edit one visit ----------------------------------------------------------------------------------------

-- The whole desired state of one visit's schedule and content. Passing the complete state, not a diff, lets
-- the table's own constraints be the single judge of a valid shape: an unscheduled visit sends a null date, an
-- anytime visit a date with no time, a booked one a date and a start. assignee_ids null leaves the crew
-- unchanged; an array (including an empty one) replaces it exactly.
create or replace function public.update_job_visit(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid,
  expected_revision integer,
  new_visit_date date,
  new_start_time time,
  new_end_time time,
  new_all_day boolean,
  new_title text,
  new_instructions text,
  new_assignee_ids jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_visit public.job_visits;
  clean_title text := nullif(trim(coalesce(new_title, '')), '');
  clean_instructions text := nullif(trim(coalesce(new_instructions, '')), '');
  changed text[] := array[]::text[];
  assignee_element jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  -- Lock the visit so the revision we check is the revision we write against, and confirm it belongs to this
  -- job in this organization in the same breath.
  select visit.* into current_visit
  from public.job_visits as visit
  where visit.organization_id = target_organization_id
    and visit.job_id = target_job_id
    and visit.id = target_visit_id
  for update;
  if not found then
    raise exception 'That visit could not be found.' using errcode = 'P0404';
  end if;

  -- A completed visit is a record of work done. Scheduling never rewrites it; the contract protects it under
  -- every edit path.
  if current_visit.completed_at is not null then
    raise exception 'A completed visit cannot be rescheduled.' using errcode = 'P0410';
  end if;

  if current_visit.revision is distinct from expected_revision then
    raise exception 'Someone else changed this visit. Reload to see the latest.' using errcode = 'P0409';
  end if;

  -- Which fields moved, for a redacted history note: field names only, never before-and-after values.
  if new_visit_date is distinct from current_visit.visit_date
    or new_start_time is distinct from current_visit.start_time
    or new_end_time is distinct from current_visit.end_time
    or coalesce(new_all_day, false) is distinct from current_visit.all_day then
    changed := array_append(changed, 'schedule');
  end if;
  if clean_title is distinct from current_visit.title then
    changed := array_append(changed, 'title');
  end if;
  if clean_instructions is distinct from current_visit.instructions then
    changed := array_append(changed, 'instructions');
  end if;
  if new_assignee_ids is not null and jsonb_typeof(new_assignee_ids) = 'array' then
    changed := array_append(changed, 'assignees');
  end if;

  -- The table's shape constraints (a timed visit needs a date, an all-day visit carries no clock time, an end
  -- must follow a start) are the single judge here, surfacing a bad combination as a 23514 the API turns into
  -- a form error rather than a second guard that could disagree with the table.
  update public.job_visits
  set visit_date = new_visit_date,
      start_time = new_start_time,
      end_time = new_end_time,
      all_day = coalesce(new_all_day, false),
      title = clean_title,
      instructions = clean_instructions,
      revision = current_visit.revision + 1,
      updated_at = now()
  where organization_id = target_organization_id
    and id = target_visit_id;

  -- Replace the crew exactly when a set was sent. An assignee who is not a member of this organization is
  -- refused by the assignment's composite foreign key, surfacing as a form error.
  if new_assignee_ids is not null and jsonb_typeof(new_assignee_ids) = 'array' then
    delete from public.job_visit_assignments
    where organization_id = target_organization_id and visit_id = target_visit_id;
    for assignee_element in select value from jsonb_array_elements(new_assignee_ids) as a(value)
    loop
      insert into public.job_visit_assignments (organization_id, visit_id, user_id)
      values (target_organization_id, target_visit_id, (assignee_element #>> '{}')::uuid)
      on conflict do nothing;
    end loop;
  end if;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visit_updated',
    caller,
    target_visit_id,
    jsonb_build_object('changed', to_jsonb(changed))
  );

  return jsonb_build_object('revision', current_visit.revision + 1);
end;
$$;

comment on function public.update_job_visit(uuid, uuid, uuid, integer, date, time, time, boolean, text, text, jsonb) is
  'Edits one visit''s schedule shape, title, instructions and crew. Checks jobs.schedule, refuses a completed '
  'visit (P0410) and a stale revision (P0409), bumps the visit revision and appends a visit_updated row.';

-- 5. Move a batch of visits by a number of days ------------------------------------------------------------

-- Bulk reschedule: shift the chosen dated, incomplete visits forward or back by whole days. Unscheduled
-- visits have no date to shift and completed visits are protected, so both are silently skipped rather than
-- refused — the returned count says how many actually moved. Idempotent by key so a retry cannot double-shift.
create or replace function public.move_job_visits(
  target_organization_id uuid,
  target_job_id uuid,
  visit_ids jsonb,
  day_offset integer,
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
  id_list uuid[];
  moved_count integer;
  final_result jsonb;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
  end if;

  if day_offset is null or day_offset = 0 then
    raise exception 'Choose how many days to move the visits.' using errcode = 'check_violation';
  end if;
  if abs(day_offset) > 3650 then
    raise exception 'Visits can only be moved within ten years.' using errcode = 'check_violation';
  end if;
  if jsonb_typeof(visit_ids) is distinct from 'array' or jsonb_array_length(visit_ids) < 1 then
    raise exception 'Choose at least one visit to move.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(visit_ids) > 100 then
    raise exception 'Up to 100 visits can be moved at once.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if char_length(trim(coalesce(new_request_hash, ''))) < 1 then
    raise exception 'A request fingerprint is required.' using errcode = 'check_violation';
  end if;

  select job.* into current_job
  from public.jobs as job
  where job.organization_id = target_organization_id
    and job.id = target_job_id;
  if not found then
    raise exception 'That job could not be found.' using errcode = 'P0404';
  end if;

  insert into public.job_command_receipts (organization_id, action, idempotency_key, request_hash)
  values (target_organization_id, 'move_job_visits', new_idempotency_key, new_request_hash)
  on conflict (organization_id, action, idempotency_key) do nothing
  returning id into receipt_id;

  if receipt_id is null then
    select receipt.* into existing_receipt
    from public.job_command_receipts as receipt
    where receipt.organization_id = target_organization_id
      and receipt.action = 'move_job_visits'
      and receipt.idempotency_key = new_idempotency_key;

    if existing_receipt.request_hash is distinct from new_request_hash then
      raise exception 'Those visits were already moved differently.' using errcode = 'P0409';
    end if;

    return coalesce(existing_receipt.result, '{}'::jsonb) || jsonb_build_object('applied', false);
  end if;

  select array_agg((element #>> '{}')::uuid) into id_list
  from jsonb_array_elements(visit_ids) as element;

  -- One statement takes the row locks it needs. Only dated, incomplete visits of this job move; unscheduled
  -- and completed visits in the list fall through the where clause untouched.
  update public.job_visits
  set visit_date = visit_date + day_offset,
      revision = revision + 1,
      updated_at = now()
  where organization_id = target_organization_id
    and job_id = target_job_id
    and id = any(id_list)
    and visit_date is not null
    and completed_at is null;
  get diagnostics moved_count = row_count;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visits_moved',
    caller,
    jsonb_build_object('count', moved_count, 'day_offset', day_offset)
  );

  final_result := jsonb_build_object('applied', true, 'moved_count', moved_count);
  update public.job_command_receipts set result = final_result where id = receipt_id;
  return final_result;
end;
$$;

comment on function public.move_job_visits(uuid, uuid, jsonb, integer, text, text) is
  'Shifts the dated, incomplete visits in the list by day_offset days. Checks jobs.schedule, idempotent by '
  'key, skips unscheduled and completed visits, and appends a visits_moved history row with the moved count.';

-- 6. Remove one visit --------------------------------------------------------------------------------------

-- Deleting a visit affects that visit only; its assignments cascade with it. A completed visit is protected;
-- removing the whole job (with all its visits) is a different, confirmed command in an earlier part.
create or replace function public.delete_job_visit(
  target_organization_id uuid,
  target_job_id uuid,
  target_visit_id uuid,
  expected_revision integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  current_visit public.job_visits;
begin
  if caller is null then
    raise exception 'You must be signed in to schedule a job.' using errcode = 'insufficient_privilege';
  end if;
  if not private.member_has_permission(target_organization_id, caller, 'jobs.schedule') then
    raise exception 'You do not have access to schedule this job.' using errcode = 'insufficient_privilege';
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
    raise exception 'A completed visit cannot be removed.' using errcode = 'P0410';
  end if;

  if current_visit.revision is distinct from expected_revision then
    raise exception 'Someone else changed this visit. Reload to see the latest.' using errcode = 'P0409';
  end if;

  delete from public.job_visits
  where organization_id = target_organization_id
    and id = target_visit_id;

  insert into public.job_events (organization_id, job_id, event_type, actor_id, related_visit_id, metadata)
  values (
    target_organization_id,
    target_job_id,
    'visit_deleted',
    caller,
    target_visit_id,
    '{}'::jsonb
  );

  return jsonb_build_object('applied', true);
end;
$$;

comment on function public.delete_job_visit(uuid, uuid, uuid, integer) is
  'Removes one incomplete visit and its assignments. Checks jobs.schedule, refuses a completed visit (P0410) '
  'and a stale revision (P0409), and appends a visit_deleted history row.';

-- 7. Grants --------------------------------------------------------------------------------------------------

revoke all on function public.add_job_visits(uuid, uuid, jsonb, text, text) from public;
revoke execute on function public.add_job_visits(uuid, uuid, jsonb, text, text) from anon;
grant execute on function public.add_job_visits(uuid, uuid, jsonb, text, text) to authenticated;

revoke all on function public.update_job_visit(uuid, uuid, uuid, integer, date, time, time, boolean, text, text, jsonb) from public;
revoke execute on function public.update_job_visit(uuid, uuid, uuid, integer, date, time, time, boolean, text, text, jsonb) from anon;
grant execute on function public.update_job_visit(uuid, uuid, uuid, integer, date, time, time, boolean, text, text, jsonb) to authenticated;

revoke all on function public.move_job_visits(uuid, uuid, jsonb, integer, text, text) from public;
revoke execute on function public.move_job_visits(uuid, uuid, jsonb, integer, text, text) from anon;
grant execute on function public.move_job_visits(uuid, uuid, jsonb, integer, text, text) to authenticated;

revoke all on function public.delete_job_visit(uuid, uuid, uuid, integer) from public;
revoke execute on function public.delete_job_visit(uuid, uuid, uuid, integer) from anon;
grant execute on function public.delete_job_visit(uuid, uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
