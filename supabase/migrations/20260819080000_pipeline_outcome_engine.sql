-- Sales Pipeline, Part 4A: the atomic outcome engine.
-- Adds Lost and Reopen as the only two ways an Opportunity's outcome can change. Won stays reserved for a
-- future Quote/Job caller: nothing here exposes a generic "set outcome" path, and no browser or API caller
-- can manufacture it.
--
-- A pre-existing gap this migration closes: the Request detail page's "Archive"/"Bring back" toggle wrote
-- requests.status straight to 'archived' and back through the plain PATCH /api/requests/[id] route, with no
-- reason, no outcome event, and no Task completion. Every Request already gets an Opportunity automatically
-- (Part 1), so that toggle could silently desync the outcome model. From this migration on, only the two
-- functions below may move a request into or out of 'archived'.

-- 1. Immutable outcome history --------------------------------------------------------------------------

create table public.opportunity_outcome_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_id uuid not null,
  event_type text not null check (event_type in ('lost', 'reopened')),
  occurred_at timestamptz not null default now(),
  -- Kept even after the member leaves, so the audit trail never loses its actor.
  actor_user_id uuid references auth.users(id) on delete set null,
  reason text,
  note text,
  reopen_explanation text,
  -- Captured only on a 'lost' event, from the request row before it was archived. Reopen reads it back
  -- from here rather than guessing, because by the time Reopen runs the request itself already says
  -- 'archived'.
  prior_request_status text,
  -- Only set on a 'reopened' event: which 'lost' event this one reverses. This is also how Reopen finds
  -- exactly the Tasks that Lost auto-completed, without searching history.
  restores_event_id uuid,
  idempotency_key text not null check (char_length(trim(idempotency_key)) >= 8),
  created_at timestamptz not null default now(),
  constraint opportunity_outcome_events_organization_id_unique unique (organization_id, id),
  constraint opportunity_outcome_events_opportunity_fk
    foreign key (organization_id, opportunity_id)
    references public.opportunities(organization_id, id) on delete cascade,
  constraint opportunity_outcome_events_restores_fk
    foreign key (organization_id, restores_event_id)
    references public.opportunity_outcome_events(organization_id, id),
  -- Idempotency is scoped to one opportunity, not the whole organization: two staff members closing two
  -- different cards must never collide just because a client generated the same key by coincidence.
  constraint opportunity_outcome_events_idempotency_unique
    unique (organization_id, opportunity_id, idempotency_key),
  -- Each event type owns a disjoint set of fields, so a row can never carry a reopen explanation and a
  -- lost reason at once, or claim to restore an event it isn't a lost/reopened pair with.
  constraint opportunity_outcome_events_type_fields_consistent check (
    (event_type = 'lost'
      and reopen_explanation is null
      and restores_event_id is null
      and prior_request_status is not null)
    or
    (event_type = 'reopened'
      and reason is null
      and note is null
      and prior_request_status is null
      and reopen_explanation is not null
      and restores_event_id is not null)
  ),
  constraint opportunity_outcome_events_reason_vocabulary check (
    reason is null or reason in (
      'price_too_high', 'chose_another_contractor', 'no_response', 'project_postponed',
      'work_not_a_fit', 'duplicate_or_test_request', 'other'
    )
  ),
  constraint opportunity_outcome_events_other_requires_note check (
    reason is distinct from 'other' or char_length(trim(coalesce(note, ''))) > 0
  ),
  constraint opportunity_outcome_events_note_length check (note is null or char_length(note) <= 1000),
  constraint opportunity_outcome_events_reopen_explanation_length check (
    reopen_explanation is null or char_length(trim(reopen_explanation)) between 1 and 500
  ),
  constraint opportunity_outcome_events_prior_status_valid check (
    prior_request_status is null
    or prior_request_status in ('new', 'unscheduled', 'assessment_completed', 'completed')
  )
);

comment on table public.opportunity_outcome_events is
  'Immutable Lost/Reopen history for Sales Pipeline opportunities. Members may only read this table. Every '
  'row is written by public.pipeline_mark_opportunity_lost or public.pipeline_reopen_opportunity, which run '
  'as the table owner; nothing else may insert, update, or delete a row here.';

-- One index answers both the Brief's audit list and, once 4C exists, the report's drill-in.
create index opportunity_outcome_events_opportunity_idx
  on public.opportunity_outcome_events(organization_id, opportunity_id, occurred_at desc);

-- 2. Current-outcome fields on the Opportunity ------------------------------------------------------------

-- The smallest denormalization current reporting needs. Everything else -- reason, note, explanation --
-- stays only on the immutable event; it is not a "current" fact and the 4C report does not show it.
alter table public.opportunities
  add column outcome_at timestamptz,
  add column current_outcome_event_id uuid;

alter table public.opportunities
  add constraint opportunities_current_outcome_event_fk
    foreign key (organization_id, current_outcome_event_id)
    references public.opportunity_outcome_events(organization_id, id) on delete set null;

-- Serves the Won/Lost tiles' 30-day window and the future Sales Outcomes report's date-ordered paging.
-- Partial, because an open Opportunity is never a hit for either.
create index opportunities_outcome_idx
  on public.opportunities(organization_id, outcome, outcome_at desc)
  where outcome <> 'open';

comment on table public.opportunities is
  'Sales Pipeline opportunities. Members may read this table, never write it. Identity comes from the '
  'Request trigger, stage from the stage triggers, the Part 2 fields from '
  'public.pipeline_update_opportunity_details, and outcome from public.pipeline_mark_opportunity_lost / '
  'public.pipeline_reopen_opportunity. Any future write must arrive through a definer function that checks '
  'the caller, not through a new grant or policy.';

-- New columns are invisible to members until they are granted; see Part 2's note on this table.
grant select (outcome_at, current_outcome_event_id) on public.opportunities to authenticated;

-- 3. Task completion provenance ---------------------------------------------------------------------------

-- Null on every Task a person completed by hand. Set only when Lost auto-completes an open Task, so Reopen
-- can restore exactly those rows and leave human-completed ones alone.
alter table public.tasks
  add column completed_by_outcome_event_id uuid;

alter table public.tasks
  add constraint tasks_outcome_event_organization_fk
    foreign key (organization_id, completed_by_outcome_event_id)
    references public.opportunity_outcome_events(organization_id, id) on delete set null;

-- 4. Row level security and grants for the event table ----------------------------------------------------

alter table public.opportunity_outcome_events enable row level security;

create policy "permitted members can view opportunity outcome events"
on public.opportunity_outcome_events for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'pipeline.view')
);

revoke all on public.opportunity_outcome_events from anon;
revoke all on public.opportunity_outcome_events from authenticated;

grant select on public.opportunity_outcome_events to authenticated;

-- 5. Closing the pre-existing archive gap ------------------------------------------------------------------

-- Any statement that moves a request into or out of 'archived' must first mark this exact request id as
-- expected, or it is refused. Only the two functions below ever do that, and only for one row at a time
-- inside their own transaction, so the flag can never leak onto an unrelated request.
create or replace function private.request_reject_direct_archive_transition()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(current_setting('pipeline.outcome_transition_request_id', true), '') <> new.id::text then
    raise exception 'Archiving or restoring a request happens only through the sales pipeline outcome engine.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger requests_guard_archive_transition
before update of status on public.requests
for each row
when (
  (old.status = 'archived' or new.status = 'archived')
  and old.status is distinct from new.status
)
execute function private.request_reject_direct_archive_transition();

revoke all on function private.request_reject_direct_archive_transition() from public;
revoke execute on function private.request_reject_direct_archive_transition() from anon, authenticated;

-- 6. The shared guard every outcome write goes through -------------------------------------------------

-- Resolves and locks the Opportunity, and checks the caller, exactly like private.pipeline_lock_task_parent
-- does for Tasks. Locking the Opportunity first, before either function ever locks its Request or its prior
-- outcome event, keeps lock order consistent across both functions so they cannot deadlock against each
-- other.
create or replace function private.pipeline_lock_opportunity_for_outcome(target_opportunity_id uuid)
returns public.opportunities
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_row public.opportunities;
begin
  select * into target_row
  from public.opportunities
  where id = target_opportunity_id
  for update;

  if target_row.id is null
     or not private.member_has_permission(
       target_row.organization_id, (select auth.uid()), 'pipeline.edit'
     ) then
    raise exception 'You do not have access to change outcomes on this opportunity.'
      using errcode = 'insufficient_privilege';
  end if;

  return target_row;
end;
$$;

revoke all on function private.pipeline_lock_opportunity_for_outcome(uuid) from public;
revoke execute on function private.pipeline_lock_opportunity_for_outcome(uuid) from anon, authenticated;

-- 7. Lost -----------------------------------------------------------------------------------------------

create or replace function public.pipeline_mark_opportunity_lost(
  target_opportunity_id uuid,
  idempotency_key text,
  reason text default null,
  note text default null,
  occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  opportunity_row public.opportunities;
  request_row public.requests;
  existing_event public.opportunity_outcome_events;
  inserted_event public.opportunity_outcome_events;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  clean_reason text := nullif(trim(coalesce(reason, '')), '');
  clean_note text := nullif(trim(coalesce(note, '')), '');
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'An outcome cannot be dated in the future.' using errcode = 'check_violation';
  end if;
  if clean_reason is not null and clean_reason not in (
    'price_too_high', 'chose_another_contractor', 'no_response', 'project_postponed',
    'work_not_a_fit', 'duplicate_or_test_request', 'other'
  ) then
    raise exception 'Choose a valid lost reason.' using errcode = 'check_violation';
  end if;
  if clean_reason = 'other' and clean_note is null then
    raise exception 'Add a short note for "Other".' using errcode = 'check_violation';
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  -- A retry of the same command returns the first result untouched, even if the opportunity has since
  -- moved on. This must run before the "must be open" check below, or a legitimate retry after the first
  -- call already applied would be rejected as a conflicting command instead of recognised as a repeat.
  select * into existing_event
  from public.opportunity_outcome_events
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and opportunity_outcome_events.idempotency_key = pipeline_mark_opportunity_lost.idempotency_key;
  if found then
    return jsonb_build_object(
      'applied', false, 'event_id', existing_event.id, 'outcome', 'lost',
      'outcome_at', existing_event.occurred_at
    );
  end if;

  if opportunity_row.outcome <> 'open' then
    raise exception 'Only an open opportunity can be marked lost.' using errcode = 'check_violation';
  end if;
  if opportunity_row.request_id is null then
    -- Unreachable today: every Opportunity comes from a Request until Quotes exist. Refusing plainly is
    -- safer than fabricating Quote-side Lost behavior.
    raise exception 'Standalone opportunities cannot be marked lost yet.' using errcode = 'check_violation';
  end if;

  select * into request_row
  from public.requests
  where id = opportunity_row.request_id and organization_id = opportunity_row.organization_id
  for update;

  if request_row.id is null then
    raise exception 'The backing request could not be found.' using errcode = 'foreign_key_violation';
  end if;
  if request_row.status in ('archived', 'converted') then
    raise exception 'This request cannot be marked lost right now.' using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.outcome_transition_request_id', request_row.id::text, true);

  update public.requests
  set status = 'archived'
  where id = request_row.id;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
    reason, note, prior_request_status, idempotency_key
  ) values (
    opportunity_row.organization_id, target_opportunity_id, 'lost', command_time, (select auth.uid()),
    clean_reason, clean_note, request_row.status, idempotency_key
  ) returning * into inserted_event;

  update public.opportunities
  set outcome = 'lost', outcome_at = command_time, current_outcome_event_id = inserted_event.id
  where id = target_opportunity_id;

  -- Only Tasks still open at this moment are this Lost event's to claim. A Task a person already finished
  -- keeps its own completed_by and no event id, so Reopen will never touch it. The five-completed limit is
  -- deliberately not re-checked here: it bounds active board work, and this card is leaving the board.
  update public.tasks
  set status = 'completed', completed_at = command_time, completed_by = null,
      completed_by_outcome_event_id = inserted_event.id
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and status = 'open';

  return jsonb_build_object(
    'applied', true, 'event_id', inserted_event.id, 'outcome', 'lost', 'outcome_at', command_time
  );
end;
$$;

revoke all on function public.pipeline_mark_opportunity_lost(uuid, text, text, text, timestamptz) from public;
revoke execute on function public.pipeline_mark_opportunity_lost(uuid, text, text, text, timestamptz)
  from anon;
grant execute on function public.pipeline_mark_opportunity_lost(uuid, text, text, text, timestamptz)
  to authenticated;

-- 8. Reopen -----------------------------------------------------------------------------------------------

create or replace function public.pipeline_reopen_opportunity(
  target_opportunity_id uuid,
  idempotency_key text,
  reopen_explanation text,
  occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  opportunity_row public.opportunities;
  lost_event public.opportunity_outcome_events;
  existing_event public.opportunity_outcome_events;
  inserted_event public.opportunity_outcome_events;
  command_time timestamptz := coalesce(occurred_at, clock_timestamp());
  clean_explanation text := nullif(trim(coalesce(reopen_explanation, '')), '');
  open_count integer;
  reopening_count integer;
begin
  if char_length(trim(coalesce(idempotency_key, ''))) < 8 then
    raise exception 'A valid idempotency key is required.' using errcode = 'check_violation';
  end if;
  if clean_explanation is null or char_length(clean_explanation) > 500 then
    raise exception 'A short explanation is required to reopen.' using errcode = 'check_violation';
  end if;
  if command_time > now() then
    raise exception 'An outcome cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  opportunity_row := private.pipeline_lock_opportunity_for_outcome(target_opportunity_id);

  select * into existing_event
  from public.opportunity_outcome_events
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and opportunity_outcome_events.idempotency_key = pipeline_reopen_opportunity.idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id, 'outcome', 'open');
  end if;

  if opportunity_row.outcome <> 'lost' or opportunity_row.current_outcome_event_id is null then
    raise exception 'Only a lost opportunity can be reopened.' using errcode = 'check_violation';
  end if;

  select * into lost_event
  from public.opportunity_outcome_events
  where id = opportunity_row.current_outcome_event_id
    and organization_id = opportunity_row.organization_id
  for update;

  if lost_event.id is null then
    raise exception 'No lost event was found to reopen.' using errcode = 'foreign_key_violation';
  end if;

  -- Almost always zero: at most five Tasks could have been open when Lost fired. This only fires when
  -- something opened new Tasks on an already-closed card, which the write path does not block today.
  select
    count(*) filter (where status = 'open'),
    count(*) filter (where completed_by_outcome_event_id = lost_event.id)
  into open_count, reopening_count
  from public.tasks
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id;

  if open_count + reopening_count > 5 then
    raise exception 'Reopening would leave more than five open tasks. Close some open tasks first.'
      using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.outcome_transition_request_id', opportunity_row.request_id::text, true);

  update public.requests
  set status = lost_event.prior_request_status
  where id = opportunity_row.request_id;

  insert into public.opportunity_outcome_events (
    organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
    reopen_explanation, restores_event_id, idempotency_key
  ) values (
    opportunity_row.organization_id, target_opportunity_id, 'reopened', command_time, (select auth.uid()),
    clean_explanation, lost_event.id, idempotency_key
  ) returning * into inserted_event;

  update public.opportunities
  set outcome = 'open', outcome_at = null, current_outcome_event_id = null
  where id = target_opportunity_id;

  update public.tasks
  set status = 'open', completed_at = null, completed_by = null, completed_by_outcome_event_id = null
  where organization_id = opportunity_row.organization_id
    and opportunity_id = target_opportunity_id
    and completed_by_outcome_event_id = lost_event.id;

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id, 'outcome', 'open');
end;
$$;

revoke all on function public.pipeline_reopen_opportunity(uuid, text, text, timestamptz) from public;
revoke execute on function public.pipeline_reopen_opportunity(uuid, text, text, timestamptz) from anon;
grant execute on function public.pipeline_reopen_opportunity(uuid, text, text, timestamptz) to authenticated;
