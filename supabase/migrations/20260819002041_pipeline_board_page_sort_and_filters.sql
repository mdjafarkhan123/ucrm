-- Sales Pipeline, Part 2, item 3: the board column learns to sort and to filter.
--
-- One read model, extended. There is no second function for "the sorted board": a card reaches the
-- browser through pipeline_board_page or not at all, so every rule it re-applies by hand (tenant,
-- pipeline access, client visibility, owner name, money) keeps applying whatever the board is asked for.
--
-- Three things had to be true at once:
--
--   the order is one the caller picked   time in stage, created date, or estimated value, either way up
--   the page is still keyset             no offset anywhere, at any depth, under any filter
--   money is still not readable          sorting by value is refused outright without the permission,
--                                        because an order is an answer about amounts even when the
--                                        amounts themselves are withheld
--
-- Missing values are always last, and they are paged as their own phase rather than sorted with NULLS
-- LAST, because a null cannot be put in a cursor. The caller pages the estimated cards first and the
-- unestimated ones after, and says which phase it is in. A page may cross the boundary: when the
-- estimated side runs out mid-page, the rest of the page is filled from the unestimated side.
--
-- The statement is assembled rather than written six times over. A CASE in ORDER BY would have cost the
-- index scan, and an "or the filter is null" clause would have cost it too, so each request gets exactly
-- the clauses it needs and nothing else. Every value is inlined with %L, which is quoting, not trust:
-- sort_key, sort_direction and owner_filter are checked against fixed lists before they are used at all.

-- 1. Indexes, all measured on 50,000 rows -----------------------------------------------------------
--
-- The cursor is written as a row comparison, (sort column, id) < (value, id), because that is the only
-- form Postgres turns into an index condition. Written the long way round — "less than, or equal and
-- then id" — it means the same thing but becomes a filter, and a deep page then reads and throws away
-- everything above it: measured at 5,024 discarded rows and 67 buffers on page 200, against 0 and 4 for
-- the row comparison. That is the whole point of keyset paging, so the row comparison is not optional.
--
-- A row comparison only works when the index runs the same way for both of its columns, which is why
-- ties now break on id in the same direction as the sort, and why the board index is rebuilt ascending
-- rather than left descending with an ascending id after it. Ascending reads forward for oldest first
-- and backward for newest first, so one index still serves both directions of one sort.

-- Rebuilt, not duplicated: this is the Part 1 board index in the shape the cursor can use. Descending
-- with an ascending id could not serve a row comparison, and cost an extra incremental sort per page.
drop index if exists public.opportunities_board_idx;
create index opportunities_board_idx
  on public.opportunities(organization_id, stage, stage_entered_at, id)
  where outcome = 'open' and stage <> 'request_closed';

create index opportunities_board_created_idx
  on public.opportunities(organization_id, stage, created_at, id)
  where outcome = 'open' and stage <> 'request_closed';

-- The estimated half of the value sort. Nulls sit at the far end of an ascending index and are excluded
-- by the phase's own "is not null", which Postgres reads as an index bound rather than a filter.
create index opportunities_board_value_idx
  on public.opportunities(organization_id, stage, estimated_value, id)
  where outcome = 'open' and stage <> 'request_closed';

-- The unestimated half, which on a real board is most of it. Without this the planner either scans the
-- value index and sorts every unestimated card in the column before applying the limit, or falls back to
-- the organization index and filters the other three stages out row by row. With it the phase is a plain
-- ordered read: 5 buffers, no sort node.
create index opportunities_board_unvalued_idx
  on public.opportunities(organization_id, stage, id)
  where outcome = 'open' and stage <> 'request_closed' and estimated_value is null;

-- The salesperson filter, on the sort the board opens with. Measured on one person's cards inside a
-- 12,500-card column: 12,266 buffers and 11 ms filtering the whole column, against 5 buffers and 0.9 ms
-- through this index. Only the default sort gets one — filtering while also re-sorting by created date
-- or value is the rarer combination, and three more indexes on a table every Request writes to is a
-- price the board has not been shown to need.
create index opportunities_board_owner_idx
  on public.opportunities(organization_id, stage, owner_user_id, stage_entered_at, id)
  where outcome = 'open' and stage <> 'request_closed';

-- 2. The read ---------------------------------------------------------------------------------------

-- The old signature goes rather than gaining an overload: two functions of the same name, one of them
-- unable to sort, is exactly the kind of thing a caller picks by accident.
drop function if exists public.pipeline_board_page(uuid, text, timestamptz, uuid, integer);

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
  next_follow_up_on date
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
    'new_request', 'assessment_unscheduled', 'assessment_scheduled', 'assessment_completed'
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
      opportunity.next_follow_up_on
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
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.properties as property
      on property.id = opportunity.property_id
     and property.organization_id = opportunity.organization_id
    left join public.requests as request
      on request.id = opportunity.request_id
     and request.organization_id = opportunity.organization_id
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
