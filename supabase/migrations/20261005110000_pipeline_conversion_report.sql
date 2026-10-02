-- Pipeline stage F2: the Sales Outcomes conversion report — funnel, lead source, and time in stage.
--
-- F1's numbers answer "what closed in this period". These answer "what became of the work that came in
-- during this period", so everything here is grouped by the day the work was CREATED (plan § Outcomes:
-- "Funnel reports group work by its created-date cohort and show still-Open work separately").
--
-- What is counted
--   A Request is one piece of work. Its Quote, if it has one, is a second card for the same work
--   (`quotes_request_lineage_idx`: at most one Quote per Request), so a Request's result is read across
--   both cards: Won if either was won, still open if either is still on the board, otherwise Lost if either
--   was lost, otherwise closed with no result (archived, or converted to a Quote that was abandoned).
--   A Quote made without a Request is its own piece of work. A Draft Quote archived before anybody saw it
--   ("Abandoned before sending") is not a result of any kind, and a Direct job never enters a rate.
--
-- The counts returned are raw; the three rates are divided in one place in the app (`$lib/pipeline/
-- conversion`), always over work that is no longer open, so open work is never counted as lost.
--
-- Shape, decided with the performance-review design branch on 2026-10-02: live queries bounded by one
-- organization, no read model, no cache. The dominant cost is time in stage, which reads every stage event
-- of the cards in the window and rides `opportunity_stage_events_opportunity_idx`.
--
-- Measured 2026-10-02 on the development database, one organization seeded with 12,000 cards and 60,000
-- stage events: a one-month window (about 370 cards) answered in 21 ms, and "All time" in 400-600 ms, all
-- through index scans. All time grows in a straight line with the organization's stage events, roughly
-- 7 ms per 1,000, so it stays inside the eight-second limit on a signed-in request up to about a million
-- events. A contractor past that needs this report kept as a maintained summary; nothing smaller is
-- justified before then.

-- 1. A stage event knows when it is an Undo ---------------------------------------------------------------
--
-- Carried from D1: an Undo leaves the mistaken move and its reverse in the history. Time in stage must
-- drop both, or the stage the card was dragged to by mistake would count a card that spent seconds there.
-- The Undo functions already announce themselves through `pipeline.undo_opportunity_id`; the event now
-- keeps that fact instead of leaving reports to guess it from timing.

alter table public.opportunity_stage_events
  add column is_undo boolean not null default false;

comment on column public.opportunity_stage_events.is_undo is
  'True when this event was written by an Undo (pipeline_undo_move, pipeline_undo_placement). Reports drop it together with the event just before it, the move it took back.';

-- Rows written before this column: an Undo is an exact reversal of the event just before it, by the same
-- person, inside the two minutes the Undo is offered for, of a move that recorded the clocks it replaced.
update public.opportunity_stage_events as event
set is_undo = true
from public.opportunity_stage_events as undone
where undone.organization_id = event.organization_id
  and undone.opportunity_id = event.opportunity_id
  and undone.occurred_at < event.occurred_at
  and undone.occurred_at >= event.occurred_at - interval '2 minutes'
  and undone.from_stage_entered_at is not null
  and undone.actor_user_id is not distinct from event.actor_user_id
  and undone.from_stage = event.to_stage
  and undone.to_stage = event.from_stage
  and (
    undone.from_stage <> undone.to_stage
    or (undone.from_custom_stage_id is not distinct from event.to_custom_stage_id
        and undone.to_custom_stage_id is not distinct from event.from_custom_stage_id)
  )
  and not exists (
    select 1
    from public.opportunity_stage_events as between_event
    where between_event.organization_id = event.organization_id
      and between_event.opportunity_id = event.opportunity_id
      and between_event.occurred_at > undone.occurred_at
      and between_event.occurred_at < event.occurred_at
  );

-- The 20261002210000 version with the one new column.
create or replace function private.opportunity_record_stage_event() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  undoing boolean := current_setting('pipeline.undo_opportunity_id', true) = new.id::text;
begin
  insert into public.opportunity_stage_events (
    organization_id, opportunity_id, from_stage, to_stage,
    from_custom_stage_id, to_custom_stage_id, actor_user_id, occurred_at,
    from_stage_entered_at, from_progress_at, is_undo
  )
  values (
    new.organization_id,
    new.id,
    case when tg_op = 'INSERT' then null else old.stage end,
    new.stage,
    case when tg_op = 'INSERT' then null else old.custom_stage_id end,
    new.custom_stage_id,
    (select auth.uid()),
    case when undoing then clock_timestamp() else new.stage_entered_at end,
    case when tg_op = 'INSERT' then null else old.stage_entered_at end,
    case when tg_op = 'INSERT' then null else old.progress_at end,
    coalesce(undoing, false)
  );
  return null;
end;
$$;

-- 2. The report ------------------------------------------------------------------------------------------

create function public.pipeline_conversion_report(
  target_organization_id uuid,
  report_from timestamptz default null,
  report_to timestamptz default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_every_client boolean;
  request_totals jsonb;
  quote_totals jsonb;
  sources jsonb;
  stages jsonb;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Lead source is the client's own detail. The board blanks it on a card whose client the member may not
  -- see; a breakdown cannot be blanked row by row, so it is given only to a member who sees every client.
  caller_sees_every_client :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  -- Each piece of work created in the window, with its result read across the Request and its Quote.
  with work as (
    select
      card.request_id is not null as is_request,
      card.client_id,
      -- "Quoted" means a Quote that was not abandoned before sending.
      quote_card.id is not null
        and not (quote_card.outcome = 'open' and quote_card.stage = 'request_closed') as quoted,
      case
        when card.outcome = 'won' or quote_card.outcome = 'won' then 'won'
        when card.stage <> 'request_closed'
          or (quote_card.outcome = 'open' and quote_card.stage <> 'request_closed') then 'open'
        when card.outcome = 'lost' or quote_card.outcome = 'lost' then 'lost'
        else 'closed'
      end as result,
      case
        when card.outcome = 'won' then card.estimated_value
        when quote_card.outcome = 'won' then quote_card.estimated_value
      end as won_value
    from public.opportunities as card
    left join public.quotes as quote
      on quote.organization_id = card.organization_id
     and quote.request_id = card.request_id
    left join public.opportunities as quote_card
      on quote_card.organization_id = quote.organization_id
     and quote_card.quote_id = quote.id
    where card.organization_id = target_organization_id
      and card.job_id is null
      and (
        card.request_id is not null
        -- A Quote with no Request behind it, unless it was abandoned before sending.
        or (card.quote_id is not null
            and not (card.outcome = 'open' and card.stage = 'request_closed')
            and not exists (
              select 1 from public.quotes as own_quote
              where own_quote.organization_id = card.organization_id
                and own_quote.id = card.quote_id
                and own_quote.request_id is not null
            ))
      )
      and (report_from is null or card.created_at >= report_from)
      and (report_to is null or card.created_at < report_to)
  ),
  by_source as (
    select
      mode() within group (order by btrim(client.lead_source)) as lead_source,
      count(*) as total,
      count(*) filter (where work.result = 'won') as won,
      count(*) filter (where work.result = 'lost') as lost,
      count(*) filter (where work.result = 'closed') as closed,
      count(*) filter (where work.result = 'open') as still_open,
      sum(work.won_value) as won_value
    from work
    join public.clients as client
      on client.organization_id = target_organization_id and client.id = work.client_id
    where caller_sees_every_client
    group by lower(btrim(coalesce(client.lead_source, '')))
  )
  select
    (
      select jsonb_build_object(
        'total', count(*),
        'quoted', count(*) filter (where work.quoted),
        'won', count(*) filter (where work.result = 'won'),
        'lost', count(*) filter (where work.result = 'lost'),
        'closed', count(*) filter (where work.result = 'closed'),
        'open', count(*) filter (where work.result = 'open'),
        'open_unquoted', count(*) filter (where work.result = 'open' and not work.quoted)
      )
      from work
      where work.is_request
    ),
    (
      -- Free text, so the list is capped; the busiest sources are the ones worth reading.
      select coalesce(jsonb_agg(
        jsonb_build_object(
          'lead_source', nullif(top.lead_source, ''),
          'total', top.total,
          'won', top.won,
          'lost', top.lost,
          'closed', top.closed,
          'open', top.still_open
        ) || case when caller_sees_money
               then jsonb_build_object('won_value', top.won_value) else '{}'::jsonb end
        order by top.total desc, top.lead_source), '[]'::jsonb)
      from (
        select * from by_source order by by_source.total desc, by_source.lead_source limit 50
      ) as top
    )
  into request_totals, sources;

  -- Per-Quote win rate: every Quote card created in the window, whether or not a Request came first.
  select jsonb_build_object(
    'total', count(*),
    'won', count(*) filter (where card.outcome = 'won'),
    'lost', count(*) filter (where card.outcome = 'lost'),
    'open', count(*) filter (where card.outcome = 'open' and card.stage <> 'request_closed'),
    'abandoned', count(*) filter (where card.outcome = 'open' and card.stage = 'request_closed')
  )
  into quote_totals
  from public.opportunities as card
  where card.organization_id = target_organization_id
    and card.quote_id is not null
    and (report_from is null or card.created_at >= report_from)
    and (report_to is null or card.created_at < report_to);

  -- Time in stage. Each stage event is an arrival in a column: a custom stage when it names one, the
  -- built-in stage otherwise (ADR 0004: a row with equal stages is a custom move). The stay ends at the
  -- card's next arrival, or runs to now when the card is still there. A card that comes back to a stage
  -- adds to its own time there, so each card counts once per stage (HubSpot's cumulative time in stage).
  with arrivals as (
    select
      event.opportunity_id,
      event.to_stage,
      event.to_custom_stage_id,
      event.occurred_at,
      event.is_undo,
      lead(event.is_undo) over card_history as taken_back
    from public.opportunity_stage_events as event
    join public.opportunities as card
      on card.organization_id = event.organization_id and card.id = event.opportunity_id
    where event.organization_id = target_organization_id
      and (report_from is null or card.created_at >= report_from)
      and (report_to is null or card.created_at < report_to)
    window card_history as (partition by event.opportunity_id order by event.occurred_at, event.id)
  ),
  stays as (
    select
      arrivals.opportunity_id,
      arrivals.to_stage,
      arrivals.to_custom_stage_id,
      arrivals.occurred_at,
      lead(arrivals.occurred_at) over (
        partition by arrivals.opportunity_id order by arrivals.occurred_at
      ) as left_at
    from arrivals
    -- An Undo and the move it took back never happened as far as a report is concerned.
    where not arrivals.is_undo and not coalesce(arrivals.taken_back, false)
  ),
  per_card as (
    select
      stays.to_stage,
      stays.to_custom_stage_id,
      sum(extract(epoch from (coalesce(stays.left_at, now()) - stays.occurred_at))) / 86400.0 as days,
      bool_or(stays.left_at is null) as still_there
    from stays
    where stays.to_stage <> 'request_closed'
    group by stays.opportunity_id, stays.to_stage, stays.to_custom_stage_id
  ),
  per_stage as (
    select
      case when per_card.to_custom_stage_id is null then per_card.to_stage end as stage,
      per_card.to_custom_stage_id as custom_stage_id,
      count(*) as cards,
      count(*) filter (where per_card.still_there) as still_there,
      percentile_cont(0.5) within group (order by per_card.days) as median_days,
      avg(per_card.days) as average_days
    from per_card
    group by 1, 2
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'stage', per_stage.stage,
      'custom_stage_id', per_stage.custom_stage_id,
      'name', custom.name,
      'section', custom.section,
      'after_stage', custom.after_stage,
      'position', custom.position,
      'disabled', custom.disabled_at is not null,
      'cards', per_stage.cards,
      'still_there', per_stage.still_there,
      'median_days', round(per_stage.median_days::numeric, 1),
      'average_days', round(per_stage.average_days::numeric, 1)
    )), '[]'::jsonb)
  into stages
  from per_stage
  left join public.pipeline_custom_stages as custom
    on custom.organization_id = target_organization_id and custom.id = per_stage.custom_stage_id;

  return jsonb_build_object(
    'requests', request_totals,
    'quotes', quote_totals,
    'sources', sources,
    'stages', stages,
    'can_view_sources', caller_sees_every_client,
    'can_view_value', caller_sees_money
  );
end;
$$;

comment on function public.pipeline_conversion_report(uuid, timestamptz, timestamptz) is
  'Sales Outcomes conversion numbers for work CREATED in the window. requests: each Request with its result read across its own card and its Quote card (won, open, lost, closed-with-no-result), and how many were quoted. quotes: every Quote card (won, lost, open, abandoned before sending). sources: the same work, plus Quotes that had no Request, by the client''s lead source (customers.view only; won_value for pipeline.view_value only). stages: per column, how many cards were in it and their median/average days there, re-entries summed, Undo pairs dropped. Raw counts only; rates are divided in the app. Direct jobs are never included. Requires pipeline.view.';

revoke all on function public.pipeline_conversion_report(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.pipeline_conversion_report(uuid, timestamptz, timestamptz) to authenticated, service_role;
