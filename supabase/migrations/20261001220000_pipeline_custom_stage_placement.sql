-- Pipeline upgrade A2: a card can sit in a custom follow-up stage.
--
-- Product truth: docs/sales-pipeline-behavior-contract.md, "Revision 3 adds section-bound custom follow-up
-- stages". Design: docs/adr/0004-pipeline-custom-stages-anchor-to-protected-stages.md. Industry reference:
-- Jobber's Sales Pipeline — a card is moved by hand among custom stages of its own section, and a real
-- Request, Assessment, or Quote action always takes it to the built-in stage that action establishes.
--
-- 1. opportunities.custom_stage_id is the placement. It sits beside `stage`, never in place of it: `stage`
--    stays the projection of Request and Quote truth. `board_column` is the one value the board reads —
--    the custom stage when there is one, the real stage otherwise.
-- 2. The six board indexes are rebuilt on `board_column`, so a custom column pages, sorts, filters, and
--    counts through exactly the access paths a protected column already had. No index is added for them.
-- 3. The stage trigger clears the placement whenever the real stage changes; history records every move.
-- 4. pipeline_place_opportunity is the only way a placement is written.
-- 5. The board's page and count readers answer for custom columns.

-- 1. The placement -------------------------------------------------------------------------------------------

alter table public.opportunities
  add column custom_stage_id uuid,
  add constraint opportunities_custom_stage_fk
    foreign key (organization_id, custom_stage_id)
    references public.pipeline_custom_stages (organization_id, id),
  -- A card that has left the board holds no place on it.
  add constraint opportunities_custom_stage_on_board_check
    check (custom_stage_id is null or stage <> 'request_closed');

alter table public.opportunities
  add column board_column text generated always as (coalesce(custom_stage_id::text, stage)) stored;

comment on column public.opportunities.custom_stage_id is
  'The custom follow-up stage this card was placed in by hand, or null when it sits in its real stage. Written only by public.pipeline_place_opportunity and cleared by private.opportunity_apply_stage whenever the real stage changes.';
comment on column public.opportunities.board_column is
  'The column the board draws this card in: the custom stage id as text when placed in one, the real stage otherwise. Every board read and board index keys on this.';
comment on column public.opportunities.stage_entered_at is
  'When the card arrived in the column it is drawn in — its real stage, or the custom stage it was placed in.';

grant select (custom_stage_id) on table public.opportunities to authenticated;

-- The reference above is checked from this side whenever a stage row is removed, and switching a stage off
-- (part A3) asks for every card still in it. Only placed cards are in it, so it stays small.
create index opportunities_custom_stage_idx
  on public.opportunities (organization_id, custom_stage_id)
  where custom_stage_id is not null;

-- 2. Board indexes, re-keyed from `stage` to `board_column` ------------------------------------------------

drop index public.opportunities_board_idx;
drop index public.opportunities_board_created_idx;
drop index public.opportunities_board_owner_idx;
drop index public.opportunities_board_value_idx;
drop index public.opportunities_board_unvalued_idx;
drop index public.opportunities_board_assessment_group_idx;

create index opportunities_board_idx
  on public.opportunities (organization_id, board_column, stage_entered_at, id)
  where outcome = 'open' and board_column <> 'request_closed';

create index opportunities_board_created_idx
  on public.opportunities (organization_id, board_column, created_at, id)
  where outcome = 'open' and board_column <> 'request_closed';

create index opportunities_board_owner_idx
  on public.opportunities (organization_id, board_column, owner_user_id, stage_entered_at, id)
  where outcome = 'open' and board_column <> 'request_closed';

create index opportunities_board_value_idx
  on public.opportunities (organization_id, board_column, estimated_value, id)
  where outcome = 'open' and board_column <> 'request_closed';

create index opportunities_board_unvalued_idx
  on public.opportunities (organization_id, board_column, id)
  where outcome = 'open' and board_column <> 'request_closed' and estimated_value is null;

create index opportunities_board_assessment_group_idx
  on public.opportunities (organization_id, stage_entered_at, id)
  where outcome = 'open'
    and board_column in ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed');

comment on index public.opportunities_board_assessment_group_idx is
  'The collapsed Assessment column reads all three assessment stages as one keyset-ordered range. The stage set is the predicate rather than the leading key, so no Sort node is needed. Keyed on board_column, so a card placed in a custom stage is not in it.';

-- 3. Real actions win, and every move is history ----------------------------------------------------------

alter table public.opportunity_stage_events
  add column from_custom_stage_id uuid,
  add column to_custom_stage_id uuid,
  add constraint opportunity_stage_events_from_custom_stage_fk
    foreign key (organization_id, from_custom_stage_id)
    references public.pipeline_custom_stages (organization_id, id),
  add constraint opportunity_stage_events_to_custom_stage_fk
    foreign key (organization_id, to_custom_stage_id)
    references public.pipeline_custom_stages (organization_id, id);

comment on column public.opportunity_stage_events.to_custom_stage_id is
  'The custom stage the card was placed in by this move, or null when it landed in the real stage named by to_stage. A switched-off stage keeps its row, so the name of the time can always be read.';

create index opportunity_stage_events_from_custom_stage_idx
  on public.opportunity_stage_events (organization_id, from_custom_stage_id)
  where from_custom_stage_id is not null;
create index opportunity_stage_events_to_custom_stage_idx
  on public.opportunity_stage_events (organization_id, to_custom_stage_id)
  where to_custom_stage_id is not null;

create or replace function private.opportunity_apply_stage() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
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

  -- `stage_entered_at` is when the card arrived in the column it is drawn in, so it restarts on a real
  -- stage change and on a move into, out of, or between custom stages.
  if tg_op = 'INSERT' then
    new.stage_entered_at := coalesce(new.stage_entered_at, now());
  elsif new.stage is distinct from old.stage then
    -- A real Request, Assessment, or Quote action always wins over where somebody placed the card: it
    -- goes to the protected stage that action established.
    new.custom_stage_id := null;
    new.stage_entered_at := now();
  elsif new.custom_stage_id is distinct from old.custom_stage_id then
    new.stage_entered_at := now();
  else
    new.stage_entered_at := old.stage_entered_at;
  end if;

  return new;
end;
$$;

create or replace function private.opportunity_record_stage_event() returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
begin
  insert into public.opportunity_stage_events (
    organization_id, opportunity_id, from_stage, to_stage,
    from_custom_stage_id, to_custom_stage_id, actor_user_id, occurred_at
  )
  values (
    new.organization_id,
    new.id,
    case when tg_op = 'INSERT' then null else old.stage end,
    new.stage,
    case when tg_op = 'INSERT' then null else old.custom_stage_id end,
    new.custom_stage_id,
    (select auth.uid()),
    new.stage_entered_at
  );
  return null;
end;
$$;

drop trigger opportunities_record_stage_change on public.opportunities;
create trigger opportunities_record_stage_change
  after update on public.opportunities
  for each row
  when (
    old.stage is distinct from new.stage
    or old.custom_stage_id is distinct from new.custom_stage_id
  )
  execute function private.opportunity_record_stage_event();

-- 4. Placing a card ----------------------------------------------------------------------------------------

-- `target_custom_stage_id` null puts the card back in its real stage. Asking for where the card already is
-- changes nothing and writes no history, so a retried request cannot record the same move twice.
create function public.pipeline_place_opportunity(
  target_opportunity_id uuid,
  target_custom_stage_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  opportunity_row public.opportunities;
  stage_row public.pipeline_custom_stages;
  card_section text;
begin
  -- Locks the card, so a real action landing at the same moment is seen either wholly before or wholly
  -- after this move.
  opportunity_row := private.pipeline_lock_opportunity_for_drag(target_opportunity_id);

  if opportunity_row.outcome <> 'open' or opportunity_row.stage = 'request_closed' then
    raise exception 'This card is no longer on the board.' using errcode = 'check_violation';
  end if;

  if target_custom_stage_id is not null then
    -- Shared lock: switching the stage off waits for this move, and this move waits for that.
    select * into stage_row
    from public.pipeline_custom_stages as custom_stage
    where custom_stage.organization_id = opportunity_row.organization_id
      and custom_stage.id = target_custom_stage_id
      and custom_stage.disabled_at is null
    for share;

    if stage_row.id is null then
      raise exception 'That stage is no longer on the board. Refresh the page and try again.'
        using errcode = 'check_violation';
    end if;

    card_section := case
      when opportunity_row.stage in (
        'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
      ) then 'quote'
      else 'request'
    end;

    if stage_row.section <> card_section then
      if card_section = 'request' then
        raise exception
          'This is a request, so it can only go into a Requests stage. Convert it to a quote first.'
          using errcode = 'check_violation';
      end if;
      raise exception 'This is a quote, so it can only go into a Quotes stage.'
        using errcode = 'check_violation';
    end if;
  end if;

  if target_custom_stage_id is not distinct from opportunity_row.custom_stage_id then
    return jsonb_build_object(
      'applied', false,
      'stage', opportunity_row.stage,
      'custom_stage_id', opportunity_row.custom_stage_id
    );
  end if;

  update public.opportunities
  set custom_stage_id = target_custom_stage_id
  where id = opportunity_row.id;

  return jsonb_build_object(
    'applied', true,
    'stage', opportunity_row.stage,
    'custom_stage_id', target_custom_stage_id
  );
end;
$$;

revoke all on function public.pipeline_place_opportunity(uuid, uuid) from public, anon;
grant execute on function public.pipeline_place_opportunity(uuid, uuid) to authenticated, service_role;

-- 5. Board readers ------------------------------------------------------------------------------------------

drop function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid);

create function public.pipeline_board_page(
  target_organization_id uuid,
  target_stage text,
  page_limit integer default 25,
  sort_key text default 'stage_entered_at',
  sort_direction text default 'desc',
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null,
  cursor_sort_key text default null,
  cursor_phase integer default null,
  cursor_timestamp timestamptz default null,
  cursor_value numeric default null,
  cursor_id uuid default null
) returns table (
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
  next_follow_up_on date,
  task_id uuid,
  task_title text,
  task_due_on date,
  quote_id uuid,
  quote_status text,
  assessment_starts_at timestamptz,
  assessment_ends_at timestamptz,
  custom_stage_id uuid
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  sorting_by_value boolean;
  phase integer;
  select_body text;
  stage_predicate text;
  filters text := '';
  keyset text;
  ordering text;
  fetched integer;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  -- One named logical column, the seven real stages, or one of this organization's custom stages. Written
  -- out rather than assembled from a caller's list, so 'assessment' is the only grouping that exists and no
  -- other combination is reachable. Every one is a value of `board_column`, the column a card is drawn in:
  -- its custom stage when somebody placed it in one, its real stage otherwise. So a protected column never
  -- shows a card that is sitting in a custom stage, and all of them read through the same indexes.
  if target_stage = 'assessment' then
    -- Spelled exactly as opportunities_board_assessment_group_idx spells it: the planner matches the two
    -- expressions before attempting a harder proof, and a mismatch here silently costs the index.
    stage_predicate :=
      $p$ and opportunity.board_column in
        ('assessment_unscheduled', 'assessment_scheduled', 'assessment_completed')$p$;
  elsif target_stage in (
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed',
    'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
  ) then
    stage_predicate := format(' and opportunity.board_column = %L', target_stage);
  elsif target_stage ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and exists (
          select 1
          from public.pipeline_custom_stages as custom_stage
          where custom_stage.organization_id = target_organization_id
            and custom_stage.id = target_stage::uuid
            and custom_stage.disabled_at is null
        ) then
    -- Through uuid and back, so the text compared is the one spelling `board_column` holds.
    stage_predicate := format(' and opportunity.board_column = %L', target_stage::uuid::text);
  else
    raise exception 'That is not a board column.' using errcode = 'invalid_parameter_value';
  end if;

  if sort_key not in ('stage_entered_at', 'created_at', 'estimated_value')
     or sort_direction not in ('asc', 'desc')
     or owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to sort or filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat cards, so it is refused instead. The column a cursor belongs to is
  -- checked by the route, which is the only place that knows the logical-column vocabulary.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  -- One row over the asked-for page is how the caller detects there is more, so the cap is 50 plus one.
  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  -- Asked once for the whole page. can_view_client is still called per row underneath, but only for a
  -- caller who lacks the blanket permission, so the ordinary page pays nothing for it.
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  sorting_by_value := sort_key = 'estimated_value';

  -- Ordering by money is reading money. Withholding the amounts while handing over the ranking would
  -- give the column away one comparison at a time.
  if sorting_by_value and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.stage,
      opportunity.stage_entered_at,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.request_id,
      request.status,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      opportunity.property_id,
      case when client_visible.allowed then property.label end,
      case when client_visible.allowed then property.address_line1 end,
      case when client_visible.allowed then property.city end,
      case when client_visible.allowed then property.state_region end,
      case when client_visible.allowed then property.postal_code end,
      opportunity.owner_user_id,
      case when owner_is_teammate.yes then owner_profile.full_name end,
      case when owner_is_teammate.yes then owner_profile.avatar_url end,
      case when %L::boolean then opportunity.estimated_value end,
      opportunity.expected_close_on,
      opportunity.next_follow_up_on,
      open_task.id,
      open_task.title,
      open_task.due_on,
      opportunity.quote_id,
      quote.status,
      assessment.starts_at,
      assessment.ends_at,
      opportunity.custom_stage_id
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    cross join lateral (
      select exists (
        select 1
        from public.organization_members as owner_membership
        where owner_membership.organization_id = opportunity.organization_id
          and owner_membership.user_id = opportunity.owner_user_id
      ) as yes
    ) as owner_is_teammate
    left join lateral (
      select task.id, task.title, task.due_on
      from public.tasks as task
      where task.organization_id = opportunity.organization_id
        and task.opportunity_id = opportunity.id
        and task.status = 'open'
      order by task.due_on nulls last, task.created_at, task.id
      limit 1
    ) as open_task on true
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.properties as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join public.requests as request
      on request.id = opportunity.request_id
     and request.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.profiles as owner_profile
      on owner_profile.id = opportunity.owner_user_id
    left join public.assessments as assessment
      on assessment.request_id = opportunity.request_id
     and assessment.organization_id = opportunity.organization_id
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
  $body$, caller_sees_money, caller_sees_clients, target_organization_id) || stage_predicate;

  -- Only the clauses this request actually needs. "Or the filter is null" reads the same and costs the
  -- index scan.
  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants. The upper bound is exclusive: it is the first moment of the day after.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  if not sorting_by_value then
    -- Ties break the same way the sort runs, so the pair reads as one index range rather than as a
    -- filter over everything above it. This is also what keeps the grouped column's order globally
    -- correct: one keyset across all three assessment states, never three lists stitched together.
    if sort_direction = 'desc' then
      ordering := format(' order by opportunity.%1$I desc, opportunity.id desc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by opportunity.%1$I asc, opportunity.id asc', sort_key);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.%1$I, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)',
          sort_key, cursor_timestamp, cursor_id)
      end;
    end if;

    return query execute select_body || filters || keyset || ordering
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Value sorting, phase by phase. Phase 1 is the estimated cards in the caller's chosen direction;
  -- phase 2 is the unestimated ones, always oldest id first, which is the order they already sit in.
  phase := coalesce(cursor_phase, 1);
  if phase not in (1, 2) then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  if phase = 1 then
    if sort_direction = 'desc' then
      ordering := ' order by opportunity.estimated_value desc, opportunity.id desc';
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
      end;
    else
      ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
          cursor_value, cursor_id)
      end;
    end if;

    return query execute select_body || filters
      || ' and opportunity.estimated_value is not null' || keyset || ordering
      || format(' limit %s', resolved_limit);
    get diagnostics fetched = row_count;

    -- The estimated side is finished, so the rest of this page comes from the unestimated side, from its
    -- beginning. No unestimated card can have been returned before this point, so there is nothing to
    -- page past.
    if fetched < resolved_limit then
      return query execute select_body || filters
        || ' and opportunity.estimated_value is null'
        || ' order by opportunity.id asc'
        || format(' limit %s', resolved_limit - fetched);
    end if;
    return;
  end if;

  return query execute select_body || filters
    || ' and opportunity.estimated_value is null'
    || case when cursor_id is null then ''
            else format(' and opportunity.id > %L::uuid', cursor_id) end
    || ' order by opportunity.id asc'
    || format(' limit %s', resolved_limit);
end;
$_$;

revoke all on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid) from public, anon;
grant execute on function public.pipeline_board_page(uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz, numeric, uuid) to authenticated, service_role;

create or replace function public.pipeline_stage_counts(
  target_organization_id uuid,
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null
) returns table (stage_key text, open_count bigint, value_total numeric)
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $_$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  filters text := '';
  counted text;
begin
  -- The same rule the select policy applies: current member, active organization, pipeline.view.
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if owner_filter not in ('all', 'unassigned', 'member') then
    raise exception 'That is not a way to filter the board.'
      using errcode = 'invalid_parameter_value';
  end if;

  if owner_filter = 'member' and filter_owner_user_id is null then
    raise exception 'Filtering by salesperson needs a salesperson.'
      using errcode = 'invalid_parameter_value';
  end if;

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');

  if owner_filter = 'unassigned' then
    filters := filters || ' and opportunity.owner_user_id is null';
  elsif owner_filter = 'member' then
    filters := filters || format(' and opportunity.owner_user_id = %L', filter_owner_user_id);
  end if;

  -- Calendar boundaries are worked out in the organization's timezone before they get here, so this only
  -- ever sees two instants, and the upper one is the first moment of the day after. The same two the
  -- columns are paging with, so the heading and the cards cannot drift apart.
  if created_from is not null then
    filters := filters || format(' and opportunity.created_at >= %L', created_from);
  end if;
  if created_to is not null then
    filters := filters || format(' and opportunity.created_at < %L', created_to);
  end if;

  counted := format($body$
    select
      opportunity.board_column as stage_key,
      count(*) as open_count,
      case when %L::boolean then sum(opportunity.estimated_value) end as value_total
    from public.opportunities as opportunity
    -- Matches the partial board indexes exactly: same tenant, same predicate.
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
      and opportunity.board_column <> 'request_closed'
  $body$, caller_sees_money, target_organization_id);

  -- Every column is listed — the seven protected stages and each custom stage that is switched on, by its
  -- id — so one that filtered down to nothing still reports zero and keeps its heading, instead of going
  -- missing from the board. A card counts under the column it is drawn in, never under both.
  return query execute format($head$
    select
      board_stage.stage_key,
      coalesce(counted.open_count, 0)::bigint,
      counted.value_total
    from (
      select unnest(array[
        'new_request',
        'assessment_unscheduled',
        'assessment_scheduled',
        'assessment_completed',
        'quote_draft',
        'quote_awaiting_response',
        'quote_changes_requested'
      ])
      union all
      select custom_stage.id::text
      from public.pipeline_custom_stages as custom_stage
      where custom_stage.organization_id = %L
        and custom_stage.disabled_at is null
    ) as board_stage(stage_key)
    left join (
  $head$, target_organization_id) || counted || filters || $tail$
      group by opportunity.board_column
    ) as counted on counted.stage_key = board_stage.stage_key
  $tail$;
end;
$_$;

