-- Sales Pipeline, Part 5C-i: the board's read side learns about the Quotes group.
--
-- 5A already derives quote_draft/quote_awaiting_response/quote_changes_requested on the opportunities row,
-- and 5B's drag gate already accepts them as legal targets. The two board reads never caught up: both still
-- hard-refuse anything but the four Request stages, so a quote-backed opportunity exists but cannot be
-- fetched or counted. Client, property, title, and estimated_value already flow onto that row the same way
-- they do for a Request-backed one (public.create_quote / public.convert_request_to_quote insert them
-- directly), so the only new column either read needs is a pointer to the Quote itself -- quote_id and
-- quote_status, the same shape request_id/request_status already take.
--
-- opportunities_board_idx (organization_id, stage, stage_entered_at desc, id) already covers every stage,
-- not just the four Request ones, so no new index is needed for either function.
--
-- quotes is safe to join unconditionally: every role holding pipeline.view also holds quotes.view (owner,
-- admin, office, sales), so a member who can reach a quote-backed card at all can already see the quote it
-- points to. This mirrors how request.status is already exposed to "only a member reaches this line".

drop function if exists public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
);

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
)
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
  next_follow_up_on date,
  task_id uuid,
  task_title text,
  task_due_on date,
  quote_id uuid,
  quote_status text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  sorting_by_value boolean;
  phase integer;
  select_body text;
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

  if target_stage not in (
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed',
    'quote_draft', 'quote_awaiting_response', 'quote_changes_requested'
  ) then
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
  -- would silently skip and repeat cards, so it is refused instead.
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
      quote.status
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
    where opportunity.organization_id = %L
      and opportunity.stage = %L
      and opportunity.outcome = 'open'
  $body$, caller_sees_money, caller_sees_clients, target_organization_id, target_stage);

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
    -- filter over everything above it.
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
$function$;

revoke all on function public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
) from public;
revoke execute on function public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
) from anon;
grant execute on function public.pipeline_board_page(
  uuid, text, integer, text, text, text, uuid, timestamptz, timestamptz, text, integer, timestamptz,
  numeric, uuid
) to authenticated;

-- pipeline_stage_counts: same widening, for the headings above both groups. Its own cross-tenant/predicate
-- match with opportunities_board_idx is unaffected -- only the fixed list of stages it left-joins against
-- grows, so a quote-backed stage stops being silently absent from the counted totals.

drop function if exists public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz);

create function public.pipeline_stage_counts(
  target_organization_id uuid,
  owner_filter text default 'all',
  filter_owner_user_id uuid default null,
  created_from timestamptz default null,
  created_to timestamptz default null
)
returns table (stage_key text, open_count bigint, value_total numeric)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
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
      opportunity.stage as stage_key,
      count(*) as open_count,
      case when %L::boolean then sum(opportunity.estimated_value) end as value_total
    from public.opportunities as opportunity
    -- Matches the partial board indexes exactly: same tenant, same predicate.
    where opportunity.organization_id = %L
      and opportunity.outcome = 'open'
      and opportunity.stage <> 'request_closed'
  $body$, caller_sees_money, target_organization_id);

  -- Every protected stage is listed, so a column that filtered down to nothing still reports zero and
  -- keeps its heading, instead of going missing from the board.
  return query execute $head$
    select
      board_stage.stage_key,
      coalesce(counted.open_count, 0)::bigint,
      counted.value_total
    from unnest(array[
      'new_request',
      'assessment_unscheduled',
      'assessment_scheduled',
      'assessment_completed',
      'quote_draft',
      'quote_awaiting_response',
      'quote_changes_requested'
    ]) as board_stage(stage_key)
    left join (
  $head$ || counted || filters || $tail$
      group by opportunity.stage
    ) as counted on counted.stage_key = board_stage.stage_key
  $tail$;
end;
$function$;

revoke all on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz)
  from public;
revoke execute on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz)
  from anon;
grant execute on function public.pipeline_stage_counts(uuid, text, uuid, timestamptz, timestamptz)
  to authenticated;
