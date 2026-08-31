-- Contractor Settings Part 6D, slice 5a: record-level enrollment control commands + safe per-record read.
--
-- docs/automation-behavior-contract.md § Record-level Automation controls ("Authorized actions are Manual
-- enroll (after preview), Pause, Resume, Skip next step, and Stop ... Controls never imply that stopping
-- Automation changes Quote truth or recalls an already accepted message") and § Enrollment, re-entry, and
-- overlap ("Manual enrollment uniqueness is recipe version + subject + explicit command id ... Preview shows
-- recipe version, recipient/channel, first due time, stop/safety results, overlap, and expected message
-- count. Confirm uses a fresh preview revision and an idempotency key").
--
-- These are staff controls only. The reply-driven auto-pause is dependency-owned (Communications) and is not
-- built here. Every write is SECURITY DEFINER, executed by service_role AFTER the route has resolved feature
-- entitlement, the automations.control_enrollment permission, and platform authority
-- (src/lib/server/access/automation.ts). The command re-checks organization ownership, enrollment/recipe
-- state, and an idempotency key atomically; it never trusts the caller for access.
--
-- Resume timing is GHL-accurate (Jafar, 2026-08-31): pausing NEVER moves a reminder's send time. Pause records
-- the pending work item's absolute due_at and cancels the item; resume re-creates the item at that same due_at
-- (already past -> fires the next worker cycle). It is not a wait restart.

-- 1. Spine: let an enrollment exist without a triggering event (manual enroll has none). --------------------
-- Automatic enrollment keeps its event evidence (on delete restrict); manual enrollment records the actor and
-- time instead. The check makes the two sources mutually exclusive on the evidence column.
alter table private.automation_enrollments
  alter column trigger_event_id drop not null;

alter table private.automation_enrollments
  add column enrolled_by uuid,
  -- Set when a manual pause cancels the pending work item, so resume restores the exact original send time.
  add column paused_work_due_at timestamptz;

comment on column private.automation_enrollments.enrolled_by is
  'The user who manually enrolled this subject. Null for automatic (event-sourced) enrollments.';
comment on column private.automation_enrollments.paused_work_due_at is
  'While paused, the absolute due_at of the work item that pause cancelled. Resume re-creates the item at this '
  'time so pausing never delays a reminder. Null when active or when no step was pending at pause.';

alter table private.automation_enrollments
  add constraint automation_enrollments_source_evidence_ck
  check ((source = 'event') = (trigger_event_id is not null));

-- 2. Idempotency receipts for enrollment commands (separate from the recipe/draft receipts). --------------
create table public.automation_enrollment_command_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  idempotency_key uuid not null,
  command text not null check (command in ('enroll', 'pause', 'resume', 'skip', 'stop')),
  subject_type text,
  subject_id uuid,
  enrollment_id uuid,
  -- The exact response the first application produced, replayed verbatim on a retry.
  result jsonb not null,
  created_at timestamptz not null default now(),
  constraint automation_enrollment_command_receipts_key_unique unique (organization_id, idempotency_key)
);

comment on table public.automation_enrollment_command_receipts is
  'Private idempotency receipts for record-level enrollment commands. A retried submit replays its stored '
  'result. Retained at least 24h; batched indexed cleanup is owned by 6E.';

revoke all on table public.automation_enrollment_command_receipts from public, anon, authenticated;

-- 3. Preview: read-only eligibility for one record before a manual enroll. -------------------------------
-- Returns plain, tenant-safe facts only: recipe version, first due time, expected customer-message count,
-- same-subject overlap, and whether this subject is already in a live enrollment for this recipe. Never a
-- definition, payload, or internal key.
create or replace function public.preview_automation_manual_enrollment(
  p_organization_id uuid,
  p_recipe_id uuid,
  p_subject_type text,
  p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  recipe public.automation_recipes%rowtype;
  version public.automation_recipe_versions%rowtype;
  expected_messages integer;
  already_enrolled boolean;
  overlap_same integer;
  overlap_other integer;
begin
  if p_subject_type is distinct from 'quote' then
    return jsonb_build_object('eligible', false, 'reason', 'unsupported_subject');
  end if;

  select * into recipe
  from public.automation_recipes
  where id = p_recipe_id and organization_id = p_organization_id;
  if not found then
    return jsonb_build_object('eligible', false, 'reason', 'recipe_not_found');
  end if;
  if recipe.status <> 'active' or recipe.current_version_id is null then
    return jsonb_build_object('eligible', false, 'reason', 'recipe_not_active');
  end if;

  select * into version
  from public.automation_recipe_versions
  where id = recipe.current_version_id and organization_id = p_organization_id;
  if not found then
    return jsonb_build_object('eligible', false, 'reason', 'recipe_not_active');
  end if;

  select count(*) into expected_messages
  from jsonb_array_elements(version.definition -> 'steps') as step
  where step ->> 'type' = 'action';

  select
    count(*) filter (where recipe_id = p_recipe_id),
    count(*) filter (where recipe_id <> p_recipe_id)
  into overlap_same, overlap_other
  from private.automation_enrollments
  where organization_id = p_organization_id
    and subject_type = p_subject_type
    and subject_id = p_subject_id
    and state in ('active', 'paused');

  already_enrolled := overlap_same > 0;

  return jsonb_build_object(
    'eligible', not already_enrolled,
    'reason', case when already_enrolled then 'already_enrolled' else null end,
    'recipe_id', p_recipe_id,
    'recipe_name', recipe.name,
    'version_id', version.id,
    'version_number', version.version_number,
    'first_due_at', now(),
    'expected_message_count', expected_messages,
    'overlap_same_recipe', overlap_same,
    'overlap_other_recipes', overlap_other
  );
end;
$$;

revoke all on function public.preview_automation_manual_enrollment(uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.preview_automation_manual_enrollment(uuid, uuid, text, uuid) to service_role;

comment on function public.preview_automation_manual_enrollment(uuid, uuid, text, uuid) is
  'Read-only manual-enroll eligibility for one record: recipe version, first due time, expected message count, '
  'and same-subject overlap. Safe projection; service role only.';

-- 4. Manual enroll: seed one enrollment + its first step, mirroring automatic intake. --------------------
-- Uniqueness is the command id (re_entry_key = ''manual:''||idempotency_key), which subsumes recipe version +
-- subject. p_max_enrollment_duration_days is the effective limit the route resolved (null = unlimited). The
-- engine re-reads all live quote/recipient/consent truth before any effect, so manual context is minimal.
create or replace function public.manual_enroll_automation(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_recipe_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_max_enrollment_duration_days integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_receipt public.automation_enrollment_command_receipts%rowtype;
  recipe public.automation_recipes%rowtype;
  live_overlap integer;
  new_enrollment_id uuid;
  expires timestamptz;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if p_subject_type is distinct from 'quote' then
    raise exception 'This record type cannot be enrolled.' using errcode = 'check_violation';
  end if;

  select * into existing_receipt
  from public.automation_enrollment_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  perform pg_advisory_xact_lock(hashtext('automation-recipe:' || p_recipe_id::text));

  select * into recipe
  from public.automation_recipes
  where id = p_recipe_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That automation does not exist.' using errcode = 'no_data_found';
  end if;
  if recipe.status <> 'active' or recipe.current_version_id is null then
    raise exception 'Only an active automation can enroll a record.' using errcode = 'restrict_violation';
  end if;

  -- One live enrollment per subject+recipe: a manual enroll never stacks a second reminder sequence on the
  -- same quote for the same recipe (the preview already warns; this enforces it under the lock).
  select count(*) into live_overlap
  from private.automation_enrollments
  where organization_id = p_organization_id
    and recipe_id = p_recipe_id
    and subject_type = p_subject_type
    and subject_id = p_subject_id
    and state in ('active', 'paused');
  if live_overlap > 0 then
    raise exception 'This record is already enrolled in this automation.' using errcode = 'unique_violation';
  end if;

  expires := case
    when p_max_enrollment_duration_days is not null
      then now() + make_interval(days => p_max_enrollment_duration_days)
    else null
  end;

  insert into private.automation_enrollments (
    organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
    trigger_event_id, source, state, current_step_index, re_entry_key, context,
    enrolled_by, expires_at
  ) values (
    p_organization_id, p_recipe_id, recipe.current_version_id, p_subject_type, p_subject_id,
    null, 'manual', 'active', 0, 'manual:' || p_idempotency_key::text,
    jsonb_build_object('source', 'manual', 'enrolled_by', p_actor_user_id, 'enrolled_at', now()),
    p_actor_user_id, expires
  )
  returning id into new_enrollment_id;

  -- The first transition is immediately claimable; the engine advances step 0 (a leading wait schedules
  -- forward, a leading action fires) exactly as automatic intake does.
  insert into private.automation_work_items (
    organization_id, enrollment_id, step_index, due_at, available_at
  ) values (
    p_organization_id, new_enrollment_id, 0, now(), now()
  );
  -- The AFTER INSERT trigger on automation_work_items requests the worker wake for this due-now row.

  command_result := jsonb_build_object(
    'enrollment_id', new_enrollment_id,
    'recipe_id', p_recipe_id,
    'version_id', recipe.current_version_id,
    'state', 'active'
  );

  insert into public.automation_enrollment_command_receipts (
    organization_id, idempotency_key, command, subject_type, subject_id, enrollment_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'enroll', p_subject_type, p_subject_id, new_enrollment_id, command_result
  );

  return command_result;
end;
$$;

revoke all on function public.manual_enroll_automation(uuid, uuid, uuid, text, uuid, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.manual_enroll_automation(uuid, uuid, uuid, text, uuid, integer, uuid) to service_role;

comment on function public.manual_enroll_automation(uuid, uuid, uuid, text, uuid, integer, uuid) is
  'Manually enrolls one eligible record into an active automation and seeds its first step. Idempotent per '
  'organization + key; one live enrollment per subject+recipe. Service role only.';

-- 5. Pause: stop future steps without moving the reminder clock. -----------------------------------------
create or replace function public.pause_automation_enrollment(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_enrollment_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_receipt public.automation_enrollment_command_receipts%rowtype;
  enrollment private.automation_enrollments%rowtype;
  pending_item private.automation_work_items%rowtype;
  v_has_pending boolean;
  v_pending_due timestamptz;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_receipt
  from public.automation_enrollment_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = p_enrollment_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That enrollment does not exist.' using errcode = 'no_data_found';
  end if;
  if enrollment.state <> 'active' then
    raise exception 'Only an active enrollment can be paused.' using errcode = 'restrict_violation';
  end if;

  -- Record the next step's absolute due time, then take the item out of the claimable pool. An unclaimed
  -- pending item is cancelled but its row is KEPT (unique on enrollment_id+step_index): resume resurrects
  -- that exact row. An item currently claimed by a worker is left alone; its advance() sees the paused
  -- enrollment and cancels it, and resume rebuilds from the recorded due time regardless.
  select * into pending_item
  from private.automation_work_items
  where enrollment_id = p_enrollment_id and state = 'pending'
  order by step_index
  limit 1
  for update;
  v_has_pending := found;
  v_pending_due := pending_item.due_at;

  if v_has_pending and pending_item.claim_token is null then
    update private.automation_work_items
    set state = 'cancelled'
    where id = pending_item.id;
  end if;

  update private.automation_enrollments
  set state = 'paused',
      paused_work_due_at = case when v_has_pending then v_pending_due else null end
  where id = p_enrollment_id;

  command_result := jsonb_build_object('enrollment_id', p_enrollment_id, 'state', 'paused');

  insert into public.automation_enrollment_command_receipts (
    organization_id, idempotency_key, command, subject_type, subject_id, enrollment_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'pause', enrollment.subject_type, enrollment.subject_id,
    p_enrollment_id, command_result
  );

  return command_result;
end;
$$;

revoke all on function public.pause_automation_enrollment(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.pause_automation_enrollment(uuid, uuid, uuid, uuid) to service_role;

comment on function public.pause_automation_enrollment(uuid, uuid, uuid, uuid) is
  'Pauses an active enrollment and parks its next step at its original due time so resume never delays the '
  'reminder. Idempotent per organization + key. Service role only.';

-- 6. Resume: continue at the original send time (fires immediately if it already passed). -----------------
create or replace function public.resume_automation_enrollment(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_enrollment_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_receipt public.automation_enrollment_command_receipts%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  resume_due timestamptz;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_receipt
  from public.automation_enrollment_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = p_enrollment_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That enrollment does not exist.' using errcode = 'no_data_found';
  end if;
  if enrollment.state <> 'paused' then
    raise exception 'Only a paused enrollment can be resumed.' using errcode = 'restrict_violation';
  end if;

  select status into recipe_status
  from public.automation_recipes
  where id = enrollment.recipe_id and organization_id = p_organization_id;
  if recipe_status is distinct from 'active' then
    raise exception 'This automation is not active, so it cannot be resumed.' using errcode = 'restrict_violation';
  end if;

  resume_due := coalesce(enrollment.paused_work_due_at, now());

  -- Resurrect the exact step row pause cancelled (unique on enrollment_id+step_index forbids re-inserting it).
  -- Clearing the claim token means a worker that still holds the old lease gets claim_lost, never a double.
  update private.automation_work_items
  set state = 'pending', due_at = resume_due, available_at = resume_due,
      claim_token = null, claimed_at = null
  where enrollment_id = p_enrollment_id and step_index = enrollment.current_step_index;

  -- No such row (e.g. it was hard-deleted): schedule the step fresh.
  if not found then
    insert into private.automation_work_items (
      organization_id, enrollment_id, step_index, due_at, available_at
    ) values (
      p_organization_id, p_enrollment_id, enrollment.current_step_index, resume_due, resume_due
    )
    on conflict (enrollment_id, step_index) do nothing;
  end if;

  update private.automation_enrollments
  set state = 'active', paused_work_due_at = null
  where id = p_enrollment_id;

  -- The resurrect path is an UPDATE, so the insert-wake trigger did not fire; nudge the worker explicitly.
  perform public.request_automation_worker_wake();

  command_result := jsonb_build_object(
    'enrollment_id', p_enrollment_id, 'state', 'active', 'next_due_at', resume_due
  );

  insert into public.automation_enrollment_command_receipts (
    organization_id, idempotency_key, command, subject_type, subject_id, enrollment_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'resume', enrollment.subject_type, enrollment.subject_id,
    p_enrollment_id, command_result
  );

  return command_result;
end;
$$;

revoke all on function public.resume_automation_enrollment(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.resume_automation_enrollment(uuid, uuid, uuid, uuid) to service_role;

comment on function public.resume_automation_enrollment(uuid, uuid, uuid, uuid) is
  'Resumes a paused enrollment at the step''s original due time (already past -> next worker cycle). '
  'Idempotent per organization + key. Service role only.';

-- 7. Skip next step: cancel the pending step and advance to the following one now. ------------------------
create or replace function public.skip_automation_enrollment_step(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_enrollment_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_receipt public.automation_enrollment_command_receipts%rowtype;
  enrollment private.automation_enrollments%rowtype;
  pending_item private.automation_work_items%rowtype;
  definition jsonb;
  step_count integer;
  next_index integer;
  new_state text;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_receipt
  from public.automation_enrollment_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = p_enrollment_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That enrollment does not exist.' using errcode = 'no_data_found';
  end if;
  if enrollment.state not in ('active', 'paused') then
    raise exception 'Only a running enrollment has a step to skip.' using errcode = 'restrict_violation';
  end if;

  -- Cancel the current pending step (claimed or not: skip is an explicit staff override of what is next).
  select * into pending_item
  from private.automation_work_items
  where enrollment_id = p_enrollment_id and state = 'pending'
  order by step_index
  limit 1
  for update;
  if found then
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = pending_item.id;
  end if;

  select version.definition into definition
  from public.automation_recipe_versions as version
  where version.id = enrollment.recipe_version_id;
  step_count := jsonb_array_length(coalesce(definition -> 'steps', '[]'::jsonb));

  next_index := enrollment.current_step_index + 1;

  if next_index >= step_count then
    -- Skipping the last step completes the enrollment; nothing further is scheduled.
    new_state := 'completed';
    update private.automation_enrollments
    set state = 'completed', completed_at = now(), current_step_index = next_index, paused_work_due_at = null
    where id = p_enrollment_id;
  else
    new_state := enrollment.state;
    update private.automation_enrollments
    set current_step_index = next_index,
        paused_work_due_at = case when enrollment.state = 'paused' then now() else null end
    where id = p_enrollment_id;

    -- Only an active enrollment schedules the next step now; a paused one keeps it parked (recorded above)
    -- until resume.
    if enrollment.state = 'active' then
      insert into private.automation_work_items (
        organization_id, enrollment_id, step_index, due_at, available_at
      ) values (
        p_organization_id, p_enrollment_id, next_index, now(), now()
      )
      on conflict (enrollment_id, step_index) do nothing;
      -- The AFTER INSERT trigger requests the worker wake for this due-now row.
    end if;
  end if;

  command_result := jsonb_build_object(
    'enrollment_id', p_enrollment_id, 'state', new_state, 'current_step_index', next_index
  );

  insert into public.automation_enrollment_command_receipts (
    organization_id, idempotency_key, command, subject_type, subject_id, enrollment_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'skip', enrollment.subject_type, enrollment.subject_id,
    p_enrollment_id, command_result
  );

  return command_result;
end;
$$;

revoke all on function public.skip_automation_enrollment_step(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.skip_automation_enrollment_step(uuid, uuid, uuid, uuid) to service_role;

comment on function public.skip_automation_enrollment_step(uuid, uuid, uuid, uuid) is
  'Cancels the pending step and advances to the next one (active: scheduled now; paused: parked; last step: '
  'completes). Idempotent per organization + key. Service role only.';

-- 8. Stop: terminal, with a reason. Cancels all pending work; never recalls a sent message. ---------------
create or replace function public.stop_automation_enrollment(
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_enrollment_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_receipt public.automation_enrollment_command_receipts%rowtype;
  enrollment private.automation_enrollments%rowtype;
  command_result jsonb;
begin
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;

  select * into existing_receipt
  from public.automation_enrollment_command_receipts
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = p_enrollment_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'That enrollment does not exist.' using errcode = 'no_data_found';
  end if;
  if enrollment.state not in ('active', 'paused') then
    raise exception 'This enrollment is already finished.' using errcode = 'restrict_violation';
  end if;

  update private.automation_work_items
  set state = 'cancelled', claim_token = null, claimed_at = null
  where enrollment_id = p_enrollment_id and state = 'pending';

  update private.automation_enrollments
  set state = 'stopped',
      stop_reason = left(coalesce(nullif(btrim(p_reason), ''), 'stopped_manually'), 200),
      stopped_at = now(),
      paused_work_due_at = null
  where id = p_enrollment_id;

  command_result := jsonb_build_object('enrollment_id', p_enrollment_id, 'state', 'stopped');

  insert into public.automation_enrollment_command_receipts (
    organization_id, idempotency_key, command, subject_type, subject_id, enrollment_id, result
  ) values (
    p_organization_id, p_idempotency_key, 'stop', enrollment.subject_type, enrollment.subject_id,
    p_enrollment_id, command_result
  );

  return command_result;
end;
$$;

revoke all on function public.stop_automation_enrollment(uuid, uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.stop_automation_enrollment(uuid, uuid, uuid, text, uuid) to service_role;

comment on function public.stop_automation_enrollment(uuid, uuid, uuid, text, uuid) is
  'Terminally stops an enrollment with a reason and cancels its pending work. Never recalls a sent message. '
  'Idempotent per organization + key. Service role only.';

-- 9. Safe per-record read: current and recent enrollments for one record. --------------------------------
-- Uses automation_enrollments_subject_idx (organization_id, subject_type, subject_id, updated_at desc,
-- id desc). Projects summaries only: recipe name/version, state, next step + time, messages sent, source,
-- stop reason. Never context, payload, work-item lease, or attempt state.
create or replace function public.automation_record_enrollments(
  p_organization_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_limit integer default 20
)
returns table (
  enrollment_id uuid,
  recipe_id uuid,
  recipe_name text,
  version_number integer,
  state text,
  source text,
  current_step_index integer,
  next_due_at timestamptz,
  customer_messages_sent integer,
  stop_reason text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog, public, private
as $$
  select
    e.id,
    e.recipe_id,
    r.name,
    v.version_number,
    e.state,
    e.source,
    e.current_step_index,
    coalesce(
      e.paused_work_due_at,
      (select w.due_at
       from private.automation_work_items w
       where w.enrollment_id = e.id and w.state = 'pending'
       order by w.step_index
       limit 1)
    ) as next_due_at,
    e.customer_messages_sent,
    e.stop_reason,
    e.created_at,
    e.updated_at
  from private.automation_enrollments e
  join public.automation_recipes r
    on r.id = e.recipe_id and r.organization_id = e.organization_id
  join public.automation_recipe_versions v
    on v.id = e.recipe_version_id
  where e.organization_id = p_organization_id
    and e.subject_type = p_subject_type
    and e.subject_id = p_subject_id
  order by e.updated_at desc, e.id desc
  limit least(coalesce(p_limit, 20), 50);
$$;

revoke all on function public.automation_record_enrollments(uuid, text, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.automation_record_enrollments(uuid, text, uuid, integer) to service_role;

comment on function public.automation_record_enrollments(uuid, text, uuid, integer) is
  'Safe per-record enrollment summaries (recipe/version/state/next-step/messages/source) for the Quote detail '
  'controls. Never exposes context, payload, or worker/lease state. Service role only.';
