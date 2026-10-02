-- Pipeline stage F1: the Sales Outcomes report's headline numbers.
--
-- One answer for a chosen outcome-date window: how many were Won, Lost, and booked as Direct jobs (counted
-- apart, never inside Won), how many of each have no value ("Unvalued", never a fake zero), why Lost deals
-- were lost, and how many days Won deals took from creation to win (median and average).
--
-- Reads only `opportunities` and the current Lost event, bounded by organization and outcome date, so it
-- rides the existing `opportunities_outcome_idx`. Money is returned only to callers with
-- pipeline.view_value; the same permission gate as `pipeline_outcome_tiles`.

create or replace function public.pipeline_outcomes_report(
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
  totals record;
  reasons jsonb;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  select
    count(*) filter (where o.outcome_kind = 'won') as won_count,
    count(*) filter (where o.outcome_kind = 'won' and o.estimated_value is null) as won_unvalued,
    sum(o.estimated_value) filter (where o.outcome_kind = 'won') as won_value,
    count(*) filter (where o.outcome_kind = 'lost') as lost_count,
    count(*) filter (where o.outcome_kind = 'lost' and o.estimated_value is null) as lost_unvalued,
    sum(o.estimated_value) filter (where o.outcome_kind = 'lost') as lost_value,
    count(*) filter (where o.outcome_kind = 'direct_job') as direct_count,
    count(*) filter (where o.outcome_kind = 'direct_job' and o.estimated_value is null) as direct_unvalued,
    sum(o.estimated_value) filter (where o.outcome_kind = 'direct_job') as direct_value,
    percentile_cont(0.5) within group (
      order by extract(epoch from (o.outcome_at - o.created_at)) / 86400.0
    ) filter (where o.outcome_kind = 'won') as median_days,
    avg(extract(epoch from (o.outcome_at - o.created_at)) / 86400.0)
      filter (where o.outcome_kind = 'won') as average_days
  into totals
  from public.opportunities as o
  where o.organization_id = target_organization_id
    and o.outcome_kind in ('won', 'lost', 'direct_job')
    and (report_from is null or o.outcome_at >= report_from)
    and (report_to is null or o.outcome_at < report_to);

  -- Why Lost deals were lost. A customer's own decline is its own bucket (the Lost list shows it the same
  -- way); otherwise the staff reason on the current Lost event, with "no reason" kept as a bucket of its
  -- own so the breakdown always adds up to the Lost count.
  select coalesce(jsonb_agg(jsonb_build_object('reason', bucket.reason, 'count', bucket.reason_count)
    order by bucket.reason_count desc, bucket.reason nulls last), '[]'::jsonb)
  into reasons
  from (
    select
      case
        when quote.decision is not distinct from 'declined' then 'customer_declined'
        else lost_event.reason
      end as reason,
      count(*) as reason_count
    from public.opportunities as o
    left join public.quotes as quote
      on quote.id = o.quote_id and quote.organization_id = o.organization_id
    left join public.opportunity_outcome_events as lost_event
      on lost_event.id = o.current_outcome_event_id
     and lost_event.organization_id = o.organization_id
     and lost_event.event_type = 'lost'
    where o.organization_id = target_organization_id
      and o.outcome_kind = 'lost'
      and (report_from is null or o.outcome_at >= report_from)
      and (report_to is null or o.outcome_at < report_to)
    group by 1
  ) as bucket;

  return jsonb_build_object(
    'won', jsonb_build_object(
      'count', totals.won_count,
      'unvalued_count', totals.won_unvalued
    ) || case when caller_sees_money then jsonb_build_object('value_total', totals.won_value) else '{}'::jsonb end,
    'lost', jsonb_build_object(
      'count', totals.lost_count,
      'unvalued_count', totals.lost_unvalued
    ) || case when caller_sees_money then jsonb_build_object('value_total', totals.lost_value) else '{}'::jsonb end,
    'direct_job', jsonb_build_object(
      'count', totals.direct_count,
      'unvalued_count', totals.direct_unvalued
    ) || case when caller_sees_money then jsonb_build_object('value_total', totals.direct_value) else '{}'::jsonb end,
    'days_to_win', jsonb_build_object(
      'count', totals.won_count,
      'median', round(totals.median_days::numeric, 1),
      'average', round(totals.average_days::numeric, 1)
    ),
    'lost_reasons', reasons
  );
end;
$$;

comment on function public.pipeline_outcomes_report(uuid, timestamptz, timestamptz) is
  'Sales Outcomes headline numbers for an outcome-date window: Won, Lost and Direct job counts kept apart, unvalued counts, value totals (pipeline.view_value only), the Lost-reason breakdown (customer declines and "no reason" are their own buckets, so it sums to the Lost count), and median/average days from creation to win over Won deals only. Null days when nothing was won. Requires pipeline.view.';

revoke all on function public.pipeline_outcomes_report(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.pipeline_outcomes_report(uuid, timestamptz, timestamptz) to authenticated, service_role;
