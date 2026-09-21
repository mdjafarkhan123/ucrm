-- CRM launch readiness, financial reconciliation Part 2: sales outcomes reader.
--
-- One row per Opportunity that closed Won or Lost inside the report range, so an accountant can trace a
-- Pipeline result back to the Request or Quote that produced it. Pipeline value and Won outcomes are sales
-- estimates, never financial revenue: nothing here is billed sales or cash received, and the value column is
-- the Opportunity's estimated value exactly as the board and the Sales Outcomes screen show it.
--
-- Truth is the outcome engine's current state (opportunities.outcome, outcome_at), the same rule
-- public.pipeline_outcome_page follows: a reopened Opportunity leaves current results the instant Reopen
-- commits, while its Lost and Reopened events stay in opportunity_outcome_events untouched. The current
-- Lost event supplies the reason; an Opportunity decided before the outcome engine existed has no event and
-- reports no reason rather than an invented one.
--
-- A row belongs to the range its outcome instant falls in, resolved in the organization's timezone, exactly
-- as the Job profitability reader dates a closure. Estimated values are stored as numeric(12, 2) major units
-- and reported here in integer minor units like every other financial figure.
--
-- Reads need pipeline.view. Values need pipeline.view_value: without it the value columns are null, never
-- zero. Every read is explicitly organization scoped.

-- 1. The paged ledger ------------------------------------------------------------------------------------

-- Keyset on (outcome_at, id): outcome_at is set once per decision and id is unique, so the pair is a
-- complete marker. Both outcomes share one dated ledger; opportunities_outcome_idx (organization_id,
-- outcome, outcome_at, id) answers each outcome's range with one index scan.
create or replace function public.financial_sales_outcomes_page(
  target_organization_id uuid,
  report_from date,
  report_to date,
  cursor_outcome_at timestamptz default null,
  cursor_opportunity_id uuid default null,
  page_limit integer default 100,
  sort_direction text default 'asc'
)
returns table (
  opportunity_id uuid,
  outcome text,
  outcome_at timestamptz,
  outcome_on date,
  created_on date,
  source_kind text,
  request_id uuid,
  quote_id uuid,
  quote_number integer,
  title text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  currency_code text,
  estimated_value_minor bigint,
  lost_reason text,
  outcome_event_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_view_value boolean;
  zone text;
  organization_currency text;
  window_start timestamptz;
  window_end timestamptz;
  resolved_limit integer;
begin
  if not private.member_has_permission(target_organization_id, caller, 'pipeline.view') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a report order.' using errcode = 'invalid_parameter_value';
  end if;
  if (cursor_outcome_at is null) <> (cursor_opportunity_id is null) then
    raise exception 'That page marker is incomplete.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_value := private.member_has_permission(target_organization_id, caller, 'pipeline.view_value');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC'), settings.currency_code
  into zone, organization_currency
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;
  resolved_limit := least(greatest(coalesce(page_limit, 100), 1), 501);

  return query
  select opportunity.id,
    opportunity.outcome,
    opportunity.outcome_at,
    (opportunity.outcome_at at time zone zone)::date,
    (opportunity.created_at at time zone zone)::date,
    case when opportunity.quote_id is not null then 'quote' else 'request' end,
    opportunity.request_id,
    opportunity.quote_id,
    quote.quote_number,
    opportunity.title,
    opportunity.client_id,
    client.display_name,
    client.company_name,
    coalesce(quote.currency_code, organization_currency),
    case when can_view_value then round(opportunity.estimated_value * 100)::bigint end,
    outcome_event.reason,
    opportunity.current_outcome_event_id
  from public.opportunities as opportunity
  left join public.quotes as quote
    on quote.organization_id = opportunity.organization_id and quote.id = opportunity.quote_id
  left join public.clients as client
    on client.organization_id = opportunity.organization_id and client.id = opportunity.client_id
  left join public.opportunity_outcome_events as outcome_event
    on outcome_event.organization_id = opportunity.organization_id
   and outcome_event.id = opportunity.current_outcome_event_id
   and outcome_event.event_type = 'lost'
  where opportunity.organization_id = target_organization_id
    and opportunity.outcome in ('won', 'lost')
    and opportunity.outcome_at >= window_start and opportunity.outcome_at < window_end
    and (
      cursor_outcome_at is null
      or (sort_direction = 'asc'
        and (opportunity.outcome_at, opportunity.id) > (cursor_outcome_at, cursor_opportunity_id))
      or (sort_direction = 'desc'
        and (opportunity.outcome_at, opportunity.id) < (cursor_outcome_at, cursor_opportunity_id))
    )
  order by
    case when sort_direction = 'asc' then opportunity.outcome_at end asc,
    case when sort_direction = 'asc' then opportunity.id end asc,
    case when sort_direction = 'desc' then opportunity.outcome_at end desc,
    case when sort_direction = 'desc' then opportunity.id end desc
  limit resolved_limit;
end;
$$;

-- 2. The whole-range totals ------------------------------------------------------------------------------

-- Opportunities with no estimate are counted separately so a hidden or missing value is disclosed rather
-- than read as a zero-value deal.
create or replace function public.financial_sales_outcomes_summary(
  target_organization_id uuid,
  report_from date,
  report_to date
)
returns table (
  won_count bigint,
  lost_count bigint,
  won_unvalued_count bigint,
  lost_unvalued_count bigint,
  won_value_minor bigint,
  lost_value_minor bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  caller uuid := (select auth.uid());
  can_view_value boolean;
  zone text;
  window_start timestamptz;
  window_end timestamptz;
begin
  if not private.member_has_permission(target_organization_id, caller, 'pipeline.view') then
    raise exception 'You do not have access to this financial report.'
      using errcode = 'insufficient_privilege';
  end if;
  if report_from is null or report_to is null or report_from >= report_to then
    raise exception 'Choose a valid report date range.' using errcode = 'invalid_parameter_value';
  end if;

  can_view_value := private.member_has_permission(target_organization_id, caller, 'pipeline.view_value');

  select coalesce(nullif(btrim(settings.timezone), ''), 'UTC') into zone
  from public.organization_settings as settings
  where settings.organization_id = target_organization_id;
  zone := coalesce(zone, 'UTC');
  window_start := report_from::timestamp at time zone zone;
  window_end := report_to::timestamp at time zone zone;

  return query
  select count(*) filter (where opportunity.outcome = 'won'),
    count(*) filter (where opportunity.outcome = 'lost'),
    count(*) filter (where opportunity.outcome = 'won' and opportunity.estimated_value is null),
    count(*) filter (where opportunity.outcome = 'lost' and opportunity.estimated_value is null),
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome = 'won'), 0)::bigint
    end,
    case when can_view_value
      then coalesce(sum(round(opportunity.estimated_value * 100)) filter (where opportunity.outcome = 'lost'), 0)::bigint
    end
  from public.opportunities as opportunity
  where opportunity.organization_id = target_organization_id
    and opportunity.outcome in ('won', 'lost')
    and opportunity.outcome_at >= window_start and opportunity.outcome_at < window_end;
end;
$$;

comment on function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text) is
  'Keyset-paged sales outcomes ledger for a report range: every Opportunity currently Won or Lost with its '
  'outcome instant inside the range, traceable to its Request or Quote. Values are sales estimates, never '
  'revenue. Requires pipeline.view; estimated_value_minor is null without pipeline.view_value. Every row is '
  'explicitly organization scoped.';
comment on function public.financial_sales_outcomes_summary(uuid, date, date) is
  'Whole-range Won/Lost counts, unvalued counts and estimated value totals over the same Opportunity set as '
  'financial_sales_outcomes_page.';

revoke all on function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text)
  from public, anon;
grant execute on function public.financial_sales_outcomes_page(uuid, date, date, timestamptz, uuid, integer, text)
  to authenticated;
revoke all on function public.financial_sales_outcomes_summary(uuid, date, date) from public, anon;
grant execute on function public.financial_sales_outcomes_summary(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
