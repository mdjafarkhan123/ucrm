-- Pipeline part D1: a short Undo for a reversible move.
--
-- The plan (docs/sales-pipeline-behavior-contract.md, § Movement and automation) lets a safely reversible
-- move offer a short-lived Undo "only while it remains the latest action and no later change has made
-- reversal unsafe". Five board moves qualify, all inside the Requests section, because each is one
-- assessment fact that the Request page can already take back by hand:
--
--   New requests           -> Assessment unscheduled   remove the assessment
--   New requests           -> Assessment scheduled     remove the assessment
--   Assessment unscheduled -> Assessment scheduled     clear the booked time
--   Assessment unscheduled -> Assessment completed     un-complete it
--   Assessment scheduled   -> Assessment completed     un-complete it
--
-- Converting to a quote and sending a quote are not here: both ask before they run, and neither can be
-- taken back. A custom-stage placement needs nothing new — its undo is another placement.
--
-- An Undo puts the card back as it was, not merely in the old column: the time it had already spent in the
-- stage and its inactivity clock come back too. A mistaken move followed by Undo must not silence a warning
-- that was showing, so each stage event now remembers the two clocks it replaced.

-- 1. A stage event remembers the clocks it replaced ------------------------------------------------------

alter table public.opportunity_stage_events
  add column from_stage_entered_at timestamptz,
  add column from_progress_at timestamptz;

comment on column public.opportunity_stage_events.from_stage_entered_at is
  'The card''s stage_entered_at just before this move. Null on the creating event and on rows older than part D1. Read only by public.pipeline_undo_move.';
comment on column public.opportunity_stage_events.from_progress_at is
  'The card''s progress_at just before this move. Null on the creating event and on rows older than part D1. Read only by public.pipeline_undo_move.';

-- The 20261001220000 version with the two clocks added. An Undo restores the old `stage_entered_at`, so
-- its own event is timed by the clock instead — it must still read as the latest thing that happened.
create or replace function private.opportunity_record_stage_event() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  insert into public.opportunity_stage_events (
    organization_id, opportunity_id, from_stage, to_stage,
    from_custom_stage_id, to_custom_stage_id, actor_user_id, occurred_at,
    from_stage_entered_at, from_progress_at
  )
  values (
    new.organization_id,
    new.id,
    case when tg_op = 'INSERT' then null else old.stage end,
    new.stage,
    case when tg_op = 'INSERT' then null else old.custom_stage_id end,
    new.custom_stage_id,
    (select auth.uid()),
    case
      when current_setting('pipeline.undo_opportunity_id', true) = new.id::text then clock_timestamp()
      else new.stage_entered_at
    end,
    case when tg_op = 'INSERT' then null else old.stage_entered_at end,
    case when tg_op = 'INSERT' then null else old.progress_at end
  );
  return null;
end;
$$;

-- 2. The stage trigger lets an Undo put the clocks back ---------------------------------------------------
--
-- The 20261002180000 version with one branch added. `pipeline.undo_opportunity_id` is set only by
-- public.pipeline_undo_move, for its own transaction and its own card.

create or replace function private.opportunity_apply_stage() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  resolved_stage text;
  request_row record;
  quote_status text;
  undoing boolean;
begin
  if new.quote_id is not null then
    select quote.status into quote_status
    from public.quotes as quote
    where quote.id = new.quote_id and quote.organization_id = new.organization_id;

    resolved_stage := case quote_status
      when 'draft' then 'quote_draft'
      when 'awaiting_response' then 'quote_awaiting_response'
      when 'changes_requested' then 'quote_changes_requested'
      -- approved, declined, archived, converted: decided or parked, off the active board either way.
      else 'request_closed'
    end;
  elsif new.job_id is not null then
    -- A Direct job is closed from birth. It holds no place on the board, the same as any decided card.
    resolved_stage := 'request_closed';
  elsif new.request_id is null then
    -- A standalone Opportunity sits at the front of the board until a Request gives it real state.
    resolved_stage := 'new_request';
  else
    select
      request.status as status,
      assessment.id is not null as has_assessment,
      assessment.starts_at as starts_at,
      assessment.completed_at as completed_at
    into request_row
    from public.requests as request
    left join public.assessments as assessment
      on assessment.request_id = request.id
    where request.id = new.request_id
      and request.organization_id = new.organization_id;

    resolved_stage := private.request_pipeline_stage(
      request_row.status,
      coalesce(request_row.has_assessment, false),
      request_row.starts_at,
      request_row.completed_at
    );
  end if;

  new.stage := resolved_stage;

  -- `stage_entered_at` is when the card arrived in the column it is drawn in, so it restarts on a real
  -- stage change and on a move into, out of, or between custom stages. `progress_at` restarts only on the
  -- real change; anything else that writes it goes through private.opportunity_record_progress.
  --
  -- An Undo is the one exception: the card goes back to the clocks it had before the move being undone,
  -- both for the stage coming back and for the custom placement that may follow it.
  undoing := tg_op = 'UPDATE'
    and current_setting('pipeline.undo_opportunity_id', true) = new.id::text;

  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
    new.progress_at := coalesce(new.progress_at, now());
  elsif new.stage is distinct from old.stage then
    -- A real Request, Assessment, or Quote action always wins over where somebody placed the card: it
    -- goes to the protected stage that action established.
    new.custom_stage_id := null;
    if undoing then
      new.stage_entered_at := current_setting('pipeline.undo_stage_entered_at')::timestamptz;
      new.progress_at := current_setting('pipeline.undo_progress_at')::timestamptz;
    else
      new.stage_entered_at := now();
      new.progress_at := now();
    end if;
  elsif new.custom_stage_id is distinct from old.custom_stage_id then
    if undoing then
      new.stage_entered_at := current_setting('pipeline.undo_stage_entered_at')::timestamptz;
    else
      new.stage_entered_at := now();
    end if;
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

-- 2. Progress that does not change the stage -------------------------------------------------------------

-- 3. The Undo itself ------------------------------------------------------------------------------------
--
-- The caller names the move it wants undone, and that move must still be the last thing that happened to
-- the card: made by this same person, within the last two minutes, with the card still where it left it.
-- Anything else — a second move, another person's move, an old toast left open — is refused, and so is a
-- reversal that would throw away something added since (who is going, instructions, a completion).
--
-- `restore_new_request` is what the move route reported when it turned the Request from New into
-- Unscheduled; the Undo turns it back. It can only ever restore New on a Request with no assessment.

create function public.pipeline_undo_move(
  target_opportunity_id uuid,
  undone_from_stage text,
  undone_to_stage text,
  restore_new_request boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  event_row public.opportunity_stage_events;
  assessment_row public.assessments;
  changed constant text := 'This move can no longer be undone because the card has changed since.';
begin
  opportunity_row := private.pipeline_lock_opportunity_for_drag(target_opportunity_id);

  if undone_from_stage is null or undone_to_stage is null
     or (undone_from_stage, undone_to_stage) not in (
    ('new_request', 'assessment_unscheduled'),
    ('new_request', 'assessment_scheduled'),
    ('assessment_unscheduled', 'assessment_scheduled'),
    ('assessment_unscheduled', 'assessment_completed'),
    ('assessment_scheduled', 'assessment_completed')
  ) then
    raise exception 'That move cannot be undone.' using errcode = 'check_violation';
  end if;

  select * into event_row
  from public.opportunity_stage_events as event
  where event.organization_id = opportunity_row.organization_id
    and event.opportunity_id = opportunity_row.id
  order by event.occurred_at desc
  limit 1;

  if opportunity_row.outcome <> 'open'
     or opportunity_row.request_id is null
     or opportunity_row.custom_stage_id is not null
     or opportunity_row.stage <> undone_to_stage
     or event_row.id is null
     or event_row.from_stage is distinct from undone_from_stage
     or event_row.to_stage <> undone_to_stage
     or event_row.actor_user_id is distinct from (select auth.uid())
     or event_row.occurred_at < now() - interval '2 minutes'
     or event_row.from_stage_entered_at is null
     or event_row.from_progress_at is null then
    raise exception '%', changed using errcode = 'check_violation';
  end if;

  select * into assessment_row
  from public.assessments as assessment
  where assessment.organization_id = opportunity_row.organization_id
    and assessment.request_id = opportunity_row.request_id
  for update;

  if assessment_row.id is null then
    raise exception '%', changed using errcode = 'check_violation';
  end if;

  perform set_config('pipeline.undo_opportunity_id', opportunity_row.id::text, true);
  perform set_config('pipeline.undo_stage_entered_at', event_row.from_stage_entered_at::text, true);
  perform set_config('pipeline.undo_progress_at', event_row.from_progress_at::text, true);

  if undone_from_stage = 'new_request' then
    -- The move created this assessment. Removing it is only an Undo while it is still exactly what the
    -- move made: not completed, nobody assigned, no instructions, and unbooked if it was left unbooked.
    if assessment_row.completed_at is not null
       or assessment_row.instructions is not null
       or (undone_to_stage = 'assessment_unscheduled' and assessment_row.starts_at is not null)
       or exists (
         select 1 from public.assessment_assignees as assignee
         where assignee.assessment_id = assessment_row.id
       ) then
      raise exception '%', changed using errcode = 'check_violation';
    end if;

    delete from public.assessments where id = assessment_row.id;

    if restore_new_request then
      update public.requests
      set status = 'new'
      where id = opportunity_row.request_id
        and organization_id = opportunity_row.organization_id
        and status = 'unscheduled';
    end if;
  elsif undone_to_stage = 'assessment_scheduled' then
    if assessment_row.completed_at is not null then
      raise exception '%', changed using errcode = 'check_violation';
    end if;

    update public.assessments
    set starts_at = null, ends_at = null, all_day = false
    where id = assessment_row.id;
  else
    -- Un-completing, the same two writes the Request page makes when the box is unticked.
    update public.assessments
    set completed_at = null
    where id = assessment_row.id;

    update public.requests
    set status = 'unscheduled'
    where id = opportunity_row.request_id
      and organization_id = opportunity_row.organization_id
      and status = 'assessment_completed';
  end if;

  -- The card was dragged out of a custom stage: it goes back there, through the one function that places
  -- cards. If that stage has since been switched off or wants a Task the card no longer has, the card
  -- simply stays in its real stage.
  if event_row.from_custom_stage_id is not null then
    begin
      perform public.pipeline_place_opportunity(opportunity_row.id, event_row.from_custom_stage_id);
    exception when check_violation then
      null;
    end;
  end if;

  perform set_config('pipeline.undo_opportunity_id', '', true);

  select * into opportunity_row from public.opportunities where id = target_opportunity_id;

  if opportunity_row.stage <> undone_from_stage then
    raise exception '%', changed using errcode = 'check_violation';
  end if;

  return jsonb_build_object(
    'stage', opportunity_row.stage,
    'custom_stage_id', opportunity_row.custom_stage_id
  );
end;
$$;

revoke all on function public.pipeline_undo_move(uuid, text, text, boolean) from public, anon;
grant execute on function public.pipeline_undo_move(uuid, text, text, boolean) to authenticated, service_role;
