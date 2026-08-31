-- Automation Part 6D-2: make due work claimable, leased, fair, retryable, and visible when it gets stuck.
--
-- Shape: competing consumers over a Postgres queue -- the pattern the Communications email outbox already
-- runs, minus its global single-flight lease. That lease is deliberately NOT reproduced here: it serializes
-- every wake to one at a time, which is right for one Cron-driven route and wrong for the production plan of
-- several background-worker containers. Concurrency safety comes entirely from an atomic claim
-- (`FOR UPDATE SKIP LOCKED`) plus a per-row lease, so any number of workers may drain at once.
--
-- The lease IS the availability: claiming pushes `available_at` out by the lease, so a claimed row simply is
-- not due yet, and a worker that dies leaves a row that becomes claimable again the moment its lease passes.
-- There is no stale-claim quarantine job to run, and the claim predicate needs no `lease_expires_at`
-- comparison, so the partial index covers the whole predicate.
--
-- Nothing here sends anything. An `action` step has no adapter until 6D-3, so reaching one parks the work
-- item in `needs_attention` with a plain reason and leaves the enrollment active and resumable.

-- ---------------------------------------------------------------------------------------------------
-- 1. Events get a retry clock.
-- ---------------------------------------------------------------------------------------------------
-- 6D-1 retried a failing event on every batch with no delay, so one poisoned row could take a batch slot
-- repeatedly while sitting at the head of `seq` order until it hit five attempts. `available_at` gives the
-- same backoff the work queue uses.
--
-- The pending index deliberately stays keyed on `seq` alone rather than moving to
-- `(available_at, seq)` as docs/automation-behavior-contract.md's index table sketched. Intake drains in
-- strict arrival order (Jafar, 2026-08-31), and only a `seq`-leading index can return that order without
-- sorting the whole backlog. Deferred events are bounded by the five-attempt cap, so the number of rows the
-- `available_at` filter skips stays tiny.
alter table private.automation_events
  add column available_at timestamptz not null default now();

comment on column private.automation_events.available_at is
  'When this event may next be claimed. Pushed out by intake backoff after a failed attempt; equal to '
  'creation time otherwise.';

-- ---------------------------------------------------------------------------------------------------
-- 2. Work items get a lease, an attempt history, and an attention state.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_work_items
  -- Claim eligibility. Starts at due_at; a claim pushes it to the lease expiry, a retry to the backoff
  -- deadline. `due_at` stays untouched so "when was this actually due" remains readable for lateness.
  add column available_at timestamptz not null default now(),
  add column claim_token uuid,
  add column claimed_at timestamptz,
  add column claimed_by text check (claimed_by is null or char_length(claimed_by) between 1 and 100),
  add column attempts integer not null default 0 check (attempts >= 0),
  add column last_error_code text check (last_error_code is null or char_length(last_error_code) <= 100),
  add column last_error_message text
    check (last_error_message is null or char_length(last_error_message) <= 1000),
  add column attention_reason text
    check (attention_reason is null or char_length(attention_reason) between 1 and 100),
  add column attention_at timestamptz;

update private.automation_work_items set available_at = due_at;

comment on column private.automation_work_items.available_at is
  'When this row may next be claimed. The claim sets it to the lease expiry, so a claimed row is simply not '
  'due and an abandoned claim recovers on its own with no quarantine sweep.';
comment on column private.automation_work_items.attempts is
  'Incremented by the claim, not by the outcome, so a worker that dies mid-step still counts its attempt and '
  'a crash loop reaches the dead-letter cap instead of spinning forever.';

alter table private.automation_work_items
  drop constraint automation_work_items_state_check;
alter table private.automation_work_items
  add constraint automation_work_items_state_check
    check (state in ('pending', 'done', 'cancelled', 'needs_attention')),
  -- An attention row must say why, and only an attention row may.
  add constraint automation_work_items_attention_check check (
    (state = 'needs_attention' and attention_reason is not null and attention_at is not null)
    or (state <> 'needs_attention' and attention_reason is null and attention_at is null)
  );

-- The claim predicate, whole. Partial so it tracks the claimable backlog rather than history.
drop index if exists private.automation_work_items_due_idx;
create index automation_work_items_claim_idx
  on private.automation_work_items (available_at, id) where state = 'pending';

-- Needs attention, per tenant and most recent first. 6D-4 builds the contractor-facing read on top of this;
-- the resume command below is its first reader.
create index automation_work_items_attention_idx
  on private.automation_work_items (organization_id, attention_at desc, id desc)
  where state = 'needs_attention';

-- ---------------------------------------------------------------------------------------------------
-- 3. Backoff.
-- ---------------------------------------------------------------------------------------------------
-- Exponential with full jitter, the AWS-documented shape: doubling alone makes every worker that failed in
-- the same burst retry in lockstep, and the random spread is what breaks that up.
create or replace function private.automation_retry_delay(p_attempts integer)
returns interval
language sql
-- Volatile, not immutable: the jitter is a real random() call and must not be folded or cached.
volatile
set search_path = pg_catalog
as $$
  select make_interval(
    secs => least(3600, 30 * power(2, greatest(coalesce(p_attempts, 1), 1) - 1)) * (0.5 + random() * 0.5)
  );
$$;

comment on function private.automation_retry_delay(integer) is
  'Exponential backoff with full jitter: 30s doubling to a one-hour ceiling, then randomised across half the '
  'window so a burst of simultaneous failures does not retry in lockstep.';

revoke all on function private.automation_retry_delay(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------
-- 4. Intake honours the retry clock.
-- ---------------------------------------------------------------------------------------------------
-- Replaced from the 6D-1 definition. The only changes are marked 6D-2: the availability filter on the claim
-- and the backoff on the failure path.
create or replace function public.intake_automation_events(p_batch_size integer default 25)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate private.automation_events%rowtype;
  match_row record;
  authority public.organization_automation_authority%rowtype;
  quote_row public.quotes%rowtype;
  is_entitled boolean;
  duration_days integer;
  enrollment_expires_at timestamptz;
  re_entry_key text;
  match_outcome text;
  new_enrollment_id uuid;
  processed_count integer := 0;
  max_processing_attempts constant integer := 5;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The intake batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select *
    from private.automation_events
    where processed_at is null
      and available_at <= now()   -- 6D-2
    order by seq
    limit p_batch_size
    for update skip locked
  loop
    begin
      select * into authority
      from public.organization_automation_authority
      where organization_id = candidate.organization_id;

      is_entitled := private.organization_has_automations_feature(candidate.organization_id);

      select * into quote_row
      from public.quotes
      where organization_id = candidate.organization_id and id = candidate.subject_id;

      select case when limits.state = 'numeric' then limits.value end
      into duration_days
      from public.effective_automation_limits(candidate.organization_id) as limits
      where limits.limit_key = 'automation_max_enrollment_duration_days';

      enrollment_expires_at := case
        when duration_days is not null and duration_days > 0
        then now() + make_interval(days => duration_days)
      end;

      re_entry_key := coalesce(candidate.payload ->> 'quote_version_id', '')
        || ':' || coalesce(candidate.payload ->> 'quote_recipient_id', '');

      for match_row in
        select
          recipe.id as recipe_id,
          recipe.current_version_id,
          version.definition,
          version.activation_cutoff_snapshot,
          version.activation_cutoff_sequence
        from public.automation_recipes as recipe
        join public.automation_recipe_versions as version
          on version.id = recipe.current_version_id
        where recipe.organization_id = candidate.organization_id
          and recipe.status = 'active'
          and recipe.active_trigger_key = candidate.event_type
        order by recipe.id
      loop
        match_outcome := null;
        new_enrollment_id := null;

        if not is_entitled then
          match_outcome := 'not_entitled';
        elsif authority.organization_id is not null
          and (authority.operational_state <> 'enabled' or authority.security_state <> 'active') then
          match_outcome := 'authority_blocked';
        elsif (
            match_row.activation_cutoff_snapshot is not null
            and pg_visible_in_snapshot(candidate.created_xid, match_row.activation_cutoff_snapshot)
          ) or (
            match_row.activation_cutoff_snapshot is null
            and candidate.seq <= coalesce(match_row.activation_cutoff_sequence, 0)
          ) then
          match_outcome := 'before_activation';
        elsif quote_row.id is null or quote_row.archived_at is not null then
          match_outcome := 'subject_gone';
        else
          match_outcome := private.automation_conditions_outcome(
            match_row.definition, candidate.organization_id, quote_row.status, candidate.payload
          );
          if match_outcome = 'pass' then
            insert into private.automation_enrollments (
              organization_id, recipe_id, recipe_version_id, subject_type, subject_id,
              trigger_event_id, source, re_entry_key, context, expires_at
            ) values (
              candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
              candidate.subject_type, candidate.subject_id, candidate.id, 'event',
              re_entry_key, candidate.payload, enrollment_expires_at
            )
            on conflict do nothing
            returning id into new_enrollment_id;

            if new_enrollment_id is null then
              match_outcome := 'already_enrolled';
            else
              match_outcome := 'enrolled';
              -- 6D-2: available_at mirrors due_at so the first transition is immediately claimable.
              insert into private.automation_work_items (
                organization_id, enrollment_id, step_index, due_at, available_at
              ) values (
                candidate.organization_id, new_enrollment_id, 0, now(), now()
              )
              on conflict do nothing;
            end if;
          end if;
        end if;

        insert into private.automation_event_matches (
          event_id, organization_id, recipe_id, recipe_version_id, outcome, enrollment_id
        ) values (
          candidate.id, candidate.organization_id, match_row.recipe_id, match_row.current_version_id,
          match_outcome, new_enrollment_id
        )
        on conflict (event_id, recipe_id) do nothing;
      end loop;

      update private.automation_events
      set processed_at = now(), processing_error = null
      where id = candidate.id;
      processed_count := processed_count + 1;

    exception
      when others then
        -- 6D-2: back the failing event off instead of re-claiming it on the very next batch.
        update private.automation_events
        set processing_attempts = coalesce(processing_attempts, 0) + 1,
          processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
          available_at = now() + private.automation_retry_delay(coalesce(processing_attempts, 0) + 1),
          processed_at = case
            when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
            else processed_at
          end
        where id = candidate.id;
    end;
  end loop;

  return processed_count;
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 5. The fair claim.
-- ---------------------------------------------------------------------------------------------------
-- One atomic statement, deterministic order, and a per-organization cap so a tenant with a huge backlog
-- cannot take a whole batch while everyone else waits. The cap is a first pass, not a hard limit: rows over
-- the cap still fill capacity the fair pass left empty, which is exactly what
-- docs/automation-behavior-contract.md § Scheduling asks for. Batch and cap are configuration to prove under
-- load, not capacity promises.
create or replace function public.claim_automation_work_items(
  p_batch_size integer default 25,
  p_per_organization_cap integer default 5,
  p_lease_seconds integer default 120,
  p_max_attempts integer default 8,
  p_worker text default null
)
returns table (
  work_item_id uuid,
  claim_token uuid,
  organization_id uuid,
  enrollment_id uuid,
  step_index integer,
  attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_token uuid := gen_random_uuid();
  v_worker text := left(coalesce(nullif(btrim(p_worker), ''), 'automation-worker'), 100);
  v_candidate_window integer;
begin
  if p_batch_size < 1 or p_batch_size > 200 then
    raise exception 'The claim batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_per_organization_cap < 1 or p_per_organization_cap > p_batch_size then
    raise exception 'The per-organization cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The claim lease is outside its safe bounds.' using errcode = 'check_violation';
  end if;
  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception 'The attempt cap is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  -- Dead-letter first, bounded. A row that has burned its attempts -- including one whose worker kept dying
  -- before it could report anything -- becomes visible instead of being claimed forever.
  update private.automation_work_items as w
  set state = 'needs_attention',
    attention_reason = 'max_attempts',
    attention_at = now(),
    claim_token = null,
    claimed_at = null
  where w.id in (
    select doomed.id
    from private.automation_work_items as doomed
    where doomed.state = 'pending'
      and doomed.available_at <= now()
      and doomed.attempts >= p_max_attempts
    order by doomed.available_at, doomed.id
    limit p_batch_size
    for update skip locked
  );

  -- The candidate window bounds the fairness pass: ranking is computed over a small slice of the queue, never
  -- the whole backlog. Four batches of head-room is enough for the cap to have something to reorder.
  v_candidate_window := least(p_batch_size * 4, 400);

  return query
  with due as (
    select
      w.id,
      w.available_at,
      row_number() over (
        partition by w.organization_id order by w.available_at, w.id
      ) as per_organization_rank
    from private.automation_work_items as w
    where w.state = 'pending'
      and w.available_at <= now()
      and w.attempts < p_max_attempts
    order by w.available_at, w.id
    limit v_candidate_window
  ),
  -- Sorting on the boolean puts every within-cap row first (false < true), then lets over-cap rows fill
  -- whatever capacity is left. One pass, both rules.
  ranked as (
    select
      due.id,
      row_number() over (
        order by (due.per_organization_rank > p_per_organization_cap), due.available_at, due.id
      ) as pick_order
    from due
  ),
  picked as (
    select ranked.id from ranked where ranked.pick_order <= p_batch_size
  ),
  locked as (
    select w.id
    from private.automation_work_items as w
    where w.id in (select picked.id from picked)
    order by w.available_at, w.id
    for update skip locked
  )
  update private.automation_work_items as w
  set claim_token = v_token,
    claimed_at = now(),
    claimed_by = v_worker,
    attempts = w.attempts + 1,
    -- The claim IS the lease: the row stops being due until the lease passes.
    available_at = now() + make_interval(secs => p_lease_seconds),
    last_error_code = null,
    last_error_message = null
  from locked
  where w.id = locked.id
  returning w.id, w.claim_token, w.organization_id, w.enrollment_id, w.step_index, w.attempts;
end;
$$;

comment on function public.claim_automation_work_items(integer, integer, integer, integer, text) is
  'Atomically claims a bounded, organization-fair batch of due work under a per-row lease. Safe to run from '
  'any number of workers at once: there is no global lock, and an abandoned claim recovers when its lease '
  'passes. Service role only.';

revoke all on function public.claim_automation_work_items(integer, integer, integer, integer, text)
  from public, anon, authenticated;
grant execute on function public.claim_automation_work_items(integer, integer, integer, integer, text)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 6. One transition.
-- ---------------------------------------------------------------------------------------------------
-- Completing a step writes the enrollment advance and at most one next work item in the same transaction,
-- so a crash between them is impossible and nothing is ever pre-expanded. Every write is guarded by the
-- claim token, so a worker whose lease expired mid-step cannot overwrite the worker that took over.
create or replace function public.advance_automation_work_item(
  p_work_item_id uuid,
  p_claim_token uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  definition jsonb;
  step jsonb;
  step_type text;
  wait_amount integer;
  wait_unit text;
  next_due timestamptz;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;

  select * into item
  from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending'
  for update;

  -- Lease lost, already settled, or never claimed by this worker. Not an error: the row belongs to someone
  -- else now, and that owner's outcome is the real one.
  if not found then
    return 'claim_lost';
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = item.enrollment_id
  for update;

  if not found or enrollment.state <> 'active' then
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = item.id;
    return 'enrollment_inactive';
  end if;

  -- Expiry is the organization's maximum enrollment duration, frozen onto the enrollment at intake.
  if enrollment.expires_at is not null and enrollment.expires_at <= now() then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'enrollment_expired', stopped_at = now()
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = item.id;
    return 'enrollment_expired';
  end if;

  -- The recipe must still be running. A paused or archived recipe stops its enrollments rather than quietly
  -- continuing to act under a definition the contractor has taken out of service.
  select recipe.status, version.definition
  into recipe_status, definition
  from private.automation_enrollments as e
  join public.automation_recipes as recipe on recipe.id = e.recipe_id
  join public.automation_recipe_versions as version on version.id = e.recipe_version_id
  where e.id = enrollment.id;

  if recipe_status is distinct from 'active' then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'recipe_not_active', stopped_at = now()
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = item.id;
    return 'recipe_not_active';
  end if;

  step := (definition -> 'steps') -> item.step_index;

  -- Past the last step: the sequence is finished.
  if step is null then
    update private.automation_enrollments
    set state = 'completed', completed_at = now(), current_step_index = item.step_index
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null
    where id = item.id;
    return 'completed';
  end if;

  step_type := step ->> 'type';

  if step_type = 'wait' then
    wait_unit := step -> 'config' ->> 'unit';
    wait_amount := nullif(step -> 'config' ->> 'amount', '')::integer;
    if wait_unit not in ('hours', 'days') or wait_amount is null or wait_amount < 1 then
      raise exception 'This automation step has an unusable delay.' using errcode = 'check_violation';
    end if;

    next_due := now() + case wait_unit
      when 'days' then make_interval(days => wait_amount)
      else make_interval(hours => wait_amount)
    end;

    update private.automation_enrollments
    set current_step_index = item.step_index + 1
    where id = enrollment.id;

    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null
    where id = item.id;

    -- The one next transition. Future-dated on purpose: no wake fires for it, and the minute Cron sweep is
    -- what finds it when it becomes due.
    insert into private.automation_work_items (
      organization_id, enrollment_id, step_index, due_at, available_at
    ) values (
      enrollment.organization_id, enrollment.id, item.step_index + 1, next_due, next_due
    )
    on conflict (enrollment_id, step_index) do nothing;

    return 'waiting';
  end if;

  if step_type = 'action' then
    -- 6D-3 registers the effect adapters. Until then an action is a truthful "not yet", not a failure: the
    -- enrollment stays active, the step keeps its place, and resume_automation_work_items puts it back.
    update private.automation_work_items
    set state = 'needs_attention',
      attention_reason = 'action_not_available',
      attention_at = now(),
      claim_token = null,
      claimed_at = null
    where id = item.id;
    return 'action_not_available';
  end if;

  raise exception 'This automation step has an unknown type.' using errcode = 'check_violation';
end;
$$;

comment on function public.advance_automation_work_item(uuid, uuid) is
  'Runs one claimed transition: rechecks enrollment, expiry, and recipe state, then completes, waits and '
  'schedules the single next step, or parks an action that has no adapter yet. Claim-token guarded. '
  'Service role only.';

revoke all on function public.advance_automation_work_item(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_automation_work_item(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 7. Failure reporting.
-- ---------------------------------------------------------------------------------------------------
-- The worker calls this when a transition raised. A permanent result parks immediately; a transient one
-- backs off and stays claimable. Error text is truncated and stored as-is by the caller, which is
-- responsible for passing a sanitized message -- credentials, headers, and customer content never belong in
-- operational state.
create or replace function public.retry_automation_work_item(
  p_work_item_id uuid,
  p_claim_token uuid,
  p_error_code text,
  p_error_message text,
  p_permanent boolean default false
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
begin
  select * into item
  from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending'
  for update;

  if not found then
    return 'claim_lost';
  end if;

  if p_permanent then
    update private.automation_work_items
    set state = 'needs_attention',
      attention_reason = left(coalesce(nullif(btrim(p_error_code), ''), 'permanent_failure'), 100),
      attention_at = now(),
      last_error_code = left(nullif(btrim(p_error_code), ''), 100),
      last_error_message = left(nullif(btrim(p_error_message), ''), 1000),
      claim_token = null,
      claimed_at = null
    where id = item.id;
    return 'parked';
  end if;

  update private.automation_work_items
  set available_at = now() + private.automation_retry_delay(item.attempts),
    last_error_code = left(nullif(btrim(p_error_code), ''), 100),
    last_error_message = left(nullif(btrim(p_error_message), ''), 1000),
    claim_token = null,
    claimed_at = null
  where id = item.id;
  return 'retry_scheduled';
end;
$$;

comment on function public.retry_automation_work_item(uuid, uuid, text, text, boolean) is
  'Records a failed transition: backs the row off with jittered exponential delay, or parks it for attention '
  'when the failure is permanent. Claim-token guarded. Service role only.';

revoke all on function public.retry_automation_work_item(uuid, uuid, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.retry_automation_work_item(uuid, uuid, text, text, boolean) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 8. Resume.
-- ---------------------------------------------------------------------------------------------------
-- The recovery half of dead-letter: an attention row goes back to claimable, its attempt count cleared, and
-- runs every current check again on its next claim. This is what makes the pre-6D-3 `action_not_available`
-- park safe -- when the email adapter lands, those parked steps resume exactly where they stopped, under the
-- version they were pinned to, with no duplicate enrollment and no lost step.
--
-- Bounded and optionally scoped to one organization or one reason. Service role only for now; 6D-5 gives
-- contractors the permission-checked command.
create or replace function public.resume_automation_work_items(
  p_organization_id uuid default null,
  p_attention_reason text default null,
  p_batch_size integer default 100
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  resumed_count integer;
begin
  if p_batch_size < 1 or p_batch_size > 1000 then
    raise exception 'The resume batch size is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  with resumable as (
    select w.id
    from private.automation_work_items as w
    join private.automation_enrollments as e on e.id = w.enrollment_id
    where w.state = 'needs_attention'
      and e.state = 'active'
      and (p_organization_id is null or w.organization_id = p_organization_id)
      and (p_attention_reason is null or w.attention_reason = p_attention_reason)
    order by w.organization_id, w.attention_at, w.id
    limit p_batch_size
    for update of w skip locked
  )
  update private.automation_work_items as w
  set state = 'pending',
    attention_reason = null,
    attention_at = null,
    attempts = 0,
    available_at = now(),
    claim_token = null,
    claimed_at = null,
    last_error_code = null,
    last_error_message = null
  from resumable
  where w.id = resumable.id;

  get diagnostics resumed_count = row_count;
  return resumed_count;
end;
$$;

comment on function public.resume_automation_work_items(uuid, text, integer) is
  'Returns parked work to the claimable queue with a fresh attempt budget; every safety check runs again on '
  'the next claim. Skips rows whose enrollment is no longer active. Service role only until 6D-5.';

revoke all on function public.resume_automation_work_items(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.resume_automation_work_items(uuid, text, integer) to service_role;
