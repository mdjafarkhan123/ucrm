-- Sales Pipeline, Part 1: one grouped count for the whole board.
-- The board header needs a number on every column. Counting each column separately would mean one
-- query per column on every board load, so this returns all four in a single pass over the partial
-- board index. Security invoker on purpose: the caller's own RLS decides which rows are counted, so
-- a member without pipeline.view counts nothing rather than seeing a leaked total.
create or replace function public.pipeline_stage_counts(target_organization_id uuid)
returns table (stage_key text, open_count bigint)
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  -- Every protected stage is listed, so an empty column still reports zero instead of going missing.
  select
    board_stage.stage_key,
    coalesce(counted.open_count, 0) as open_count
  from unnest(array[
    'new_request',
    'assessment_unscheduled',
    'assessment_scheduled',
    'assessment_completed'
  ]) as board_stage(stage_key)
  left join (
    select
      opportunity.stage as stage_key,
      count(*) as open_count
    from public.opportunities as opportunity
    -- Matches opportunities_board_idx exactly: same tenant, same partial predicate.
    where opportunity.organization_id = target_organization_id
      and opportunity.outcome = 'open'
      and opportunity.stage <> 'request_closed'
    group by opportunity.stage
  ) as counted on counted.stage_key = board_stage.stage_key;
$$;

revoke all on function public.pipeline_stage_counts(uuid) from public;
grant execute on function public.pipeline_stage_counts(uuid) to authenticated;
