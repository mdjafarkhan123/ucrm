-- Pipeline E1: a dated Task shows on its assignee's Schedule, and clicking it opens its card's Brief.
--
-- Two small pieces, both reads:
--
-- 1. The Schedule asks for every dated Task in a window of at most 42 days. Until now Tasks were only ever
--    read per Opportunity, so no index answered "this organization's Tasks between two days". This one
--    does, in the same (organization_id, date) shape the visit and event reads walk.
--
-- 2. A Task on the Schedule opens its card's Brief on the Pipeline, and the Brief needs the whole board card.
--    `pipeline_opportunity_card` returns that one card by asking `pipeline_board_page` itself, narrowed to
--    the instant the card was created, so the Brief opened from a link can never disagree with the board:
--    the same tenant, permission, client-visibility, and money rules, in one place. A card that is no longer
--    open on the board (won, lost, closed) comes back as no row.

create index if not exists tasks_schedule_idx
  on public.tasks using btree (organization_id, due_on)
  where due_on is not null;

create or replace function public.pipeline_opportunity_card(target_opportunity_id uuid)
returns table (
  id uuid,
  title text,
  stage text,
  stage_entered_at timestamptz,
  outcome text,
  created_at timestamptz,
  request_id uuid,
  request_status text,
  client_id uuid,
  client_display_name text,
  client_company_name text,
  property_id uuid,
  property_label text,
  property_address_line1 text,
  property_city text,
  property_state_region text,
  property_postal_code text,
  owner_user_id uuid,
  owner_full_name text,
  owner_avatar_url text,
  estimated_value numeric,
  expected_close_on date,
  next_task_due_on date,
  task_id uuid,
  task_title text,
  task_due_on date,
  quote_id uuid,
  quote_status text,
  assessment_starts_at timestamptz,
  assessment_ends_at timestamptz,
  custom_stage_id uuid,
  quote_delivery_failed_at timestamptz,
  quote_delivery_failed_email text,
  quote_delivery_failure text,
  progress_at timestamptz,
  client_lead_source text
)
language sql
stable
security invoker
set search_path to 'pg_catalog', 'public'
as $$
  -- Security invoker on purpose: the lookup below is the caller's own RLS-checked read, so an Opportunity
  -- the caller may not see is never found, and pipeline_board_page re-checks everything it returns.
  select card.*
  from public.opportunities as opportunity
  cross join lateral public.pipeline_board_page(
    target_organization_id => opportunity.organization_id,
    target_stage => 'all',
    page_limit => 51,
    sort_key => 'created_at',
    sort_direction => 'asc',
    created_from => opportunity.created_at,
    created_to => opportunity.created_at + interval '1 microsecond'
  ) as card
  where opportunity.id = target_opportunity_id
    and card.id = target_opportunity_id;
$$;

revoke all on function public.pipeline_opportunity_card(uuid) from public, anon;
grant execute on function public.pipeline_opportunity_card(uuid) to authenticated, service_role;
