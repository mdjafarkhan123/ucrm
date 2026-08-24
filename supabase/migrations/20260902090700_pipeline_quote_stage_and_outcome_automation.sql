-- Sales Pipeline, Part 5A: real Quote stages and automatic Won/Lost/Reopen.
-- The Quotes campaign already gave every Quote its own Opportunity as forward-looking groundwork
-- (public.create_quote and public.convert_request_to_quote both insert one inline, and
-- private.opportunity_apply_stage already parks a quote-backed card at 'request_closed'). This migration
-- is only the part that was deliberately left undone: real stage derivation from quotes.status, and the
-- automatic outcome writes docs/quote-behavior-contract.md already commits to ("Pipeline atomically marks
-- only this Quote Opportunity Won/Lost").
--
-- Automation is trigger-based, not a new client-facing RPC: one AFTER UPDATE OF status trigger on quotes,
-- guarded by the opportunity's *current* outcome rather than by inspecting old.status, so every path is
-- naturally idempotent and safe to fire from any caller (Approve, Decline, Archive, Restore, Revise).
-- public.pipeline_mark_opportunity_lost / public.pipeline_reopen_opportunity are untouched -- their
-- existing refusal of quote-backed opportunities stays correct, because quote-backed Lost/Reopen now
-- flows entirely through this trigger.

-- 1. Real Quote stages ----------------------------------------------------------------------------------

alter table public.opportunities
  drop constraint opportunities_stage_check;

alter table public.opportunities
  add constraint opportunities_stage_check check (stage in (
    'new_request',
    'assessment_unscheduled',
    'assessment_scheduled',
    'assessment_completed',
    'request_closed',
    'quote_draft',
    'quote_awaiting_response',
    'quote_changes_requested'
  ));

-- Only the quote_id branch changes. Everything else -- the request derivation, stage_entered_at handling
-- -- is copied verbatim from the version quotes_request_conversion.sql left behind.
create or replace function private.opportunity_apply_stage()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  resolved_stage text;
  request_row record;
  quote_status text;
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

  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
  elsif new.stage is distinct from old.stage then
    new.stage_entered_at := now();
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

revoke all on function private.opportunity_apply_stage() from public;

-- 2. opportunity_outcome_events learns about Quotes and Won -----------------------------------------------

alter table public.opportunity_outcome_events
  add column prior_quote_status text;

alter table public.opportunity_outcome_events
  drop constraint opportunity_outcome_events_event_type_check;

alter table public.opportunity_outcome_events
  add constraint opportunity_outcome_events_event_type_check
    check (event_type in ('won', 'lost', 'reopened'));

alter table public.opportunity_outcome_events
  drop constraint opportunity_outcome_events_type_fields_consistent;

alter table public.opportunity_outcome_events
  add constraint opportunity_outcome_events_type_fields_consistent check (
    (event_type = 'lost'
      and reopen_explanation is null
      and restores_event_id is null
      and (prior_request_status is not null) <> (prior_quote_status is not null))
    or
    (event_type = 'won'
      and reason is null
      and note is null
      and reopen_explanation is null
      and restores_event_id is null
      and prior_request_status is null)
    or
    (event_type = 'reopened'
      and reason is null
      and note is null
      and prior_request_status is null
      and prior_quote_status is null
      and restores_event_id is not null)
  );

comment on column public.opportunity_outcome_events.prior_quote_status is
  'The quotes.status value the moment before a won/lost event fired, for a quote-backed opportunity. '
  'Audit only -- unlike prior_request_status, nothing restores a Quote to this value, because the Quote''s '
  'own command (Revise, Restore) already drives its own status independently of Pipeline.';

comment on column public.opportunity_outcome_events.reopen_explanation is
  'Required by public.pipeline_reopen_opportunity for a Request-backed reopen. Null for a Quote-backed '
  'reopen: that one fires automatically off quotes.status, with no separate Pipeline-side explanation step '
  '(Jafar, 2026-08-23 -- the existing quote.revised activity entry is the record).';

grant select (prior_quote_status) on public.opportunity_outcome_events to authenticated;

-- 3. Automatic Won/Lost/Reopen for Quotes ------------------------------------------------------------------

create or replace function private.opportunity_resync_from_quote()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  opportunity_row public.opportunities;
  inserted_event public.opportunity_outcome_events;
begin
  -- organization_id in the predicate matters: opportunities_quote_unique is (organization_id, quote_id),
  -- and a lookup on quote_id alone cannot use that composite index as an equality condition -- it would
  -- seq-scan the whole tenant table on every single Quote status write otherwise.
  select * into opportunity_row
  from public.opportunities
  where organization_id = new.organization_id and quote_id = new.id
  for update;

  -- Unreachable in steady state -- every Quote gets its Opportunity inline at creation -- but a trigger
  -- must never assume the row it wants is there.
  if opportunity_row.id is null then
    return null;
  end if;

  if new.status = 'approved' and opportunity_row.outcome = 'open' then
    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      prior_quote_status, idempotency_key
    ) values (
      opportunity_row.organization_id, opportunity_row.id, 'won', now(), (select auth.uid()),
      old.status, gen_random_uuid()::text
    ) returning * into inserted_event;

    update public.opportunities
    set outcome = 'won', outcome_at = inserted_event.occurred_at,
        current_outcome_event_id = inserted_event.id, updated_at = now()
    where id = opportunity_row.id;

  elsif new.status in ('declined', 'archived') and opportunity_row.outcome = 'open' then
    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      prior_quote_status, idempotency_key
    ) values (
      opportunity_row.organization_id, opportunity_row.id, 'lost', now(), (select auth.uid()),
      old.status, gen_random_uuid()::text
    ) returning * into inserted_event;

    update public.opportunities
    set outcome = 'lost', outcome_at = inserted_event.occurred_at,
        current_outcome_event_id = inserted_event.id, updated_at = now()
    where id = opportunity_row.id;

  elsif new.status in ('draft', 'awaiting_response', 'changes_requested')
        and opportunity_row.outcome <> 'open' then
    insert into public.opportunity_outcome_events (
      organization_id, opportunity_id, event_type, occurred_at, actor_user_id,
      restores_event_id, idempotency_key
    ) values (
      opportunity_row.organization_id, opportunity_row.id, 'reopened', now(), (select auth.uid()),
      opportunity_row.current_outcome_event_id, gen_random_uuid()::text
    ) returning * into inserted_event;

    update public.opportunities
    set outcome = 'open', outcome_at = null, current_outcome_event_id = null, updated_at = now()
    where id = opportunity_row.id;

  else
    -- Every other transition (a fresh send, changes_requested -> draft with no prior decision, restoring
    -- straight back to an already-won or already-lost status) has nothing to do to outcome, but the stage
    -- still needs to catch up with the new quotes.status.
    update public.opportunities set updated_at = now() where id = opportunity_row.id;
  end if;

  return null;
end;
$$;

create trigger quotes_resync_opportunity_outcome
after update of status on public.quotes
for each row
when (old.status is distinct from new.status)
execute function private.opportunity_resync_from_quote();

revoke all on function private.opportunity_resync_from_quote() from public;

-- 4. Backfill ---------------------------------------------------------------------------------------------

-- Every existing quote-backed Opportunity was parked at 'request_closed' by the pre-5A branch. Touching
-- the row re-runs the (now corrected) before-update trigger and gives it its real stage.
update public.opportunities set updated_at = now() where quote_id is not null;

-- Outcome for quotes already decided before this migration existed. No synthetic event row: there was no
-- Pipeline to log one against at the time, exactly like Part 1's own backfill left stage_entered_at as the
-- best honest age rather than inventing history.
update public.opportunities as opportunity
set outcome = 'won',
    outcome_at = coalesce(quote.decided_at, quote.updated_at),
    updated_at = now()
from public.quotes as quote
where opportunity.organization_id = quote.organization_id
  and opportunity.quote_id = quote.id
  and quote.status in ('approved', 'converted')
  and opportunity.outcome = 'open';

update public.opportunities as opportunity
set outcome = 'lost',
    outcome_at = coalesce(quote.decided_at, quote.updated_at),
    updated_at = now()
from public.quotes as quote
where opportunity.organization_id = quote.organization_id
  and opportunity.quote_id = quote.id
  and quote.status = 'declined'
  and opportunity.outcome = 'open';

update public.opportunities as opportunity
set outcome = 'won',
    outcome_at = coalesce(quote.archived_at, quote.updated_at),
    updated_at = now()
from public.quotes as quote
where opportunity.organization_id = quote.organization_id
  and opportunity.quote_id = quote.id
  and quote.status = 'archived'
  and quote.previous_status = 'approved'
  and opportunity.outcome = 'open';

update public.opportunities as opportunity
set outcome = 'lost',
    outcome_at = coalesce(quote.archived_at, quote.updated_at),
    updated_at = now()
from public.quotes as quote
where opportunity.organization_id = quote.organization_id
  and opportunity.quote_id = quote.id
  and quote.status = 'archived'
  and quote.previous_status is distinct from 'approved'
  and opportunity.outcome = 'open';
